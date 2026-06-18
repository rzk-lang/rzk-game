---
id: lut
inventory:
- 'f        : hom A x y'
- 'id-hom   : (A : U) → (x : A) → hom A x x'
- 'λ-intro  : introduce the cube coordinates'
statement: hom2 A x x y (id-hom A x) f f
title: The left-unit triangle
---

Now the mirror image. Given $f : x \to y$, the triangle whose left edge is the identity at $x$ also has $f$ as its hypotenuse — but this time the degenerate copy of $f$ must vary in the other coordinate. Build it.

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
```

```rzk template
#def lut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x x y (id-hom A x) f f
  := \ (t , s) → ?
```

```rzk solution
#def lut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x x y (id-hom A x) f f
  := \ (t , s) → f s
```

## Conclusion

The same edge $f$, reparametrised in the other coordinate. The right-unit triangle used the first coordinate; the left-unit one uses the second.
