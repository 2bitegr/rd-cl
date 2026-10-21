#requires -Version 7.4
[CmdletBinding()]
param(
  [string]$SourceDir = (Split-Path -Parent $PSScriptRoot),
  [string]$BuildBase,
  [string]$ToolsRoot,
  [string]$VcpkgRoot,
  [ValidatePattern('^$|^[0-9a-fA-F]{40}$')][string]$ExpectedCommit = '',
  [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Checked([string]$File, [string[]]$Arguments) {
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}

function Get-SourceVersion([string]$Root) {
  $cargo = Get-Content -LiteralPath (Join-Path $Root 'Cargo.toml') -Raw
  $pubspec = Get-Content -LiteralPath (Join-Path $Root 'flutter/pubspec.yaml') -Raw
  $portable = Get-Content -LiteralPath (Join-Path $Root 'libs/portable/Cargo.toml') -Raw
  $cargoVersion = [regex]::Match($cargo, '(?m)^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
  $flutterVersion = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$')
  $portableVersion = [regex]::Match($portable, '(?m)^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
  if (!$cargoVersion.Success -or !$flutterVersion.Success -or !$portableVersion.Success -or $cargoVersion.Groups[1].Value -ne $flutterVersion.Groups[1].Value -or $cargoVersion.Groups[1].Value -ne $portableVersion.Groups[1].Value) {
    throw 'Cargo, Flutter and portable application versions must exist and match.'
  }
  return $cargoVersion.Groups[1].Value
}

function Get-VerifiedDownload([string]$Uri, [string]$Destination, [string]$Sha256) {
  if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'A trusted SHA-256 pin is required.' }
  if (([uri]$Uri).Scheme -ne 'https') { throw 'Build downloads require HTTPS.' }
  if (!(Test-Path -LiteralPath $Destination)) { Invoke-WebRequest -Uri $Uri -OutFile $Destination }
  if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Sha256) {
    throw "SHA-256 mismatch: $Destination. Preserve the failed download; do not change the pin."
  }
}

function Assert-X64Executable([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  $reader = [IO.BinaryReader]::new($stream)
  try {
    if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Missing DOS executable signature.' }
    $stream.Position = 0x3c
    $offset = $reader.ReadUInt32()
    if ($offset -gt $stream.Length - 6) { throw 'Invalid PE header offset.' }
    $stream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Expected a Windows x64 PE executable.' }
  } finally { $reader.Dispose(); $stream.Dispose() }
}

$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$config = Get-Content -LiteralPath (Join-Path $SourceDir 'scripts/windows-cloud-build.json') -Raw | ConvertFrom-Json
$version = Get-SourceVersion $SourceDir
$commit = (& git -C $SourceDir rev-parse --verify 'HEAD^{commit}').Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the selected source commit.' }
if ($ExpectedCommit -and $commit -ne $ExpectedCommit) { throw 'Selected checkout does not match ExpectedCommit.' }
$dirtySource = @(& git -C $SourceDir status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source changes.' }
if ($config.engine.sha256 -notmatch '^[0-9a-f]{64}$' -or $config.flutter.commit -notmatch '^[0-9a-f]{40}$' -or $config.vcpkg.commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid build-input pins.' }
if ($ValidateOnly) {
  [ordered]@{ version = $version; source_commit = $commit; dirty_source = $dirtySource; target = 'windows-x86_64'; native_build_executed = $false } | ConvertTo-Json
  return
}
if (!$IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') { throw 'Run the Windows cloud workflow on its Windows x64 runner; the Linux coordinator is not the native build host.' }
if (!$BuildBase) { $BuildBase = Join-Path ([IO.Path]::GetTempPath()) 'rd-cl-cloud-build' }
if (!$ToolsRoot) { $ToolsRoot = Join-Path $BuildBase 'tools' }
if (!$VcpkgRoot) { $VcpkgRoot = Join-Path $ToolsRoot 'vcpkg' }
$output = Join-Path $BuildBase 'artifacts'
if ((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force).Count) { throw 'Artifact output must be empty; preserve previous deliveries and use a new BuildBase.' }
if (Test-Path -LiteralPath (Join-Path $BuildBase 'bundle')) { throw 'Preserve the existing bundle and choose a new BuildBase for this build.' }
New-Item -ItemType Directory -Force -Path $BuildBase, $ToolsRoot, $output | Out-Null
$buildStarted = [DateTime]::UtcNow
Start-Transcript -Path (Join-Path $BuildBase 'windows-build.log') | Out-Null
$originalLocation = Get-Location
try {
  Set-Location -LiteralPath $SourceDir
  foreach ($command in @('git', 'python', 'rustup', 'cargo', 'nuget', 'cmake')) {
    if (!(Get-Command $command -ErrorAction SilentlyContinue)) { throw "Missing runner prerequisite: $command" }
  }
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  $vsRoot = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
  if ($LASTEXITCODE -ne 0 -or !$vsRoot) { throw 'Visual Studio C++ x64 tools are required.' }
  $vsDevCmd = Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'
  $vsEnvironment = & cmd.exe /d /s /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
  if ($LASTEXITCODE -ne 0) { throw 'Visual Studio environment initialization failed.' }
  foreach ($line in $vsEnvironment) {
    if ($line -match '^([^=]+)=(.*)$') { Set-Item -LiteralPath "Env:$($matches[1])" -Value $matches[2] }
  }
  $llvm = Join-Path $env:ProgramFiles 'LLVM/bin'
  if (!(Test-Path -LiteralPath (Join-Path $llvm 'libclang.dll'))) { throw 'Runner LLVM libclang.dll is required for bridge generation.' }
  $env:LIBCLANG_PATH = $llvm
  $env:LLVM_PATH = Split-Path -Parent $llvm
  $env:PATH = "$llvm;$env:PATH"
  $env:RUSTUP_TOOLCHAIN = "$($config.rust_version)-x86_64-pc-windows-msvc"
  Invoke-Checked 'rustup' @('toolchain', 'install', $env:RUSTUP_TOOLCHAIN, '--profile', 'minimal')
  Invoke-Checked 'git' @('submodule', 'update', '--init', '--recursive')
  $hbb = Join-Path $SourceDir 'libs/hbb_common'
  $patch = Join-Path $SourceDir 'patches/hbb_common-exantas-config.patch'
  $patchOptions = @('--ignore-whitespace', '--ignore-space-change', '--unidiff-zero')
  & git -C $hbb apply @patchOptions --check $patch 2>$null
  if ($LASTEXITCODE -eq 0) { Invoke-Checked 'git' (@('-C', $hbb, 'apply') + $patchOptions + @($patch)) }
  else {
    & git -C $hbb apply @patchOptions --reverse --check $patch 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The public Exantas submodule patch no longer applies.' }
  }
  $flutterRoot = Join-Path $ToolsRoot "flutter-$($config.flutter.version)"
  if (!(Test-Path -LiteralPath $flutterRoot)) { Invoke-Checked 'git' @('clone', '--depth', '1', '--branch', $config.flutter.version, 'https://github.com/flutter/flutter.git', $flutterRoot) }
  $flutterCommit = (& git -C $flutterRoot rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $flutterCommit -ne $config.flutter.commit) { throw 'Flutter SDK commit does not match its pin.' }
  $env:PATH = "$(Join-Path $flutterRoot 'bin');$env:PATH"
  $flutterPatch = Join-Path $SourceDir '.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff'
  & git -C $flutterRoot apply --check $flutterPatch 2>$null
  if ($LASTEXITCODE -eq 0) { Invoke-Checked 'git' @('-C', $flutterRoot, 'apply', $flutterPatch) }
  else {
    & git -C $flutterRoot apply --reverse --check $flutterPatch 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Flutter compatibility patch failed; do not suppress this error.' }
  }
  Invoke-Checked 'flutter' @('config', '--enable-windows-desktop', '--no-analytics')
  Invoke-Checked 'flutter' @('precache', '--windows')
  $engineZip = Join-Path $ToolsRoot "engine-$($config.engine.sha256).zip"
  Get-VerifiedDownload $config.engine.url $engineZip $config.engine.sha256
  Expand-Archive -LiteralPath $engineZip -DestinationPath (Join-Path $flutterRoot 'bin/cache/artifacts/engine/windows-x64-release') -Force
  if (!(Test-Path -LiteralPath $VcpkgRoot)) { Invoke-Checked 'git' @('clone', '--no-checkout', 'https://github.com/microsoft/vcpkg.git', $VcpkgRoot) }
  Invoke-Checked 'git' @('-C', $VcpkgRoot, 'fetch', '--depth', '1', 'origin', $config.vcpkg.commit)
  Invoke-Checked 'git' @('-C', $VcpkgRoot, 'checkout', '--detach', $config.vcpkg.commit)
  Invoke-Checked (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') @('-disableMetrics')
  $env:VCPKG_ROOT = $VcpkgRoot
  $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
  $env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
  Invoke-Checked (Join-Path $VcpkgRoot 'vcpkg.exe') @('install', '--triplet', 'x64-windows-static', "--x-install-root=$VcpkgRoot/installed")
  $bridgeRoot = Join-Path $ToolsRoot "bridge-$($config.bridge_version)"
  $expand = Join-Path $bridgeRoot 'bin/cargo-expand.exe'
  if (!(Test-Path -LiteralPath $expand)) { Invoke-Checked 'cargo' @('install', 'cargo-expand', '--version', $config.cargo_expand_version, '--locked', '--root', $bridgeRoot) }
  $env:PATH = "$(Join-Path $bridgeRoot 'bin');$env:PATH"
  $bridge = Join-Path $bridgeRoot 'bin/flutter_rust_bridge_codegen.exe'
  if (!(Test-Path -LiteralPath $bridge)) { Invoke-Checked 'cargo' @('install', 'flutter_rust_bridge_codegen', '--version', $config.bridge_version, '--features', 'uuid', '--locked', '--root', $bridgeRoot) }
  $bridgeVersion = (& $bridge --version) -join ' '
  if ($LASTEXITCODE -ne 0 -or $bridgeVersion -notmatch [regex]::Escape($config.bridge_version)) { throw 'Incorrect bridge generator version.' }
  $cargoLockBefore = (Get-FileHash -LiteralPath 'Cargo.lock' -Algorithm SHA256).Hash
  $pubLockBefore = (Get-FileHash -LiteralPath 'flutter/pubspec.lock' -Algorithm SHA256).Hash
  Push-Location 'flutter'
  try { Invoke-Checked 'flutter' @('pub', 'get', '--enforce-lockfile') } finally { Pop-Location }
  Invoke-Checked $bridge @('--rust-input', 'src/flutter_ffi.rs', '--dart-output', 'flutter/lib/generated_bridge.dart')
  Push-Location 'flutter'
  try { Invoke-Checked 'dart' @('run', 'build_runner', 'build', '--delete-conflicting-outputs') } finally { Pop-Location }
  Invoke-Checked 'cargo' @('build', '--locked', '--release', '--features', 'flutter,hwcodec,vram', '--lib')
  Push-Location 'flutter'
  try { Invoke-Checked 'flutter' @('build', 'windows', '--release', '--no-pub') } finally { Pop-Location }
  $releaseDir = Join-Path $SourceDir 'flutter/build/windows/x64/runner/Release'
  Copy-Item -LiteralPath 'target/release/deps/dylib_virtual_display.dll' -Destination $releaseDir
  Assert-X64Executable (Join-Path $releaseDir 'rustdesk.exe')
  $bundle = Join-Path $BuildBase 'bundle'
  Copy-Item -LiteralPath $releaseDir -Destination $bundle -Recurse
  $topmost = Join-Path $ToolsRoot "topmost-$($config.topmost.commit)"
  if (!(Test-Path -LiteralPath $topmost)) { Invoke-Checked 'git' @('clone', 'https://github.com/rustdesk-org/RustDeskTempTopMostWindow.git', $topmost) }
  Invoke-Checked 'git' @('-C', $topmost, 'checkout', '--detach', $config.topmost.commit)
  Invoke-Checked 'msbuild' @((Join-Path $topmost 'WindowInjection/WindowInjection.vcxproj'), '/p:Configuration=Release', '/p:Platform=x64', '/p:TargetVersion=Windows10', '/m:2')
  Copy-Item -LiteralPath (Join-Path $topmost 'WindowInjection/x64/Release/WindowInjection.dll') -Destination $bundle
  $appExe = Join-Path $bundle 'Exantas Support.exe'
  Rename-Item -LiteralPath (Join-Path $bundle 'rustdesk.exe') -NewName 'Exantas Support.exe'
  Invoke-Checked 'python' @('-m', 'pip', 'install', '--require-hashes', '-r', 'scripts/windows-cloud-requirements.txt')
  Push-Location 'libs/portable'
  try { Invoke-Checked 'python' @('generate.py', '-f', $bundle, '-o', '.', '-e', $appExe) } finally { Pop-Location }
  $portableOut = Join-Path $output "ExantasSupport-$version-x86_64-portable.exe"
  Copy-Item -LiteralPath 'target/release/rustdesk-portable-packer.exe' -Destination $portableOut
  Assert-X64Executable $portableOut
  Push-Location 'res/msi'
  try {
    Invoke-Checked 'python' @('preprocess.py', '--arp', '-d', $bundle, '--version', $version)
    Invoke-Checked 'nuget' @('restore', 'msi.sln', '-NonInteractive')
    Invoke-Checked 'msbuild' @('msi.sln', '/restore', '/p:Configuration=Release', '/p:Platform=x64', '/p:TargetVersion=Windows10', '/m:2')
    $msiFiles = @(Get-ChildItem 'Package/bin' -Recurse -Filter '*.msi' | Where-Object { $_.LastWriteTimeUtc -ge $buildStarted })
    if ($msiFiles.Count -ne 1) { throw 'Expected exactly one freshly built MSI.' }
    $msiOut = Join-Path $output "ExantasInstaller-$version-x86_64.msi"
    Copy-Item -LiteralPath $msiFiles[0].FullName -Destination $msiOut
  } finally { Pop-Location }
  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database = $installer.OpenDatabase($msiOut, 0)
  $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = 'ProductVersion'")
  $view.Execute(); $msiVersion = $view.Fetch().StringData(1); $view.Close()
  if ($msiVersion -ne $version) { throw "MSI ProductVersion does not match source: $msiVersion" }
  if ($database.SummaryInformation(0).Property(7) -notmatch '^x64;') { throw 'MSI does not target x64.' }
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view)
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database)
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
  if ((Get-FileHash 'Cargo.lock').Hash -ne $cargoLockBefore -or (Get-FileHash 'flutter/pubspec.lock').Hash -ne $pubLockBefore) { throw 'Build changed a dependency lockfile; correct build inputs separately.' }
  $artifacts = @(Get-Item $portableOut, $msiOut | ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
  $artifacts | ForEach-Object { "$($_.sha256)  $($_.name)" } | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS') -Encoding utf8NoBOM
  [ordered]@{
    status = 'PASS'; validation = 'Package architecture, MSI version, dependency lockfiles and SHA-256; Windows runtime acceptance pending'
    application = 'rd-cl'; version = $version; target = 'windows-x86_64'; source_repository = 'https://github.com/2bitegr/rd-cl'
    source_commit = $commit; dirty_source = $dirtySource; expected_submodule_patch = 'patches/hbb_common-exantas-config.patch'
    toolchain = $env:RUSTUP_TOOLCHAIN; flutter_commit = $flutterCommit; build_inputs = $config
    signing = 'unsigned development build; Windows SmartScreen may warn'; artifacts = $artifacts
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'BUILD-INFO.json') -Encoding utf8NoBOM
  Write-Host "ARTIFACT_DIR=$output"
} finally { Set-Location $originalLocation; Stop-Transcript | Out-Null }
