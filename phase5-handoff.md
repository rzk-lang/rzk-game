# Phase 5 handoff — hints, inventory gating, authoring DX

This note scopes the rest of Phase 5 so a later session can start cold. As in the
earlier handoffs, the decisions below are **pinned**: a recommended path is chosen
for each so work can begin without further deliberation. They can be revised if an
obstacle appears, but the default is to build them as written. Context:
[`roadmap-1.md`](./roadmap-1.md) Phase 5, Section 5 (spec), and Section 6.1 (the
hole-interaction model the hints attach to).

## Where Phase 5 starts

One Phase 5 item is **already done**: the **Format action** (branch
`format-action`) — a Format button, an opt-in format-on-check, and canonically
formatted preludes guarded by a self-test, with a `make format-game` tool. See
the Section 2.5 bullets in the roadmap. That clears the deferred Phase 2 polish
except prelude-context reuse, which stays deferred (see *Out of scope* below).

What remains for the Phase 5 exit — *an author can create a new small game from
the template without reading the engine source* — is three pieces:

- **Goal/context-matched hints** (the headline Phase 5 feature; builds on Phase 1).
- **Inventory gating** (and the related "hidden hints" / template ergonomics).
- **Authoring docs + seeding `rzk-lang/rzk-game-template`** (the exit itself).

The three are mostly independent. Hints and gating are engine + schema work, no
upstream rzk. The template seed is content and docs. In practice do hints first
(it exercises the schema-extension pattern the others reuse), then gating, then
the template — which can then showcase both.

## Decision 1 (pinned) — goal/context-matched hints

A hint is authored prose shown when the player is stuck. Phase 1 already gives the
engine a focused hole's goal and context (`RzkGame.Level.HoleView` —
`hvGoal`/`hvContext`), so a hint can be tied to a hole.

**Pinned shape:**

- **Hints are an ordered list per level**, authored in the level file's
  front-matter under a new `hints:` key. Each entry is `{ text, when-goal? }`:
  `text` is Markdown prose (rendered by `prose.js`, like intros), `when-goal` is
  an optional trigger string.
- **A "Hint" button reveals them one at a time** (progressive disclosure): the
  first tap shows hint 1, the next shows hint 2, and so on. This is the robust
  default — it needs no matching and always works. The count of revealed hints is
  *not* persisted (a per-session affordance; keep it in the model only), so the
  export/import key set is untouched.
- **`when-goal` auto-surfaces a hint** when it is a substring of the focused
  hole's rendered `hvGoal`. Keep matching deliberately simple — a case-sensitive
  infix test on the already-rendered goal text, not structural unification.
  Structural goal matching is subtle and listed as a risk (Section 8, "hint
  matching"); a substring trigger is enough for the MVP and easy for authors to
  reason about. A hint with no `when-goal` is only ever reached by the ordered
  reveal.
- **Hints are hidden by default** ("hidden hints" in the Phase 5 list): nothing is
  shown until the player asks, so a hint never spoils a level the player has not
  engaged with.

*Mechanism, pinned:* extend the `Meta` record and the level model with
`levelHints :: [Hint]` (`Hint { hintText :: Text, hintWhenGoal :: Maybe Text }`);
the loader reads them from front-matter; `app/Main.hs` adds a `RevealHint` action,
a revealed-count model field, and a hint panel below the goal/context. No rzk work.

## Decision 2 (pinned) — inventory gating (and template ergonomics)

The level model already carries `levelInventory :: [Text]` (parsed from the
`inventory` front-matter field), but it is **unused** today — the static inventory
panel was dropped in Phase 2 in favour of the smart Moves panel, and checking puts
the *whole* prelude in scope. Phase 5 turns the inventory into a gate: the player
should only use the lemmas a level grants.

**Pinned position:**

- **Gating is computed in the engine, not the typechecker.** rzk has no
  usage-restriction mechanism, so do not try to make it reject a disallowed name.
  Instead: parse the prelude once to collect the names it *defines*
  (`#def`/`#postulate` heads); the level's allow-list is `levelInventory`. After a
  check, scan the editable region's referenced identifiers, intersect with the
  prelude-defined names, and subtract the inventory — anything left is a
  **gating violation** (a prelude lemma used but not granted).
- **Soft by default, hard if the author opts in.** A violation surfaces as a
  non-blocking notice ("uses `comp-is-segal`, which this level does not grant"),
  so a player is informed but not stuck on a technicality. A level may set
  `gated: true` in front-matter to make a violation fail the check like an error.
  A level with an empty inventory gates nothing (today's behaviour preserved).
- **Revive the inventory display** as the gating reference: a collapsible
  "Allowed here" list beside the Moves panel, so the gate is visible. Reuse the
  `RzkGame.Highlight` tokeniser for the identifier scan (it already tokenises rzk
  losslessly) rather than re-lexing by hand.

This re-maps lean4game's "inventory of tactics → inventory of definitions/lemmas,
with gating of what may be used" (Section 2.2). It is engine-side; no upstream rzk.

*Caveat to verify first:* the identifier scan must exclude locally-bound names and
keywords, so a violation is only ever a real prelude lemma. Restricting the
intersection to *prelude-defined* names (not all identifiers) already does most of
this; confirm against a level whose solution legitimately uses only its granted
lemmas before turning any level's `gated` on.

## Decision 3 (pinned) — authoring docs + seed `rzk-game-template` (the exit)

The empty `rzk-lang/rzk-game-template` repo exists (Section 9), ready to seed.
This is the Phase 5 exit.

**Pinned shape:**

- **Seed the template with a small but complete game that exercises every item
  type and feature**, not a bare stub — an author should be able to read one of
  each and copy it. Keep each level tiny (a one-line filler), but cover the full
  surface across **two BOPPPS sections**:
  - **prose** blocks in several BOPPPS roles (bridge-in, outcomes, a mid-section
    note, summary), so the role tags are all demonstrated;
  - a **core** puzzle (the baseline);
  - a **pre-test** puzzle that **gates a dependent level** via `prereqs`, with a
    `remedies` pointer — so prerequisite locking and remediation are both shown;
  - an **extra** (★) puzzle (optional enrichment);
  - a level carrying **hints** (ordered + one `when-goal`), and a **`gated`**
    level with an `inventory` — so the Phase 5 features are live in the sample;
  - one **multi-block prelude** so the ```` ```rzk prelude/template/solution ````
    split and `make format-game` are visible on real code.

  It must deploy via `rzk-lang/rzk-game-action@v1` + `peaceiris/actions-gh-pages`,
  exactly like `rzk-lang/yoneda-game`, so an author forks, edits `game/`, and gets
  a live site with no Haskell toolchain.
- **Author-facing docs, not engine docs.** A `docs/authoring.md` in this repo (and
  a short README in the template) covering: the `game.yaml` table of contents; the
  level file shape (YAML front-matter — `id`, `title`, `statement`, `inventory`,
  `role`, `hints`, `gated` — plus the ```` ```rzk prelude/template/solution ````
  fenced blocks and the `## Conclusion` prose); how prereqs/remedies gate levels;
  and the local loop (`make format-game`, the `rzk-game-spec` checks an author can
  run). It must include two how-to subsections:
  - **"How to make a good puzzle"** — pin the goal by name and type so an empty
    region cannot pass; keep the editable region small and the prelude as the
    given machinery; start the template from the solution and blank out the parts
    the player supplies (so template-holes / solution-solves by construction);
    grant only the lemmas the puzzle needs (`inventory` + `gated`); write the
    `statement` as the human-readable goal and the conclusion as the takeaway; add
    hints from most general to most specific.
  - **"BOPPPS-style sections"** — a section is a lesson, not just a list: open with
    a **bridge-in**, state **outcomes**, use a **pre-test** to gate (and remediate)
    a dependent level, sequence **participatory** core puzzles, and close with a
    **summary**; map each BOPPPS stage to a prose `role` tag or a puzzle `role`,
    and note that the structure is recommended, not mandatory (prose may sit
    anywhere).

  Keep it task-oriented throughout — it should not require reading `RzkGame.*`.
- **Pin the engine version** the template consumes (`engine-version` in the action
  inputs) to the release that ships hints + gating, so the template demonstrates
  the current schema.

## Decision 4 (pinned) — UI polish: separate controls from moves; lead the error with its message

Two small fixes noticed in play, both web-side, foldable into Phase 5.

- **Controls vs. moves "soup".** The Moves panel (tap-to-refine buttons,
  type-directed and variable in number — `movesView`, the `actions` div) sits
  directly above the control row (Check / Format / Undo / Reset — the `buttons`
  div), so the two read as one undifferentiated mass of buttons. Pin: **separate
  the controls from the moves, spatially and visually.** The controls become a
  fixed, always-in-the-same-place action bar — a sticky footer pinned to the
  bottom of the level page — so Check / Format / Undo / Reset are muscle memory;
  the Moves panel stays in the document flow beside the goal/holes, where it
  belongs as per-hole content. Keep the move buttons as the two-part kind-chip +
  filler chips (already distinct from the solid control buttons) and keep
  Undo/Reset's disabled states. If a sticky footer is awkward on short viewports,
  the fallback keeps the controls in flow but in a clearly bordered, labelled
  group, separated from Moves by a divider and distinct button styling. Either
  way the principle is pinned: controls and moves must not blend.
- **Error message ordering (LSP-style).** A `TypeError` is shown with a friendly
  lead-in and then rzk's full formatted error in a height-capped box
  (`resultView`). But the engine formats with `ppTypeErrorInScopedContext'
  BottomUp` (`RzkGame.Level.ppErr`), and `block BottomUp` *reverses* each block —
  so the context dump prints first and the actual mismatch last, buried below the
  fold. Pin: **lead with the headline error message, then the trace/context
  below**, as an LSP diagnostic does. The lever is already threaded through: try
  **`TopDown`** in `ppErr` first (since `block dir` only reverses on `BottomUp`,
  `TopDown` surfaces the message), and confirm the "when typechecking" trace then
  reads acceptably. If the trace order is still wrong, post-process the formatted
  string engine-side — message line(s) first, the "when typechecking …" trace and
  context folded into a collapsed `<details>` below — defensively (show the text
  unchanged when the expected markers are absent). The clean long-term form is the
  structured-diagnostics direction (Section 4, item 3: a diagnostic with a
  separate message and a notes list); consume that when rzk exposes it rather than
  slicing a string.

## Out of scope — prelude-context reuse (still deferred)

Section 4, item 5. Unchanged from the Phase 2 deferral: checking is on-submit
(D4), the current preludes check in milliseconds, and a cheap engine-only win
needs an upstream `typecheckInContext`-style rzk API that does not exist yet. It
becomes a hard requirement only at Yoneda scale (the full sHoTT project checks in
~65 s cold). Sequence it with Phase 7 content, after the upstream API lands — see
[`phase2-deferred-handoff.md`](./phase2-deferred-handoff.md) Decision 2.

## Module and code plan

- **`RzkGame.Level`** — add `levelHints :: [Hint]` and a `Hint` type; add a
  `levelGated :: Bool`. A pure `inventoryViolations :: Level -> Text -> [Text]`
  (prelude-defined names ∩ editable-referenced names \ inventory), natively
  testable beside `checkLevel`.
- **`RzkGame.Spec` / `RzkGame.Loader`** — extend `Meta` with `hints`, `gated`;
  decode them; carry them into the built `Level`. Keep `RzkGame.Content` (the
  fixture) in step, since the suite round-trips `game/` against it.
- **`app/Main.hs`** — a `RevealHint` action + revealed-count field + hint panel; a
  gating notice in the result view; the revived collapsible inventory list. No new
  localStorage keys (hints/gating are per-session/derived), so the export/import
  set is unchanged. **Decision 4:** split the control row out of the level body
  into a fixed action bar, distinct from `movesView`.
- **`RzkGame.Level`** (Decision 4) — flip `ppErr` to `TopDown` (or reshape the
  formatted error so the message leads); keep it pure for a render test.
- **`static/`** — CSS for the sticky control bar and the message-first error box.
- **`docs/authoring.md`** (new, this repo) and the **`rzk-game-template`** seed
  (separate repo).

## Tests

- `RzkGame.Level`: `inventoryViolations` flags a disallowed prelude lemma and is
  empty when the solution uses only granted names; add to the `rzk-game-spec`
  suite beside the play tests.
- Loader: a level file carrying `hints`/`gated` round-trips through `buildGame`
  (extend the existing `game/` ↔ `Content` round-trip).
- Headless wasm (optional): a `hs_*` check that a hint with a matching `when-goal`
  surfaces for the first template hole, driven like `loadtest.mjs`.
- The template repo: a CI lane (or a manual run) that bundles it via
  `rzk-game-action` and checks the assembled `public/` has `app.wasm` + `game.json`
  — the same validation `yoneda-game` uses.
- `RzkGame.Level` (Decision 4): a wrong-typed editable region renders an error
  whose first non-empty line is the mismatch, not the global context.

## First steps (in order)

1. **Hints schema + model:** `Hint`, `levelHints`, the `Meta`/loader plumbing, and
   a loader round-trip test. (Pure, the safe first move.)
2. **Hints UI:** the `RevealHint` action, the revealed-count field, the hint
   panel, and the `when-goal` auto-surface. Verify in the browser.
3. **Inventory gating:** `inventoryViolations` + its unit test; the soft notice
   and the `gated` hard path; revive the inventory display. Confirm the caveat on
   a real level before enabling `gated`.
4. **Authoring docs + template seed:** write `docs/authoring.md` (including the
   "How to make a good puzzle" and "BOPPPS-style sections" subsections); seed
   `rzk-game-template` with the small-but-complete game that exercises every item
   type and feature, and prove it deploys through `rzk-game-action@v1`. **That
   closes Phase 5.**
5. **UI polish (Decision 4, independent — do anytime):** split the control bar out
   of the Moves panel, and reorder the type-error display to lead with the message.
6. **Separately, only at Yoneda scale:** prelude-context reuse, from the upstream
   rzk API (deferred — see above).
