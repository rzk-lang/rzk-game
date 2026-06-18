{
  description = "rzk-game — engine for interactive Rzk games (miso + GHC WASM backend)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # The GHC WebAssembly toolchain, pinned via flake.lock for reproducibility.
    # This is the same toolchain miso uses for its wasm frontend.
    ghc-wasm-meta.url = "gitlab:haskell-wasm/ghc-wasm-meta?host=gitlab.haskell.org";
  };

  outputs = { self, nixpkgs, flake-utils, ghc-wasm-meta }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # The dev shell provides the reproducible wasm toolchain
        # (wasm32-wasi-{ghc,cabal}, wasm-opt, wasm-tools, post-link.mjs). The
        # Haskell build itself is done by wasm32-wasi-cabal against
        # cabal.project (which pins rzk and miso) — nix supplies the toolchain,
        # cabal does the build, exactly as in miso's own flake.
        #
        #   nix develop
        #   make build && make serve
        devShells.default = pkgs.mkShell {
          buildInputs = [
            ghc-wasm-meta.packages.${system}.all_9_12
            pkgs.binaryen    # wasm-opt (make optim)
            pkgs.wasm-tools  # wasm-tools strip (make optim)
            pkgs.nodejs      # WASI loader + headless checks
            pkgs.gnumake     # the build/serve recipes
          ];
          shellHook = ''
            echo "rzk-game wasm dev shell — 'make build' then 'make serve'"
          '';
        };

        # The native (non-wasm) shell for the host-side components: the
        # rzk-game-bundle bundler and the rzk-game-spec tests, built against
        # cabal.project.native (which drops the wasm-only miso pin). The bundler
        # needs a native GHC (it uses the yaml package, which the wasm app
        # deliberately avoids); GHC 9.6.x matches the local toolchain. Used by the
        # CI native-checks job:  nix develop .#native --command make test bundle
        devShells.native = pkgs.mkShell {
          buildInputs = [
            pkgs.haskell.compiler.ghc967
            pkgs.cabal-install
            pkgs.gnumake
            pkgs.git          # cabal clones the rzk source-repository-package
            pkgs.pkg-config
            pkgs.zlib
          ];
          shellHook = ''
            echo "rzk-game native shell — 'make test' and 'make bundle'"
          '';
        };
      });
}
