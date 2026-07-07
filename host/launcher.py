#!/usr/bin/env python3
"""
CompuOffice macOS native-messaging host.

A macOS reimplementation of the Windows `CompuOffice.ChromeNative.exe` (by
Professional Softec Pvt. Ltd.), reverse-engineered from that binary so the
CompuOffice/CompuTax Chrome extension gets the same answers on a Mac as it does
on Windows. The extension refuses to run ("extension issue") until this host
responds to its startup handshake.

Wire format: Chrome Native Messaging — a 4-byte little-endian length, then that
many bytes of UTF-8 JSON, on stdin/stdout.

Protocol (mirrors the Windows host):
  request  : {"action": <str>, "version": <str?>, "readOnly": <bool?>, "ID": <any?>, ...}
  responses (shapes copied from the Windows host's serializer):
    version        -> {Status, action, Version, ID}
    checkextension -> {Status, action, ID}
    macaddress     -> {Status, version, updateRequired, MacAddress, ID}
    selfUpdate     -> {Status, version, updateRequired, MacAddress, ID}
    savefile       -> {Status, action, ID}
    runfile        -> {Status, action, Output, ID}
    printfile      -> {Status, action, ID}
    unknown        -> {Status: "Invalid action", Error, ID}
Status values: "Success", "Failed", "already updated", "Invalid action".

The file operations (savefile/runfile/printfile) are best-effort on macOS: the
Windows request field names for the file name / data are not fully known from
the binary, so we accept several common spellings and save to the Desktop
(the Windows host uses the desktop too). The startup handshake — the part that
clears the "extension issue" — is matched exactly and needs no file payload.
"""

import base64
import json
import os
import struct
import subprocess
import sys
import uuid

# Report the same version the Windows host reports, and never ask the app to
# update (a Windows-only self-update would just fail on a Mac).
VERSION = "1.0.9202.22305"
DESKTOP = os.path.join(os.path.expanduser("~"), "Desktop")


# --- native messaging framing ------------------------------------------------


def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        return None
    (length,) = struct.unpack("<I", raw_len)
    if length < 0:
        return None
    data = sys.stdin.buffer.read(length)
    if len(data) < length:
        return None
    return json.loads(data.decode("utf-8"))


def send_message(obj):
    encoded = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


# --- helpers -----------------------------------------------------------------


def mac_address():
    """Return this Mac's MAC address as XX-XX-XX-XX-XX-XX (Windows host style)."""
    node = uuid.getnode()
    return "-".join("%02X" % ((node >> ele) & 0xFF) for ele in range(40, -1, -8))


def _get(msg, *names, default=None):
    for n in names:
        if isinstance(msg, dict) and n in msg and msg[n] not in (None, ""):
            return msg[n]
    return default


def _msg_id(msg):
    return _get(msg, "ID", "id", "Id")


def _resolve_file(msg):
    """
    Best-effort extraction of (filename, bytes) from a savefile/printfile/runfile
    request. Accepts several field spellings; returns (name, data_or_None).
    """
    name = _get(msg, "fileName", "FileName", "filename", "name", "Name",
                default="CompuOffice_output")
    b64 = _get(msg, "data", "fileData", "FileData", "content", "Content", "base64")
    if b64 is not None:
        try:
            return name, base64.b64decode(b64)
        except (ValueError, TypeError):
            return name, None
    return name, None


def _save_to_desktop(name, data):
    os.makedirs(DESKTOP, exist_ok=True)
    # keep it inside Desktop even if name contains path separators
    safe = os.path.basename(str(name)) or "CompuOffice_output"
    path = os.path.join(DESKTOP, safe)
    with open(path, "wb") as fh:
        fh.write(data)
    return path


# --- action handlers ---------------------------------------------------------


def handle(msg):
    action = str(_get(msg, "action", "Action", "type", "cmd", default="")).strip()
    key = action.lower()
    mid = _msg_id(msg)

    if key == "version":
        return {"Status": "Success", "action": "version", "Version": VERSION, "ID": mid}

    if key == "checkextension":
        return {"Status": "Success", "action": "checkextension", "ID": mid}

    if key == "macaddress":
        return {"Status": "Success", "version": VERSION, "updateRequired": False,
                "MacAddress": mac_address(), "ID": mid}

    if key == "selfupdate":
        # Already current — do not trigger the Windows-only updater.
        return {"Status": "already updated", "version": VERSION,
                "updateRequired": False, "MacAddress": mac_address(), "ID": mid}

    if key == "savefile":
        name, data = _resolve_file(msg)
        if data is None:
            return {"Status": "Failed", "Error": "no file data", "ID": mid}
        try:
            path = _save_to_desktop(name, data)
            if _get(msg, "readOnly", "ReadOnly") is True:
                try:
                    os.chmod(path, 0o444)
                except OSError:
                    pass
            return {"Status": "Success", "action": "savefile", "ID": mid}
        except OSError as exc:
            return {"Status": "Failed", "Error": str(exc), "ID": mid}

    if key == "runfile":
        name, data = _resolve_file(msg)
        try:
            if data is not None:
                path = _save_to_desktop(name, data)
            else:
                path = _get(msg, "path", "filePath", "FilePath", "url", "URL")
            if not path:
                return {"Status": "Failed", "Error": "nothing to run", "ID": mid}
            subprocess.Popen(["/usr/bin/open", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {"Status": "Success", "action": "runfile", "Output": str(path), "ID": mid}
        except OSError as exc:
            return {"Status": "Failed", "Error": str(exc), "ID": mid}

    if key == "printfile":
        name, data = _resolve_file(msg)
        try:
            if data is not None:
                path = _save_to_desktop(name, data)
            else:
                path = _get(msg, "path", "filePath", "FilePath")
            if not path:
                return {"Status": "Failed", "Error": "no file to print", "ID": mid}
            # Send to the default printer; falls back to opening for manual print.
            try:
                subprocess.Popen(["/usr/bin/lp", path],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                subprocess.Popen(["/usr/bin/open", path])
            return {"Status": "Success", "action": "printfile", "ID": mid}
        except OSError as exc:
            return {"Status": "Failed", "Error": str(exc), "ID": mid}

    return {"Status": "Invalid action", "Error": "Invalid action", "ID": mid}


def main():
    while True:
        try:
            msg = read_message()
        except (ValueError, OSError):
            break
        if msg is None:
            break
        try:
            reply = handle(msg)
        except Exception as exc:  # keep the host alive on any single bad message
            reply = {"Status": "Failed", "Error": "internal error: %s" % exc}
        try:
            send_message(reply)
        except OSError:
            break


if __name__ == "__main__":
    main()
