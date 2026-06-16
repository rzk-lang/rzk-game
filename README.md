# rzk-game

Engine for interactive [Rzk](https://github.com/rzk-lang/rzk) games — in the
style of the Lean 4 games, but for synthetic ∞-category theory.

The engine is a [miso](https://haskell-miso.org) application compiled with the
**GHC WebAssembly backend** and linked with the `rzk` library, so the
typechecker runs **in-process in the browser** — no server. The player fills
holes (`?`) in a term; for each hole the engine shows its goal and local context
(term variables, cube variables, tope assumptions) via rzk's structured
`typecheckModulesWithHoles` query.

## Status

Early. The current build is the **L0** slice (textarea + result panel) with one
hand-authored level (a `hom2` filler). See the design notes kept locally
alongside this repo.

## Layout

- `src/RzkGame/Level.hs` — the level model and the check against rzk.
- `src/RzkGame/Content.hs` — hand-authored level content.
- `app/Main.hs` — the miso L0 UI and the wasm entry points.
- `static/` — the page and the WASI loader.
- `cabal.project` — pins `rzk` and `miso` (both built under the wasm backend).

## Building

The reproducible route uses nix to provide the wasm toolchain (this is how miso
itself is built):

```sh
nix develop     # shell with wasm32-wasi-cabal, wasm-opt, wasm-tools, node
make build      # compile to wasm + assemble public/
make optim      # (optional) shrink the module
make serve      # serve public/ locally
```

Without nix, install the toolchain via
[`ghc-wasm-meta`](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta)
(FLAVOUR 9.12), `source ~/.ghc-wasm/env`, then run the same `make` targets.

The first build fetches and compiles `rzk` and `miso` under `wasm32-wasi`
(several minutes).
