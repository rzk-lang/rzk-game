// Headless run of hs_selftest against the repo's public/ build, using the same
// vendored WASI shim the browser loader uses. Run: node selftest.mjs
import { WASI, OpenFile, File, ConsoleStdout } from './public/vendor/wasi/index.js';
import ghc_wasm_jsffi from './public/ghc_wasm_jsffi.js';
import { readFile } from 'node:fs/promises';

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
console.log('--- calling hs_selftest (rzk inside wasm) ---');
instance.exports.hs_selftest();
console.log('--- returned ---');
