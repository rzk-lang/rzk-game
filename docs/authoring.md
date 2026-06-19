# Authoring a Game

This guide is for authors. It explains how to write a game without reading the
engine source. An author edits data files under `game/`, and the engine compiles
them into a single playable web page.

A game has two parts. The first is a table of contents, `game/game.yaml`. The
second is one file per item under `game/levels/`. Each item is either a puzzle (a
proof the player fills in) or a prose page (text the player reads). The table of
contents only orders the items and records how they gate each other. Everything
intrinsic to an item lives in its own file. Thus a level file is portable across
games.

## The Local Loop

First, install the toolchain. The reproducible route uses
[Nix](https://nixos.org/download/) with flakes enabled (the
[Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
enables them by default). Running `nix develop` then provides
`wasm32-wasi-cabal` and the rest of the toolchain. Without Nix, install the WASM
toolchain via
[`ghc-wasm-meta`](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta)
(FLAVOUR 9.12), then run `source ~/.ghc-wasm/env`. Then, after editing files
under `game/`, run two targets.

```sh
make bundle      # parse game/ into public/game.json (fast, native)
make serve       # serve public/ locally and play
```

`make bundle` reparses `game.yaml` and each level file's front-matter. When a
file fails to parse, it reports the first one. A full rebuild of the web app is
rarely needed; `make all` does it.

One further target helps while authoring. `make format-game` rewrites the
`rzk prelude` blocks in place with rzk's canonical formatting. Run it when a
prelude looks untidy. Templates and solutions are left as written.

The working check on your own content is `make bundle` followed by `make serve`.
The bundle parses, and each level plays: its template holes, and its solution
solves. For a published game the CI lane does the equivalent on every push, by
bundling the game and checking the assembled site. (`make test` runs the engine's
own spec suite. It pins this repo's built-in game, so it checks the engine rather
than your game.)

Finally, a game deploys through
[`rzk-lang/rzk-game-action`](https://github.com/rzk-lang/rzk-game-action) in CI.
An author forks a template, edits `game/`, and gets a live site with no Haskell
toolchain. Pin the `engine-version` input to the release the game is authored
against.

## The Table of Contents

The table of contents is `game.yaml`. It holds a title and an ordered list of
sections. A section has an `id`, a `title`, and ordered `items`. Each item
references a file by path, tagged `prose:` or `puzzle:`.

```yaml
title: My game
sections:
- id: morphisms
  title: Morphisms and triangles
  items:
  - prose:
      file: levels/morphisms-intro.md
  - puzzle:
      file: levels/my-id.rzk.md
  - puzzle:
      file: levels/map-point.rzk.md
      role: pretest
      remedies:
      - label: 'Review: the basics'
        section: morphisms
  - puzzle:
      file: levels/ap-hom.rzk.md
      prereqs:
      - map-point
  - prose:
      file: levels/morphisms-summary.md
```

A `puzzle:` reference carries the placement metadata. This is the part about a
puzzle's place in this game, not about the puzzle itself.

- `role` is `core` (the default), `pretest`, or `extra`. Core puzzles gate section
  completion. A pre-test doubles as a self-assessment. An `extra` (★) is optional
  enrichment, and does not gate completion.
- `prereqs` is a list of puzzle ids that must be satisfied before this one
  unlocks. A puzzle is satisfied once solved, or once the player marks its
  pre-test "I already know this".
- `remedies` are labelled pointers, shown when a player is stuck on a pre-test or
  locked out. Each has a `label` and exactly one target: an in-game `section` id,
  an in-game `level` (puzzle) id, or an external `url`.

A `prose:` reference is just a `file`. The prose page carries its own metadata.

## A Puzzle File

A puzzle file lives at `levels/<id>.rzk.md`. It is YAML front-matter, then a
Markdown body that mixes prose with fenced rzk code blocks.

````markdown
---
id: rut
title: The right-unit triangle
statement: hom2 A x y y f (id-hom A y) f
inventory:
- 'f        : hom A x y'
- 'id-hom   : (A : U) → (x : A) → hom A x x'
hints:
- text: 'The right edge is the identity at $y$, so the whole triangle is just $f$ reparametrised.'
- text: 'Look at the bottom edge of the goal: `↦ f t`. Apply $f$ to the first coordinate.'
  when-goal: '↦ f t'
gated: false
---

Now an edge becomes a genuine morphism. Given $f : x \to y$, the triangle whose
right edge is the identity at $y$ has $f$ itself as its hypotenuse. Build it.

```rzk prelude
#lang rzk-1
#def hom (A : U) (x y : A) : U
  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]
-- … the rest of the given definitions …
```

```rzk template
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → ?
```

```rzk solution
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → f t
```

## Conclusion

The degenerate triangle is just $f$ ignoring the second coordinate.
````

The front-matter holds the intrinsic metadata.

- `id` is the stable id, referenced by `prereqs` and by the file path.
- `title` is the heading shown on the page.
- `statement` is the goal in human-readable form, shown in the Goal panel.
- `inventory` lists the lemmas and moves the level grants, one per line as
  `name : description`. The leading token is the granted name. See *Inventory and
  gating* below.
- `hints` is an ordered list. See *Hints* below.
- `gated`, when `true`, makes an inventory violation fail the check. It defaults
  to `false`.

The body has three roles of fenced rzk block, with surrounding prose.

- A `rzk prelude` block holds the read-only, already-checked definitions the
  player builds on. Every `prelude` block is concatenated in order. Start it with
  `#lang rzk-1`.
- A `rzk template` block is the editable region's starting text, with a `?` where
  the player works. There is exactly one.
- A `rzk solution` block is a reference solution. There is exactly one. The suite
  checks that it solves, so it doubles as a test.
- The Markdown before the first rzk block is the intro prose. (A plain `rzk`
  display block, with no role word, stays part of the intro.) The Markdown under
  a trailing `## Conclusion` heading is shown on success.

Note that the engine recovers the goal the player must produce, both its name and
its closed type, from the template's `#def`. So an author does not state them
twice. The win condition is that a definition of that name with that type is in
scope and hole-free. Intuitively, this means an empty editable region cannot
pass.

## A Prose Page

A prose page lives at `levels/<id>.md`. It is front-matter and a Markdown body.

```markdown
---
id: morphisms-intro
title: Start here
role: bridge-in
---

In directed type theory a **morphism** $x \to y$ is a path along the directed
interval $\Delta^1$ …
```

Its `role` is a BOPPPS tag, used only to label the page. The tags are
`bridge-in`, `outcomes`, `participatory`, `post-test`, `summary`, and `note`. The
tag is advisory. A page needs none, and may sit anywhere in a section. Prose and
TeX render as they do in a puzzle's intro.

## Hints

A hint is authored prose, shown when the player asks. Hints are hidden by
default. A level shows only a "Show a hint" button until the player taps it.
There are two kinds of hint.

- A plain hint has no `when-goal`. The button reveals the plain hints one at a
  time, in order. Write them from most general to most specific.
- A contextual hint carries a `when-goal` trigger. Once the player has asked for
  a hint, a contextual hint is shown automatically while its trigger is a
  substring of the focused hole's goal, and hidden again when the goal moves on.
  The button never reaches it, so it never shows out of context.

Matching is a plain case-sensitive substring test on the goal text, as it appears
in the hole's Goal panel. It is not structural unification. So a trigger can be
chosen by reading that panel. A contextual hint is best tied to a goal feature
the player leaves behind as they make progress, so the hint appears only while it
is relevant.

## Inventory and Gating

The `inventory` lists what a level grants. It doubles as the "Allowed here"
reference shown beside the moves. The leading token of each entry is the granted
name.

By default the inventory is informative only. After a check, the engine scans the
identifiers the proof body uses, keeps those the prelude defines, and reports any
that are not granted. This is a soft amber notice, a heads-up rather than a
blocker. Set `gated: true` to make a violation hard. Then a proof that uses an
ungranted prelude lemma does not count as solved, even when it type-checks, and
the success is withheld until only granted moves are used.

Only proof bodies are scanned, the text after each `:=`, never the type
signatures. So the type formers a goal mentions are never flagged. Only
prelude-defined names are kept, so local hypotheses and keywords are ignored. A
level with an empty inventory gates nothing. Importantly, before turning `gated`
on, check that the reference solution uses only granted names, since a gated
level whose solution trips its own gate cannot be solved.

## How to Make a Good Puzzle

A few guidelines have proven useful. They are recommendations, not rules.

- Pin the goal by name and type. Give the template `#def` a definite name and a
  closed type. Then an empty region cannot pass, and the player must produce
  exactly that definition.
- Start from the solution. Write the reference solution first, then blank out the
  parts the player supplies to form the template. The template then holes, and
  the solution solves, by construction.
- Keep the editable region small. Put the given machinery in the prelude, and
  leave only the step the puzzle is about in the template. A one-line hole is
  often enough.
- Grant only what the puzzle needs. List the relevant lemmas in `inventory`.
  Where the puzzle should force a construction by hand rather than a shortcut, set
  `gated: true`.
- Write the framing. The `statement` is the human-readable goal, the intro
  motivates it, and the conclusion states the takeaway.
- Order the hints from general to specific, and add a contextual `when-goal` hint
  for the step the goal makes obvious.

## BOPPPS-style Sections

A section is a lesson, not just a list of puzzles. The sections follow the BOPPPS
model from instructional design, which gives a section a clear arc. The structure
is recommended rather than mandatory, since prose may sit anywhere.

- Bridge-in. Open with a prose page (`role: bridge-in`) that connects to what the
  player already knows.
- Outcomes. State what the player will be able to do, either as a `role: outcomes`
  page or as a line in the bridge-in.
- Pre-test. Gate a dependent puzzle with a `pretest` puzzle, and give it
  `remedies`, so an unready player is sent somewhere useful.
- Participatory. Sequence the `core` puzzles that form the body of the section.
- Post-test and summary. Close with a `summary` page. Reaching it once the section
  is complete doubles as a completion marker.

Finally, map each BOPPPS stage to a prose `role` tag or a puzzle `role`. Mark
optional enrichment puzzles `extra` (★), so they do not gate completion. This
structure has proven comfortable to work with, but it is a recommendation, not a
requirement.
