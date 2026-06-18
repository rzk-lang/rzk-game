---
id: tetrahedron-associative-is-segal
inventory:
- 'witness-associative-is-segal : the prism Δ²×Δ¹ → A, as a curried witness'
- '((t , s) , r) : the Δ³ coordinates'
- '(t , r) s     : the middle-simplex regrouping'
statement: Δ³ → A
title: The associativity tetrahedron
---

The triangle of arrows, uncurried, is a prism $\Delta^2\times\Delta^1 \to A$. The $3$-simplex $\Delta^3$ embeds in that prism by the *middle-simplex* map $((t,s),r) \mapsto ((t,r),s)$ — swap the inner coordinate $s$ with the outer one $r$. Introduce the three coordinates of $\Delta^3$, then apply the witness with them regrouped this way.

**Useful here:**

```rzk
witness-associative-is-segal A is-segal-A w x y z f g h
  : hom2 (arr A) f g h … …   -- a curried prism, applied as (t , r) s
-- middle-simplex map:  ((t , s) , r)  ↦  (t , r) s
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
#def witness-associative-is-segal
  ( A : U) (is-segal-A : is-segal A) (w x y z : A)
  ( f : hom A w x) (g : hom A x y) (h : hom A y z)
  : hom2 (arr A) f g h
      ( arr-in-arr-is-segal A is-segal-A w x y f g)
      ( arr-in-arr-is-segal A is-segal-A x y z g h)
      ( comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h
        ( arr-in-arr-is-segal A is-segal-A w x y f g)
        ( arr-in-arr-is-segal A is-segal-A x y z g h))
  := witness-comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h
       ( arr-in-arr-is-segal A is-segal-A w x y f g)
       ( arr-in-arr-is-segal A is-segal-A x y z g h)
```

```rzk template
#def tetrahedron-associative-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : Δ³ → A
  := \ ((t , s) , r) → ?
```

```rzk solution
#def tetrahedron-associative-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : Δ³ → A
  := \ ((t , s) , r) → witness-associative-is-segal A is-segal-A w x y z f g h (t , r) s
```

## Conclusion

The middle-simplex map carries $\Delta^3$ into the prism, extracting a genuine tetrahedron. Its four faces are the three pairwise composites and the triple composite; reading off its edges gives the two bracketings of $h\circ g\circ f$.
