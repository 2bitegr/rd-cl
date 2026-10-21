#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'scripts/windows-cloud-build.ps1') -SourceDir $root -ValidateOnly | Out-Null
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("rd-cl-build-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temporary 'flutter') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $temporary 'libs/portable') -Force | Out-Null
$passed = 0
function Check([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message }; $script:passed++ }
function Reject([scriptblock]$Action, [string]$Pattern) {
  $rejected = $false
  try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; $rejected = $true }
  Check $rejected "Expected rejection: $Pattern"
}
try {
  Set-Content (Join-Path $temporary 'Cargo.toml') '[package]`nversion = "1.4.11"'.Replace('`n', "`n")
  Set-Content (Join-Path $temporary 'libs/portable/Cargo.toml') 'version = "1.4.11"'
  Set-Content (Join-Path $temporary 'flutter/pubspec.yaml') 'version: 1.4.11+69'
  Check ((Get-SourceVersion $temporary) -eq '1.4.11') 'Build labels must come from matching source versions.'
  Set-Content (Join-Path $temporary 'flutter/pubspec.yaml') 'version: 1.4.10+1'
  Reject { Get-SourceVersion $temporary } 'versions must exist and match'
  Set-Content (Join-Path $temporary 'flutter/pubspec.yaml') 'version: 1.4.11+69'
  Set-Content (Join-Path $temporary 'libs/portable/Cargo.toml') 'version = "1.4.10"'
  Reject { Get-SourceVersion $temporary } 'versions must exist and match'
  Reject { & (Join-Path $root 'scripts/windows-cloud-build.ps1') -SourceDir $root -ExpectedCommit ('0' * 40) -ValidateOnly } 'ExpectedCommit'

  $download = Join-Path $temporary 'cached.bin'
  [IO.File]::WriteAllBytes($download, [byte[]](1, 2, 3))
  $hash = (Get-FileHash $download -Algorithm SHA256).Hash
  Get-VerifiedDownload 'https://example.invalid/no-network-expected' $download $hash
  Check ((Get-FileHash $download).Hash -eq $hash) 'A valid cached download must be reused unchanged.'
  Reject { Get-VerifiedDownload 'https://example.invalid/no-network-expected' $download ('0' * 64) } 'SHA-256 mismatch'
  Check ((Get-FileHash $download).Hash -eq $hash) 'A failed checksum must preserve the diagnostic bytes.'
  Reject { Get-VerifiedDownload 'http://example.invalid/no-network-expected' $download $hash } 'HTTPS'

  $exe = Join-Path $temporary 'synthetic.exe'
  $bytes = [byte[]]::new(128)
  [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes, 0)
  [BitConverter]::GetBytes([uint32]0x40).CopyTo($bytes, 0x3c)
  [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 0x40)
  [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes, 0x44)
  [IO.File]::WriteAllBytes($exe, $bytes)
  Assert-X64Executable $exe
  Check $true 'Valid synthetic x64 PE header accepted.'
  [BitConverter]::GetBytes([uint16]0x14c).CopyTo($bytes, 0x44)
  [IO.File]::WriteAllBytes($exe, $bytes)
  Reject { Assert-X64Executable $exe } 'Windows x64'
  [BitConverter]::GetBytes([uint32]::MaxValue).CopyTo($bytes, 0x3c)
  [IO.File]::WriteAllBytes($exe, $bytes)
  Reject { Assert-X64Executable $exe } 'Invalid PE header offset'
  $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
  Reject { Invoke-Checked $pwsh @('-NoLogo', '-NoProfile', '-Command', 'exit 23') } 'exit code 23'
  Invoke-Checked $pwsh @('-NoLogo', '-NoProfile', '-Command', 'exit 0')
  Check $true 'Successful native command accepted.'
  Write-Host "PASS: $passed build-input, integrity, architecture and exit-status checks. No native Windows build executed."
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
