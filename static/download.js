// Progress export/import helpers, called from the wasm app (see Main.hs).
//
// We expose plain global functions and call them through the miso DSL (jsg0 /
// jsg2) rather than a raw foreign import, to avoid the JSString-argument codegen
// bug noted in Main.hs (same reason prose.js's renderInto is called that way).
(function () {
  // download(filename, text): save `text` to a file the browser downloads, via a
  // Blob and a transient clicked <a download>. Used by ExportProgress.
  globalThis.download = function (filename, text) {
    var blob = new Blob([String(text)], { type: "application/json" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = filename || "download.json";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // Revoke on the next tick, after the click has been handled.
    setTimeout(function () { URL.revokeObjectURL(url); }, 0);
  };

  // pickImport(): open a file picker, read the chosen file as text, stash it
  // under a scratch localStorage key, and reload. The Haskell side validates and
  // applies it at startup (see Main.hs applyPendingImport), so the authoritative
  // archive codec stays in Haskell; this only ferries the raw text across.
  globalThis.pickImport = function () {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "application/json,.json";
    input.addEventListener("change", function () {
      var file = input.files && input.files[0];
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function () {
        try {
          localStorage.setItem("rzk-game-import", String(reader.result));
        } catch (e) {
          console.error("[rzk] could not stash import", e);
        }
        location.reload();
      };
      reader.readAsText(file);
    });
    input.click();
  };
})();
