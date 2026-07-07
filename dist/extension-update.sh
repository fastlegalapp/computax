for E in "$HOME/CompuOfficeExtension" "$HOME/Downloads/CompuOfficeExtension"; do
  [ -d "$E" ] || continue
  cat > "$E/content.js" <<'CTEOF'
// CompuOffice Bridge — isolated-world content script.
//
// Receives intercepted requests from the page-world shim (inject.js) via window
// messages, answers them (talking to the native helper through the background
// worker), and posts the reply back to the shim, which resolves the page's
// original callback.

(function () {
  var VERSION = "1.0.9202.22305";
  function log() {
    try { console.log.apply(console, ["[CO-CS]"].concat([].slice.call(arguments))); } catch (e) {}
  }
  log("content script ready on", location.href);

  function ver(m) { return (m && (m.version || m.ver)) || VERSION; }

  // Ask the native helper something; resolves null on any failure.
  function native(msg) {
    return new Promise(function (resolve) {
      try {
        chrome.runtime.sendMessage(msg, function (resp) {
          if (chrome.runtime.lastError) { log("native err:", chrome.runtime.lastError.message); resolve(null); return; }
          resolve(resp);
        });
      } catch (e) { log("native exception:", String(e)); resolve(null); }
    });
  }

  function handle(msg) {
    var action = String((msg && (msg.action || msg.Action)) || "").toLowerCase();
    log("request action:", action, msg);

    // The startup detection. The page needs {status:"ok", version, updateRequired, macAddress}.
    if (action === "checkextension") {
      return native({ action: "macaddress", version: ver(msg) }).then(function (nat) {
        var mac = (nat && (nat.MacAddress || nat.macAddress)) || "02-00-00-00-00-00";
        var out = { status: "ok", version: ver(msg), updateRequired: false, macAddress: mac };
        log("checkExtension ->", out);
        return out;
      });
    }

    // File actions (savefile / runfile / printfile): CompuOffice hands us a
    // document (Word/PDF/etc.) to save. On Windows the native host writes/opens
    // it; on the Mac we save it straight to the Downloads folder via a normal
    // browser download.
    if (action === "savefile" || action === "runfile" || action === "printfile") {
      try { log("file action keys:", Object.keys(msg || {})); } catch (e) {}
      var b64 = firstDefined(msg, ["fileB64", "FileB64", "filedata", "fileData",
                                   "data", "content", "base64", "fileBase64"]);
      var name = firstDefined(msg, ["fileName", "FileName", "filename", "name"]) || "CompuOffice_download";
      var url = firstDefined(msg, ["url", "URL", "fileUrl", "fileArgs", "href", "path"]);
      var done = triggerDownload(name, b64, url);
      if (done) {
        var okr = { status: "ok", result: "Response", response: { status: "ok", output: name } };
        log("download started:", name);
        return Promise.resolve(okr);
      }
      // Nothing downloadable found — fall through to the native helper and log
      // the keys so we can see the real field names.
      log("no file data found for", action, "— relaying to native helper");
    }

    // Anything else: relay to the native helper and adapt the reply so the
    // page's handlers (which read response.response.output) find what they want.
    return native(msg).then(function (nat) {
      if (!nat) return { status: "ok", result: "Response", response: { status: "ok", output: "" } };
      var out = { status: "ok", raw: nat };
      var output = (nat.Output !== undefined) ? nat.Output
                 : (nat.output !== undefined) ? nat.output : undefined;
      out.response = { output: output, status: "ok" };
      if (nat.MacAddress || nat.macAddress) out.macAddress = nat.MacAddress || nat.macAddress;
      if (nat.Version) out.version = nat.Version;
      return out;
    });
  }

  function firstDefined(obj, keys) {
    for (var i = 0; i < keys.length; i++) {
      var v = obj && obj[keys[i]];
      if (v !== undefined && v !== null && v !== "") return v;
    }
    return undefined;
  }

  var MIME = {
    pdf: "application/pdf", doc: "application/msword",
    docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xls: "application/vnd.ms-excel",
    xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    xml: "application/xml", txt: "text/plain", csv: "text/csv", zip: "application/zip",
    rtf: "application/rtf", html: "text/html", htm: "text/html"
  };
  function mimeFor(name) {
    var m = String(name).toLowerCase().match(/\.([a-z0-9]+)\s*$/);
    return (m && MIME[m[1]]) || "application/octet-stream";
  }

  // Trigger a browser download from base64 data (preferred) or a URL.
  // Returns true if a download was started.
  function triggerDownload(name, b64, url) {
    try {
      var href;
      if (b64) {
        href = (String(b64).indexOf("data:") === 0)
             ? b64
             : ("data:" + mimeFor(name) + ";base64," + String(b64).replace(/\s/g, ""));
      } else if (url && /^https?:|^data:|^blob:/.test(String(url))) {
        href = url;
      } else {
        return false;
      }
      var a = document.createElement("a");
      a.href = href;
      a.download = name || "";
      a.style.display = "none";
      (document.body || document.documentElement).appendChild(a);
      a.click();
      setTimeout(function () { try { a.remove(); } catch (e) {} }, 1000);
      return true;
    } catch (e) {
      log("download error:", String(e));
      return false;
    }
  }

  window.addEventListener("message", function (ev) {
    if (ev.source !== window) return;
    var d = ev.data;
    if (!d || d.__coBridge !== "req") return;
    handle(d.message || {}).then(function (resp) {
      window.postMessage({ __coBridge: "resp", id: d.id, response: resp }, "*");
    });
  }, false);
})();
CTEOF
  cat > "$E/inject.js" <<'INJEOF'
// CompuOffice Bridge — page-world shim (runs in the page's MAIN world).
//
// CompuOffice's page code calls chrome.runtime.sendMessage(<hardcoded CompuTax
// extension id>, {action:"checkExtension", ...}, cb). Our extension has a
// different id, so that message would never reach us. This shim overrides
// chrome.runtime.sendMessage in the page: calls aimed at a CompuTax id are
// intercepted and routed (via window messages) to our isolated content script,
// which talks to the native helper and replies. Calls to any other id fall
// through to the original.

(function () {
  var IDS = {
    ohcokhailmiiebggggbllhllifdldegk: 1,
    aginpdbdkhdcfgdndhbagboecblnhfgp: 1,
    pddegllmnldjcaonfinbgaonhfjdbckk: 1
  };
  var seq = 0;
  var pending = {};

  // Messages from the page may contain functions (e.g. a payload.callback).
  // Those cannot be structured-cloned through postMessage, so build a
  // JSON-safe copy, dropping any properties that are not cloneable.
  function sanitize(o) {
    try { return JSON.parse(JSON.stringify(o)); } catch (e) {}
    var out = {};
    for (var k in o) {
      if (!Object.prototype.hasOwnProperty.call(o, k)) continue;
      if (typeof o[k] === "function") continue;
      try { JSON.stringify(o[k]); out[k] = o[k]; } catch (e2) {}
    }
    return out;
  }

  window.addEventListener("message", function (ev) {
    if (ev.source !== window) return;
    var d = ev.data;
    if (!d || d.__coBridge !== "resp") return;
    var cb = pending[d.id];
    if (cb) { delete pending[d.id]; try { cb(d.response); } catch (e) {} }
  });

  var chrome = window.chrome = window.chrome || {};
  var rt = chrome.runtime = chrome.runtime || {};

  function installShim() {
    var current = rt.sendMessage;
    if (current && current.__coShim) return;              // already ours
    var orig = (typeof current === "function") ? current : null;

    function shim() {
      var args = arguments;
      var extId = args[0];
      if (typeof extId === "string" && IDS[extId]) {
        var message = args[1];
        var cb = null;
        for (var i = 1; i < args.length; i++) {
          if (typeof args[i] === "function") { cb = args[i]; break; }
        }
        var id = ++seq;
        if (cb) pending[id] = cb;
        try { console.log("[CO-INJECT] intercepted sendMessage ->", message && message.action); } catch (e) {}
        window.postMessage({ __coBridge: "req", id: id, message: sanitize(message) }, "*");
        return true;
      }
      if (orig) return orig.apply(rt, args);
      return undefined;
    }
    shim.__coShim = true;
    try {
      Object.defineProperty(rt, "sendMessage", { value: shim, writable: true, configurable: true });
    } catch (e) {
      try { rt.sendMessage = shim; } catch (e2) {}
    }
  }

  installShim();
  // Re-assert in case Chrome (re)defines chrome.runtime after us.
  var tries = 0;
  var iv = setInterval(function () {
    installShim();
    if (++tries >= 40) clearInterval(iv);   // ~10s
  }, 250);

  try { window.__COMPUOFFICE_BRIDGE__ = "1.0.9202.22305"; } catch (e) {}
  try { console.log("[CO-INJECT] sendMessage shim installed"); } catch (e) {}
})();
INJEOF
  echo "updated: $E"
done
echo "DONE. Now: chrome://extensions -> reload the CompuOffice Bridge, then reload the CompuTax tab."

