#!/bin/sh
# Set up a Wine environment on macOS to run the CompuOffice / CompuTax Windows
# app WITHOUT installing Windows. This installs a Wine engine, a dedicated Wine
# prefix, and the .NET Framework CompuOffice needs, then (optionally) runs the
# CompuOffice installer you point it at.
#
# Usage:
#   ./setup-wine-macos.sh                 # set up the environment only
#   ./setup-wine-macos.sh /path/Setup.exe # set up, then run that installer
#
# Read docs/wine-setup-mac.md first. The database (SQL Server) is handled
# separately by scripts/compuoffice-db.sh.

set -e

PREFIX="$HOME/CompuOffice-Wine"     # dedicated Wine prefix (keeps things clean)
export WINEPREFIX="$PREFIX"
export WINEARCH="win64"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }

# --- 0. sanity: must be macOS -------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    warn "This script is for macOS. Detected: $(uname -s)."
    exit 1
fi

ARCH="$(uname -m)"   # arm64 (Apple Silicon) or x86_64 (Intel)
say "CompuOffice-on-Mac (Wine) setup — detected $ARCH Mac"

# --- 1. Homebrew --------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    say "Homebrew is required and was not found."
    info "Install it by pasting this into Terminal, then re-run this script:"
    info '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
info "Homebrew found: $(brew --prefix)"

# --- 2. Wine engine -----------------------------------------------------------
# We use a CLI-scriptable Wine. On Apple Silicon this runs via Rosetta 2.
if ! command -v wine >/dev/null 2>&1 && ! command -v wine64 >/dev/null 2>&1; then
    if [ "$ARCH" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
        say "Installing Rosetta 2 (needed to run x86 Wine on Apple Silicon)"
        softwareupdate --install-rosetta --agree-to-license || \
            warn "Rosetta install skipped/failed — continue only if already present."
    fi
    say "Installing Wine (this can take several minutes)"
    # gcenx's wine builds are the most reliable on macOS; fall back to wine-stable.
    brew install --cask --no-quarantine gcenx/wine/wine-crossover 2>/dev/null \
        || brew install --cask --no-quarantine wine-stable \
        || { warn "Could not install Wine via brew. See docs/wine-setup-mac.md for Whisky/CrossOver."; exit 1; }
else
    info "Wine already installed: $(command -v wine wine64 | head -n1)"
fi

WINE="$(command -v wine64 || command -v wine)"
info "Using wine: $WINE"

# --- 3. winetricks ------------------------------------------------------------
if ! command -v winetricks >/dev/null 2>&1; then
    say "Installing winetricks"
    brew install winetricks
fi

# --- 4. create the Wine prefix ------------------------------------------------
say "Creating Wine prefix at $PREFIX"
mkdir -p "$PREFIX"
"$WINE" wineboot --init >/dev/null 2>&1 || true
info "Prefix initialised."

# --- 5. .NET Framework + fonts CompuOffice needs ------------------------------
say "Installing .NET Framework + fonts into the prefix (slow; be patient)"
warn "If dotnet48 fails on Apple Silicon, use Whisky or CrossOver instead — they"
warn "ship better .NET support. See docs/wine-setup-mac.md, section 'If .NET fails'."
winetricks -q corefonts || warn "corefonts step had issues (non-fatal)."
winetricks -q dotnet48   || warn "dotnet48 step had issues — see the doc for alternatives."

# --- 6. optionally run the CompuOffice installer ------------------------------
if [ -n "$1" ]; then
    if [ ! -f "$1" ]; then
        warn "Installer not found: $1"
        exit 1
    fi
    say "Launching the CompuOffice installer under Wine"
    info "Follow the installer's on-screen steps. When it asks for a database"
    info "server, point it at the SQL Server from scripts/compuoffice-db.sh"
    info "(default: localhost,1433 — user 'sa')."
    "$WINE" "$1" || warn "Installer exited non-zero — check the messages above."
else
    say "Environment ready."
    info "You do not have the CompuOffice installer yet? Download the full"
    info "CompuOffice setup from CompuTax (your account / update.computax.in)."
    info "Then run:  ./setup-wine-macos.sh /path/to/CompuOfficeSetup.exe"
fi

say "Next steps"
info "1. Start the database:   ./scripts/compuoffice-db.sh up"
info "2. Run CompuOffice:      $WINE \"\$WINEPREFIX/drive_c/.../CompuOffice.exe\""
info "   (or launch it from the Wine Start Menu shortcut)"
info "3. Point CompuOffice's database settings at:  localhost,1433"
info ""
info "Full guide + troubleshooting: docs/wine-setup-mac.md"
