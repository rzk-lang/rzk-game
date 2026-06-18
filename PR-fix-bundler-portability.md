# Build the release bundler with ghcup, not nix

Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/fix-bundler-portability

The v0.1.0 bundler asset was built in the nix native shell, so its ELF interpreter was a `/nix/store/...` path that does not exist on a vanilla runner. Downstream — when `rzk-game-action` ran the binary in `yoneda-game` — it failed with `cannot execute: required file not found` (exit 127). The whole produce → publish path was green; only the consumed binary was non-portable.

This rebuilds the bundler with a stock ghcup GHC (`haskell-actions/setup`), which records the standard interpreter and links only system glibc libraries present on GitHub-hosted ubuntu runners, so the artifact runs there. The bundler has no `rzk` dependency (only aeson/yaml and friends), so this build compiles no rzk and needs no nix — it is also faster. A diagnostic step prints the binary's type and shared-library needs; caching keeps the cabal store, the Hackage index, and `dist-newstyle` (build outputs + the cloned rzk source-repository-package).

After merge, `v0.1.0` is re-cut at the fixed commit and the `yoneda-game` deploy re-run to confirm the end-to-end chain.
