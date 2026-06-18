# Rzk Probe Notes — towards the hole-interaction design

These are hands-on notes from running `rzk` on partial, Rzk-specific examples,
to learn what the typechecker *already* exposes at a "hole" and what the game
engine will need from it. They feed the hole-interaction storyboard
([`hole-interaction-storyboard-1.md`](./hole-interaction-storyboard-1.md)) and
Phase 1 of [`roadmap-1.md`](./roadmap-1.md).

Rzk has no holes yet, so following the suggestion we substitute `U` for the
missing subterm. Because `U` almost never has the expected type, the resulting
type error prints the **expected type (the goal)**, the **context**, and the
**local tope context** at that position. That is exactly the goal/context data a
hole UI needs, so the error text is a faithful preview of what Phase 1 must
expose structurally.

- Tool: `rzk` v0.8.0 (prebuilt macOS-ARM64 release binary).
- Method: minimal self-contained `.rzk` files with one `U`-hole; plus probes
  against the real `rzk-lang/sHoTT` formalisation.
- All snippets below are trimmed verbatim `rzk typecheck` output.

## 1. What rzk already exposes at a hole

A trivial probe (`x : A ⊢ ? : A`, body `:= U`) already prints three things:

```
Definitions in context:
  x : A
  A : U
...
when unifying expected type
  A
with actual type
  U
...
Local tope context is unrestricted (⊤).
```

So the typechecker already computes, and pretty-prints, the **goal** (`A`), the
**context**, and the **local tope context** (`⊤` here). The information exists;
Phase 1 is largely about returning it as structured data instead of as a
formatted error string, and querying it at a real hole rather than at a forced
type mismatch.

## 2. Extension-type goals carry their boundary obligations

A `hom2` filler with the body replaced by `U`:

```rzk
#def hom2 ( A : U) ( x y z : A) ( f : hom A x y) ( g : hom A y z) ( h : hom A x z) : U
  := ( (t₁ , t₂) : Δ²) → A [ t₂ ≡ 0₂ ↦ f t₁ , t₁ ≡ 1₂ ↦ g t₂ , t₂ ≡ t₁ ↦ h t₂ ]
#def my-hom2-filler (…same params…) : hom2 A x y z f g h
  := \ (t₁ , t₂) → U
```

The goal printed at the hole is the **full extension type with its boundary**,
then narrowed to the underlying type:

```
when typechecking U against type
  A [π₂ x₁ ≡ 0₂ ↦ f (π₁ x₁), π₁ x₁ ≡ 1₂ ↦ g (π₂ x₁), π₂ x₁ ≡ π₁ x₁ ↦ h (π₂ x₁)]
when typechecking U against type
  A
```

Design consequence: the goal panel should show *both* — the underlying type
`A` and the boundary conditions the term must satisfy (`when t₂ ≡ 0₂, it must
equal f t₁`, …). The boundary is the part a player most needs spelled out.

## 3. Tope contexts are real, and the solver works

- **Clean single tope.** A hole on the restricted shape `((t,s) : 2×2 | t ≤ s)`
  prints `Local tope context: π₁ x₁ ≤ π₂ x₁`. The goal is `A` under that
  assumption.
- **Nested cube quantifiers (Fubini-flavoured).** `(t : 2) → (s : 2 | t ≤ s) → A`
  with an inner `U` prints context `s : 2, t : 2, A : U` and tope `t ≤ s`. Two
  cube variables and an accumulated tope, exactly as expected.
- **recOR coherence.** `recOR (t ≤ s ↦ U , s ≤ t ↦ a)` over `2 × 2` does not
  complain that the topes fail to cover — the solver accepts `t ≤ s ∨ s ≤ t = ⊤`
  by linearity. Instead it runs a **coherence check** on the overlap, printing
  the tope context as the *conjunction* `π₁ x₁ ≤ π₂ x₁ ∧ π₂ x₁ ≤ π₁ x₁` (the
  diagonal) and asking the two branches to agree there.
- The real sHoTT code pushes this much further: a single `recOR` with **six
  branches** and conjunction topes (`s1 ≤ t1 ∧ t2 ≤ s2 ↦ …`, …) appears in the
  pushout-product machinery. Each pair of branches generates an overlap
  coherence obligation.

Design consequences:

- The context panel needs **three sections** for Rzk: term context, cube
  variables, and tope assumptions (Storyboard §5). All three are available.
- `recOR` is not just "choose a branch": filling one branch creates **coherence
  obligations** against the others on their overlaps. The game must surface these
  as first-class sub-goals, not hide them. A `recOR` hole effectively spawns: one
  hole per branch, plus one coherence check per overlapping pair.

## 4. Binder names survive simple binders but are lost under pair patterns

With simple binders `\ t → \ s → …`, the context shows `t : 2, s : 2` — the
player's names. With a **pair pattern** `\ (t₁ , t₂) → …`, rzk desugars to a
single `x₁ : 2 × 2` and rewrites everything through `π₁ x₁` / `π₂ x₁`:

```
Definitions in context:
  x₁ : 2 × 2          ← was written (t₁ , t₂)
...
  A [π₂ x₁ ≡ 0₂ ↦ f (π₁ x₁), …]
```

This is a real UX hazard: the player writes `(t₁ , t₂)` but the goal and context
talk about `π₁ x₁`, `π₂ x₁`. Since simplicial work is *full* of pair and triple
patterns over `2 × 2` and `2 × 2 × 2`, the game should either restore the
user's binder names for display, or push a fix upstream so rzk keeps them. Flag
for Phase 1 / decision D1.

## 5. The large-context problem is severe (the main UX finding)

A hole at the **real associativity goal** for Segal types (`assoc-hole`,
appended after the full sHoTT prelude) gives a genuinely useful goal:

```
when unifying expected type
  comp-is-segal A is-segal-A w y z (comp-is-segal A is-segal-A w x y f g) h
    =_{ (t : 2 | Δ¹ t) → A [t ≡ 0₂ ↦ w, t ≡ 1₂ ↦ z] }
  comp-is-segal A is-segal-A w x z f (comp-is-segal A is-segal-A x y z g h)
```

Two good things: the goal is **symbolic** (the `comp-is-segal` composites are
*not* force-unfolded into their contractibility centres), and the path type
shows its endpoints. This is readable and player-friendly.

The bad thing: the `Definitions in context` block is **896 lines long**. The
genuinely relevant local context is the first nine entries:

```
h : hom A y z
g : hom A x y
f : hom A w x
z : A   y : A   x : A   w : A
is-segal-A : is-segal A
A : U
```

Everything after that is the *entire global environment* — every prior
definition with its full type, including monsters such as
`is-weak-inner-anodyne-pushout-product-right-is-weak-inner-anodyne : (I : CUBE) → …`
spanning a full screen each.

Design consequence (the most important one): the goal/context query **must
separate local hypotheses from the global environment**. The level UI shows the
locals (here, nine lines); the globals belong in a separate, searchable,
collapsed **inventory**, gated per level (Storyboard §6, roadmap Phase 3/5).
Dumping the environment, as the error formatter does, is unusable in a game.

## 6. Performance: incremental checking is mandatory, not optional

Timings on this machine (`rzk typecheck` over the sHoTT `rzk.yaml`, 1371
definitions, 25 files):

- cold full check: **~65 s**;
- a run after appending one definition: **~20 s** (variance; partly OS file
  cache, partly stopping at the first error);
- **no persistent on-disk cache** is produced (`.rzk*` is absent), so the CLI
  recomputes from scratch each run. Caching today lives only inside the LSP
  (per the changelog).

Consequence: re-checking the whole prelude on every keystroke is impossible —
even a single heavy file is seconds. The engine must use an **in-process
"check-in-context"** entry point (roadmap §4.5): typecheck the level's prelude
once, keep the resulting environment, and check only the player's editable
region against it. This is now a hard requirement, with a number attached.

## 7. Rzk-specific stories for the storyboard

Each story is a small, real example that exercises a distinct Rzk feature and
teaches the engine something concrete.

- **S1 — `hom2` filler (extension types + Δ² topes).** Fill a square with a
  given boundary. Teaches: extension-type goals with boundary obligations (§2);
  the cube/tope sections of the context (§3). Hardest part for the UI: showing
  the three boundary conditions legibly.
- **S2 — `unfolding-square` via `recOR` (tope disjunction + coherence).** Define
  a map on `2 × 2` by `t ≤ s` / `s ≤ t`. Teaches: a `recOR` hole spawns a hole
  per branch *plus* a coherence sub-goal on the diagonal (§3). This is the story
  that justifies modelling coherence as first-class.
- **S3 — Fubini for extension types (reordering cube quantifiers).** Two cube
  variables with a dependent tope. Teaches: contexts accumulate several cube
  variables and topes; reordering is definitional. Good for explaining the
  cube/tope context to players (§3).
- **S4 — associativity for Segal types (large context, symbolic goal).** The
  real research-level goal. Teaches: goals stay symbolic and readable (§5), but
  the context must be filtered to locals (§5) and the prelude must be cached
  (§6). This is the stress test that validates the whole approach end to end.

A `hom2` helper (S1) is the right *first* Rzk-native level: small, self-contained,
and it already forces the extension-type and tope-context machinery. S4 is the
capstone, and a natural waypoint on the way to the ∞-Yoneda game.

## 8. Requirements this surfaces (feeding Phase 1 and the storyboard)

1. **Structured goal/context query** returning four parts: goal (symbolic, with
   any extension-type boundary), local term context, cube variables, tope
   assumptions — all of which rzk already computes.
2. **Local/global separation.** Never show the global environment inline; route
   it to a searchable, gated inventory. Without this the UI is unusable on real
   formalisations.
3. **Binder-name preservation** through pair/tuple patterns, or name recovery in
   the UI (§4). Ties to D1.
4. **`recOR` as a structured construct**: one hole per branch plus per-overlap
   coherence sub-goals (§3, §7-S2).
5. **In-process incremental check-in-context** with a cached prelude environment
   (§6); per-keystroke whole-prelude rechecking is ruled out by the 65 s number.
6. **Keep goals symbolic** by default — do not force-unfold definitions; offer
   unfolding on demand only (§5).

## 9. Open questions / risks uncovered

- **Tope-solver cost** on large disjunctions/conjunctions (the six-branch
  `recOR`, pushout products): not yet measured in isolation. Worth a focused
  timing probe before committing to live checking on shape-heavy levels.
- **Normalisation cost** when a goal *is* unfolded (e.g. if a level needs the
  player to see inside `comp-is-segal`). Symbolic-by-default avoids it, but
  "unfold" actions could be slow.
- **Name recovery** (§4) may be fiddly if rzk has already discarded the names by
  the time we query; an upstream fix may be cleaner than reconstructing them.
- **Memory** of holding the full sHoTT environment in a WASM module (ties to the
  Phase 0D bundle/memory spike).
