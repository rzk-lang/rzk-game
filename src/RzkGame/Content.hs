{-# LANGUAGE OverloadedStrings #-}

-- | Hand-authored level content. (Later this comes from a game spec; see the
-- roadmap's Phase 3.) For now, the first Rzk-native level: a @hom2@ filler.
module RzkGame.Content
  ( gameLevels
  , idMorphismLevel
  , constTriangleLevel
  , hom2Level
  , homLeftUnitLevel
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
      , "  := \\ t → ?"
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
      , "  := \\ (t , s) → ?"
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
