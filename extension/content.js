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

    // Everything else: relay to the native helper and adapt the reply so the
    // page's handlers (which read response.response.output) find what they want.
    return native(msg).then(function (nat) {
      if (!nat) return { status: "error", error: "native helper not reachable" };
      var out = { status: "ok", raw: nat };
      var output = (nat.Output !== undefined) ? nat.Output
                 : (nat.output !== undefined) ? nat.output : undefined;
      out.response = { output: output, status: "ok" };
      // also surface common fields at top level
      if (nat.MacAddress || nat.macAddress) out.macAddress = nat.MacAddress || nat.macAddress;
      if (nat.Version) out.version = nat.Version;
      return out;
    });
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
