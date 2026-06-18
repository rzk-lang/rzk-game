---
hints:
- text: 'The right edge is the identity at $y$, so the whole triangle is just $f$, reparametrised. You only need one coordinate.'
- text: 'Look at the bottom edge of the goal: `↦ f t`. That tells you to apply $f$ to the first coordinate — type `\ (t , s) → f t`.'
  when-goal: '↦ f t'
id: rut
inventory:
- 'f        : hom A x y'
- 'id-hom   : (A : U) → (x : A) → hom A x x'
- 'λ-intro  : introduce the cube coordinates'
statement: hom2 A x y y f (id-hom A y) f
title: The right-unit triangle
---

Now an edge becomes a genuine morphism. The hypotenuse of a `hom2` is the composite of its other two edges. Most triangles need $A$ to be Segal — but some are free. Given $f : x \to y$, the triangle whose right edge is the identity at $y$ has $f$ itself as its hypotenuse. This time the point must vary along the first coordinate. Build it.

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
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → ?
```

```rzk solution
#def rut (A : U) (x y : A) (f : hom A x y)
  : hom2 A x y y f (id-hom A y) f
  := \ (t , s) → f t
```

## Conclusion

The degenerate triangle is just $f$ ignoring the second coordinate. Reusing an existing edge, reparametrised, is the bread and butter of simplicial proofs.
