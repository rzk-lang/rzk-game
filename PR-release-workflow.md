# Release workflow for engine + bundler artifacts

Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/release-workflow

Adds `.github/workflows/release.yml`: on a `v*` tag (or a manual `workflow_dispatch`), build the wasm engine and the native `rzk-game-bundle` and attach both to the GitHub Release — `rzk-game-engine.tar.gz` (the engine without `game.json`) and `rzk-game-bundle-linux-x64` (the bundler). These are the artifacts a downstream game repo consumes via `rzk-game-action`, so other games deploy with no Haskell toolchain.

The build steps mirror `ci.yml` (same nix shells, same cache keys), so a release warm-starts from CI's caches. A `workflow_dispatch` run builds both artifacts without publishing, which smoke-tests the build off a tag.

The companion `rzk-game-action` (composite action) and a consuming `yoneda-game` scaffold are prepared separately in their own repos (`rzk-lang/rzk-game-action`, `rzk-lang/yoneda-game`).
