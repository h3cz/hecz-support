# Hecz Support build toolchain, isolated under C:\hsb. Idempotent.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$R = "C:\hsb"
New-Item -ItemType Directory -Force -Path $R, "$R\dl" | Out-Null
function Log($m) { "$(Get-Date -Format s) $m" | Tee-Object -FilePath "$R\setup.log" -Append }
# SHA-256 of every downloaded input, recorded from the 2026-10-25 build. The
# RustDesk engine is published under a mutable "main" tag, so a mismatch means
# upstream replaced it: stop and review rather than build with different bytes.
$Pinned = @{
  "7z.msi"      = "ec6af1ea0367d16dde6639a89a080a524cebc4d4bedfe00ed0cac4b865a918d8"
  "llvm.exe"    = "22e2f2c38be4c44db7a1e9da5e67de2a453c5b4be9cf91e139592a63877ac0a2"
  "flutter.zip" = "b8a7485acd3c6fb23a76b7ac09f89e8d93d62fbff7147c6f5f8c5686d949eeac"
  "engine.zip"  = "ec8cabf36ee4ff24c8d98de25b00e70781eb03876265aee84d0fe554a110036e"
}
function Fetch($url, $out) {
  if (-not (Test-Path $out)) { Log "download $url"; Invoke-WebRequest -Uri $url -OutFile "$out.part"; Move-Item "$out.part" $out }
  $want = $Pinned[(Split-Path $out -Leaf)]
  $got = (Get-FileHash -Algorithm SHA256 $out).Hash.ToLower()
  if ($want -and $got -ne $want) { Log "HASH MISMATCH $out got $got want $want"; exit 1 }
}

# 7-Zip (admin-free MSI extraction) for unpacking the LLVM NSIS installer
if (-not (Test-Path "$R\7zip\Files\7-Zip\7z.exe")) {
  Fetch "https://github.com/ip7z/7zip/releases/download/24.09/7z2409-x64.msi" "$R\dl\7z.msi"
  Start-Process msiexec -Wait -ArgumentList "/a `"$R\dl\7z.msi`" /qn TARGETDIR=`"$R\7zip`""
}
$7z = "$R\7zip\Files\7-Zip\7z.exe"; Log "7z: $(Test-Path $7z)"

# LLVM 15.0.6 (pinned by RustDesk CI)
if (-not (Test-Path "$R\llvm\bin\libclang.dll")) {
  Fetch "https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.6/LLVM-15.0.6-win64.exe" "$R\dl\llvm.exe"
  & $7z x "$R\dl\llvm.exe" "-o$R\llvm" -y | Out-Null
}
Log "llvm: $(Test-Path "$R\llvm\bin\libclang.dll")"

# Rust 1.75 (pinned by RustDesk CI), installed as an extra toolchain; default is untouched
rustup toolchain install 1.75-x86_64-pc-windows-msvc --profile minimal --component rustfmt 2>&1 | Out-String | Log

# Flutter 3.24.5 + RustDesk custom Windows engine + dropdown patch
if (-not (Test-Path "$R\flutter\bin\flutter.bat")) {
  Fetch "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip" "$R\dl\flutter.zip"
  Expand-Archive "$R\dl\flutter.zip" -DestinationPath $R
}
$env:Path = "$R\flutter\bin;$R\llvm\bin;$env:Path"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
git config --global --add safe.directory "C:/hsb/flutter" 2>$null
& flutter config --no-analytics 2>&1 | Out-Null
& flutter precache --windows 2>&1 | Out-String | Log
if (-not (Test-Path "$R\engine-replaced.txt")) {
  Fetch "https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip" "$R\dl\engine.zip"
  Expand-Archive "$R\dl\engine.zip" -DestinationPath "$R\dl\engine" -Force
  Copy-Item -Force "$R\dl\engine\*" "$R\flutter\bin\cache\artifacts\engine\windows-x64-release\"
  "ok" | Set-Content "$R\engine-replaced.txt"; Log "engine replaced"
}

# Source: RustDesk 1.5.0 with submodules
if (-not (Test-Path "$R\src\Cargo.toml")) {
  git clone --depth 1 --branch 1.5.0 --recurse-submodules --shallow-submodules https://github.com/rustdesk/rustdesk.git "$R\src" 2>&1 | Out-String | Log
}
if (-not (Test-Path "$R\flutter-patched.txt")) {
  Push-Location "$R\flutter"; git apply "$R\src\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff"; Pop-Location
  "ok" | Set-Content "$R\flutter-patched.txt"; Log "flutter patched"
}

# vcpkg at the commit RustDesk pins
if (-not (Test-Path "$R\vcpkg\vcpkg.exe")) {
  git clone https://github.com/microsoft/vcpkg "$R\vcpkg" 2>&1 | Out-String | Log
  Push-Location "$R\vcpkg"; git checkout 9e593bb18ea69cc5095e012465dcd675a822ed0d 2>&1 | Out-String | Log
  & .\bootstrap-vcpkg.bat -disableMetrics 2>&1 | Out-String | Log; Pop-Location
}
Log "toolchain ready"
