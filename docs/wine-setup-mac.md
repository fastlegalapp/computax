# Run CompuOffice / CompuTax on a Mac with Wine — no Windows

> **Do you actually need this?** If your CompuOffice **server, database, and data
> live on another machine** and you only *browse* it, you do **not** need Wine or
> Docker — just install the browser bridge from the main [README](../README.md)
> and point it at your server. This Wine guide is only for running the whole app
> standalone on a Mac with no server.


This runs the actual CompuOffice Windows app on your Mac **without installing
Windows**. Two pieces run side by side, both on macOS:

1. **The app** (`CompuOffice.exe`) runs under **Wine** — a compatibility layer
   that translates Windows calls to macOS. Wine is *not* Windows; nothing
   Microsoft-OS is installed.
2. **The database** (SQL Server, which CompuOffice requires) runs as a **Linux
   container** via Docker. Microsoft publishes SQL Server for Linux, so no
   Windows is needed for the database either.

> **Set expectations honestly.** CompuOffice is a heavy .NET app on SQL Server.
> This setup works, but it is not vendor-supported and some modules may misbehave
> under Wine. Do a test run before you rely on it for filing season. If you hit a
> wall, the fallback that always works is a cloud Windows desktop (see
> [running-computax-on-mac.md](running-computax-on-mac.md)) — still nothing
> installed on your Mac.

---

## What you need

- A Mac (Apple Silicon M1–M4, or Intel).
- About 15 GB free disk and ~1 hour the first time.
- **The full CompuOffice installer** from CompuTax — download it from your
  CompuTax account or `update.computax.in`. (The `CompuOfficeExt.exe` you may
  already have is only the browser launcher, not the application.)

---

## Step 1 — Install the app environment (Wine)

From this repo:

```sh
cd computax
./scripts/setup-wine-macos.sh
```

The script installs Homebrew's Wine, creates a dedicated Wine "prefix" at
`~/CompuOffice-Wine`, and adds the .NET Framework CompuOffice needs.

### Easier alternative: Whisky (Apple Silicon, free, GUI)

If you prefer clicking to Terminal, or the script's `dotnet48` step fails, use
**Whisky** instead — it bundles a modern Wine (CrossOver-based) with much better
.NET support:

```sh
brew install --cask whisky
```

Then open Whisky ▸ **New Bottle** (Windows 10) ▸ open the bottle ▸ **Run…** and
select the CompuOffice installer. Whisky handles the Wine details for you.
**CrossOver** (paid, ~$74) is the most polished option and worth it if Whisky
struggles.

---

## Step 2 — Start the database (SQL Server in Docker)

Install Docker once, if you do not have it:

```sh
brew install --cask docker      # Docker Desktop (GUI), or:
brew install colima docker      # Colima (lightweight CLI) + 'colima start'
```

Then bring up SQL Server:

```sh
./scripts/compuoffice-db.sh up
./scripts/compuoffice-db.sh status     # wait until "accepting connections"
```

This gives you SQL Server on **`localhost,1433`**, login **`sa`**, with the
password printed by the script (override with `SA_PASSWORD=... ./compuoffice-db.sh up`).

On Apple Silicon the SQL Server image runs under emulation — a little slower to
start, but it works.

---

## Step 3 — Install CompuOffice

```sh
./scripts/setup-wine-macos.sh /path/to/CompuOfficeSetup.exe
```

Work through the installer. When it asks for a **database server / SQL Server
instance**, point it at:

```
localhost,1433
```

with **SQL Server authentication**, login `sa`, and the password from Step 2.

> **The instance-name snag.** CompuOffice on Windows uses a *named* SQL instance
> (`mssql$compuoffice`). The Docker container is a *default* instance on port
> 1433. If CompuOffice will not let you type `localhost,1433` and insists on an
> instance name, see **Troubleshooting ▸ Named instance** below.

---

## Step 4 — Run it

```sh
# start the DB if it is not running
./scripts/compuoffice-db.sh up

# launch the app (path depends on where the installer put it)
WINEPREFIX="$HOME/CompuOffice-Wine" wine \
  "$HOME/CompuOffice-Wine/drive_c/Program Files (x86)/CompuOffice/CompuOffice.exe"
```

Or use the Start-Menu shortcut Wine created. With Whisky/CrossOver, just click
the app inside the bottle.

---

## Troubleshooting

### If .NET (`dotnet48`) fails under plain Wine
This is common on Apple Silicon. Switch to **Whisky** or **CrossOver** — their
bundled Wine installs .NET Framework far more reliably. Create a fresh bottle and
run the CompuOffice installer inside it.

### Named instance (`mssql$compuoffice`)
Some CompuOffice builds hard-expect an instance called `compuoffice`. Options:
- In CompuOffice's DB settings, try `localhost,1433` or `127.0.0.1,1433` first —
  many builds accept host,port directly.
- If it demands `SERVER\compuoffice`, you can run the container so it registers a
  named instance, or use a connection alias. Ask CompuTax support for the exact
  connection string their client expects, then adjust. (Named-instance discovery
  uses SQL Browser on UDP 1434, which the container does not expose by default.)

### The app opens but can't reach the database
- `./scripts/compuoffice-db.sh status` — confirm it says *accepting connections*.
- Confirm the port: `docker ps` should show `0.0.0.0:1433->1433/tcp`.
- Firewall/VPN on the Mac can block localhost:1433 in rare setups.

### The browser-launch / Chrome integration
If you also want the CompuOffice **Chrome** integration (the part your original
`.exe` handled), install the macOS native-messaging bridge from this repo — see
the main [README](../README.md). Point its `config.json` at `localhost` and the
CompuOffice web port.

### Nothing works / filing deadline pressure
Use a **cloud Windows desktop** and access it from your Mac's browser
([running-computax-on-mac.md](running-computax-on-mac.md)). It always works and
still installs nothing on your Mac.

---

## Uninstall / start over

```sh
./scripts/compuoffice-db.sh destroy      # remove DB + its data
rm -rf "$HOME/CompuOffice-Wine"          # remove the Wine prefix (the app)
```
