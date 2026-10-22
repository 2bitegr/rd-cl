"""Real Git/process fixtures for source, package, SDK and release-session guards."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from native_guard_fixture import sdk_fixture

SCRIPT = Path(__file__).resolve().parents[1] / 'windows-native-build.py'
spec = importlib.util.spec_from_file_location('release_integrity_native', SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def put(root, name, data):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data.encode() if isinstance(data, str) else data)
    return path


@unittest.skipUnless(shutil.which('git'), 'Existing Git required')
class SubmoduleIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'submodule'
        self.root.mkdir()
        self.env = native.offline_environment(os.environ)
        self.git('init', 'init', '-q')
        self.git('name', 'config', 'user.name', 'Synthetic fixture')
        self.git('email', 'config', 'user.email', 'fixture@example.invalid')
        put(self.root, 'src/config.rs', 'const VALUE: u32 = 1;\n')
        put(self.root, 'src/other.rs', 'const OTHER: u32 = 1;\n')
        self.git('add', 'add', '.')
        self.git('commit', 'commit', '-qm', 'pinned fixture')
        self.head = self.git('head', 'rev-parse', 'HEAD')[1].strip()
        self.patch = put(self.base, 'reviewed.patch', '''diff --git a/src/config.rs b/src/config.rs
--- a/src/config.rs
+++ b/src/config.rs
@@ -1 +1 @@
-const VALUE: u32 = 1;
+const VALUE: u32 = 2;
diff --git a/src/config/new.rs b/src/config/new.rs
new file mode 100644
--- /dev/null
+++ b/src/config/new.rs
@@ -0,0 +1 @@
+const PATCHED: bool = true;
''')

    def git(self, label, *args, cwd=None, env=None, check=True):
        result = subprocess.run(['git', *args], cwd=cwd or self.root, env=env or self.env,
                                capture_output=True, text=True, timeout=10)
        if check and result.returncode:
            raise RuntimeError(label + ': ' + result.stderr)
        return result.returncode, result.stdout

    def verify(self, allow_unpatched=True):
        return native.require_submodule_tree(self.git, self.root, self.head, self.patch,
                                              self.env, self.base, allow_unpatched)

    def apply(self):
        self.git('apply', 'apply', str(self.patch))

    def test_base_and_exact_patch_pass_without_changing_real_index(self):
        index = self.root / '.git/index'
        original = index.read_bytes()
        self.assertEqual(self.verify(), 'PINNED')
        with self.assertRaises(RuntimeError):
            self.verify(False)
        self.apply()
        self.assertEqual(self.verify(False), 'PATCHED')
        self.assertEqual(index.read_bytes(), original)

    def test_crlf_normalization_accepts_only_expected_source(self):
        self.apply()
        for path in (self.root / 'src').rglob('*.rs'):
            path.write_bytes(path.read_bytes().replace(b'\n', b'\r\n'))
        self.assertEqual(self.verify(False), 'PATCHED')

    def test_extra_tracked_edit_before_and_after_patch_is_preserved_and_rejected(self):
        changed = put(self.root, 'src/other.rs', 'const OTHER: u32 = 999;\n')
        with self.assertRaises(RuntimeError):
            self.verify()
        self.apply()
        with self.assertRaises(RuntimeError):
            self.verify(False)
        self.assertIn('999', changed.read_text())

    def test_staged_extra_edit_is_rejected_without_resetting_index(self):
        put(self.root, 'src/other.rs', 'const OTHER: u32 = 999;\n')
        self.git('stage', 'add', 'src/other.rs')
        original = (self.root / '.git/index').read_bytes()
        with self.assertRaises(RuntimeError):
            self.verify()
        self.assertEqual((self.root / '.git/index').read_bytes(), original)

    def test_untracked_source_and_modified_patch_addition_are_rejected(self):
        self.apply()
        extra = put(self.root, 'src/rogue.rs', 'unexpected')
        with self.assertRaises(RuntimeError):
            self.verify(False)
        extra.unlink()  # exact disposable fixture file
        put(self.root, 'src/config/new.rs', 'unreviewed content')
        with self.assertRaises(RuntimeError):
            self.verify(False)


class PayloadIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'flutter/build/windows/x64/runner/Release'
        pe = bytearray(128)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 0x3c, 64)
        pe[64:68] = b'PE\0\0'
        struct.pack_into('<H', pe, 68, 0x8664)
        for name in ['rustdesk.exe', 'flutter_windows.dll', 'librustdesk.dll',
                     'dylib_virtual_display.dll', 'data/icudtl.dat', 'data/app.so']:
            put(self.bundle, name, pe if name == 'rustdesk.exe' else b'synthetic payload')
        put(self.root, 'flutter/pubspec.lock', 'locked')
        put(self.root, 'toolchain-manifest.json', '{}')
        self.files = native.runtime_inventory(self.bundle)
        put(self.root, 'native-compile-receipt.json', json.dumps({
            'source_commit': 'a' * 40, 'lock_sha256': native.digest(self.root / 'flutter/pubspec.lock'),
            'payload_sha256': self.files}))
        self.runner = object.__new__(native.Build)
        self.runner.source = self.runner.logs = self.runner.output = self.root
        self.runner.args = argparse.Namespace(source_commit='a' * 40)
        self.runner.profile = {'version': '1.4.13+71', 'source_repository': 'synthetic',
                               'input_sha256': {'flutter/pubspec.lock': native.digest(self.root / 'flutter/pubspec.lock')}}

    def test_stable_inventory_matches_every_archived_hash(self):
        self.runner.package()
        archive = next(self.root.glob('*.zip'))
        with zipfile.ZipFile(archive) as payload:
            self.assertEqual(len(payload.namelist()), len(self.files))
            for name, expected in self.files.items():
                member = 'rd-cl-1.4.13+71-windows-x64-portable/' + name
                self.assertEqual(hashlib.sha256(payload.read(member)).hexdigest(), expected)

    def test_extra_file_after_compile_receipt_stops_before_zip(self):
        put(self.bundle, 'unexpected.dll', b'not compiled')
        with self.assertRaisesRegex(RuntimeError, 'inventory differs'):
            self.runner.package()
        self.assertEqual(list(self.root.glob('*.zip')), [])

    def test_missing_or_changed_file_stops_before_zip(self):
        target = self.bundle / 'data/app.so'
        for mode in ['missing', 'changed']:
            with self.subTest(mode=mode):
                if mode == 'missing':
                    target.unlink()
                else:
                    target.write_bytes(b'modified')
                with self.assertRaises(RuntimeError):
                    self.runner.package()
                target.write_bytes(b'synthetic payload')
        self.assertEqual(list(self.root.glob('*.zip')), [])

    def test_mutation_while_creating_zip_never_publishes_pass_info(self):
        original = zipfile.ZipFile.write
        def mutate(archive, filename, *args, **kwargs):
            Path(filename).write_bytes(b'changed during packaging')
            return original(archive, filename, *args, **kwargs)
        with patch.object(zipfile.ZipFile, 'write', mutate):
            with self.assertRaisesRegex(RuntimeError, 'ZIP payload differs'):
                self.runner.package()
        self.assertFalse((self.root / 'BUILD-INFO.json').exists())


class CodecIdentity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runner = object.__new__(native.Build)
        r = self.runner
        r.source = r.logs = self.root
        r.vs = self.root / 'VS'
        put(r.vs, 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt', 'fixture')
        compiler = r.vs / 'VC/Tools/MSVC/fixture/bin/Hostx64/x64'
        r.cmake = put(self.root, 'cmake.exe', b'cmake')
        r.tools = {'vcpkg': self.root / 'vcpkg'}
        self.tools = [put(compiler, name, b'compiler tool') for name in ['cl.exe', 'link.exe', 'lib.exe']]
        self.tools += [r.cmake, put(self.root, 'vcpkg/vcpkg.exe', b'vcpkg')]
        r.profile = {'input_sha256': {'vcpkg.json': 'manifest'}}
        lib = put(self.root, 'vcpkg/installed/x64-windows-static/lib/codec.lib', b'codec')
        self.receipt = {'status': 'PASS', 'inputs': {'vcpkg.json': 'manifest'},
                        'source_sha256': {}, 'tool_sha256': {str(p): native.digest(p) for p in self.tools},
                        'codec_abi_sha256': {'lib/codec.lib': native.digest(lib)},
                        'sdk_identity': sdk_fixture(r, self.root),
                        'triplet_sha256': hashlib.sha256(native.native_triplet(r.profile)).hexdigest()}
        self.path = put(self.root, 'receipt.json', json.dumps(self.receipt))
        r.cfg = {'compiled_cache_receipt': str(self.path)}

    def test_matching_identity_passes_without_rewriting_receipt(self):
        original = self.path.read_bytes()
        self.runner.require_verified_codecs()
        self.assertEqual(self.path.read_bytes(), original)

    def test_each_recorded_executable_change_is_rejected(self):
        for tool in self.tools:
            with self.subTest(tool=tool.name):
                original = tool.read_bytes()
                tool.write_bytes(b'changed')
                with self.assertRaisesRegex(RuntimeError, 'compiler/tool differs'):
                    self.runner.require_verified_codecs()
                tool.write_bytes(original)

    def test_wrong_sdk_version_or_changed_sdk_input_is_rejected(self):
        self.runner.env['WINDOWSSDKVERSION'] = '10.0.26100.0\\'
        with self.assertRaises(RuntimeError):
            self.runner.require_verified_codecs()
        self.runner.env['WINDOWSSDKVERSION'] = '10.0.22621.0\\'
        put(self.root, 'WindowsSDK/Include/10.0.22621.0/um/Windows.h', b'updated header')
        with self.assertRaisesRegex(RuntimeError, 'SDK identity differs'):
            self.runner.require_verified_codecs()

    def test_legacy_receipt_is_preserved_and_fails_with_actionable_reason(self):
        del self.receipt['sdk_identity']
        self.path.write_text(json.dumps(self.receipt))
        original = self.path.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'lacks Windows SDK identity'):
            self.runner.require_verified_codecs()
        self.assertEqual(self.path.read_bytes(), original)

    def test_wrong_sdk_triplet_is_rejected(self):
        self.receipt['triplet_sha256'] = 'old release-only triplet'
        self.path.write_text(json.dumps(self.receipt))
        with self.assertRaisesRegex(RuntimeError, 'triplet differs'):
            self.runner.require_verified_codecs()

    def test_actual_flutter_project_must_select_exact_sdk(self):
        name = 'flutter/build/windows/x64/runner/rustdesk.vcxproj'
        for version, valid in [('10.0.22621.0', True), ('10.0.26100.0', False), ('', False)]:
            with self.subTest(version=version):
                put(self.root, name, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>'
                    '<WindowsTargetPlatformVersion>' + version + '</WindowsTargetPlatformVersion></PropertyGroup></Project>')
                if valid:
                    self.runner.require_flutter_sdk()
                else:
                    with self.assertRaises(RuntimeError):
                        self.runner.require_flutter_sdk()


class ReleaseLocks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lockdir = self.root / 'locks'

    def child(self, resource):
        code = '''import importlib.util,sys
from pathlib import Path
s=importlib.util.spec_from_file_location('native',sys.argv[1]); m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
x=m.BuildLocks(Path(sys.argv[2]),[sys.argv[3]])
try: x.acquire()
except RuntimeError: sys.exit(23)
x.close()
'''
        return subprocess.run([sys.executable, '-c', code, str(SCRIPT), str(self.lockdir), resource],
                              capture_output=True, text=True, timeout=10)

    def test_constructor_failure_releases_acquired_resource_before_reporting(self):
        test = self
        def initialize(runner, args):
            runner.session_locks = native.BuildLocks(test.lockdir, ['source:owned'])
            runner.session_locks.acquire()
            raise OSError('synthetic constructor failure after acquisition')
        with patch.object(native.Build, '_initialize', initialize):
            with self.assertRaisesRegex(OSError, 'constructor failure'):
                native.Build(argparse.Namespace())
        self.assertEqual(self.child('source:owned').returncode, 0)

    def test_resume_package_and_exe_keep_session_through_environment_import(self):
        test = self
        events = []
        class Session:
            def __init__(self, args):
                self.logs = test.root
                self.args = args
                self.lock = native.BuildLocks(test.lockdir, ['source:owned'])
                self.lock.acquire()
            def preflight(self):
                events.append('preflight')
            def package(self):
                events.append('package')
                test.assertEqual(test.child('source:owned').returncode, 23)
            def developer_environment(self):
                events.append('environment')
                test.assertEqual(test.child('source:owned').returncode, 23)
            def package_exe(self):
                events.append('exe')
                test.assertEqual(test.child('source:owned').returncode, 23)
            def close(self):
                self.lock.close()
        argv = ['native', '--mode', 'Package', '--with-exe', '--toolchain', 'fixture',
                '--source-commit', 'a' * 40, '--output-root', str(self.root)]
        with patch.object(native, 'Build', Session), patch.object(sys, 'argv', argv):
            self.assertEqual(native.main(), 0)
        self.assertEqual(events, ['preflight', 'package', 'environment', 'exe'])
        self.assertEqual(self.child('source:owned').returncode, 0)

    def test_real_child_is_blocked_until_owner_releases(self):
        lock = native.BuildLocks(self.lockdir, ['source:owned'])
        lock.acquire()
        self.assertEqual(self.child('source:owned').returncode, 23)
        self.assertEqual(self.child('source:other').returncode, 0)
        lock.close()
        self.assertEqual(self.child('source:owned').returncode, 0)

    def test_partial_acquisition_releases_only_own_resources(self):
        owner = native.BuildLocks(self.lockdir, ['b'])
        owner.acquire()
        contender = native.BuildLocks(self.lockdir, ['a', 'b'])
        with self.assertRaises(RuntimeError):
            contender.acquire()
        self.assertEqual(len(list(self.lockdir.glob('*.lock'))), 1)
        owner.close()

    def test_stale_or_changed_lock_is_never_automatically_deleted(self):
        owner = native.BuildLocks(self.lockdir, ['owned'])
        owner.acquire()
        path, token = owner.owned[0]
        path.write_text('changed owner')
        with self.assertRaisesRegex(RuntimeError, 'ownership changed'):
            owner.close()
        with self.assertRaises(RuntimeError):
            native.BuildLocks(self.lockdir, ['owned']).acquire()
        self.assertEqual(path.read_text(), 'changed owner')

    def test_build_and_exe_packaging_share_the_same_session(self):
        events = []
        test = self
        class Session:
            def __init__(self, args):
                self.logs = test.root
                self.args = args
                self.lock = native.BuildLocks(test.lockdir, ['source:owned'])
                self.lock.acquire()
            def preflight(self):
                events.append('preflight')
            def build(self):
                events.append('build')
                test.assertEqual(test.child('source:owned').returncode, 23)
            def package_exe(self):
                events.append('exe')
                test.assertEqual(test.child('source:owned').returncode, 23)
            def close(self):
                self.lock.close()
        argv = ['native', '--mode', 'Build', '--with-exe', '--toolchain', 'fixture',
                '--source-commit', 'a' * 40, '--output-root', str(self.root)]
        with patch.object(native, 'Build', Session), patch.object(sys, 'argv', argv):
            self.assertEqual(native.main(), 0)
        self.assertEqual(events, ['preflight', 'build', 'exe'])
        self.assertEqual(self.child('source:owned').returncode, 0)

    def test_packaging_failure_releases_session_and_reports_blocked(self):
        test = self
        class Session:
            def __init__(self, args):
                self.logs = test.root
                self.args = args
                self.lock = native.BuildLocks(test.lockdir, ['source:owned'])
                self.lock.acquire()
            def preflight(self):
                pass
            def build(self):
                pass
            def package_exe(self):
                test.assertEqual(test.child('source:owned').returncode, 23)
                raise RuntimeError('synthetic packaging failure')
            def close(self):
                self.lock.close()
        argv = ['native', '--mode', 'Build', '--with-exe', '--toolchain', 'fixture',
                '--source-commit', 'a' * 40, '--output-root', str(self.root)]
        with patch.object(native, 'Build', Session), patch.object(sys, 'argv', argv):
            self.assertEqual(native.main(), 1)
        self.assertEqual(json.loads((self.root / 'result.json').read_text())['status'], 'BLOCKED')
        self.assertEqual(self.child('source:owned').returncode, 0)

    def test_failure_between_build_and_packaging_releases_session(self):
        test = self
        class Session:
            def __init__(self, args):
                self.logs = test.root
                self.args = args
                self.lock = native.BuildLocks(test.lockdir, ['source:owned'])
                self.lock.acquire()
            def preflight(self):
                pass
            def build(self):
                raise RuntimeError('synthetic compile failure')
            def package_exe(self):
                test.fail('Packaging must not run after failed compile')
            def close(self):
                self.lock.close()
        argv = ['native', '--mode', 'Build', '--with-exe', '--toolchain', 'fixture',
                '--source-commit', 'a' * 40, '--output-root', str(self.root)]
        with patch.object(native, 'Build', Session), patch.object(sys, 'argv', argv):
            self.assertEqual(native.main(), 1)
        self.assertEqual(self.child('source:owned').returncode, 0)


if __name__ == '__main__':
    unittest.main()
