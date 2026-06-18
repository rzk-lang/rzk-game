# Hole-Interaction Storyboard

This is the gating design artifact for Phase 2 of [`roadmap-1.md`](./roadmap-1.md)
(Section 6.2). It fixes the *interaction model* the level UI is built against:
how a hole is shown, focused, filled, and refined, and where the goal and context
appear. The model is editor-surface-agnostic; the same model renders at L0
(textarea + panels), L1 (overlay), or L2 (CodeMirror) per decision D3. The
desktop frames come first, followed by the L0/L2 mapping and the mobile variant.

This is a first sketch (`-1`). It is meant to be marked up and argued with, not
treated as settled.

## 1. Running example

We use function composition, because its proof term is a short refinement chain
and shows the loop end to end.

```
#def comp
  (A B C : U)
  (g : B → C)
  (f : A → B)
  : A → C
  := ?            -- the player fills this
```

The intended solution is `\x → g (f x)`. The player reaches it by refinement:
introduce a binder, then apply `g`, then `f`, then `x`.

## 2. Notation used in the frames

- `{ }₀`, `{ }₁`, … — an unfilled hole, numbered.
- `▸{ }₁◂` — the *focused* hole; it drives the Goal/Context panel.
- `⊢ T` — the goal: the type expected at the focused hole.
- Status line — number of unsolved holes and whether the term currently
  typechecks.

The surface syntax of a hole (`?`, `{! !}`, `?name`) is decision **D1** and is
deliberately not fixed here; the frames show the *rendered* hole `{ }ₙ`.

## 3. The loop, frame by frame (desktop)

### F1 — Level opens

```
Editor                              Goal / Context
  #def comp                           ⊢ A → C
    (A B C : U)                       ──────────────────────
    (g : B → C)                       A B C : U
    (f : A → B)                       g : B → C
    : A → C                           f : A → B
    := ▸{ }₀◂
                                      Inventory
                                        g   f   x?   λ-intro   comp …
Holes: ▸0 : A → C        Status: 1 hole · not checked
Action: level opens with hole 0 focused; the goal is the declared type A → C.
```

### F2 — Introduce a binder (refine the goal shape)

The goal is a function type, so the player introduces a λ. They tap **λ-intro**
in the inventory (or type `\x → ?`). Refinement rewrites the term and spawns a
sub-hole.

```
Editor                              Goal / Context
    := \x → ▸{ }₁◂                    ⊢ C
                                      ──────────────────────
                                      A B C : U
                                      g : B → C   f : A → B
                                      x : A          ← new
Holes: ▸1 : C            Status: 1 hole · not checked
Action: λ-intro replaced { }₀ with `\x → { }₁`; x : A entered the context;
        the focus moved to the new hole, whose goal is now C.
```

### F3 — Refine with a function head (tap-to-refine)

The goal is `C`, and `g : B → C` produces a `C`. The player taps **g**. Refine
applies `g` and spawns one sub-hole for its missing argument.

```
Editor                              Goal / Context
    := \x → g ▸{ }₂◂                  ⊢ B
                                      ──────────────────────
                                      A B C : U
                                      g : B → C   f : A → B   x : A
Holes: ▸2 : B            Status: 1 hole · not checked
Action: tapping g rewrote { }₁ to `g { }₂`; the new goal is B (g's argument).
```

### F4 — Refine again

The goal is `B`, and `f : A → B`. The player taps **f**.

```
Editor                              Goal / Context
    := \x → g (f ▸{ }₃◂)             ⊢ A
Holes: ▸3 : A            Status: 1 hole · not checked
Action: f { }₃ inserted; the goal is A. Note the parentheses are managed for
        the player — refine inserts a well-formed application spine.
```

### F5 — Fill from context (give)

The goal is `A`, and `x : A` is in context. The player taps **x** (or types `x`
and gives). This *gives* a complete term, spawning no sub-holes.

```
Editor                              Goal / Context
    := \x → g (f x)                  (no focused hole)
                                      ──────────────────────
                                      All holes filled.
Holes: (none)            Status: 0 holes · checking…
Action: x closed the last hole. With no holes left, a check runs.
```

### F6 — Solved

```
Editor                              Goal / Context
    := \x → g (f x)        ✓          ✓ comp typechecks.
                                      Level complete.
Holes: (none)            Status: 0 holes · ✓ checked
Action: the term typechecks with no remaining holes → win condition met.
```

## 4. The error path

Filling a hole with an ill-typed term must be a *gentle*, local event, not a
wall of output. Suppose at F3 the player taps **f** (type `A → B`) where a `C`
is expected.

```
Editor                              Goal / Context
    := \x → ⟨f⟩ { }₂                  ⊢ C
    ~~~~~~~~~~~~                       ──────────────────────
                                      ✗ Type mismatch
Holes: ▸2 : B  (+1 error)             expected:  C
                                      got:       A → B
Status: 1 hole · ✗ 1 error            at the focused hole.
Action: the offending subterm is marked; the panel explains expected-vs-got.
        The player clears the hole (undo) and tries g instead. No progress is
        lost elsewhere.
```

Principles the error path fixes:

- Errors are attached to a *position* (a subterm or hole), never dumped as raw
  compiler text. This needs the Phase 1 structured diagnostics.
- One bad hole does not block reading the goal of the other holes.
- "Clear / undo" is always one action away.

## 5. Rzk-specific: the context panel carries cube and tope assumptions

Unlike a plain type theory, a Rzk goal can sit inside a shape, so the context
has three sections, not one. A hole inside an extension term shows (schematic):

```
Goal / Context
  ⊢ A t                              ← goal may mention cube vars
  ──────────────────────
  Terms      A : Δ¹ → U
  Cube vars  t : 2                   ← the directed interval
  Topes      (0 ≤ t) , (t ≤ 1)       ← assumptions in scope here
```

The storyboard therefore requires the goal/context query (Phase 1, Section 4.4)
to return *all three* sections. The level UI renders them as labelled groups.

Probing real rzk (see [`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md)) sharpens
this. rzk already prints the goal, the context, and the tope context at a
`U`-hole, but: (1) it **dumps the entire global environment** into the context —
at the Segal associativity goal, 896 lines, of which only 9 are the real
locals — so the UI must split local hypotheses from a searchable global
inventory; (2) it **loses binder names under pair patterns** (`(t₁ , t₂)`
becomes `x₁` with `π₁ x₁` / `π₂ x₁`); and (3) it keeps goals pleasantly
**symbolic** (composites are not force-unfolded). The Rzk-native stories S1–S4
(a `hom2` helper, a `recOR` square, Fubini, Segal associativity) and a `recOR`
hole's per-overlap coherence obligations are worked out in those notes.

**Future (not MVP).** The cube/tope context and cube-indexed terms can also be
*visualised* as diagrams, reusing Rzk's existing SVG rendering of shapes and
topes, shown beside the textual sections. This is roadmap decision **D12** and is
explicitly out of scope for the first playable game; the textual context above is
the MVP target.

## 6. The verbs (interaction vocabulary)

The model has a small, fixed set of actions. Everything in the frames is one of
these.

- **Focus** — select a hole; updates the Goal/Context panel. (click / tap a
  hole; or pick it from the Holes panel by number.)
- **Refine** — apply a chosen head (from the inventory or typed) and spawn
  sub-holes for its missing arguments. The mobile-friendly, low-typing path.
- **λ-intro** — the special refine for a function/Π goal: introduce a binder.
- **Give** — commit a complete term into the focused hole; spawns no sub-hole.
- **Clear / Undo** — empty a hole or undo the last refine/give.
- **Hint** — request a hint matched to this hole's goal and context (Phase 5).
- **Discover / Find** — rank the inventory by relevance to the focused hole's
  goal, and, when the player asks, highlight the candidates that could refine it
  (Section 6.1). MVP scope is the level's inventory only.

Refine versus give is the central distinction, mirroring `agda-mode`'s
*refine* (`C-c C-r`) and *give* (`C-c C-SPC`). Refine drives the low-typing,
tap-to-assemble experience that makes the game pleasant on a touch screen.

### 6.1 Lemma discovery (the smart inventory)

The inventory is not a flat palette: it is **ranked by relevance to the focused
hole's goal**. This is lemma discovery at MVP scope — type-directed filtering of
the *level's* inventory — and it is what makes tap-to-refine quick on a small
screen. The player can also press **Find** when stuck, highlighting the
candidates whose result type could refine the current goal.

With the focused goal `⊢ C` (from F3):

```
Goal  ⊢ C
Inventory (ranked for ⊢ C)              [ Find ]
  ★ g : B → C        produces C — top candidate
  ★ h : A → C        also produces C
    f : A → B        does not produce C — dimmed
    comp …           matches after unification — lower
```

Tapping a ranked candidate refines the hole (the *refine* verb). The ranking
uses the goal from the Phase 1 query; because rzk keeps goals symbolic (probe
notes §5) the candidate's result-type head is usually visible to match against,
and the inventory is small and gated, so the search is cheap.

Out of scope for the MVP, recorded as roadmap **D13**: **library-wide** search
(`exact?` / Hoogle-by-type over all of sHoTT). It is powerful but expensive — the
library is large and goals need normalising to match — and it can trivialise
levels, so if added it is author-enabled per level and gated behind an explicit
action.

## 7. Hole states

The UI must distinguish, visually, the following states (the storyboard's state
machine):

```
        focus            give (ok)
 empty ───────▶ focused ───────────▶ solved (term replaces hole)
   ▲              │  │
   │ clear        │  └── refine ──▶ spawns sub-holes (focus moves in)
   └──────────────┘  │
                     └── give (ill-typed) ──▶ error (marked, message in panel)
```

## 8. Rendering the same model at L0 / L1 / L2 (D3)

The model above is identical across editor surfaces; only the rendering differs.
This is the point of fixing the model first.

- **L0 — textarea + panels (MVP).** Holes are textual (`{ }ₙ`) in the textarea.
  "Focus" is selecting a hole from the **Holes** panel by number. Refine / give /
  clear are panel buttons that rewrite the textarea text. Goal, Context, and
  Inventory are panels. No inline widgets. Fully sufficient for the loop in
  Sections 3–4, and read-friendly on mobile.
- **L1 — overlay highlight.** As L0, plus syntax highlighting of the term.
  Focus is still panel-driven.
- **L2 — CodeMirror.** Holes are inline widgets the player taps directly; the
  goal/context may appear inline (popover) as well as in the panel; refine
  offers an inline menu; errors render as inline squiggles. Best desktop UX.

A level is played the same way at every level; L0 proves the loop, L2 polishes
it.

## 9. Mobile variant (stacked, read + light-refine)

On a phone the panes stack into one column with a segmented switch. Per D11 the
target is read/browse plus *light* refine, not heavy typing.

```
┌─ comp · Level 3 ───────────────┐
│ [ Goal ] [ Edit ] [ Inv ] [ ⋯ ]│   ← segmented switch
├────────────────────────────────┤
│ ⊢ C                            │
│ ───────────────                │
│ g : B → C   f : A → B   x : A  │
│                                │
│ Tap a lemma to refine the      │
│ focused hole { }₁:             │
│   [ g ]  [ f ]  [ x ]  [ λ ]   │   ← tap-to-refine = the primary action
└────────────────────────────────┘
```

The whole composition example is solvable on a phone with four taps
(λ, g, f, x) and no keyboard. That is the concrete test of "comfortable to
explore" from the mobile discussion (Section 6.4).

## 10. Decisions this storyboard surfaces

Feeding back into the roadmap's open decisions and a few new ones:

- **D1 (hole syntax).** The frames render `{ }ₙ`; the underlying token (`?`,
  `{! !}`, `?name`) is still open and touches the parser.
- **Refine semantics.** Does refine auto-insert the full application spine and
  auto-spawn one sub-hole per missing argument (as drawn)? Recommended: yes,
  following `agda-mode`.
- **Goal/context placement.** Always-visible panel (as drawn) versus on-focus
  popover. Recommended: panel on desktop, panel-as-segment on mobile.
- **Error placement.** Inline squiggle (L2) versus panel-only (L0). The message
  content is the same; only the anchor differs.
- **Check trigger.** Continuous/debounced versus an explicit "Check" action
  (this is D4). The frames assume a check fires when the last hole closes;
  intermediate checking is a tuning choice.
- **Inventory gating.** Which heads appear in the inventory per level (Phase 3
  spec, Phase 5 gating).
- **Lemma discovery scope.** MVP ranks the *level* inventory by goal relevance
  (Section 6.1); whole-library `exact?`-style search is roadmap **D13** (scope,
  gating, perf), out of scope for the MVP.

## 11. What "sign-off" means (the Phase 2 gate)

Phase 2 UI work may start once we agree on:

1. the verb set (Section 6) and the hole state machine (Section 7);
2. that refine/tap-to-refine is the primary action, give is secondary;
3. the three-section context panel for Rzk shapes (Section 5);
4. the L0 rendering of the loop as the MVP target (Section 8);
5. the mobile four-tap solvability target (Section 9).

Surface polish (L2 inline widgets, theming) is explicitly *not* part of the
gate; it follows once the model is agreed.

### Sign-off — 2026-06-16 ✅

The interaction model is **signed off**; Phase 2 UI work is unblocked. The five
items above are agreed:

1. ✅ verb set (§6) + hole state machine (§7);
2. ✅ refine / tap-to-refine primary, give secondary;
3. ✅ three-section context panel (terms / cube vars / topes, §5);
4. ✅ L0 rendering as the MVP target (§8);
5. ✅ mobile four-tap solvability (§9).

> ### Correction, then resolution — refine under extension-type boundaries
>
> A first test (rzk #237/#238) found that **incremental refine did not
> typecheck under extension-type boundaries**: `\ (t , s) → f ?` failed
> (`cannot unify y with f ?`), so refine was briefly downgraded. **rzk #239/#240
> fixed this** (verified 2026-06-16, rebuilt from HEAD): a hole as the argument
> of a shape-restricted function is now accepted and reports its goal as the
> **shape** `(t : 2 | Δ¹ t)`. The full four-tap chain on the first level now
> works end to end: `\ (t , s) → ?` (goal `A [ … ]`) → tap `f` → `\ (t , s) →
> f ?` (goal `(t : 2 | Δ¹ t)`) → give `t` → `\ (t , s) → f t` typechecks.
> So **refine / tap-to-refine is restored as the primary verb**, including the
> four-tap mobile flow.
>
> Semantics to remember: intermediate states with holes are checked **leniently**
> (a hole satisfies any obligation it sits under); the final, hole-free term is
> checked **strictly**. Two things remain open and are *rendering* concerns, not
> model concerns: **binder names** for pair patterns still show as `π₁ x`/`π₂ x`
> (still open upstream), and `id-hom A y s` shows unreduced (wants unfold-on-
> demand). The level walkthrough in
> [`first-hom2-level.md`](./first-hom2-level.md) matches this resolved state.

**Deferred — explicitly NOT part of the model, so they do not block sign-off:**

- **D1 (hole syntax)** — settled in the rzk Phase 1 session; the storyboard
  renders `{ }ₙ` regardless of the underlying token.
- **D4 (check trigger)** — Phase 2 perf tuning.
- **Goal/context placement** — panel on desktop, segment on mobile (default).
- **Error placement** — L0 panel, L2 inline; same message either way.
- **Lemma discovery** — smart inventory only for the MVP (§6.1, D13).

Two concrete Phase 1 work items the level surfaced — **restoring binder names**
(`t , s`, not `π₁ x₁`) and **unfold-on-demand** for symbolic boundaries — are
recorded against §5 and the probe notes; they improve the model's rendering but
do not change the model.
