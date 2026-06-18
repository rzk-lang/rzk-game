{-# LANGUAGE OverloadedStrings #-}

-- | Hand-authored level content. (Later this comes from a game spec; see the
-- roadmap's Phase 3.) For now, the first Rzk-native level: a @hom2@ filler.
--
-- The levels are grouped into BOPPPS-style 'Section's ('gameSections'). The flat
-- 'gameLevels' is derived from them, in the same global order as before, so the
-- index-keyed progress and drafts stay compatible.
module RzkGame.Content
  ( gameLevels
  , gameSections
  , gameSlots
  , idMorphismLevel
  , constTriangleLevel
  , hom2Level
  , homLeftUnitLevel
  , mapPointLevel
  , apHomLevel
  , composeLevel
  , composeWitnessLevel
  ) where

import           Data.Text     (Text)
import qualified Data.Text     as T

import           RzkGame.Level
import           RzkGame.Section

-- | The levels, in play order, easiest first, derived from 'gameSections'. The
-- global order is @[my-id, const-triangle, rut, lut, map-point, ap-hom, compose,
-- compose-witness]@; preserve it, since progress and drafts are keyed by this
-- index (see the handoff note).
gameLevels :: [Level]
gameLevels = [ puzzleLevel z | SPuzzle z <- concatMap sectionItems gameSections ]

-- | The flattened navigation sequence: prose and puzzles interleaved, with
-- puzzles numbered by their global index.
gameSlots :: [Slot]
gameSlots = slotsOfSections gameSections

-- | The game's BOPPPS-style modules. BOPPPS structure is recommended, not
-- mandatory: prose blocks carry an optional role tag and may sit anywhere. The
-- three sections demonstrate the mechanics — a starred extra (the left-unit
-- triangle), a pre-test that gates a dependent level (functions on cells), and a
-- mid-section aside (the associativity preview).
gameSections :: [Section]
gameSections =
  [ Section "morphisms" "Morphisms and triangles"
      [ SProse  proseMorphismsIntro
      , SPuzzle (core  "my-id"          idMorphismLevel)
      , SPuzzle (core  "const-triangle" constTriangleLevel)
      , SPuzzle (core  "rut"            hom2Level)
      , SPuzzle (extra "lut"            homLeftUnitLevel)
      , SProse  proseMorphismsSummary
      ]
  , Section "functions" "Functions act on cells"
      [ SProse  proseFunctionsIntro
      , SPuzzle (pretest "map-point" mapPointLevel functionsRemedy)
      , SPuzzle ((core "ap-hom" apHomLevel) { puzzlePrereqs = ["map-point"] })
      , SProse  proseFunctionsSummary
      ]
  , Section "composition" "Composition in Segal types"
      [ SProse  proseCompositionIntro
      , SPuzzle (core "compose" composeLevel)
      , SProse  proseAssociativityNote
      , SPuzzle ((core "compose-witness" composeWitnessLevel)
                   { puzzlePrereqs = ["compose"] })
      , SProse  proseCompositionSummary
      ]
  ]

-- | Smart constructors for the common puzzle roles, so the section list above
-- reads as content rather than record boilerplate.
core :: Text -> Level -> PuzzleItem
core pid lvl = PuzzleItem lvl pid Core [] []

extra :: Text -> Level -> PuzzleItem
extra pid lvl = PuzzleItem lvl pid Extra [] []

pretest :: Text -> Level -> [Remedy] -> PuzzleItem
pretest pid lvl = PuzzleItem lvl pid PreTest []

-- | Remediation for the @map-point@ pre-test: where to send a player who is not
-- yet comfortable that functions act on cells.
functionsRemedy :: [Remedy]
functionsRemedy =
  [ Remedy "Review: Morphisms and triangles" (ToSection "morphisms")
  , Remedy "sHoTT: the Segal-types chapter"
      (ToExternal "https://rzk-lang.github.io/sHoTT/simplicial-hott/05-segal-types.rzk/")
  ]

-- | Section prose (Markdown + TeX, rendered by @prose.js@). Backslashes are
-- doubled for Haskell; @\\n\\n@ separates paragraphs.
proseMorphismsIntro :: Prose
proseMorphismsIntro = Prose "morphisms-intro" "Start here" (Just BridgeIn) $ T.concat
  [ "In directed type theory a **morphism** $x \\to y$ is a path along the "
  , "directed interval $\\Delta^1$, and a **triangle** (`hom2`) is a map out of "
  , "the $2$-simplex $\\Delta^2$. This first module builds them by hand.\n\n"
  , "*By the end you will be able to:* construct the identity morphism, fill the "
  , "constant triangle, and reparametrise an edge to fill a degenerate (unit) "
  , "triangle. The mirror **left-unit** triangle is marked ★ — optional "
  , "enrichment you may skip."
  ]

proseMorphismsSummary :: Prose
proseMorphismsSummary = Prose "morphisms-summary" "Wrap-up" (Just Summary) $ T.concat
  [ "You can now build morphisms as paths and fill triangles by reusing an edge "
  , "under a change of coordinates. These degenerate triangles needed no extra "
  , "hypotheses — the next module brings in functions."
  ]

proseFunctionsIntro :: Prose
proseFunctionsIntro = Prose "functions-intro" "Start here" (Just BridgeIn) $ T.concat
  [ "A function $g : A \\to B$ does more than map points: it carries whole "
  , "cells. Applying $g$ along a path gives a path, so a function acts on "
  , "morphisms, not just points — this is **functoriality**.\n\n"
  , "This module opens with a quick **pre-test**. If functoriality is new to "
  , "you, say so: you will get a pointer to review first, and the dependent "
  , "level will wait for you.\n\n"
  , "*By the end you will be able to:* carry a point and a morphism along a "
  , "function."
  ]

proseFunctionsSummary :: Prose
proseFunctionsSummary = Prose "functions-summary" "Wrap-up" (Just Summary) $ T.concat
  [ "A function preserves cells: it sends points to points and morphisms to "
  , "morphisms. With functoriality in hand, the last module tackles genuine "
  , "composition."
  ]

proseCompositionIntro :: Prose
proseCompositionIntro = Prose "composition-intro" "Start here" (Just BridgeIn) $ T.concat
  [ "Every construction so far was free. **Composition** needs a hypothesis: a "
  , "type is **Segal** when each composable pair of arrows has a unique filler "
  , "triangle. The composite is read off the centre of that contractible "
  , "space.\n\n"
  , "*By the end you will be able to:* extract the composite arrow and recover "
  , "the triangle that witnesses it."
  ]

-- | A mid-section aside (a prose pseudo-level that sits /between/ two puzzles),
-- previewing associativity and linking the sHoTT source. We do not build the
-- associativity levels here; this note points the way.
proseAssociativityNote :: Prose
proseAssociativityNote = Prose "composition-assoc" "Aside: associativity" (Just Note) $ T.concat
  [ "**Looking ahead: associativity.** Once composition exists, the natural "
  , "question is whether $(h \\circ g) \\circ f = h \\circ (g \\circ f)$. In a "
  , "Segal type it does, by a slick argument: the composition witnesses become "
  , "arrows in the arrow type $\\mathsf{arr}\\,A$, which is *itself* Segal, so "
  , "composing them builds a $3$-simplex (a tetrahedron) whose uniqueness forces "
  , "both bracketings to agree. We do not prove it here — see the "
  , "[sHoTT chapter on associativity]"
  , "(https://rzk-lang.github.io/sHoTT/simplicial-hott/05-segal-types.rzk/#associativity)."
  ]

proseCompositionSummary :: Prose
proseCompositionSummary = Prose "composition-summary" "Wrap-up" (Just Summary) $ T.concat
  [ "In a Segal type, composition exists and comes with a witnessing triangle — "
  , "the two halves of one centre of contraction. That is the structure that "
  , "makes a type behave like an $(\\infty,1)$-category."
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
      "A morphism $x \\to y$ in $A$ is a path along the directed interval $\\Delta^1$. The simplest one is the identity: the morphism from $x$ to itself that just stays put. Both endpoints of the path are $x$, so a constant path will do. Build it."
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
  , levelGoalName  = "my-id"
  , levelGoalType  = "(A : U) → (x : A) → hom A x x"
  , levelInventory =
      [ "x        : A"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "The constant path is the identity morphism. Both endpoints ask for $x$, so $x$ itself fills the hole — no need to move along the interval at all."
  }

-- | The constant 2-simplex: every edge is the identity at a single point @x@.
-- A first @hom2@ with all three boundaries equal, so the same point @x@ fills
-- the whole triangle. It teaches the two-coordinate λ-intro before the edges
-- start to differ. Solution: ignore both coordinates and return @x@.
constTriangleLevel :: Level
constTriangleLevel = Level
  { levelTitle     = "The constant triangle"
  , levelIntro     =
      "A `hom2` is a triangle: a map out of the 2-simplex $\\Delta^2$. The simplest one is constant — every edge is the identity at a single point $x$. Introduce the two coordinates, then find the point of $A$ that sits on all three edges."
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
  , levelGoalName  = "const-triangle"
  , levelGoalType  =
      "(A : U) → (x : A) → hom2 A x x x (id-hom A x) (id-hom A x) (id-hom A x)"
  , levelInventory =
      [ "x        : A"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the two cube coordinates"
      ]
  , levelConclusion =
      "Every boundary asked for $x$, so the constant function fills the whole triangle. In the next levels one edge becomes a genuine morphism, and the point has to vary along a coordinate."
  }

-- | The right-unit degenerate triangle. Given @f : x → y@, build the 2-simplex
-- whose right edge is the identity at @y@ and whose hypotenuse is @f@ itself.
-- Solution: ignore the second coordinate and reuse @f@ on the first.
hom2Level :: Level
hom2Level = Level
  { levelTitle     = "The right-unit triangle"
  , levelIntro     =
      "Now an edge becomes a genuine morphism. The hypotenuse of a `hom2` is the composite of its other two edges. Most triangles need $A$ to be Segal — but some are free. Given $f : x \\to y$, the triangle whose right edge is the identity at $y$ has $f$ itself as its hypotenuse. This time the point must vary along the first coordinate. Build it."
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
  , levelGoalName  = "rut"
  , levelGoalType  =
      "(A : U) → (x : A) → (y : A) → (f : hom A x y) \
      \→ hom2 A x y y f (id-hom A y) f"
  , levelInventory =
      [ "f        : hom A x y"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the cube coordinates"
      ]
  , levelConclusion =
      "The degenerate triangle is just $f$ ignoring the second coordinate. Reusing an existing edge, reparametrised, is the bread and butter of simplicial proofs."
  }

-- | The left-unit degenerate triangle: the mirror of the right-unit one. Given
-- @f : x → y@, the triangle whose /left/ edge is the identity at @x@ again has
-- @f@ as its hypotenuse, but the degenerate copy of @f@ must vary in the second
-- coordinate. Solution: reuse @f@ on @s@ rather than @t@.
homLeftUnitLevel :: Level
homLeftUnitLevel = Level
  { levelTitle     = "The left-unit triangle"
  , levelIntro     =
      "Now the mirror image. Given $f : x \\to y$, the triangle whose left edge is the identity at $x$ also has $f$ as its hypotenuse — but this time the degenerate copy of $f$ must vary in the other coordinate. Build it."
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
  , levelGoalName  = "lut"
  , levelGoalType  =
      "(A : U) → (x : A) → (y : A) → (f : hom A x y) \
      \→ hom2 A x x y (id-hom A x) f f"
  , levelInventory =
      [ "f        : hom A x y"
      , "id-hom   : (A : U) → (x : A) → hom A x x"
      , "λ-intro  : introduce the cube coordinates"
      ]
  , levelConclusion =
      "The same edge $f$, reparametrised in the other coordinate. The right-unit triangle used the first coordinate; the left-unit one uses the second."
  }

-- | Functoriality on a point. A function @g : A → B@ sends each point of @A@ to
-- a point of @B@. The identity morphism at @x@ is carried to the identity at its
-- image @g x@. The application @g@ is already in place; the player fills the
-- point it carries. Solution: the constant point @x@, so the result is @g x@.
mapPointLevel :: Level
mapPointLevel = Level
  { levelTitle     = "A function on a point"
  , levelIntro     =
      "Now we leave a single type and bring in a function $g : A \\to B$. A function sends each point of $A$ to a point of $B$. The identity morphism at a point just stays put, and $g$ carries it along. The application `g (?)` is already in place; fill in the point of $A$ whose image is the identity's endpoint."
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
  , levelGoalName  = "map-point"
  , levelGoalType  =
      "(A : U) → (B : U) → (g : A → B) → (x : A) → hom B (g x) (g x)"
  , levelInventory =
      [ "g        : A → B"
      , "x        : A"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "A function sends a point to a point, and the constant path at `g x` is its identity. The next level carries a whole morphism along, not just a point."
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
      "Functions act on morphisms too. A morphism $f : x \\to y$ in $A$ is a path; applying $g$ at each moment of that path gives a morphism $g\\,x \\to g\\,y$ in $B$. The function $g$ is already in place; fill in the point of $A$ that $f$ traces out as the coordinate moves. Refine with `f`, then give the coordinate."
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
  , levelGoalName  = "ap-hom"
  , levelGoalType  =
      "(A : U) → (B : U) → (g : A → B) → (x : A) → (y : A) \
      \→ (f : hom A x y) → hom B (g x) (g y)"
  , levelInventory =
      [ "g        : A → B"
      , "f        : hom A x y"
      , "λ-intro  : introduce the interval coordinate"
      ]
  , levelConclusion =
      "Applying $g$ along the path $f$ gives a morphism between the images. This is functoriality: a function carries morphisms to morphisms, here `g (f t)` tracing $g$'s image of $f$."
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
      "Every level so far was free: no hypothesis was needed. Genuine composition is different. A Segal type is one where each composable pair of arrows has a unique filler triangle, so `is-segal-A x y z f g` proves that the type of pairs `(h , triangle)` is contractible. Its centre, `first (is-segal-A x y z f g)`, is the pair `(composite , witness)`. Take the first projection of that pair to get the composite arrow. Type the term and press Check."
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
  , levelGoalName  = "compose"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A x y) → (g : hom A y z) → hom A x z"
  , levelInventory =
      [ "is-segal-A : is-segal A"
      , "is-segal-A x y z f g : is-contr (Σ (h : hom A x z) , hom2 …)"
      , "first      : the centre of a contractible type / first of a pair"
      , "second     : the second component of a pair"
      ]
  , levelConclusion =
      "The composite $g \\circ f$ is the arrow at the centre of the contractible space of fillers. The Segal condition is exactly what makes this arrow exist and be well-defined. Next: recover the triangle that witnesses it."
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
      "Building the composite arrow was only half of the centre of contraction. Its second component is the triangle witnessing that the arrow really is the composite of $f$ and $g$. The goal's diagonal is the composite you built last time. Take the second projection of the centre to recover its witness."
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
  , levelGoalName  = "compose-witness"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A x y) → (g : hom A y z) \
      \→ hom2 A x y z f g (first (first (is-segal-A x y z f g)))"
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
