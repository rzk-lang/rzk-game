{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The level model and the check against rzk.
--
-- A level is a read-only /prelude/ (already-checked definitions) plus an
-- /editable/ region the player fills in. Checking concatenates the two, parses
-- and typechecks the result in lenient hole mode, and classifies the outcome.
-- The player wins when the editable region typechecks with no remaining holes.
module RzkGame.Level
  ( Level (..)
  , CheckResult (..)
  , HoleView (..)
  , checkLevel
  , holeActions
  , refineFirstHole
  , renderResult
  ) where

import           Data.List            (nub)
import           Data.Text            (Text)
import qualified Data.Text            as T

import           Language.Rzk.Syntax  (parseModule)
import           Rzk.TypeCheck        (HoleEntry (..), HoleInfo (..),
                                       OutputDirection (BottomUp),
                                       ppTypeErrorInScopedContext',
                                       typecheckModulesWithHoles)

-- | A single level. The text fields are Rzk source or human-readable prose.
data Level = Level
  { levelTitle      :: Text   -- ^ short title
  , levelIntro      :: Text   -- ^ prose shown before the goal
  , levelStatement  :: Text   -- ^ the goal, human-readable
  , levelPrelude    :: Text   -- ^ read-only, pre-checked definitions
  , levelTemplate   :: Text   -- ^ the editable region's starting text (with a @?@)
  , levelSolution   :: Text   -- ^ a reference solution (for self-tests)
  , levelInventory  :: [Text] -- ^ names available to the player
  , levelConclusion :: Text   -- ^ prose shown on success
  } deriving (Eq, Show)

-- | The outcome of checking an editable region against a level.
data CheckResult
  = NotChecked          -- ^ nothing checked yet
  | ParseError Text     -- ^ the source did not parse
  | TypeError Text      -- ^ a genuine type error (not just a hole)
  | Holes [HoleView]    -- ^ unsolved holes, each with its goal + local context
  | Solved              -- ^ typechecks with no remaining holes
  deriving (Eq, Show)

-- | A single hole with every part pre-rendered to display text, so the UI can
-- lay it out as panels (goal / context / cube variables / topes) without
-- depending on rzk's internal term representation. The global environment is
-- deliberately excluded by rzk (it belongs in a searchable inventory, not the
-- goal panel); local hypotheses are split into term variables and cube
-- variables, matching the cube/tope layer of simplicial type theory.
data HoleView = HoleView
  { hvName     :: Maybe Text     -- ^ the @?name@, if the hole was named
  , hvGoal     :: Text           -- ^ the goal, shown as @(b : ty | tope)@ for a shape
  , hvContext  :: [(Text, Text)] -- ^ term hypotheses, as @(name, type)@
  , hvCubeVars :: [(Text, Text)] -- ^ cube variables, as @(name, type)@
  , hvTopes    :: [Text]         -- ^ tope assumptions
  , hvMoves    :: [Text]         -- ^ elimination/context moves (rzk's @holeCandidates@)
  , hvIntros   :: [Text]         -- ^ introduction moves (rzk's @holeIntroductions@)
  } deriving (Eq, Show)

-- | Convert rzk's structured 'HoleInfo' into a display-ready 'HoleView'. Each
-- field is already in user-facing names, so we just render it to text here.
toHoleView :: HoleInfo -> HoleView
toHoleView HoleInfo{..} = HoleView
  { hvName     = (\n -> "?" <> tshow n) <$> holeName
  , hvGoal     = case holeGoalShape of
      Nothing        -> tshow holeGoal
      Just (s, tope) -> "(" <> tshow s <> " : " <> tshow holeGoal
                          <> " | " <> tshow tope <> ")"
  , hvContext  = map entry holeTermVars
  , hvCubeVars = map entry holeCubeVars
  , hvTopes    = map tshow holeTopes
  , hvMoves    = map (humanize . tshow) holeCandidates
  , hvIntros   = map (humanize . tshow) holeIntroductions
  }
  where
    entry e = (tshow (holeEntryName e), tshow (holeEntryType e))

tshow :: Show a => a -> Text
tshow = T.pack . show

-- | Check an editable region against a level. The prelude is prepended, so the
-- player's text is checked in the context of the given definitions.
checkLevel :: Level -> Text -> CheckResult
checkLevel lvl editable =
  let src = levelPrelude lvl <> "\n" <> editable
  in case parseModule src of
       Left err -> ParseError err
       Right m  ->
         case typecheckModulesWithHoles [("level", m)] of
           -- A fatal error short-circuits to 'Left'; recoverable type errors
           -- (e.g. an unbound variable or a type mismatch) come back in the
           -- middle field. Both must be reported — only the holes-aware
           -- elaboration records unsolved holes separately. A real type error
           -- takes priority over any holes the partial term still has.
           Left err -> TypeError (ppErr err)
           Right (_, err : _, _) -> TypeError (ppErr err)
           Right (_, [], holes)
             | null holes -> Solved
             | otherwise  -> Holes (map toHoleView holes)
  where
    ppErr = T.pack . ppTypeErrorInScopedContext' BottomUp

-- | Tap-to-refine: replace the first hole (@?@) in the text with the given
-- insertion. This is how a tap turns into an edit — the engine re-checks the
-- rewritten text, so no engine-side refinement logic is needed. If there is no
-- hole, the text is returned unchanged.
refineFirstHole :: Text -> Text -> Text
refineFirstHole insertion src =
  case T.breakOn "?" src of
    (_, after) | T.null after -> src
    (before, after)           -> before <> insertion <> T.drop 1 after

-- | Smart inventory: the tap-to-fill moves offered for a focused hole, computed
-- type-directed by rzk rather than by string heuristics here. Two kinds, both
-- dropped onto the first @?@ (whose carried holes become the next moves):
--
--   * /introductions/ build a value of the goal by its constructor (rzk's
--     @holeIntroductions@): @\\ (t , s) → ?@, @(? , ?)@, @refl@, a tope
--     constructor, … — labelled @intro@;
--   * /gives/ are elimination spines over the hypotheses and context-driven
--     moves like @recBOT@ / @recOR@ (rzk's @holeCandidates@) — labelled @give@.
--
-- Introductions come first: they make progress on the goal's own structure,
-- which is usually what a fresh @?@ needs. We keep rzk's order within each kind
-- and only drop duplicates.
holeActions :: HoleView -> [(Text, Text)]
holeActions HoleView{..} =
     [ ("intro " <> m, m) | m <- nub hvIntros ]
  <> [ ("give "  <> m, m) | m <- nub hvMoves ]

-- | Render rzk's notation as the ASCII the levels use in prose and reference
-- solutions, so a tapped move reads the same as the text the player would type.
-- Projections @π₁@ / @π₂@ become @first@ / @second@, and the tope constants
-- @⊤@ / @⊥@ become @TOP@ / @BOT@. All forms parse in rzk either way; the other
-- tope operators (@≡@, @≤@, @∧@, @∨@, @↦@) already match the level notation.
--
-- The choices follow the sHoTT style guide's use-of-unicode conventions
-- (https://rzk-lang.github.io/sHoTT/STYLEGUIDE/#use-of-unicode-characters):
-- @first@ / @second@ and the @TOP@ / @BOT@ keywords are written in ASCII, while
-- the relational tope operators are kept in their unicode form.
humanize :: Text -> Text
humanize = T.replace "π₁" "first" . T.replace "π₂" "second"
         . T.replace "⊤" "TOP"    . T.replace "⊥" "BOT"

-- | A plain-text rendering of a result, for self-tests and logs.
renderResult :: CheckResult -> Text
renderResult = \case
  NotChecked   -> "(not checked)"
  ParseError e -> "Parse error:\n" <> e
  TypeError e  -> "Type error:\n" <> e
  Holes hs     -> tshow (length hs) <> " hole(s):\n\n"
                    <> T.intercalate "\n" (map renderHoleView hs)
  Solved       -> "Solved: no holes, typechecks."

-- | A plain-text rendering of a single hole, mirroring rzk's @ppHoleInfo@ for
-- the self-tests and logs.
renderHoleView :: HoleView -> Text
renderHoleView HoleView{..} = T.unlines $
  [ "Hole" <> maybe "" (" " <>) hvName
  , "  goal:"
  , "    " <> hvGoal
  ]
  <> section "context" hvContext
  <> section "cube variables" hvCubeVars
  <> (if null hvTopes then [] else "  tope context:" : map ("    " <>) hvTopes)
  where
    section title entries
      | null entries = []
      | otherwise = ("  " <> title <> ":")
          : [ "    " <> n <> " : " <> ty | (n, ty) <- entries ]
