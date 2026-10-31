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
# One native Python session owns the locks across Build and EXE/MSI packaging.
$core = @{Mode=$Mode;Toolchain=$Toolchain;SourceCommit=$SourceCommit;OutputRoot=$OutputRoot}
if ($ElevateProvision) { $core.ElevateProvision = $true }
if ($WithExe) { $core.WithExe = $true }
if ($WithMsi) { $core.WithMsi = $true }
& (Join-Path $PSScriptRoot 'windows-native-build.ps1') @core
