// Headless run of hs_progresscheck against the repo's public/ build: prove the
// progress export/import round-trip works inside wasm. We stub localStorage (the
// browser provides it) and call the hs_progresscheck export, which seeds some
// progress, exports it to an archive, clears, imports it back, and checks the
// keys are restored (and that a wrong-version archive is rejected). Run:
//   node progresscheck.mjs
import { WASI, OpenFile, File, ConsoleStdout } from './public/vendor/wasi/index.js';
import ghc_wasm_jsffi from './public/ghc_wasm_jsffi.js';
import { readFile } from 'node:fs/promises';

// A minimal in-memory localStorage; the wasm app reaches it through `window`.
const store = {};
globalThis.localStorage = {
  getItem: (k) => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: (k) => { delete store[k]; },
};
globalThis.window = globalThis;

const fds = [
  new OpenFile(new File([])),
  ConsoleStdout.lineBuffered((m) => console.log(`[wasm stdout] ${m}`)),
  ConsoleStdout.lineBuffered((m) => console.warn(`[wasm stderr] ${m}`)),
];
const wasi = new WASI([], ['GHCRTS=-H64m'], fds, { debug: false });

const bytes = await readFile('./public/app.wasm');
const wasmModule = await WebAssembly.compile(bytes);

const instance_exports = {};
const instance = await WebAssembly.instantiate(wasmModule, {
  wasi_snapshot_preview1: wasi.wasiImport,
  ghc_wasm_jsffi: ghc_wasm_jsffi(instance_exports),
});
Object.assign(instance_exports, instance.exports);

wasi.initialize(instance);
console.log('--- calling hs_progresscheck (export/import round-trip, inside wasm) ---');
instance.exports.hs_progresscheck();
console.log('--- returned ---');
