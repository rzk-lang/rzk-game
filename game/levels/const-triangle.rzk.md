# The constant triangle

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
#def const-triangle (A : U) (x : A)
  : hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)
  := ?
```

```rzk solution
#def const-triangle (A : U) (x : A)
  : hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)
  := \ (t , s) → x
```
