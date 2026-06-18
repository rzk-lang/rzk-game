# The right-unit triangle

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
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → ?
```

```rzk solution
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → f t
```
