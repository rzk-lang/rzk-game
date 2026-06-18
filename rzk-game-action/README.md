# rzk-game-action (DRAFT)

A GitHub Action that turns a Rzk-game repo's data into a playable static site,
so a game-project repo needs no Haskell toolchain — only its `game.yaml` and
level files.

```yaml
# .github/workflows/deploy.yml in e.g. a yoneda-game repo
- uses: rzk-lang/rzk-game/rzk-game-action@v1
  with:
    game: game/game.yaml          # default
    engine-version: v0.1.0        # which rzk-game release to use
- uses: peaceiris/actions-gh-pages@v4
  with:
    publish_dir: ./public
```

The action fetches a pinned [`rzk-game`](https://github.com/rzk-lang/rzk-game)
release (the engine `app.wasm` + glue + static assets, and the native
`rzk-game-bundle`), runs the bundler over the repo's `game/`, and assembles
`./public`. The release artifacts are produced by `.github/workflows/release.yml`
in the rzk-game repo.

## Status and open decisions

This is a **skeleton**. Before it can ship:

- **Bundler portability.** `release.yml` currently builds a dynamically-linked
  glibc binary (`rzk-game-bundle-linux-x64`). It runs on `ubuntu-latest` but not
  arbitrary runners. Decide between a static (musl) build and shipping the action
  as a **Docker container action** (one linux-x64 image, runs anywhere). A
  container action would replace the `composite` runner below.
- **Engine distribution.** This draft *fetches* the engine at runtime, so a game
  repo pins its engine via `engine-version`. The alternative is baking the engine
  into the action image (simpler, but couples the action and engine versions).
- **Home.** This likely graduates to its own `rzk-lang/rzk-game-action` repo,
  referenced as `rzk-lang/rzk-game-action@v1`; it lives here for now so the
  skeleton ships alongside the release workflow it depends on.
- **Local authoring.** A macos-arm64 standalone bundler (or `nix run
  github:rzk-lang/rzk-game#bundler`) for iterating on a game repo off-CI.
