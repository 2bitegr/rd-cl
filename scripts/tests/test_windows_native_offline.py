"""Offline build guards; stdlib only, synthetic files, no external network."""
import importlib.util
import argparse
import contextlib
import io
import errno
import json
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys
import threading
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


build = load('native_build', 'windows-native-build.py')
msi = load('native_msi', 'windows-native-msi.py')


class OfflineGuards(unittest.TestCase):
    def test_missing_flutter_snapshot_never_bootstraps(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = object.__new__(build.Build)
            runner.tools = {'flutter': Path(directory)}
            runner.run = Mock()
            with self.assertRaisesRegex(RuntimeError, 'Missing cached dependency; downloads are disabled'):
                runner.flutter_command('build', 'windows')
            runner.run.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_missing_dart_dependency_never_runs_a_package_manager(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'flutter/.dart_tool/package_config.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'packages': []}))
            runner = object.__new__(build.Build)
            runner.source = root
            runner.run = Mock()
            with self.assertRaisesRegex(RuntimeError, 'Missing cached Dart package.*build_runner'):
                runner.run_dart_package('build_runner', ['build'])
            runner.run.assert_not_called()

    def test_dart_package_outside_owned_cache_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'flutter/.dart_tool/package_config.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'packages': [{'name': 'build_runner', 'rootUri': root.as_uri()}]}))
            runner = object.__new__(build.Build)
            runner.source = root
            runner.env = {'PUB_CACHE': str(root / 'cache')}
            runner.run = Mock()
            with self.assertRaisesRegex(RuntimeError, 'outside the reviewed cache'):
                runner.run_dart_package('build_runner', ['build'])
            runner.run.assert_not_called()

    def test_git_https_is_rejected_before_contacting_a_server(self):
        git = shutil.which('git')
        if git is None:
            self.skipTest('Existing Git executable unavailable; no installation attempted')
        env = build.offline_environment(os.environ)
        result = subprocess.run([git, 'ls-remote', 'https://127.0.0.1:9/unused'],
                                capture_output=True, env=env, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("transport 'https' not allowed", result.stderr)

    def test_inherited_network_settings_cannot_enable_downloads(self):
        original = {'CARGO_NET_OFFLINE': 'false', 'GIT_ALLOW_PROTOCOL': 'https',
                    'HTTPS_PROXY': 'http://example.invalid', 'NO_PROXY': '*'}
        guarded = build.offline_environment(original)
        self.assertEqual(original['CARGO_NET_OFFLINE'], 'false')
        self.assertEqual(guarded['CARGO_NET_OFFLINE'], 'true')
        self.assertEqual(guarded['GIT_ALLOW_PROTOCOL'], 'file')
        self.assertEqual(guarded['NO_PROXY'], 'localhost,127.0.0.1,::1')
        self.assertEqual(guarded['HTTPS_PROXY'], 'http://127.0.0.1:9')

    def test_local_test_harness_bypasses_the_blocked_external_proxy(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'local-fixture')

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = 'http://127.0.0.1:' + str(server.server_port)
            code = "import urllib.request; print(urllib.request.urlopen('" + url + "', timeout=5).read().decode())"
            result = subprocess.run([sys.executable, '-c', code], capture_output=True,
                                    text=True, env=build.offline_environment(os.environ), timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'local-fixture')
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_full_volume_stops_before_any_build_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = object.__new__(build.Build)
            runner.source = runner.logs = Path(directory)
            runner.args = argparse.Namespace(mode='Build')
            runner.require_cached_tools = Mock()
            with patch.object(build.shutil, 'disk_usage', return_value=argparse.Namespace(free=1024)):
                with self.assertRaisesRegex(RuntimeError, 'Insufficient free space before build'):
                    runner.preflight()
            runner.require_cached_tools.assert_not_called()
            self.assertEqual(json.loads((runner.logs / 'space-floor.json').read_text())['free_bytes'], 1024)

    def test_failed_json_save_preserves_previous_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / 'receipt.json'
            build.save(receipt, {'status': 'previous'})
            with patch.object(build.os, 'replace', side_effect=OSError(errno.ENOSPC, 'simulated full volume')):
                with self.assertRaises(OSError):
                    build.save(receipt, {'status': 'new'})
            self.assertEqual(json.loads(receipt.read_text()), {'status': 'previous'})
            self.assertEqual(list(Path(directory).iterdir()), [receipt])

    def test_constructor_failure_still_releases_acquired_drive(self):
        def interrupted(runner, args):
            runner.drive_created = True
            raise OSError(errno.ENOSPC, 'initialization log directory failed')

        with patch.object(build.Build, '_initialize', interrupted):
            with patch.object(build.Build, 'close', autospec=True) as release:
                with self.assertRaisesRegex(OSError, 'initialization log directory failed'):
                    build.Build(argparse.Namespace())
                release.assert_called_once()
                self.assertTrue(release.call_args.args[0].drive_created)

    def test_reporting_failure_keeps_original_error_visible(self):
        runner = argparse.Namespace(logs=Path('synthetic-logs'), args=argparse.Namespace(mode='Build'))
        stderr = io.StringIO()
        with patch.object(build, 'save', side_effect=OSError(errno.ENOSPC, 'full log disk')):
            with contextlib.redirect_stderr(stderr):
                code = build.report_failure(runner, RuntimeError('missing exact cached crate'))
        self.assertEqual(code, 1)
        self.assertEqual(stderr.getvalue().splitlines()[0], 'missing exact cached crate')
        self.assertIn('Could not write result.json:', stderr.getvalue())

    def test_vcpkg_accepts_only_an_already_installed_plan(self):
        build.require_installed_vcpkg_plan('Compiler found: synthetic\n'
            'The following packages are already installed:\n    opus:x64-windows-static@1.5.2\n')

    def test_vcpkg_rejects_partial_install_and_rebuild_plans(self):
        for action in ['will be built and installed:', 'will be rebuilt:', 'will be removed:']:
            with self.subTest(action=action):
                with self.assertRaisesRegex(RuntimeError, 'existing installations are preserved'):
                    build.require_installed_vcpkg_plan('The following packages are already installed:\n'
                        '    opus:x64-windows-static@1.5.2\nThe following packages ' + action)

    def test_vcpkg_unknown_output_does_not_authorize_installation(self):
        with self.assertRaisesRegex(RuntimeError, 'unknown plan'):
            build.require_installed_vcpkg_plan('Unknown future vcpkg output')

    def test_unverified_compiler_stops_codec_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = root / 'VS/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            version.parent.mkdir(parents=True)
            version.write_text('synthetic')
            receipt = root / 'receipt.json'
            receipt.write_text(json.dumps({'status': 'PASS', 'inputs': {'vcpkg.json': 'manifest'},
                'codec_abi_sha256': {'lib/codec.lib': 'hash'}, 'tool_sha256': {}}))
            runner = object.__new__(build.Build)
            runner.cfg = {'compiled_cache_receipt': str(receipt)}
            runner.profile = {'input_sha256': {'vcpkg.json': 'manifest'}}
            runner.vs = root / 'VS'
            runner.tools = {}
            runner.cmake = root / 'cmake.exe'
            with self.assertRaisesRegex(RuntimeError, 'compiler/tool differs'):
                runner.require_verified_codecs()

    def test_matching_codecs_can_be_reused_after_application_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version = root / 'VS/VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            version.parent.mkdir(parents=True)
            version.write_text('synthetic')
            tools = [root / 'VS/VC/Tools/MSVC/synthetic/bin/Hostx64/x64/cl.exe',
                     root / 'VS/VC/Tools/MSVC/synthetic/bin/Hostx64/x64/link.exe', root / 'cmake.exe']
            for tool in tools:
                tool.parent.mkdir(parents=True, exist_ok=True)
                tool.write_bytes(b'owned-tool')
            library = root / 'vcpkg/installed/x64-windows-static/lib/codec.lib'
            library.parent.mkdir(parents=True)
            library.write_bytes(b'owned-codec')
            receipt = root / 'receipt.json'
            receipt.write_text(json.dumps({'status': 'PASS', 'source_commit': 'previous-app',
                'inputs': {'vcpkg.json': 'manifest'}, 'source_sha256': {},
                'codec_abi_sha256': {'lib/codec.lib': build.digest(library)},
                'tool_sha256': {str(t): build.digest(t) for t in tools}}))
            runner = object.__new__(build.Build)
            runner.cfg = {'compiled_cache_receipt': str(receipt)}
            runner.profile = {'input_sha256': {'vcpkg.json': 'manifest'}, 'source_commit': 'new-app'}
            runner.vs = root / 'VS'
            runner.tools = {'vcpkg': root / 'vcpkg'}
            runner.cmake = root / 'cmake.exe'
            runner.source = runner.logs = root
            runner.require_verified_codecs()
            self.assertEqual(json.loads((root / 'verified-codecs.json').read_text())['status'], 'PASS')

    def test_nuget_has_only_local_source_even_with_xml_sensitive_path(self):
        cache = Path('existing cache & tools')
        root = ET.fromstring(msi.local_nuget_config(cache))
        self.assertIsNotNone(root.find('packageSources/clear'))
        sources = root.findall('packageSources/add')
        self.assertEqual(len(sources), 1)
        self.assertEqual(sources[0].attrib['value'], str(cache / 'packages'))
        self.assertNotIn('https://', ET.tostring(root, encoding='unicode'))


if __name__ == '__main__':
    unittest.main()
