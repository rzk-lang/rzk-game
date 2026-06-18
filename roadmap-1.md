# Rzk Games — Roadmap

This document validates the ideas in [`ideas-1.md`](./ideas-1.md), records the
decisions taken so far, lists the unresolved gaps, and lays out a phased plan.
Choices that have to be made now are marked **Decide now**. Choices we can
postpone are collected in [Open decisions](#10-open-decisions) and marked
**Delayed** at their point of use.

## 1. Vision

We want an engine for interactive Rzk games in the style of the Lean4 games.
The first concrete target is the "∞-Yoneda Game", following Emily Riehl's
[geodesic to the Yoneda lemma](https://emilyriehl.github.io/yoneda/master/simplicial-hott/13-yoneda-geodesic.rzk/).
A second source of material is the 2023
[Rzk demo for the HoTT seminar at BMSTU](https://github.com/fizruk/bmstu-rzk-demo-2023).
New tutorials, and eventually the modal extensions, will follow.

## 2. Validation of the initial ideas

We start by checking the assumptions in `ideas-1.md` against the current state
of Rzk and the surrounding tooling.

### 2.1 What holds

- **A game is a collection of `*.rzk.md` files plus a config.** This is
  sound. Rzk already has a project config, `rzk.yaml`, with `include` globs and
  a defined file order (added around v0.6, used by `rzk typecheck` since
  [PR #119](https://github.com/rzk-lang/rzk/pull/119)). The game config should
  wrap, not replace, this mechanism.
- **Two compilation targets (standalone website, VS Code).** Both remain
  desirable. We prioritise the website first (see 2.3).
- **Browser local storage for progress, with export/import of an archive.**
  Standard and unproblematic.

### 2.2 What changed — the key findings

- **Client-side checking is already a solved path.** Rzk ships `rzk-js`, a
  GHCJS wrapper around the `rzk` library, used by `rzk-playground`. It exports a
  single function:

  ```
  rzkTypecheck_({ input: <string> })
    → sets { status: "ok" | "error", result: <string> }
  ```

  This is significant. The reason the Lean4 games run **server-side** (with
  `bubblewrap` sandboxing and a relay server) is that there is no WASM build of
  Lean 4. Rzk is Haskell and already runs in the browser. We inherit none of
  the Lean4 server, capacity, or sandboxing problems: untrusted proof terms run
  only in the player's own browser sandbox. This is a genuine architectural
  advantage and should shape the whole design.

- **Rzk has dropped `miso` from its playground.** The current `rzk-playground`
  uses GHCJS 9.6 + CodeMirror 6 + Next.js/React, not miso. So the original
  "miso for the frontend" note in `ideas-1.md` no longer aligns with Rzk's own
  tooling. We revisited this (see 2.3).

- **The current `rzk-js` API is coarse.** Whole-source string in; one status
  plus an error *string* out. There are no structured positions, no typed
  holes, and no per-hole goal context. These are exactly the things a "game"
  UX needs, and they require work inside Rzk itself. This sits in tension with
  the `ideas-1.md` note to "keep Rzk changes to a minimum". We have chosen to
  resolve that tension in favour of holes (see 2.3).

- **Rzk is term-mode, not tactic-mode.** This is the most important conceptual
  correction. The Lean4 games are built around *tactics*: an inventory of
  tactics, hints matched against tactic-driven goal states, and proofs written
  as tactic blocks. Rzk has no tactics. A Rzk proof is a *term* inhabiting a
  type. The right mental model for a Rzk game is therefore **Agda-style
  interactive, hole-driven development**, not Lean tactic mode. The player
  fills holes in a term; for each hole the game shows the expected type and the
  local context. Much of the Lean4 game vocabulary needs re-mapping:
  - "inventory of tactics" → inventory of available **definitions/lemmas** and,
    optionally, unlocked **language constructs**;
  - "hint matched on tactic goal state" → hint matched on a **hole's goal/
    context**;
  - "tactic template" → **term template with holes**.

  Agda's interaction model (show goal+context, refine, give) is a far better
  reference for the level UX than `lean4game`'s tactic loop.

### 2.3 Decisions taken

| Decision | Choice | Rationale |
|---|---|---|
| Frontend stack | **miso on the GHC WASM backend** | Haskell end-to-end, one language with Rzk, type-safe UI. Modern miso (1.x) supports the GHC WASM backend with JSFFI. |
| Rzk modification scope | **Invest in holes early** | Typed holes + structured diagnostics + goal-at-hole land before the first playable game, so the first game already has the interactive UX. |
| Primary target | **Website first** (GitHub Pages); VS Code path delayed | Lowest-friction distribution; the client-side advantage above makes it cheap. |
| rzk dependency | **Pin upstream rzk**; make its wasm build first-class (build-type Simple + a CI drift-guard on the generated parser); no vendoring, no build-time patching | Keeps rzk in its own repo; the holes/diagnostics/goal-query work serves the LSP and CLI too, so it belongs upstream (Section 4, Section 9). |

### 2.4 Consequence of the decisions: a single-binary architecture

The two decisions combine into an architecture that is cleaner than `ideas-1.md`
assumed. Both the UI (miso) and the checker (the `rzk` library) are Haskell. If
we build both with the **GHC WASM backend** and link them into **one WASM
module**, the game engine calls the typechecker *in-process*, against Haskell
data structures. We no longer pass strings across a JS FFI boundary as
`rzk-js` does today. We get structured diagnostics, holes, and goal contexts as
ordinary Haskell values.

In other words, the "invest in holes early" decision becomes much cheaper:
instead of extending a stringly-typed JS protocol, we expose richer Haskell
functions from the `rzk` library and call them directly from the miso app.

This architecture is no longer hypothetical: the Phase 0 spike built exactly
this — one wasm module with miso + `rzk`, calling `typecheckString` in-process
(see Section 7, Phase 0, and [`spikes/phase0-wasm/`](./spikes/phase0-wasm/)).

## 2.5 Validation of the 2026-06-18 notes (UI/UX refinements)

A second batch of ideas ([`notes-2026-06-18.md`](./notes-2026-06-18.md)) records
UI/UX refinements noticed once the L0/L1 game was playable. We validate each
against the current engine and slot it into a phase. Most are small, web-side
polish that needs no upstream rzk work; two need the rzk formatter (reachable —
see below); one is a larger content-structure direction.

- **Hide the level prelude by default.** Valid. The level page currently always
  renders the read-only prelude in a `<pre class="prelude">`, which crowds the
  page above the editor. Collapse it into a `<details>` (closed by default), so
  the prelude is available but out of the way. Cheap, web-side. *Phase 2 polish.*
- **Format the prelude (sHoTT code style).** ✅ **Done** (branch `format-action`).
  `Rzk.Format` is an exposed library module (`format :: Text → Text`,
  `isWellFormatted`, `formatTextEdits`) that depends only on the lexer/parser we
  already build under the wasm backend — it is *not* behind the `lsp` flag. The
  read-only preludes are formatted once in the source, both in `RzkGame.Content`
  and in the bundled `game/` files, with a native guard that every prelude is
  `isWellFormatted` (beside the existing `game/` ↔ `Content` round-trip check).
  rzk's `format` is not idempotent on every input (e.g. it settles a cube product
  like `(2 × 2)` only on a second pass), so the engine formats to a fixpoint
  (`RzkGame.Format.formatFixpoint`). The reformatting is mechanical, so it lives
  in a tool, `make format-game` (the native `rzk-game-format` executable), off
  the normal build path.
- **Auto-format the player's code on edit, with an opt-out checkbox.** ✅ **Done**
  (branch `format-action`). A **Format** button beside Check tidies the editable
  region on demand, and an opt-in, persisted **format-on-check** preference (off
  by default, key `rzk-game-format-on-check`, folded into the export/import key
  set) formats before each Check and tap-to-refine. Never per keystroke
  (consistent with D4). Formatting is parse-guarded — it runs only when the
  region parses as a module, so a mid-edit fragment is returned unchanged, never
  corruptingly rewritten. Holes (`?` / `?name`) lex fine, so a hole-bearing but
  otherwise well-formed term formats cleanly. The policy lives in the pure,
  natively-tested `RzkGame.Format.formatEditable`.
- **Highlight the prelude too.** Valid and trivial: reuse the lossless
  `RzkGame.Highlight` tokeniser already driving the L1 editor overlay to render
  the prelude `<pre>` with the same token classes. *Phase 2 (now).*
- **Moves should wrap the inserted term in parentheses.** Valid robustness fix.
  `refineFirstHole` currently splices the insertion verbatim, so a give-spine
  dropped into an argument position can re-associate or fail to parse. Wrapping
  the insertion in `(…)` avoids this. Caveats: do not wrap a bare atom (`x` →
  `x`, not `(x)`) or an already-parenthesised insertion (no double wrap), and
  keep the insertion's inner `?` holes tappable. *Do this alongside the
  move-button redesign (Phase 2).*
- **Move buttons render weirdly.** Valid; addressed now (see below). The move
  kind and the filler term run together into one string
  (`give second (first (is-segal-A ? ? ? ? ?))`). Split each button into a
  colour-coded **kind chip** (`intro` / `give`) and a syntax-highlighted **filler
  term**. *Phase 2 (in progress).*
- **The "Inventory" panel looks stale — remove?** Valid. The static
  `levelInventory` list at the foot of the level page predates the smart
  inventory (the Moves panel, derived type-directed from the focused hole), and
  now duplicates it without the type-direction. Recommendation: drop it from the
  level page for the MVP, or fold it into a collapsible reference; the Moves
  panel is the live inventory. *Phase 2 cleanup.*
- **Organise levels into "modules"/"sections"; mix a BOPPPS lesson with a puzzle
  game.** Valid and larger; a content-structure direction, not a quick fix. It
  maps onto the planned **worlds** (Section 5): a "section"/"module" is a world
  whose lesson prose (BOPPPS — bridge-in, outcomes, pre-assessment,
  participatory practice, post-assessment, summary) frames a sequence of puzzle
  levels. This sharpens the Phase 3 spec (a world needs lesson prose around its
  levels, not just a title) and feeds Phase 7 content design. *Phase 3 (spec) /
  Phase 7 (content).*

## 3. Target architecture

```
            ┌───────────────────────────────────────────────┐
            │   One GHC-WASM-backend module (browser)        │
            │                                               │
            │   ┌─────────────┐     in-process    ┌───────┐ │
            │   │  miso app   │ ───────calls─────▶ │  rzk  │ │
            │   │  (game UI,  │ ◀──structured────  │ core  │ │
            │   │  game model)│   diagnostics,     │ (lib) │ │
            │   └─────┬───────┘   holes, contexts  └───────┘ │
            │         │ JSFFI                                 │
            └─────────┼─────────────────────────────────────┘
                      │
            ┌─────────▼───────────┐   ┌──────────────────────┐
            │ Editor surface (JS) │   │ localStorage          │
            │ textarea → CM6 (D3)  │   │ progress + export/    │
            └─────────────────────┘   │ import archive        │
                                      └──────────────────────┘

   Static assets (HTML + WASM + JS + game spec) hosted on GitHub Pages.
   No server. Checking happens entirely in the player's browser.
```

Components:

- **rzk core (library).** The existing `rzk` typechecker, built with the GHC
  WASM backend, with CLI/LSP-only dependencies excluded. Extended with the
  holes/diagnostics API (Phase 1).
- **Game engine (miso).** Game model (worlds, levels, inventory, progress),
  level orchestration, goal/context panels, hint logic.
- **Editor surface.** Not necessarily CodeMirror 6 (Section 6.3): a `<textarea>`
  plus miso panels (L0) is a viable MVP, with CodeMirror 6 via JSFFI (L2) the
  full option. miso has no built-in code editor, so any JS editor is interop we
  own. At L2 we can lift `rzk-playground`'s CodeMirror Rzk language mode even
  though its React shell is not reusable.
- **Persistence.** localStorage for progress; export/import of a JSON or zip
  archive of the player's solutions.
- **Deployment.** A static bundle on GitHub Pages, produced by
  `rzk-game-action`.

## 4. Required Rzk changes (upstream, and shared with the LSP/CLI)

This is the language- and library-level work implied by "invest in holes early".
A deliberate decision (Section 2.3): **this work lives upstream in
`rzk-lang/rzk`, not in the game engine.** Almost all of it serves the language
server and the CLI as much as the game — typed holes, structured diagnostics,
and a goal-at-position query are exactly what a good VS Code experience needs.
Building them into rzk makes them useful immediately, independent of the game,
and the engine consumes them through a pinned rzk dependency (Section 9). Each
item is annotated with who else benefits. It is the main source of risk, so it
is sequenced first after the spikes.

**Status (2026-06-16): #236–#240 merged.** Typed holes (`?` / `?name`), the
structured goal/context query (`typecheckModulesWithHoles → [HoleInfo]`:
**local-only**, three-section terms/cube/topes, symbolic-with-boundary), and
`Rzk.Diagnostic` (+ `rzk typecheck --json`) all landed and are **verified on the
first level** ([`first-hom2-level.md`](./first-hom2-level.md)). This resolves
items 2–4 and **D1** (hole syntax = `?` / `?name`).

- **Refine-by-text-rewrite works** under extension-type boundaries (#239/#240,
  verified rebuilt from HEAD): `\ (t , s) → f ?` is accepted with goal
  `(t : 2 | Δ¹ t)`, so the four-tap chain holds. (A first test on #237/#238 found
  it failing; #239/#240 fixed it.) Intermediate holes check leniently; the
  hole-free term checks strictly. The engine therefore needs **no** refinement
  logic of its own — text-rewrite + re-check suffices.
- **One item remains: (5) incremental check-in-context** — not yet present; fine
  for small levels (the hom2 prelude checks in ms), needed before big preludes
  (Yoneda).
- **Rendering niceties (still open, cosmetic):** pair-pattern binder names show
  as `π₁ x`/`π₂ x` (the engine restores `t,s` or waits upstream); and
  unfold-on-demand for symbolic boundaries. Neither changes the model.

1. **Build the `rzk` core under the GHC WASM backend.** *Largely done already:*
   [PR #235](https://github.com/rzk-lang/rzk/pull/235) adds CI that
   cross-compiles `rzk:lib:rzk` to `wasm32-wasi` with the LSP disabled,
   `build-type: Simple`, pre-committed parser/lexer, and `build-tool-depends`
   removed so BNFC/alex/happy are not needed at build time. Notably,
   `wasm32-wasi` is the same toolchain haskell-miso targets, which confirms the
   single-binary architecture (Section 2.4); the Phase 0 spike then proved a
   full miso + rzk module on this toolchain. **PR #235 is now merged.** The
   remaining piece is to let consumers depend on rzk under the wasm backend
   *without* patching it — today the wasm-buildability is a CI-time source
   mutation, not a property of the package. Make it first-class: switch the
   `rzk` library to `build-type: Simple` permanently (safe, since the generated
   `Lex.hs`/`Par.hs` are committed), delete the Custom `Setup.hs`, and move parser
   regeneration plus `build-tool-depends` to an out-of-band `make regen-parser`
   target (a cabal flag cannot do it — `Simple` has no build hook). Add a CI lane
   that regenerates the parser from `Lex.x`/`Par.y` with BNFC/alex/happy and
   `git diff --exit-code`s the result, so the committed modules cannot drift from
   the grammar. *Serves:* the wasm/game build (no vendoring or patching needed
   downstream); the normal GHC and GHCJS builds keep working. Immediately
   actionable, and the natural first upstream task.
2. **Typed holes — syntax and semantics.** A hole is an unfilled subterm. The
   typechecker must accept a term containing holes as "incomplete but
   well-formed so far", and for each hole report:
   - the expected type, and
   - the local context (term variables with their types, plus the cube/tope
     context that is specific to Rzk).

   The exact surface syntax is **Delayed** (candidates in
   [Open decisions](#10-open-decisions)). *Serves:* the LSP (interactive,
   Agda-style hole-driven editing in VS Code), the CLI (report unsolved holes),
   and the game.
3. **Structured diagnostics.** Replace, or sit beside, the current single-string
   error output with a list of diagnostics carrying source spans, severities,
   and messages. The LSP already computes spans for diagnostics internally;
   reuse that machinery rather than the CLI's string formatting. *Serves:* the
   LSP (factor the structured diagnostic type down into the library it already
   feeds), the CLI (a `--json` diagnostics mode for editor-agnostic tooling/CI),
   and the game.
4. **Goal/context query at a position.** Given a parsed module and a position
   (a hole, or a cursor), return the goal and context. The LSP hover may
   already compute part of this; check before building anew. *Serves:* the LSP
   most of all (goal / context under the cursor, for any editor — the most
   clearly LSP-useful item here), the game, and possibly a CLI goal query.
5. **Check-in-context / incremental reuse.** A level has a fixed, already-checked
   *prelude* and a small editable region. We want to typecheck the prelude once
   and reuse the resulting context while the player edits, rather than
   rechecking everything on each keystroke. Rzk already has incremental
   typechecking in the LSP (since v0.6) and "skip typechecking when decls have
   not changed" ([PR #159](https://github.com/rzk-lang/rzk/pull/159)); we need
   to expose a `typecheckInContext`-style entry point to the engine. *Serves:*
   the game (the 65 s prelude problem); the LSP already checks incrementally
   internally, so this mostly exposes existing machinery as a library API.

All five are exposed as ordinary Haskell functions in the `rzk` library —
consumed by the miso app (Section 2.4) as structured values, and equally
available to the LSP and CLI — not as a stringly-typed JS protocol. Their
"sharpened requirements" below (binder-name preservation especially) improve
rzk's error output for *every* consumer, not just the game.

*Validated by probing rzk 0.8.0* (see
[`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md)): the goal, term context, cube
variables, and tope context are already computed and printed at a `U`-substituted
hole, so items 3–4 are largely a matter of returning them structurally rather
than inventing them. Probing sharpened the requirements:

- the query must **separate local hypotheses from the global environment** — the
  error formatter dumps ~900 context lines at the Segal associativity goal, of
  which only nine are the real locals; the globals belong in a searchable, gated
  inventory, not inline;
- it should **keep goals symbolic** (composites are not force-unfolded today —
  good) and **preserve binder names** through pair patterns (`(t₁ , t₂)` is
  currently shown as `x₁` / `π₁ x₁` / `π₂ x₁`), which touches D1;
- `recOR` must be modelled as **one sub-hole per branch plus a coherence
  obligation per overlapping pair** of topes, not a simple branch choice.

The full sHoTT project checks in ~65 s with no persistent CLI cache, which makes
item 5 (in-process check-in-context with a cached prelude) a hard requirement.

*Future (post-MVP), not part of this track:* expose Rzk's existing SVG diagram
rendering of cube/shape/tope terms from the WASM build, so the UI can visualise
goals, contexts, and cube-indexed terms (decision D12). Listed here only so the
WASM library surface is designed with room for it later.

## 5. Game specification format

We keep the `ideas-1.md` shape: a set of `*.rzk.md` files plus a unifying YAML
config, wrapping `rzk.yaml`. We borrow the *structure* of `lean4game`, but
re-map its tactic-centric vocabulary to Rzk's term-mode, hole-driven model
(Section 2.2).

Structure to support (subset chosen per phase):

- **Game → Worlds → Levels**, with world dependencies (a DAG).
- **Per level:** title, introduction text, statement/goal, conclusion text,
  the editable term with holes, and a reference solution for checking.
- **Inventory:** definitions/lemmas (and optionally language constructs)
  unlocked per level; gating of what may be used.
- **Hints:** matched against a hole's goal/context (depends on Phase 1).
- **Templates:** a starting term with holes for the player to fill.
- **Presentation:** Markdown throughout, KaTeX for mathematics, optional
  images per world/level.

Open sub-question (**Delayed**): how a single `*.rzk.md` file is partitioned
into *prelude* (read-only, pre-checked), *editable region*, and *reference
solution*. Options include explicit fenced markers, naming conventions, or a
sidecar in the YAML. We decide this when we reach Phase 3.

## 6. UI/UX design

The first draft of this roadmap under-treated the interface. It deserves its own
workstream, and it matters more here than in a typical web app for two reasons.

- **The miso/WASM choice removes the React component ecosystem.** Every widget
  — editor chrome, goal/context panel, inventory, world map, dialogs, progress
  indicators — is hand-built in miso plus CSS. `lean4game` is therefore a
  *layout and interaction reference*, not a code-reuse path. Its CSS is
  framework-agnostic, so adapting its *styles* remains a possible shortcut even
  though its React components are not reusable.
- **Rzk is term-mode, so the hole is the central interaction.** The level loop
  is Agda-like: focus a hole, read its goal and context, fill or refine it.
  There is no off-the-shelf web component for this; it must be designed
  deliberately and wired into CodeMirror 6 (see D3) and the Phase 1 diagnostics.

### 6.1 What needs designing

- **Information architecture / layout.** Where the editor, goal+context panel,
  inventory, world map, level navigation, and intro/conclusion text live.
  `lean4game`'s layout is the reference to react to.
- **The hole-interaction model (the core).** How a hole is shown in the editor
  (gutter marker, inline widget, highlight); how focusing a hole drives the
  goal/context panel; how the player fills or refines it; how solved vs.
  unsolved holes and error squiggles are indicated. `agda-mode`'s interaction
  loop is the closest reference.
- **Code and prose rendering.** Rzk syntax highlighting in CodeMirror, heavy
  Unicode support, Markdown for prose, and KaTeX for mathematics.
- **Navigation and progress.** A world DAG map and level list with
  locked / unlocked / completed states.
- **Visual identity.** Rzk branding, light/dark themes, math-friendly and
  monospace fonts.
- **Responsiveness and accessibility.** Desktop-first is acceptable for a proof
  game; keyboard navigation matters; mobile is likely out of scope for the MVP.
- **Onboarding / first-run.**

### 6.2 A parallel design sub-track

The design work needs no WASM, so a lightweight sub-track can start now, in
parallel with Phases 0–1, and feed Phase 2's level UI:

- collect references (`lean4game` UI, `agda-mode` interaction, the Rzk
  playground);
- low-fidelity wireframes of the level screen and the world map;
- a storyboard of the hole-interaction loop — the **gating deliverable for
  Phase 2** (see Phase 2); first sketch in
  [`hole-interaction-storyboard-1.md`](./hole-interaction-storyboard-1.md). It
  fixes the interaction model (how a hole is shown,
  focused, filled, and refined; where the goal/context appears) that governs the
  UI effort, the editor choice (D3), and mobile comfort (Section 6.4) all at
  once, so it must be settled before Phase 2 UI work begins;
- a small static HTML/CSS styling spike that fixes the look and settles the CSS
  approach (D9).

Open choices for this sub-track are D9–D11 in [Open decisions](#10-open-decisions);
the look-and-feel direction (D10) is worth an early sketch.

### 6.3 Editor surface — is CodeMirror 6 required?

The first draft assumed CodeMirror 6 because `rzk-playground` uses it. We do not
strictly need it. We need *an* editing surface, and how rich it is decides
whether a full editor is warranted. The question splits by **where the "smart"
UI lives**:

- **Inline-in-editor** — syntax highlighting, error squiggles, gutter markers,
  hole widgets, click-a-hole-to-focus, read-only prelude ranges, a Unicode input
  method. These want a real editor (CodeMirror 6).
- **Side-panel** — a list of diagnostics with positions, a list of holes, and
  the goal/context panel. These need only a `<textarea>` plus our own
  miso-rendered panels.

A term-mode, Agda-like game can put much of the interaction in side panels:
holes appear as `?`/`{! !}` in the text, numbered, with goals shown beside the
editor — close to how `agda-mode` actually works. So a bare textarea is a viable
MVP. The choice is a ladder:

- **L0 — textarea + miso panels.** No JS editor. Cheapest, full control, proves
  the Phase 2 loop. No highlighting; hole interaction is by-number in a panel.
- **L1 — textarea over a highlighted `<pre>` (overlay).** Adds syntax
  highlighting with no heavy dependency. Interaction still panel-based.
- **L2 — CodeMirror 6 via JSFFI.** Inline diagnostics, hole widgets, read-only
  prelude ranges, and an Agda-style Unicode input method. Best UX; a JS island
  we drive from the WASM app and must maintain.

The capacities CM6 would serve, specifically: Rzk syntax highlighting — and here
is the one concrete reuse win, `rzk-playground` already ships a working CM6 Rzk
language mode, framework-agnostic JS we *can* lift (unlike its React components);
inline error decorations; inline hole widgets and click-to-focus; read-only
prelude regions; and a Unicode input method (Rzk source is Unicode-heavy).

Recommendation: start at **L0** in Phase 2 to prove the loop, move to **L2** when
inline hole UX is the priority (reusing rzk-playground's language mode), with
**L1** as a fallback if CM6 ↔ WASM interop proves fiddly. This is decision **D3**
(reframed). CM6 is the one place we deliberately keep a JS island beside the WASM
app.

### 6.4 Mobile (smartphones)

Decided (D11): **desktop-first**. On phones the app should run and be
readable and browsable — intro/conclusion text, the world map, level lists, and
the goal/context panel — but comfortable proof *authoring* by typing is not an
MVP goal. Authoring is hard on touch for two reasons: Rzk source is
Unicode-heavy code that mobile soft keyboards bury, and the desktop multi-panel
layout does not fit a small screen.

Comfortable mobile authoring is feasible later, but as a deliberate goal needing
a responsive stacked/tabbed layout, a Unicode symbol palette, and a
**tap-to-refine** interaction that minimises free typing (tap a hole → pick a
lemma from the inventory → refine). That interaction also fits the term-mode,
hole-driven model well, and a content lever helps too: short, selection-heavy
levels designed for phones.

Whether the app even *runs acceptably* on a phone is now **measured, not
assumed** (Phase 0D): on an iPhone (iOS 18.7 Safari) the module runs with
9.7 MB peak memory and ~370 ms cold start, so the wasm *runtime* is not the
blocker. What keeps mobile at read-only is the editing-comfort gap above
(Unicode soft keyboard, small-screen multi-panel layout), not the engine.

## 7. Phased plan

Each phase has an explicit exit criterion. Phase 0 spikes are independent and
can run in parallel; everything after depends on Phase 0 succeeding.

### Phase 0 — De-risking spikes — ✅ DONE (spike)

**Result: the architecture is proven end to end on macOS arm64.** A miso app
compiled with the GHC WASM backend, linked with the `rzk` library into one wasm
module, typechecks a snippet with `rzk` in-process. See
[`spikes/phase0-wasm/NOTES.md`](./spikes/phase0-wasm/NOTES.md). Headline:
0A (rzk→wasm) ✅, 0B (miso→wasm) ✅, 0C (combined module runs rzk) ✅,
0D sizes: 9.0 MB raw → 4.9 MB opt → **0.8 MB brotli**; **phone measured** —
iPhone/iOS 18.7 Safari ✅ runs, **9.7 MB peak memory** (same as desktop), 30 ms
compile, ~370 ms cold start (mostly the uncompressed fetch). The GHCJS fallback
is no longer needed, and the iOS memory-cap risk is retired.
- **0A. rzk core under GHC WASM backend.** *Mostly resolved by
  [PR #235](https://github.com/rzk-lang/rzk/pull/235)* — `rzk:lib:rzk` already
  cross-compiles to `wasm32-wasi`. Remaining: shepherd the PR to merge and
  expose a `typecheckString` entry point from the WASM library target.
  *Exit:* call `typecheckString` from a throwaway WASM harness, get ok/error.
- **0B. miso editor surface under GHC WASM backend.** A minimal miso app with an
  editing surface that round-trips text to a stub. A `<textarea>` (L0, Section
  6.3) suffices for the spike; optionally also mount a CodeMirror 6 editor via
  JSFFI to validate the L2 interop early. *Exit:* edit text, press a button, see
  the text echoed back through Haskell.
- **0C. Link 0A + 0B.** One binary: the miso app calls the rzk typechecker
  in-process. *Exit:* type a snippet in the miso app, see ok/error from real
  Rzk.
- **0D. Bundle and memory budget.** Measure the 0C binary's compressed size,
  cold-start time, and peak memory on desktop and on a mid-range phone (iOS
  Safari and Chrome Android). *Exit:* concrete numbers and a go / no-go on the
  mobile read-only target (Section 6.4); a size/memory budget for later phases.

PR #235 already shows the core builds under the WASM backend, so the main
remaining make-or-break is 0C: linking the rzk library and the miso app into one
working binary. If 0C fails, we fall back to a **Delayed** alternative: keep the
UI in miso/WASM but run the checker as a separate GHCJS `rzk-js` module called
over JSFFI (string protocol), accepting the coarser interface short-term.

### Phase 1 — Holes and structured diagnostics in Rzk — ✅ DONE
Implements Section 4 (items 2–5; item 1 is Phase 0A).
*Exit:* in the miso app, errors show as squiggles at correct positions, and
clicking a hole shows its goal and *local* context (local hypotheses only, with
the global environment routed to a separate inventory — see
[`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md) §5).

**Met.** The hole half landed first: the structured query (#236–#240) is consumed
by `RzkGame.Level.toHoleView` and shown as local-only goal / context / cube-var /
tope panels, with the global environment excluded. The squiggle half shipped in
PR #16 (`error-position-squiggles`): `checkLevel` maps a type error's line (via
`Rzk.Diagnostic.locationOfTypeError`) back into the editable region and the editor
underlines it. rzk records locations at *line* granularity (the column is
discarded), so a whole line is squiggled — finer spans need column-preserving
locations upstream. Item 5 (incremental check-in-context) is upstream, perf-only,
and not part of this app criterion (see Phase 2).

### Phase 2 — Engine core, one level end-to-end — ✅ DONE (exit met)

**Met, and exceeded.** The full loop runs in the browser: 15 hand-authored
levels are playable end-to-end, from the right-unit triangle through the
associativity tetrahedron. `RzkGame.Level` holds the level model (prelude +
editable + solution, with the goal pinned by name and type) and the check against
rzk; `RzkGame.Section` groups levels into locking BOPPPS sections; `app/Main.hs`
is the **L1** editor (textarea over a highlighted `<pre>`), tap-to-refine moves,
the goal/context panel, the hole list, and the success state. The smart inventory
ranks moves type-directed from the focused hole. A headless self-test
(`hs_selftest`, run via `selftest.mjs`) checks every level's template and
solution, the refine chains, the error paths, and the section/locking/progress
logic.

Two listed sub-items were **deferred, not blocking the exit**, and scoped in
[`phase2-deferred-handoff.md`](./phase2-deferred-handoff.md). The first has since
landed in Phase 5; the second is still deferred:

- **Format action.** ✅ **Done** (branch `format-action`, Phase 5 — see the 2.5
  bullets above): a Format button, opt-in format-on-check, and canonically
  formatted preludes guarded by a self-test.
- **Prelude-context reuse (Section 4, item 5).** Not implemented. Checking is
  on-submit (Check / a tap), not per keystroke (decision D4), and the current
  preludes check in milliseconds, so it is not yet needed. It becomes a hard
  requirement only for a large prelude (Yoneda) — likely upstream rzk work.

Work that ran *ahead* of its phase while building the content: locking sections
with prerequisites (Phase 3 worlds/DAG), Markdown + KaTeX prose rendering
(Phase 3), and localStorage progress (Phase 4, persistence half).

The earlier spike notes still hold: the structured query
`typecheckModulesWithHoles` runs **in-process inside the wasm module**; the
**clean pin** works (rzk depended on with no mutation, #236); size budget
**~0.9 MB brotli**.

- **Gate: ✅ cleared (2026-06-16).** The hole-interaction storyboard (Section
  6.2) is signed off (its §11), validated against the first verified Rzk-native
  level ([`first-hom2-level.md`](./first-hom2-level.md)). The interaction model
  the UI is built against is fixed; Phase 2 UI implementation is unblocked.
- Level model: prelude (pre-checked, read-only) + editable region + solution
  check.
- Win condition: the editable region typechecks with no remaining holes.
- MVP interaction loop: **tap-to-refine** (rewrite the focused hole, re-check
  with `typecheckModulesWithHoles`, inspect the new holes' goals/context) — now
  verified to work under extension-type boundaries (#239/#240). Give-a-complete-
  term is the always-available fallback; the goal/context panel is the teaching
  tool.
- Minimal level UI: statement, editor, goal/context panel, hole list, success
  state — implemented from the UI/UX design sub-track (Section 6), especially the
  hole-interaction model.
- Reuse the prelude context across keystrokes (Section 4, item 5). *Deferred —
  see the status note above.*
- Smart inventory: rank the level's inventory by relevance to the focused hole's
  goal (lemma discovery, MVP scope — storyboard §6.1), powering tap-to-refine.
  Library-wide search is out of scope (D13).
- UI refinements from the 2026-06-18 notes (Section 2.5): two-part move buttons,
  parenthesised refinements, prelude highlighting, a collapsible prelude, and
  dropping the stale static inventory — all **done**. The Format action, then the
  one deferred item, has since landed in Phase 5 (branch `format-action`).
*Exit:* play one hand-written level end-to-end in the browser.

### Phase 3 — Game spec format and multi-level structure — ✅ DONE (exit met)

**Met.** Content is now loadable from data. `RzkGame.Spec` holds the `FromJSON`
schema, the `.rzk.md` body readers, and `goalFromTemplate`; `RzkGame.Loader.buildGame
:: ByteString -> Either Text [Section]` rebuilds the same `[Section]` model the
engine consumes. A game is a **table of contents** (`game.yaml`) plus one
self-contained file per item: each level file carries its intrinsic metadata in a
YAML **front-matter** header and its prose in the Markdown body (intro before the
first rzk block, conclusion under a trailing `## Conclusion`), with the rzk code in
`prelude`/`template`/`solution` fenced blocks (**D2**). The table of contents keeps
only *placement* metadata — curriculum role, prerequisites, remedies — so a level
file is portable and the locking graph stays in one place. A native
`rzk-game-bundle` step parses all YAML and packs everything into one
`public/game.json` (**D1/D5**: the wasm app parses only JSON); `index.js` fetches it
before `hs_start` and `Main.loadGame` builds the sections, falling back to the
built-in `RzkGame.Content`. All four worlds (15 levels + 9 prose) are ported to
`game/` and play from data; `RzkGame.Content` stays as the fallback and the fixture
the loader is checked against (native `make test` round-trips it exactly). A native
CI job builds the bundler and runs the loader tests; the wasm deploy job folds in
`game.json`. Followed [`phase3-handoff.md`](./phase3-handoff.md); one deviation —
templates keep grouped binders and `goalFromTemplate` reconstructs the closed
Π-type, so the ported levels play identically. Merged via PR #17.
*Exit:* load a small custom game from a spec and navigate its worlds and levels. ✅

### Phase 4 — Persistence, packaging, deployment — ✅ DONE (exit met)

**Met.** The four bullets are all in place. localStorage progress (solved /
viewed / pre-test / unlock, plus per-level drafts) and the static build → GitHub
Pages deploy were already done in Phases 2–3; this phase finished the two
remaining bullets, following [`phase4-handoff.md`](./phase4-handoff.md).

- **Export / import / reset of progress.** `RzkGame.Save` is the pure, versioned
  archive codec (`encodeArchive` / `decodeArchive`, natively tested). Export
  gathers the player-data keys into one JSON file and downloads it (vendored
  `static/download.js`, called through `jsg2`); import reads a file, validates it
  with the Haskell codec at startup (`applyPendingImport`), and replaces the
  player-data keys (a full replace, not a merge); reset erases all progress behind
  an in-place confirmation. The loaded `game.json` is excluded throughout. A
  headless `hs_progresscheck` (`progresscheck.mjs`) round-trips the live path.
  *(Branch `export-import-progress`.)*
- **Release artifacts + `rzk-game-action`.** A tag-triggered `release.yml`
  publishes two assets — the engine tarball (`app.wasm` + glue + static, no
  `game.json`) and the native bundler (`rzk-game-bundle-linux-x64`, built with
  ghcup so it is portable, cached and warmed from `main`). The composite
  **`rzk-lang/rzk-game-action@v1`** (graduated to its own repo) fetches a pinned
  release, runs the bundler over a consumer's `game/`, and assembles `public/`.
  **`v0.1.0` is cut** and validated end to end through `v0.1.0-rc.1` against the
  **`rzk-lang/yoneda-game`** scaffold (deploys to GitHub Pages with no Haskell
  toolchain).

*Exit:* a deployed, playable game on GitHub Pages with progress saved and restored
across sessions (**met**), extended with export/import of progress and a reusable
`rzk-game-action` consumed by a separate game repo (**met**).

### Phase 5 — Hints, polish, authoring DX — ▶ IN PROGRESS
- Goal/context-matched hints (builds on Phase 1).
- Templates, hidden hints, inventory gating.
- Authoring docs and the `rzk-game-template` repository (the empty
  `rzk-lang/rzk-game-template` repo is created, ready to seed).
- **Format action — ✅ done** (branch `format-action`): a Format button, opt-in
  format-on-check, and canonically formatted preludes with a `make format-game`
  tool and a `isWellFormatted` self-test.
- UI polish: separate the control buttons (Check/Format/Undo/Reset) from the
  type-directed Moves panel they currently blend with (a fixed action bar), and
  reorder the type-error display to lead with the message (LSP-style) rather than
  the context dump.
- The other **deferred Phase 2 polish**, prelude-context reuse, stays deferred
  (Section 4, item 5 — upstream rzk work, needed only at Yoneda scale).
- Remaining work is scoped for a cold start in
  [`phase5-handoff.md`](./phase5-handoff.md).
*Exit:* an author can create a new small game from the template without reading
the engine source.

### Phase 6 — VS Code path (**Delayed**)
Reuse the Rzk LSP and a local `rzk` binary; persist solutions in a `solution/`
subdirectory of a forked game repo. Share the game spec and as much engine
model as is practical. Decide whether this is a mode of the existing VS Code
extension or a separate `vscode-rzk-game` extension when we get here.

### Phase 7 — Content (**Delayed**, can start partially earlier)
- Port the BMSTU demo as the first full game (drives Phases 2–4).
- The ∞-Yoneda game, following Riehl's geodesic (the headline target).
- Modal extensions, once [PR #230](https://github.com/rzk-lang/rzk/pull/230)
  lands.

## 8. Risks and gaps

- **WASM-backend build of `rzk` (resolved).** Previously the highest risk;
  [PR #235](https://github.com/rzk-lang/rzk/pull/235) cross-compiles
  `rzk:lib:rzk` to `wasm32-wasi`, so the core and its dependencies do build.
  Residual concern: keep that CI green and land the PR. The remaining
  integration risk has moved to **0C** (linking with miso).
- **GHC version alignment.** `rzk-js` targets GHCJS 9.6; the WASM build uses the
  `wasm32-wasi` GHC backend. We must keep `rzk`, miso, and the WASM toolchain on
  mutually compatible GHC versions (PR #235 fixes a concrete working point to
  pin against).
- **Holes are new language work.** Typed holes do not exist in Rzk today. The
  design (syntax + how incomplete terms typecheck + what context is reported)
  is non-trivial and is the main schedule risk after the build spike.
- **Incremental reuse granularity.** If we cannot cheaply reuse the prelude
  context, per-keystroke checking may be slow for large preludes. *Measured:* the
  full sHoTT project takes ~65 s cold with no persistent CLI cache
  ([`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md) §6), so prelude reuse is
  essential. Mitigation: in-process check-in-context (Section 4.5); check on
  demand (debounce / on submit) rather than per keystroke for the MVP.
- **Editor ↔ WASM interop (at L2).** If we adopt CodeMirror 6 (Section 6.3), we
  own the JSFFI glue; miso provides no editor, so markers, hole widgets, and the
  diagnostics gutter are bespoke. The L0 textarea MVP avoids this entirely.
- **UI is hand-built in miso.** No React component reuse (Section 6): panels,
  the world map, the inventory, and dialogs are reimplemented in miso + CSS.
  `lean4game` is a layout reference, not a code source. Mitigation: start the
  design sub-track now, in parallel; keep the MVP layout simple.
- **Hint matching.** Matching on a hole's goal/context is more subtle than
  Lean4's tactic-state matching and depends on Phase 1 introspection quality.
- **WASM bundle size and memory — retired.** *Measured (Phase 0 spike):* the
  combined rzk+miso module is 9.0 MB raw → 4.9 MB after `wasm-opt`/strip →
  **0.8 MB brotli** over the wire. On an iPhone (iOS 18.7 Safari) it runs with
  **9.7 MB peak wasm memory** (identical to desktop) and 30 ms compile — far
  under any iOS WASM cap, so the "large module crashes the tab" risk does not
  materialise. Cold start (~370 ms) is download-bound; brotli + GitHub Pages is
  the lever. Treat the measured size/memory as a budget for later phases.

## 9. Repository organisation

Refining the `ideas-1.md` plan (target home: `rzk-lang`). All four planned repos
now exist under `rzk-lang`:

- `rzk-lang/rzk-game` — the engine (this repo); compiles a game spec into a
  static WASM app, and publishes the engine + bundler as release artifacts. **Live.**
- `rzk-lang/rzk-game-action` — composite GitHub Action that fetches a pinned
  engine release, bundles a game repo's `game/`, and assembles `public/` for
  deploy. **Live, tagged `v1`** (Phase 4).
- `rzk-lang/yoneda-game` — the ∞-Yoneda game (Phase 7). **Scaffold only** (one
  starter level, deploys via `rzk-game-action@v1`); real content lands later.
- `rzk-lang/rzk-game-template` — template game spec (Phase 5). **Created, empty**,
  ready to seed.
- `rzk-lang/vscode-rzk-game` — *(possibly)* VS Code support (Phase 6).

Upstream `rzk` changes (Section 4) live in `rzk-lang/rzk`, not here.

**Dependency on rzk.** rzk stays in `rzk-lang/rzk`. This repo pins it as a
`source-repository-package` (a commit), built with `flags: -lsp`. The build
specialness lives upstream (Section 4, item 1): once rzk's library is
`build-type: Simple` with a CI lane guarding the generated parser against drift,
this repo needs no vendoring and no build-time patching. The Phase 0 spike's
local-path pin and hand-applied Custom→Simple mutation
([`spikes/phase0-wasm/`](./spikes/phase0-wasm/)) were a stopgap for the spike
only. The holes / structured-diagnostics / goal-query work is *not* a satellite
of the game: it is upstream rzk work that also improves the language server and
CLI (Section 4), so it is sequenced and owned there, and the engine simply bumps
its rzk pin to pick it up.

## 10. Open decisions

Already decided (Section 2.3): frontend = miso on GHC WASM backend; invest in
holes early; website-first.

Delayed — to settle when we reach the relevant phase:

| # | Decision | When | Candidate options |
|---|---|---|---|
| D1 | Hole surface syntax in Rzk | **resolved (#237)** | `?` and named `?name` (holes allowed only in checking position) |
| D2 | How `*.rzk.md` is partitioned into prelude / editable / solution | **resolved (Phase 3 handoff)** | fenced rzk-block roles: ```` ```rzk prelude/template/solution ````; goal name+type read from the `template` `#def`; prose in YAML for the MVP. See [`phase3-handoff.md`](./phase3-handoff.md) |
| D3 | Editor surface (see Section 6.3) | **decided: L1** (Phase 2 shipped L1) | L0 textarea+panels; L1 overlay highlight; L2 CodeMirror 6 via JSFFI, reusing rzk-playground's Rzk language mode |
| D4 | Per-keystroke vs. on-submit / debounced checking | **decided: on-submit** (Phase 2; preludes check in ms) | depends on incremental reuse perf (Section 4.5) |
| D5 | Game-config YAML schema specifics | **resolved (Phase 3 handoff)** | minimal lean4game-shaped YAML, decoded as JSON via aeson after a native YAML→JSON bundle step (single `game.json`, one `fetch`, no yaml-in-wasm). See [`phase3-handoff.md`](./phase3-handoff.md) |
| D6 | VS Code: extend existing extension vs. separate `vscode-rzk-game` | Phase 6 | — |
| D7 | i18n / multiple languages per game (`lean4game` has this) | post-MVP | defer |
| D8 | Phase 0 fallback: single WASM binary vs. miso-WASM UI + GHCJS `rzk-js` checker | Phase 0 | only if 0A/0C fails |
| D9 | Styling approach in miso (no component library) | design sub-track / Phase 2 | hand-rolled CSS; utility CSS (Tailwind) via a build step; adapt `lean4game`'s CSS |
| D10 | Look-and-feel direction | design sub-track (needed early) | mirror `lean4game`'s layout; Agda/hole-native; minimal MVP, design later |
| D11 | Responsive + accessibility scope for the MVP | **decided** | desktop-first authoring; phones run + read/browse only (Section 6.4); keyboard navigation in scope; comfortable mobile authoring deferred |
| D12 | Visualisation of topes / cube-indexed terms in goal, context, and editor | future (post-MVP) | reuse Rzk's existing SVG diagram rendering of shapes/topes; expose it from the WASM build and show diagrams beside the textual context (Section 5 of the storyboard). Not part of the holes track or the MVP |
| D13 | Library-wide lemma search (`exact?` / Hoogle-by-type over all of sHoTT) | future (post-MVP) | MVP = smart inventory only (goal-ranked, level-scoped — storyboard §6.1). If added: author-enabled per level, gated behind an explicit action, with a perf budget (goals need normalising; the library is large, ~65 s full check) |

**Note on diagram rendering (D12), 2026-06-18.** With KaTeX now vendored for
prose (it renders the level intros/conclusions), the question came up whether
KaTeX could also draw the commutative/simplicial diagrams. Probing the vendored
KaTeX 0.16.11 settles it: KaTeX supports only the `amscd` `CD` environment (and
only in display mode, which our `$$…$$` path already uses), so an author can drop
a `\begin{CD}…\end{CD}` square into prose today with no code change. But `CD` is a
rectangular grid with horizontal/vertical arrows only (`@>>>`, `@<<<`, `@VVV`,
`@AAA`, `@=`, `@|`) — **no diagonal arrows**, so the `hom2` *triangle* (a
2-simplex), the central object of the game, cannot be drawn with it. KaTeX also
has no `tikz-cd` and no `xypic`/`xymatrix` (both confirmed to throw). So KaTeX
covers squares/naturality for free, but not the triangles, the 2-simplex, or the
cube/tope geometry. This confirms the D12 direction: the right path for the
simplicial diagrams is to reuse **rzk's own SVG rendering** of shapes/topes
(exposed from the WASM build) rather than a TeX diagram package. Alternatives if
author-drawn diagrams are wanted instead: pre-render `tikz-cd` to SVG at
build time (adds a build-time LaTeX dependency, no interactivity), or `quiver`
(q.uiver.app) for hand-drawn diagrams exported to SVG/`tikz-cd`.

Decisions that may need your input *soon* (before or during Phase 0), not
blocking this document:

- **GHC/toolchain pin** for the WASM build (D-adjacent to the version-alignment
  risk).
- **D1 (hole syntax)** — worth an early sketch since it touches the parser.
- **D10 (look-and-feel direction)** — needed early if the design sub-track
  starts in parallel with Phases 0–1.
