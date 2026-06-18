---
id: map-point
inventory:
- 'g        : A → B'
- 'x        : A'
- 'λ-intro  : introduce the interval coordinate'
statement: hom B (g x) (g x)
title: A function on a point
---

Now we leave a single type and bring in a function $g : A \to B$. A function sends each point of $A$ to a point of $B$. The identity morphism at a point just stays put, and $g$ carries it along. The application `g (?)` is already in place; fill in the point of $A$ whose image is the identity's endpoint.

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
#def map-point (A B : U) (g : A → B) (x : A)
  : hom B (g x) (g x)
  := \ t → g (?)
```

```rzk solution
#def map-point (A B : U) (g : A → B) (x : A)
  : hom B (g x) (g x)
  := \ t → g (x)
```

## Conclusion

A function sends a point to a point, and the constant path at `g x` is its identity. The next level carries a whole morphism along, not just a point.
