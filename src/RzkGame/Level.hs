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
  , MoveKind (..)
  , checkLevel
  , holeActions
  , refineFirstHole
  , renderResult
  ) where

import           Data.Char            (isSpace)
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
--
-- The insertion is parenthesised (see 'parenthesize') so an application spine or
-- a lambda cannot re-associate or fail to parse in the hole's position.
refineFirstHole :: Text -> Text -> Text
refineFirstHole insertion src =
  case T.breakOn "?" src of
    (_, after) | T.null after -> src
    (before, after)           -> before <> parenthesize insertion <> T.drop 1 after

-- | Wrap a refinement insertion in parentheses, unless it does not need them: a
-- bare atom (no internal whitespace, e.g. @x@, @refl@, @recBOT@) and a term that
-- is already a single parenthesised group (e.g. @(? , ?)@) are left as is. This
-- keeps the rewritten proof parseable without sprinkling redundant parentheses.
parenthesize :: Text -> Text
parenthesize ins
  | not (T.any isSpace s)             = ins
  | "(" `T.isPrefixOf` s && wrapsWhole s = ins
  | otherwise                         = "(" <> ins <> ")"
  where
    s = T.strip ins

-- | Does the leading @(@ of a string close only at its final character — i.e. is
-- the whole string a single parenthesised group, rather than two adjacent ones?
wrapsWhole :: Text -> Bool
wrapsWhole s = go (0 :: Int) 0 (T.unpack s)
  where
    n = T.length s
    go _ _ []           = False
    go depth i (c : cs) =
      let depth' = case c of '(' -> depth + 1; ')' -> depth - 1; _ -> depth
      in if depth' == 0 then i == n - 1 else go depth' (i + 1) cs

-- | The kind of a tap-to-fill move, used to colour-code the move button and
-- separate the move's kind from its filler term in the UI.
--
--   * 'Intro' builds a value of the goal by its constructor;
--   * 'Give' is an elimination spine over a hypothesis or a context-driven move.
data MoveKind = Intro | Give
  deriving (Eq, Show)

-- | Smart inventory: the tap-to-fill moves offered for a focused hole, computed
-- type-directed by rzk rather than by string heuristics here. Each move is its
-- 'MoveKind' paired with the filler term that is dropped onto the first @?@
-- (whose carried holes become the next moves):
--
--   * 'Intro' moves build a value of the goal by its constructor (rzk's
--     @holeIntroductions@): @\\ (t , s) → ?@, @(? , ?)@, @refl@, a tope
--     constructor, …;
--   * 'Give' moves are elimination spines over the hypotheses and context-driven
--     moves like @recBOT@ / @recOR@ (rzk's @holeCandidates@).
--
-- Introductions come first: they make progress on the goal's own structure,
-- which is usually what a fresh @?@ needs. We keep rzk's order within each kind
-- and only drop duplicates.
holeActions :: HoleView -> [(MoveKind, Text)]
holeActions HoleView{..} =
     [ (Intro, m) | m <- nub hvIntros ]
  <> [ (Give,  m) | m <- nub hvMoves ]

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
