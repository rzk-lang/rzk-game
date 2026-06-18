---
id: compose
inventory:
- 'is-segal-A : is-segal A'
- 'is-segal-A x y z f g : is-contr (Σ (h : hom A x z) , hom2 …)'
- 'first      : the centre of a contractible type / first of a pair'
- 'second     : the second component of a pair'
statement: hom A x z
title: Composition
---

Every level so far was free: no hypothesis was needed. Genuine composition is different. A Segal type is one where each composable pair of arrows has a unique filler triangle, so `is-segal-A x y z f g` proves that the type of pairs `(h , triangle)` is contractible. Its centre, `first (is-segal-A x y z f g)`, is the pair `(composite , witness)`. Take the first projection of that pair to get the composite arrow. Type the term and press Check.

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
```

```rzk template
#def compose
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom A x z
  := ?
```

```rzk solution
#def compose
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom A x z
  := first (first (is-segal-A x y z f g))
```

## Conclusion

The composite $g \circ f$ is the arrow at the centre of the contractible space of fillers. The Segal condition is exactly what makes this arrow exist and be well-defined. Next: recover the triangle that witnesses it.
