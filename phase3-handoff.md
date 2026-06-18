# Phase 3 handoff — game spec format and loader

This note scopes Phase 3 so the next session can start implementing cold. The
decisions below are **pinned**, not open: a recommended path was chosen for each
so work can begin without further deliberation. They can still be revised if an
obstacle appears, but the default is to build them as written. Context:
[`roadmap-1.md`](./roadmap-1.md) Sections 5 and 7.

## Where Phase 3 starts

Phases 1 and 2 are done. The structural half of Phase 3 is already built while
authoring content:

- `RzkGame.Section` is the multi-level model — sections (worlds), ordered items,
  prerequisites, locking, and progress. Pure and headlessly tested.
- Markdown + KaTeX prose rendering works (the `renderInto` path in `prose.js`).
- Navigation across sections and levels works (the level map, the nav bar).

What is *not* done is the spec format. Today the whole game is Haskell literals:
the 15 levels and their sections live in `RzkGame.Content`. Adding or editing a
level means editing Haskell and rebuilding the wasm. Phase 3 lifts that content
out of Haskell into an authorable spec, plus a loader that rebuilds the same
model from data.

*Exit (unchanged):* load a small custom game from a spec and navigate its worlds
and levels.

## The target the loader must produce

The loader's output is exactly the model the engine already consumes, so nothing
downstream of `RzkGame.Content` changes:

- a `[Section]` (`RzkGame.Section`), each section an ordered list of
  `SProse` / `SPuzzle` items;
- each `SPuzzle` wraps a `PuzzleItem` (id, role, prereqs, remedies) around a
  `Level` (`RzkGame.Level`);
- a `Level` needs: title, intro/statement/conclusion prose, the read-only
  `levelPrelude`, the `levelTemplate` (editable, with `?`), a `levelSolution`,
  and the pinned `levelGoalName` + `levelGoalType` (the win condition).

So Phase 3 is, in essence: *parse a spec into `[Section]`*. Flattening, locking,
progress, and the UI are reused verbatim.

## Decision 1 (pinned) — runtime load via a single JSON bundle

The engine stays a generic static single-binary wasm app; a game is **data**,
swapped without rebuilding the engine. The pipeline:

1. The author edits `game.yaml` plus `levels/*.rzk.md` (human-friendly: YAML and
   Markdown).
2. A **native** bundle step — `make bundle`, later run by `rzk-game-action` —
   converts the YAML to JSON and inlines every referenced file's contents into a
   single `public/game.json`:

   ```json
   { "config": { ...the game.yaml as JSON... },
     "files":  { "levels/my-id.rzk.md": "…contents…", "…": "…" } }
   ```
3. The wasm app does **one** `fetch("game.json")`, hands the string to Haskell,
   and builds `[Section]` in-process.

**Why this shape.** Moving YAML→JSON to the native bundle step means the wasm app
parses only **JSON with aeson**, which already builds and runs under the wasm
backend (proven in Phase 2). It avoids the yaml-in-wasm question, multiple async
fetches and their ordering, and any fetch round-trips. Authors still write YAML +
Markdown; the bundler packs them. Build-time codegen (Template Haskell compiling
content into the wasm) is **rejected**: every game would need a wasm rebuild,
which defeats "author without touching the engine" (Phase 5).

*Trade-off, accepted:* a game cannot be loaded without the bundle step. Fine — a
static-site deploy always has a build step, and the action runs it.

## Decision 2 (pinned, D2) — partition by fenced rzk-block roles

One `.rzk.md` per level. Code is split by **info string on the fenced block**:

````markdown
```rzk prelude
#def id-hom … := …
```

```rzk template
#def my-id (A : U) (x : A) : hom A x x
  := ?
```

```rzk solution
#def my-id (A : U) (x : A) : hom A x x
  := \ t → x
```
````

- `levelPrelude` = all `prelude` blocks, concatenated in order.
- `levelTemplate` = the single `template` block.
- `levelSolution` = the single `solution` block.
- `levelGoalName` / `levelGoalType` = parsed from the `template` block's
  `#def <name> : <type> := …`. The signature must already be the *closed* Π-type
  that the win-condition check appends (`__rzkgame_goal_check`), so the author
  writes a closed type there.

rzk's `tryExtractMarkdownCodeBlocks` already isolates ```` ```rzk ```` blocks;
extend that idea to read the role word after the language tag. Rejected
alternatives: YAML sidecar (splits one level across two files), naming
conventions (file sprawl), in-source `-- BEGIN/END` markers (clutters the
source).

**MVP prose split.** For the first cut, the *prose* fields — `title`,
`statement`, `intro`, `conclusion`, `inventory` — live in `game.yaml`, not the
`.rzk.md`. This keeps the file splitter trivial (extract three tagged blocks).
*Planned refinement (non-blocking):* move `intro`/`conclusion` into the `.rzk.md`
Markdown body (prose before the first code block = intro; a trailing
`## Conclusion` section = conclusion). The `Level` model is identical either way,
so this is a later, local change to the splitter.

## Decision 3 (pinned, D5) — minimal, lean4game-shaped schema

Decoded with **aeson** `FromJSON`. Minimal first; grow as needed.

```yaml
title: "A small Rzk game"
sections:
  - id: morphisms
    title: "Morphisms"
    items:
      - prose:
          id: morphisms-intro
          role: bridge-in           # optional BOPPPS tag
          text: |                    # Markdown/TeX inline (or `file:` ref)
            We start with morphisms…
      - puzzle:
          id: my-id
          role: core                 # core | pretest | extra
          file: levels/my-id.rzk.md
          title: "The identity morphism"
          statement: "hom A x x"
          intro: |
            Build the identity…
          conclusion: |
            Every object has one…
          inventory: ["id-hom : (A : U) → (x : A) → hom A x x"]
          prereqs: []                # ids of puzzles that must be satisfied
          remedies: []               # optional remediation pointers
```

Field names mirror the `Section`/`PuzzleItem`/`Prose` records so the `FromJSON`
instances are mechanical. Reuse rzk's `Rzk.Project.Config` (it parses `rzk.yaml`
with aeson) as the precedent for the bundler, and keep the game config a wrapper
around `rzk.yaml` rather than a replacement (roadmap §2.1).

## Module and code plan

- **`RzkGame.Spec`** (new) — the schema records + `FromJSON` instances, and the
  `.rzk.md` block splitter (`splitLevelSource :: Text -> Either Text (prelude,
  template, solution)` plus `goalFromTemplate :: Text -> Either Text (name,
  type)`). Pure.
- **`RzkGame.Loader`** (new) — `buildGame :: ByteString -> Either Text [Section]`
  (parse `game.json` with aeson, resolve `file:` refs against the inlined
  `files`, run the splitter, assemble `[Section]`). Pure and headlessly testable.
- **`app/Main.hs`** — a thin JSFFI shim to `fetch("game.json")` and feed the
  bytes to `buildGame`; on success use the loaded sections, on failure fall back
  to the built-in `RzkGame.Content`.
- **`RzkGame.Content`** — kept as the built-in fallback fixture and as test data.
- **`Makefile`** — a `bundle` target (native) that reads `game.yaml` + level
  files and writes `public/game.json`.

## Tests

- `buildGame` on a small literal `game.json` fixture reproduces a known
  `Section` (compare against the corresponding `RzkGame.Content` value).
- `splitLevelSource` / `goalFromTemplate` round-trip on a sample level.
- Keep the existing soundness checks (`hs_selftest`) running against the *loaded*
  model, or against a tiny literal fixture, so content-as-data stays verified.

## First steps (in order)

1. `RzkGame.Spec`: schema records + `FromJSON`, and the block splitter. Unit-test
   the splitter on a literal sample.
2. `RzkGame.Loader.buildGame`: assemble `[Section]` from a literal `game.json`
   fixture; assert it matches a `Content` section. (No wasm yet — native test.)
3. `make bundle`: pack `game.yaml` + `levels/*.rzk.md` → `public/game.json`.
4. JSFFI `fetch("game.json")` in `Main`; load behind a fallback to `Content`.
5. Port one section (*Morphisms*) to `game.yaml` + `.rzk.md` files and play it
   from data end-to-end. **That is the Phase 3 exit.**
