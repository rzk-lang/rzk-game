# The left-unit triangle

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
