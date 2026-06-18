# Build the Rzk Games engine to WebAssembly and assemble the static bundle.
# Requires the GHC WASM toolchain on PATH:  source ~/.ghc-wasm/env
# (install via ghc-wasm-meta, FLAVOUR 9.12).

.PHONY: all build bundle optim serve clean test

# Set WASM_STORE to a path to use a project-local cabal store (CI caches it).
WASM_STORE ?=
STORE := $(if $(WASM_STORE),--store-dir=$(WASM_STORE),)

# The authorable game spec and where the bundle is written.
GAME ?= game/game.yaml
GAME_JSON ?= public/game.json

# A complete, playable public/: the wasm engine plus the game data. 'build' and
# 'bundle' use different toolchains (wasm vs native), so they are kept separate —
# CI runs them in separate jobs (see .github/workflows/ci.yml). Locally, with
# both toolchains in scope, `make all` produces the whole bundle.
all: build bundle

# Compile to wasm, generate the JS FFI glue, and assemble public/. Does not write
# game.json — run `make bundle` (native) for that, or `make all` for both.
build:
	wasm32-wasi-cabal $(STORE) build exe:rzk-game --flags=-lsp
	rm -rf public && cp -r static public
	$(eval WASM := $(shell wasm32-wasi-cabal $(STORE) list-bin exe:rzk-game | tail -n1))
	"$(shell wasm32-wasi-ghc --print-libdir)/post-link.mjs" --input "$(WASM)" --output public/ghc_wasm_jsffi.js
	cp "$(WASM)" public/app.wasm
	@echo "Built public/ — add game.json with: make bundle"

# Native bundle step: parse game.yaml + level front-matter and inline everything
# into a single public/game.json (decision D1). Native-only (uses libyaml); it
# does not touch the wasm toolchain. Writes into an existing public/ (or creates
# the directory) so it can run after `make build` or on its own.
bundle:
	cabal --project-file=cabal.project.native run -v0 exe:rzk-game-bundle -- "$(GAME)" "$(GAME_JSON)"

# Headless native tests for the pure data pipeline (RzkGame.Spec / .Loader).
test:
	cabal --project-file=cabal.project.native run -v0 test:rzk-game-spec

# Shrink the module (run after build).
optim:
	wasm-opt -all -O2 public/app.wasm -o public/app.wasm
	wasm-tools strip -o public/app.wasm public/app.wasm

serve:
	npx http-server public -c-1

clean:
	rm -rf dist-newstyle public
