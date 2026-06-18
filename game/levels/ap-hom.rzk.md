---
id: ap-hom
inventory:
- 'g        : A → B'
- 'f        : hom A x y'
- 'λ-intro  : introduce the interval coordinate'
statement: hom B (g x) (g y)
title: A function on a morphism
---

Functions act on morphisms too. A morphism $f : x \to y$ in $A$ is a path; applying $g$ at each moment of that path gives a morphism $g\,x \to g\,y$ in $B$. The function $g$ is already in place; fill in the point of $A$ that $f$ traces out as the coordinate moves. Refine with `f`, then give the coordinate.

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
#def ap-hom (A B : U) (g : A → B) (x y : A) (f : hom A x y)
  : hom B (g x) (g y)
  := \ t → g (?)
```

```rzk solution
#def ap-hom (A B : U) (g : A → B) (x y : A) (f : hom A x y)
  : hom B (g x) (g y)
  := \ t → g (f t)
```

## Conclusion

Applying $g$ along the path $f$ gives a morphism between the images. This is functoriality: a function carries morphisms to morphisms, here `g (f t)` tracing $g$'s image of $f$.
