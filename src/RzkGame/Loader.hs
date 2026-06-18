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
--
-- Each item joins two sources: the /placement/ metadata from the table of
-- contents (the curriculum role, prerequisites, remedies) and the /intrinsic/
-- metadata and prose from the referenced level file (its front-matter 'Meta' and
-- its body).
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
-- 'Bundle'): the config is the @game.yaml@ table of contents as JSON, and the
-- files map carries every referenced level file — front-matter parsed, body kept
-- — inlined by path. We resolve each item's @file@ against that map, read its
-- metadata and prose, split the puzzle body into prelude/template/solution,
-- recover the goal from the template, and add the placement metadata.
buildGame :: ByteString -> Either Text [Section]
buildGame bs = do
  bundle <- first (("game.json: " <>) . T.pack) (eitherDecodeStrict' bs)
  traverse (sectionFrom (bundleFiles bundle)) (gsSections (bundleConfig bundle))

sectionFrom :: Map Text FileSpec -> SectionSpec -> Either Text Section
sectionFrom files s = do
  items <- traverse (itemFrom files) (ssItems s)
  pure (Section (ssId s) (ssTitle s) items)

itemFrom :: Map Text FileSpec -> ItemSpec -> Either Text SectionItem
itemFrom files = \case
  ItemProse  ref -> SProse  <$> proseFrom files ref
  ItemPuzzle ref -> SPuzzle <$> puzzleFrom files ref

proseFrom :: Map Text FileSpec -> ProseRef -> Either Text Prose
proseFrom files ref = do
  f <- resolve files (prFile ref)
  let m = fileMeta f
  pure Prose
    { proseId    = metaId m
    , proseTitle = metaTitle m
    , proseRole  = metaRole m >>= parseBoppps
    , proseText  = T.strip (fileBody f)
    }

puzzleFrom :: Map Text FileSpec -> PuzzleRef -> Either Text PuzzleItem
puzzleFrom files ref = do
  f <- resolve files (puFile ref)
  let m    = fileMeta f
      body = fileBody f
  (prelude, template, solution) <- splitLevelSource body
  (goalName, goalType)          <- goalFromTemplate template
  let (intro, conclusion) = levelProse body
      lvl = Level
        { levelTitle      = metaTitle m
        , levelIntro      = intro
        , levelStatement  = metaStatement m
        , levelPrelude    = prelude
        , levelTemplate   = template
        , levelSolution   = solution
        , levelGoalName   = goalName
        , levelGoalType   = goalType
        , levelInventory  = metaInventory m
        , levelHints      = metaHints m
        , levelGated      = metaGated m
        , levelConclusion = conclusion
        }
  pure PuzzleItem
    { puzzleLevel   = lvl
    , puzzleId      = metaId m
    , puzzleRole    = parseRole (puRole ref)
    , puzzlePrereqs = puPrereqs ref
    , puzzleRemedy  = map remedyFrom (puRemedies ref)
    }

-- | Look up an inlined level file by the path the table of contents refers to.
resolve :: Map Text FileSpec -> Text -> Either Text FileSpec
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
