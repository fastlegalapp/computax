#!/usr/bin/env python3
"""
Generate a copy-paste Terminal block that:
  1. writes the compat extension to ~/CompuOfficeExtension (manifest + JS), and
  2. re-writes the native-host manifests so they authorize the extension's ID.
The user then loads ~/CompuOfficeExtension via chrome://extensions (Load unpacked).

Run:  python3 build-extension-paste.py > dist/extension-paste.sh
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def read(p):
    with open(os.path.join(HERE, p), "r") as fh:
        return fh.read().rstrip("\n")


MANIFEST = read("extension/manifest.json")
BACKGROUND = read("extension/background.js")
CONTENT = read("extension/content.js")
INJECT = read("extension/inject.js")

BLOCK = r'''E="$HOME/CompuOfficeExtension"; mkdir -p "$E"
cat > "$E/manifest.json" <<'MANIFESTEOF'
@@MANIFEST@@
MANIFESTEOF
cat > "$E/background.js" <<'BGEOF'
@@BACKGROUND@@
BGEOF
cat > "$E/content.js" <<'CTEOF'
@@CONTENT@@
CTEOF
cat > "$E/inject.js" <<'INJEOF'
@@INJECT@@
INJEOF
echo "Extension written to: $E"

# Re-authorize the extension in the native host manifests (adds its ID).
D="$HOME/Library/Application Support/CompuOfficeBridge"
for B in "Google/Chrome" "Google/Chrome Beta" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Chromium"; do
  P="$HOME/Library/Application Support/$B"; [ -d "$P" ] || continue
  mkdir -p "$P/NativeMessagingHosts"
  cat > "$P/NativeMessagingHosts/compuoffice.native.chrome.json" <<JEOF
{"name":"compuoffice.native.chrome","description":"compuoffice native chrome","path":"$D/launcher.sh","type":"stdio","allowed_origins":["chrome-extension://ohcokhailmiiebggggbllhllifdldegk/","chrome-extension://aginpdbdkhdcfgdndhbagboecblnhfgp/","chrome-extension://pddegllmnldjcaonfinbgaonhfjdbckk/","chrome-extension://ikeipdbjlaejlcjldjjhlpdnhlehmdap/"]}
JEOF
  echo "re-authorized: $B"
done
# If a copy was loaded from Downloads, update it too (that is what Chrome runs).
if [ -d "$HOME/Downloads/CompuOfficeExtension" ]; then
  cp -f "$E"/manifest.json "$E"/background.js "$E"/content.js "$E"/inject.js "$HOME/Downloads/CompuOfficeExtension/"
  echo "Updated the Downloads copy too."
fi
echo ""
echo "Now in Chrome: chrome://extensions -> click the RELOAD (circular arrow)"
echo "icon on 'CompuOffice Bridge'. If not loaded yet: Developer mode ON ->"
echo "Load unpacked -> choose:  $E"
echo "Then reload your CompuOffice tab (Cmd-R)."
'''

out = (BLOCK
       .replace("@@MANIFEST@@", MANIFEST)
       .replace("@@BACKGROUND@@", BACKGROUND)
       .replace("@@CONTENT@@", CONTENT)
       .replace("@@INJECT@@", INJECT))
print(out)
