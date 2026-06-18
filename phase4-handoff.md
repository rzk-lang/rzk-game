# Phase 4 handoff — persistence, packaging, deployment

This note scopes Phase 4 so the next session can start cold. As in the Phase 3
handoff, the decisions below are **pinned**, not open: a recommended path was
chosen for each so work can begin without further deliberation. They can still be
revised if an obstacle appears, but the default is to build them as written.
Context: [`roadmap-1.md`](./roadmap-1.md) Phase 4 and Section 9.

## Where Phase 4 starts

Two of the four Phase 4 bullets are **already done**, so the literal exit — a
deployed, playable game on GitHub Pages with progress saved and restored across
sessions — is already met for this repo:

- **localStorage progress** (built in Phase 2): `app/Main.hs` persists the solved
  set, viewed prose, pre-test answers, unlock overrides, and a per-level draft,
  each under its own key, and restores them at mount (`Init`). The codecs
  (`encodeSolved`/`decodeSolved`, …) are headlessly tested in `hs_selftest`.
- **Static build → GitHub Pages** (Phase 3 CI): the `build-and-deploy` job builds
  the wasm engine and deploys `public/` to `gh-pages` on push to `main`, now
  folding in the bundled `game.json` from the native job.

What is *not* done is the rest of the persistence story and the reuse story:

- **export/import of a progress archive** — so a player can move their progress
  between browsers/devices, or back it up.
- **`rzk-game-action` + release artifacts** — so *other* game repos (not just this
  engine repo) can build and deploy, with no Haskell toolchain. A **skeleton is
  already drafted** on the `release-workflow-and-action` branch (see Decision 2).

*Exit (extended):* the deployed/persistent exit above (met), plus a working
export/import of progress, and a `rzk-game-action` that deploys a separate game
repo from a tagged engine release.

## Decision 1 (pinned) — export/import as a single versioned JSON archive

The whole player state already lives in a handful of `localStorage` keys. An
archive is just those keys, serialised to one downloadable JSON file and
re-importable. No rzk work; this is web-side (JSFFI), like the prose renderer.

**The keys** (all defined in `app/Main.hs`): the four fixed keys
`rzk-game-progress`, `rzk-game-viewed`, `rzk-game-pretest`, `rzk-game-unlocked`,
and the per-level drafts `rzk-game-draft-<i>` for `i` in `0 .. (number of puzzles
− 1)`. The engine's own loaded bundle, `rzk-game-json`, is **excluded** (it is
content, regenerated at load — not player data). The engine already knows the
puzzle count (`length gameLevels`), so it can enumerate the keys without iterating
`localStorage`.

**The format**:

```json
{ "version": 1,
  "saved": { "rzk-game-progress": "0,1,2",
             "rzk-game-viewed": "morphisms-intro,…",
             "rzk-game-draft-0": "#def my-id …",
             "…": "…" } }
```

Export reads each present key and writes this object to a file; import parses it,
writes each key back with `setLocalStorage`, and re-dispatches `Init` to reload
the model. **Semantics: import replaces** the player-data keys (no merge). An
unknown `version` is rejected with a message rather than guessed at.

**Why this shape.** It reuses the existing per-key string codecs unchanged, needs
no zip dependency in wasm, and is a single human-readable file. A draft for a
level no longer in the game simply lingers in the archive, harmlessly unread (same
as today's lingering drafts).

*Mechanism, pinned:* a small vendored `static/download.js` exposing
`download(filename, text)` (a `Blob` + a clicked `<a download>`), called from
Haskell through the DSL like `renderInto` (`jsg2`), to avoid the `JSString`-arg
codegen bug noted in `Main.hs`. Import uses a hidden `<input type="file">` whose
change handler reads the file with `FileReader` and hands the text back to a Haskell
action.

## Decision 2 (pinned, builds on the drafted skeleton) — release artifacts + action

The reuse story is already scaffolded on the **`release-workflow-and-action`**
branch (rebased on `main`, no PR for now). Phase 4 finishes it.

- **`.github/workflows/release.yml`** (drafted) — on a `v*` tag, build and attach
  two assets to the GitHub Release: the **engine** (`app.wasm` + glue + static, as
  a tarball, *without* `game.json`) and the native **`rzk-game-bundle`**. Built
  with the same two toolchains CI already uses (`flake` default shell + `.#native`).
- **`rzk-game-action/`** (drafted) — a composite action that fetches a pinned
  release, runs the bundler over a consumer repo's `game/`, and assembles
  `./public`, so a game repo (`yoneda-game`) deploys with `uses:
  rzk-lang/rzk-game/rzk-game-action@v1` + `peaceiris/actions-gh-pages`.

**Pinned choices** (the open questions in `rzk-game-action/README.md`, decided):

1. **Engine fetched at runtime**, not baked into the action — a game repo pins its
   engine via `engine-version`, so it controls which engine ships (decoupling a
   game's engine version from the action's own version).
2. **Bundler portability:** ship a **Docker container action** (one linux-x64
   image with the bundler) to sidestep the platform matrix — the composite draft
   is the fallback if Docker proves heavy. Optionally also a macos-arm64 standalone
   binary for local authoring.
3. **Home:** keep `rzk-game-action/` in this repo for now; graduate it to its own
   `rzk-lang/rzk-game-action` repo when publishing to the Actions Marketplace
   (Section 9 lists it as a separate repo).

*Validation before a real tag:* exercise the action against a throwaway one-level
game repo (or a CI job that runs the action over this repo's `game/`), so the
fetch → bundle → assemble path is proven before `v0.1.0` is cut.

## Module and code plan

- **`static/download.js`** (new) — `download(filename, text)`; vendored like
  `prose.js`, wired in `index.html`/the loader.
- **`app/Main.hs`** — two actions, `ExportProgress` (gather keys → archive JSON →
  `download`) and `ImportProgress MisoString` (archive text → write keys →
  re-`Init`), plus an Export button, an Import file input, and a small "Progress"
  affordance in the header/nav.
- **`RzkGame.Save`** (new, in the library) — the pure archive codec
  `encodeArchive :: [(Text, Text)] -> Text` / `decodeArchive :: Text -> Either
  Text [(Text, Text)]` (versioned), so it is **natively testable** (the existing
  codecs live in `Main.hs`, which is wasm-only; put the archive codec in the lib).
- **`.github/workflows/release.yml`**, **`rzk-game-action/`** — finish from the
  skeleton per Decision 2.

## Tests

- `RzkGame.Save`: `decodeArchive . encodeArchive` round-trips a key/value list;
  an unknown `version` is rejected; junk keys are dropped. Add to the native
  `rzk-game-spec` suite (and/or `hs_selftest`, beside the progress/viewed/pretest
  codec checks).
- Round-trip the live path headlessly with the `localStorage` shim already used by
  `loadtest.mjs`: seed some progress, export to a string, clear, import, and assert
  the keys are restored. (A new `hs_*` export, or drive the codec directly.)
- The action: a CI lane that runs `rzk-game-action` over this repo's `game/` and
  checks the assembled `public/` has `app.wasm` + `game.json`.

## First steps (in order)

1. `RzkGame.Save`: the versioned archive codec, with a native unit test. (Pure, no
   UI — the safe first move.)
2. `static/download.js` + the JSFFI shim; `Main.ExportProgress` and an Export
   button. Verify a real download in the browser.
3. `Main.ImportProgress` (file input → text → write keys → re-`Init`) and an Import
   button; confirm an exported archive restores progress in a fresh browser.
4. Finish `release.yml` + `rzk-game-action` from the skeleton (Decision 2);
   validate against a throwaway game repo; cut `v0.1.0`. **That closes Phase 4.**
