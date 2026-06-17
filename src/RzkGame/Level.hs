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

import           Data.Char            (isAlpha)
import           Data.List            (sortOn)
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

-- | Smart inventory: the tap-to-refine moves offered for a focused hole,
-- derived from what is in scope and ranked by relevance to the goal. This
-- replaces hand-authored per-level actions.
--
-- Two sources feed the list. Term hypotheses come from the hole's context: a
-- function-like one is offered as @name ?@ (apply, leaving a hole for the
-- argument), an ordinary one as @name@ (give it directly). Cube coordinates come
-- from the hole's cube variables: rzk shows a pattern-bound point as its pattern
-- (e.g. @(t, s) : 2 × 2@), so each coordinate is one component name of that
-- binder.
--
-- Moves whose inserted name occurs in the goal are offered first.
holeActions :: HoleView -> [(Text, Text)]
holeActions HoleView{..} = sortOn relevance (termMoves <> cubeMoves)
  where
    termMoves =
      [ if applicable ty then ("refine " <> n, n <> " ?") else ("give " <> n, n)
      | (n, ty) <- hvContext
      , ty /= "U"   -- a type parameter is rarely the term that fills a hole
      ]
    -- We cannot read arity off the rendered type, so treat a hypothesis as
    -- applicable when its type is a function arrow or a hom (which unfolds to
    -- one). This is a heuristic, refined later if HoleInfo carries arity.
    applicable ty = "→" `T.isInfixOf` ty || "hom" `T.isInfixOf` ty

    -- Each cube variable's binder is shown as its pattern; the coordinates are
    -- its component names (a plain binder contributes just itself).
    cubeMoves =
      [ ("give " <> n, n) | (binder, _) <- hvCubeVars, n <- patternNames binder ]

    -- 0 sorts before 1: a move whose head name appears in the goal comes first.
    relevance (_, ins)
      | T.takeWhile (/= ' ') ins `T.isInfixOf` hvGoal = 0 :: Int
      | otherwise                                     = 1

-- | The atomic names of a (possibly pattern) binder as rzk renders it, e.g.
-- @(t, s)@ yields @["t", "s"]@ and a plain @t@ yields @["t"]@.
patternNames :: Text -> [Text]
patternNames = filter isIdent . T.split (`elem` (" \t\r\n(),|" :: String))
  where
    isIdent w = not (T.null w) && w /= "_" && isAlpha (T.head w)

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
