---
id: witness-square-comp-is-segal
inventory:
- 'unfolding-square    : (A : U) → (Δ² → A) → Δ¹×Δ¹ → A'
- 'witness-comp-is-segal : the composition witness triangle'
- 'is-segal-A x y z f g  : the centre of contraction for f, g'
statement: Δ¹×Δ¹ → A
title: The composition square
---

Now use the unfolder. The Segal structure gives a *triangle* witnessing that the composite of $f$ and $g$ really is their composite. Unfold that triangle into a square, so it can later be read as an arrow in the arrow type. Apply `unfolding-square` to the composition witness.

**Useful here:**

```rzk
unfolding-square
  : (A : U) → (Δ² → A) → Δ¹×Δ¹ → A
witness-comp-is-segal
  : (A : U) → (is-segal-A : is-segal A) → (x y z : A)
  → (f : hom A x y) → (g : hom A y z)
  → hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)
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
```

```rzk template
#def witness-square-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : Δ¹×Δ¹ → A
  := unfolding-square A (?)
```

```rzk solution
#def witness-square-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : Δ¹×Δ¹ → A
  := unfolding-square A (witness-comp-is-segal A is-segal-A x y z f g)
```

## Conclusion

The composition witness is now a square. Its left and right edges are $f$ and $g$; its other two edges are the composite. Seen sideways, this square is an arrow whose endpoints are $f$ and $g$. The arrow type makes that precise — and the next two levels put it to work.
