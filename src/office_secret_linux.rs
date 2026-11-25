//! Linux counterpart of the Windows DPAPI store used for Office secrets.
//!
//! A random per-user key is kept in the desktop keyring (Freedesktop Secret
//! Service through libsecret, as Office Call Popup on Ubuntu does). Values in the
//! local config are sealed with that key as `secret:v1:<base64 nonce+box>`.
//! There is no plaintext fallback: without an unlocked keyring nothing is stored
//! or read. The Office Call Popup launch ticket is read from the same keyring.
use hbb_common::{
    anyhow::{anyhow, bail, Result},
    log,
    sodiumoxide::{base64, crypto::secretbox},
};
use libloading::Library;
use std::{
    ffi::{c_char, c_int, c_uint, c_void, CStr, CString},
    ptr,
    sync::{Mutex, OnceLock},
};

pub const PREFIX: &str = "secret:v1:";
const MAX_STORED: usize = 32768;
const STORE_SCHEMA: &str = "eu.exantas.Support";
const STORE_APPLICATION: &str = "exantas-support";
const STORE_KEY: &str = "office-secure-store-v1";
// Same schema/attributes as OfficeCallPopup.Linux LinuxSecretService.
const POPUP_SCHEMA: &str = "eu.exantas.OfficeCallPopup";
const POPUP_APPLICATION: &str = "office-call-popup";
const POPUP_TICKET_PREFIX: &str = "Exantas.OfficeCallPopup.Handoff.v1.native-";
const TICKET_LIMIT: usize = 5120;

#[repr(C)]
struct SchemaAttribute {
    name: *const c_char,
    kind: c_int,
}

#[repr(C)]
struct Schema {
    name: *const c_char,
    flags: c_int,
    attributes: [SchemaAttribute; 32],
    reserved: c_int,
    reserved_ptr: [*mut c_void; 7],
}

#[repr(C)]
struct GError {
    domain: c_uint,
    code: c_int,
    message: *const c_char,
}

type HashFn = unsafe extern "C" fn(*const c_void) -> c_uint;
type EqualFn = unsafe extern "C" fn(*const c_void, *const c_void) -> c_int;

struct Api {
    _secret: Library,
    _glib: Library,
    lookup: unsafe extern "C" fn(*const Schema, *mut c_void, *mut c_void, *mut *mut GError) -> *mut c_char,
    store: unsafe extern "C" fn(*const Schema, *mut c_void, *const c_char, *const c_char, *const c_char, *mut c_void, *mut *mut GError) -> c_int,
    clear: unsafe extern "C" fn(*const Schema, *mut c_void, *mut c_void, *mut *mut GError) -> c_int,
    free_password: unsafe extern "C" fn(*mut c_char),
    table_new: unsafe extern "C" fn(HashFn, EqualFn) -> *mut c_void,
    table_insert: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut c_void) -> c_int,
    table_unref: unsafe extern "C" fn(*mut c_void),
    str_hash: HashFn,
    str_equal: EqualFn,
    error_free: unsafe extern "C" fn(*mut GError),
}

// The function pointers are process-global C entry points; libsecret's sync
// calls are documented as usable from any thread.
unsafe impl Send for Api {}
unsafe impl Sync for Api {}

static API: OnceLock<Option<Api>> = OnceLock::new();
static MASTER: Mutex<Option<secretbox::Key>> = Mutex::new(None);

fn load() -> Result<Api> {
    unsafe {
        let secret = Library::new("libsecret-1.so.0")?;
        let glib = Library::new("libglib-2.0.so.0")?;
        let api = Api {
            lookup: *secret.get(b"secret_password_lookupv_sync\0")?,
            store: *secret.get(b"secret_password_storev_sync\0")?,
            clear: *secret.get(b"secret_password_clearv_sync\0")?,
            free_password: *secret.get(b"secret_password_free\0")?,
            table_new: *glib.get(b"g_hash_table_new\0")?,
            table_insert: *glib.get(b"g_hash_table_insert\0")?,
            table_unref: *glib.get(b"g_hash_table_unref\0")?,
            str_hash: *glib.get(b"g_str_hash\0")?,
            str_equal: *glib.get(b"g_str_equal\0")?,
            error_free: *glib.get(b"g_error_free\0")?,
            _secret: secret,
            _glib: glib,
        };
        Ok(api)
    }
}

fn api() -> Result<&'static Api> {
    API.get_or_init(|| match load() {
        Ok(api) => Some(api),
        Err(err) => {
            log::error!("Secret Service (libsecret) unavailable: {}", err);
            None
        }
    })
    .as_ref()
    .ok_or_else(|| anyhow!("Secret Service unavailable"))
}

/// One keyring item: schema name plus `application` and `key` string attributes.
struct Item {
    schema: Box<Schema>,
    _strings: Vec<CString>,
    table: *mut c_void,
    api: &'static Api,
}

impl Item {
    fn new(schema_name: &str, application: &str, key: &str) -> Result<Self> {
        let api = api()?;
        let strings = vec![
            CString::new(schema_name)?,
            CString::new("application")?,
            CString::new("key")?,
            CString::new(application)?,
            CString::new(key)?,
        ];
        let empty = || SchemaAttribute { name: ptr::null(), kind: 0 };
        let mut attributes: [SchemaAttribute; 32] = std::array::from_fn(|_| empty());
        attributes[0] = SchemaAttribute { name: strings[1].as_ptr(), kind: 0 };
        attributes[1] = SchemaAttribute { name: strings[2].as_ptr(), kind: 0 };
        let schema = Box::new(Schema {
            name: strings[0].as_ptr(),
            flags: 0,
            attributes,
            reserved: 0,
            reserved_ptr: [ptr::null_mut(); 7],
        });
        let table = unsafe { (api.table_new)(api.str_hash, api.str_equal) };
        if table.is_null() {
            bail!("Could not allocate Secret Service attributes");
        }
        unsafe {
            (api.table_insert)(table, strings[1].as_ptr() as _, strings[3].as_ptr() as _);
            (api.table_insert)(table, strings[2].as_ptr() as _, strings[4].as_ptr() as _);
        }
        Ok(Self { schema, _strings: strings, table, api })
    }

    fn check(&self, error: *mut GError) -> Result<()> {
        if error.is_null() {
            return Ok(());
        }
        let detail = unsafe {
            let message = (*error).message;
            let text = if message.is_null() { String::new() } else { CStr::from_ptr(message).to_string_lossy().into_owned() };
            (self.api.error_free)(error);
            text
        };
        bail!("Secret Service error: {}", detail)
    }

    fn read(&self) -> Result<Option<String>> {
        let mut error = ptr::null_mut();
        let value = unsafe { (self.api.lookup)(&*self.schema, self.table, ptr::null_mut(), &mut error) };
        self.check(error)?;
        if value.is_null() {
            return Ok(None);
        }
        let text = unsafe { CStr::from_ptr(value).to_str().map(str::to_owned) };
        unsafe { (self.api.free_password)(value) };
        Ok(Some(text?))
    }

    fn write(&self, label: &str, value: &str) -> Result<()> {
        let label = CString::new(label)?;
        let value = CString::new(value)?;
        let mut error = ptr::null_mut();
        let stored = unsafe {
            (self.api.store)(&*self.schema, self.table, ptr::null(), label.as_ptr(), value.as_ptr(), ptr::null_mut(), &mut error)
        };
        self.check(error)?;
        if stored == 0 {
            bail!("Secret Service did not store the value");
        }
        Ok(())
    }

    fn delete(&self) -> Result<()> {
        let mut error = ptr::null_mut();
        unsafe { (self.api.clear)(&*self.schema, self.table, ptr::null_mut(), &mut error) };
        self.check(error)
    }
}

impl Drop for Item {
    fn drop(&mut self) {
        unsafe { (self.api.table_unref)(self.table) };
    }
}

fn master_key(create: bool) -> Result<secretbox::Key> {
    let mut cached = MASTER.lock().unwrap();
    if let Some(key) = cached.as_ref() {
        return Ok(key.clone());
    }
    let item = Item::new(STORE_SCHEMA, STORE_APPLICATION, STORE_KEY)?;
    let key = match item.read()? {
        Some(stored) => {
            let bytes = base64::decode(stored.trim(), base64::Variant::Original)
                .map_err(|_| anyhow!("Invalid keyring key"))?;
            secretbox::Key::from_slice(&bytes).ok_or_else(|| anyhow!("Invalid keyring key"))?
        }
        None if create => {
            let key = secretbox::gen_key();
            item.write("Exantas Support Office protection key", &base64::encode(&key.0, base64::Variant::Original))?;
            // Read back so a keyring that silently drops writes is not trusted.
            if item.read()?.is_none() {
                bail!("Keyring did not keep the protection key");
            }
            key
        }
        None => bail!("Keyring protection key is missing"),
    };
    *cached = Some(key.clone());
    Ok(key)
}

pub fn protect(plain: &str) -> Result<String> {
    if plain.is_empty() {
        bail!("Empty value");
    }
    let key = master_key(true)?;
    let nonce = secretbox::gen_nonce();
    let mut sealed = nonce.0.to_vec();
    sealed.extend(secretbox::seal(plain.as_bytes(), &nonce, &key));
    let stored = format!("{}{}", PREFIX, base64::encode(&sealed, base64::Variant::Original));
    if stored.len() > MAX_STORED {
        bail!("Protected value too large");
    }
    Ok(stored)
}

pub fn unprotect(stored: &str) -> Result<String> {
    let payload = stored.strip_prefix(PREFIX).ok_or_else(|| anyhow!("Not a protected value"))?;
    if payload.len() > MAX_STORED {
        bail!("Protected value too large");
    }
    let bytes = base64::decode(payload, base64::Variant::Original).map_err(|_| anyhow!("Invalid protected value"))?;
    if bytes.len() < secretbox::NONCEBYTES + secretbox::MACBYTES {
        bail!("Invalid protected value");
    }
    let nonce = secretbox::Nonce::from_slice(&bytes[..secretbox::NONCEBYTES]).ok_or_else(|| anyhow!("Invalid nonce"))?;
    let key = master_key(false)?;
    let plain = secretbox::open(&bytes[secretbox::NONCEBYTES..], &nonce, &key)
        .map_err(|_| anyhow!("Protected value could not be opened"))?;
    Ok(String::from_utf8(plain)?)
}

fn valid_ticket(ticket: &str) -> bool {
    ticket.len() == 32 && ticket.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// The Office Call Popup handoff written by OfficeCallPopup.Linux.
pub fn read_launch_ticket(ticket: &str) -> Result<String> {
    if !valid_ticket(ticket) {
        bail!("Invalid Office ticket");
    }
    let item = Item::new(POPUP_SCHEMA, POPUP_APPLICATION, &format!("{}{}", POPUP_TICKET_PREFIX, ticket))?;
    let value = item.read()?.ok_or_else(|| anyhow!("Office launch credential unavailable"))?;
    if value.is_empty() || value.len() > TICKET_LIMIT {
        bail!("Invalid Office credential size");
    }
    Ok(value)
}

pub fn delete_launch_ticket(ticket: &str) -> Result<()> {
    if !valid_ticket(ticket) {
        return Ok(());
    }
    Item::new(POPUP_SCHEMA, POPUP_APPLICATION, &format!("{}{}", POPUP_TICKET_PREFIX, ticket))?.delete()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ticket_shape() {
        assert!(valid_ticket("0123456789abcdef0123456789abcdef"));
        assert!(!valid_ticket("0123456789ABCDEF0123456789abcdef"));
        assert!(!valid_ticket("../../etc"));
    }

    /// Needs an unlocked Secret Service; run with EXANTAS_KEYRING_TEST=1, e.g.
    /// under `dbus-run-session` with `gnome-keyring-daemon --unlock`.
    #[test]
    fn keyring_round_trip_and_popup_ticket() {
        if std::env::var("EXANTAS_KEYRING_TEST").is_err() {
            return;
        }
        let sealed = protect("lease-json").unwrap();
        assert!(sealed.starts_with(PREFIX));
        assert_ne!(sealed, protect("lease-json").unwrap());
        assert_eq!(unprotect(&sealed).unwrap(), "lease-json");
        let mut tampered = sealed.clone();
        tampered.pop();
        tampered.push(if sealed.ends_with('A') { 'B' } else { 'A' });
        assert!(unprotect(&tampered).is_err());
        let ticket = "0123456789abcdef0123456789abcdef";
        let item = Item::new(POPUP_SCHEMA, POPUP_APPLICATION, &format!("{}{}", POPUP_TICKET_PREFIX, ticket)).unwrap();
        item.write("test", "{\"api\":\"x\"}").unwrap();
        assert_eq!(read_launch_ticket(ticket).unwrap(), "{\"api\":\"x\"}");
        delete_launch_ticket(ticket).unwrap();
        assert!(read_launch_ticket(ticket).is_err());
    }

    #[test]
    fn rejects_foreign_values() {
        assert!(unprotect("dpapi:v1:AAAA").is_err());
        assert!(unprotect("secret:v1:not-base64!").is_err());
        assert!(unprotect("secret:v1:AAAA").is_err());
    }
}
