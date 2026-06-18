---
id: id-arr-in-arr
inventory:
- 'f        : arr A   (an arrow of A)'
- 'f s      : A       the arrow f at its own coordinate s'
- 'λ-intro  : two coordinates — t between arrows, s along the arrow'
statement: hom (arr A) f f
title: An identity between arrows
---

A new kind of target: the **arrow type** $\mathsf{arr}\,A = \Delta^1 \to A$, whose points are the arrows of $A$. A morphism *between* two arrows, $\mathsf{hom}\,(\mathsf{arr}\,A)\,f\,g$, is a path of arrows, and it takes two coordinates — the first, $t$, slides between arrows; the second, $s$, runs along the arrow sitting there. Start with the simplest one: the **identity** at $f$, the constant path that never leaves $f$. Ignore the path coordinate $t$ and return $f$ at its own coordinate $s$.

**Useful here:**

```rzk
arr A := Δ¹ → A             -- a point of arr A is an arrow
f : arr A                   -- so f s : A for a coordinate s
```

```rzk prelude
#lang rzk-1
#def Δ¹
  : 2 → TOPE
  := \ t → TOP
#def Δ²
  : ( 2 × 2) → TOPE
  := \ (t , s) → s ≤ t
#def hom (A : U) (x y : A)
  : U
  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]
#def id-hom (A : U) (x : A)
  : hom A x x
  := \ t → x
#def hom2 (A : U) (x y z : A)
  ( f : hom A x y) (g : hom A y z) (h : hom A x z)
  : U
  := ((t , s) : Δ²) → A [ s ≡ 0₂ ↦ f t , t ≡ 1₂ ↦ g s , s ≡ t ↦ h s ]
#def is-contr (A : U)
  : U
  := Σ (a : A) , (x : A) → a =_{ A } x
#def is-segal (A : U)
  : U
  := (x : A) → (y : A) → (z : A) → (f : hom A x y) → (g : hom A y z)
   → is-contr (Σ (h : hom A x z) , hom2 A x y z f g h)
#def Δ³
  : ( 2 × 2 × 2) → TOPE
  := \ ((t1 , t2) , t3) → t3 ≤ t2 ∧ t2 ≤ t1
#def Δ¹×Δ¹
  : ( 2 × 2) → TOPE
  := \ (t , s) → TOP ∧ TOP
#def comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : hom A x z
  := first (first (is-segal-A x y z f g))
#def witness-comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)
  := second (first (is-segal-A x y z f g))
#def arr (A : U)
  : U
  := Δ¹ → A
#postulate is-segal-arr
  : ( A : U) → (is-segal-A : is-segal A) → is-segal (arr A)
#def unfolding-square (A : U) (triangle : Δ² → A)
  : Δ¹×Δ¹ → A
  := \ (t , s) → recOR (t ≤ s ↦ triangle (s , t) , s ≤ t ↦ triangle (t , s))
#def witness-square-comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : Δ¹×Δ¹ → A
  := unfolding-square A (witness-comp-is-segal A is-segal-A x y z f g)
```

```rzk template
#def id-arr-in-arr (A : U) (f : arr A)
  : hom (arr A) f f
  := \ t s → ?
```

```rzk solution
#def id-arr-in-arr (A : U) (f : arr A)
  : hom (arr A) f f
  := \ t s → f s
```

## Conclusion

The identity between arrows ignores the path coordinate $t$ and hands back the arrow $f$ unchanged. The two coordinates have clear roles: $t$ moves between arrows, $s$ runs along the arrow at hand. In the next level $t$ genuinely moves.
