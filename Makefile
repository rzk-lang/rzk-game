# Build the Rzk Games engine to WebAssembly and assemble the static bundle.
# Requires the GHC WASM toolchain on PATH:  source ~/.ghc-wasm/env
# (install via ghc-wasm-meta, FLAVOUR 9.12).

.PHONY: build optim serve clean

# Compile to wasm, generate the JS FFI glue, and assemble public/.
build:
	wasm32-wasi-cabal build exe:rzk-game --flags=-lsp
	rm -rf public && cp -r static public
	$(eval WASM := $(shell wasm32-wasi-cabal list-bin exe:rzk-game | tail -n1))
	"$(shell wasm32-wasi-ghc --print-libdir)/post-link.mjs" --input "$(WASM)" --output public/ghc_wasm_jsffi.js
	cp "$(WASM)" public/app.wasm
	@echo "Built public/ — serve with: make serve"

# Shrink the module (run after build).
optim:
	wasm-opt -all -O2 public/app.wasm -o public/app.wasm
	wasm-tools strip -o public/app.wasm public/app.wasm

serve:
	npx http-server public -c-1

clean:
	rm -rf dist-newstyle public
