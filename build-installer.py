#!/usr/bin/env python3
"""
Build a single self-contained macOS installer (.command) that embeds the whole
CompuOffice bridge. Double-clicking the resulting file in Finder installs the
native-messaging host for every Chromium-family browser on the Mac — no git
clone, no Terminal typing.

Run:  python3 build-installer.py
Out:  dist/Install-CompuOffice-Bridge.command
"""

import base64
import os
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "dist")
OUT = os.path.join(OUT_DIR, "Install-CompuOffice-Bridge.command")


def b64(path):
    with open(os.path.join(HERE, path), "rb") as fh:
        return base64.b64encode(fh.read()).decode("ascii")


def wrap_b64(data, width=100):
    return "\n".join(textwrap.wrap(data, width))


def main():
    launcher_py_b64 = wrap_b64(b64("host/launcher.py"))
    launcher_sh_b64 = wrap_b64(b64("host/launcher.sh"))
    config_example_b64 = wrap_b64(b64("host/config.example.json"))

    script = (
        INSTALLER_TEMPLATE.replace("@@LAUNCHER_PY_B64@@", launcher_py_b64)
        .replace("@@LAUNCHER_SH_B64@@", launcher_sh_b64)
        .replace("@@CONFIG_EXAMPLE_B64@@", config_example_b64)
    )

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(script)
    os.chmod(OUT, 0o755)
    print("wrote", OUT)


# The .command installer. It is a POSIX shell script; Finder runs it in Terminal
# on double-click. It decodes the embedded files into an install directory and
# drops the native-messaging manifest into each browser it finds.
INSTALLER_TEMPLATE = r'''#!/bin/sh
# CompuOffice macOS bridge — self-contained installer.
# Double-click this file in Finder to install. It installs a Chrome Native
# Messaging host so the CompuOffice/CompuTax Chrome extension can reach a
# CompuOffice server from this Mac.
#
# This installer contains NO CompuOffice application code. It only installs the
# small bridge that connects Chrome to a CompuOffice server on your network.

set -e

HOST_NAME="compuoffice.native.chrome"
EXT_ID="aginpdbdkhdcfgdndhbagboecblnhfgp"
INSTALL_DIR="$HOME/Library/Application Support/CompuOfficeBridge"

printf '\n=== CompuOffice macOS bridge installer ===\n\n'

# --- 1. write the bridge files ------------------------------------------------
mkdir -p "$INSTALL_DIR"

decode() {
    # decode base64 (macOS base64 uses -D, GNU uses -d; -D works on macOS)
    base64 -D 2>/dev/null || base64 -d
}

cat <<'PYEOF' | decode > "$INSTALL_DIR/launcher.py"
@@LAUNCHER_PY_B64@@
PYEOF

cat <<'SHEOF' | decode > "$INSTALL_DIR/launcher.sh"
@@LAUNCHER_SH_B64@@
SHEOF

cat <<'CFGEOF' | decode > "$INSTALL_DIR/config.example.json"
@@CONFIG_EXAMPLE_B64@@
CFGEOF

chmod +x "$INSTALL_DIR/launcher.sh" "$INSTALL_DIR/launcher.py"
echo "Installed bridge files to:"
echo "  $INSTALL_DIR"

# --- 2. check python3 ---------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1 \
    && [ ! -x /usr/bin/python3 ] \
    && [ ! -x /opt/homebrew/bin/python3 ] \
    && [ ! -x /usr/local/bin/python3 ]; then
    printf '\nNOTE: python3 was not found. The bridge needs it to run.\n'
    printf '      Install it by running this in Terminal:  xcode-select --install\n'
fi

# --- 3. install the manifest into each browser --------------------------------
LAUNCHER="$INSTALL_DIR/launcher.sh"
SUPPORT="$HOME/Library/Application Support"
TARGETS="
$SUPPORT/Google/Chrome/NativeMessagingHosts
$SUPPORT/Google/Chrome Beta/NativeMessagingHosts
$SUPPORT/Google/Chrome Canary/NativeMessagingHosts
$SUPPORT/Chromium/NativeMessagingHosts
$SUPPORT/Microsoft Edge/NativeMessagingHosts
$SUPPORT/BraveSoftware/Brave-Browser/NativeMessagingHosts
"

installed=0
# Split on newlines only: the paths contain a space ("Application Support").
OLDIFS=$IFS
IFS='
'
for target in $TARGETS; do
    [ -n "$target" ] || continue
    parent=$(dirname "$target")
    [ -d "$parent" ] || continue
    mkdir -p "$target"
    cat > "$target/$HOST_NAME.json" <<JSONEOF
{
  "name": "$HOST_NAME",
  "description": "CompuOffice macOS native-messaging bridge",
  "path": "$LAUNCHER",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXT_ID/"
  ]
}
JSONEOF
    echo "  registered for: $parent"
    installed=$((installed + 1))
done
IFS=$OLDIFS

printf '\n'
if [ "$installed" -eq 0 ]; then
    echo "No Chromium-family browser found. Open Chrome once, then run this again."
else
    echo "Registered the bridge for $installed browser(s)."
fi

# --- 3b. point the bridge at your CompuOffice server --------------------------
# Your app/database/data are on another machine; tell the bridge where that
# server is, so Chrome on this Mac can reach it. Written to config.json.
printf '\n--- Connect to your CompuOffice server ---\n'
printf 'On the PC where CompuOffice works, the Chrome address bar shows something\n'
printf 'like  http://SERVER-NAME:PORT  when it is open. Enter those below.\n\n'

SERVER=""
PORT=""
printf 'Server name or IP (blank = auto-detect on this network): '
read -r SERVER || SERVER=""
if [ -n "$SERVER" ]; then
    printf 'Server port (blank = 8080): '
    read -r PORT || PORT=""
    [ -n "$PORT" ] || PORT="8080"
    cat > "$INSTALL_DIR/config.json" <<CFGJSON
{
  "server_host": "$SERVER",
  "server_port": $PORT
}
CFGJSON
    echo "Saved: bridge will use http://$SERVER:$PORT"
else
    echo "No server entered — the bridge will try to auto-detect it on your network."
    echo "You can set it later by editing:"
    echo "  $INSTALL_DIR/config.json"
fi

# --- 4. next steps ------------------------------------------------------------
printf '\nNext steps:\n'
printf '  1. Install the CompuOffice Chrome extension (id %s)\n' "$EXT_ID"
printf '     in Chrome on this Mac.\n'
printf '  2. Fully quit and reopen Chrome.\n'
printf '  3. Open CompuOffice the same way you do on the PC.\n\n'
printf 'Tip: you can often just open  http://<your-server>:<port>  directly in\n'
printf 'Chrome on this Mac. Try that first — if it works, you may not even need\n'
printf 'the extension.\n\n'
printf 'To uninstall: delete the files named %s.json from each browser'"'"'s\n' "$HOST_NAME"
printf 'NativeMessagingHosts folder, and remove %s\n\n' "$INSTALL_DIR"

printf 'Done. You can close this window.\n\n'
'''

if __name__ == "__main__":
    main()
