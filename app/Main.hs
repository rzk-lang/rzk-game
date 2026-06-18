{-# LANGUAGE CPP               #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The L0 user interface. Levels are grouped into BOPPPS-style /sections/, and
-- the player navigates a flat sequence of /slots/: prose pseudo-levels (text the
-- player reads and that is marked viewed) interleaved with puzzle levels. A
-- puzzle slot shows the textarea, the derived tap-to-refine moves, a Check
-- button, and the result panel. Pre-test puzzles add a self-assessment; a level
-- whose prerequisite the player marked "not familiar" is locked, with a gentle
-- "Unlock anyway" escape. Progress (solved puzzles, viewed prose, pre-test
-- answers, unlock overrides) is persisted to @localStorage@.
module Main (main) where

import           Miso
import qualified Miso.Html          as H
import qualified Miso.Html.Property as P
import qualified Miso.Svg           as S
import qualified Miso.Svg.Property  as SP
import           Miso.DSL           (jsg2)
import           Miso.Lens
import           Miso.String        (MisoString, fromMisoString, ms)

import           Data.List          (find)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (fromMaybe, mapMaybe)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import qualified Data.Text          as T
import           Text.Read          (readMaybe)

import           RzkGame.Content    (apHomLevel, composeLevel,
                                     composeWitnessLevel, constTriangleLevel,
                                     gameLevels, gameSections, gameSlots,
                                     hom2Level, homLeftUnitLevel, idMorphismLevel,
                                     mapPointLevel)
import           RzkGame.Highlight  (Tok (..), highlight, tokClassName)
import           RzkGame.Level
import           RzkGame.Section

-- | Inject rendered prose (Markdown/TeX via @prose.js@) into a div miso has just
-- created, given its 'DOMRef' from an @onCreatedWith@ hook.
--
-- The injected DOM lives entirely outside miso's virtual DOM: the div is an
-- empty leaf as far as miso is concerned, so writing its content here cannot
-- desync the diff (an earlier version injected via a vdom @innerHTML@ prop, which
-- crashed with a stale-DOM-ref @removeChild@ when the result panel restructured
-- on a solve). We call through the DSL's @jsg2@ rather than a raw @foreign
-- import@ because marshalling a @JSString@ argument directly trips a wasm codegen
-- bug.
renderProseInto :: DOMRef -> MisoString -> IO ()
renderProseInto ref src = do
  _ <- jsg2 "renderInto" ref src
  pure ()

-- | The navigation sequence and the sections, named once.
slots :: [Slot]
slots = gameSlots

-- | The total number of navigable slots (prose + puzzles).
totalSlots :: Int
totalSlots = length slots

-- | UI state. The current position is a /slot/ index; solved puzzles, viewed
-- prose, pre-test answers, and unlock overrides are persisted to @localStorage@.
data Model = Model
  { _slotIx   :: Int
  , _editable :: MisoString
  , _result   :: CheckResult
  , _solved   :: Set Int                  -- ^ solved puzzles, by global index
  , _viewed   :: Set T.Text               -- ^ viewed prose, by id
  , _pretest  :: Map T.Text PretestAnswer -- ^ pre-test self-assessments, by id
  , _unlocked :: Set T.Text               -- ^ "Unlock anyway" overrides, by id
  , _history  :: [MisoString]             -- ^ prior editable states, for Undo
  , _mapOpen  :: Bool                      -- ^ whether the full level map is shown
  } deriving (Eq)

slotIx :: Lens Model Int
slotIx = lens _slotIx $ \m v -> m { _slotIx = v }

editable :: Lens Model MisoString
editable = lens _editable $ \m v -> m { _editable = v }

result :: Lens Model CheckResult
result = lens _result $ \m v -> m { _result = v }

solved :: Lens Model (Set Int)
solved = lens _solved $ \m v -> m { _solved = v }

viewed :: Lens Model (Set T.Text)
viewed = lens _viewed $ \m v -> m { _viewed = v }

pretest :: Lens Model (Map T.Text PretestAnswer)
pretest = lens _pretest $ \m v -> m { _pretest = v }

unlocked :: Lens Model (Set T.Text)
unlocked = lens _unlocked $ \m v -> m { _unlocked = v }

history :: Lens Model [MisoString]
history = lens _history $ \m v -> m { _history = v }

mapOpen :: Lens Model Bool
mapOpen = lens _mapOpen $ \m v -> m { _mapOpen = v }

-- | The slot currently being shown.
currentSlot :: Model -> Slot
currentSlot m = slotAt (_slotIx m)

slotAt :: Int -> Slot
slotAt i = head (drop i slots)

-- | The global puzzle index of a slot, if it is a puzzle.
puzzleIndexAt :: Int -> Maybe Int
puzzleIndexAt i = case slotAt i of
  SlotPuzzle _ ix _ -> Just ix
  _                 -> Nothing

-- | Index the puzzle list by global index. (Miso's DSL re-exports @(!!)@ as a JS
-- property accessor, shadowing Prelude's list index, so we avoid it here.)
nthLevel :: Int -> Level
nthLevel i = head (drop i gameLevels)

tshow :: Show a => a -> T.Text
tshow = T.pack . show

data Action
  = SetEditable MisoString
  | Refine T.Text
  | Undo                       -- ^ revert the last tap-to-refine or Reset
  | Check
  | Reset
  | SelectSlot Int             -- ^ navigate to a slot (prose or puzzle)
  | ToggleMap                  -- ^ show/hide the full level map
  | Init                       -- ^ dispatched at mount: load saved state + draft
  | LoadState (Set Int) (Set T.Text) (Map T.Text PretestAnswer) (Set T.Text)
  | ApplyText Int MisoString   -- ^ install a puzzle's restored draft (by index)
  | SetPretest T.Text PretestAnswer  -- ^ record a pre-test self-assessment
  | Unlock T.Text              -- ^ override a lock ("Unlock anyway"), by puzzle id
  | InitProse MisoString DOMRef  -- ^ inject prose into a just-created div
  -- No 'Eq': 'DOMRef' (a 'JSVal') has none. miso does not require 'Eq' on actions.

main :: IO ()
#ifdef INTERACTIVE
main = live defaultEvents app
#else
main = startApp defaultEvents app
#endif

#ifdef WASM
#ifndef INTERACTIVE
foreign export javascript "hs_start"    main       :: IO ()
foreign export javascript "hs_selftest" hsSelftest :: IO ()

-- | Headless proof that the engine runs in wasm: for every level, check the
-- starting template (holes) and the reference solution (solved); then exercise
-- the first level's tap-to-refine, the type-error paths, the smart inventory,
-- and the section/locking/progress logic.
hsSelftest :: IO ()
hsSelftest = do
  flip mapM_ (zip [1 :: Int ..] gameLevels) $ \(n, lvl) -> do
    putStrLn ("== level " <> show n <> " template (expect holes) ==")
    putStrLn (T.unpack (renderResult (checkLevel lvl (levelTemplate lvl))))
    putStrLn ("== level " <> show n <> " solution (expect Solved) ==")
    putStrLn (T.unpack (renderResult (checkLevel lvl (levelSolution lvl))))
  putStrLn "== identity: intro λ → give x (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel idMorphismLevel
      (refineFirstHole "x" (refineFirstHole "\\ t → ?" (levelTemplate idMorphismLevel))))))
  putStrLn "== constant triangle: intro λ → give x (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel constTriangleLevel
      (refineFirstHole "x" (refineFirstHole "\\ (t, s) → ?" (levelTemplate constTriangleLevel))))))
  putStrLn "== intro moves: offered for the bare-hole templates =="
  let showMove (k, i) = (case k of Intro -> "intro "; Give -> "give ") <> i <> "  ↦  " <> i
      dumpIntros lvl = case checkLevel lvl (levelTemplate lvl) of
        Holes (h : _) ->
          mapM_ (\mv -> putStrLn ("   " <> T.unpack (showMove mv)))
                [ a | a@(k, _) <- holeActions h, k == Intro ]
        r -> putStrLn ("   (no holes: " <> T.unpack (renderResult r) <> ")")
  putStrLn "-- identity --"
  dumpIntros idMorphismLevel
  putStrLn "-- constant triangle --"
  dumpIntros constTriangleLevel
  putStrLn "== right-unit tap-to-refine: refine f → give t (expect Solved) =="
  let step1 = refineFirstHole "f ?" (levelTemplate hom2Level)
      step2 = refineFirstHole "t"   step1
  putStrLn (T.unpack (renderResult (checkLevel hom2Level step2)))
  putStrLn "== right-unit garbage: replace ? with asd (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel hom2Level (refineFirstHole "asd" (levelTemplate hom2Level)))))
  putStrLn "== right-unit wrong branch: give s (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel hom2Level (refineFirstHole "s" (levelTemplate hom2Level)))))
  putStrLn "== right-unit smart inventory: moves for the template hole =="
  case checkLevel hom2Level (levelTemplate hom2Level) of
    Holes (h : _) -> mapM_ (putStrLn . T.unpack . showMove) (holeActions h)
    r             -> putStrLn ("(expected holes, got " <> T.unpack (renderResult r) <> ")")
  putStrLn "== smart inventory: moves for every level's template hole =="
  let dumpMoves src lvl = case checkLevel lvl src of
        Holes (h : _) -> mapM_ (\mv -> putStrLn ("   " <> T.unpack (showMove mv)))
                               (holeActions h)
        r             -> putStrLn ("   (no holes: " <> T.unpack (renderResult r) <> ")")
  flip mapM_ (zip [1 :: Int ..] gameLevels) $ \(n, lvl) -> do
    putStrLn ("-- level " <> show n <> " (" <> T.unpack (levelTitle lvl) <> ") --")
    dumpMoves (levelTemplate lvl) lvl
  putStrLn "== smart inventory: inner-hole moves after the first refine =="
  putStrLn "-- right-unit after refine f --"
  dumpMoves (refineFirstHole "f ?" (levelTemplate hom2Level)) hom2Level
  putStrLn "-- ap-hom after refine f --"
  dumpMoves (refineFirstHole "f ?" (levelTemplate apHomLevel)) apHomLevel
  putStrLn "== left-unit tap-to-refine: refine f → give s (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel homLeftUnitLevel (refineFirstHole "s" (refineFirstHole "f ?" (levelTemplate homLeftUnitLevel))))))
  putStrLn "== map-point: give x inside g (?) (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel mapPointLevel (refineFirstHole "x" (levelTemplate mapPointLevel)))))
  putStrLn "== ap-hom tap-to-refine: refine f → give t inside g (?) (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel apHomLevel (refineFirstHole "t" (refineFirstHole "f ?" (levelTemplate apHomLevel))))))
  putStrLn "== compose: give first (first (is-segal-A x y z f g)) (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel composeLevel (refineFirstHole "first (first (is-segal-A x y z f g))" (levelTemplate composeLevel)))))
  putStrLn "== compose-witness: give second (first (is-segal-A x y z f g)) (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel composeWitnessLevel (refineFirstHole "second (first (is-segal-A x y z f g))" (levelTemplate composeWitnessLevel)))))
  -- The composition levels are now tappable: drop the projection spine offered by
  -- the smart inventory, then fill its five argument holes one tap each.
  let tapChain lvl insertions = checkLevel lvl (foldl (flip refineFirstHole) (levelTemplate lvl) insertions)
  putStrLn "== compose tap chain: spine then x y z f g (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain composeLevel ["first (first (is-segal-A ? ? ? ? ?))", "x", "y", "z", "f", "g"])))
  putStrLn "== compose-witness tap chain: spine then x y z f g (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain composeWitnessLevel ["second (first (is-segal-A ? ? ? ? ?))", "x", "y", "z", "f", "g"])))
  putStrLn "== soundness: an empty proof is never Solved (expect OK) =="
  putStrLn (if all (\lvl -> checkLevel lvl "" /= Solved) gameLevels
              then "empty-not-solved: OK" else "EMPTY-NOT-SOLVED FAILED")
  putStrLn "== soundness: a wrong-typed goal is not Solved (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel hom2Level "#def rut (A : U) : U := A")))
  putStrLn "== soundness: helper definitions are allowed (expect Solved) =="
  putStrLn (T.unpack (renderResult (checkLevel hom2Level (T.unlines
    [ "#def rut-edge (A : U) (x y : A) (f : hom A x y) : hom A x y := f"
    , "#def rut (A : U) (x y : A) (f : hom A x y)"
    , "  : hom2 A x y y f (id-hom A y) f"
    , "  := \\ (t , s) → rut-edge A x y f t"
    ]))))
  putStrLn "== L1 highlighter: lossless on every template (expect OK) =="
  let lossless lvl = T.concat [ tx | Tok _ tx <- highlight (levelTemplate lvl) ]
                       == levelTemplate lvl
  putStrLn (if all lossless gameLevels then "lossless: OK" else "LOSSLESS FAILED")
  putStrLn "== progress codec: encode/decode round-trips; junk is dropped =="
  let allSolved   = Set.fromList [0 .. length gameLevels - 1]
      roundTrips  = decodeSolved (encodeSolved allSolved) == allSolved
      emptyOk     = decodeSolved (encodeSolved Set.empty) == Set.empty
      junkDropped = decodeSolved "0,x,,2" == Set.fromList [0, 2]
  putStrLn (if roundTrips && emptyOk && junkDropped
              then "progress codec: OK" else "PROGRESS CODEC FAILED")
  putStrLn "== viewed codec: encode/decode round-trips =="
  let viewedSet  = Set.fromList ["morphisms-intro", "composition-assoc"]
      viewedOk   = decodeTextSet (encodeTextSet viewedSet) == viewedSet
      viewedEmpt = decodeTextSet (encodeTextSet Set.empty) == Set.empty
  putStrLn (if viewedOk && viewedEmpt then "viewed codec: OK" else "VIEWED CODEC FAILED")
  putStrLn "== pretest codec: encode/decode round-trips; junk is dropped =="
  let pt         = Map.fromList [("map-point", Familiar), ("compose", NotFamiliar)]
      ptOk       = decodePretest (encodePretest pt) == pt
      ptJunk     = decodePretest "map-point=familiar,x,bad=maybe" == Map.fromList [("map-point", Familiar)]
  putStrLn (if ptOk && ptJunk then "pretest codec: OK" else "PRETEST CODEC FAILED")
  putStrLn "== sections: derived gameLevels matches the section puzzle order (expect OK) =="
  let puzzleIds  = [ puzzleId z | SPuzzle z <- concatMap sectionItems gameSections ]
      orderOk    = puzzleIds == ["my-id", "const-triangle", "rut", "lut"
                                , "map-point", "ap-hom", "compose", "compose-witness"]
      derivedOk  = map levelTitle [ puzzleLevel z | SPuzzle z <- concatMap sectionItems gameSections ]
                     == map levelTitle gameLevels
  putStrLn (if orderOk && derivedOk then "section order: OK" else "SECTION ORDER FAILED")
  putStrLn "== locking: an unmet prerequisite locks its dependents (expect OK) =="
  let apHomItem  = maybe (error "no ap-hom") snd (lookupPuzzleSlot slots "ap-hom")
      mapPointIx = maybe (error "no map-point") fst (lookupPuzzleSlot slots "map-point")
      noAnswers  = Map.empty
      familiar   = Map.fromList [("map-point", Familiar)]
      solvedPre  = Set.fromList [mapPointIx]
      lockOk     = levelLocked slots Set.empty Set.empty noAnswers apHomItem            -- prereq unsolved: locked
                && not (levelLocked slots solvedPre Set.empty noAnswers apHomItem)      -- prereq solved: open
                && not (levelLocked slots Set.empty Set.empty familiar apHomItem)       -- marked familiar: open
                && not (levelLocked slots Set.empty (Set.fromList ["ap-hom"]) noAnswers apHomItem) -- override: open
  putStrLn (if lockOk then "locking: OK" else "LOCKING FAILED")
  putStrLn "== progress: a section completes only when its required slots are done (expect OK) =="
  let allIdx     = Set.fromList [0 .. length gameLevels - 1]
      allViewed  = Set.fromList [ proseId p | SProse p <- concatMap sectionItems gameSections ]
      -- 'morphisms' has a ★ extra (lut, index 3): solving only the core puzzles
      -- and viewing the prose should complete it.
      coreIdx    = Set.fromList [0, 1, 2]
      doneFull   = sectionComplete slots allIdx allViewed noAnswers "morphisms"
      doneCore   = sectionComplete slots coreIdx allViewed noAnswers "morphisms"
      notDoneRaw = not (sectionComplete slots Set.empty Set.empty noAnswers "morphisms")
      progOk     = doneFull && doneCore && notDoneRaw
  putStrLn (if progOk then "section progress: OK" else "SECTION PROGRESS FAILED")
#endif
#endif

app :: App Model Action
app = (component initModel updateModel viewModel)
  { mount = Just Init }   -- seed solved/viewed/pretest/unlock and the draft

initModel :: Model
initModel = enterSlotPure 0
  (Model 0 "" NotChecked Set.empty Set.empty Map.empty Set.empty [] False)

-- | Set up the model's editor for a slot, without IO. A puzzle slot loads its
-- template and checks it (so the focused hole and its moves show without a first
-- manual Check); a prose slot clears the editor. The undo history is reset.
enterSlotPure :: Int -> Model -> Model
enterSlotPure i m = case slotAt i of
  SlotProse _ _ ->
    m { _slotIx = i, _editable = "", _result = NotChecked, _history = [] }
  SlotPuzzle _ _ z ->
    let t = levelTemplate (puzzleLevel z)
    in m { _slotIx = i, _editable = ms t
         , _result = checkLevel (puzzleLevel z) t, _history = [] }

-- localStorage keys.
progressKey, viewedKey, pretestKey, unlockedKey :: MisoString
progressKey = "rzk-game-progress"
viewedKey   = "rzk-game-viewed"
pretestKey  = "rzk-game-pretest"
unlockedKey = "rzk-game-unlocked"

-- | The solved set is stored as a comma-separated list of level indices, e.g.
-- @"0,1"@. Unparseable or out-of-range entries are dropped on load, so a stale
-- value from an older level list cannot crash the game.
encodeSolved :: Set Int -> MisoString
encodeSolved = ms . T.intercalate "," . map (T.pack . show) . Set.toList

decodeSolved :: MisoString -> Set Int
decodeSolved =
  Set.fromList . mapMaybe (readMaybe . T.unpack) . T.splitOn "," . fromMisoString

-- | A set of ids (viewed prose, unlock overrides) as a comma-separated list. Ids
-- are kebab-case and contain no commas, so the source needs no escaping.
encodeTextSet :: Set T.Text -> MisoString
encodeTextSet = ms . T.intercalate "," . Set.toList

decodeTextSet :: MisoString -> Set T.Text
decodeTextSet =
  Set.fromList . filter (not . T.null) . T.splitOn "," . fromMisoString

-- | Pre-test answers as @id=familiar@ / @id=notfamiliar@ pairs. Junk is dropped.
encodePretest :: Map T.Text PretestAnswer -> MisoString
encodePretest = ms . T.intercalate "," . map enc . Map.toList
  where
    enc (k, v) = k <> "=" <> ans v
    ans Familiar    = "familiar"
    ans NotFamiliar = "notfamiliar"

decodePretest :: MisoString -> Map T.Text PretestAnswer
decodePretest = Map.fromList . mapMaybe dec . T.splitOn "," . fromMisoString
  where
    dec s = case T.splitOn "=" s of
      [k, "familiar"]    | not (T.null k) -> Just (k, Familiar)
      [k, "notfamiliar"] | not (T.null k) -> Just (k, NotFamiliar)
      _                                   -> Nothing

readProgress :: IO (Set Int)
readProgress = maybe Set.empty decodeSolved <$> getLocalStorage progressKey

saveProgress :: Set Int -> IO ()
saveProgress = setLocalStorage progressKey . encodeSolved

readViewed :: IO (Set T.Text)
readViewed = maybe Set.empty decodeTextSet <$> getLocalStorage viewedKey

saveViewed :: Set T.Text -> IO ()
saveViewed = setLocalStorage viewedKey . encodeTextSet

readPretest :: IO (Map T.Text PretestAnswer)
readPretest = maybe Map.empty decodePretest <$> getLocalStorage pretestKey

savePretest :: Map T.Text PretestAnswer -> IO ()
savePretest = setLocalStorage pretestKey . encodePretest

readUnlocked :: IO (Set T.Text)
readUnlocked = maybe Set.empty decodeTextSet <$> getLocalStorage unlockedKey

saveUnlocked :: Set T.Text -> IO ()
saveUnlocked = setLocalStorage unlockedKey . encodeTextSet

-- | Per-level draft storage. Each puzzle's in-progress text is saved under its
-- own key, so the raw source needs no escaping (unlike a single packed value).
-- A draft for a level no longer in the list simply lingers, harmlessly unread.
draftKey :: Int -> MisoString
draftKey i = "rzk-game-draft-" <> ms (show i)

saveDraft :: Int -> MisoString -> IO ()
saveDraft i = setLocalStorage (draftKey i)

removeDraft :: Int -> IO ()
removeDraft = removeLocalStorage . draftKey

-- | Read a puzzle's saved draft, falling back to its template when none is
-- stored, and return the action that installs it. The index is carried so the
-- update can ignore a stale read after a quick navigation.
loadDraftAction :: Int -> IO Action
loadDraftAction i =
  ApplyText i . fromMaybe (ms (levelTemplate (nthLevel i))) <$> getLocalStorage (draftKey i)


updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  SetEditable s -> do
    editable .= s
    mix <- currentPuzzleIx
    case mix of
      Just ix -> io_ (saveDraft ix s)
      Nothing -> pure ()
  ToggleMap -> mapOpen %= not
  SelectSlot i -> do
    history .= []
    slotIx  .= i
    mapOpen .= False         -- collapse the map after a jump, back to content
    case slotAt i of
      SlotProse _ p -> do
        editable .= ""
        result   .= NotChecked
        viewed %= Set.insert (proseId p)
        v <- use viewed
        io_ (saveViewed v)
      SlotPuzzle _ ix z -> do
        let t = levelTemplate (puzzleLevel z)
        editable .= ms t
        result   .= checkLevel (puzzleLevel z) t
        io (loadDraftAction ix)
  Reset -> withPuzzle $ \ix -> do
    e <- use editable
    history %= (e :)         -- a mistaken Reset can be undone
    let t = levelTemplate (nthLevel ix)
    editable .= ms t
    result   .= checkLevel (nthLevel ix) t
    io_ (removeDraft ix)     -- drop the draft so the template stays on next load
  Init -> do
    io (LoadState <$> readProgress <*> readViewed <*> readPretest <*> readUnlocked)
    mix <- currentPuzzleIx
    case mix of
      Just ix -> io (loadDraftAction ix)  -- a puzzle slot 0: restore its draft
      Nothing -> pure ()                  -- a prose slot 0: LoadState marks it viewed
  LoadState s v pt u -> do
    solved   .= s
    pretest  .= pt
    unlocked .= u
    -- If slot 0 is prose, it has already been "visited" at mount, so fold it in.
    i <- use slotIx
    let v' = case slotAt i of
               SlotProse _ p -> Set.insert (proseId p) v
               _             -> v
    viewed .= v'
    if v' /= v then io_ (saveViewed v') else pure ()
  SetPretest pid ans -> do
    pretest %= Map.insert pid ans
    pt <- use pretest
    io_ (savePretest pt)
  Unlock pid -> do
    unlocked %= Set.insert pid
    u <- use unlocked
    io_ (saveUnlocked u)
  InitProse src ref -> io_ (renderProseInto ref src)
  ApplyText i s -> do
    -- Ignore a draft that arrived after the player moved to another slot.
    mix <- currentPuzzleIx
    if mix == Just i
      then do
        editable .= s
        result   .= checkLevel (nthLevel i) (fromMisoString s)
      else pure ()
  Refine ins -> withPuzzle $ \ix -> do
    e <- use editable
    history %= (e :)         -- remember the pre-refine text so the tap can be undone
    let e'  = refineFirstHole ins (fromMisoString e)
        res = checkLevel (nthLevel ix) e'
    editable .= ms e'
    result   .= res
    io_ (saveDraft ix (ms e'))
    recordSolved ix res
  Undo -> do
    hs  <- use history
    mix <- currentPuzzleIx
    case (hs, mix) of
      (prev : rest, Just ix) -> do
        history  .= rest
        editable .= prev
        result   .= checkLevel (nthLevel ix) (fromMisoString prev)
        io_ (saveDraft ix prev)
      _ -> pure ()
  Check -> withPuzzle $ \ix -> do
    e <- use editable
    let res = checkLevel (nthLevel ix) (fromMisoString e)
    result .= res
    recordSolved ix res
  where
    -- The current slot's global puzzle index, if it is a puzzle.
    currentPuzzleIx = do
      i <- use slotIx
      pure (puzzleIndexAt i)

    -- Run an action only when the current slot is a puzzle, passing its index.
    withPuzzle k = do
      mix <- currentPuzzleIx
      case mix of
        Just ix -> k ix
        Nothing -> pure ()

    -- On a solved puzzle, record it and persist the updated set. We only write to
    -- storage when the set actually changes, to avoid redundant re-checks.
    recordSolved i Solved = do
      s <- use solved
      if Set.member i s
        then pure ()
        else do
          let s' = Set.insert i s
          solved .= s'
          io_ (saveProgress s')
    recordSolved _ _ = pure ()

viewModel :: props -> Model -> View Model Action
viewModel _ m =
  H.div_ []
    [ H.header_ [ P.class_ "game" ]
        [ H.h1_ [] [ text "Rzk Game" ]
        , H.p_ [ P.class_ "tagline" ]
            [ text "An interactive Rzk proof game — fill the holes." ]
        ]
    , navHeader m
    , H.section_ [ P.class_ "level" ]
        ( case currentSlot m of
            SlotProse  sid p    -> proseSlotView  m sid p
            SlotPuzzle sid ix z -> puzzleSlotView m sid ix z
        )
    ]

-- | A thin, sticky bar that keeps the level content in focus: it shows where the
-- player is and the overall progress, with a toggle that reveals the full level
-- map on demand. The map is hidden by default and collapses again after a jump.
navHeader :: Model -> View Model Action
navHeader m =
  H.div_ [ P.class_ (ms ("mapbar-wrap" <> if open then " open" else "" :: T.Text)) ]
    [ H.div_ [ P.class_ "mapbar" ]
        [ H.button_ [ P.class_ "map-toggle", H.onClick ToggleMap ]
            [ text (if open then "✕  Close map" else "☰  Levels") ]
        , H.span_ [ P.class_ "mapbar-loc" ]
            [ text (ms (sectionTitleOf (slotSectionId (currentSlot m)))) ]
        , H.span_ [ P.class_ (ms (progCls :: T.Text)) ]
            [ text (ms (tshow done <> " / " <> tshow total)) ]
        ]
    , if open then levelMap m else text ""
    ]
  where
    open          = m ^. mapOpen
    (done, total) = overallProgress m
    progCls       = "mapbar-progress" <> if done == total && total > 0 then " done" else ""

-- | The section title for a section id (empty if unknown).
sectionTitleOf :: T.Text -> T.Text
sectionTitleOf sid = maybe "" sectionTitle (find ((== sid) . sectionId) gameSections)

-- | The grouped level map: each section is a titled block with its progress count
-- and a row of slot buttons. Shown only when the map is open. Navigation stays
-- free — every slot is always reachable; locking only affects a puzzle page.
levelMap :: Model -> View Model Action
levelMap m =
  H.div_ [ P.class_ "sections" ] (map sectionBlock gameSections)
  where
    indexed = zip [0 ..] slots
    sectionBlock sec =
      let sid       = sectionId sec
          mine      = [ (i, s) | (i, s) <- indexed, slotSectionId s == sid ]
          (d, t)    = sectionProgress slots (m ^. solved) (m ^. viewed) (m ^. pretest) sid
      in H.div_ [ P.class_ "section-block" ]
           [ H.div_ [ P.class_ "section-head" ]
               [ H.span_ [ P.class_ "section-title" ] [ text (ms (sectionTitle sec)) ]
               , H.span_ [ P.class_ (ms (countCls d t)) ]
                   [ text (ms (tshow d <> " / " <> tshow t)) ]
               ]
           , H.div_ [ P.class_ "levels" ] (map (slotButton m) mine)
           ]
    countCls :: Int -> Int -> T.Text
    countCls d t = "section-count" <> if d == t && t > 0 then " done" else ""

-- | One slot tile: a compact rounded square whose icon names the item's role
-- (prose, ordinary puzzle, pre-test, or a starred extra), with the puzzle's
-- number in the corner. State — current, viewed/solved, locked — is carried by
-- the tile's classes; the full label lives in the @title@ tooltip, so the map
-- stays succinct as sections and items grow. A locked tile shows a padlock.
slotButton :: Model -> (Int, Slot) -> View Model Action
slotButton m (i, s) =
  H.button_
    [ H.onClick (SelectSlot i)
    , P.class_ (ms (T.unwords ("tile" : classes)))
    , P.title_ (ms tip)
    ]
    (icon : numBadge)
  where
    current = i == _slotIx m
    (classes, icon, numBadge, tip) = case s of
      SlotProse _ p ->
        let v = Set.member (proseId p) (m ^. viewed)
        in ( ["tile-prose"] <> [ "current" | current ] <> [ "done" | v ]
           , icoProse, [], proseTitle p )
      SlotPuzzle _ ix z ->
        let star    = puzzleRole z == Extra
            pre     = puzzleRole z == PreTest
            solvedThis = Set.member ix (m ^. solved)
            familiar   = pre && Map.lookup (puzzleId z) (m ^. pretest) == Just Familiar
            doneThis   = solvedThis || familiar
            locked = levelLocked slots (m ^. solved) (m ^. unlocked) (m ^. pretest) z
            roleCls | star      = "tile-star"
                    | pre       = "tile-pretest"
                    | otherwise = "tile-core"
            ico | locked    = icoLock
                | star      = icoStar
                | pre       = icoPretest
                | otherwise = icoCore
            note | star      = " (extra)"
                 | pre       = " (pre-test)"
                 | otherwise = ""
        in ( [roleCls] <> [ "current" | current ]
                       <> [ "solved" | doneThis ] <> [ "tile-locked" | locked ]
           , ico
           , [ H.span_ [ P.class_ "tile-num" ] [ text (ms (tshow (ix + 1))) ] ]
           , tshow (ix + 1) <> ". " <> levelTitle (puzzleLevel z) <> note )

-- | The role icons, drawn as inline SVG so they inherit the tile's colour
-- (@currentColor@) and stay crisp at any size. Each icon is a single @<path>@,
-- so swapping one role icon for another (e.g. a puzzle that becomes locked) only
-- changes attributes — miso never restructures the SVG subtree. Sizing comes from
-- CSS (@.tile svg@), so the per-icon @viewBox@ just frames the path.
svgIcon :: MisoString -> MisoString -> View Model Action
svgIcon vb d =
  S.svg_ [ SP.viewBox_ vb, SP.fill_ "currentColor" ] [ S.path_ [ SP.d_ d ] ]

-- text lines (a document)
icoProse :: View Model Action
icoProse = svgIcon "0 0 24 24" "M5 6 H19 V8.5 H5 Z M5 10.75 H19 V13.25 H5 Z M5 15.5 H14 V18 H5 Z"

-- a node (a filled disc)
icoCore :: View Model Action
icoCore = svgIcon "0 0 24 24" "M12 7 A5 5 0 1 0 12 17 A5 5 0 1 0 12 7 Z"

-- a diamond (a checkpoint)
icoPretest :: View Model Action
icoPretest = svgIcon "0 0 24 24" "M12 3 L21 12 L12 21 L3 12 Z"

-- a five-point star
icoStar :: View Model Action
icoStar = svgIcon "0 0 24 24"
  "M12 2 L14.7 8.6 L21.8 9.2 L16.4 13.9 L18 20.8 L12 17.1 L6 20.8 L7.6 13.9 L2.2 9.2 L9.3 8.6 Z"

-- a padlock (Bootstrap Icons "lock-fill", MIT-licensed, a single filled path)
icoLock :: View Model Action
icoLock = svgIcon "0 0 16 16"
  "M8 1a2 2 0 0 1 2 2v4H6V3a2 2 0 0 1 2-2m3 6V3a3 3 0 0 0-6 0v4a2 2 0 0 1-2 2v5a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V9a2 2 0 0 1-2-2"

-- | @(done, total)@ over every required slot of the game.
overallProgress :: Model -> (Int, Int)
overallProgress m =
  let req = filter slotRequired slots
  in ( length (filter (slotDone (m ^. solved) (m ^. viewed) (m ^. pretest)) req)
     , length req )

-- | A section breadcrumb shown atop each slot page: the section title and its
-- "k / n done" count.
breadcrumb :: Model -> T.Text -> View Model Action
breadcrumb m sid =
  H.p_ [ P.class_ "breadcrumb" ]
    [ text (ms (title <> " · " <> tshow d <> " / " <> tshow t <> " done")) ]
  where
    title  = maybe "" sectionTitle (find ((== sid) . sectionId) gameSections)
    (d, t) = sectionProgress slots (m ^. solved) (m ^. viewed) (m ^. pretest) sid

-- | A prose pseudo-level page: the rendered text, a viewed mark, and a section
-- "complete" badge when reaching it finishes the section.
proseSlotView :: Model -> T.Text -> Prose -> [View Model Action]
proseSlotView m sid p =
  [ breadcrumb m sid
  , H.h2_ []
      [ text (ms ((if isViewed then "✓ " else "") <> roleLabel (proseRole p) <> proseTitle p)) ]
  -- Prose is injected on creation (see InitProse); miso keeps this div an empty
  -- leaf. Keyed by slot so the hook re-fires when the page changes.
  , H.div_ [ P.class_ "prose prose-page"
           , key_ (ms ("prose-" <> show (_slotIx m)))
           , onCreatedWith (InitProse (ms (proseText p)))
           ] []
  , H.p_ [ P.class_ "viewed-note" ]
      [ text (if isViewed then "✓ Read" else "") ]
  , sectionDoneBadge m sid
  , navBar m
  ]
  where
    isViewed = Set.member (proseId p) (m ^. viewed)

-- | A small BOPPPS label for a prose heading, when the block carries a tag.
roleLabel :: Maybe Boppps -> T.Text
roleLabel = \case
  Nothing            -> ""
  Just BridgeIn      -> "Intro · "
  Just Outcomes      -> "Outcomes · "
  Just Participatory -> ""
  Just PostTest      -> "Check · "
  Just Summary       -> "Summary · "
  Just Note          -> "Note · "

-- | A puzzle page: goal, prelude, then either the editor (with moves, buttons,
-- result, and conclusion) or a lock panel. Pre-test puzzles add a self-assessment.
puzzleSlotView :: Model -> T.Text -> Int -> PuzzleItem -> [View Model Action]
puzzleSlotView m sid ix z =
  [ breadcrumb m sid
  , H.h2_ [] [ text (ms (titleMark <> levelTitle lvl <> roleSuffix)) ]
  -- Level intro prose, injected on creation; keyed by slot so it re-fires.
  , H.div_ [ P.class_ "prose"
           , key_ (ms ("intro-" <> show (_slotIx m)))
           , onCreatedWith (InitProse (ms (levelIntro lvl)))
           ] []
  , H.h3_ [] [ text "Goal" ]
  , H.pre_ [ P.class_ "goal" ] [ text (ms (levelStatement lvl)) ]
  , preludeView lvl
  ]
  <> body
  <> [ advanceView m, navBar m ]
  where
    lvl       = puzzleLevel z
    locked    = levelLocked slots (m ^. solved) (m ^. unlocked) (m ^. pretest) z
    titleMark = if Set.member ix (m ^. solved) then "✓ " else ""
    roleSuffix = case puzzleRole z of
      Extra   -> " ★"
      PreTest -> " — pre-test"
      Core    -> ""
    body
      | locked    = [ lockPanel m z ]
      | otherwise =
          pretestControls m z
          <> [ H.h3_ [] [ text "Your proof" ]
             , editorView (m ^. editable)
             , H.h3_ [] [ text "Moves" ]
             , movesView m
             , H.div_ [ P.class_ "buttons" ]
                 [ H.button_ [ P.class_ "primary", H.onClick Check ] [ text "Check" ]
                 , H.button_ ( [ P.class_ "secondary", H.onClick Undo ]
                                 <> [ P.disabled_ | null (m ^. history) ] )
                     [ text "Undo" ]
                 , H.button_ [ P.class_ "secondary", H.onClick Reset ] [ text "Reset" ]
                 ]
             , H.h3_ [] [ text "Result" ]
             , resultView (m ^. result)
             , conclusionView m lvl
             ]

-- | The self-assessment for a pre-test puzzle: two buttons, the current choice
-- highlighted, and a remediation box if the player said they are not familiar.
pretestControls :: Model -> PuzzleItem -> [View Model Action]
pretestControls m z
  | puzzleRole z /= PreTest = []
  | otherwise =
      [ H.div_ [ P.class_ "pretest" ]
          ( [ H.p_ [ P.class_ "pretest-q" ]
                [ text "Pre-test — are you already comfortable with this idea?" ]
            , H.div_ [ P.class_ "pretest-btns" ]
                [ choice Familiar    "I already know this"
                , choice NotFamiliar "Not familiar yet"
                ]
            ]
            <> case ans of
                 Just NotFamiliar ->
                   [ remedyBox "No problem — review this first, then come back:"
                               (puzzleRemedy z) ]
                 _ -> [] )
      ]
  where
    ans = Map.lookup (puzzleId z) (m ^. pretest)
    choice a lbl =
      H.button_ [ P.class_ (ms (("pretest-btn" <> if ans == Just a then " chosen" else "") :: T.Text))
                , H.onClick (SetPretest (puzzleId z) a) ]
        [ text lbl ]

-- | The lock panel shown in place of the editor when a prerequisite is not yet
-- met. It names the unmet prerequisites, offers a jump to each (and any
-- remediation), and an "Unlock anyway" escape so a player is never trapped.
lockPanel :: Model -> PuzzleItem -> View Model Action
lockPanel m z =
  H.div_ [ P.class_ "locked" ]
    ( [ H.p_ [] [ text (ms msg) ]
      , H.div_ [ P.class_ "lock-jumps" ] (map jumpTo blockers)
      ]
      <> [ remedyBox "Recommended before this level:" remedies | not (null remedies) ]
      <> [ H.button_ [ P.class_ "secondary", H.onClick (Unlock (puzzleId z)) ]
             [ text "Unlock anyway" ] ]
    )
  where
    blockers = unmetPrereqs slots (m ^. solved) (m ^. pretest) z
    remedies = concatMap puzzleRemedy blockers
    names    = T.intercalate ", " (map (levelTitle . puzzleLevel) blockers)
    msg      = "🔒 Locked — finish " <> names <> " first."
    jumpTo pz = case puzzleSlotIndex (puzzleId pz) of
      Just i  -> H.button_ [ P.class_ "remedy-link", H.onClick (SelectSlot i) ]
                   [ text (ms ("Go to: " <> levelTitle (puzzleLevel pz))) ]
      Nothing -> text ""

-- | A box of remediation links. External targets are anchors; in-game targets
-- are buttons that navigate to the relevant slot.
remedyBox :: T.Text -> [Remedy] -> View Model Action
remedyBox heading rs
  | null rs   = text ""
  | otherwise =
      H.div_ [ P.class_ "remedy" ]
        ( H.p_ [ P.class_ "remedy-head" ] [ text (ms heading) ]
        : map remedyLink rs )

remedyLink :: Remedy -> View Model Action
remedyLink (Remedy lbl tgt) = case tgt of
  ToExternal url ->
    H.a_ [ P.href_ (ms url), P.target_ "_blank", P.class_ "remedy-link" ]
      [ text (ms lbl) ]
  ToSection sid -> jump (sectionFirstSlot sid)
  ToLevel pid   -> jump (puzzleSlotIndex pid)
  where
    jump = \case
      Just i  -> H.button_ [ P.class_ "remedy-link", H.onClick (SelectSlot i) ]
                   [ text (ms lbl) ]
      Nothing -> H.span_ [ P.class_ "remedy-link" ] [ text (ms lbl) ]

-- | The slot index of the first item in a section / of a puzzle by id.
sectionFirstSlot :: T.Text -> Maybe Int
sectionFirstSlot sid =
  fst <$> find ((== sid) . slotSectionId . snd) (zip [0 ..] slots)

puzzleSlotIndex :: T.Text -> Maybe Int
puzzleSlotIndex pid = fst <$> find (isPuz . snd) (zip [0 ..] slots)
  where
    isPuz (SlotPuzzle _ _ z) = puzzleId z == pid
    isPuz _                  = False

-- | A "section complete" badge, shown on a prose page once every required slot
-- of the section is done (so a summary block doubles as a completion marker).
sectionDoneBadge :: Model -> T.Text -> View Model Action
sectionDoneBadge m sid
  | sectionComplete slots (m ^. solved) (m ^. viewed) (m ^. pretest) sid =
      H.p_ [ P.class_ "section-complete" ]
        [ text (ms ("🎉 Section complete: " <> title)) ]
  | otherwise = text ""
  where
    title = maybe "" sectionTitle (find ((== sid) . sectionId) gameSections)

-- | The level's read-only prelude. It is reference material, not the focus, so
-- it is collapsed by default; opening it reveals the given definitions,
-- syntax-highlighted with the same tokeniser as the editor.
preludeView :: Level -> View Model Action
preludeView lvl =
  H.details_ [ P.class_ "prelude-wrap" ]
    [ H.summary_ [] [ text "Prelude (given)" ]
    , H.pre_ [ P.class_ "prelude" ]
        [ H.span_ [ P.class_ (ms (tokClassName cls)) ] [ text (ms txt) ]
        | Tok cls txt <- highlight (levelPrelude lvl)
        ]
    ]

-- | The L1 editor: a transparent textarea over a syntax-highlighted @<pre>@.
-- The pre is absolutely positioned to fill the wrapper, which is sized by the
-- textarea, so the two stay the same height (even on manual resize). Both share
-- identical metrics in CSS, so the coloured layer lines up with the text the
-- player types. The tokeniser is lossless, so no character is dropped or added.
editorView :: MisoString -> View Model Action
editorView code =
  H.div_ [ P.class_ "editor-wrap" ]
    [ H.pre_ [ P.class_ "editor-hl" ]
        [ H.span_ [ P.class_ (ms (tokClassName cls)) ] [ text (ms txt) ]
        | Tok cls txt <- highlight (fromMisoString code)
        ]
    , H.textarea_
        [ P.class_ "editor"
        , P.rows_ "6"
        , P.value_ code
        , H.onInput SetEditable
        ]
    ]

-- | The smart-inventory moves for the focused hole (the first unsolved one),
-- derived from the current result. There is nothing to refine when the proof is
-- solved, errs, or has not been checked.
movesView :: Model -> View Model Action
movesView m =
  case m ^. result of
    Holes (h : _)
      | moves@(_ : _) <- holeActions h ->
          H.div_ [ P.class_ "actions" ]
            [ moveButton kind ins | (kind, ins) <- moves ]
    _ -> H.p_ [ P.class_ "muted" ] [ text "Moves appear here when a hole is in focus." ]

-- | A two-part move button: a colour-coded chip naming the move kind (intro /
-- give), then the filler term rendered with the same syntax highlighting as the
-- editor. Splitting the two keeps the kind and the term glanceable, rather than
-- running them together into one contiguous string.
moveButton :: MoveKind -> T.Text -> View Model Action
moveButton kind ins =
  H.button_ [ P.class_ "refine", H.onClick (Refine ins) ]
    [ H.span_ [ P.class_ (ms ("move-kind " <> kindClass)) ] [ text (ms kindLabel) ]
    , H.span_ [ P.class_ "move-term" ]
        [ H.span_ [ P.class_ (ms (tokClassName cls)) ] [ text (ms txt) ]
        | Tok cls txt <- highlight ins
        ]
    ]
  where
    (kindLabel, kindClass) = case kind of
      Intro -> ("intro" :: T.Text, "kind-intro" :: T.Text)
      Give  -> ("give",            "kind-give")

-- | When the level is solved, offer a step onward: the next /incomplete/ slot
-- (an unviewed prose or an unsolved required puzzle), searching forward and
-- wrapping past the end. A closing line shows once everything is done.
advanceView :: Model -> View Model Action
advanceView m
  | Solved <- m ^. result =
      case nextIncomplete m of
        Just j  -> H.div_ [ P.class_ "advance" ]
                     [ H.button_ [ H.onClick (SelectSlot j) ]
                         [ text "Next →" ] ]
        Nothing -> H.div_ [ P.class_ "advance" ]
                     [ H.p_ [ P.class_ "all-done" ]
                         [ text "🏆 You've finished every activity. The end — for now!" ] ]
  | otherwise = text ""

-- | The next incomplete /required/ slot, searching forward from the current one
-- and wrapping past the end. 'Nothing' when everything required is done.
nextIncomplete :: Model -> Maybe Int
nextIncomplete m = find incomplete order
  where
    n     = totalSlots
    order = [ (_slotIx m + k) `mod` n | k <- [1 .. n - 1] ]
    incomplete i =
      let s = slotAt i
      in slotRequired s
           && not (slotDone (m ^. solved) (m ^. viewed) (m ^. pretest) s)

-- | A linear navigation bar over all slots: previous, the current slot's label,
-- then next. Adjacent navigation, disabled at the ends; the picker above remains
-- the way to jump anywhere.
navBar :: Model -> View Model Action
navBar m =
  H.div_ [ P.class_ "nav" ]
    [ navButton "← Previous" (cur - 1) (cur > 0)
    , H.span_ [ P.class_ "nav-current" ]
        [ text (ms ("Step " <> tshow (cur + 1) <> " / " <> tshow totalSlots
                      <> " — " <> slotLabel (currentSlot m))) ]
    , navButton "Next →" (cur + 1) (cur < totalSlots - 1)
    ]
  where
    cur = _slotIx m
    navButton lbl j enabled =
      H.button_ ( [ H.onClick (SelectSlot j) ] <> [ P.disabled_ | not enabled ] )
        [ text lbl ]

-- | A short human label for a slot, for the nav bar.
slotLabel :: Slot -> T.Text
slotLabel (SlotProse  _ p)    = proseTitle p
slotLabel (SlotPuzzle _ ix z) = tshow (ix + 1) <> ". " <> levelTitle (puzzleLevel z)

resultView :: CheckResult -> View Model Action
resultView = \case
  NotChecked   -> H.pre_ [] [ text "(press Check)" ]
  ParseError e -> H.pre_ [ P.class_ "err" ] [ text (ms ("Parse error:\n" <> e)) ]
  -- The rzk type-error formatter is verbose (a "when typechecking …" trace per
  -- lambda layer). Lead with a friendly line and keep the full report in a
  -- height-capped, scrollable box so it does not run down the page.
  TypeError e  ->
    H.div_ [ P.class_ "err" ]
      [ H.p_  [] [ text "This proof doesn't typecheck yet:" ]
      , H.pre_ [ P.class_ "errdump" ] [ text (ms e) ]
      ]
  Solved       ->
    H.div_ [ P.class_ "ok" ]
      [ H.pre_ [] [ text "✓ Solved — no holes, typechecks. Level complete!" ] ]
  Holes hs ->
    H.div_ [ P.class_ "holes" ]
      ( H.p_ [] [ text (ms (tshow (length hs) <> " hole(s) remaining")) ]
      : map holeView hs
      )

-- | The level conclusion prose. The div is keyed by slot, so it is recreated on
-- navigation (and the prose re-injected); it is revealed once the level solves.
conclusionView :: Model -> Level -> View Model Action
conclusionView m lvl =
  H.div_ [ P.class_ (ms cls)
         , key_ (ms ("concl-" <> show (_slotIx m)))
         , onCreatedWith (InitProse (ms (levelConclusion lvl)))
         ] []
  where
    cls :: T.Text
    cls = case m ^. result of
      Solved -> "prose concl shown"
      _      -> "prose concl hidden"

-- | Render one hole as a stack of labelled panels: goal, then any local
-- hypotheses, cube variables, and tope assumptions.
holeView :: HoleView -> View Model Action
holeView HoleView{..} =
  H.div_ [ P.class_ "hole" ] $
    [ H.div_ [ P.class_ "hole-head" ]
        [ text (maybe "Hole" (\n -> "Hole " <> ms n) hvName) ]
    , panel "Goal" [ H.pre_ [ P.class_ "goal" ] [ text (ms hvGoal) ] ]
    ]
    <> bindings "Context" hvContext
    <> bindings "Cube variables" hvCubeVars
    <> topes hvTopes
  where
    panel title body = H.div_ [ P.class_ "hole-panel" ]
      ( H.div_ [ P.class_ "hole-label" ] [ text title ] : body )

    bindings _ []      = []
    bindings title es  =
      [ panel title
          [ H.ul_ [ P.class_ "ctx" ]
              [ H.li_ []
                  [ H.span_ [ P.class_ "name" ] [ text (ms n) ]
                  , text " : "
                  , H.span_ [ P.class_ "type" ] [ text (ms ty) ]
                  ]
              | (n, ty) <- es
              ]
          ]
      ]

    topes []  = []
    topes ts  =
      [ panel "Topes"
          [ H.ul_ [ P.class_ "ctx" ] [ H.li_ [] [ text (ms t) ] | t <- ts ] ]
      ]
