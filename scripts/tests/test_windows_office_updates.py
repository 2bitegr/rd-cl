"""Windows synthetic recovery fixtures; never create product tasks or services."""
import base64
import hashlib
import json
import os
import re
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
    def test_production_barrier_check_reads_protected_acl(self):
        source = (SCRIPTS.parent / 'src' / 'office_update.rs').read_text()
        verifier = re.search(r'let check = r#"(.*?)"#;', source, re.S)
        self.assertIsNotNone(verifier)
        self.assertIn('OpenExisting(', verifier[1])
        # Exercise the production verifier with a unique session-local event.
        check = base64.b64encode(verifier[1].encode('utf-8')).decode('ascii')
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
try {
    if (!$created) { throw 'Test event already existed' }
    $source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__VERIFIER__'))
    $source = $source.Replace('Global\ExantasRdclUpdateBarrier', $newName)
    $source = $source.Replace("-ne 'S-1-5-18'", ("-ne '" + $sid.Value + "'"))
    $source = $source.Replace("@('S-1-5-18','S-1-5-32-544')",
        ("@('S-1-5-18','S-1-5-32-544','" + $sid.Value + "')"))
    $command = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
    $ps = Join-Path $PSHOME 'powershell.exe'
    $process = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $command) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Protected event ACL could not be read' }

    $world = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
    $security.AddAccessRule([Security.AccessControl.EventWaitHandleAccessRule]::new($world, $rights::Modify, 'Allow'))
    $event.SetAccessControl($security)
    $process = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $command) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 1) { throw 'Verifier accepted an event writable by everyone' }
} finally {
    $event.Dispose()
}
""".replace('__VERIFIER__', check)
        command = base64.b64encode(harness.encode('utf-16-le')).decode('ascii')
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-EncodedCommand',
            command], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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
