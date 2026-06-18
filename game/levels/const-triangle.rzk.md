---
id: const-triangle
inventory:
- 'x        : A'
- 'id-hom   : (A : U) → (x : A) → hom A x x'
- 'λ-intro  : introduce the two cube coordinates'
statement: hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)
title: The constant triangle
---

A `hom2` is a triangle: a map out of the 2-simplex $\Delta^2$. The simplest one is constant — every edge is the identity at a single point $x$. Introduce the two coordinates, then find the point of $A$ that sits on all three edges.

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

## Conclusion

Every boundary asked for $x$, so the constant function fills the whole triangle. In the next levels one edge becomes a genuine morphism, and the point has to vary along a coordinate.
