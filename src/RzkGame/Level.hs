{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The level model and the check against rzk.
--
-- A level is a read-only /prelude/ (already-checked definitions) plus an
-- /editable/ region the player fills in. Checking concatenates the two, parses
-- and typechecks the result in lenient hole mode, and classifies the outcome.
-- The player wins when the editable region typechecks with no remaining holes.
module RzkGame.Level
  ( Level (..)
  , CheckResult (..)
  , checkLevel
  , refineFirstHole
  , renderResult
  ) where

import           Data.Text            (Text)
import qualified Data.Text            as T

import           Language.Rzk.Syntax  (parseModule)
import           Rzk.Diagnostic       (ppHoleInfo)
import           Rzk.TypeCheck        (OutputDirection (BottomUp),
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
  , levelActions    :: [(Text, Text)]
      -- ^ tap-to-refine moves: @(button label, text inserted at the first hole)@
  , levelConclusion :: Text   -- ^ prose shown on success
  } deriving (Eq, Show)

-- | The outcome of checking an editable region against a level.
data CheckResult
  = NotChecked          -- ^ nothing checked yet
  | ParseError Text     -- ^ the source did not parse
  | TypeError Text      -- ^ a genuine type error (not just a hole)
  | Holes [Text]        -- ^ unsolved holes, each rendered with its goal + context
  | Solved              -- ^ typechecks with no remaining holes
  deriving (Eq, Show)

-- | Check an editable region against a level. The prelude is prepended, so the
-- player's text is checked in the context of the given definitions.
checkLevel :: Level -> Text -> CheckResult
checkLevel lvl editable =
  let src = levelPrelude lvl <> "\n" <> editable
  in case parseModule src of
       Left err -> ParseError err
       Right m  ->
         case typecheckModulesWithHoles [("level", m)] of
           Left err -> TypeError (T.pack (ppTypeErrorInScopedContext' BottomUp err))
           Right (_, _, holes)
             | null holes -> Solved
             | otherwise  -> Holes (map (T.pack . ppHoleInfo) holes)

-- | Tap-to-refine: replace the first hole (@?@) in the text with the given
-- insertion. This is how a tap turns into an edit — the engine re-checks the
-- rewritten text, so no engine-side refinement logic is needed. If there is no
-- hole, the text is returned unchanged.
refineFirstHole :: Text -> Text -> Text
refineFirstHole insertion src =
  case T.breakOn "?" src of
    (_, after) | T.null after -> src
    (before, after)           -> before <> insertion <> T.drop 1 after

-- | A plain-text rendering of a result, for self-tests and logs.
renderResult :: CheckResult -> Text
renderResult = \case
  NotChecked   -> "(not checked)"
  ParseError e -> "Parse error:\n" <> e
  TypeError e  -> "Type error:\n" <> e
  Holes hs     -> T.pack (show (length hs)) <> " hole(s):\n\n" <> T.intercalate "\n" hs
  Solved       -> "Solved: no holes, typechecks."
