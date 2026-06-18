# First Rzk-native level — a `hom2` helper

This is story **S1** from [`rzk-probe-notes-1.md`](./rzk-probe-notes-1.md): the
first concrete, *verified* Rzk-native level. It exercises the machinery the
generic composition example in
[`hole-interaction-storyboard-1.md`](./hole-interaction-storyboard-1.md) could
not — extension types and a real cube/tope context — and so validates the
storyboard's interaction model against genuine Rzk content.

Everything below typechecks with rzk 0.8.0. The goals and contexts quoted are
**verbatim rzk output** at a `U`-substituted hole (the probe method from the
notes), so they are exactly what the level UI must render.

It also doubles as a hand-authored prototype of the Phase 3 game-spec fields
(intro / prelude / statement / template / solution / inventory / hints /
conclusion).

## Shared prelude (read-only, pre-checked)

```rzk
#def Δ¹ : 2 → TOPE := \ t → TOP
#def Δ² : (2 × 2) → TOPE := \ (t , s) → s ≤ t

#def hom (A : U) (x y : A) : U
  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]

#def id-hom (A : U) (x : A) : hom A x x
  := \ t → x

#def hom2 (A : U) (x y z : A)
  (f : hom A x y) (g : hom A y z) (h : hom A x z) : U
  := ( (t , s) : Δ²) → A [ s ≡ 0₂ ↦ f t , t ≡ 1₂ ↦ g s , s ≡ t ↦ h s ]
```

The prelude is checked once and reused (roadmap §4.5). The player never edits it;
its definitions populate the **inventory**.

## Level 0 (warm-up) — the identity morphism

A single-hole on-ramp before the `hom2` level. Names are preserved here (single
cube binder), and the tope context is trivial, so it isolates "extension-type
goal with a boundary" with nothing else going on.

- **Intro.** "A morphism `x → y` in `A` is a path along the interval `Δ¹`. The
  simplest one is the *identity*: the morphism from `x` to itself that stays
  put."
- **Statement.** `id (A : U) (x : A) : hom A x x`
- **Template.** `\ t → { }₀`
- **Hole 0 goal/context** (verbatim):
  ```
  ⊢ A [t ≡ 0₂ ↦ x, t ≡ 1₂ ↦ x]
  Terms      t : 2     x : A     A : U
  Topes      ⊤ (unrestricted)
  ```
- **Solution.** `\ t → x`  — tap `x` from the inventory; it satisfies both
  endpoints because they are both `x`.
- **Conclusion.** "The constant path is the identity morphism. Both endpoints
  ask for `x`, so `x` itself fills the hole."

## Level 1 — the right-unit triangle (the first `hom2` level)

The degenerate 2-simplex: reuse an edge, reparametrised. This is the canonical
first non-trivial `hom2`, and it needs no Segal hypothesis.

### Intro

"A `hom2` is a *triangle*: a 2-cell witnessing that its hypotenuse `h` is the
composite `g ∘ f`. Most triangles need `A` to be Segal — but some are free.
Given `f : x → y`, the triangle with right edge the identity at `y` has `f`
itself as its hypotenuse. Build it."

### Statement

```rzk
#def right-unit-triangle (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := { }
```

### Inventory

`f` (the given morphism), `id-hom`, and **λ-intro**. (`hom`, `hom2`, `Δ¹`, `Δ²`
are visible but not needed.)

### Hole-by-hole walkthrough (verbatim goals)

This is the storyboard loop (frames F1–F6) on real content.

1. **F1 — open.** Goal is the whole triangle type:
   ```
   ⊢ hom2 A x y y f (id-hom A y) f
   ```
2. **F2 — λ-intro** (the goal is a function from `Δ²`). Template becomes
   `\ (t , s) → { }₀`. The hole's goal and context (verbatim):
   ```
   ⊢ A [ s ≡ 0₂ ↦ f t ,  t ≡ 1₂ ↦ id-hom A y s ,  s ≡ t ↦ f s ]
   Terms      f : hom A x y     y : A     x : A     A : U
   Cube vars  (t , s) : 2 × 2
   Topes      Δ² (t , s)            -- i.e. s ≤ t
   ```
   The three boundary conditions are the heart of the goal panel: on the bottom
   edge the term must be `f t`, on the right edge `id-hom A y s` (which is `y`),
   on the hypotenuse `f s`.
3. **Refine with `f`.** Tapping `f` rewrites the hole to `f ?`; the new hole's
   goal is the interval point `f` needs (verified, rzk #239/#240):
   ```
   ⊢ (t : 2 | Δ¹ t)        -- a point of the directed interval (shape goal)
   ```
   This previously failed (`cannot unify y with f ?`); #239/#240 fixed it, so a
   hole as a shape-restricted function's argument is now accepted and reports
   the shape as its goal. Intermediate states with holes check **leniently**.
4. **Give `t`.** The first coordinate is the point that makes all three
   boundaries agree. Template becomes `\ (t , s) → f t`.
5. **Solved.** `\ (t , s) → f t` has no holes and typechecks **strictly** →
   **level complete.** Four interactions (λ-intro, refine `f`, give `t`, done),
   no free typing — the four-tap target met.

### Reference solution (verified)

```rzk
#def right-unit-triangle (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → f t
```

`rzk typecheck` → *Everything is ok!*

### Hints (goal-matched, Phase 5)

- at hole 0 (goal `hom2 …`): "A `hom2` is a map out of the triangle `Δ²`.
  Introduce its two coordinates with λ."
- at hole 0 (goal `A [ … ]`): "You need a point of `A` on the triangle. One of
  your edges already provides points of `A` — refine with `f`."
- at hole 1 (goal `2`): "`f` wants an interval point. The first coordinate `t`
  is the one that lands on `f`'s endpoints."

### Conclusion

"The degenerate triangle is just `f` ignoring the second coordinate. Reusing an
existing edge — reparametrised — is the bread and butter of simplicial proofs."

## What this validates and surfaces

Validates (verified against rzk's real holes API, #237–#240):

- The **goal/context query works on real content**: `typecheckModulesWithHoles`
  reports each hole's goal and **local-only** context, with the **three-section
  split** (terms / cube vars / topes) and the extension-type boundary — exactly
  what the panel needs. Both levels confirmed.
- **Goals stay symbolic** and readable; the boundary conditions are the useful
  part to display.
- **Incremental refine works under extension-type boundaries** (rzk #239/#240):
  `\ (t , s) → f ?` is accepted with goal `(t : 2 | Δ¹ t)`, so the four-tap
  chain (λ-intro → refine `f` → give `t`) holds end to end. (A first test on
  #237/#238 found this failing; #239/#240 fixed it.) Intermediate states with
  holes check leniently; the hole-free term checks strictly.
- The **give-a-complete-term → check** loop also works, as the always-available
  fallback to refine.

Surfaces (concrete Phase 1 work items, from real output here):

- **Binder names are lost.** rzk shows the `hom2` hole's context as `x₁ : 2 × 2`
  with `π₁ x₁` / `π₂ x₁`, not the `t , s` the player wrote. The UI must restore
  the binder names (roadmap §4, D1-adjacent) or this level reads badly.
- **`id-hom A y s` is shown unreduced** in the boundary rather than as `y`. This
  is the "symbolic by default" behaviour; an **unfold-on-demand** affordance
  (probe notes §5) would let the player see it equals `y`.
- The warm-up's trivial tope (`⊤`) vs. the `hom2` level's `Δ²` is a natural
  difficulty ramp the spec format should make easy to author.

## Status

Both levels typecheck (rzk 0.8.0). This is the first content artifact and the
concrete validation backing the storyboard sign-off
([`hole-interaction-storyboard-1.md`](./hole-interaction-storyboard-1.md) §11).
