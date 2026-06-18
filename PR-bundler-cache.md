# Cache the release bundler build and warm it on main

Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/bundler-cache

The release bundler job recompiled all of its dependencies on every run (~8 min each). The cache was even restored, but cabal rebuilt everything anyway: the compiled-dependency store was not at the cached path. cabal 3.12 keeps its store under an XDG directory rather than `~/.cabal`, and pointing `CABAL_DIR` at a workspace path did not relocate it to where the cache looked, so the store was never actually preserved — and once the key existed it was never refreshed, leaving the cache permanently cold.

This caches the store at the path `haskell-actions/setup` reports through its `cabal-store` output (alongside `dist-newstyle`), and bumps the cache key to `v2` so the poisoned v1 cache is abandoned (actions/cache never overwrites an existing key).

It also adds a `release-bundler` job to `ci.yml` that builds the bundler the same way (stock ghcup GHC), sharing the cache path and key. On `main` that run warms the cache — caches created on the default branch are visible to all refs, including release tags, whereas tag-scoped caches are not shared between tags — so a release restores it instead of recompiling. On pull requests the job also checks the portable bundler still builds before a tag is cut.

No change to the produced artifacts — only build caching and a new PR check. Verified: with the v2 key in place the store is saved and reused on a subsequent run.
