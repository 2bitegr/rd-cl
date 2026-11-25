"""Windows synthetic recovery fixtures; never create product tasks or services."""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
SOURCE = SCRIPTS.parent / 'res' / 'office-update.ps1'
PWSH = os.environ.get('RDCL_TEST_PWSH') or shutil.which('powershell.exe')


@unittest.skipUnless(os.name == 'nt' and PWSH, 'Native Windows PowerShell fixture required')
class OfficeSilentRecovery(unittest.TestCase):
    def test_native_gui_core_process_contract(self):
        base_python = Path(getattr(sys, '_base_executable', sys.executable))
        gui_python = Path(os.environ.get('RDCL_TEST_GUI_PYTHON') or
                          base_python.with_name('pythonw.exe'))
        self.assertTrue(gui_python.is_file(), 'Existing native pythonw.exe is required')
        with tempfile.TemporaryDirectory(prefix='rdcl-core-process-report-') as directory:
            output = Path(directory) / 'result.json'
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
                str(SCRIPTS / 'tests' / 'test-office-update-core.ps1'),
                '-Source', str(SOURCE), '-GuiPython', str(gui_python),
                '-Output', str(output)], capture_output=True, text=True, timeout=150)
            report = json.loads(output.read_text(encoding='utf-8-sig')) if output.is_file() else None
            evidence = result.stdout + result.stderr + json.dumps({'native_core_process_fixture': report})
            self.assertEqual(result.returncode, 0, evidence)
            self.assertIsNotNone(report, evidence)
            self.assertEqual(report['status'], 'PASS')
            self.assertEqual(report['tests'], 13)
            self.assertEqual(report['source_sha256'], hashlib.sha256(SOURCE.read_bytes()).hexdigest())
            self.assertEqual(report['gui_subsystem'], 2)
            for field in ['product_installation', 'service_changes', 'network']:
                self.assertEqual(report[field], 'NOT_RUN')
            self.assertEqual(report['nas'], 'NOT_TOUCHED')
            print(json.dumps({'native_core_process_fixture': report}, sort_keys=True))

    def test_production_barrier_check_reads_protected_acl(self):
        source = (SCRIPTS.parent / 'src' / 'office_update.rs').read_text()
        verifier = re.search(r'let check = r#"(.*?)"#;', source, re.S)
        self.assertIsNotNone(verifier)
        self.assertIn('OpenExisting(', verifier[1])
        # Keep the fixture readable. The child uses the same plain -Command
        # invocation as production; only the isolated event/owner are substituted.
        self.assertNotIn("\n'@", verifier[1])
        harness = r"""
$ErrorActionPreference = 'Stop'
$newName = 'Local\rdcl-barrier-test-' + [guid]::NewGuid().ToString('N')
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$rights = [Security.AccessControl.EventWaitHandleRights]
$security = [Security.AccessControl.EventWaitHandleSecurity]::new()
$security.SetOwner($sid)
$security.SetAccessRuleProtection($true, $false)
$security.AddAccessRule([Security.AccessControl.EventWaitHandleAccessRule]::new($sid, $rights::FullControl, 'Allow'))
$created = $false
$event = [Threading.EventWaitHandle]::new($false, 'ManualReset', $newName, [ref]$created, $security)
$checks = 0
try {
    if (!$created) { throw 'Test event already existed' }
    $source = @'
__VERIFIER__
'@
    $source = $source.Replace('Global\ExantasRdclUpdateBarrier', $newName)
    $source = $source.Replace("-ne 'S-1-5-18'", ("-ne '" + $sid.Value + "'"))
    $source = $source.Replace("@('S-1-5-18','S-1-5-32-544')",
        ("@('S-1-5-18','S-1-5-32-544','" + $sid.Value + "')"))
    $ps = Join-Path $PSHOME 'powershell.exe'
    & $ps -NoProfile -NonInteractive -Command $source
    if ($LASTEXITCODE -ne 0) { throw 'Protected event ACL could not be read' }
    $checks++

    $world = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
    $security.AddAccessRule([Security.AccessControl.EventWaitHandleAccessRule]::new($world, $rights::Modify, 'Allow'))
    $event.SetAccessControl($security)
    & $ps -NoProfile -NonInteractive -Command $source
    if ($LASTEXITCODE -ne 1) { throw 'Verifier accepted an event writable by everyone' }
    $checks++
} finally {
    $event.Dispose()
}
if ($checks -ne 2) { throw 'Barrier ACL checks incomplete' }
[Console]::WriteLine('barrier_acl_cases=2')
""".replace('__VERIFIER__', verifier[1])
        with tempfile.TemporaryDirectory(prefix='rdcl-barrier-test-') as directory:
            script = Path(directory) / 'barrier-fixture.ps1'
            script.write_text(harness, encoding='utf-8')
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
                str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr.strip(), '', result.stderr)
        self.assertIn('barrier_acl_cases=2', result.stdout)

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
