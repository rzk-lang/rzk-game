{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}

-- | Sections: BOPPPS-style modules that group the puzzle levels with trackable
-- prose, optional pre-tests, prerequisites, and starred enrichment levels.
--
-- The design follows four guidelines (see the handoff note). BOPPPS structure is
-- /recommended, not mandatory/: a section is just an ordered list of items, each
-- of which may optionally carry a BOPPPS role tag. Prose items ("text
-- pseudo-levels") may appear anywhere — start, middle, or end — and count as
-- activities that the player /views/. Puzzle items carry a role (ordinary,
-- pre-test, or starred extra), prerequisites, and remediation pointers.
--
-- This module is deliberately pure (no miso, no rzk type-checking) so the slot
-- flattening, locking, and progress logic can be exercised headlessly.
module RzkGame.Section
  ( -- * Model
    Section (..)
  , SectionItem (..)
  , Prose (..)
  , Boppps (..)
  , PuzzleItem (..)
  , LevelRole (..)
  , Remedy (..)
  , RemedyTarget (..)
  , PretestAnswer (..)
    -- * Flattened navigation
  , Slot (..)
  , slotsOfSections
  , slotSectionId
  , puzzleSlots
  , lookupPuzzleSlot
    -- * Prerequisites and locking
  , prereqSatisfied
  , unmetPrereqs
  , levelLocked
    -- * Progress
  , slotRequired
  , slotDone
  , sectionSlots
  , sectionProgress
  , sectionComplete
  ) where

import           Data.List        (find)
import           Data.Map.Strict  (Map)
import qualified Data.Map.Strict  as Map
import           Data.Set         (Set)
import qualified Data.Set         as Set
import           Data.Text        (Text)

import           RzkGame.Level    (Level)

-- | A BOPPPS role tag. Tags are advisory only: they guide authoring and let the
-- UI label a prose block, but a section need not use any of them.
data Boppps = BridgeIn | Outcomes | Participatory | PostTest | Summary | Note
  deriving (Eq, Show)

-- | A text pseudo-level: Markdown/TeX prose that the player can read and that is
-- marked /viewed/ once visited. Carries a stable id (for view-tracking and the
-- prose-injection key) and a short title for the picker.
data Prose = Prose
  { proseId    :: Text          -- ^ stable id (view-tracking + InitProse key)
  , proseTitle :: Text          -- ^ short label for the picker / heading
  , proseRole  :: Maybe Boppps  -- ^ optional BOPPPS tag, for labelling only
  , proseText  :: Text          -- ^ Markdown/TeX source
  } deriving (Eq, Show)

-- | The role of a puzzle within its section.
--
--   * 'Core' levels are the participatory body; they gate section completion.
--   * 'PreTest' levels double as a pre-assessment: the player may /solve/ them
--     or self-report familiarity, and either satisfies them as a prerequisite.
--   * 'Extra' (★) levels are optional enrichment and do not gate completion.
data LevelRole = Core | PreTest | Extra
  deriving (Eq, Show)

-- | Where a remediation pointer sends a player who is missing a prerequisite.
data RemedyTarget
  = ToLevel    Text  -- ^ a puzzle id within the game
  | ToSection  Text  -- ^ a section id within the game
  | ToExternal Text  -- ^ an external URL
  deriving (Eq, Show)

-- | A labelled remediation pointer.
data Remedy = Remedy
  { remedyLabel  :: Text
  , remedyTarget :: RemedyTarget
  } deriving (Eq, Show)

-- | A puzzle placed in a section: a 'Level' plus its curriculum metadata. The
-- id is stable across reorderings; prerequisites reference other puzzles by id.
-- 'puzzleRemedy' is shown when this puzzle is a pre-test the player is unfamiliar
-- with, and to dependents that lock because of it.
data PuzzleItem = PuzzleItem
  { puzzleLevel   :: Level
  , puzzleId      :: Text
  , puzzleRole    :: LevelRole
  , puzzlePrereqs :: [Text]    -- ^ ids that must be satisfied to unlock this one
  , puzzleRemedy  :: [Remedy]
  } deriving (Eq, Show)

-- | One item in a section, in author order.
data SectionItem
  = SProse  Prose
  | SPuzzle PuzzleItem
  deriving (Eq, Show)

-- | A BOPPPS-style module: a titled, ordered list of items.
data Section = Section
  { sectionId    :: Text
  , sectionTitle :: Text
  , sectionItems :: [SectionItem]
  } deriving (Eq, Show)

-- | A player's self-assessment on a pre-test.
data PretestAnswer = Familiar | NotFamiliar
  deriving (Eq, Show)

-- | A flattened navigation slot. Prose slots carry their section id; puzzle
-- slots additionally carry the /global puzzle index/ — the position among
-- puzzles only, which is what progress and drafts are keyed by. Interleaving
-- prose does not consume puzzle indices, so persistence stays compatible.
data Slot
  = SlotProse  Text Prose          -- ^ section id, prose
  | SlotPuzzle Text Int PuzzleItem -- ^ section id, global puzzle index, puzzle
  deriving (Eq, Show)

-- | Flatten sections into the navigation sequence, numbering puzzles in order.
slotsOfSections :: [Section] -> [Slot]
slotsOfSections = go 0 . concatMap tag
  where
    tag s = map (sectionId s,) (sectionItems s)
    go _ [] = []
    go n ((sid, SProse  p) : rest) = SlotProse  sid p   : go n       rest
    go n ((sid, SPuzzle z) : rest) = SlotPuzzle sid n z : go (n + 1) rest

-- | The section a slot belongs to.
slotSectionId :: Slot -> Text
slotSectionId (SlotProse  sid _)   = sid
slotSectionId (SlotPuzzle sid _ _) = sid

-- | The puzzle slots, paired with their global puzzle index.
puzzleSlots :: [Slot] -> [(Int, PuzzleItem)]
puzzleSlots slots = [ (ix, z) | SlotPuzzle _ ix z <- slots ]

-- | Find a puzzle by id, with its global index.
lookupPuzzleSlot :: [Slot] -> Text -> Maybe (Int, PuzzleItem)
lookupPuzzleSlot slots pid = find ((== pid) . puzzleId . snd) (puzzleSlots slots)

-- | A prerequisite is satisfied when its puzzle is solved, or the player has
-- self-reported familiarity on it (the pre-test "I already know this" escape).
-- An unknown id is treated as satisfied, so a typo in a prereq list fails open
-- rather than locking a level forever.
prereqSatisfied :: [Slot] -> Set Int -> Map Text PretestAnswer -> Text -> Bool
prereqSatisfied slots solvedIxs answers pid =
  case lookupPuzzleSlot slots pid of
    Nothing      -> True
    Just (ix, _) -> Set.member ix solvedIxs
                 || Map.lookup pid answers == Just Familiar

-- | The prerequisites of a puzzle that are not yet satisfied, resolved to their
-- 'PuzzleItem's (so the UI can show their titles and remediation), in order.
unmetPrereqs
  :: [Slot] -> Set Int -> Map Text PretestAnswer -> PuzzleItem -> [PuzzleItem]
unmetPrereqs slots solvedIxs answers z =
  [ pz | pid <- puzzlePrereqs z, not (prereqSatisfied slots solvedIxs answers pid)
       , Just (_, pz) <- [lookupPuzzleSlot slots pid] ]

-- | Whether a puzzle is locked: a prerequisite is not yet satisfied and the
-- player has not overridden the lock ("Unlock anyway"). A prerequisite counts as
-- satisfied once solved (or marked familiar on its pre-test), so finishing the
-- prerequisites opens the level.
levelLocked
  :: [Slot] -> Set Int -> Set Text -> Map Text PretestAnswer -> PuzzleItem -> Bool
levelLocked slots solvedIxs overrides answers z =
  not (puzzleId z `Set.member` overrides)
    && not (null (unmetPrereqs slots solvedIxs answers z))

-- | Whether a slot counts toward section completion. Starred extras do not.
slotRequired :: Slot -> Bool
slotRequired (SlotProse  _ _)   = True
slotRequired (SlotPuzzle _ _ z) = puzzleRole z /= Extra

-- | Whether a slot's activity is done. Prose is done when viewed. A core puzzle
-- is done when solved; a pre-test is done when solved /or/ marked familiar (a
-- "not familiar" answer sends the player to remediation, so it is not yet done);
-- an extra is done when solved.
slotDone :: Set Int -> Set Text -> Map Text PretestAnswer -> Slot -> Bool
slotDone solvedIxs viewed answers = \case
  SlotProse  _ p    -> Set.member (proseId p) viewed
  SlotPuzzle _ ix z -> case puzzleRole z of
    Core    -> Set.member ix solvedIxs
    Extra   -> Set.member ix solvedIxs
    PreTest -> Set.member ix solvedIxs
                 || Map.lookup (puzzleId z) answers == Just Familiar

-- | The slots belonging to a section, in order.
sectionSlots :: [Slot] -> Text -> [Slot]
sectionSlots slots sid = filter ((== sid) . slotSectionId) slots

-- | @(done, total)@ over a section's /required/ slots.
sectionProgress
  :: [Slot] -> Set Int -> Set Text -> Map Text PretestAnswer -> Text -> (Int, Int)
sectionProgress slots solvedIxs viewed answers sid =
  let req = filter slotRequired (sectionSlots slots sid)
  in ( length (filter (slotDone solvedIxs viewed answers) req)
     , length req )

-- | Whether every required slot of a non-empty section is done.
sectionComplete
  :: [Slot] -> Set Int -> Set Text -> Map Text PretestAnswer -> Text -> Bool
sectionComplete slots solvedIxs viewed answers sid =
  let (d, t) = sectionProgress slots solvedIxs viewed answers sid
  in t > 0 && d == t
