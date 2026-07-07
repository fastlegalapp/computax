#!/bin/sh
# Remove the CompuOffice native-messaging host manifests installed by
# install-macos.sh.

HOST_NAME="compuoffice.native.chrome"
SUPPORT="$HOME/Library/Application Support"
TARGETS="
$SUPPORT/Google/Chrome/NativeMessagingHosts
$SUPPORT/Google/Chrome Beta/NativeMessagingHosts
$SUPPORT/Google/Chrome Canary/NativeMessagingHosts
$SUPPORT/Chromium/NativeMessagingHosts
$SUPPORT/Microsoft Edge/NativeMessagingHosts
$SUPPORT/BraveSoftware/Brave-Browser/NativeMessagingHosts
"

removed=0
for target in $TARGETS; do
    f="$target/$HOST_NAME.json"
    if [ -f "$f" ]; then
        rm -f "$f"
        echo "removed: $f"
        removed=$((removed + 1))
    fi
done

if [ "$removed" -eq 0 ]; then
    echo "Nothing to remove; no manifests found."
else
    echo "Removed $removed manifest(s). Restart Chrome to finish."
fi
