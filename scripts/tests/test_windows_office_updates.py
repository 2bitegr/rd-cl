"""Windows synthetic recovery fixtures; never create product tasks or services."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
SOURCE = SCRIPTS.parent / 'res' / 'office-update.ps1'
PWSH = os.environ.get('RDCL_TEST_PWSH') or shutil.which('powershell.exe')


@unittest.skipUnless(os.name == 'nt' and PWSH, 'Native Windows PowerShell fixture required')
class OfficeSilentRecovery(unittest.TestCase):
    def test_atomic_replacement_recovery_and_lost_responses(self):
        with tempfile.TemporaryDirectory(prefix='rdcl-update-test-report-') as directory:
            output = Path(directory) / 'result.json'
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
                str(SCRIPTS / 'tests' / 'test-office-update.ps1'), '-Source', str(SOURCE),
                '-Output', str(output)], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(output.read_text(encoding='utf-8-sig'))
            self.assertEqual(report['status'], 'PASS')
            self.assertGreaterEqual(report['tests'], 38)
            self.assertEqual(report['source_sha256'], hashlib.sha256(SOURCE.read_bytes()).hexdigest())
            for field in ['product_installation', 'service_changes', 'network']:
                self.assertEqual(report[field], 'NOT_RUN')
            print(json.dumps({'native_fixture': report}, sort_keys=True))


if __name__ == '__main__':
    unittest.main()
