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
  , unfoldingSquareLevel
  , witnessSquareLevel
  , idArrLevel
  , arrInArrLevel
  , witnessAssocLevel
  , tetrahedronLevel
  , tripleCompLevel
  ) where

import           Data.Text     (Text)
import qualified Data.Text     as T

import           RzkGame.Level
import           RzkGame.Section

-- | The levels, in play order, easiest first, derived from 'gameSections'. The
-- global order is @[my-id, const-triangle, rut, lut, map-point, ap-hom, compose,
-- compose-witness, unfolding-square, witness-square-comp-is-segal,
-- id-arr-in-arr, arr-in-arr-is-segal, witness-associative-is-segal,
-- tetrahedron-associative-is-segal, triple-comp-is-segal]@; preserve the prefix,
-- since progress and drafts are keyed by this index (see the handoff note). New
-- levels are appended, so the existing indices are untouched.
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
      , SPuzzle ((core "compose-witness" composeWitnessLevel)
                   { puzzlePrereqs = ["compose"] })
      , SProse  proseCompositionSummary
      ]
  , Section "associativity" "Associativity in Segal types"
      [ SProse  proseAssociativityIntro
      , SPuzzle (core "unfolding-square" unfoldingSquareLevel)
      , SPuzzle ((core "witness-square-comp-is-segal" witnessSquareLevel)
                   { puzzlePrereqs = ["compose-witness"] })
      , SPuzzle (core "id-arr-in-arr" idArrLevel)
      , SPuzzle ((core "arr-in-arr-is-segal" arrInArrLevel)
                   { puzzlePrereqs = ["compose-witness"] })
      , SProse  proseArrIsSegalNote
      , SPuzzle ((extra "witness-associative-is-segal" witnessAssocLevel)
                   { puzzlePrereqs = ["compose-witness"] })
      , SPuzzle ((core "tetrahedron-associative-is-segal" tetrahedronLevel)
                   { puzzlePrereqs = ["compose-witness"] })
      , SPuzzle ((core "triple-comp-is-segal" tripleCompLevel)
                   { puzzlePrereqs = ["compose-witness"] })
      , SProse  proseAssociativitySummary
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

-- | The bridge into the associativity module. Once composition exists, the
-- natural question is whether it is associative; in a Segal type it is, by a
-- slick argument that this module builds step by step.
proseAssociativityIntro :: Prose
proseAssociativityIntro = Prose "associativity-intro" "Start here" (Just BridgeIn) $ T.concat
  [ "Once composition exists, the natural question is whether "
  , "$(h \\circ g) \\circ f = h \\circ (g \\circ f)$. In a Segal type it is, by a "
  , "slick argument due to Riehl and Shulman: the composition witnesses become "
  , "arrows in the arrow type $\\mathsf{arr}\\,A$, which is *itself* Segal, so "
  , "composing them builds a $3$-simplex (a tetrahedron) whose uniqueness forces "
  , "both bracketings to agree.\n\n"
  , "*By the end you will be able to:* unfold a triangle into a square, lift "
  , "composition into the arrow type, and extract the associativity tetrahedron "
  , "and the triple composite. The witness-assembly level is marked ★ — the most "
  , "clerical step, optional. We follow the "
  , "[sHoTT chapter on associativity]"
  , "(https://rzk-lang.github.io/sHoTT/simplicial-hott/05-segal-types.rzk/#associativity)."
  ]

-- | The one assumption the module adds, stated plainly where it is first used.
proseArrIsSegalNote :: Prose
proseArrIsSegalNote = Prose "associativity-arr-segal" "Aside: one assumption" (Just Note) $ T.concat
  [ "**One fact taken on faith.** The argument needs that the arrow type "
  , "$\\mathsf{arr}\\,A$ of a Segal type is *itself* Segal. This is a theorem of "
  , "Riehl and Shulman, but its proof goes through the closure of Segal types "
  , "under extension types, which rests on extension extensionality — machinery "
  , "an order of magnitude larger than the reparametrisations this module is "
  , "about. So we postulate it (`is-segal-arr`) and keep the focus on the "
  , "geometry. It is the only assumption added here; everything else you build by "
  , "hand."
  ]

-- | The module wrap-up.
proseAssociativitySummary :: Prose
proseAssociativitySummary = Prose "associativity-summary" "Wrap-up" (Just Summary) $ T.concat
  [ "You lifted composition into the arrow type, composed the witnesses there, "
  , "and read the triple composite off the main diagonal of the resulting "
  , "tetrahedron. Its two faces present that composite as both $(h\\circ g)\\circ "
  , "f$ and $h\\circ(g\\circ f)$, so uniqueness of Segal composites makes the two "
  , "bracketings equal. That is associativity. With composition that is unital "
  , "and associative, a Segal type is a **pre-$(\\infty,1)$-category**; "
  , "strengthening it with local univalence — a **Rezk type** — gives a genuine "
  , "$(\\infty,1)$-category."
  ]

proseCompositionSummary :: Prose
proseCompositionSummary = Prose "composition-summary" "Wrap-up" (Just Summary) $ T.concat
  [ "In a Segal type, composition exists and comes with a witnessing triangle — "
  , "the two halves of one centre of contraction. That is what makes a Segal "
  , "type a **pre-$(\\infty,1)$-category**. A **Rezk type** — a Segal type that "
  , "is also locally univalent — is then a genuine $(\\infty,1)$-category."
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
-- that contractible type. Following Riehl and Shulman, this is the structure of
-- a pre-(∞,1)-category (a Segal type); a Rezk type — Segal plus local
-- univalence — is a genuine (∞,1)-category.
segalPrelude :: Text
segalPrelude = prelude <> T.unlines
  [ "#def is-contr (A : U) : U"
  , "  := Σ (a : A) , (x : A) → a =_{ A } x"
  , "#def is-segal (A : U) : U"
  , "  := (x : A) → (y : A) → (z : A) → (f : hom A x y) → (g : hom A y z)"
  , "   → is-contr (Σ (h : hom A x z) , hom2 A x y z f g h)"
  ]

-- | The prelude for the associativity levels. It extends the Segal one with the
-- machinery the associativity proof needs: the composition operators
-- @comp-is-segal@ / @witness-comp-is-segal@ (built by hand in the previous
-- section, here taken as given), the @3@-simplex @Δ³@ and the square @Δ¹×Δ¹@,
-- the arrow type @arr A@, and the one fact we take on faith — that the arrow
-- type of a Segal type is itself Segal (@is-segal-arr@).
--
-- Following Riehl and Shulman, @is-segal-arr@ is a theorem: it follows from the
-- closure of Segal types under extension types, which in turn needs extension
-- extensionality (@extext@). That proof is an order of magnitude larger than the
-- geometry these levels are about, so we 'postulate' it and focus on the
-- reparametrisations. This is the only assumption the section adds.
assocPrelude :: Text
assocPrelude = segalPrelude <> T.unlines
  [ "#def Δ³ : (2 × 2 × 2) → TOPE"
  , "  := \\ ((t1 , t2) , t3) → t3 ≤ t2 ∧ t2 ≤ t1"
  , "#def Δ¹×Δ¹ : (2 × 2) → TOPE := \\ (t , s) → TOP ∧ TOP"
  , "#def comp-is-segal"
  , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
  , "  (f : hom A x y) (g : hom A y z) : hom A x z"
  , "  := first (first (is-segal-A x y z f g))"
  , "#def witness-comp-is-segal"
  , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
  , "  (f : hom A x y) (g : hom A y z)"
  , "  : hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)"
  , "  := second (first (is-segal-A x y z f g))"
  , "#def arr (A : U) : U := Δ¹ → A"
  , "#postulate is-segal-arr"
  , "  : (A : U) → (is-segal-A : is-segal A) → is-segal (arr A)"
  ]

-- | The associativity levels stack: each builds on the definitions the player
-- produced in the earlier levels. We reuse those reference solutions verbatim as
-- the read-only prelude for the levels that follow, so a level's prelude is
-- exactly the section's accepted answers so far.
assocPreludeFor :: [Level] -> Text
assocPreludeFor prev = assocPrelude <> T.concat (map levelSolution prev)

-- | Append a "Useful here" block to a level's intro: the signatures of the
-- lemmas the solution leans on, as a fenced @rzk@ code block (rendered as a
-- monospaced box by @prose.js@). The full prelude is always available under
-- "Prelude (given)", but it lists /everything/; this restates just the handful
-- that matter for the level, so the player does not have to hunt. The block is
-- display only — it is never typechecked — so the readable grouped-binder
-- signatures (as in sHoTT) are fine even where a closed Π-type could not use
-- them. (A type-directed inventory of fillers is future work, on the rzk side.)
usefulHere :: [Text] -> Text
usefulHere ls = "\n\n**Useful here:**\n\n```rzk\n" <> T.intercalate "\n" ls <> "\n```"

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

-- | Unfolding a triangle into a square. The associativity proof works in the
-- arrow type @arr A@, and its building blocks are squares @Δ¹×Δ¹ → A@ rather
-- than triangles @Δ² → A@. A triangle covers only the lower half @s ≤ t@ of the
-- square; to fill the whole square we reflect it across the diagonal, reusing
-- the same triangle with its coordinates swapped on the upper half. This is pure
-- reparametrisation — no Segal hypothesis — and a first use of @recOR@ to split
-- on which side of the diagonal a point lies. Solution: on @s ≤ t@ keep
-- @triangle (t , s)@; on @t ≤ s@ use the reflected @triangle (s , t)@.
unfoldingSquareLevel :: Level
unfoldingSquareLevel = Level
  { levelTitle     = "Unfolding a triangle"
  , levelIntro     =
      "The associativity proof lives in the arrow type, and there the cells are *squares* $\\Delta^1\\times\\Delta^1 \\to A$, not triangles. A triangle fills only the lower half $s \\le t$ of the square. To fill the whole square, reflect the triangle across the diagonal: on the upper half $t \\le s$ reuse the same triangle with its two coordinates *swapped*. The `recOR` splits the square along the diagonal; fill each branch. No Segal hypothesis is needed — this is reparametrisation."
      <> usefulHere
           [ "triangle : Δ² → A           -- the lower-half triangle to unfold"
           , "-- recOR glues two branches along covering topes:"
           , "--   recOR ( t ≤ s ↦ … , s ≤ t ↦ … ) : A"
           ]
  , levelStatement = "Δ¹×Δ¹ → A"
  , levelPrelude   = assocPreludeFor []
  , levelTemplate  = T.unlines
      [ "#def unfolding-square (A : U) (triangle : Δ² → A)"
      , "  : Δ¹×Δ¹ → A"
      , "  := \\ (t , s) → recOR ( t ≤ s ↦ ? , s ≤ t ↦ ? )"
      ]
  , levelSolution  = T.unlines
      [ "#def unfolding-square (A : U) (triangle : Δ² → A)"
      , "  : Δ¹×Δ¹ → A"
      , "  := \\ (t , s) → recOR ( t ≤ s ↦ triangle (s , t) , s ≤ t ↦ triangle (t , s) )"
      ]
  , levelGoalName  = "unfolding-square"
  , levelGoalType  = "(A : U) → (triangle : Δ² → A) → Δ¹×Δ¹ → A"
  , levelInventory =
      [ "triangle : Δ² → A"
      , "recOR    : split on a pair of covering topes (here t ≤ s / s ≤ t)"
      , "(s , t)  : the swapped coordinate, reflecting across the diagonal"
      ]
  , levelConclusion =
      "A square is two copies of one triangle glued along the diagonal — the original on $s \\le t$ and its reflection on $t \\le s$. The two branches agree on the diagonal $s \\equiv t$, where both read $\\mathsf{triangle}\\,(t,t)$, so `recOR` is well-defined. We can now unfold any triangle into a square."
  }

-- | The composition witness, unfolded into a square. The previous level built
-- the unfolder; here we feed it the composition witness triangle from the Segal
-- structure. The result is the square cell that, read as an arrow in the arrow
-- type, witnesses composition there. Solution: hand @witness-comp-is-segal@ to
-- @unfolding-square@.
witnessSquareLevel :: Level
witnessSquareLevel = Level
  { levelTitle     = "The composition square"
  , levelIntro     =
      "Now use the unfolder. The Segal structure gives a *triangle* witnessing that the composite of $f$ and $g$ really is their composite. Unfold that triangle into a square, so it can later be read as an arrow in the arrow type. Apply `unfolding-square` to the composition witness."
      <> usefulHere
           [ "unfolding-square"
           , "  : (A : U) → (Δ² → A) → Δ¹×Δ¹ → A"
           , "witness-comp-is-segal"
           , "  : (A : U) → (is-segal-A : is-segal A) → (x y z : A)"
           , "  → (f : hom A x y) → (g : hom A y z)"
           , "  → hom2 A x y z f g (comp-is-segal A is-segal-A x y z f g)"
           ]
  , levelStatement = "Δ¹×Δ¹ → A"
  , levelPrelude   = assocPreludeFor [unfoldingSquareLevel]
  , levelTemplate  = T.unlines
      [ "#def witness-square-comp-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : Δ¹×Δ¹ → A"
      , "  := unfolding-square A (?)"
      ]
  , levelSolution  = T.unlines
      [ "#def witness-square-comp-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : Δ¹×Δ¹ → A"
      , "  := unfolding-square A (witness-comp-is-segal A is-segal-A x y z f g)"
      ]
  , levelGoalName  = "witness-square-comp-is-segal"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A x y) → (g : hom A y z) → Δ¹×Δ¹ → A"
  , levelInventory =
      [ "unfolding-square    : (A : U) → (Δ² → A) → Δ¹×Δ¹ → A"
      , "witness-comp-is-segal : the composition witness triangle"
      , "is-segal-A x y z f g  : the centre of contraction for f, g"
      ]
  , levelConclusion =
      "The composition witness is now a square. Its left and right edges are $f$ and $g$; its other two edges are the composite. Seen sideways, this square is an arrow whose endpoints are $f$ and $g$. The arrow type makes that precise — and the next two levels put it to work."
  }

-- | A gentle warm-up in the arrow type, isolating the two new ideas before they
-- meet the composition square: the type @arr A@ (whose points are arrows) and
-- the curried @\ t s →@ binder. The simplest arrow between arrows is the
-- identity at an arrow @f@ — the constant path that never leaves @f@. Solution:
-- ignore the path coordinate @t@ and return @f@ at its own coordinate @s@.
idArrLevel :: Level
idArrLevel = Level
  { levelTitle     = "An identity between arrows"
  , levelIntro     =
      "A new kind of target: the **arrow type** $\\mathsf{arr}\\,A = \\Delta^1 \\to A$, whose points are the arrows of $A$. A morphism *between* two arrows, $\\mathsf{hom}\\,(\\mathsf{arr}\\,A)\\,f\\,g$, is a path of arrows, and it takes two coordinates — the first, $t$, slides between arrows; the second, $s$, runs along the arrow sitting there. Start with the simplest one: the **identity** at $f$, the constant path that never leaves $f$. Ignore the path coordinate $t$ and return $f$ at its own coordinate $s$."
      <> usefulHere
           [ "arr A := Δ¹ → A             -- a point of arr A is an arrow"
           , "f : arr A                   -- so f s : A for a coordinate s"
           ]
  , levelStatement = "hom (arr A) f f"
  , levelPrelude   = assocPreludeFor [unfoldingSquareLevel, witnessSquareLevel]
  , levelTemplate  = T.unlines
      [ "#def id-arr-in-arr (A : U) (f : arr A)"
      , "  : hom (arr A) f f"
      , "  := \\ t s → ?"
      ]
  , levelSolution  = T.unlines
      [ "#def id-arr-in-arr (A : U) (f : arr A)"
      , "  : hom (arr A) f f"
      , "  := \\ t s → f s"
      ]
  , levelGoalName  = "id-arr-in-arr"
  , levelGoalType  = "(A : U) → (f : arr A) → hom (arr A) f f"
  , levelInventory =
      [ "f        : arr A   (an arrow of A)"
      , "f s      : A       the arrow f at its own coordinate s"
      , "λ-intro  : two coordinates — t between arrows, s along the arrow"
      ]
  , levelConclusion =
      "The identity between arrows ignores the path coordinate $t$ and hands back the arrow $f$ unchanged. The two coordinates have clear roles: $t$ moves between arrows, $s$ runs along the arrow at hand. In the next level $t$ genuinely moves."
  }

-- | The composition square, read as an arrow in the arrow type. Currying the
-- square @Δ¹×Δ¹ → A@ in its first coordinate gives a map @Δ¹ → (Δ¹ → A)@, i.e.
-- an arrow in @arr A@ whose endpoints are @f@ and @g@. This is the key change of
-- viewpoint that makes composition in @A@ into composition in @arr A@. It is the
-- same curried @\ t s →@ as the identity warm-up, but with the constant arrow
-- replaced by the moving composition square. Solution: @\ t s → witness-square …
-- (t , s)@.
arrInArrLevel :: Level
arrInArrLevel = Level
  { levelTitle     = "An arrow between arrows"
  , levelIntro     =
      "Now the real thing. The warm-up built the *constant* path of arrows; here the arrow genuinely moves. Use the composition square: as the first coordinate $t$ slides from $0$ to $1$, the arrow slides from $f$ to $g$. Curry it exactly as before — introduce $t$ and $s$, then read off the square at $(t , s)$. This is the pivot of the whole proof: composition in $A$ becomes an arrow in $\\mathsf{arr}\\,A$."
      <> usefulHere
           [ "witness-square-comp-is-segal"
           , "  : (A : U) → (is-segal-A : is-segal A) → (x y z : A)"
           , "  → (f : hom A x y) → (g : hom A y z) → Δ¹×Δ¹ → A"
           , "-- hom (arr A) f g is a path of arrows from f to g"
           ]
  , levelStatement = "hom (arr A) f g"
  , levelPrelude   = assocPreludeFor [unfoldingSquareLevel, witnessSquareLevel, idArrLevel]
  , levelTemplate  = T.unlines
      [ "#def arr-in-arr-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom (arr A) f g"
      , "  := \\ t s → ?"
      ]
  , levelSolution  = T.unlines
      [ "#def arr-in-arr-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (x y z : A)"
      , "  (f : hom A x y) (g : hom A y z)"
      , "  : hom (arr A) f g"
      , "  := \\ t s → witness-square-comp-is-segal A is-segal-A x y z f g (t , s)"
      ]
  , levelGoalName  = "arr-in-arr-is-segal"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A x y) → (g : hom A y z) → hom (arr A) f g"
  , levelInventory =
      [ "witness-square-comp-is-segal : the composition square Δ¹×Δ¹ → A"
      , "f , g    : the endpoints, now points of arr A"
      , "λ-intro  : t slides from f to g; s runs along the arrow at (t , s)"
      ]
  , levelConclusion =
      "Composition in $A$ is now an arrow in $\\mathsf{arr}\\,A$. Because the arrow type of a Segal type is again Segal, these arrows can themselves be composed — and that second-order composition is what makes associativity fall out."
  }

-- | Composition associativity, witnessed in the arrow type. With @arr A@ shown
-- Segal (taken as given here via @is-segal-arr@), the two composition arrows
-- @arr-in-arr@ for @(f,g)@ and @(g,h)@ compose. Their composition witness is a
-- @hom2@ in @arr A@ — a triangle of arrows whose hypotenuse is their composite.
-- This is the mechanical heart: assemble @witness-comp-is-segal@ at @arr A@. The
-- long goal type names every edge, so the term is one spine over the inventory.
-- Marked ★: it carries the idea but is the most clerical of the section.
witnessAssocLevel :: Level
witnessAssocLevel = Level
  { levelTitle     = "Composing the witnesses"
  , levelIntro     =
      "The two composition arrows — one for $(f,g)$, one for $(g,h)$ — are composable arrows in $\\mathsf{arr}\\,A$. Since the arrow type is itself Segal (we take this as given; see the section note), they have a composition witness: a triangle `hom2 (arr A)` whose hypotenuse is their composite. Build it the same way as before, but one level up: apply `witness-comp-is-segal` in the arrow type to the two `arr-in-arr-is-segal` arrows."
      <> usefulHere
           [ "-- the same witness-comp-is-segal, applied with A := arr A and"
           , "-- is-segal-A := is-segal-arr A is-segal-A:"
           , "is-segal-arr A is-segal-A"
           , "  : is-segal (arr A)"
           , "arr-in-arr-is-segal A is-segal-A w x y f g"
           , "  : hom (arr A) f g          -- the (f,g) composition arrow"
           , "arr-in-arr-is-segal A is-segal-A x y z g h"
           , "  : hom (arr A) g h          -- the (g,h) composition arrow"
           ]
  , levelStatement = "hom2 (arr A) f g h …"
  , levelPrelude   = assocPreludeFor
      [unfoldingSquareLevel, witnessSquareLevel, idArrLevel, arrInArrLevel]
  , levelTemplate  = T.unlines
      [ "#def witness-associative-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : hom2 (arr A) f g h"
      , "      (arr-in-arr-is-segal A is-segal-A w x y f g)"
      , "      (arr-in-arr-is-segal A is-segal-A x y z g h)"
      , "      (comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h"
      , "        (arr-in-arr-is-segal A is-segal-A w x y f g)"
      , "        (arr-in-arr-is-segal A is-segal-A x y z g h))"
      , "  := ?"
      ]
  , levelSolution  = T.unlines
      [ "#def witness-associative-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : hom2 (arr A) f g h"
      , "      (arr-in-arr-is-segal A is-segal-A w x y f g)"
      , "      (arr-in-arr-is-segal A is-segal-A x y z g h)"
      , "      (comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h"
      , "        (arr-in-arr-is-segal A is-segal-A w x y f g)"
      , "        (arr-in-arr-is-segal A is-segal-A x y z g h))"
      , "  := witness-comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h"
      , "       (arr-in-arr-is-segal A is-segal-A w x y f g)"
      , "       (arr-in-arr-is-segal A is-segal-A x y z g h)"
      ]
  , levelGoalName  = "witness-associative-is-segal"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (w : A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A w x) → (g : hom A x y) → (h : hom A y z) \
      \→ hom2 (arr A) f g h \
      \(arr-in-arr-is-segal A is-segal-A w x y f g) \
      \(arr-in-arr-is-segal A is-segal-A x y z g h) \
      \(comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h \
      \(arr-in-arr-is-segal A is-segal-A w x y f g) \
      \(arr-in-arr-is-segal A is-segal-A x y z g h))"
  , levelInventory =
      [ "witness-comp-is-segal : the witness, here applied in arr A"
      , "is-segal-arr A is-segal-A : arr A is Segal (taken as given)"
      , "arr-in-arr-is-segal … w x y f g : the (f,g) composition arrow"
      , "arr-in-arr-is-segal … x y z g h : the (g,h) composition arrow"
      ]
  , levelConclusion =
      "A triangle of arrows: its two legs are the $(f,g)$ and $(g,h)$ composition arrows, and its hypotenuse is their composite in $\\mathsf{arr}\\,A$. Uncurried, this triangle of arrows is a prism $\\Delta^2\\times\\Delta^1 \\to A$ — and the tetrahedron is hiding inside it."
  }

-- | The tetrahedron, extracted from the prism. The witness triangle in @arr A@
-- curries to a prism @Δ²×Δ¹ → A@. The @3@-simplex @Δ³@ sits inside that prism via
-- the middle-simplex map @((t , s) , r) ↦ ((t , r) , s)@: swap the inner and
-- outer second coordinates. Solution: apply the witness with the coordinates
-- regrouped, @witness-associative … (t , r) s@.
tetrahedronLevel :: Level
tetrahedronLevel = Level
  { levelTitle     = "The associativity tetrahedron"
  , levelIntro     =
      "The triangle of arrows, uncurried, is a prism $\\Delta^2\\times\\Delta^1 \\to A$. The $3$-simplex $\\Delta^3$ embeds in that prism by the *middle-simplex* map $((t,s),r) \\mapsto ((t,r),s)$ — swap the inner coordinate $s$ with the outer one $r$. Introduce the three coordinates of $\\Delta^3$, then apply the witness with them regrouped this way."
      <> usefulHere
           [ "witness-associative-is-segal A is-segal-A w x y z f g h"
           , "  : hom2 (arr A) f g h … …   -- a curried prism, applied as (t , r) s"
           , "-- middle-simplex map:  ((t , s) , r)  ↦  (t , r) s"
           ]
  , levelStatement = "Δ³ → A"
  , levelPrelude   = assocPreludeFor
      [ unfoldingSquareLevel, witnessSquareLevel, idArrLevel, arrInArrLevel
      , witnessAssocLevel ]
  , levelTemplate  = T.unlines
      [ "#def tetrahedron-associative-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : Δ³ → A"
      , "  := \\ ((t , s) , r) → ?"
      ]
  , levelSolution  = T.unlines
      [ "#def tetrahedron-associative-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : Δ³ → A"
      , "  := \\ ((t , s) , r) → witness-associative-is-segal A is-segal-A w x y z f g h (t , r) s"
      ]
  , levelGoalName  = "tetrahedron-associative-is-segal"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (w : A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A w x) → (g : hom A x y) → (h : hom A y z) → Δ³ → A"
  , levelInventory =
      [ "witness-associative-is-segal : the prism Δ²×Δ¹ → A, as a curried witness"
      , "((t , s) , r) : the Δ³ coordinates"
      , "(t , r) s     : the middle-simplex regrouping"
      ]
  , levelConclusion =
      "The middle-simplex map carries $\\Delta^3$ into the prism, extracting a genuine tetrahedron. Its four faces are the three pairwise composites and the triple composite; reading off its edges gives the two bracketings of $h\\circ g\\circ f$."
  }

-- | The triple composite, read off the tetrahedron's main diagonal. The
-- tetrahedron @Δ³ → A@ has a long diagonal from the first to the last vertex,
-- traced by the fully degenerate point @((t , t) , t)@. That diagonal is the
-- composite of all three arrows. Solution: restrict the tetrahedron to the main
-- diagonal, @tetrahedron … ((t , t) , t)@.
tripleCompLevel :: Level
tripleCompLevel = Level
  { levelTitle     = "The triple composite"
  , levelIntro     =
      "One arrow is left to read off. The tetrahedron's main diagonal runs from its first vertex $w$ to its last vertex $z$, traced by the fully degenerate point $((t,t),t)$. That diagonal *is* the composite $h\\circ g\\circ f$ of all three arrows. Introduce the interval coordinate and restrict the tetrahedron to its main diagonal."
      <> usefulHere
           [ "tetrahedron-associative-is-segal A is-segal-A w x y z f g h"
           , "  : Δ³ → A"
           , "-- the main diagonal is the point  ((t , t) , t)"
           ]
  , levelStatement = "hom A w z"
  , levelPrelude   = assocPreludeFor
      [ unfoldingSquareLevel, witnessSquareLevel, idArrLevel, arrInArrLevel
      , witnessAssocLevel, tetrahedronLevel ]
  , levelTemplate  = T.unlines
      [ "#def triple-comp-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : hom A w z"
      , "  := \\ t → tetrahedron-associative-is-segal A is-segal-A w x y z f g h (?)"
      ]
  , levelSolution  = T.unlines
      [ "#def triple-comp-is-segal"
      , "  (A : U) (is-segal-A : is-segal A) (w x y z : A)"
      , "  (f : hom A w x) (g : hom A x y) (h : hom A y z)"
      , "  : hom A w z"
      , "  := \\ t → tetrahedron-associative-is-segal A is-segal-A w x y z f g h ((t , t) , t)"
      ]
  , levelGoalName  = "triple-comp-is-segal"
  , levelGoalType  =
      "(A : U) → (is-segal-A : is-segal A) → (w : A) → (x : A) → (y : A) → (z : A) \
      \→ (f : hom A w x) → (g : hom A x y) → (h : hom A y z) → hom A w z"
  , levelInventory =
      [ "tetrahedron-associative-is-segal : the tetrahedron Δ³ → A"
      , "((t , t) , t) : the fully degenerate point, the main diagonal"
      ]
  , levelConclusion =
      "The triple composite is the tetrahedron's main diagonal. Its two faces exhibit it both as $(h\\circ g)\\circ f$ and as $h\\circ(g\\circ f)$; since a Segal type's composites are unique, the two bracketings agree. That is associativity — see the sHoTT chapter for the final equality."
  }
