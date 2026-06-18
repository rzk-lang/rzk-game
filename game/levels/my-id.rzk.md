---
id: my-id
inventory:
- 'x        : A'
- 'id-hom   : (A : U) → (x : A) → hom A x x'
- 'λ-intro  : introduce the interval coordinate'
statement: hom A x x
title: The identity morphism
---

A morphism $x \to y$ in $A$ is a path along the directed interval $\Delta^1$. The simplest one is the identity: the morphism from $x$ to itself that just stays put. Both endpoints of the path are $x$, so a constant path will do. Build it.

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
#def my-id (A : U) (x : A)
  : hom A x x
  := ?
```

```rzk solution
#def my-id (A : U) (x : A)
  : hom A x x
  := \ t → x
```

## Conclusion

The constant path is the identity morphism. Both endpoints ask for $x$, so $x$ itself fills the hole — no need to move along the interval at all.
