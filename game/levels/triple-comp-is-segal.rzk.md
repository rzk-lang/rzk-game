---
id: triple-comp-is-segal
inventory:
- 'tetrahedron-associative-is-segal : the tetrahedron Δ³ → A'
- '((t , t) , t) : the fully degenerate point, the main diagonal'
statement: hom A w z
title: The triple composite
---

One arrow is left to read off. The tetrahedron's main diagonal runs from its first vertex $w$ to its last vertex $z$, traced by the fully degenerate point $((t,t),t)$. That diagonal *is* the composite $h\circ g\circ f$ of all three arrows. Introduce the interval coordinate and restrict the tetrahedron to its main diagonal.

**Useful here:**

```rzk
tetrahedron-associative-is-segal A is-segal-A w x y z f g h
  : Δ³ → A
-- the main diagonal is the point  ((t , t) , t)
```

```rzk prelude
#lang rzk-1
#def Δ¹ : 2 → TOPE := \ t → TOP
#def Δ² : (2 × 2) → TOPE := \ (t , s) → s ≤ t
#def hom (A : U) (x y : A) : U
  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]
#def id-hom (A : U) (x : A) : hom A x x := \ t → x
#def hom2 (A : U) (x y z : A)
  (f : hom A x y) (g : hom A y z) (h : hom A x z) : U
  := ( (t , s) : Δ²) → A [ s ≡ 0₂ ↦ f t , t ≡ 1₂ ↦ g s , s ≡ t ↦ h s ]
#def is-contr (A : U) : U
  := Σ (a : A) , (x : A) → a =_{ A } x
#def is-segal (A : U) : U
  := (x : A) → (y : A) → (z : A) → (f : hom A x y) → (g : hom A y z)
   → is-contr (Σ (h : hom A x z) , hom2 A x y z f g h)
#def Δ³ : (2 × 2 × 2) → TOPE
  := \ ((t1 , t2) , t3) → t3 ≤ t2 ∧ t2 ≤ t1
#def Δ¹×Δ¹ : (2 × 2) → TOPE := \ (t , s) → TOP ∧ TOP
#def comp-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z) : hom A x z
  := first (first (is-segal-A x y z f g))
#def witness-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)
  := second (first (is-segal-A x y z f g))
#def arr (A : U) : U := Δ¹ → A
#postulate is-segal-arr
  : (A : U) → (is-segal-A : is-segal A) → is-segal (arr A)
#def unfolding-square (A : U) (triangle : Δ² → A)
  : Δ¹×Δ¹ → A
  := \ (t , s) → recOR ( t ≤ s ↦ triangle (s , t) , s ≤ t ↦ triangle (t , s) )
#def witness-square-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : Δ¹×Δ¹ → A
  := unfolding-square A (witness-comp-is-segal A is-segal-A x y z f g)
#def id-arr-in-arr (A : U) (f : arr A)
  : hom (arr A) f f
  := \ t s → f s
#def arr-in-arr-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom (arr A) f g
  := \ t s → witness-square-comp-is-segal A is-segal-A x y z f g (t , s)
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
#def tetrahedron-associative-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : Δ³ → A
  := \ ((t , s) , r) → witness-associative-is-segal A is-segal-A w x y z f g h (t , r) s
```

```rzk template
#def triple-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : hom A w z
  := \ t → tetrahedron-associative-is-segal A is-segal-A w x y z f g h (?)
```

```rzk solution
#def triple-comp-is-segal
  (A : U) (is-segal-A : is-segal A) (w x y z : A)
  (f : hom A w x) (g : hom A x y) (h : hom A y z)
  : hom A w z
  := \ t → tetrahedron-associative-is-segal A is-segal-A w x y z f g h ((t , t) , t)
```

## Conclusion

The triple composite is the tetrahedron's main diagonal. Its two faces exhibit it both as $(h\circ g)\circ f$ and as $h\circ(g\circ f)$; since a Segal type's composites are unique, the two bracketings agree. That is associativity — see the sHoTT chapter for the final equality.
