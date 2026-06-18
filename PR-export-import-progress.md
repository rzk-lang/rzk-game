# Export, import, and reset progress

Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/export-import-progress

Adds the remaining Phase 4 persistence piece: moving progress between browsers/devices, and erasing it. Three controls sit at the foot of the level-map panel.

**Export** gathers the player-data `localStorage` keys (solved set, viewed prose, pre-test answers, unlock overrides, and per-level drafts) into one versioned JSON archive and downloads it. **Import** opens a file picker, validates the archive, and replaces the player-data keys (a full replace, not a merge), showing the outcome in a dismissible banner. **Reset** erases all progress behind an in-place confirmation so a stray tap cannot wipe it. The engine's loaded `game.json` bundle is excluded throughout — it is content, not player data.

The archive codec lives in a new pure, natively-tested library module `RzkGame.Save` (`encodeArchive` / `decodeArchive`, versioned; rejects malformed JSON, a missing/wrong shape, and an unsupported version; drops non-string values). The app-side wiring keeps the codec authoritative: export calls a vendored `static/download.js` through the DSL's `jsg2` (as `prose.js` is called, avoiding the `JSString`-arg codegen bug); import has `download.js` stash the raw file text under a scratch key and reload, and `applyPendingImport` validates and applies it at startup with the Haskell codec before the app reads state.

Verification: `RzkGame.Save` is covered by the native `rzk-game-spec` suite (round-trip, empty archive, version rejection, malformed input, junk-value dropping); a new `hs_progresscheck` wasm export, driven by `progresscheck.mjs` against the `localStorage` shim, round-trips the live path headlessly (seed → export → clear → import → restore) and checks a wrong-version archive is rejected. The wasm app builds and the existing self-test still passes. The browser-only surface (the actual file-save dialog and file picker) is the one bit not exercised headlessly.
