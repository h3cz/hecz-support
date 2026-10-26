#!/usr/bin/env python3
"""Turn a clean RustDesk 1.5.0 checkout into the Hecz Support client.

Usage: python apply_branding.py <rustdesk-src> <hecz-support-repo>

Every edit is an exact string replacement that must match once. If upstream
moves a line, the script stops instead of guessing, so a new RustDesk tag
needs a deliberate review of this file.
"""
import shutil
import sys
from pathlib import Path

SRC = Path(sys.argv[1]).resolve()
REPO = Path(sys.argv[2]).resolve()
BRAND = REPO / "branding"

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

# 6. Icons and logo.
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
