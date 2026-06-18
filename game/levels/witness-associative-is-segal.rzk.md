---
id: witness-associative-is-segal
inventory:
- 'witness-comp-is-segal : the witness, here applied in arr A'
- 'is-segal-arr A is-segal-A : arr A is Segal (taken as given)'
- 'arr-in-arr-is-segal … w x y f g : the (f,g) composition arrow'
- 'arr-in-arr-is-segal … x y z g h : the (g,h) composition arrow'
statement: hom2 (arr A) f g h …
title: Composing the witnesses
---

The two composition arrows — one for $(f,g)$, one for $(g,h)$ — are composable arrows in $\mathsf{arr}\,A$. Since the arrow type is itself Segal (we take this as given; see the section note), they have a composition witness: a triangle `hom2 (arr A)` whose hypotenuse is their composite. Build it the same way as before, but one level up: apply `witness-comp-is-segal` in the arrow type to the two `arr-in-arr-is-segal` arrows.

**Useful here:**

```rzk
-- the same witness-comp-is-segal, applied with A := arr A and
-- is-segal-A := is-segal-arr A is-segal-A:
is-segal-arr A is-segal-A
  : is-segal (arr A)
arr-in-arr-is-segal A is-segal-A w x y f g
  : hom (arr A) f g          -- the (f,g) composition arrow
arr-in-arr-is-segal A is-segal-A x y z g h
  : hom (arr A) g h          -- the (g,h) composition arrow
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
#def id-arr-in-arr (A : U) (f : arr A)
  : hom (arr A) f f
  := \ t s → f s
#def arr-in-arr-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : hom (arr A) f g
  := \ t s → witness-square-comp-is-segal A is-segal-A x y z f g (t , s)
```

```rzk template
#def witness-associative-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : hom2 (arr A) f g h
      (arr-in-arr-is-segal A is-segal-A w x y f g)
      (arr-in-arr-is-segal A is-segal-A x y z g h)
      (comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h
        (arr-in-arr-is-segal A is-segal-A w x y f g)
        (arr-in-arr-is-segal A is-segal-A x y z g h))
  := ?
```

```rzk solution
#def witness-associative-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : hom2 (arr A) f g h
      (arr-in-arr-is-segal A is-segal-A w x y f g)
      (arr-in-arr-is-segal A is-segal-A x y z g h)
      (comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h
        (arr-in-arr-is-segal A is-segal-A w x y f g)
        (arr-in-arr-is-segal A is-segal-A x y z g h))
  := witness-comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h
       (arr-in-arr-is-segal A is-segal-A w x y f g)
       (arr-in-arr-is-segal A is-segal-A x y z g h)
```

## Conclusion

A triangle of arrows: its two legs are the $(f,g)$ and $(g,h)$ composition arrows, and its hypotenuse is their composite in $\mathsf{arr}\,A$. Uncurried, this triangle of arrows is a prism $\Delta^2\times\Delta^1 \to A$ — and the tetrahedron is hiding inside it.
