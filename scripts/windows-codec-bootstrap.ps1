param(
    [Parameter(Mandatory=$true)][ValidateSet('Preflight','Compile')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Toolchain,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$CodecRoot,
    [Parameter(Mandatory=$true)][string]$ExistingTriplet
)
$ErrorActionPreference = 'Stop'
$hostError = 'Run on an approved native Windows codec host (S2 or DESKTOP-5OTBBT7). No elevation, downloads or S1 receipt import.'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    [Environment]::MachineName -notin @('S2', 'DESKTOP-5OTBBT7')) {
    throw $hostError
}
if (-not ('RdClCodecHost' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RdClCodecHost {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string name);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    public static bool IsNativeWindows() {
        var ntdll = GetModuleHandle("ntdll.dll");
        return ntdll != IntPtr.Zero && GetProcAddress(ntdll, "wine_get_version") == IntPtr.Zero;
    }
}
'@
}
if (-not [RdClCodecHost]::IsNativeWindows()) {
    throw $hostError
}
$config = Get-Content -LiteralPath $Toolchain -Raw | ConvertFrom-Json
$python = $config.paths.python
if (!(Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Existing native Python venv is required.' }
$allowed = [IO.Path]::GetFullPath((Join-Path $config.artifact_root 'Builds\rd-cl')) + '\'
if (![IO.Path]::GetFullPath($OutputRoot).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must be within this artifact root Builds\rd-cl.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$run = [Guid]::NewGuid().ToString('N')
$stdout = Join-Path $OutputRoot "codec-wrapper-$run.out.log"
$stderr = Join-Path $OutputRoot "codec-wrapper-$run.err.log"
$values = @((Join-Path $PSScriptRoot 'windows-codec-bootstrap.py'), '--mode', $Mode,
    '--toolchain', $Toolchain, '--source-commit', $SourceCommit, '--output-root', $OutputRoot,
    '--codec-root', $CodecRoot, '--existing-triplet', $ExistingTriplet)
$quoted = foreach ($value in $values) {
    if ($value -match '["\r\n]' -or $value.EndsWith('\')) { throw 'Unsupported Windows argument.' }
    '"' + $value + '"'
}
$process = Start-Process -FilePath $python -ArgumentList ($quoted -join ' ') -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$null = $process.Handle
$process.WaitForExit()
if ($null -eq $process.ExitCode) { throw 'Native codec process exit code was not confirmed.' }
Get-Content -LiteralPath $stdout
if ($process.ExitCode -ne 0) {
    Get-Content -LiteralPath $stderr
    throw "Codec bootstrap $Mode exited $($process.ExitCode). Existing codecs/deliveries must be retained."
}
