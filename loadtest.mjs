// Headless run of hs_gamecheck against the repo's public/ build: prove the
// *loaded* game (public/game.json) is built and played inside wasm. We stub
// localStorage with the bundle (the browser does this in index.js), then call
// the hs_gamecheck export. Run: node loadtest.mjs
import { WASI, OpenFile, File, ConsoleStdout } from './public/vendor/wasi/index.js';
import ghc_wasm_jsffi from './public/ghc_wasm_jsffi.js';
import { readFile } from 'node:fs/promises';

// A minimal localStorage, seeded with the bundle the app expects to find.
const gameJson = await readFile('./public/game.json', 'utf8');
const store = { 'rzk-game-json': gameJson };
globalThis.localStorage = {
  getItem: (k) => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: (k) => { delete store[k]; },
};
// miso's getLocalStorage reaches localStorage through `window`; in the browser
// window === globalThis, so mirror that here.
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
console.log('--- calling hs_gamecheck (load game.json + play, inside wasm) ---');
instance.exports.hs_gamecheck();
console.log('--- returned ---');
