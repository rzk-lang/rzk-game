# Phase 2 deferred sub-items handoff — Format action, prelude-context reuse

This note scopes the two Phase 2 sub-items that were deferred without blocking the
Phase 2 exit, so a later session can start cold. As in the earlier handoffs, the
decisions below are **pinned**: a recommended path is chosen for each so work can
begin without further deliberation. They can be revised if an obstacle appears,
but the default is to build them as written. Context:
[`roadmap-1.md`](./roadmap-1.md) Phase 2, Section 2.5, and Section 4 (item 5).

## What is deferred, and why

Phase 2 shipped the full level loop (the L1 editor, tap-to-refine, the
goal/context panel, the smart inventory) and exceeded its exit. Two listed
sub-items were left out because nothing in the MVP needed them:

- **Format action.** `Rzk.Format` is reachable under the wasm backend, but the
  engine never calls it. The player has no way to tidy a term, and authored
  preludes are hand-formatted by eye.
- **Prelude-context reuse** (Section 4, item 5). Checking concatenates the
  read-only prelude with the editable region and rechecks the whole module on each
  submit. The current preludes check in milliseconds, so reuse buys nothing yet.

The two are independent and very different in size. The Format action is a small,
self-contained, web-side feature. Prelude-context reuse is mostly **upstream rzk
work** and only matters once a prelude is large (the Yoneda game). They are
collected here because both are Phase 2 leftovers; in practice the Format action
is the one to do next (it fits Phase 5 polish), and prelude reuse waits for
Phase 7 content.

## Decision 1 (pinned) — the Format action

**Verify the API first.** Section 2.5 records `Rzk.Format` as an exposed library
module — `format :: Text → Text`, `isWellFormatted`, `formatTextEdits` — that
depends only on the lexer/parser we already build under the wasm backend, *not*
behind the `lsp` flag. Confirm the exact names and signatures against the pinned
rzk before coding (one `:type` in a wasm or native GHCi against the rzk pin).

**Pinned shape, learned from the 2026-06-18 notes:**

- **A Format button**, on the puzzle page beside Check. It formats the editable
  region on demand. Reformatting on every keystroke fights the caret and is
  jarring, so there is **no per-keystroke formatting** (consistent with D4).
- **Guard the format.** The formatter needs input that lexes and parses; a
  mid-edit fragment may not. So format only when the editable region is
  well-formed (use `isWellFormatted`, or catch a parse failure), and otherwise
  leave the text untouched — a no-op, never a corrupting rewrite. Holes (`?` /
  `?name`) lex fine, so a hole-bearing but otherwise well-formed term formats
  cleanly, which is the common case mid-proof.
- **Optional format-on-check**, behind a checkbox that **defaults off** and is
  persisted (a new `rzk-game-format-on-check` key, in the export/import archive's
  key set — see [`phase4-handoff.md`](./phase4-handoff.md)). When on, Check (and a
  tap) formats first, then checks. Off by default so the player is never surprised
  by their text moving; checking already parses, so enabling it is cheap.
- **Format the prelude as an authoring concern, not at runtime.** The prelude is
  fixed and pre-checked, so format it once in the source rather than per render.
  Pin this as a native self-test that asserts every level's prelude
  `isWellFormatted`, failing the suite when it is not — nudging authors to run a
  formatter over `game/`. Optionally add a `make format-game` target that rewrites
  the `game/` files in place. (Highlighting the prelude with the lossless
  tokeniser already shipped in Phase 2; this is only about whitespace/layout.)

*Mechanism, pinned:* call `Rzk.Format.format` directly — it is an ordinary
in-process Haskell call, no JSFFI, unlike the download/prose helpers. Keep the
caret/scroll handling minimal: replace the editable text and let the textarea
reset the caret, as Reset already does.

## Decision 2 (pinned) — prelude-context reuse

This is the open Section 4 item 5, and it is **primarily upstream rzk work**, not
an engine feature. The engine cannot cheaply reuse a checked prelude until rzk
exposes a `typecheckInContext`-style entry point: typecheck the prelude once,
keep the resulting context, and check only the editable region against it. rzk
already checks incrementally inside the LSP (since v0.6) and skips unchanged
decls ([PR #159](https://github.com/rzk-lang/rzk/pull/159)); the work is to
surface that as a library API the engine can call.

**Pinned position:**

- **Keep on-submit checking** (D4). Reuse is a performance optimisation, not a UX
  change.
- **Do nothing engine-side until a large prelude exists.** The trigger is the
  Yoneda game: the full sHoTT project checks in ~65 s cold
  ([`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md) §6), so a per-submit recheck
  of a Yoneda-sized prelude would be unusable. Small preludes check in
  milliseconds, so there is nothing to gain now.
- **Sequence it with the upstream API and Phase 7 content.** When Yoneda content
  starts, first land the upstream `typecheckInContext` (it serves the LSP and CLI
  too), then have the engine cache each level's checked prelude context (an
  `IORef`/`Map` keyed by level id, populated at level load) and feed only the
  editable region on each check.

Until the upstream API lands there is no clean engine-only win — re-checking the
prelude each submit is the cost, and for the current content it is negligible.

## Module and code plan

- **`RzkGame.Format`** (new, in the library) — a thin, pure wrapper:
  `formatEditable :: Text → Text` that formats when the input is well-formed and
  returns it unchanged otherwise, plus whatever `isWellFormatted` re-export the UI
  needs. Putting the no-op-on-failure policy here (not in `Main`) keeps it
  **natively testable**, like `RzkGame.Save`.
- **`app/Main.hs`** — a `Format` action and a Format button; a `formatOnCheck`
  model field with its `rzk-game-format-on-check` localStorage key and a checkbox;
  Check/Refine run `formatEditable` first when the flag is set.
- **`test/SpecTest.hs`** — formatting tests (below), and the prelude
  `isWellFormatted` assertion over the built-in content.
- **Prelude reuse** — no engine module yet; it begins with the upstream rzk API.
  When it lands, a small per-level context cache in `RzkGame.Level` (or an `IORef`
  beside `loadedSectionsRef` in `Main`).

## Tests

- `RzkGame.Format`: formatting a well-formed hole-bearing term parses and is
  idempotent (`format . format == format`); a non-parsing fragment is returned
  unchanged (the guard); add to the native `rzk-game-spec` suite beside the
  `RzkGame.Save` checks.
- Authoring guard: every built-in level's prelude is `isWellFormatted` (native).
- Optional headless wasm: a `Format` of a template still holes, and a formatted
  solution still solves, via an `hs_*` export driven like `progresscheck.mjs`.
- Prelude reuse, when built: assert the cached-context check and the
  whole-module check agree on a level (same `CheckResult`), and measure that the
  cached path avoids re-checking the prelude.

## First steps (in order)

1. Confirm the `Rzk.Format` API against the pinned rzk (`:type format`,
   `isWellFormatted`).
2. `RzkGame.Format`: `formatEditable` with the no-op-on-failure guard, and a
   native unit test. (Pure, the safe first move.)
3. `Main`: a Format button and action; verify a real format in the browser.
4. `Main`: the format-on-check checkbox and its persisted flag (fold the key into
   the export/import key set).
5. Authoring: the prelude `isWellFormatted` self-test (and optionally a
   `make format-game` target); format the existing `game/` files once.
6. **Separately, and only when Yoneda-scale content begins:** prelude-context
   reuse, starting from the upstream rzk `typecheckInContext` API, then an
   engine-side per-level context cache.
