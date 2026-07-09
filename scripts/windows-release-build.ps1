param(
  [string]$Version = "1.4.9",
  [string]$RepoUrl = "https://github.com/2bitegr/rd-cl.git",
  [string]$Branch = "main",
  [string]$ToolsRoot = "C:\Tools",
  [string]$BuildBase = "C:\Build\rd-cl",
  [string]$VcpkgRoot = "C:\vcpkg"
)

$ErrorActionPreference = "Stop"

function Step($message) {
  Write-Host ""
  Write-Host "==> $message"
}

function Ensure-Directory($path) {
  if (!(Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Import-VsDevCmd($vsDevCmd) {
  Step "Loading Visual Studio build environment"
  $envLines = cmd.exe /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
  foreach ($line in $envLines) {
    if ($line -match "^(.*?)=(.*)$") {
      Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2]
    }
  }
}

function To-GitBashPath($windowsPath) {
  $drive = $windowsPath.Substring(0, 1).ToLowerInvariant()
  $rest = $windowsPath.Substring(2).Replace("\", "/")
  return "/$drive$rest"
}

function Run-GitBash($command) {
  & "C:\Program Files\Git\bin\bash.exe" -lc $command
  if ($LASTEXITCODE -ne 0) {
    throw "Git Bash command failed: $command"
  }
}

function Download-File($url, $outFile) {
  if (Test-Path -LiteralPath $outFile) {
    Remove-Item -LiteralPath $outFile -Force
  }
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (!$curl) {
    throw "curl.exe is required for large artifact downloads"
  }
  & $curl.Source -L --fail --retry 3 --retry-delay 5 --output $outFile $url
  if ($LASTEXITCODE -ne 0) {
    throw "Download failed: $url"
  }
}

$flutterRoot = Join-Path $ToolsRoot "flutter-3.24.5"
$flutterZip = Join-Path $ToolsRoot "flutter_windows_3.24.5-stable.zip"
$flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip"
$engineZip = Join-Path $ToolsRoot "rustdesk-windows-x64-release.zip"
$engineExtract = Join-Path $ToolsRoot "rustdesk-windows-x64-release"
$engineUrl = "https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip"
$vcpkgCommit = "120deac3062162151622ca4860575a33844ba10b"
$buildRoot = Join-Path $BuildBase "rd-cl-build-$(Get-Date -Format yyyyMMdd-HHmmss)"
$repoRoot = Join-Path $buildRoot "rd-cl"
$signOutput = Join-Path $buildRoot "SignOutput"
$vsDevCmd = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"

Ensure-Directory $ToolsRoot
Ensure-Directory $BuildBase
Ensure-Directory $signOutput
Start-Transcript -Path (Join-Path $buildRoot "release-build.log") -Force | Out-Null

try {
  Step "Checking required Windows tools"
  if (!(Test-Path -LiteralPath $vsDevCmd)) {
    throw "Visual Studio BuildTools VsDevCmd.bat was not found at $vsDevCmd"
  }
  foreach ($cmd in @("git", "python", "cargo", "rustup", "nuget", "cmake")) {
    if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
      throw "$cmd is missing from Windows PATH"
    }
  }

  Step "Installing Rust 1.75 MSVC toolchain if missing"
  rustup toolchain install 1.75-x86_64-pc-windows-msvc

  Step "Preparing Flutter 3.24.5 for Windows"
  if (!(Test-Path -LiteralPath (Join-Path $flutterRoot "bin\flutter.bat"))) {
    Download-File $flutterUrl $flutterZip
    $tmpFlutter = Join-Path $ToolsRoot "flutter-3.24.5-extract"
    if (Test-Path -LiteralPath $tmpFlutter) {
      Remove-Item -LiteralPath $tmpFlutter -Recurse -Force
    }
    Expand-Archive -Path $flutterZip -DestinationPath $tmpFlutter -Force
    if (Test-Path -LiteralPath $flutterRoot) {
      Remove-Item -LiteralPath $flutterRoot -Recurse -Force
    }
    Move-Item -LiteralPath (Join-Path $tmpFlutter "flutter") -Destination $flutterRoot
    Remove-Item -LiteralPath $tmpFlutter -Recurse -Force
  }
  $env:PATH = "$flutterRoot\bin;$env:PATH"
  flutter --version
  flutter config --enable-windows-desktop
  flutter precache --windows

  Step "Replacing Flutter x64 engine with RustDesk custom engine"
  if (!(Test-Path -LiteralPath $engineZip)) {
    Download-File $engineUrl $engineZip
  }
  if (Test-Path -LiteralPath $engineExtract) {
    Remove-Item -LiteralPath $engineExtract -Recurse -Force
  }
  Expand-Archive -Path $engineZip -DestinationPath $engineExtract -Force
  $engineTarget = Join-Path $flutterRoot "bin\cache\artifacts\engine\windows-x64-release"
  Copy-Item -Path (Join-Path $engineExtract "*") -Destination $engineTarget -Recurse -Force

  Step "Preparing vcpkg"
  if (!(Test-Path -LiteralPath (Join-Path $VcpkgRoot "vcpkg.exe"))) {
    git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
    Push-Location $VcpkgRoot
    git checkout $vcpkgCommit
    .\bootstrap-vcpkg.bat -disableMetrics
    Pop-Location
  } else {
    Push-Location $VcpkgRoot
    git fetch --depth 1 origin $vcpkgCommit
    git checkout $vcpkgCommit
    .\bootstrap-vcpkg.bat -disableMetrics
    Pop-Location
  }

  Step "Cloning rd-cl into clean build directory"
  git clone --branch $Branch --recursive $RepoUrl $repoRoot
  Push-Location $repoRoot
  git rev-parse HEAD

  Step "Applying Exantas submodule patches"
  $repoRootBash = To-GitBashPath $repoRoot
  Run-GitBash "cd '$repoRootBash' && scripts/apply-exantas-submodule-patches.sh"

  Step "Patching Flutter SDK for RustDesk dropdown filter compatibility"
  $flutterRootBash = To-GitBashPath $flutterRoot
  $patchBash = To-GitBashPath (Join-Path $repoRoot ".github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff")
  Run-GitBash "cd '$flutterRootBash' && (git apply --check '$patchBash' && git apply '$patchBash' || git apply --reverse --check '$patchBash' >/dev/null 2>&1 || true)"

  Step "Installing vcpkg dependencies"
  $env:VCPKG_ROOT = $VcpkgRoot
  $env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
  $env:VCPKG_BINARY_SOURCES = "clear"
  & (Join-Path $VcpkgRoot "vcpkg.exe") install --triplet x64-windows-static --x-install-root="$VcpkgRoot\installed"
  if ($LASTEXITCODE -ne 0) {
    throw "vcpkg install failed"
  }

  Import-VsDevCmd $vsDevCmd
  $env:PATH = "$flutterRoot\bin;$env:PATH"
  $env:VCPKG_ROOT = $VcpkgRoot
  $env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
  $env:VCPKG_BINARY_SOURCES = "clear"
  $env:RUSTUP_TOOLCHAIN = "1.75-x86_64-pc-windows-msvc"

  Step "Generating Flutter Rust Bridge bindings"
  if (!(Get-Command flutter_rust_bridge_codegen -ErrorAction SilentlyContinue)) {
    cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
    if ($LASTEXITCODE -ne 0) {
      throw "flutter_rust_bridge_codegen install failed"
    }
  }
  Push-Location .\flutter
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed before FRB generation"
  }
  Pop-Location
  flutter_rust_bridge_codegen --rust-input .\src\flutter_ffi.rs --dart-output .\flutter\lib\generated_bridge.dart
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Rust Bridge generation failed"
  }
  foreach ($generated in @(".\src\bridge_generated.rs", ".\src\bridge_generated.io.rs", ".\flutter\lib\generated_bridge.dart")) {
    if (!(Test-Path -LiteralPath $generated)) {
      throw "Expected generated file missing after FRB generation: $generated"
    }
  }

  Step "Building RustDesk Windows Flutter release"
  python .\build.py --portable --flutter --skip-portable-pack --hwcodec --vram

  Step "Preparing release folder"
  $releaseDir = Join-Path $repoRoot "flutter\build\windows\x64\runner\Release"
  if (!(Test-Path -LiteralPath $releaseDir)) {
    throw "Flutter release folder was not created: $releaseDir"
  }
  $rustdeskDir = Join-Path $repoRoot "rustdesk"
  if (Test-Path -LiteralPath $rustdeskDir) {
    Remove-Item -LiteralPath $rustdeskDir -Recurse -Force
  }
  Copy-Item -LiteralPath $releaseDir -Destination $rustdeskDir -Recurse

  Step "Building portable self-extracting executable"
  $manifest = Join-Path $repoRoot "res\manifest.xml"
  $manifestContent = Get-Content -LiteralPath $manifest
  $manifestContent | Where-Object { $_ -notmatch "dpiAware" } | Set-Content -LiteralPath $manifest -Encoding UTF8
  $exe = Get-ChildItem -LiteralPath $rustdeskDir -Filter "*.exe" | Select-Object -First 1
  if (!$exe) {
    throw "No executable found in $rustdeskDir"
  }
  $appExeName = "Exantas Support.exe"
  if ($exe.Name -ne $appExeName) {
    Rename-Item -LiteralPath $exe.FullName -NewName $appExeName -Force
    $exe = Get-Item -LiteralPath (Join-Path $rustdeskDir $appExeName)
  }
  Push-Location (Join-Path $repoRoot "libs\portable")
  python -m pip install -r requirements.txt
  python .\generate.py -f $rustdeskDir -o . -e $exe.FullName
  Pop-Location
  $portableBuilt = Join-Path $repoRoot "target\release\rustdesk-portable-packer.exe"
  if (!(Test-Path -LiteralPath $portableBuilt)) {
    throw "Portable packer output was not created: $portableBuilt"
  }
  $portableOut = Join-Path $signOutput "ExantasSupport-$Version-x86_64-portable.exe"
  Move-Item -LiteralPath $portableBuilt -Destination $portableOut -Force

  Step "Building MSI"
  Push-Location (Join-Path $repoRoot "res\msi")
  python .\preprocess.py --arp -d ..\..\rustdesk
  if ($LASTEXITCODE -ne 0) {
    throw "MSI preprocess failed"
  }
  nuget restore .\msi.sln
  if ($LASTEXITCODE -ne 0) {
    throw "NuGet restore for MSI failed"
  }
  msbuild .\msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
  if ($LASTEXITCODE -ne 0) {
    throw "MSI build failed"
  }
  $msi = Get-ChildItem -Path ".\Package\bin\*\Release\en-us\*.msi" | Select-Object -First 1
  if (!$msi) {
    throw "MSI output was not found"
  }
  $msiOut = Join-Path $signOutput "ExantasInstaller-$Version-x86_64.msi"
  Move-Item -LiteralPath $msi.FullName -Destination $msiOut -Force
  Pop-Location

  Step "Release artifact checksums"
  Get-ChildItem -LiteralPath $signOutput | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    [PSCustomObject]@{
      Name = $_.Name
      Size = $_.Length
      SHA256 = $hash.Hash
      Path = $_.FullName
    }
  } | Format-Table -AutoSize

  Step "Release build completed"
  Write-Host "BUILD_ROOT=$buildRoot"
  Write-Host "SOURCE_DIR=$repoRoot"
  Write-Host "ARTIFACT_DIR=$signOutput"
}
finally {
  Pop-Location -ErrorAction SilentlyContinue
  Stop-Transcript | Out-Null
}
