#!/usr/bin/env python3
"""Turn a clean RustDesk 1.5.0 checkout into the Hecz Support client.

Usage: python apply_branding.py <rustdesk-src> <hecz-support-repo> [1.5.0-rN]

Every edit is an exact string replacement that must match once. If upstream
moves a line, the script stops instead of guessing, so a new RustDesk tag
needs a deliberate review of this file.
"""
import hashlib
import re
import shutil
import sys
from pathlib import Path

SRC = Path(sys.argv[1]).resolve()
REPO = Path(sys.argv[2]).resolve()
BRAND = REPO / "branding"
VERSION = sys.argv[3] if len(sys.argv) > 3 else "1.5.0"
if not re.fullmatch(r"1\.5\.0(?:-r[1-9][0-9]*)?", VERSION):
    sys.exit("Expected a 1.5.0 release version, optionally followed by -rN")

APP_NAME = "HeczSupport"  # no spaces: Windows service and sc.exe commands use it unquoted
DISPLAY_NAME = "Hecz Support"
SITE = "https://hecz.dev/download"
SOURCE = "https://github.com/h3cz/hecz-support"
COPYRIGHT = (
    "Hecz Support by Hecz (hecz.dev). Modified from RustDesk, "
    "Copyright (C) Purslane Tech Pte. Ltd. Licensed under AGPL-3.0."
)


def edit(rel, old, new, count=1):
    path = SRC / rel
    text = path.read_text(encoding="utf-8")
    found = text.count(old)
    if found != count:
        sys.exit(f"{rel}: expected {count} match(es) for {old!r}, found {found}")
    path.write_text(text.replace(old, new), encoding="utf-8")
    print(f"patched {rel}")


def copy(name, *dests):
    for dest in dests:
        shutil.copyfile(BRAND / name, SRC / dest)
        print(f"copied {name} -> {dest}")


# 1. Identity. APP_NAME drives the window title, tray, install folder, service
#    name and every translated string (src/lang.rs swaps "RustDesk" for it).
edit(
    "libs/hbb_common/src/config.rs",
    'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());',
    f'pub static ref APP_NAME: RwLock<String> = RwLock::new("{APP_NAME}".to_owned());',
)
edit(
    "libs/hbb_common/src/config.rs",
    'pub static ref ORG: RwLock<String> = RwLock::new("com.carriez".to_owned());',
    'pub static ref ORG: RwLock<String> = RwLock::new("dev.hecz".to_owned());',
)

# 2. Attended support by default. Every incoming session waits for the person
#    at the PC to click Accept. Nothing is preset: no permanent password and no
#    unattended access. These are defaults, so the owner can see and change them
#    in Settings > Security.
edit(
    "src/common.rs",
    "pub fn load_custom_client() {\n",
    """pub fn load_custom_client() {
    apply_hecz_support_defaults();
""",
)
edit(
    "src/common.rs",
    "fn read_custom_client_advanced_settings(",
    """/// Hecz Support: attended, click-to-accept sessions out of the box.
fn apply_hecz_support_defaults() {
    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    defaults.insert("approve-mode".to_owned(), "click".to_owned());
    defaults.insert(
        "verification-method".to_owned(),
        "use-temporary-password".to_owned(),
    );
}

fn read_custom_client_advanced_settings(""",
)

# 3. Hecz palette: dusty mauve accent instead of RustDesk blue.
common = "flutter/lib/common.dart"
edit(common, "static const Color accent = Color(0xFF0071FF);", "static const Color accent = Color(0xFF6B5D82);")
edit(common, "static const Color accent50 = Color(0x770071FF);", "static const Color accent50 = Color(0x776B5D82);")
edit(common, "static const Color accent80 = Color(0xAA0071FF);", "static const Color accent80 = Color(0xAA6B5D82);")
edit(common, "static const Color idColor = Color(0xFF00B6F0);", "static const Color idColor = Color(0xFF8B7DA8);")
edit(common, "static const Color button = Color(0xFF2C8CFF);", "static const Color button = Color(0xFF6B5D82);")
edit(common, "  return Color(0xFF2C8CFF);\n}", "  return Color(0xFF6B5D82);\n}")
edit(common, "primary: Colors.blue, secondary: accent, background: grayBg),", "primary: accent, secondary: accent, background: grayBg),")

# 4. About page: point at Hecz, keep the RustDesk copyright and the license,
#    and link the corresponding source as AGPL-3.0 requires.
about = "flutter/lib/desktop/pages/desktop_setting_page.dart"
edit(about, "launchUrlString('https://rustdesk.com/privacy.html');", f"launchUrlString('{SITE}#privacy');")
edit(
    about,
    """                    launchUrlString('https://rustdesk.com');
                  },
                  child: Text(
                    translate('Website'),
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),""",
    f"""                    launchUrlString('{SITE}');
                  }},
                  child: Text(
                    translate('Website'),
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {{
                    launchUrlString('{SOURCE}');
                  }},
                  child: Text(
                    'Source code (AGPL-3.0)',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),""",
)
edit(about, "decoration: const BoxDecoration(color: Color(0xFF2c8cff)),", "decoration: const BoxDecoration(color: Color(0xFF2A1B3D)),")
edit(
    about,
    "'Copyright © ${DateTime.now().toString().substring(0, 4)} Purslane Tech Pte. Ltd.\\n$license',",
    "'Hecz Support is a modified build of RustDesk, made by Hecz (hecz.dev).\\nRustDesk is Copyright © ${DateTime.now().toString().substring(0, 4)} Purslane Tech Pte. Ltd. and contributors, licensed under AGPL-3.0.\\n$license',",
)

# 5. Windows version resources (Explorer > Properties > Details).
rc = "flutter/windows/runner/Runner.rc"
edit(rc, 'VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\\0"', 'VALUE "CompanyName", "Hecz" "\\0"')
edit(rc, 'VALUE "FileDescription", "RustDesk Remote Desktop" "\\0"', f'VALUE "FileDescription", "{DISPLAY_NAME}" "\\0"')
edit(rc, 'VALUE "InternalName", "rustdesk" "\\0"', f'VALUE "InternalName", "{APP_NAME}" "\\0"')
edit(rc, 'VALUE "OriginalFilename", "rustdesk.exe" "\\0"', f'VALUE "OriginalFilename", "{APP_NAME}.exe" "\\0"')
edit(rc, 'VALUE "ProductName", "RustDesk" "\\0"', f'VALUE "ProductName", "{DISPLAY_NAME}" "\\0"')
rc_path = SRC / rc
rc_text = rc_path.read_text(encoding="utf-8")
start = rc_text.index('VALUE "LegalCopyright", "')
end = rc_text.index("\n", start)
rc_path.write_text(rc_text[:start] + f'VALUE "LegalCopyright", "{COPYRIGHT}" "\\0"' + rc_text[end:], encoding="utf-8")
print(f"patched {rc} LegalCopyright")

for toml in ("Cargo.toml", "libs/portable/Cargo.toml"):
    edit(toml, 'LegalCopyright = "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved."', f'LegalCopyright = "{COPYRIGHT}"')
    edit(toml, 'ProductName = "RustDesk"', f'ProductName = "{DISPLAY_NAME}"')
    edit(toml, 'FileDescription = "RustDesk Remote Desktop"', f'FileDescription = "{DISPLAY_NAME}"')
    edit(toml, 'OriginalFilename = "rustdesk.exe"', f'OriginalFilename = "{APP_NAME}.exe"')

# 5b. The desktop title bar draws a literal "RustDesk" beside the icon instead
#     of the app name.
edit(
    "flutter/lib/desktop/widgets/tabbar_widget.dart",
    """                            child: const Text(
                              "RustDesk",""",
    f"""                            child: const Text(
                              "{DISPLAY_NAME}",""",
)
# Translated strings swap "RustDesk" for the internal APP_NAME. Show the
# spaced display name instead; APP_NAME itself stays space-free.
edit("src/lang.rs", '                    s = s.replace("RustDesk", &app_name);\n                } else {',
     f'                    s = s.replace("RustDesk", "{DISPLAY_NAME}");\n                }} else {{')
# The status bar links to RustDesk's paid server plans ("set up your own server").
# That is an upsell for operators, not for the person being helped: hide it.
edit(
    "flutter/lib/desktop/pages/connection_page.dart",
    "            offstage: !(!_svcStopped.value &&",
    "            offstage: true || !(!_svcStopped.value &&",
)
edit("flutter/lib/desktop/pages/connection_page.dart", 'const url = "https://rustdesk.com/pricing";', f'const url = "{SITE}";')
# "Switch Sides" button uses saturated purple, which the Hecz palette reserves for the logo.
edit("flutter/lib/desktop/pages/server_page.dart", "              color: Colors.purple,\n              onClick: () => handleSwitchBack(context),",
     "              color: MyTheme.accent,\n              onClick: () => handleSwitchBack(context),")
# The self-extracting wrapper has no CompanyName at all upstream.
edit("libs/portable/Cargo.toml", f'ProductName = "{DISPLAY_NAME}"', f'ProductName = "{DISPLAY_NAME}"\nCompanyName = "Hecz"')

# The home page uses a separate attribution link and hides the title by default.
# Keep upstream attribution in About and NOTICE, with the support link on Home.
edit(common,
     """      onTap: () {
        launchUrl(Uri.parse('https://rustdesk.com'));
      },
      child: Opacity(""",
     f"""      onTap: () {{
        launchUrl(Uri.parse('{SITE}'));
      }},
      child: Opacity(""")
edit(common, '            translate("powered_by_me"),',
     '            "Hecz Support",')
edit("flutter/lib/desktop/pages/desktop_tab_page.dart",
     """            body: DesktopTab(
              controller: tabController,""",
     """            body: DesktopTab(
              controller: tabController,
              showTitle: true,""")
# Display the package revision without changing the upstream protocol version.
edit(about, "      final version = await bind.mainGetVersion();",
     f"      const version = '{VERSION}';")

# 7. Installer ("Paper" wizard). The upstream page is replaced wholesale, so
#    it is pinned by hash: a new RustDesk tag must be reviewed by hand.
UPSTREAM_INSTALL_PAGE = "982b723ef0cd3dcb11ba5c6fed5ce6ae896ed2bee13dc5e36a56e59a90381806"


def replace_pinned(rel, sha256, new_file):
    path = SRC / rel
    found = hashlib.sha256(path.read_bytes()).hexdigest()
    if found != sha256:
        sys.exit(f"{rel}: upstream changed (sha256 {found}); review before replacing")
    shutil.copyfile(new_file, path)
    print(f"replaced {rel}")


replace_pinned("flutter/lib/desktop/pages/install_page.dart", UPSTREAM_INSTALL_PAGE,
               REPO / "branding/flutter/install_page.dart")
shutil.copyfile(REPO / "branding/flutter/hecz_installed_banner.dart",
                SRC / "flutter/lib/desktop/widgets/hecz_installed_banner.dart")
print("copied hecz_installed_banner.dart")

# Upstream exits the process right after the elevated install, whether it
# worked or not, so a cancelled UAC prompt made the window vanish. Record the
# result instead and let the install page show it.
edit("src/ui_interface.rs",
     """#[inline]
pub fn install_me(_options: String, _path: String, _silent: bool, _debug: bool) {
    #[cfg(windows)]
    std::thread::spawn(move || {
        allow_err!(crate::platform::windows::install_me(
            &_options, _path, _silent, _debug
        ));
        std::process::exit(0);
    });
}
""",
     """// Hecz Support: install result for the install page (see install_status).
#[cfg(windows)]
pub static HECZ_ELEVATED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);
#[cfg(windows)]
static HECZ_INSTALL: std::sync::Mutex<(&'static str, String)> =
    std::sync::Mutex::new(("idle", String::new()));

#[inline]
pub fn install_me(_options: String, _path: String, _silent: bool, _debug: bool) {
    #[cfg(windows)]
    {
        {
            let mut state = HECZ_INSTALL.lock().unwrap();
            if state.0 == "running" {
                return;
            }
            *state = ("running", String::new());
        }
        HECZ_ELEVATED.store(false, std::sync::atomic::Ordering::SeqCst);
        std::thread::spawn(move || {
            let result = match crate::platform::windows::install_me(
                &_options, _path, _silent, _debug,
            ) {
                Ok(()) if crate::platform::is_installed() => ("done", String::new()),
                Ok(()) => (
                    "failed",
                    "The install script finished, but Hecz Support is not in the install folder."
                        .to_owned(),
                ),
                Err(e) => {
                    log::error!("install failed: {:?}", e);
                    // ShellExecuteEx reports a declined UAC prompt as ERROR_CANCELLED.
                    let cancelled = !HECZ_ELEVATED.load(std::sync::atomic::Ordering::SeqCst)
                        && e.chain().any(|c| {
                            c.downcast_ref::<::windows::core::Error>()
                                .map_or(false, |w| w.code().0 as u32 == 0x800704C7)
                        });
                    (if cancelled { "cancelled" } else { "failed" }, format!("{e:#}"))
                }
            };
            *HECZ_INSTALL.lock().unwrap() = result;
        });
    }
}

/// JSON for the install page: state is idle|running|done|cancelled|failed.
/// `elevated` is set once Windows accepted the UAC prompt; `copied` once the
/// installed exe is this exe (XCOPY keeps the size and modified time).
pub fn hecz_install_status() -> String {
    #[cfg(windows)]
    {
        let (state, message) = HECZ_INSTALL.lock().unwrap().clone();
        let elevated = HECZ_ELEVATED.load(std::sync::atomic::Ordering::SeqCst);
        let copied = state == "done" || (elevated && hecz_install_copied());
        return serde_json::json!({
            "state": state,
            "elevated": elevated || state == "done",
            "copied": copied,
            "message": message,
            "reduce_motion": hecz_reduce_motion(),
        })
        .to_string();
    }
    #[cfg(not(windows))]
    "{}".to_owned()
}

#[cfg(windows)]
fn hecz_install_copied() -> bool {
    let (_, _, _, exe) = crate::platform::windows::get_install_info();
    let Ok(cur) = std::env::current_exe().and_then(std::fs::metadata) else {
        return false;
    };
    let Ok(installed) = std::fs::metadata(&exe) else {
        return false;
    };
    cur.len() == installed.len() && cur.modified().ok() == installed.modified().ok()
}

/// Windows Settings > Accessibility > Animation effects is off.
#[cfg(windows)]
fn hecz_reduce_motion() -> bool {
    const SPI_GETCLIENTAREAANIMATION: u32 = 0x1042;
    let mut on: i32 = 1;
    let ok = unsafe {
        winapi::um::winuser::SystemParametersInfoW(
            SPI_GETCLIENTAREAANIMATION,
            0,
            &mut on as *mut i32 as *mut winapi::ctypes::c_void,
            0,
        )
    };
    ok != 0 && on == 0
}

/// Finish with "Open Hecz Support now": start the installed copy, then leave.
pub fn hecz_install_open_installed() {
    #[cfg(windows)]
    {
        let (_, _, _, exe) = crate::platform::windows::get_install_info();
        allow_err!(std::process::Command::new(&exe).spawn());
    }
    std::process::exit(0);
}
""")
edit("src/platform/windows/installer_shell.rs",
     """    unsafe { Shell::ShellExecuteExW(&mut info) }?;
""",
     """    unsafe { Shell::ShellExecuteExW(&mut info) }?;
    // Hecz Support: the UAC prompt was accepted (the install page ticks a step).
    crate::ui_interface::HECZ_ELEVATED.store(true, std::sync::atomic::Ordering::SeqCst);
""")
edit("src/flutter_ffi.rs",
     """pub fn install_install_me(options: String, path: String) {
    install_me(options, path, false, false);
}
""",
     """pub fn install_install_me(options: String, path: String) {
    // silent: the install page offers "Open Hecz Support now" itself.
    install_me(options, path, true, false);
}

pub fn install_status() -> SyncReturn<String> {
    SyncReturn(hecz_install_status())
}

pub fn install_open_installed() {
    hecz_install_open_installed();
}
""")
# Add/Remove Programs shows the spaced name and publisher. Display only: the
# uninstall subkey, service and folder keep the space-free APP_NAME.
edit("src/platform/windows.rs",
     'reg add {subkey} /f /v DisplayName /t REG_SZ /d \\"{app_name}\\"',
     f'reg add {{subkey}} /f /v DisplayName /t REG_SZ /d \\"{DISPLAY_NAME}\\"')
edit("src/platform/windows.rs",
     'reg add {subkey} /f /v Publisher /t REG_SZ /d \\"{app_name}\\"',
     'reg add {subkey} /f /v Publisher /t REG_SZ /d \\"Hecz\\"')
# Uninstall (Start menu or Settings > Apps) asks first instead of starting at once.
edit("src/core_main.rs",
     """            if args[0] == "--uninstall" {
                if let Err(err) = platform::uninstall_me(true) {""",
     """            if args[0] == "--uninstall" {
                let text: Vec<u16> = "Remove Hecz Support from this PC?\\n\\nHecz will no longer be able to help through it. You can install it again from hecz.dev/download."
                    .encode_utf16()
                    .chain(Some(0))
                    .collect();
                let title: Vec<u16> = "Hecz Support".encode_utf16().chain(Some(0)).collect();
                let answer = unsafe {
                    winapi::um::winuser::MessageBoxW(
                        std::ptr::null_mut(),
                        text.as_ptr(),
                        title.as_ptr(),
                        winapi::um::winuser::MB_YESNO
                            | winapi::um::winuser::MB_ICONQUESTION
                            | winapi::um::winuser::MB_DEFBUTTON2,
                    )
                };
                if answer != winapi::um::winuser::IDYES {
                    return None;
                }
                if let Err(err) = platform::uninstall_me(true) {""")
home = "flutter/lib/desktop/pages/desktop_home_page.dart"
edit(home, "import 'package:flutter_hbb/desktop/widgets/update_progress.dart';\n",
     "import 'package:flutter_hbb/desktop/widgets/update_progress.dart';\n"
     "import 'package:flutter_hbb/desktop/widgets/hecz_installed_banner.dart';\n")
edit(home,
     """      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
""",
     """      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(children: [
        const HeczInstalledBanner(),
        Expanded(child: ConnectionPage()),
      ]),
""")

# 6. Icons and logo.
# Windows must use the dedicated high-contrast tray icon, not the app logo.
edit("src/tray.rs", "fn load_icon_from_asset() -> Option<image::DynamicImage> {",
     """fn load_icon_from_asset() -> Option<image::DynamicImage> {
    if cfg!(windows) {
        return None;
    }""")
copy("app_icon.ico", "res/icon.ico", "flutter/windows/runner/resources/app_icon.ico")
copy("tray-icon.ico", "res/tray-icon.ico")
copy("icon.png", "res/icon.png", "flutter/assets/icon.png")
copy("32x32.png", "res/32x32.png")
copy("64x64.png", "res/64x64.png")
copy("128x128.png", "res/128x128.png")
copy("128x128@2x.png", "res/128x128@2x.png")
copy("icon.svg", "flutter/assets/icon.svg")
copy("logo.png", "flutter/assets/logo.png")

print("Hecz Support branding applied.")
