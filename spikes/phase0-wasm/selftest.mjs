// Headless proof that rzk's typechecker runs inside the combined rzk+miso wasm
// module, using the same WASI shim the browser loader uses.
import { WASI, OpenFile, File, ConsoleStdout } from '@bjorn3/browser_wasi_shim';
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
console.log('hs_selftest export:', typeof instance.exports.hs_selftest);
console.log('--- calling hs_selftest (rzk inside wasm) ---');
instance.exports.hs_selftest();
console.log('--- returned ---');
