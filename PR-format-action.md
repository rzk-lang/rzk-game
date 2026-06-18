Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/format-action

# Format action and canonical preludes

A **Format** button beside Check tidies the player's editable region with rzk's formatter, and an opt-in, persisted **Format on check** preference (off by default) formats before each Check and tap-to-refine. Formatting only runs when the region parses, so a mid-edit fragment is never rewritten. The read-only preludes are now formatted in the source, in both `RzkGame.Content` and the bundled `game/` files, with a native guard that every prelude is `isWellFormatted`.

rzk's `format` is not idempotent on every input (it settles forms like the cube product `(2 × 2)` only on a second pass), so the engine formats to a fixpoint. The prelude reformatting is mechanical, so it lives in a tool, `make format-game`, off the normal build path.

Also folds in a small refactor: the grown `LoadState` action carries a `LoadedState` record instead of a five-field positional payload.

Verified by the `rzk-game-spec` suite and the wasm harnesses (`selftest`, `progresscheck`, `loadtest` — the last now also formats the loaded level inside wasm).
