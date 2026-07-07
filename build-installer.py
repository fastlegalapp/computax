#!/usr/bin/env python3
"""
Build a self-contained macOS installer (.command) that embeds the CompuOffice
native-messaging host (host/launcher.py + host/launcher.sh) and installs it for
every Chromium-family browser on the Mac. Double-click in Finder to run (or, if
the download loses its execute bit, run it as `sh <file>`).

Run:  python3 build-installer.py
Out:  dist/Install-CompuOffice-Bridge.command
"""
import base64
import os
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "dist")
OUT = os.path.join(OUT_DIR, "Install-CompuOffice-Bridge.command")


def b64_wrapped(path):
    with open(os.path.join(HERE, path), "rb") as fh:
        return "\n".join(textwrap.wrap(base64.b64encode(fh.read()).decode(), 100))


TEMPLATE = r'''#!/bin/sh
# CompuOffice macOS bridge — self-contained installer.
# Installs the native-messaging host that answers the CompuTax Chrome extension
# so it stops reporting an "extension issue" on a Mac. Contains no CompuOffice
# application code.
#
# Run by double-clicking in Finder, or:  sh Install-CompuOffice-Bridge.command

set -e
INSTALL_DIR="$HOME/Library/Application Support/CompuOfficeBridge"
mkdir -p "$INSTALL_DIR"
printf '\n=== CompuOffice macOS bridge installer ===\n\n'

decode() { base64 -D 2>/dev/null || base64 -d; }

cat <<'PYEOF' | decode > "$INSTALL_DIR/launcher.py"
@@PY_B64@@
PYEOF
cat <<'SHEOF' | decode > "$INSTALL_DIR/launcher.sh"
@@SH_B64@@
SHEOF
chmod +x "$INSTALL_DIR/launcher.py" "$INSTALL_DIR/launcher.sh"
echo "Installed host to: $INSTALL_DIR"

if ! command -v python3 >/dev/null 2>&1 \
    && [ ! -x /usr/bin/python3 ] && [ ! -x /opt/homebrew/bin/python3 ] \
    && [ ! -x /usr/local/bin/python3 ]; then
    echo "NOTE: python3 not found. Install it:  xcode-select --install"
fi

n=0
for B in "Google/Chrome" "Google/Chrome Beta" "Google/Chrome Canary" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Chromium"; do
    P="$HOME/Library/Application Support/$B"
    [ -d "$P" ] || continue
    mkdir -p "$P/NativeMessagingHosts"
    cat > "$P/NativeMessagingHosts/compuoffice.native.chrome.json" <<JEOF
{
  "name": "compuoffice.native.chrome",
  "description": "compuoffice native chrome",
  "path": "$INSTALL_DIR/launcher.sh",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://ohcokhailmiiebggggbllhllifdldegk/",
    "chrome-extension://aginpdbdkhdcfgdndhbagboecblnhfgp/",
    "chrome-extension://pddegllmnldjcaonfinbgaonhfjdbckk/"
  ]
}
JEOF
    echo "registered for: $B"; n=$((n+1))
done
echo ""
[ "$n" -eq 0 ] && echo "No Chromium-family browser found. Open Chrome once, then re-run." \
              || echo "Registered the bridge for $n browser(s)."

printf '\nNext steps:\n'
printf '  1. Install the CompuTax Chrome extension in Chrome on this Mac.\n'
printf '  2. Fully quit and reopen Chrome.\n'
printf '  3. Open your CompuOffice web address as usual.\n\n'
printf 'Done. You can close this window.\n\n'
'''


def main():
    script = (TEMPLATE
              .replace("@@PY_B64@@", b64_wrapped("host/launcher.py"))
              .replace("@@SH_B64@@", b64_wrapped("host/launcher.sh")))
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(script)
    os.chmod(OUT, 0o755)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
