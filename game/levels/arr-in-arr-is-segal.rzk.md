---
id: arr-in-arr-is-segal
inventory:
- 'witness-square-comp-is-segal : the composition square Δ¹×Δ¹ → A'
- 'f , g    : the endpoints, now points of arr A'
- 'λ-intro  : t slides from f to g; s runs along the arrow at (t , s)'
statement: hom (arr A) f g
title: An arrow between arrows
---

Now the real thing. The warm-up built the *constant* path of arrows; here the arrow genuinely moves. Use the composition square: as the first coordinate $t$ slides from $0$ to $1$, the arrow slides from $f$ to $g$. Curry it exactly as before — introduce $t$ and $s$, then read off the square at $(t , s)$. This is the pivot of the whole proof: composition in $A$ becomes an arrow in $\mathsf{arr}\,A$.

**Useful here:**

```rzk
witness-square-comp-is-segal
  : (A : U) → (is-segal-A : is-segal A) → (x y z : A)
  → (f : hom A x y) → (g : hom A y z) → Δ¹×Δ¹ → A
-- hom (arr A) f g is a path of arrows from f to g
```

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
#def Δ³
  : ( 2 × 2 × 2) → TOPE
  := \ ((t1 , t2) , t3) → t3 ≤ t2 ∧ t2 ≤ t1
#def Δ¹×Δ¹
  : ( 2 × 2) → TOPE
  := \ (t , s) → TOP ∧ TOP
#def comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : hom A x z
  := first (first (is-segal-A x y z f g))
#def witness-comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)
  := second (first (is-segal-A x y z f g))
#def arr (A : U)
  : U
  := Δ¹ → A
#postulate is-segal-arr
  : ( A : U) → (is-segal-A : is-segal A) → is-segal (arr A)
#def unfolding-square (A : U) (triangle : Δ² → A)
  : Δ¹×Δ¹ → A
  := \ (t , s) → recOR (t ≤ s ↦ triangle (s , t) , s ≤ t ↦ triangle (t , s))
#def witness-square-comp-is-segal
  ( A : U) (is-segal-A : is-segal A) (x y z : A)
  ( f : hom A x y) (g : hom A y z)
  : Δ¹×Δ¹ → A
  := unfolding-square A (witness-comp-is-segal A is-segal-A x y z f g)
#def id-arr-in-arr (A : U) (f : arr A)
  : hom (arr A) f f
  := \ t s → f s
```

```rzk template
#def arr-in-arr-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom (arr A) f g
  := \ t s → ?
```

```rzk solution
#def arr-in-arr-is-segal
  (A : U) (is-segal-A : is-segal A) (x y z : A)
  (f : hom A x y) (g : hom A y z)
  : hom (arr A) f g
  := \ t s → witness-square-comp-is-segal A is-segal-A x y z f g (t , s)
```

## Conclusion

Composition in $A$ is now an arrow in $\mathsf{arr}\,A$. Because the arrow type of a Segal type is again Segal, these arrows can themselves be composed — and that second-order composition is what makes associativity fall out.
