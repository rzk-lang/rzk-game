---
id: compose-witness
inventory:
- 'is-segal-A : is-segal A'
- 'first (is-segal-A x y z f g) : (composite , witness) pair'
- 'first      : the composite arrow (the pair''s first component)'
- 'second     : the witness triangle (the pair''s second component)'
statement: hom2 A x y z f g (first (first (is-segal-A x y z f g)))
title: The composition witness
---

Building the composite arrow was only half of the centre of contraction. Its second component is the triangle witnessing that the arrow really is the composite of $f$ and $g$. The goal's diagonal is the composite you built last time. Take the second projection of the centre to recover its witness.

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
#def compose-witness
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom2 A x y z f g (first (first (is-segal-A x y z f g)))
  := ?
```

```rzk solution
#def compose-witness
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom2 A x y z f g (first (first (is-segal-A x y z f g)))
  := second (first (is-segal-A x y z f g))
```

## Conclusion

The composite and its witnessing triangle are the two halves of one centre of contraction. Together they say: in a Segal type, composition exists and the triangle proving it is there for free.
