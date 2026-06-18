# Build the Rzk Games engine to WebAssembly and assemble the static bundle.
# Requires the GHC WASM toolchain on PATH:  source ~/.ghc-wasm/env
# (install via ghc-wasm-meta, FLAVOUR 9.12).

.PHONY: build bundle optim serve clean test

# Set WASM_STORE to a path to use a project-local cabal store (CI caches it).
WASM_STORE ?=
STORE := $(if $(WASM_STORE),--store-dir=$(WASM_STORE),)

# The authorable game spec and where the bundle is written.
GAME ?= game/game.yaml
GAME_JSON ?= public/game.json

# Compile to wasm, generate the JS FFI glue, assemble public/, and bundle the
# game data into public/game.json (so the app loads from data, not the built-in
# fallback). 'bundle' runs last, after static/ is copied into the fresh public/.
build:
	wasm32-wasi-cabal $(STORE) build exe:rzk-game --flags=-lsp
	rm -rf public && cp -r static public
	$(eval WASM := $(shell wasm32-wasi-cabal $(STORE) list-bin exe:rzk-game | tail -n1))
	"$(shell wasm32-wasi-ghc --print-libdir)/post-link.mjs" --input "$(WASM)" --output public/ghc_wasm_jsffi.js
	cp "$(WASM)" public/app.wasm
	$(MAKE) bundle
	@echo "Built public/ — serve with: make serve"

# Native bundle step: convert game.yaml to JSON and inline the referenced level
# files into a single public/game.json (decision D1). Native-only (uses libyaml);
# it does not touch the wasm toolchain, so it can also run on its own.
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
