"""Portable parser/provider checks; native UAC/SCM acceptance remains separate."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
PWSH = os.environ.get('RDCL_TEST_PWSH') or shutil.which('pwsh')


class InstallReadiness(unittest.TestCase):
    @unittest.skipUnless(PWSH, 'PowerShell required for real diagnostic functions')
    def test_shared_diagnostic_functions_with_synthetic_windows_providers(self):
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT / 'scripts/tests/test-office-readiness.ps1'),
            '-Source', str(ROOT / 'res/office-readiness.ps1')],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS:', result.stdout)

    def test_worker_uses_same_reboot_implementation_and_embeds_library_after_param(self):
        worker = (ROOT / 'res/office-update.ps1').read_text()
        native = (ROOT / 'src/office_update.rs').read_text()
        self.assertIn('$reboot = @(Get-OfficeRebootReasons).Count -gt 0', worker)
        self.assertNotIn('PendingFileRenameOperations', worker)
        self.assertLess(worker.index('param('), worker.index('# OFFICE_READINESS_LIBRARY'))
        self.assertIn('SCRIPT.replace("# OFFICE_READINESS_LIBRARY",', native)


if __name__ == '__main__':
    unittest.main()
