# Running the CompuOffice / CompuTax desktop app on a Mac

The native-messaging bridge in this repo connects Chrome to a CompuOffice
**server**. It does not run the CompuOffice desktop application, which is
Windows-only. If you need the actual application on a Mac, use one of these:

1. **Windows in a VM (most reliable).**
   - Apple Silicon (M1–M4): [Parallels Desktop](https://www.parallels.com) +
     Windows 11 ARM, or the free [UTM](https://mac.getutm.app). Install
     CompuOffice inside Windows exactly as on a PC.
   - Intel Macs: Parallels, VMware Fusion (free for personal use), or Boot Camp.
   - Everything — Chrome, this launcher, the desktop app — then works as on a PC.

2. **CrossOver / Wine.** [CrossOver Mac](https://www.codeweavers.com/crossover)
   can sometimes run Windows apps without a full Windows license. CompuOffice is
   a heavy networked app, so test with the free trial before buying.

3. **Remote into the Windows PC.** If the PC where it already works stays on, use
   Microsoft Remote Desktop, Chrome Remote Desktop, or AnyDesk/TeamViewer.

4. **Ask CompuTax** whether a fully browser-based (no local install) edition is
   available for your modules — if so, this bridge plus a reachable server may be
   all you need.

## When this bridge alone is enough

If your office runs a CompuOffice **server** on a Windows machine on the LAN and
that server serves its UI over HTTP, a Mac with Chrome + this bridge can reach it
without running any Windows app on the Mac itself. Point `host/config.json` at
the server's host and port and you are done.
