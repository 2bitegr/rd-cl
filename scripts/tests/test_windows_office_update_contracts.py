"""Typecheck the real updater functions with pinned, already compiled native deps.

This optional fast S1/S2 regression probe is not a product build. The barrier
function is compiled but never called; envelope tests use disposable keys/files.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUSTC = os.environ.get('RDCL_TEST_RUSTC')
DEPS = os.environ.get('RDCL_TEST_NATIVE_DEPS')


def production_function(source, name, next_name):
    return source[source.index('fn ' + name + '('):source.index('\n' + next_name, source.index('fn ' + name + '('))]


@unittest.skipUnless(os.name == 'nt' and RUSTC and DEPS,
                     'Explicit pinned native Rust/dependency cache required')
class OfficeUpdateNativeContracts(unittest.TestCase):
    def test_actual_envelope_and_barrier_api_contracts(self):
        version = subprocess.check_output([RUSTC, '--version'], text=True)
        self.assertTrue(version.startswith('rustc 1.75.0 '), version)
        deps = Path(DEPS).resolve(strict=True)
        fingerprints = deps.parent / '.fingerprint'
        lock = tomllib.loads((ROOT / 'Cargo.lock').read_text())
        expected = {'anyhow':'1.0.98', 'sodiumoxide':'0.2.7', 'serde_json':'1.0.118',
                    'chrono':'0.4.41', 'winapi':'0.3.9'}
        arguments, recorded = [], {}
        for crate, wanted in expected.items():
            self.assertTrue(any(p['name'] == crate and p['version'] == wanted for p in lock['package']))
            candidates = []
            for metadata in sorted(fingerprints.glob(crate + '-*/lib-' + crate + '.json')):
                data = json.loads(metadata.read_text())
                stem = metadata.parent.name
                rlib = deps / ('lib' + stem + '.rlib')
                depfile = deps / (stem + '.d')
                if not rlib.is_file() or not depfile.is_file():
                    continue
                if crate + '-' + wanted not in depfile.read_text(errors='replace'):
                    continue
                if crate == 'winapi' and '"sddl"' not in data['features']:
                    continue
                candidates.append(rlib)
            self.assertTrue(candidates, 'Missing pinned compiled cache: ' + crate)
            selected = candidates[0]
            arguments += ['--extern', crate + '=' + str(selected)]
            recorded[crate] = {'path':str(selected), 'sha256':hashlib.sha256(selected.read_bytes()).hexdigest()}
        source = (ROOT / 'src/office_update.rs').read_text()
        fixture = Path(__file__).with_name('fixtures') / 'office_update_envelope_probe.rs'
        with tempfile.TemporaryDirectory(prefix='rdcl-native-contract-') as folder:
            folder = Path(folder)
            (folder / 'office_update_policy.rs').write_bytes((ROOT / 'src/office_update_policy.rs').read_bytes())
            code = fixture.read_text().replace('// PRODUCTION_FUNCTIONS',
                production_function(source, 'verify_envelope', 'fn wide') + '\n' +
                production_function(source, 'wide', 'pub fn blocked') + '\n' +
                production_function(source, 'create_barrier', 'pub fn start_service_worker'))
            probe, exe = folder / 'probe.rs', folder / 'probe.exe'
            probe.write_text(code)
            command = [RUSTC, '--edition=2021', '-C', 'panic=abort', str(probe), '-L', 'dependency=' + str(deps),
                       *arguments, '-o', str(exe)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            env = dict(os.environ, RDCL_NATIVE_FIXTURE=str(folder))
            result = subprocess.run([str(exe), '--nocapture'], capture_output=True, text=True, timeout=30, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout)
            print(json.dumps({'updater_source_sha256':hashlib.sha256((ROOT/'src/office_update.rs').read_bytes()).hexdigest(),
                              'deps':recorded, 'product_build':'NOT_RUN', 'barrier_execution':'NOT_RUN',
                              'production_keys':'NOT_USED', 'network':'NOT_RUN'}, sort_keys=True))


if __name__ == '__main__':
    unittest.main()
