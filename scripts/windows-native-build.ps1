param(
    [Parameter(Mandatory=$true)][ValidateSet('Preflight','Provision','Build','Package')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Toolchain,
    [Parameter(Mandatory=$true)][string]$SourceCommit,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [switch]$ElevateProvision
)
$ErrorActionPreference = 'Stop'
if ($ElevateProvision) {
    if ($Mode -ne 'Provision') { throw 'Elevation is limited to the prerequisite Provision mode.' }
    $values = @('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-Mode','Provision',
                '-Toolchain',$Toolchain,'-SourceCommit',$SourceCommit,'-OutputRoot',$OutputRoot)
    $quoted = foreach ($value in $values) {
        if ($value -match '["\r\n]' -or $value.EndsWith('\')) { throw 'Unsupported Windows argument.' }
        '"' + $value + '"'
    }
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -ArgumentList ($quoted -join ' ') -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Elevated Provision exited $($process.ExitCode)." }
    return
}
$config = Get-Content -LiteralPath $Toolchain -Raw | ConvertFrom-Json
$python = $config.paths.python
if (!(Test-Path -LiteralPath $python)) { throw 'The reviewed native Python venv is missing.' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$run = [Guid]::NewGuid().ToString('N')
$stdout = Join-Path $OutputRoot "wrapper-$run.out.log"
$stderr = Join-Path $OutputRoot "wrapper-$run.err.log"
# Use the native Windows argument quoting contract; reject embedded quote/newline.
$values = @((Join-Path $PSScriptRoot 'windows-native-build.py'), '--mode', $Mode,
            '--toolchain', $Toolchain, '--source-commit', $SourceCommit, '--output-root', $OutputRoot)
$quoted = foreach ($value in $values) {
    if ($value -match '["\r\n]' -or $value.EndsWith('\')) { throw 'Unsupported Windows argument.' }
    '"' + $value + '"'
}
$process = Start-Process -FilePath $python -ArgumentList ($quoted -join ' ') -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$null = $process.Handle
$process.WaitForExit()
if ($null -eq $process.ExitCode) { throw 'Native process exit code was not confirmed.' }
Get-Content -LiteralPath $stdout
if ($process.ExitCode -ne 0) {
    Get-Content -LiteralPath $stderr
    throw "Native build mode $Mode exited $($process.ExitCode). See $OutputRoot."
}
