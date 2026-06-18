// Instantiate the wasm module and start the miso app (hs_start). The WASI shim
// is vendored under ./vendor/wasi (self-hosted, no CDN at runtime);
// ghc_wasm_jsffi.js is produced by post-link.mjs at build time. We fetch the
// wasm as bytes (rather than instantiateStreaming) so we do not depend on the
// server sending Content-Type: application/wasm.
import { WASI, OpenFile, File, ConsoleStdout } from "./vendor/wasi/index.js";
import ghc_wasm_jsffi from "./ghc_wasm_jsffi.js";

const fds = [
  new OpenFile(new File([])),
  ConsoleStdout.lineBuffered((m) => console.log(`[rzk] ${m}`)),
  ConsoleStdout.lineBuffered((m) => console.warn(`[rzk] ${m}`)),
];
const wasi = new WASI([], ["GHCRTS=-H64m"], fds, { debug: false });

const bytes = await (await fetch("app.wasm")).arrayBuffer();
const instance_exports = {};
const { instance } = await WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: wasi.wasiImport,
  ghc_wasm_jsffi: ghc_wasm_jsffi(instance_exports),
});
Object.assign(instance_exports, instance.exports);

wasi.initialize(instance);

// Load the game data (decision D1): fetch the bundled game.json and stash it in
// localStorage, so the wasm app can read it synchronously at startup (see
// Main.hs loadGame) and rebuild the sections in-process. On any failure we clear
// the key, so the app falls back to its built-in content.
try {
  localStorage.removeItem("rzk-game-json");
  const res = await fetch("game.json");
  if (res.ok) localStorage.setItem("rzk-game-json", await res.text());
} catch (e) {
  console.warn("[rzk] no game.json found; using built-in content", e);
}

await instance.exports.hs_start();
