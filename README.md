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

With Nix, use the default shell for the WebAssembly build and the native shell
for bundling the game:

```sh
nix develop --command make build
nix develop .#native --command make bundle
nix develop --command make optim  # optional
nix develop --command make serve
```

Run `make bundle` after every `make build`: rebuilding the web app removes
`public/game.json`.

Without Nix, install the WebAssembly toolchain via
[`ghc-wasm-meta`](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta)
(FLAVOUR 9.12) and run `source ~/.ghc-wasm/env`. Also install native GHC 9.8 or
newer, Cabal and Node.js, then run the same `make` targets in order.

The first build fetches and compiles `rzk` and `miso` under `wasm32-wasi`
(several minutes).

## Authoring a game

A game is a `game/game.yaml` table of contents plus one file per item under
`game/levels/`, and needs no Haskell. See
[`docs/authoring.md`](docs/authoring.md) for the file shapes, the `hints` and
`gated` keys, how prereqs and remedies gate levels, and how to write a good
puzzle and a BOPPPS-style section. After editing `game/`, rerun `make bundle`
and `make serve` with their respective toolchains.
