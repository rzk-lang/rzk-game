{-# LANGUAGE OverloadedStrings #-}

-- | Hand-authored level content. (Later this comes from a game spec; see the
-- roadmap's Phase 3.) For now, the first Rzk-native level: a @hom2@ filler.
module RzkGame.Content
  ( gameLevels
  , hom2Level
  , homLeftUnitLevel
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

import           RzkGame.Level

-- | The levels, in play order. (Later this comes from a game spec; see the
-- roadmap's Phase 3.)
gameLevels :: [Level]
gameLevels = [hom2Level, homLeftUnitLevel]

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

-- | The right-unit degenerate triangle. Given @f : x → y@, build the 2-simplex
-- whose right edge is the identity at @y@ and whose hypotenuse is @f@ itself.
-- Solution: ignore the second coordinate and reuse @f@ on the first.
hom2Level :: Level
hom2Level = Level
  { levelTitle     = "The right-unit triangle"
  , levelIntro     =
      "A hom2 is a triangle: a 2-cell witnessing that its hypotenuse is the \
      \composite of its other two edges. Most triangles need A to be Segal — \
      \but some are free. Given f : x → y, the triangle whose right edge is the \
      \identity at y has f itself as its hypotenuse. Build it."
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
