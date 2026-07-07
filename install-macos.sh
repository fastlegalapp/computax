#!/bin/sh
# Install the CompuOffice native-messaging host for Chromium-family browsers on
# macOS. This is the macOS equivalent of what CompuOfficeExt.exe does on Windows
# by writing the registry key
#   SOFTWARE\Google\Chrome\NativeMessagingHosts\compuoffice.native.chrome
# On macOS the "registration" is just a JSON manifest dropped into each
# browser's NativeMessagingHosts directory.

set -e

HOST_NAME="compuoffice.native.chrome"
DIR=$(cd "$(dirname "$0")" && pwd)
SRC_MANIFEST="$DIR/host/$HOST_NAME.json"
LAUNCHER="$DIR/host/launcher.sh"

if [ ! -f "$SRC_MANIFEST" ]; then
    echo "error: cannot find $SRC_MANIFEST" >&2
    exit 1
fi

# The host runs on python3. Warn early if it is missing so the failure is not a
# mysterious "host disconnected" later inside Chrome.
if ! command -v python3 >/dev/null 2>&1 \
    && [ ! -x /usr/bin/python3 ] \
    && [ ! -x /opt/homebrew/bin/python3 ] \
    && [ ! -x /usr/local/bin/python3 ]; then
    echo "warning: python3 was not found on PATH." >&2
    echo "         Install it with:  xcode-select --install" >&2
    echo "         (Installing the host anyway; it will not run until python3 exists.)" >&2
fi

chmod +x "$LAUNCHER" "$DIR/host/launcher.py" 2>/dev/null || true

# Target manifest directories per browser (user-level installs).
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
    # Only install for browsers that are actually present on this Mac.
    if [ ! -d "$parent" ]; then
        continue
    fi
    mkdir -p "$target"
    # Write the manifest with the absolute launcher path substituted in.
    sed "s#__LAUNCHER_PATH__#$LAUNCHER#g" "$SRC_MANIFEST" > "$target/$HOST_NAME.json"
    echo "installed: $target/$HOST_NAME.json"
    installed=$((installed + 1))
done
IFS=$OLDIFS

if [ "$installed" -eq 0 ]; then
    echo "No Chromium-family browser profile found under \"$SUPPORT\"." >&2
    echo "Open Chrome once, then re-run this installer." >&2
    exit 1
fi

echo ""
echo "Done. Installed the host for $installed browser(s)."
echo "Native host name: $HOST_NAME"
echo "Launcher:         $LAUNCHER"
echo ""
echo "Next steps:"
echo "  1. Install the CompuOffice Chrome extension (id aginpdbdkhdcfgdndhbagboecblnhfgp)."
echo "  2. If your CompuOffice server is not on localhost, copy"
echo "     host/config.example.json to host/config.json and set server_host/server_port."
echo "  3. Fully quit and reopen Chrome so it picks up the new host."
