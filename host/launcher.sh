#!/bin/sh
# Wrapper that Chrome launches as the native-messaging host.
#
# Chrome starts native hosts with a minimal environment, so `#!/usr/bin/env
# python3` in launcher.py is not reliable on its own — PATH may not contain the
# python3 the user installed. This wrapper locates a python3 explicitly and
# execs the real host with it.

DIR=$(cd "$(dirname "$0")" && pwd)

find_python() {
    for c in \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /usr/bin/python3 \
        "$(command -v python3 2>/dev/null)"
    do
        if [ -x "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    # Fall back to the Xcode Command Line Tools python3, if present.
    if /usr/bin/xcrun --find python3 >/dev/null 2>&1; then
        /usr/bin/xcrun --find python3
        return 0
    fi
    return 1
}

PY=$(find_python)
if [ -z "$PY" ]; then
    # Emit a native-messaging-framed error so Chrome sees a real reply, not just
    # a crashed host. Frame = 4-byte little-endian length prefix + JSON body.
    BODY='{"ok":false,"error":"python3 not found on this Mac. Install the Xcode Command Line Tools (xcode-select --install) or Homebrew python3."}'
    LEN=$(printf '%s' "$BODY" | wc -c | tr -d ' ')
    # Encode the 4-byte little-endian length as octal escapes; POSIX printf
    # supports \ooo portably (dash and macOS bash both do), unlike \xHH.
    B0=$(printf '%03o' "$((LEN % 256))")
    B1=$(printf '%03o' "$(((LEN / 256) % 256))")
    B2=$(printf '%03o' "$(((LEN / 65536) % 256))")
    B3=$(printf '%03o' "$(((LEN / 16777216) % 256))")
    printf "\\$B0\\$B1\\$B2\\$B3%s" "$BODY"
    # Also log to stderr so it shows in Chrome's native-host logs.
    echo "compuoffice.native.chrome: python3 not found" >&2
    exit 1
fi

exec "$PY" "$DIR/launcher.py"
