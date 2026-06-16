// Instantiate the wasm module and start the miso app (hs_start). The WASI shim
// is loaded from a CDN; ghc_wasm_jsffi.js is produced by post-link.mjs at build
// time. We fetch the wasm as bytes (rather than instantiateStreaming) so we do
// not depend on the server sending Content-Type: application/wasm.
import { WASI, OpenFile, File, ConsoleStdout }
  from "https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.3.0/dist/index.js";
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
await instance.exports.hs_start();
