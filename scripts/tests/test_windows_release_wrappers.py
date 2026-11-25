"""Execute the public release wrapper against a harmless capturing core stub."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest

PWSH = os.environ.get('RDCL_TEST_PWSH') or shutil.which('powershell.exe') or shutil.which('pwsh')
SCRIPTS = Path(__file__).resolve().parents[1]
HOST_ERROR = 'Run on an approved native Windows codec host'


@unittest.skipUnless(PWSH, 'Existing PowerShell required; set RDCL_TEST_PWSH')
class ReleaseWrapper(unittest.TestCase):
    def invoke(self, arguments):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        shutil.copyfile(SCRIPTS / 'windows-native-release.ps1', root / 'windows-native-release.ps1')
        (root / 'windows-native-build.ps1').write_text('''param(
[string]$Mode,[string]$Toolchain,[string]$SourceCommit,[string]$OutputRoot,
[switch]$ElevateProvision,[switch]$WithExe,[switch]$WithMsi)
$ErrorActionPreference='Stop'
if($Toolchain -eq 'fail'){throw 'synthetic native core failure'}
@{Mode=$Mode;SourceCommit=$SourceCommit;WithExe=[bool]$WithExe;WithMsi=[bool]$WithMsi} |
  ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputRoot 'captured.json')
''', encoding='utf-8')
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
            str(root / 'windows-native-release.ps1'), '-Toolchain', 'fail' if 'fail' in arguments else 'fixture',
            '-SourceCommit', 'a' * 40, '-OutputRoot', str(root),
            *[arg for arg in arguments if arg != 'fail']], capture_output=True, text=True, timeout=20)
        captured = root / 'captured.json'
        return result, json.loads(captured.read_text(encoding='utf-8-sig')) if captured.exists() else None

    def test_one_core_invocation_receives_installer_selection(self):
        for mode, switch in [('Build', '-WithExe'), ('Package', '-WithExe'),
                             ('Build', '-WithMsi'), ('PackageMsi', None)]:
            with self.subTest(mode=mode, switch=switch):
                result, value = self.invoke(['-Mode', mode] + ([switch] if switch else []))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(value['Mode'], mode)
                self.assertEqual(value['SourceCommit'], 'a' * 40)
                self.assertEqual(value['WithExe'], switch == '-WithExe')
                self.assertEqual(value['WithMsi'], switch == '-WithMsi')

    def test_invalid_installer_combinations_never_start_core(self):
        for args in [['-Mode', 'Build', '-WithExe', '-WithMsi'],
                     ['-Mode', 'Preflight', '-WithExe']]:
            result, value = self.invoke(args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(value)

    def test_native_wrapper_passes_packaging_flags_to_the_python_process(self):
        for switch, flag in [('-WithExe', '--with-exe'), ('-WithMsi', '--with-msi')]:
            with self.subTest(switch=switch), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                config = root / 'toolchain.json'
                config.write_text(json.dumps({'paths': {'python': sys.executable}}))
                probe = root / 'probe.ps1'
                probe.write_text('''param([string]$Core,[string]$Toolchain,[string]$OutputRoot,[string]$InstallerSwitch)
$ErrorActionPreference='Stop'
function Start-Process {
  param([string]$FilePath,[string]$ArgumentList,[switch]$PassThru,[string]$WindowStyle,
        [string]$RedirectStandardOutput,[string]$RedirectStandardError)
  $ArgumentList | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputRoot 'arguments.json')
  '' | Set-Content -LiteralPath $RedirectStandardOutput
  '' | Set-Content -LiteralPath $RedirectStandardError
  $process=[pscustomobject]@{Handle=1;ExitCode=0}
  $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {}
  return $process
}
$coreArgs=@{Mode='Build';Toolchain=$Toolchain;SourceCommit=('a'*40);OutputRoot=$OutputRoot}
if($InstallerSwitch -eq 'exe'){$coreArgs.WithExe=$true}else{$coreArgs.WithMsi=$true}
& $Core @coreArgs
''', encoding='utf-8')
                result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(probe),
                    '-Core', str(SCRIPTS / 'windows-native-build.ps1'), '-Toolchain', str(config),
                    '-OutputRoot', str(root), '-InstallerSwitch', 'exe' if switch == '-WithExe' else 'msi'],
                    capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = json.loads((root / 'arguments.json').read_text(encoding='utf-8-sig'))
                self.assertIn('"' + flag + '"', arguments)
                self.assertIn('"--mode" "Build"', arguments)

    def test_native_failure_propagates_without_packaging_success(self):
        result, value = self.invoke(['-Mode', 'Build', '-WithExe', 'fail'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('synthetic native core failure', result.stderr)
        self.assertIsNone(value)


@unittest.skipUnless(PWSH, 'Existing PowerShell required; set RDCL_TEST_PWSH')
class BootstrapWrapperHost(unittest.TestCase):
    def invoke(self, fixture=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wrapper = (SCRIPTS / 'windows-codec-bootstrap.ps1')
            if fixture is not None:
                wrapper = root / wrapper.name
                wrapper.write_text(fixture, encoding='utf-8')
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(wrapper),
                '-Mode', 'Preflight', '-Toolchain', str(root / 'missing-codec-toolchain.json'),
                '-SourceCommit', 'a' * 40, '-OutputRoot', str(root / 'unused-output'),
                '-CodecRoot', str(root / 'unused-codec'), '-ExistingTriplet', 'unused-triplet'],
                env={**os.environ, 'COMPUTERNAME': 'S2', 'OS': 'Windows_NT'},
                capture_output=True, text=True, timeout=30)
            self.assertFalse((root / 'unused-output').exists())
            self.assertFalse((root / 'unused-codec').exists())
            return result

    def assert_host_result(self, result, accepted):
        self.assertNotEqual(result.returncode, 0)
        if accepted:
            self.assertIn('missing-codec-toolchain.json', result.stderr)
            self.assertNotIn(HOST_ERROR, result.stderr)
        else:
            self.assertIn(HOST_ERROR, result.stderr)

    def test_actual_wrapper_ignores_environment_hostname(self):
        self.assert_host_result(self.invoke(), platform.node().upper() in {'S2', 'DESKTOP-5OTBBT7'})

    def test_wrapper_allowlist_and_platform_before_prerequisites(self):
        source = (SCRIPTS / 'windows-codec-bootstrap.ps1').read_text(encoding='utf-8')
        for platform_id, machine, wine, accepted in [
            ('Win32NT', 's2', False, True),
            ('Win32NT', 'DESKTOP-5OTBBT7', False, True),
            ('Win32NT', 'DESKTOP-IQ8ORD5', False, False),
            ('Win32NT', 'OTHER-PC', False, False),
            ('Win32NT', 'S2', True, False),
            ('Unix', 'S2', False, False),
        ]:
            with self.subTest(platform_id=platform_id, machine=machine, wine=wine):
                # Replace only the OS probes in a temporary fixture. On Windows
                # the positive cases also exercise the real ntdll export check.
                fixture = source.replace('[Environment]::OSVersion.Platform', '[PlatformID]::' + platform_id)
                fixture = fixture.replace('[Environment]::MachineName', "'" + machine + "'")
                if wine or os.name != 'nt':
                    fixture = fixture.replace('[RdClCodecHost]::IsNativeWindows()', '$false' if wine else '$true')
                self.assert_host_result(self.invoke(fixture), accepted)


if __name__ == '__main__':
    unittest.main()
