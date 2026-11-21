use std::{
    fs::{self},
    io::{Cursor, Read},
    path::Path,
};

#[cfg(windows)]
const BIN_DATA: &[u8] = include_bytes!("../data.bin");
#[cfg(not(windows))]
const BIN_DATA: &[u8] = &[];
// 4bytes
const LENGTH: usize = 4;
const IDENTIFIER_LENGTH: usize = 8;
const MD5_LENGTH: usize = 32;
const BUF_SIZE: usize = 4096;

pub(crate) struct BinaryData {
    pub md5_code: &'static [u8],
    // compressed gzip data
    pub raw: &'static [u8],
    pub path: String,
}

pub(crate) struct BinaryReader {
    pub files: Vec<BinaryData>,
    pub exe: String,
}

impl Default for BinaryReader {
    fn default() -> Self {
        let (files, exe) = BinaryReader::read();
        Self { files, exe }
    }
}

impl BinaryData {
    fn decompress(&self) -> Vec<u8> {
        let cursor = Cursor::new(self.raw);
        let mut decoder = brotli::Decompressor::new(cursor, BUF_SIZE);
        let mut buf = Vec::new();
        decoder.read_to_end(&mut buf).ok();
        buf
    }

    pub fn write_verified_new(&self, prefix: &Path) -> std::io::Result<()> {
        use std::io::Write;
        if !self.path.split('/').all(|p| !p.is_empty() && p != "." && p != ".." && p.bytes().all(|c| c.is_ascii_alphanumeric() || b"_. -".contains(&c))) {
            return Err(std::io::ErrorKind::InvalidInput.into());
        }
        let target = prefix.join(&self.path);
        if let Some(parent) = target.parent() { std::fs::create_dir_all(parent)?; }
        let mut content = Vec::new();
        brotli::Decompressor::new(Cursor::new(self.raw), BUF_SIZE).read_to_end(&mut content)?;
        if format!("{:x}", md5::compute(&content)) != String::from_utf8_lossy(self.md5_code) {
            return Err(std::io::ErrorKind::InvalidData.into());
        }
        let mut file = std::fs::OpenOptions::new().create_new(true).write(true).open(target)?;
        file.write_all(&content)?;
        file.sync_all()?;
        Ok(())
    }

    pub fn write_to_file(&self, prefix: &Path) {
        let p = prefix.join(&self.path);
        if let Some(parent) = p.parent() {
            if !parent.exists() {
                let _ = fs::create_dir_all(parent);
            }
        }
        if p.exists() {
            // check md5
            let f = fs::read(p.clone()).unwrap_or_default();
            let digest = format!("{:x}", md5::compute(&f));
            let md5_record = String::from_utf8_lossy(self.md5_code);
            if digest == md5_record {
                // same, skip this file
                println!("skip {}", &self.path);
                return;
            } else {
                println!("writing {}", p.display());
                println!("{} -> {}", md5_record, digest)
            }
        }
        let _ = fs::write(p, self.decompress());
    }
}

impl BinaryReader {
    fn read() -> (Vec<BinaryData>, String) {
        let mut base: usize = 0;
        let mut parsed = vec![];
        assert!(BIN_DATA.len() > IDENTIFIER_LENGTH, "bin data invalid!");
        let mut iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
        if iden != "rustdesk" {
            panic!("bin file is not valid!");
        }
        base += IDENTIFIER_LENGTH;
        loop {
            iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
            if iden == "rustdesk" {
                base += IDENTIFIER_LENGTH;
                break;
            }
            // start reading
            let mut offset = 0;
            let path_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let path =
                String::from_utf8_lossy(&BIN_DATA[base + offset..base + offset + path_length])
                    .to_string();
            offset += path_length;
            // file sz
            let file_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let raw = &BIN_DATA[base + offset..base + offset + file_length];
            offset += file_length;
            // md5
            let md5 = &BIN_DATA[base + offset..base + offset + MD5_LENGTH];
            offset += MD5_LENGTH;
            parsed.push(BinaryData {
                md5_code: md5,
                raw: raw,
                path: path,
            });
            base += offset;
        }
        // executable
        let executable = String::from_utf8_lossy(&BIN_DATA[base..]).to_string();
        (parsed, executable)
    }

    #[cfg(linux)]
    pub fn configure_permission(&self, prefix: &Path) {
        use std::os::unix::prelude::PermissionsExt;

        let exe_path = prefix.join(&self.exe);
        if exe_path.exists() {
            if let Ok(f) = File::open(exe_path) {
                if let Ok(meta) = f.metadata() {
                    let mut permissions = meta.permissions();
                    permissions.set_mode(0o755);
                    f.set_permissions(permissions).ok();
                }
            }
        }
    }
}
