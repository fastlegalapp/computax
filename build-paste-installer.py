#!/usr/bin/env python3
"""
Generate a copy-paste Terminal installer that embeds the real protocol host
(host/launcher.py) as base64, plus launcher.sh and the 3-ID native manifest.
No download, no server prompt (the native host does not handle the connection).

Run:  python3 build-paste-installer.py > dist/paste-installer.sh
"""
import base64
import os
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "host/launcher.py"), "rb") as fh:
    PY_B64 = "\n".join(textwrap.wrap(base64.b64encode(fh.read()).decode(), 100))

with open(os.path.join(HERE, "host/launcher.sh"), "r") as fh:
    LAUNCHER_SH = fh.read().rstrip("\n")

TEMPLATE = r'''D="$HOME/Library/Application Support/CompuOfficeBridge"; mkdir -p "$D"
( base64 -D 2>/dev/null || base64 -d ) > "$D/launcher.py" <<'PYB64'
@@PY_B64@@
PYB64
cat > "$D/launcher.sh" <<'SHEOF'
@@LAUNCHER_SH@@
SHEOF
chmod +x "$D/launcher.sh" "$D/launcher.py"
n=0
for B in "Google/Chrome" "Google/Chrome Beta" "Google/Chrome Canary" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Chromium"; do
  P="$HOME/Library/Application Support/$B"
  [ -d "$P" ] || continue
  mkdir -p "$P/NativeMessagingHosts"
  cat > "$P/NativeMessagingHosts/compuoffice.native.chrome.json" <<JEOF
{
  "name": "compuoffice.native.chrome",
  "description": "compuoffice native chrome",
  "path": "$D/launcher.sh",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://ohcokhailmiiebggggbllhllifdldegk/",
    "chrome-extension://aginpdbdkhdcfgdndhbagboecblnhfgp/",
    "chrome-extension://pddegllmnldjcaonfinbgaonhfjdbckk/"
  ]
}
JEOF
  echo "installed for: $B"; n=$((n+1))
done
[ "$n" -eq 0 ] && echo "No Chromium-family browser found — open Chrome once, then re-run."
echo "Bridge installed. Now install the CompuTax extension, then fully quit and reopen Chrome."
'''

out = TEMPLATE.replace("@@PY_B64@@", PY_B64).replace("@@LAUNCHER_SH@@", LAUNCHER_SH)
print(out)
