---
id: unfolding-square
inventory:
- 'triangle : Δ² → A'
- 'recOR    : split on a pair of covering topes (here t ≤ s / s ≤ t)'
- '(s , t)  : the swapped coordinate, reflecting across the diagonal'
statement: Δ¹×Δ¹ → A
title: Unfolding a triangle
---

The associativity proof lives in the arrow type, and there the cells are *squares* $\Delta^1\times\Delta^1 \to A$, not triangles. A triangle fills only the lower half $s \le t$ of the square. To fill the whole square, reflect the triangle across the diagonal: on the upper half $t \le s$ reuse the same triangle with its two coordinates *swapped*. The `recOR` splits the square along the diagonal; fill each branch. No Segal hypothesis is needed — this is reparametrisation.

**Useful here:**

```rzk
triangle : Δ² → A           -- the lower-half triangle to unfold
-- recOR glues two branches along covering topes:
--   recOR ( t ≤ s ↦ … , s ≤ t ↦ … ) : A
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
```

```rzk template
#def unfolding-square (A : U) (triangle : Δ² → A)
  : Δ¹×Δ¹ → A
  := \ (t , s) → recOR ( t ≤ s ↦ ? , s ≤ t ↦ ? )
```

```rzk solution
#def unfolding-square (A : U) (triangle : Δ² → A)
  : Δ¹×Δ¹ → A
  := \ (t , s) → recOR ( t ≤ s ↦ triangle (s , t) , s ≤ t ↦ triangle (t , s) )
```

## Conclusion

A square is two copies of one triangle glued along the diagonal — the original on $s \le t$ and its reflection on $t \le s$. The two branches agree on the diagonal $s \equiv t$, where both read $\mathsf{triangle}\,(t,t)$, so `recOR` is well-defined. We can now unfold any triangle into a square.
