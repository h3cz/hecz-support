# Hecz Support

Remote support client for Hecz clients. It is a rebranded build of
[RustDesk](https://github.com/rustdesk/rustdesk) 1.5.0, licensed AGPL-3.0.

Download: https://hecz.dev/download

## How a session works

1. You run `HeczSupport-1.5.0-r4-x64.exe`. It runs without installing.
2. You read your **ID** (a short number) to Hecz over the phone or chat. No password is needed.
3. When Hecz connects, a window asks you to **Accept** or **Cancel**.
   By default nothing happens until you click Accept, and you can end the
   session at any time from that same window. These are shipped defaults:
   whoever owns the PC can change them in Settings > Security.

## Installing (optional)

The home screen offers **Install**. The installer is a three-step wizard
(Welcome, Install, Ready):

* **Welcome:** install folder, Start menu and desktop shortcuts, and a
  heads-up that Windows will ask for permission and show *Unknown publisher*
  (the build is unsigned). *Run once without installing* stays available.
* **Installing:** only real steps are shown: the Windows permission prompt,
  copying the files, and starting the background service.
* **You're ready:** the ID with a Copy button, and an option to open
  Hecz Support. If the Windows prompt is declined or the install fails, the
  wizard says so and offers **Try again** instead of closing.

Installed copies appear in Add/Remove Programs as *Hecz Support* by *Hecz*,
and uninstalling asks for confirmation first.

There is no hidden access. The client ships with no saved password, no
account, and no unattended mode. Sessions travel through RustDesk's public
ID and relay servers, end to end encrypted.

## What this repo contains

| Path | Purpose |
|---|---|
| `scripts/apply_branding.py` | Exact, fail-closed edits that turn upstream RustDesk 1.5.0 into Hecz Support |
| `scripts/build-windows.ps1` | Windows build, mirroring upstream's `flutter-build.yml` x64 job |
| `scripts/setup-toolchain.ps1` | Pinned toolchain: Flutter 3.24.5 with RustDesk's engine, LLVM 15.0.6, Rust 1.75, vcpkg `9e593bb`. Every download is checked against a recorded SHA-256 |
| `scripts/make_icons.py` | Renders the icon set from the hecz.dev mark |
| `branding/` | Icons and logo |
| `branding/flutter/` | The installer wizard and the first-run banner. The wizard replaces upstream's `install_page.dart` only while that file still matches a pinned SHA-256 |
| `NOTICE.txt` | Attribution and change summary, shipped inside the client |

Each GitHub release also attaches the full patched source tree.

## Build

On Windows with Visual Studio 2022 Build Tools (C++ workload) and Git:

```powershell
git clone --depth 1 --branch 1.5.0 --recurse-submodules https://github.com/rustdesk/rustdesk C:\hsb\src
powershell -ExecutionPolicy Bypass -File scripts\setup-toolchain.ps1
# vcpkg dependencies, from C:\hsb\src:
C:\hsb\vcpkg\vcpkg.exe install --triplet x64-windows-static --x-install-root=C:\hsb\vcpkg\installed
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Repo <this repo> -Stage all
```

The result is `C:\hsb\dist\HeczSupport-<Version>-x64.exe` (pass `-Version 1.5.0-r4`) plus its SHA-256.

## Not done yet

* **Code signing.** Builds are unsigned until Hecz has a code signing
  certificate, so Windows SmartScreen shows "Windows protected your PC".
  Edge may also say the file is not commonly downloaded. Choose Keep, then
  Keep anyway (it may be under the arrow beside Delete). Before opening it,
  check the SHA-256 on the download page. If Windows warns, choose More info,
  then Run anyway.
* **Own ID and relay server.** The client uses RustDesk's free public servers.
  Moving to a self-hosted `hbbs`/`hbbr` only needs the host and public key in
  `libs/hbb_common/src/config.rs`, rebuilt.

## License

AGPL-3.0, same as RustDesk. See `LICENSE`. RustDesk is Copyright (C)
Purslane Tech Pte. Ltd. and contributors. This project is not affiliated
with or endorsed by RustDesk.
