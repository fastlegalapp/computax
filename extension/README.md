# CompuOffice compat extension (macOS)

An independent, best-effort Chrome extension that lets the CompuOffice/CompuTax
web app talk to the macOS native helper in this repo. It contains no CompuOffice
code — it only bridges page messages to the native host `compuoffice.native.chrome`
and announces its presence so the page's "extension installed?" check passes.

Because CompuOffice's real extension is not on the Chrome Web Store and its
page↔extension message format is not published, this bridge is instrumented:
`content.js` and `background.js` log every message to the console. Load it, open
the CompuOffice site, and check the console (page console + the extension's
service-worker console) to see the exact requests — then the relay in
`content.js` / `background.js` can be tuned to match if needed.

## Load it (unpacked)

1. Chrome → `chrome://extensions` → enable **Developer mode**.
2. **Load unpacked** → select this `extension/` folder.
3. Confirm the ID is `ikeipdbjlaejlcjldjjhlpdnhlehmdap` (pinned by `key` in
   `manifest.json`; this ID is authorized in the native host manifest).
4. Fully quit and reopen Chrome, then open your CompuOffice web address.

The stable ID comes from the `key` field. The matching private key is NOT in the
repo; reloading the folder keeps the same ID as long as `key` is unchanged.
