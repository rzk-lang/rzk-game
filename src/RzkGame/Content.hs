{-# LANGUAGE OverloadedStrings #-}

-- | Hand-authored level content. (Later this comes from a game spec; see the
-- roadmap's Phase 3.) For now, the first Rzk-native level: a @hom2@ filler.
module RzkGame.Content
  ( gameLevels
  , idMorphismLevel
  , constTriangleLevel
  , hom2Level
  , homLeftUnitLevel
  , mapPointLevel
  , apHomLevel
  , composeLevel
  , composeWitnessLevel
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

import           RzkGame.Level

-- | The levels, in play order, easiest first. (Later this comes from a game
-- spec; see the roadmap's Phase 3.) The ramp introduces one idea at a time:
-- a 1-dimensional morphism, then the constant 2-simplex, then the two
-- degenerate triangles that reuse a non-trivial edge.
gameLevels :: [Level]
gameLevels =
  [ idMorphismLevel
  , constTriangleLevel
  , hom2Level
  , homLeftUnitLevel
  , mapPointLevel
  , apHomLevel
  , composeLevel
  , composeWitnessLevel
  ]

-- | The shared, read-only prelude: the simplicial-HoTT definitions the level
-- builds on. Checked once; populates the inventory.
prelude :: Text
prelude = T.unlines
  [ "#lang rzk-1"
  , "#def Δ¹ : 2 → TOPE := \\ t → TOP"
  , "#def Δ² : (2 × 2) → TOPE := \\ (t , s) → s ≤ t"
  , "#def hom (A : U) (x y : A) : U"
  , "  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]"
  , "#def id-hom (A : U) (x : A) : hom A x x := \\ t → x"
  , "#def hom2 (A : U) (x y z : A)"
  , "  (f : hom A x y) (g : hom A y z) (h : hom A x z) : U"
  , "  := ( (t , s) : Δ²) → A [ s ≡ 0₂ ↦ f t , t ≡ 1₂ ↦ g s , s ≡ t ↦ h s ]"
  ]

-- | The prelude for the composition levels. It extends the shared one with the
-- machinery of the Segal condition: a type is Segal when every composable pair
-- of arrows has a /unique/ filler triangle, i.e. the type of (composite,
-- witness) pairs is contractible. Composition is then read off the centre of
-- that contractible type. Following Riehl and Shulman, this is the structure
-- that makes a type behave like an (∞,1)-category.
segalPrelude :: Text
segalPrelude = prelude <> T.unlines
  [ "#def is-contr (A : U) : U"
  , "  := Σ (a : A) , (x : A) → a =_{ A } x"
  , "#def is-segal (A : U) : U"
  , "  := (x : A) → (y : A) → (z : A) → (f : hom A x y) → (g : hom A y z)"
  , "   → is-contr (Σ (h : hom A x z) , hom2 A x y z f g h)"
  ]

-- | The warm-up: the identity morphism. A morphism @x → y@ is a path along the
-- directed interval @Δ¹@; the identity is the constant path at @x@. One hole,
-- a trivial tope context — the gentlest first contact with an extension type.
-- Solution: ignore the interval coordinate and return @x@.
idMorphismLevel :: Level
idMorphismLevel = Level
  { levelTitle     = "The identity morphism"
  , levelIntro     =
      "A morphism x → y in A is a path along the directed interval Δ¹. The \
      \simplest one is the identity: the morphism from x to itself that just \
      \stays put. Both endpoints of the path are x, so a constant path will do. \
      \Build it."
  , levelStatement = "hom A x x"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def my-id (A : U) (x : A)"
      , "  : hom A x x"
      , "  := ?"
      ]
  , levelSolution  = T.unlines
      [ "#def my-id (A : U) (x : A)"
      , "  : hom A x x"
      , "  := \\ t → x"
      ]
  , levelInventory =
      [ "x        : A"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "The constant path is the identity morphism. Both endpoints ask for x, so \
      \x itself fills the hole — no need to move along the interval at all."
  }

-- | The constant 2-simplex: every edge is the identity at a single point @x@.
-- A first @hom2@ with all three boundaries equal, so the same point @x@ fills
-- the whole triangle. It teaches the two-coordinate λ-intro before the edges
-- start to differ. Solution: ignore both coordinates and return @x@.
constTriangleLevel :: Level
constTriangleLevel = Level
  { levelTitle     = "The constant triangle"
  , levelIntro     =
      "A hom2 is a triangle: a map out of the 2-simplex Δ². The simplest one is \
      \constant — every edge is the identity at a single point x. Introduce the \
      \two coordinates, then find the point of A that sits on all three edges."
  , levelStatement = "hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def const-triangle (A : U) (x : A)"
      , "  : hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)"
      , "  := ?"
      ]
  , levelSolution  = T.unlines
      [ "#def const-triangle (A : U) (x : A)"
      , "  : hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)"
      , "  := \\ (t , s) → x"
      ]
  , levelInventory =
      [ "x        : A"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the two cube coordinates"
      ]
  , levelConclusion =
      "Every boundary asked for x, so the constant function fills the whole \
      \triangle. In the next levels one edge becomes a genuine morphism, and the \
      \point has to vary along a coordinate."
  }

-- | The right-unit degenerate triangle. Given @f : x → y@, build the 2-simplex
-- whose right edge is the identity at @y@ and whose hypotenuse is @f@ itself.
-- Solution: ignore the second coordinate and reuse @f@ on the first.
hom2Level :: Level
hom2Level = Level
  { levelTitle     = "The right-unit triangle"
  , levelIntro     =
      "Now an edge becomes a genuine morphism. The hypotenuse of a hom2 is the \
      \composite of its other two edges. Most triangles need A to be Segal — but \
      \some are free. Given f : x → y, the triangle whose right edge is the \
      \identity at y has f itself as its hypotenuse. This time the point must \
      \vary along the first coordinate. Build it."
  , levelStatement = "hom2 A x y y f (id-hom A y) f"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def rut (A : U) (x y : A) (f : hom A x y)"
      , "  : hom2 A x y y f (id-hom A y) f"
      , "  := \\ (t , s) → ?"
      ]
  , levelSolution  = T.unlines
      [ "#def rut (A : U) (x y : A) (f : hom A x y)"
      , "  : hom2 A x y y f (id-hom A y) f"
      , "  := \\ (t , s) → f t"
      ]
  , levelInventory =
      [ "f        : hom A x y"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the cube coordinates"
      ]
  , levelConclusion =
      "The degenerate triangle is just f ignoring the second coordinate. \
      \Reusing an existing edge, reparametrised, is the bread and butter of \
      \simplicial proofs."
  }

-- | The left-unit degenerate triangle: the mirror of the right-unit one. Given
-- @f : x → y@, the triangle whose /left/ edge is the identity at @x@ again has
-- @f@ as its hypotenuse, but the degenerate copy of @f@ must vary in the second
-- coordinate. Solution: reuse @f@ on @s@ rather than @t@.
homLeftUnitLevel :: Level
homLeftUnitLevel = Level
  { levelTitle     = "The left-unit triangle"
  , levelIntro     =
      "Now the mirror image. Given f : x → y, the triangle whose left edge is \
      \the identity at x also has f as its hypotenuse — but this time the \
      \degenerate copy of f must vary in the other coordinate. Build it."
  , levelStatement = "hom2 A x x y (id-hom A x) f f"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def lut (A : U) (x y : A) (f : hom A x y)"
      , "  : hom2 A x x y (id-hom A x) f f"
      , "  := \\ (t , s) → ?"
      ]
  , levelSolution  = T.unlines
      [ "#def lut (A : U) (x y : A) (f : hom A x y)"
      , "  : hom2 A x x y (id-hom A x) f f"
      , "  := \\ (t , s) → f s"
      ]
  , levelInventory =
      [ "f        : hom A x y"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the cube coordinates"
      ]
  , levelConclusion =
      "The same edge f, reparametrised in the other coordinate. The right-unit \
      \triangle used the first coordinate; the left-unit one uses the second."
  }

-- | Functoriality on a point. A function @g : A → B@ sends each point of @A@ to
-- a point of @B@. The identity morphism at @x@ is carried to the identity at its
-- image @g x@. The application @g@ is already in place; the player fills the
-- point it carries. Solution: the constant point @x@, so the result is @g x@.
mapPointLevel :: Level
mapPointLevel = Level
  { levelTitle     = "A function on a point"
  , levelIntro     =
      "Now we leave a single type and bring in a function g : A → B. A function \
      \sends each point of A to a point of B. The identity morphism at a point \
      \just stays put, and g carries it along. The application g (?) is already \
      \in place; fill in the point of A whose image is the identity's endpoint."
  , levelStatement = "hom B (g x) (g x)"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def map-point (A B : U) (g : A → B) (x : A)"
      , "  : hom B (g x) (g x)"
      , "  := \\ t → g (?)"
      ]
  , levelSolution  = T.unlines
      [ "#def map-point (A B : U) (g : A → B) (x : A)"
      , "  : hom B (g x) (g x)"
      , "  := \\ t → g (x)"
      ]
  , levelInventory =
      [ "g        : A → B"
      , "x        : A"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "A function sends a point to a point, and the constant path at g x is its \
      \identity. The next level carries a whole morphism along, not just a point."
  }

-- | Functoriality on a morphism (the action of a function on a 1-cell). A
-- function @g : A → B@ carries a morphism @f : x → y@ in @A@ to a morphism
-- @g x → g y@ in @B@, by applying @g@ at each moment of the path. The
-- application @g@ is in place; the player fills the point @f@ traces out.
-- Solution: the traversing point @f t@, so the result is @g (f t)@.
apHomLevel :: Level
apHomLevel = Level
  { levelTitle     = "A function on a morphism"
  , levelIntro     =
      "Functions act on morphisms too. A morphism f : x → y in A is a path; \
      \applying g at each moment of that path gives a morphism g x → g y in B. \
      \The function g is already in place; fill in the point of A that f traces \
      \out as the coordinate moves. Refine with f, then give the coordinate."
  , levelStatement = "hom B (g x) (g y)"
  , levelPrelude   = prelude
  , levelTemplate  = T.unlines
      [ "#def ap-hom (A B : U) (g : A → B) (x y : A) (f : hom A x y)"
      , "  : hom B (g x) (g y)"
      , "  := \\ t → g (?)"
      ]
  , levelSolution  = T.unlines
      [ "#def ap-hom (A B : U) (g : A → B) (x y : A) (f : hom A x y)"
      , "  : hom B (g x) (g y)"
      , "  := \\ t → g (f t)"
      ]
  , levelInventory =
      [ "g        : A → B"
      , "f        : hom A x y"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "Applying g along the path f gives a morphism between the images. This is \
      \functoriality: a function carries morphisms to morphisms, here g (f t) \
      \tracing g's image of f."
  }

-- | Composition in a Segal type. Until now every construction was free; genuine
-- composition needs a hypothesis. In a Segal type each composable pair @f, g@
-- has a contractible type of fillers, so @is-segal-A x y z f g@ is a proof that
-- the type of pairs @(h , triangle)@ is contractible. The composite is the
-- arrow at the centre of that contraction: the first projection of the first
-- projection. This is a typed term rather than a tap chain — assemble it from
-- the inventory and press Check.
composeLevel :: Level
composeLevel = Level
  { levelTitle     = "Composition"
  , levelIntro     =
      "Every level so far was free: no hypothesis was needed. Genuine \
      \composition is different. A Segal type is one where each composable pair \
      \of arrows has a unique filler triangle, so is-segal-A x y z f g proves \
      \that the type of pairs (h , triangle) is contractible. Its centre, \
      \first (is-segal-A x y z f g), is the pair (composite , witness). Take the \
      \first projection of that pair to get the composite arrow. Type the term \
      \and press Check."
  , levelStatement = "hom A x z"
  , levelPrelude   = segalPrelude
  , levelTemplate  = T.unlines
      [ "#def compose"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom A x z"
      , "  := ?"
      ]
  , levelSolution  = T.unlines
      [ "#def compose"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom A x z"
      , "  := first (first (is-segal-A x y z f g))"
      ]
  , levelInventory =
      [ "is-segal-A : is-segal A"
      , "is-segal-A x y z f g : is-contr (Σ (h : hom A x z) , hom2 …)"
      , "first      : the centre of a contractible type / first of a pair"
      , "second     : the second component of a pair"
      ]
  , levelConclusion =
      "The composite g ∘ f is the arrow at the centre of the contractible space \
      \of fillers. The Segal condition is exactly what makes this arrow exist \
      \and be well-defined. Next: recover the triangle that witnesses it."
  }

-- | The witness triangle for the composite. The same centre of contraction
-- carries, in its /second/ component, the 2-simplex showing that the composite
-- really is a composite of @f@ and @g@. The goal repeats the composite term
-- from the previous level as the triangle's diagonal, so the connection is
-- visible: this triangle's hypotenuse is exactly the arrow just built.
composeWitnessLevel :: Level
composeWitnessLevel = Level
  { levelTitle     = "The composition witness"
  , levelIntro     =
      "Building the composite arrow was only half of the centre of contraction. \
      \Its second component is the triangle witnessing that the arrow really is \
      \the composite of f and g. The goal's diagonal is the composite you built \
      \last time. Take the second projection of the centre to recover its \
      \witness."
  , levelStatement = "hom2 A x y z f g (first (first (is-segal-A x y z f g)))"
  , levelPrelude   = segalPrelude
  , levelTemplate  = T.unlines
      [ "#def compose-witness"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom2 A x y z f g (first (first (is-segal-A x y z f g)))"
      , "  := ?"
      ]
  , levelSolution  = T.unlines
      [ "#def compose-witness"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom2 A x y z f g (first (first (is-segal-A x y z f g)))"
      , "  := second (first (is-segal-A x y z f g))"
      ]
  , levelInventory =
      [ "is-segal-A : is-segal A"
      , "first (is-segal-A x y z f g) : (composite , witness) pair"
      , "first      : the composite arrow (the pair's first component)"
      , "second     : the witness triangle (the pair's second component)"
      ]
  , levelConclusion =
      "The composite and its witnessing triangle are the two halves of one \
      \centre of contraction. Together they say: in a Segal type, composition \
      \exists and the triangle proving it is there for free."
  }
