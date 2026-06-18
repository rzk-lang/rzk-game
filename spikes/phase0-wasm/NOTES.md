# Phase 0 spike — rzk + miso in one wasm module

This spike validates the core architecture of [`../../roadmap-1.md`](../../roadmap-1.md):
a [miso](https://haskell-miso.org) app compiled with the **GHC WebAssembly
backend**, linked with the **rzk** library into **one wasm module**, calling
`rzk`'s typechecker **in-process** (no JS string protocol, no server).

**Result: it works, end to end, on macOS arm64.** rzk typechecks a snippet
inside the same wasm module that runs the miso UI.

## What was done (0A–0D)

- **0A — rzk → wasm32-wasi.** Reproduced rzk PR #235 on this machine: the `rzk`
  library cross-compiles to wasm32-wasi with the GHC WASM backend, LSP off.
- **0B — miso → wasm.** The upstream miso `sample-app` builds and links to
  `app.wasm` with the same toolchain.
- **0C — link them.** Added `rzk` as a dependency of the miso app and called
  `Rzk.Main.typecheckString` from both the UI (buttons) and a headless export.
  One `app.wasm` contains miso + rzk.
- **0D — size/memory.** Measured the combined module (below).

## Evidence

Headless run (`node selftest.mjs`, via the same `@bjorn3/browser_wasi_shim` the
browser loader uses) calling the exported `hs_selftest`, which typechecks a good
and a bad snippet with rzk **inside wasm**:

```
[wasm stdout] [good] OK
[wasm stdout] Everything is ok!
[wasm stdout] [bad]  ERROR
[wasm stdout] An error occurred when typechecking!
[wasm stdout] Type Error:
[wasm stdout] Definitions in context:
[wasm stdout]   a : A
[wasm stdout]   A : U
[wasm stdout] ... when unifying expected type A ... with actual type U
```

The bad snippet is the `U`-for-hole trick from
[`../../rzk-probe-notes-1.md`](../../rzk-probe-notes-1.md): the in-wasm error
already carries the goal and context, confirming the Phase 1 data is reachable
from this build.

## Sizes (0D)

| stage | size |
|---|---|
| raw `app.wasm` | 9.0 MB |
| `wasm-opt -all -O2` + `wasm-tools strip` | 4.9 MB |
| gzip -9 | 1.1 MB |
| **brotli -q 11** | **0.8 MB** |

0.8 MB over the wire is mobile-viable and supports the desktop-first /
mobile-read-only target (roadmap §6.4).

### Phone measurement (iPhone, iOS 18.7, Safari 26.5)

| metric | desktop (arm64) | iPhone (iOS 18.7) |
|---|---|---|
| compile | 7 ms | 30 ms |
| instantiate | 4 ms | 12 ms |
| init (RTS) | — | 4 ms |
| first typecheck | 13 ms | 6 ms |
| **peak wasm memory** | 9.7 MB | **9.7 MB** |
| fetch (4.9 MB, uncompressed, LAN) | — | 321 ms |
| **cold-start total** | — | **373 ms** |

✅ The module **runs on iOS Safari**, which retires the iOS WASM memory-cap
risk: peak wasm memory is **9.7 MB** — identical to desktop and orders of
magnitude under the cap. Compile is fast (30 ms). Cold start (373 ms) is
**dominated by the 321 ms fetch of the uncompressed 4.9 MB** over LAN; served
with brotli (0.8 MB) from GitHub Pages, download — the only real lever — shrinks
sharply. The typecheck timings here are for tiny snippets; a heavy prelude is a
separate concern (incremental check-in-context, roadmap §4.5), not a mobile one.

Conclusion: the mobile *runtime* is comfortably viable and memory is a non-issue.
The reasons for desktop-first (D11) are the editing-comfort blockers — Unicode
soft keyboard, small-screen layout — not the wasm runtime.

## Toolchain

- ghc-wasm-meta, FLAVOUR 9.12 → `wasm32-wasi-ghc 9.12.4`, `wasm32-wasi-cabal
  3.14.2`, `wasm-opt 130`. Install: download the gitlab tarball, `./setup.sh`,
  then `source ~/.ghc-wasm/env`.
- miso 1.11 (master), node v26 for the headless check.

## Reproduce

The files here are the spike's source. They were built inside a checkout of the
miso repo with rzk added as a local package. To rebuild:

1. Install the toolchain (above) and `source ~/.ghc-wasm/env`.
2. Clone miso; clone rzk (develop, which includes PR #235) next to it.
3. Adapt rzk for the WASM backend (PR #235's steps, also in `wasm.yml`):
   - `rm rzk/src/Language/Rzk/Syntax/Lex.x rzk/src/Language/Rzk/Syntax/Par.y`
   - `build-type: Custom` → `Simple` in `rzk/rzk.cabal`
   - strip the `build-tool-depends:` blocks
4. Drop in `Main.hs`, `app.cabal`, `cabal.project` from this directory (the
   `cabal.project` points at `../rzk-src/rzk` and sets `flags: -lsp` for rzk).
5. `wasm32-wasi-cabal build app --flags=-lsp`
6. Post-link + bundle:
   - `post-link.mjs --input $(wasm32-wasi-cabal list-bin app) --output public/ghc_wasm_jsffi.js`
   - copy the wasm to `public/app.wasm`, copy `index.html` / `index.js`
7. Headless check: `npm i @bjorn3/browser_wasi_shim@0.3.0 && node selftest.mjs`
8. Browser check: serve `public/` (e.g. `npx http-server public`) and open it;
   the two "Check … rzk" buttons run rzk in the browser.

## Caveats / follow-ups

- The browser button path was not visually clicked here (no browser driver);
  the headless export proves the same `typecheckString` call path. A human
  eyeball of the served page is the last confirmation.
- rzk error output is rendered as a string (`"Rendering type error… (this may
  take a few seconds)"`); Phase 1 still needs to return goal/context/topes as
  structured data (roadmap §4) rather than this text.
- The `cabal.project` here pins rzk via a local path; a real project will pin a
  rzk commit/source-repository-package.

## Phase 2 query — verified against merged rzk (#236–#240)

The spike was rebuilt against the **merged** rzk (your local
`~/git/rzk-lang/rzk/rzk`, `develop` HEAD with #236–#240). `Main.hs` now calls the
**structured holes query** `typecheckModulesWithHoles` (rendered with
`Rzk.Diagnostic.ppHoleInfo`) on the first hom2 level *mid-refine*
(`\ (t , s) → f ?`). Verified in-wasm (headless, `node selftest.mjs`):

```
HOLES FOUND: 1
  goal:           (t : 2 | Δ¹ t)       -- the #239/#240 shape goal, in wasm
  context:        f, y, x, A           -- local-only
  cube variables: x₆ : 2 × 2
  tope context:   Δ² x₆
```

What this establishes:

- **Reachability:** the merged rzk **and its new `aeson` dependency build under
  the GHC wasm backend** — the structured API is callable from the wasm module.
- **Phase 2 engine core, in the browser runtime:** the goal/context query runs
  in-process and returns structured `HoleInfo` (goal + three-section context),
  not a string. The refine fix (shape goal) reproduces in-wasm.
- **Clean pin works:** because rzk is now `build-type: Simple` (#236), the
  spike depends on the rzk source **with no mutation** — the dependency story
  from the roadmap (pin upstream, no vendoring) is real.

Size budget grew modestly with the diagnostics/holes API + aeson:

| stage | Phase 0 (typecheckString) | Phase 2 (holes query) |
|---|---|---|
| raw | 9.0 MB | 10 MB |
| wasm-opt -O2 + strip | 4.9 MB | 5.7 MB |
| brotli | 0.8 MB | **0.9 MB** |

(`cabal.project` here points at the absolute local rzk path; a real build pins a
commit via `source-repository-package`.)
