"""Real local Git fixtures for offline builtin-registry object closure."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('native_objects', Path(__file__).resolve().parents[1] / 'windows-native-build.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


@unittest.skipUnless(shutil.which('git'), 'Existing Git required; no installation')
class ObjectClosure(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = native.offline_environment(os.environ)
        self.calls = []
        self.command('init', '-q')
        self.command('config', 'user.name', 'Local fixture')
        self.command('config', 'user.email', 'fixture@example.invalid')
        self.write('unrelated', 'parent history is intentionally unavailable')
        self.command('add', '.')
        self.command('commit', '-qm', 'parent')
        self.parent = self.command('rev-parse', 'HEAD').strip()
        self.write('ports/example/nested/patch.txt', 'local recipe input')
        self.write('ports/example/vcpkg.json', '{"name":"example","version":"1"}')
        self.command('add', '.')
        self.tree = self.command('write-tree').strip()
        self.tree = self.command('rev-parse', self.tree + ':ports/example').strip()
        # Keep the selected override tree outside HEAD's current recipe snapshot.
        self.write('ports/example/nested/patch.txt', 'different current recipe')
        self.pin = {'baseline': '1', 'port-version': 0}
        self.write('versions/baseline.json', json.dumps({'default': {'example': self.pin}}))
        self.write('versions/e-/example.json', json.dumps({'versions': [
            {'version': '1', 'port-version': 0, 'git-tree': self.tree}]}))
        self.command('add', '.')
        self.command('commit', '-qm', 'pinned snapshot')
        self.head = self.command('rev-parse', 'HEAD').strip()
        self.write('.git/shallow', self.head + '\n')
        # Prove missing ancestry is immaterial, not merely the shallow flag.
        self.remove_object(self.parent)
        self.profile = {'vcpkg_commit': self.head, 'vcpkg_override_trees': {'example': self.tree}}
        self.ports = {'example': self.pin}

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def command(self, *args):
        result = subprocess.run(['git', *args], cwd=self.root, env=self.env,
                                capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout

    def git(self, label, *args):
        self.calls.append(args)
        return 0, self.command(*args)

    def remove_object(self, oid):
        path = self.root / '.git/objects' / oid[:2] / oid[2:]
        # Git for Windows may mark loose objects read-only. This fixture owns
        # this exact disposable object; never change real cache permissions.
        path.chmod(0o600)
        path.unlink()

    def audit(self):
        return native.require_vcpkg_objects(self.git, self.profile, self.ports)

    def test_shallow_complete_selected_closure_passes_without_parent_or_fetch(self):
        self.assertEqual(self.command('rev-parse', '--is-shallow-repository').strip(), 'true')
        self.assertEqual(self.audit(), {'example': self.tree})
        self.assertFalse(any(args[0] in ['fetch', 'pull', 'clone'] for args in self.calls))
        # These are the Git operations used by builtin baseline/port extraction.
        self.command('show', self.head + ':versions/baseline.json')
        subprocess.run(['git', 'archive', self.tree], cwd=self.root, env=self.env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True, timeout=10)

    def test_full_repository_uses_the_same_object_guard(self):
        (self.root / '.git/shallow').unlink()
        self.assertEqual(self.audit(), {'example': self.tree})

    def test_missing_baseline_commit_or_metadata_or_recipe_object_fails(self):
        # Every case starts with its own complete fixture.
        for expression in [self.head, self.head + ':versions/baseline.json',
                           self.head + ':versions/e-/example.json', self.tree,
                           self.tree + ':nested', self.tree + ':nested/patch.txt']:
            with self.subTest(object=expression):
                oid = self.command('rev-parse', expression).strip()
                path = self.root / '.git/objects' / oid[:2] / oid[2:]
                original = path.read_bytes()
                self.remove_object(oid)
                try:
                    with self.assertRaises((RuntimeError, KeyError, ValueError)):
                        self.audit()
                finally:
                    path.write_bytes(original)

    def test_missing_promisor_blob_does_not_attempt_lazy_fetch(self):
        oid = self.command('rev-parse', self.tree + ':nested/patch.txt').strip()
        self.remove_object(oid)
        self.command('config', 'remote.origin.url', 'https://127.0.0.1:9/forbidden')
        self.command('config', 'remote.origin.promisor', 'true')
        self.command('config', 'extensions.partialClone', 'origin')
        trace = self.root / 'trace.log'
        self.env['GIT_TRACE'] = str(trace)
        with self.assertRaises(RuntimeError):
            self.audit()
        self.assertNotIn('fetch', trace.read_text())
        self.assertFalse((self.root / '.git/FETCH_HEAD').exists())

    def test_changed_working_versions_are_rejected(self):
        self.write('versions/e-/example.json', '{"versions":[]}')
        with self.assertRaises(RuntimeError):
            self.audit()

    def test_receipt_verified_overlay_bypasses_builtin_recipe_history(self):
        self.profile['vcpkg_override_trees'] = {}
        self.ports['example'] = {'baseline': '2', 'port-version': 0}
        overlays = {'example': {'name': 'example', 'version': '2'}}
        self.remove_object(self.tree)
        self.assertEqual(native.require_vcpkg_objects(self.git, self.profile, self.ports, overlays), {})
        overlays['example']['version'] = 'wrong'
        with self.assertRaisesRegex(RuntimeError, 'overlay version differs'):
            native.require_vcpkg_objects(self.git, self.profile, self.ports, overlays)

    def test_override_tree_mismatch_is_rejected(self):
        self.profile['vcpkg_override_trees']['example'] = 'a' * 40
        with self.assertRaisesRegex(RuntimeError, 'override tree mismatch'):
            self.audit()

    def test_unreviewed_baseline_version_is_rejected(self):
        self.profile['vcpkg_override_trees'] = {}
        self.ports['example'] = {'baseline': '2', 'port-version': 0}
        with self.assertRaisesRegex(RuntimeError, 'baseline version differs'):
            self.audit()


class IntegrationGuards(unittest.TestCase):
    def test_installed_plan_requires_exact_versions_triplet_and_closure(self):
        ports = {'example': {'baseline': '1', 'port-version': 0}}
        prefix = 'The following packages are already installed:\n'
        native.require_installed_vcpkg_plan(prefix + '  example:x64-windows-static@1\n', ports)
        for body in ['', '  example:x64-windows-static@2\n', '  example:x64-windows@1\n',
                     '  example:x64-windows-static@1\n  extra:x64-windows-static@1\n']:
            with self.subTest(body=body), self.assertRaises(RuntimeError):
                native.require_installed_vcpkg_plan(prefix + body, ports)

    def test_missing_objects_stop_before_engine_or_package_tools(self):
        runner = object.__new__(native.Build)
        runner.developer_environment = Mock()
        runner.require_verified_codecs = Mock()
        runner.env = {}
        runner.args = type('Args', (), {'source_commit': 'a' * 40})()
        runner.profile = {'vcpkg_commit': 'b' * 40}
        runner.source = Path('unused-source')
        runner.tools = {'vcpkg': Path('unused-local-root')}
        runner.run = Mock()
        runner.git = Mock(side_effect=[(0, json.dumps({'ports': {'example': {}}})),
                                       RuntimeError('missing local baseline object')])
        with self.assertRaisesRegex(RuntimeError, 'missing local baseline object'):
            runner.provision()
        runner.require_verified_codecs.assert_called_once()
        runner.run.assert_not_called()

    def test_invalid_receipt_stops_before_object_audit_or_provisioning(self):
        runner = object.__new__(native.Build)
        runner.developer_environment = Mock()
        runner.env = {}
        runner.require_verified_codecs = Mock(side_effect=RuntimeError('invalid genuine evidence'))
        runner.git = Mock()
        runner.run = Mock()
        with self.assertRaisesRegex(RuntimeError, 'invalid genuine evidence'):
            runner.provision()
        runner.git.assert_not_called()
        runner.run.assert_not_called()
        self.assertEqual(runner.env['GIT_NO_LAZY_FETCH'], '1')
        self.assertEqual(runner.env['GIT_NO_REPLACE_OBJECTS'], '1')


if __name__ == '__main__':
    unittest.main()
