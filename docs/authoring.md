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

The table of contents is `game.yaml`. It holds an `id`, a title (shown as the
heading at the top of the page, so a game reads under its own name) and an
ordered list of `chapters`. A chapter has an optional `title` and an ordered list
of `sections`. An untitled chapter renders its sections at the top level, so a
flat game is just one untitled chapter. A section has an `id`, a `title`, and
ordered `items`. Each item references a file by path, tagged `prose:` or
`puzzle:`.

Four more fields are optional, and each replaces something the engine would
otherwise say for itself. `subtitle` is the line under the title. `completion` is
what a player reads once every required activity is done, rendered as Markdown so
a game can point at whatever comes next. `repository` says where the content
lives, for a reader with a fix to suggest. `edit-url` is a template containing
`{file}`, and setting it gives every page a link to its own source file, which is
what makes an offer of pull requests actionable.

`repository` and `edit-url` are about content. A checker crash is an engine or an
rzk bug, and the crash panel reports it to the engine's own tracker, which is not
something a game configures.

Set the game's `id`. It namespaces the player's saved progress. Games published
to GitHub Pages share one origin and differ only by path, while `localStorage` is
per-origin, so without distinct ids two games share one set of keys and overwrite
each other's progress. A game that sets no `id` falls back to a slug of its
title. That works until the title changes, at which point the namespace moves
with it and the saved progress is orphaned.

```yaml
id: my-game        # namespaces saved progress, keep it stable
title: My game
subtitle: A short line under the title.
completion: You finished. [Try the next game](https://example.org/next/).
repository: https://github.com/me/my-game
edit-url: https://github.com/me/my-game/edit/main/game/{file}
chapters:
- sections:
  - id: getting-started
    title: Getting started
    items:
    - prose:
        file: levels/how-holes-work.md
- title: Directed type theory
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
- name: id-hom
  synopsis: the identity morphism at a point
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
- `inventory` lists the prelude lemmas the level grants. Each entry is a `name`,
  with an optional one-line `synopsis` and an optional `type` (the type is
  otherwise read from the prelude). See *Inventory and gating* below.
- `forbidden` lists built-in eliminators the level bans, such as `idJ`, `first`,
  `second`, or `recOR`. See *Inventory and gating* below.
- `hints` is an ordered list. See *Hints* below.
- `checks` is an optional list of behaviour checks the finished solution must
  satisfy on top of having the goal type. See *Behaviour checks* below.
- `gated`, when `true`, makes an inventory or forbidden-move violation fail the
  check. It defaults to `false`.
- `moves`, `autohide-single-move`, and `requires-typing` control the Moves panel
  and the "requires typing" badge. See *The Moves panel* below. All three are
  optional and default off.

The body has these roles of fenced rzk block, with surrounding prose.

- A `rzk prelude` block holds the read-only, already-checked definitions the
  player builds on. Every `prelude` block is concatenated in order. Start it with
  `#lang rzk-1`.
- A `rzk template` block is the editable region's starting text, with a `?` where
  the player works. There is exactly one.
- A `rzk solution` block is a reference solution. There is exactly one. The suite
  checks that it solves, so it doubles as a test.
- A `rzk postcheck` block holds behaviour checks (optional). See *Behaviour
  checks* below.
- The Markdown before the first rzk block is the intro prose. (A plain `rzk`
  display block, with no role word, stays part of the intro.) The Markdown under
  a trailing `## Conclusion` heading is shown on success.

Note that the engine recovers the goal the player must produce, both its name and
its closed type, from the template's `#def`. So an author does not state them
twice. The win condition is that a definition of that name with that type is in
scope and hole-free. Intuitively, this means an empty editable region cannot
pass. When the goal `#def` declares a `uses (…)` clause, the win-check carries
it, so a level can require the proof to genuinely use a named assumption such as
`funext`.

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

One prose page is special. Give a page the `id` `how-holes-work`, and the engine
shows a persistent "❓ Holes" link in the header that jumps to it from any page.
A game without such a page simply has no link.

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

The `inventory` lists the prelude lemmas a level grants. It doubles as the
"Allowed here" reference shown beside the moves. Each entry is a `name`, with an
optional one-line `synopsis` and an optional `type`. The type is read from the
`#def`/`#postulate` that declares the name, so an entry is usually just a name
and a synopsis. Give an explicit `type` when the prelude cannot supply a useful
one: an `#assume`d or `#variable` lemma shows no type at all (only `#def` and
`#postulate` declarations are read), and an opaque alias such as
`UnivalenceAxiom` reads better unfolded to its applicable shape, e.g.
`(A : U) → (B : U) → Equiv (A = B) (Equiv A B)`. A bare string entry is read as
the name alone.

By default the inventory is informative only. After a check, the engine scans the
identifiers the proof body uses, keeps those the prelude defines, and reports any
that are not granted. This is a soft amber notice, a heads-up rather than a
blocker. Set `gated: true` to make a violation hard. Then a proof that uses an
ungranted prelude lemma does not count as solved, even when it type-checks, and
the success is withheld until only granted moves are used.

The `forbidden` list bans rzk's built-in eliminators, which the inventory cannot
reach because they are not prelude definitions. List any of `idJ`, `first`,
`second`, or `recOR` to ban it: a forbidden move is dropped from the Moves panel,
and one written into a proof body is flagged like an ungranted lemma — a soft
notice by default, or a hard failure under `gated: true`.

Only proof bodies are scanned, the text after each `:=`, never the type
signatures. So the type formers a goal mentions are never flagged. Only
prelude-defined names are kept, so local hypotheses and keywords are ignored. A
level with an empty inventory gates nothing. Importantly, before turning `gated`
on, check that the reference solution uses only granted names and no forbidden
move, since a gated level whose solution trips its own gate cannot be solved.

## Behaviour checks

The win condition is that the player produces a definition of the goal name with
the goal type, hole-free. A type does not always pin the answer: `not : Bool →
Bool` is inhabited by the constant `\ _ → false`, and `plus`, `double-ℕ`, and
similar are passed by wrong-but-well-typed terms. The `checks` list closes that
gap. Each check is a proposition the finished solution must satisfy; the engine
appends it as its own definition after the player's proof and requires it to
type-check. A check only runs once the proof is otherwise complete, so it never
interferes with the hole-by-hole flow.

```yaml
checks:
- not true = false                    # bare string: proved by refl
- prop: not (not true) = true         # object form: explicit proof + summary
  by: refl
  label: negation is involutive at true
```

A bare string is the proposition, proved by `refl`. Because `#data` computation
is definitional, a `refl` check pins behaviour exactly: `not true = false` holds
only when the player's `not` actually computes `true` to `false`, so the constant
`\ _ → false` is rejected. The object form `{ prop, by }`, above, gives an
explicit proof term and an optional `label` (see below). `by` defaults to `refl`;
give a different term only when `refl` is not enough — for instance naming a lemma
the prelude grants, `by: plus-comm 1 2`. The proof is checked with the player's
definition and the prelude in scope. A front-matter check is a closed
proposition; a check that quantifies over a variable (`(b : Bool) → …`) is better
written as a block, below.

The front-matter form is convenient for closed one-liners, but a check that must
quantify over the level's parameters gets unwieldy: the parameters are the
solution's telescope, not in scope at the top level, so the proposition has to
re-declare the whole telescope (and the proof re-bind it). For those, write a
`rzk postcheck` block in the body instead — a fenced code block like `prelude` /
`template` / `solution`:

````markdown
```rzk postcheck
-- label: contra-yon computes to the composite
#def _contra-yon-computes
  (A : U) (is-segal-A : is-segal A) (a b : A)
  (v : hom A a b) (z : A) (f : hom A z a)
  : contra-yon A is-segal-A a b v z f = comp-is-segal A is-segal-A z a b f v
  := refl
```
````

Each `#def` in the block is one check: its type is the proposition and its body
the proof, so the telescope is written once, the natural way. A `-- label: …`
comment on the line before a `#def` gives it the plain-English summary shown when
it fails (otherwise the written proposition is used). The two forms are
equivalent and may be combined; a block `#def` is checked independently, like a
front-matter check, so a helper a check relies on belongs in the prelude, not the
block.

When a solution type-checks and is hole-free but a check fails, the engine
reports it as a distinct "so close" result listing the checks that must hold,
rather than a type error or a win. Each is shown by its `label` if given,
otherwise by its proposition (for a block check, its written type, without the
telescope prefix the check carries internally). Keep checks to the observable
behaviour the type misses; they are not a place to re-prove the goal.

## The Moves panel

The Moves panel offers tap-to-fill steps for the focused hole: the introduction
and elimination moves the goal admits, plus the granted inventory lemmas. A few
optional front-matter fields tune how much it gives away.

- `moves` sets the panel's mode for the whole level.
  - `on` (the default) shows the moves as buttons.
  - `obscure` hides the buttons behind a nudge that reports how many moves fit
    and offers a *Reveal* button, so the player is asked to find the step before
    being shown it.
  - `off` hides the panel entirely, so the proof must be typed by hand.
- `autohide-single-move`, when `true`, degrades a hole to `obscure` only when
  exactly one move applies, and leaves it `on` otherwise. Use it to stop the
  panel from simply handing over a forced step, while still helping where there
  is a genuine choice. It has no effect on an `obscure` or `off` level.
A "⌨ typing" badge on a level's heading and tile flags that it cannot be solved
by taps alone. It is set automatically: at bundle time the engine replays the tap
loop over the reference solution, and a level whose solution no sequence of moves
reconstructs is marked as requiring typing (a `moves: off` level always is, since
it offers no taps). The classification is baked into the bundle, so the browser
never recomputes it.

- `requires-typing` overrides that automatic decision when set: `true` forces the
  badge on, `false` forces it off. Leave it unset to trust the classifier. It has
  no effect on a `moves: off` level, which always requires typing.

Two things are worth knowing. A player can hide the panel everywhere from the
action bar; that global preference wins, so an `on` or `obscure` level shows
nothing when the player has opted out. And `off`/`on` are YAML booleans — `moves:
off` parses as `false` and `moves: on` as `true` — which the reader accepts as
`off` and `on`; either spelling works, and `obscure` is a plain string.

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
- Grant only what the puzzle needs. List the relevant lemmas in `inventory`,
  and `forbidden` for any built-in shortcut to rule out. Where the puzzle should
  force a construction by hand, set `gated: true`.
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
