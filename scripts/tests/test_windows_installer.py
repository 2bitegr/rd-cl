"""Real Rust command generator, native Windows copy fixtures and release version pins."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUSTC = os.environ.get('RDCL_TEST_RUSTC') or shutil.which('rustc')


@unittest.skipUnless(RUSTC, 'Existing Rust compiler required for installer generator')
class InstallerCommands(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='rdcl-install-guards-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        module = json.dumps(str(ROOT / 'src/platform/windows_install.rs'))
        harness = cls.root / 'harness.rs'
        harness.write_text(f'#[path = {module}] mod windows_install;\n' + r'''
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let commands = windows_install::payload_commands(&a[1], &a[2], &a[3], &a[4], &a[5], true);
    print!("{}", windows_install::checked_commands(&commands));
}
''')
        cls.generator = cls.root / ('generator.exe' if os.name == 'nt' else 'generator')
        cls.units = cls.root / ('units.exe' if os.name == 'nt' else 'units')
        for extra, output in [([], cls.generator), (['--test'], cls.units)]:
            subprocess.run([RUSTC, '--edition=2021', *extra, str(harness), '-o', str(output)],
                           check=True, capture_output=True, text=True)

    def test_rust_command_generator_contracts(self):
        result = subprocess.run([self.units], check=True, capture_output=True, text=True)
        self.assertIn('4 passed', result.stdout)

    def fixture(self, missing=False):
        temp = tempfile.TemporaryDirectory(prefix='rdcl-native-copy-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        source = root / 'Source with spaces'
        target = root / 'Exantas Support'
        source.mkdir()
        target.mkdir()
        for name in ['rustdesk.exe', 'librustdesk.dll', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat']:
            path = source / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(('synthetic-new-' + name).encode())
        if missing:
            (source / 'librustdesk.dll').unlink()
        exe = target / 'Exantas Support.exe'
        exe.write_bytes(b'previous-executable')
        (target / 'librustdesk.dll').write_bytes(b'previous-core')
        unrelated = target / 'keep-local.txt'
        unrelated.write_bytes(b'keep')
        generated = subprocess.run([self.generator, str(source / 'rustdesk.exe'), str(source), 'rustdesk.exe',
                                    str(exe), str(target)], check=True, capture_output=True, text=True).stdout
        marker = root / 'failure.txt'
        marker.write_text('Not completed')
        success = root / 'success.txt'
        batch = root / 'copy.bat'
        batch.write_text('@echo off\nset "RDCL_INSTALL_FAILURE=' + str(marker) + '"\n' + generated +
                         f'echo PASS>"{success}"\nexit /b 0\n')
        return source, target, marker, success, batch

    @unittest.skipUnless(os.name == 'nt', 'Requires native Windows cmd/XCOPY/FC; no installation or services')
    def test_native_copy_renames_and_preserves_unrelated_files(self):
        source, target, _, success, batch = self.fixture()
        result = subprocess.run(['cmd.exe', '/d', '/c', str(batch)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(success.exists())
        self.assertEqual((source / 'rustdesk.exe').read_bytes(), (target / 'Exantas Support.exe').read_bytes())
        self.assertEqual((target / 'keep-local.txt').read_bytes(), b'keep')

    @unittest.skipUnless(os.name == 'nt', 'Requires native Windows cmd/XCOPY/FC; no installation or services')
    def test_missing_source_core_does_not_accept_stale_installed_core(self):
        _, _, marker, success, batch = self.fixture(missing=True)
        result = subprocess.run(['cmd.exe', '/d', '/c', str(batch)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(success.exists())
        self.assertIn('failed', marker.read_text())

    @unittest.skipUnless(os.name == 'nt', 'Requires native Windows exclusive file locks; no installation or services')
    def test_locked_installed_core_stops_before_success(self):
        import ctypes
        from ctypes import wintypes
        _, target, marker, success, batch = self.fixture()
        api = ctypes.WinDLL('kernel32', use_last_error=True)
        api.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                   wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        api.CreateFileW.restype = wintypes.HANDLE
        api.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = api.CreateFileW(str(target / 'librustdesk.dll'), 0x80000000, 0, None, 3, 0, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            result = subprocess.run(['cmd.exe', '/d', '/c', str(batch)], capture_output=True)
        finally:
            api.CloseHandle(handle)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(success.exists())
        self.assertIn('failed', marker.read_text())


@unittest.skipUnless(RUSTC, 'Existing Rust compiler required for update ownership contract')
class UpdateRestoreOwnership(unittest.TestCase):
    def test_actual_update_commands_and_restore_capture_typecheck(self):
        source = (ROOT / 'src/platform/windows.rs').read_text()
        update = source[source.index('pub fn update_me('):source.index('\nfn get_reg_msi_key(')]
        start = update.index('    let cmds = format!(')
        end = update.index('    restore_session_guard.b = true;') + len('    restore_session_guard.b = true;')
        commands = update[start:end]
        common = (ROOT / 'src/common.rs').read_text()
        guard = common[common.index('pub struct SimpleCallOnReturn {'):common.index('\npub fn global_init(')]
        # Typecheck the actual command/callback region and guard with inert helper
        # signatures. No installer, service, callback or command is executed.
        fixture = r'''#![allow(dead_code, unused_variables)]
extern crate self as log;
#[macro_export]
macro_rules! info { ($($message:tt)*) => {}; }
macro_rules! allow_err { ($operation:expr) => { let _ = $operation; }; }
mod common { PRODUCTION_GUARD }
mod platform {
    #[path = WINDOWS_INSTALL_MODULE]
    mod windows_install;
    mod windows {
        fn is_root() -> bool { false }
        fn run_exe_in_session(_: &str, _: Vec<&str>, _: u32, _: bool) -> Result<(), ()> { Ok(()) }
        fn run_exe_direct(_: &str, _: Vec<&str>, _: bool) -> Result<(), ()> { Ok(()) }
        fn copy_exe_cmd(_: &str, _: &str, _: &str) -> Result<String, ()> { Ok(String::new()) }
        fn remove_meta_toml_cmd(_: bool, _: &str) -> String { String::new() }
        fn run_cmds(_: String, _: bool, _: &str) -> Result<(), ()> { Ok(()) }
        fn update_contract(debug: bool) -> Result<(), ()> {
            let app_name = String::from("Synthetic Support");
            let src_exe = String::from(r"C:\Synthetic Input\client.exe");
            let path = String::from(r"D:\Custom Install\Synthetic Support");
            let exe = format!(r"{}\Synthetic Support.exe", path);
            let filter = String::new();
            let reg_cmd = String::new();
            let restore_service_cmd = String::new();
            let uninstall_printer_cmd = String::new();
            let install_printer_cmd = String::new();
            let is_msi = Some(false);
            let tray_sessions = vec![1_u32];
            let main_window_sessions = vec![1_u32];
            PRODUCTION_COMMANDS
            Ok(())
        }
    }
}
fn main() {}
'''
        fixture = fixture.replace('PRODUCTION_GUARD', guard).replace('PRODUCTION_COMMANDS', commands)
        fixture = fixture.replace('WINDOWS_INSTALL_MODULE', json.dumps(str(ROOT / 'src/platform/windows_install.rs')))
        with tempfile.TemporaryDirectory(prefix='rdcl-update-ownership-') as folder:
            folder = Path(folder)
            harness, metadata = folder / 'ownership.rs', folder / 'ownership.rmeta'
            harness.write_text(fixture)
            result = subprocess.run([RUSTC, '--edition=2021', '--emit=metadata', str(harness),
                                     '-o', str(metadata)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(metadata.is_file())


class VersionAndCoreIdentity(unittest.TestCase):
    def test_product_versions_and_profile_input_hashes_agree(self):
        cargo = tomllib.loads((ROOT / 'Cargo.toml').read_text())
        packer = tomllib.loads((ROOT / 'libs/portable/Cargo.toml').read_text())
        lock = tomllib.loads((ROOT / 'Cargo.lock').read_text())
        profile = json.loads((ROOT / 'scripts/windows-native-profile.json').read_text())
        pins = json.loads((ROOT / 'scripts/windows-codec-bootstrap-inputs.json').read_text())
        self.assertEqual(cargo['package']['version'], '3.2.10')
        self.assertEqual(packer['package']['version'], '3.2.10')
        self.assertEqual(profile['version'], '3.2.10')
        self.assertEqual(pins['product_version'], profile['version'])
        self.assertIn('version: ' + profile['version'], (ROOT / 'flutter/pubspec.yaml').read_text())
        for name in ['rustdesk', 'rustdesk-portable-packer']:
            self.assertEqual(next(p['version'] for p in lock['package'] if p['name'] == name), '3.2.10')
        for key in ['ProductVersion', 'FileVersion']:
            self.assertEqual(packer['package']['metadata']['winres'][key], '3.2.10.0')
        for name, expected in profile['input_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected, name)

    def test_old_generated_version_and_stale_flutter_dll_are_rejected(self):
        spec = importlib.util.spec_from_file_location('installer_native', ROOT / 'scripts/windows-native-build.py')
        native = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(native)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = native.Build.__new__(native.Build)
            runner.source = root
            runner.logs = root / 'logs'
            runner.logs.mkdir()
            runner.profile = {'version': '2.0.0+72'}
            (root / 'src').mkdir()
            generated = root / 'src/version.rs'
            compiled = root / 'release'
            compiled.mkdir()
            bundle = root / 'bundle'
            bundle.mkdir()
            (compiled / 'librustdesk.dll').write_bytes(b'new-core')
            (bundle / 'librustdesk.dll').write_bytes(b'old-core')
            generated.write_text('pub const VERSION: &str = "1.4.11";')
            with self.assertRaisesRegex(RuntimeError, 'version differs'):
                runner.require_native_core(bundle, root)
            generated.write_text('pub const VERSION: &str = "2.0.0";')
            with self.assertRaisesRegex(RuntimeError, 'different native DLL'):
                runner.require_native_core(bundle, root)
            (bundle / 'librustdesk.dll').write_bytes(b'new-core')
            runner.require_native_core(bundle, root)
            self.assertEqual(json.loads((runner.logs / 'native-core-identity.json').read_text())['version'], '2.0.0')


@unittest.skipUnless(RUSTC, 'Existing Rust compiler required for bootstrap parser')
class InstallerBootstrap(unittest.TestCase):
    def test_actual_filename_parser_handles_context_and_browser_duplicates(self):
        with tempfile.TemporaryDirectory(prefix='rdcl-bootstrap-') as folder:
            target = Path(folder) / ('bootstrap.exe' if os.name == 'nt' else 'bootstrap')
            subprocess.run([RUSTC, '--edition=2021', '--test', str(ROOT / 'src/platform/installer_bootstrap.rs'), '-o', str(target)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(target)], check=True, capture_output=True, text=True)
            self.assertIn('2 passed', result.stdout)
