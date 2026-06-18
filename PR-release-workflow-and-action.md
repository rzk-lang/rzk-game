# Draft: release workflow and rzk-game-action skeleton

Create the PR (base `main`): https://github.com/fizruk/rzk-game/pull/new/release-workflow-and-action

---

Scaffolding for reusing rzk-game from standalone game repos (Phase 5), as a separate follow-up to the spec/loader PR. Nothing here runs in normal CI — `release.yml` triggers only on version tags — so it lands safely as a skeleton to iterate on.

- `.github/workflows/release.yml` — on a `v*` tag, builds and attaches two artifacts to the GitHub Release: the engine (`app.wasm` + glue + static) and the native `rzk-game-bundle`, using the same two toolchains CI already uses.
- `rzk-game-action/` — a composite-action skeleton that fetches a pinned release, runs the bundler over a repo's `game/`, and assembles `./public`, so a game-project repo (e.g. `yoneda-game`) needs no Haskell toolchain.

Marked DRAFT. The open decisions are written up in `rzk-game-action/README.md`: bundler portability (static/musl vs. a container image), whether the action fetches the engine at runtime (pinned per game repo) or bakes it in, and the action's eventual home as its own `rzk-lang/rzk-game-action` repo.
