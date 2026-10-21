"""Synthetic guard/verifier tests, not a claim of an S2 native compilation."""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location('codec_bootstrap',
    Path(__file__).resolve().parents[1] / 'windows-codec-bootstrap.py')
codec = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codec)


class BootstrapGuards(unittest.TestCase):
    def test_helper_audit_stages_cmake_dependency_before_loading_consumers(self):
        cmake = os.environ.get('RDCL_TEST_CMAKE') or shutil.which('cmake')
        if not cmake:
            self.skipTest('Existing CMake unavailable; set RDCL_TEST_CMAKE on S2. No download attempted.')
        self.assertTrue(Path(cmake).is_file(), 'RDCL_TEST_CMAKE must name an existing executable')
        for dependency_present in [True, False]:
            with self.subTest(dependency_present=dependency_present), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / 'owned fixture'
                vcpkg = root / 'local-vcpkg'
                audit = root / 'audit'
                scripts = vcpkg / 'scripts'
                (scripts / 'cmake').mkdir(parents=True)
                audit.mkdir()
                (scripts / 'cmake/vcpkg_common_definitions.cmake').write_text('# fixture host context\n')
                (scripts / 'ports.cmake').write_text('''
set(CURRENT_BUILDTREES_DIR "${BUILDTREES_DIR}/${PORT}")
function(vcpkg_find_acquire_program program)
  set(${program} "${CMAKE_COMMAND}" PARENT_SCOPE)
endfunction()
function(vcpkg_acquire_msys output)
  set(${output} "${BOOTSTRAP_AUDIT}/fixture-msys" PARENT_SCOPE)
endfunction()
''')
                # Model the pinned helper dependency: get-vars' installed config
                # is imported by Meson and includes vcpkg-cmake's installed config.
                ports = {
                    'vcpkg-cmake': '''
file(INSTALL "${CURRENT_PORT_DIR}/vcpkg-port-config.cmake"
  DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
''',
                    'vcpkg-cmake-get-vars': '''
file(INSTALL "${CURRENT_PORT_DIR}/vcpkg-port-config.cmake"
  DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
''',
                    'vcpkg-tool-meson': '''
include("${CURRENT_HOST_INSTALLED_DIR}/share/vcpkg-cmake-get-vars/vcpkg-port-config.cmake")
if(NOT FIXTURE_CMAKE_READY)
  message(FATAL_ERROR "Missing installed vcpkg-cmake dependency")
endif()
file(WRITE "${BOOTSTRAP_AUDIT}/dependency-loaded.txt" "ready")
set(SCRIPT_MESON "${BOOTSTRAP_AUDIT}/fixture-meson.py")
file(WRITE "${SCRIPT_MESON}" "# fixture, never executed")
'''}
                for name, content in ports.items():
                    port = vcpkg / 'ports' / name
                    port.mkdir(parents=True)
                    (port / 'portfile.cmake').write_text(content)
                (vcpkg / 'ports/vcpkg-cmake/vcpkg-port-config.cmake').write_text('''
set(FIXTURE_CMAKE_READY TRUE)
function(vcpkg_cmake_configure)
  message(FATAL_ERROR "Input audit must not compile codecs")
endfunction()
''')
                (vcpkg / 'ports/vcpkg-cmake-get-vars/vcpkg-port-config.cmake').write_text(
                    'include("${CURRENT_HOST_INSTALLED_DIR}/share/vcpkg-cmake/vcpkg-port-config.cmake")\n')
                if not dependency_present:
                    (vcpkg / 'ports/vcpkg-cmake/portfile.cmake').unlink()
                downloads = root / 'preserved-downloads'
                downloads.mkdir()
                (downloads / 'original.tar.gz').write_bytes(b'preserved-local-input')
                before = codec.inventory(downloads)
                result = subprocess.run([cmake, '-DBOOTSTRAP_TOOL_DATE=2025-07-21',
                    '-DBOOTSTRAP_ROOT=' + vcpkg.as_posix(), '-DBOOTSTRAP_AUDIT=' + audit.as_posix(),
                    '-DDOWNLOADS=' + downloads.as_posix(), '-P', str(codec.SCRIPT.with_suffix('.cmake'))],
                    capture_output=True, text=True, timeout=30, env=codec.native.offline_environment(os.environ))
                if dependency_present:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual((audit / 'dependency-loaded.txt').read_text(), 'ready')
                    self.assertEqual((audit / 'helpers-complete.txt').read_text().strip(), 'LOCAL_INPUTS_CHECKED')
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('vcpkg-cmake', result.stderr)
                    self.assertFalse((audit / 'helpers-complete.txt').exists())
                self.assertEqual(codec.inventory(downloads), before)
                self.assertFalse((audit / 'compiled-cache-receipt.json').exists())

    def plan(self):
        return 'The following packages will be built and installed:\n' + ''.join(
            '  * ' + name + ':x64-windows-static@' + value['baseline'] +
            ('#' + str(value['port-version']) if value['port-version'] else '') + '\n'
            for name, value in codec.PINS['ports'].items())

    def test_triplet_exact_bytes_and_old_triplet_are_distinct(self):
        self.assertEqual(hashlib.sha256(codec.TRIPLET).hexdigest(), codec.PINS['triplet_sha256'])
        self.assertNotEqual(codec.PINS['previous_triplet_sha256'], codec.PINS['triplet_sha256'])
        self.assertEqual(codec.TRIPLET.count(b'\r\n'), 4)

    def test_full_pinned_plan_and_features_are_accepted(self):
        codec.require_empty_plan(self.plan().replace('ffmpeg:', 'ffmpeg[amf,core,nvcodec,qsv]:'))

    def test_extra_missing_changed_and_preinstalled_dependencies_stop(self):
        for text in [self.plan() + '  other:x64-windows-static@1.0\n',
                     self.plan() + '  other:x86-windows-static@1.0\n',
                     self.plan() + '  opus:x64-windows-static@1.5.2\n',
                     self.plan().replace('opus:x64-windows-static@1.5.2', 'opus:x64-windows-static@1.5.3'),
                     self.plan().replace('  * opus:x64-windows-static@1.5.2\n', ''),
                     self.plan().replace('will be built and installed:', 'are already installed:'),
                     self.plan() + 'The following packages will be removed:\n']:
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                codec.require_empty_plan(text)

    def test_every_missing_archive_is_reported_without_running_any_tool(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(codec.subprocess, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Missing LOCAL codec inputs') as error:
                codec.check_archives(Path(directory))
            self.assertIn('meson-1.8.2.tar.gz', str(error.exception))
            self.assertIn('aom-', str(error.exception))
            run.assert_not_called()

    def test_bad_archive_bytes_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / codec.PINS['archives'][0]['filename']
            path.write_bytes(b'corrupt-input')
            with self.assertRaisesRegex(RuntimeError, 'SHA512 mismatch'):
                codec.check_archives(path.parent)
            self.assertEqual(path.read_bytes(), b'corrupt-input')

    def test_local_archive_hash_checks_and_git_archive_presence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'source.tar.gz').write_bytes(b'synthetic-source')
            (root / 'codec-commit.tar.gz').write_bytes(b'synthetic-git-archive')
            pins = {'archives': [{'filename': 'source.tar.gz',
                      'sha512': hashlib.sha512(b'synthetic-source').hexdigest()}],
                    'git_archives': {'codec': 'commit'}}
            with patch.object(codec, 'PINS', pins):
                self.assertEqual(codec.check_archives(root),
                                 {'source.tar.gz': hashlib.sha256(b'synthetic-source').hexdigest()})

    def test_links_are_rejected_without_touching_the_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'preserved'
            target.write_bytes(b'prior-codecs')
            link = root / 'link'
            try:
                link.symlink_to(target)
            except OSError as error:
                self.skipTest('Synthetic symlink privilege unavailable: ' + str(error))
            with self.assertRaisesRegex(RuntimeError, 'Link/reparse'):
                codec.inventory(root)
            self.assertEqual(target.read_bytes(), b'prior-codecs')

    def test_inventory_detects_byte_changes_without_deleting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'codec.lib').write_bytes(b'original')
            before = codec.inventory(root)
            (root / 'codec.lib').write_bytes(b'modified')
            self.assertNotEqual(codec.inventory(root), before)
            self.assertTrue((root / 'codec.lib').exists())

    def tar(self, path, data, duplicate=False):
        with tarfile.open(path, 'w') as archive:
            for _ in range(2 if duplicate else 1):
                info = tarfile.TarInfo('source.c')
                info.size = len(data)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(data))

    def test_git_commit_filename_does_not_prove_archive_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.tar(root / 'expected.tar', b'pinned-source')
            self.tar(root / 'cached.tar', b'tampered-source')
            self.assertNotEqual(codec.tar_members(root / 'expected.tar'), codec.tar_members(root / 'cached.tar'))
            self.tar(root / 'cached.tar', b'pinned-source')
            self.assertEqual(codec.tar_members(root / 'expected.tar'), codec.tar_members(root / 'cached.tar'))

    def test_duplicate_tar_members_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'archive.tar'
            self.tar(path, b'source', duplicate=True)
            with self.assertRaisesRegex(RuntimeError, 'Duplicate archive member'):
                codec.tar_members(path)

    def evidence_fixture(self, root):
        for port in codec.PINS['compiled_ports']:
            for relative in ['installed/x64-windows-static/share/' + port + '/vcpkg_abi_info.txt',
                             'buildtrees/' + port + '/x64-rel/source.obj',
                             'packages/' + port + '_x64-windows-static/lib/' + port + '.lib']:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'synthetic-output')
            destination = root / 'installed/x64-windows-static/lib' / (port + '.lib')
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b'synthetic-output')

    def test_real_evidence_shape_requires_objects_abis_and_static_libraries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            started = time.time_ns()
            self.evidence_fixture(root)
            evidence = codec.require_compile_evidence(root, started)
            self.assertEqual(set(evidence), set(codec.PINS['compiled_ports']))
            self.assertTrue(evidence['aom']['objects_sha256'])

    def test_existing_library_or_exit_zero_cannot_stand_in_for_fresh_compilation(self):
        for mutation in ['missing-object', 'stale-object', 'missing-abi', 'missing-library', 'changed-installed-library']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.evidence_fixture(root)
                obj = root / 'buildtrees/aom/x64-rel/source.obj'
                if mutation == 'missing-object': obj.unlink()
                if mutation == 'stale-object': os.utime(obj, ns=(1, 1))
                if mutation == 'missing-abi': (root / 'installed/x64-windows-static/share/aom/vcpkg_abi_info.txt').unlink()
                if mutation == 'missing-library': (root / 'packages/aom_x64-windows-static/lib/aom.lib').unlink()
                if mutation == 'changed-installed-library': (root / 'installed/x64-windows-static/lib/aom.lib').write_bytes(b'changed')
                with self.assertRaises(RuntimeError):
                    codec.require_compile_evidence(root, time.time_ns())

    def test_verifier_accepts_codec_only_receipt_and_rejects_local_tool_or_abi_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = object.__new__(codec.native.Build)
            runner.vs = root / 'VS'
            version = runner.vs / 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            version.parent.mkdir(parents=True)
            version.write_text('local-version')
            compiler = runner.vs / 'VC/Tools/MSVC/local-version/bin/Hostx64/x64'
            runner.cmake = root / 'cmake.exe'
            tools = [compiler / 'cl.exe', compiler / 'link.exe', runner.cmake]
            for tool in tools:
                tool.parent.mkdir(parents=True, exist_ok=True)
                tool.write_bytes(b'local-tool')
            runner.source = runner.logs = root
            runner.tools = {'vcpkg': root / 'vcpkg'}
            runner.profile = {'input_sha256': {'vcpkg.json': 'manifest'}}
            runner.args = argparse.Namespace(source_commit='a' * 40)
            abi = root / 'vcpkg/installed/x64-windows-static/share/codec/vcpkg_abi_info.txt'
            abi.parent.mkdir(parents=True)
            abi.write_bytes(b'native-abi')
            receipt = root / 'receipt.json'
            runner.cfg = {'compiled_cache_receipt': str(receipt)}
            codec.native.save(receipt, {'status': 'PASS', 'scope': 'codecs-only',
                'inputs': runner.profile['input_sha256'], 'source_sha256': {},
                'codec_abi_sha256': {'share/codec/vcpkg_abi_info.txt': codec.native.digest(abi)},
                'tool_sha256': {str(t): codec.native.digest(t) for t in tools}})
            runner.require_verified_codecs()  # Run actual existing verifier.
            # A codec-only receipt must NEVER enable the 1.5 GiB warm-app reserve.
            self.assertFalse(runner.verified_warm_cache())
            tools[0].write_bytes(b'different-compiler')
            with self.assertRaisesRegex(RuntimeError, 'compiler/tool differs'):
                runner.require_verified_codecs()
            tools[0].write_bytes(b'local-tool')
            abi.write_bytes(b'different-abi')
            with self.assertRaisesRegex(RuntimeError, 'Installed codec/ABI differs'):
                runner.require_verified_codecs()

    def test_compile_failure_does_not_publish_a_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = object.__new__(codec.Bootstrap)
            runner.args = argparse.Namespace(source_commit='a' * 40)
            runner.codec_preflight = Mock(return_value=(root, root / 'Triplets'))
            runner.run = Mock(side_effect=RuntimeError('codec-compile: exit 1'))
            with self.assertRaisesRegex(RuntimeError, 'codec-compile: exit 1'):
                runner.compile_codecs()
            self.assertFalse((root / 'compiled-cache-receipt.json').exists())
            self.assertEqual(json.loads((root / '.rd-cl-codec-bootstrap.json').read_text())['phase'], 'COMPILING')

    def test_lock_is_released_before_removing_the_drive_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = object.__new__(codec.Bootstrap)
            runner.lock_path = Path(directory) / 'bootstrap.lock'
            runner.lock_token = 'owned-token'
            runner.lock_path.write_text(runner.lock_token)
            def release_alias(_):
                self.assertFalse(runner.lock_path.exists())
            with patch.object(codec.native.Build, 'close', autospec=True, side_effect=release_alias) as close:
                runner.close()
                close.assert_called_once_with(runner)
            self.assertIsNone(runner.lock_token)

    def test_changed_lock_is_preserved_but_owned_drive_is_still_released(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = object.__new__(codec.Bootstrap)
            runner.lock_path = Path(directory) / 'bootstrap.lock'
            runner.lock_token = 'original-token'
            runner.lock_path.write_text('changed-token')
            with patch.object(codec.native.Build, 'close', autospec=True) as close:
                with self.assertRaisesRegex(RuntimeError, 'Bootstrap lock changed'):
                    runner.close()
                close.assert_called_once_with(runner)
            self.assertEqual(runner.lock_path.read_text(), 'changed-token')

    def test_preflight_failure_stops_before_compile(self):
        runner = object.__new__(codec.Bootstrap)
        runner.codec_preflight = Mock(side_effect=RuntimeError('missing local input'))
        runner.run = Mock()
        with self.assertRaisesRegex(RuntimeError, 'missing local input'):
            runner.compile_codecs()
        runner.run.assert_not_called()

    def test_receipt_publication_and_derived_toolchain_use_the_real_existing_verifier(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runner = object.__new__(codec.Bootstrap)
            runner.output = runner.logs = base / 'report'
            runner.output.mkdir()
            runner.source = base / 'source'
            (runner.source / 'res/vcpkg/codec').mkdir(parents=True)
            (runner.source / 'res/vcpkg/codec/portfile.cmake').write_text('synthetic-recipe')
            (runner.source / 'vcpkg.json').write_text('synthetic-manifest')
            runner.overlays = {'res/vcpkg/codec/portfile.cmake': codec.native.digest(runner.source / 'res/vcpkg/codec/portfile.cmake')}
            runner.profile = {'input_sha256': {'vcpkg.json': codec.native.digest(runner.source / 'vcpkg.json')}}
            runner.vs = base / 'VS'
            version = runner.vs / 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            version.parent.mkdir(parents=True)
            version.write_text('synthetic-version')
            compiler = runner.vs / 'VC/Tools/MSVC/synthetic-version/bin/Hostx64/x64'
            compiler.mkdir(parents=True)
            for name in ['cl.exe', 'link.exe', 'lib.exe']:
                (compiler / name).write_bytes(b'synthetic-tool')
            runner.cmake = base / 'cmake.exe'
            runner.cmake.write_bytes(b'synthetic-cmake')
            original = base / 'preserved-vcpkg'
            original.mkdir()
            (original / 'vcpkg.exe').write_bytes(b'synthetic-vcpkg')
            (original / 'installed').mkdir()
            (original / 'installed/old-codec.lib').write_bytes(b'preserved-original-codec')
            runner.preserved_download_root = original / 'downloads'
            runner.preserved_download_root.mkdir()
            (runner.preserved_download_root / 'source.tar.gz').write_bytes(b'preserved-input')
            runner.original_installed = codec.inventory(original / 'installed')
            runner.original_downloads = codec.inventory(runner.preserved_download_root)
            runner.tools = {'vcpkg': original, 'vcpkg_cmake': runner.cmake}
            runner.initial_tools = runner.input_tools = runner.tool_hashes()
            root = base / 'new-vcpkg'
            root.mkdir()
            shutil.copy2(original / 'vcpkg.exe', root / 'vcpkg.exe')
            triplets = runner.output / 'Triplets'
            triplets.mkdir()
            (triplets / 'x64-windows-static.cmake').write_bytes(codec.TRIPLET)
            runner.cfg = {'paths': {'vcpkg': str(original)}, 'environment': {},
                          'compiled_cache_receipt': 'preserved-old-receipt-not-read.json'}
            toolchain = base / 'original-toolchain.json'
            codec.native.save(toolchain, runner.cfg)
            original_json_hash = codec.native.digest(toolchain)
            runner.args = argparse.Namespace(source_commit='a' * 40, toolchain=str(toolchain))
            runner.codec_preflight = Mock(return_value=(root, triplets))
            runner.cmake_version = 'synthetic CMake version'
            codec.native.save(runner.output / 'codec-preflight.json', {'status': 'synthetic-fixture'})
            codec.native.save(runner.logs / 'steps.json', [])

            def run(label, argv):
                if label == 'codec-compile':
                    self.evidence_fixture(root)
                    return 0, 'Compiler found: ' + str((compiler / 'cl.exe').resolve()) + '\n'
                self.assertEqual(label, 'codec-installed-plan')
                return 0, 'The following packages are already installed:\n'

            runner.run = Mock(side_effect=run)
            runner.compile_codecs()
            published = json.loads((runner.output / 'compiled-cache-receipt.json').read_text())
            derived = json.loads((runner.output / 'toolchain-codecs-local.json').read_text())
            self.assertEqual(published['status'], 'PASS')
            self.assertIn('codecs-only', published['scope'])
            self.assertNotIn('rust_version', published)
            self.assertEqual(derived['paths']['vcpkg'], str(root))
            self.assertEqual(derived['compiled_cache_receipt'], str(runner.output / 'compiled-cache-receipt.json'))
            self.assertEqual(codec.native.digest(toolchain), original_json_hash)
            self.assertEqual(codec.inventory(original / 'installed'), runner.original_installed)
            self.assertEqual(json.loads((runner.logs / 'verified-codecs.json').read_text())['status'], 'PASS')

    def test_linux_coordinator_is_rejected_before_toolchain_or_output_access(self):
        if os.name == 'nt':
            self.skipTest('Linux entrypoint guard is exercised on Linux only')
        result = subprocess.run([sys.executable, str(codec.SCRIPT), '--mode', 'Compile',
            '--toolchain', 'does-not-exist.json', '--source-commit', 'a' * 40,
            '--output-root', 'unused', '--codec-root', 'unused', '--existing-triplet', 'unused'],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Execute only on native Windows S2', result.stderr)


if __name__ == '__main__':
    unittest.main()
