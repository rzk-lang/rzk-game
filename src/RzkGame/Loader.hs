{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The game loader: decode a @game.json@ bundle and rebuild the @['Section']@
-- the engine consumes.
--
-- This is the second half of the Phase 3 data pipeline (the first is
-- 'RzkGame.Spec'). 'buildGame' is pure and total — every failure is reported as
-- a 'Left' message rather than an exception — so it is headlessly testable and
-- the wasm shim can fall back to the built-in 'RzkGame.Content' on any error.
-- Nothing downstream of the produced @['Section']@ changes: flattening, locking,
-- progress, and the whole UI are reused verbatim.
module RzkGame.Loader
  ( buildGame
  ) where

import           Data.Aeson      (eitherDecodeStrict')
import           Data.Bifunctor  (first)
import           Data.ByteString (ByteString)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import           RzkGame.Level   (Level (..))
import           RzkGame.Section
import           RzkGame.Spec

-- | Decode a @game.json@ bundle and assemble the sections. The bundle is the
-- JSON @{ "config": …, "files": … }@ produced by the native bundle step (see
-- 'Bundle'): the config is the @game.yaml@ as JSON, and the files map carries
-- every referenced @.rzk.md@ source inlined by path. We resolve each puzzle's
-- @file@ against that map, split it into prelude/template/solution, recover the
-- goal from the template, and fill the prose fields from the config.
buildGame :: ByteString -> Either Text [Section]
buildGame bs = do
  bundle <- first (("game.json: " <>) . T.pack) (eitherDecodeStrict' bs)
  traverse (sectionFrom (bundleFiles bundle)) (gsSections (bundleConfig bundle))

sectionFrom :: Map Text Text -> SectionSpec -> Either Text Section
sectionFrom files s = do
  items <- traverse (itemFrom files) (ssItems s)
  pure (Section (ssId s) (ssTitle s) items)

itemFrom :: Map Text Text -> ItemSpec -> Either Text SectionItem
itemFrom files = \case
  ItemProse  p -> SProse  <$> proseFrom files p
  ItemPuzzle p -> SPuzzle <$> puzzleFrom files p

proseFrom :: Map Text Text -> ProseSpec -> Either Text Prose
proseFrom files p = do
  txt <- case (psText p, psFile p) of
    (Just t, _)        -> Right t
    (Nothing, Just f)  -> resolve files f
    (Nothing, Nothing) ->
      Left ("prose `" <> psId p <> "` has neither `text` nor `file`")
  pure Prose
    { proseId    = psId p
    , proseTitle = psTitle p
    , proseRole  = psRole p >>= parseBoppps
    , proseText  = txt
    }

puzzleFrom :: Map Text Text -> PuzzleSpec -> Either Text PuzzleItem
puzzleFrom files p = do
  src                            <- resolve files (pzFile p)
  (prelude, template, solution)  <- splitLevelSource src
  (goalName, goalType)           <- goalFromTemplate template
  let lvl = Level
        { levelTitle      = pzTitle p
        , levelIntro      = pzIntro p
        , levelStatement  = pzStatement p
        , levelPrelude    = prelude
        , levelTemplate   = template
        , levelSolution   = solution
        , levelGoalName   = goalName
        , levelGoalType   = goalType
        , levelInventory  = pzInventory p
        , levelConclusion = pzConclusion p
        }
  pure PuzzleItem
    { puzzleLevel   = lvl
    , puzzleId      = pzId p
    , puzzleRole    = parseRole (pzRole p)
    , puzzlePrereqs = pzPrereqs p
    , puzzleRemedy  = map remedyFrom (pzRemedies p)
    }

-- | Look up an inlined file's contents by the path the spec refers to.
resolve :: Map Text Text -> Text -> Either Text Text
resolve files f =
  maybe (Left ("bundle is missing file: " <> f)) Right (Map.lookup f files)

-- | Map a curriculum role word to a 'LevelRole'; default 'Core' (also for an
-- unknown word, failing open rather than rejecting the whole game).
parseRole :: Maybe Text -> LevelRole
parseRole = \case
  Just "pretest" -> PreTest
  Just "extra"   -> Extra
  _              -> Core

-- | Map a BOPPPS tag word to a 'Boppps'; an unknown or absent word is no tag.
-- Tags are advisory (they only label a prose block), so a typo fails open.
parseBoppps :: Text -> Maybe Boppps
parseBoppps = \case
  "bridge-in"     -> Just BridgeIn
  "outcomes"      -> Just Outcomes
  "participatory" -> Just Participatory
  "post-test"     -> Just PostTest
  "summary"       -> Just Summary
  "note"          -> Just Note
  _               -> Nothing

-- | Build a 'Remedy' from its spec: the first target field present wins
-- (@section@, then @level@, then @url@); with none, a level pointer to the empty
-- id, which 'RzkGame.Section' resolves harmlessly to nothing.
remedyFrom :: RemedySpec -> Remedy
remedyFrom r = Remedy (rsLabel r) target
  where
    target = case (rsSection r, rsLevel r, rsUrl r) of
      (Just s, _, _) -> ToSection s
      (_, Just l, _) -> ToLevel l
      (_, _, Just u) -> ToExternal u
      _              -> ToLevel ""
