param(
    [ValidateSet('Preflight','Provision','Build','Package','PackageExe','PackageMsi')][string]$Mode = 'Build',
    [Parameter(Mandatory=$true)][string]$Toolchain,
    [Parameter(Mandatory=$true)][string]$SourceCommit,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [switch]$ElevateProvision,
    [switch]$WithExe,
    [switch]$WithMsi
)
$ErrorActionPreference = 'Stop'
if ($WithExe -and $Mode -notin @('Build','Package')) { throw 'WithExe applies only after Build/Package.' }
if ($WithExe -and $WithMsi) { throw 'Choose one installer format.' }
if ($WithMsi -and $Mode -notin @('Build','Package')) { throw 'WithMsi applies only after Build/Package.' }
if ($Mode -eq 'PackageMsi' -and $ElevateProvision) { throw 'Installer compilation does not elevate.' }
if ($Mode -ne 'PackageMsi') {
    $core = @{Mode=$Mode;Toolchain=$Toolchain;SourceCommit=$SourceCommit;OutputRoot=$OutputRoot}
    if ($ElevateProvision) { $core.ElevateProvision = $true }
    & (Join-Path $PSScriptRoot 'windows-native-build.ps1') @core
}
if ($WithMsi -or $Mode -eq 'PackageMsi') {
    $config = Get-Content -LiteralPath $Toolchain -Raw | ConvertFrom-Json
    $values = @((Join-Path $PSScriptRoot 'windows-native-msi.py'), '--toolchain', $Toolchain,
                '--source-commit', $SourceCommit, '--output-root', $OutputRoot)
    $quoted = foreach ($value in $values) {
        if ($value -match '["\r\n]' -or $value.EndsWith('\')) { throw 'Unsupported Windows argument.' }
        '"' + $value + '"'
    }
    $id = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $OutputRoot "msi-wrapper-$id.out.log"
    $stderr = Join-Path $OutputRoot "msi-wrapper-$id.err.log"
    $process = Start-Process -FilePath $config.paths.python -ArgumentList ($quoted -join ' ') `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $process.Handle
$process.WaitForExit()
if ($null -eq $process.ExitCode) { throw 'Native process exit code was not confirmed.' }
Get-Content -LiteralPath $stdout
    if ($process.ExitCode -ne 0) {
        Get-Content -LiteralPath $stderr
        throw "Installer packaging failed with exit $($process.ExitCode); portable build results remain separate."
    }
}

if ($WithExe) {
    & (Join-Path $PSScriptRoot 'windows-native-build.ps1') -Mode PackageExe -Toolchain $Toolchain -SourceCommit $SourceCommit -OutputRoot $OutputRoot
}
