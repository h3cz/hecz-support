# Build the Hecz Support Windows client from a RustDesk 1.5.0 checkout.
# Mirrors upstream .github/workflows/flutter-build.yml (x86_64 job) with the
# toolchain pinned under $Root. Run setup-toolchain.ps1 and the vcpkg step first.
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1 -Stage all
param(
  [string]$Root = "C:\hsb",
  [string]$Repo = "C:\hsb\hecz-support",
  [ValidateSet("brand", "bridge", "build", "pack", "all")] [string]$Stage = "all",
  [string]$Version = "1.5.0"
)
$ErrorActionPreference = "Continue"
$Src = "$Root\src"
$Log = "$Root\build.log"
function Log($m) { $line = "$(Get-Date -Format s) $m"; Write-Host $line; Add-Content -Encoding utf8 -Path $Log -Value $line }
function Run($what, [scriptblock]$cmd) {
  Log "BEGIN $what"
  & $cmd *>&1 | Out-File -Append -Encoding utf8 $Log
  if ($LASTEXITCODE -ne 0) { Log "FAILED $what (exit $LASTEXITCODE)"; exit 1 }
  Log "END $what"
}

$env:Path = "$Root\flutter\bin;$Root\llvm\bin;$env:USERPROFILE\.cargo\bin;$env:Path"
$env:LIBCLANG_PATH = "$Root\llvm\bin"
$env:VCPKG_ROOT = "$Root\vcpkg"
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
$env:RUSTUP_TOOLCHAIN = "1.75-x86_64-pc-windows-msvc"

if ($Stage -in "brand", "all") {
  Run "apply branding" { python "$Repo\scripts\apply_branding.py" $Src $Repo }
}

if ($Stage -in "bridge", "all") {
  # Tools build on stable; the bridge itself runs against the pinned 1.75 toolchain.
  if (-not (Test-Path "$env:USERPROFILE\.cargo\bin\flutter_rust_bridge_codegen.exe")) {
    Run "install cargo-expand" { cargo +stable install cargo-expand --version 1.0.95 --locked }
    Run "install frb codegen" { cargo +stable install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked }
  }
  Set-Location "$Src\flutter"
  Run "flutter pub get" { flutter pub get }
  Set-Location $Src
  Run "generate bridge" {
    flutter_rust_bridge_codegen --rust-input .\src\flutter_ffi.rs --dart-output .\flutter\lib\generated_bridge.dart --c-output .\flutter\macos\Runner\bridge_generated.h --llvm-path "$Root\llvm"
  }
}

if ($Stage -in "build", "all") {
  Set-Location $Src
  Run "build.py" { python .\build.py --portable --flutter --skip-portable-pack --hwcodec --vram }
  $out = "$Root\out\HeczSupport"
  if (Test-Path $out) { Remove-Item -Recurse -Force $out }
  New-Item -ItemType Directory -Force -Path "$Root\out" | Out-Null
  Copy-Item -Recurse "$Src\flutter\build\windows\x64\runner\Release" $out
  # Ship under the app name, the same way RustDesk's custom-client packages do.
  Move-Item "$out\rustdesk.exe" "$out\HeczSupport.exe"
  Copy-Item "$Src\LICENCE" "$out\LICENSE-AGPL-3.0.txt"
  Copy-Item "$Repo\NOTICE.txt" "$out\NOTICE.txt"
  Log "staged $out"
}

if ($Stage -in "pack", "all") {
  Set-Location $Src
  git checkout -- res/manifest.xml 2>$null
  (Get-Content res\manifest.xml) | Where-Object { $_ -notmatch "dpiAware" } | Set-Content res\manifest.xml
  Run "pip brotli" { python -m pip install --user -r .\libs\portable\requirements.txt }
  Set-Location "$Src\libs\portable"
  Run "pack portable" { python .\generate.py -f "$Root\out\HeczSupport" -o . -e "$Root\out\HeczSupport\HeczSupport.exe" }
  New-Item -ItemType Directory -Force -Path "$Root\dist" | Out-Null
  $dest = "$Root\dist\HeczSupport-$Version-x64.exe"
  Copy-Item -Force "$Src\target\release\rustdesk-portable-packer.exe" $dest
  $hash = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLower()
  "$hash  HeczSupport-$Version-x64.exe" | Set-Content -Encoding ascii "$dest.sha256"
  Log "artifact $dest sha256 $hash"
}
Log "done stage=$Stage"
