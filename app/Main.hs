{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

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
import           Miso.FFI.QQ        (js)
import           Miso.Lens
import           Miso.String        (MisoString, fromMisoString, ms)

import           Control.Exception  (SomeException, evaluate, try)
import           Data.List          (find, sort)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (fromMaybe, mapMaybe)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import qualified Data.Text          as T
import           Data.Text.Encoding (encodeUtf8)
import           Text.Read          (readMaybe)

import qualified RzkGame.Content    as Content
import           RzkGame.Content    (apHomLevel, arrInArrLevel, composeLevel,
                                     composeWitnessLevel, constTriangleLevel,
                                     hom2Level, homLeftUnitLevel, idMorphismLevel,
                                     idArrLevel, mapPointLevel,
                                     tetrahedronLevel, tripleCompLevel,
                                     unfoldingSquareLevel, witnessAssocLevel,
                                     witnessSquareLevel)
import           RzkGame.Highlight  (Tok (..), highlight, highlightLines,
                                     tokClassName)
import           RzkGame.Level
import           RzkGame.Format     (formatEditable)
import           RzkGame.Loader     (buildGame)
import           RzkGame.Save       (decodeArchive, encodeArchive)
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
renderProseInto ref src = [js|renderInto(${ref},${src})|]

-- | The game's sections, slots, and levels bundled together. Built once in
-- 'main' (or a test entry point) from the result of 'loadGame', then threaded
-- into all navigation, view, and update functions via partial application.
data GameEnv = GameEnv
  { envChapters :: [Chapter]
  , envSections :: [Section]
  , envSlots    :: [Slot]
  , envLevels   :: [Level]
  }

mkGameEnv :: [Chapter] -> GameEnv
mkGameEnv chapters = GameEnv chapters secs (slotsOfSections secs)
  [ puzzleLevel z | SPuzzle z <- concatMap sectionItems secs ]
  where secs = chaptersSections chapters

-- | @localStorage@ key under which @index.js@ stashes the fetched @game.json@.
gameJsonKey :: MisoString
gameJsonKey = "rzk-game-json"

-- | Read the stashed @game.json@, build the chapters, and return them. Any
-- failure (no bundle, malformed JSON, empty game) returns the built-in fallback.
loadGame :: IO [Chapter]
loadGame = do
  mjson <- getLocalStorage gameJsonKey
  case mjson of
    Just s
      | let t = fromMisoString s, not (T.null t)
      , Right chapters <- buildGame (encodeUtf8 t)
      , not (null chapters) -> pure chapters
    _ -> pure Content.gameChapters

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
  , _confirmReset :: Bool                  -- ^ whether the reset confirmation is showing
  , _importMsg :: Maybe (Either T.Text Int) -- ^ last import result: error, or count restored
  , _formatOnCheck :: Bool                  -- ^ format the editable region before each check
  , _hintsShown :: Int                      -- ^ how many hints the player has revealed (per-session)
  , _dirty      :: Bool                      -- ^ editable changed since the shown result was checked
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

confirmReset :: Lens Model Bool
confirmReset = lens _confirmReset $ \m v -> m { _confirmReset = v }

importMsg :: Lens Model (Maybe (Either T.Text Int))
importMsg = lens _importMsg $ \m v -> m { _importMsg = v }

formatOnCheck :: Lens Model Bool
formatOnCheck = lens _formatOnCheck $ \m v -> m { _formatOnCheck = v }

hintsShown :: Lens Model Int
hintsShown = lens _hintsShown $ \m v -> m { _hintsShown = v }

dirty :: Lens Model Bool
dirty = lens _dirty $ \m v -> m { _dirty = v }

-- | The slot currently being shown.
currentSlot :: GameEnv -> Model -> Slot
currentSlot env m = slotAt env (_slotIx m)

slotAt :: GameEnv -> Int -> Slot
slotAt env i = head (drop i (envSlots env))

-- | The global puzzle index of a slot, if it is a puzzle.
puzzleIndexAt :: GameEnv -> Int -> Maybe Int
puzzleIndexAt env i = case slotAt env i of
  SlotPuzzle _ ix _ -> Just ix
  _                 -> Nothing

-- | Index the puzzle list by global index. (Miso's DSL re-exports @(!!)@ as a JS
-- property accessor, shadowing Prelude's list index, so we avoid it here.)
nthLevel :: GameEnv -> Int -> Level
nthLevel env i = head (drop i (envLevels env))

-- | The stable id of the puzzle at a global puzzle index, and the inverse. These
-- bridge the in-memory progress (still keyed by index, as the section logic
-- expects) and its persisted form (keyed by id, so reordering levels cannot
-- silently reassign a player's solved levels and drafts).
puzzleIdByIx :: GameEnv -> Int -> Maybe T.Text
puzzleIdByIx env i = puzzleId . snd <$> find ((== i) . fst) (puzzleSlots (envSlots env))

puzzleIxById :: GameEnv -> T.Text -> Maybe Int
puzzleIxById env pid = fst <$> lookupPuzzleSlot (envSlots env) pid

tshow :: Show a => a -> T.Text
tshow = T.pack . show

data Action
  = SetEditable MisoString
  | Refine T.Text
  | Undo                       -- ^ revert the last tap-to-refine or Reset
  | Check
  | Format                     -- ^ tidy the editable region with rzk's formatter
  | Reset
  | SelectSlot Int             -- ^ navigate to a slot (prose or puzzle)
  | HashNav MisoString         -- ^ navigate to the slot named by a URL fragment
  | ToggleMap                  -- ^ show/hide the full level map
  | Init                       -- ^ dispatched at mount: load saved state + draft
  | LoadState LoadedState       -- ^ install the persisted player state read at 'Init'
  | ApplyText Int MisoString   -- ^ install a puzzle's restored draft (by index)
  | SetPretest T.Text PretestAnswer  -- ^ record a pre-test self-assessment
  | Unlock T.Text              -- ^ override a lock ("Unlock anyway"), by puzzle id
  | InitProse MisoString DOMRef  -- ^ inject prose into a just-created div
  | ExportProgress             -- ^ gather player-data keys → archive JSON → download
  | ImportProgress             -- ^ open a file picker; the file is applied at reload
  | ResetProgress              -- ^ ask to confirm erasing all progress
  | ConfirmReset               -- ^ confirmed: clear all player-data keys and re-init
  | CancelReset                -- ^ dismiss the reset confirmation
  | DismissImportMsg           -- ^ dismiss the import result banner
  | SetFormatOnCheck Bool      -- ^ toggle (and persist) the format-on-check preference
  | RevealHint                 -- ^ reveal the next hidden hint (progressive disclosure)
  | CopyText MisoString        -- ^ copy the given text to the clipboard
  -- No 'Eq': 'DOMRef' (a 'JSVal') has none. miso does not require 'Eq' on actions.

main :: IO ()
main = do
  chapters     <- loadGame
  let env       = mkGameEnv chapters
  importResult <- applyPendingImport env
#ifdef INTERACTIVE
  live defaultEvents (mkApp env importResult)
#else
  startApp defaultEvents (mkApp env importResult)
#endif

#ifdef WASM
#ifndef INTERACTIVE
foreign export javascript "hs_start"        main            :: IO ()
foreign export javascript "hs_selftest"     hsSelftest      :: IO ()
foreign export javascript "hs_gamecheck"    hsGameCheck     :: IO ()
foreign export javascript "hs_progresscheck" hsProgressCheck :: IO ()

-- | Headless proof that the /loaded/ game (from @game.json@) works in wasm: read
-- the stashed bundle, build the sections in-process, and play the first level
-- (its template holes, its reference solution solves) through the real rzk
-- type-checker. Driven by @loadtest.mjs@, which stubs @localStorage@ with the
-- bundle. This exercises the wasm path that the native @rzk-game-spec@ test
-- cannot: 'getLocalStorage' → 'buildGame' → 'checkLevel'.
hsGameCheck :: IO ()
hsGameCheck = do
  chapters <- loadGame
  let env  = mkGameEnv chapters
      secs = envSections env
      lvls = envLevels env
  putStrLn ("loaded sections: " <> show (length secs))
  mapM_ (\s -> putStrLn ("  section: " <> T.unpack (sectionTitle s)
                           <> " (" <> T.unpack (sectionId s) <> "), "
                           <> show (length (sectionItems s)) <> " items")) secs
  putStrLn ("loaded levels: " <> show (length lvls))
  case lvls of
    [] -> putStrLn "LOADED-PLAY FAILED (no levels)"
    (lvl : _) -> do
      let holes  = case checkLevel lvl (levelTemplate lvl) of Holes _ -> True; _ -> False
          solves = checkLevel lvl (levelSolution lvl) == Solved
      putStrLn ("first level: " <> T.unpack (levelTitle lvl))
      putStrLn (if holes && solves then "loaded-play: OK" else "LOADED-PLAY FAILED")
      -- Formatting the editable region, inside wasm, against the real loaded
      -- level: a formatted template still holes, a formatted solution still
      -- solves, and formatting is stable (a fixpoint).
      let ft = formatEditable (levelTemplate lvl)
          fs = formatEditable (levelSolution lvl)
          fHoles = case checkLevel lvl ft of Holes _ -> True; _ -> False
          fSolves = checkLevel lvl fs == Solved
          stable  = formatEditable ft == ft && formatEditable fs == fs
      putStrLn (if fHoles && fSolves && stable
                  then "loaded-format: OK" else "LOADED-FORMAT FAILED")

-- | Headless proof of the export/import round-trip in wasm, against the same
-- @localStorage@ shim @loadtest.mjs@ uses (driven by @progresscheck.mjs@). Seed
-- some progress, export it to an archive string, clear, import it back through
-- the real 'applyPendingImport', and assert the keys are restored; then check a
-- wrong-version archive is rejected and changes nothing.
hsProgressCheck :: IO ()
hsProgressCheck = do
  chapters <- loadGame
  let env = mkGameEnv chapters
  -- Seed a representative slice of player data.
  setLocalStorage progressKey      "0,2,5"
  setLocalStorage viewedKey        "morphisms-intro,functions-intro"
  setLocalStorage pretestKey       "map-point=familiar"
  setLocalStorage (draftKey env 0) "#def my-id (A : U) (x : A)\n  : hom A x x\n  := ?"
  before <- gatherProgress env
  let archive = encodeArchive before
  putStrLn ("seeded keys: " <> show (length before))

  -- Clear everything, then import the archive through the real startup path.
  clearPlayerData env
  cleared <- gatherProgress env
  setLocalStorage importScratchKey (ms archive)
  res  <- applyPendingImport env
  after <- gatherProgress env
  scratchGone <- getLocalStorage importScratchKey
  let restoredOk = sort after == sort before
      countOk    = res == Just (Right (length before))
      clearedOk  = null cleared
      consumedOk = scratchGone == Nothing
  putStrLn ("after clear: " <> show (length cleared)
            <> ", after import: " <> show (length after)
            <> ", result: " <> show res)
  putStrLn (if restoredOk && countOk && clearedOk && consumedOk
              then "progress roundtrip: OK" else "PROGRESS ROUNDTRIP FAILED")

  -- A wrong-version archive is rejected and leaves the restored state untouched.
  setLocalStorage importScratchKey "{\"version\": 2, \"saved\": {\"rzk-game-progress\": \"9\"}}"
  res2 <- applyPendingImport env
  prog  <- getLocalStorage progressKey
  let rejectedOk = case res2 of Just (Left _) -> True; _ -> False
      untouched  = prog == Just "0,2,5"
  putStrLn (if rejectedOk && untouched
              then "bad-version rejected: OK" else "BAD-VERSION REJECT FAILED")

-- | Headless proof that the engine runs in wasm: for every level, check the
-- starting template (holes) and the reference solution (solved); then exercise
-- the first level's tap-to-refine, the type-error paths, the smart inventory,
-- and the section/locking/progress logic.
hsSelftest :: IO ()
hsSelftest = do
  -- The self-test exercises the full built-in game (15 levels, fixed ids and
  -- order), independent of whatever game.json a build happens to load.
  let env          = mkGameEnv Content.gameChapters
      gameLevels   = envLevels   env
      gameSections = envSections env
      slots        = envSlots    env
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
  putStrLn "== diagnostics: a type error squiggles a line inside the editable region (expect OK) =="
  -- The hom2 template is three editable lines; rzk attaches the error to the
  -- enclosing #def's line, so the squiggled line(s) must fall in 1..3.
  let editableSpanOf lvl = length (T.lines (levelTemplate lvl))
      inEditable lvl ls  = not (null ls) && all (\l -> l >= 1 && l <= editableSpanOf lvl) ls
      typeErrLines lvl e = case checkLevel lvl (refineFirstHole e (levelTemplate lvl)) of
        TypeError _ ls -> Just ls
        _              -> Nothing
      garbageOK = maybe False (inEditable hom2Level) (typeErrLines hom2Level "asd")
      branchOK  = maybe False (inEditable hom2Level) (typeErrLines hom2Level "s")
  putStrLn ("   garbage 'asd' -> lines " <> show (typeErrLines hom2Level "asd"))
  putStrLn ("   wrong branch 's' -> lines " <> show (typeErrLines hom2Level "s"))
  putStrLn (if garbageOK && branchOK then "error lines: OK" else "ERROR LINES FAILED")
  putStrLn "== diagnostics: a parse error reports its editable line (expect OK) =="
  -- A malformed one-line editable region fails to parse on its only line (1). The
  -- whole check is forced inside 'try': rzk's layout resolver reports some
  -- malformed input by throwing (a pure 'error'), which 'checkLevel' does not
  -- catch, so a throw is tolerated here rather than aborting the self-test.
  let parseInput = "#def rut : U := )"
  parseProbe <- try (evaluate
    (case checkLevel hom2Level parseInput of
       ParseError _ (Just l) -> l == 1
       ParseError _ Nothing  -> True    -- reported, line just not extracted
       _                     -> False))
      :: IO (Either SomeException Bool)
  case parseProbe of
    Left _   -> putStrLn "   (the parser threw on this input; tolerated)"
    Right ok -> putStrLn ("   malformed body -> line maps correctly: " <> show ok)
  putStrLn (if either (const True) id parseProbe
              then "parse line: OK" else "PARSE LINE FAILED")
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
  putStrLn "== unfolding-square: fill both recOR branches (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain unfoldingSquareLevel ["triangle (s , t)", "triangle (t , s)"])))
  putStrLn "== witness-square: give the composition witness (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain witnessSquareLevel ["witness-comp-is-segal A is-segal-A x y z f g"])))
  putStrLn "== id-arr-in-arr: return f at its coordinate s (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain idArrLevel ["f s"])))
  putStrLn "== arr-in-arr: apply the square at (t , s) (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain arrInArrLevel ["witness-square-comp-is-segal A is-segal-A x y z f g (t , s)"])))
  putStrLn "== witness-associative ★: compose the witnesses in arr A (expect Solved) =="
  let witnessAssocFill = T.concat
        [ "witness-comp-is-segal (arr A) (is-segal-arr A is-segal-A) f g h "
        , "(arr-in-arr-is-segal A is-segal-A w x y f g) "
        , "(arr-in-arr-is-segal A is-segal-A x y z g h)" ]
  putStrLn (T.unpack (renderResult (tapChain witnessAssocLevel [witnessAssocFill])))
  putStrLn "== tetrahedron: regroup to the middle simplex (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain tetrahedronLevel ["witness-associative-is-segal A is-segal-A w x y z f g h (t , r) s"])))
  putStrLn "== triple-comp: restrict to the main diagonal (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (tapChain tripleCompLevel ["((t , t) , t)"])))
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
      roundTrips  = decodeSolved env (encodeSolved env allSolved) == allSolved
      emptyOk     = decodeSolved env (encodeSolved env Set.empty) == Set.empty
      junkDropped = decodeSolved env "0,x,,2" == Set.fromList [0, 2]
      -- Migration: a legacy numeric ("index") value still loads, and the new
      -- form is written as ids, not numbers.
      legacyOk    = decodeSolved env "0,2,5" == Set.fromList [0, 2, 5]
      idFormOk    = encodeSolved env (Set.fromList [0]) == ms (fromMaybe "?" (puzzleIdByIx env 0))
  putStrLn (if roundTrips && emptyOk && junkDropped && legacyOk && idFormOk
              then "progress codec: OK" else "PROGRESS CODEC FAILED")
  putStrLn "== viewed codec: encode/decode round-trips =="
  let viewedSet  = Set.fromList ["morphisms-intro", "associativity-arr-segal"]
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
                                , "map-point", "ap-hom", "compose", "compose-witness"
                                , "unfolding-square", "witness-square-comp-is-segal"
                                , "id-arr-in-arr", "arr-in-arr-is-segal"
                                , "witness-associative-is-segal"
                                , "tetrahedron-associative-is-segal", "triple-comp-is-segal"]
      derivedOk  = map levelTitle [ puzzleLevel z | SPuzzle z <- concatMap sectionItems gameSections ]
                     == map levelTitle gameLevels
  putStrLn (if orderOk && derivedOk then "section order: OK" else "SECTION ORDER FAILED")
  putStrLn "== anchors: every slot's URL anchor round-trips to its index (expect OK) =="
  let anchorOk = and [ anchorSlotIx env (slotAnchorAt env i) == Just i
                     | i <- [0 .. length slots - 1] ]
              && anchorSlotIx env ("#" <> slotAnchorAt env 0) == Just 0  -- a leading # is tolerated
              && anchorSlotIx env "" == Nothing                      -- bare URL: no jump
              && anchorSlotIx env "no-such-slot" == Nothing          -- unknown: no jump
  putStrLn (if anchorOk then "anchors: OK" else "ANCHORS FAILED")
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

mkApp :: GameEnv -> Maybe (Either T.Text Int) -> App Model Action
mkApp env importResult = (component (initModel env importResult) (updateModel env) (viewModel env))
  { mount = Just Init     -- seed solved/viewed/pretest/unlock and the draft
    -- Back/forward (a popstate carrying a new URL fragment) navigates to the
    -- named slot, so the URL hash and the shown slot stay in step. The initial
    -- fragment is handled separately in 'Init' (popstate does not fire on load).
  , subs  = [ uriSub (HashNav . uriFragment) ]
  }

-- | A slot's stable URL anchor: the prose or puzzle id. Used as the location
-- hash (e.g. @#const-triangle@) so a slot can be deep-linked and survives a
-- page refresh. Ids are kebab-case and need no escaping in a fragment.
slotAnchor :: Slot -> T.Text
slotAnchor (SlotProse  _ p)   = proseId p
slotAnchor (SlotPuzzle _ _ z) = puzzleId z

slotAnchorAt :: GameEnv -> Int -> T.Text
slotAnchorAt env = slotAnchor . slotAt env

-- | The slot index named by a URL fragment, if any matches. A leading @#@ is
-- tolerated; an empty or unknown fragment yields 'Nothing' (so a bad link or a
-- bare URL simply stays on slot 0).
anchorSlotIx :: GameEnv -> T.Text -> Maybe Int
anchorSlotIx env raw
  | T.null frag = Nothing
  | otherwise   = fst <$> find ((== frag) . slotAnchor . snd) (zip [0 ..] (envSlots env))
  where
    frag = fromMaybe raw (T.stripPrefix "#" raw)

-- | Write the location hash, without a page jump or reload. Setting it to the
-- value already there is a no-op in the browser (no @hashchange@, no history
-- entry), so navigating to the current slot does not stack history. Routed
-- through the 'js' QuasiQuoter (like 'renderProseInto') to dodge the JSString-arg
-- codegen bug.
setHash :: T.Text -> IO ()
setHash a = let a' = ms a in [js| window.location.hash = ${a'}; |]

-- | Copy text to the clipboard (the crash report). Available on localhost and
-- HTTPS (a secure context), which covers local play and GitHub Pages.
copyToClipboard :: MisoString -> IO ()
copyToClipboard t = [js| navigator.clipboard.writeText(${t}); |]

initModel :: GameEnv -> Maybe (Either T.Text Int) -> Model
initModel env importResult = enterSlotPure env 0
  (Model 0 "" NotChecked Set.empty Set.empty Map.empty Set.empty [] False False importResult False 0 False)

-- | Set up the model's editor for a slot, without IO. A puzzle slot loads its
-- template and checks it (so the focused hole and its moves show without a first
-- manual Check); a prose slot clears the editor. The undo history is reset.
enterSlotPure :: GameEnv -> Int -> Model -> Model
enterSlotPure env i m = case slotAt env i of
  SlotProse _ _ ->
    m { _slotIx = i, _editable = "", _result = NotChecked, _history = []
      , _hintsShown = 0, _dirty = False }
  SlotPuzzle _ _ z ->
    let t = levelTemplate (puzzleLevel z)
    in m { _slotIx = i, _editable = ms t
         , _result = checkLevel (puzzleLevel z) t, _history = []
         , _hintsShown = 0, _dirty = False }

-- localStorage keys.
progressKey, viewedKey, pretestKey, unlockedKey :: MisoString
progressKey = "rzk-game-progress"
viewedKey   = "rzk-game-viewed"
pretestKey  = "rzk-game-pretest"
unlockedKey = "rzk-game-unlocked"

-- | The solved set is stored as a comma-separated list of puzzle /ids/, e.g.
-- @"my-id,map-point"@, so reordering levels does not reassign saved progress.
-- On load each token resolves to its current index; a token that is no longer a
-- known id is dropped. For backward compatibility a purely numeric token is read
-- as a legacy /index/, so progress saved by an older build still loads (and is
-- rewritten in id form on the next save).
encodeSolved :: GameEnv -> Set Int -> MisoString
encodeSolved env = ms . T.intercalate "," . mapMaybe (puzzleIdByIx env) . Set.toList

decodeSolved :: GameEnv -> MisoString -> Set Int
decodeSolved env =
  Set.fromList . mapMaybe resolve . T.splitOn "," . fromMisoString
  where
    resolve t
      | T.null t                       = Nothing
      | Just ix <- puzzleIxById env t  = Just ix              -- current id form
      | otherwise                      = readMaybe (T.unpack t) -- legacy index form

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

readProgress :: GameEnv -> IO (Set Int)
readProgress env = maybe Set.empty (decodeSolved env) <$> getLocalStorage progressKey

saveProgress :: GameEnv -> Set Int -> IO ()
saveProgress env = setLocalStorage progressKey . encodeSolved env

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

-- | The format-on-check preference, stored as @"1"@ / @"0"@. Absent (or any
-- other value) reads as off, so the default is never to reformat on a check.
formatOnCheckKey :: MisoString
formatOnCheckKey = "rzk-game-format-on-check"

readFormatOnCheck :: IO Bool
readFormatOnCheck = (== Just "1") <$> getLocalStorage formatOnCheckKey

saveFormatOnCheck :: Bool -> IO ()
saveFormatOnCheck b = setLocalStorage formatOnCheckKey (if b then "1" else "0")

-- | The persisted player state read at startup: the solved set, viewed prose,
-- pre-test answers, unlock overrides, and the format-on-check preference. It is
-- read by 'Init' and applied to the model by 'LoadState'. Bundling the reads
-- into one record keeps that action's payload readable as the saved state grows.
data LoadedState = LoadedState
  { lsSolved        :: Set Int
  , lsViewed        :: Set T.Text
  , lsPretest       :: Map T.Text PretestAnswer
  , lsUnlocked      :: Set T.Text
  , lsFormatOnCheck :: Bool
  }

readLoadedState :: GameEnv -> IO LoadedState
readLoadedState env = LoadedState
  <$> readProgress env <*> readViewed <*> readPretest <*> readUnlocked
  <*> readFormatOnCheck

-- | Per-level draft storage. Each puzzle's in-progress text is saved under its
-- own key, so the raw source needs no escaping (unlike a single packed value).
-- The key is derived from the puzzle's stable id, so reordering levels does not
-- mix up drafts; a draft for a level no longer in the game lingers, harmlessly
-- unread. (If an index somehow has no id, fall back to the numeric form.)
draftKey :: GameEnv -> Int -> MisoString
draftKey env i = "rzk-game-draft-" <> ms (fromMaybe (tshow i) (puzzleIdByIx env i))

-- | The pre-id draft key for a puzzle index: @rzk-game-draft-<index>@. Read as a
-- fallback so a draft saved by an older build is not lost, and cleaned up on
-- 'removeDraft'. No longer written.
legacyDraftKey :: Int -> MisoString
legacyDraftKey i = "rzk-game-draft-" <> ms (show i)

saveDraft :: GameEnv -> Int -> MisoString -> IO ()
saveDraft env i = setLocalStorage (draftKey env i)

removeDraft :: GameEnv -> Int -> IO ()
removeDraft env i = removeLocalStorage (draftKey env i) >> removeLocalStorage (legacyDraftKey i)

-- | Read a puzzle's saved draft, falling back to its template when none is
-- stored, and return the action that installs it. The id-keyed draft is
-- preferred; a legacy index-keyed draft is read when no id-keyed one exists, so
-- progress from an older build survives (and migrates to the id key on the next
-- save). The index is carried so the update can ignore a stale read after a
-- quick navigation.
loadDraftAction :: GameEnv -> Int -> IO Action
loadDraftAction env i = do
  saved  <- getLocalStorage (draftKey env i)
  legacy <- maybe (getLocalStorage (legacyDraftKey i)) (pure . Just) saved
  pure (ApplyText i (fromMaybe (ms (levelTemplate (nthLevel env i))) legacy))

-- Progress export / import / reset ------------------------------------------

-- | All the @localStorage@ keys that make up the player's progress: the four
-- fixed keys plus one draft per puzzle. The engine's loaded @game.json@ bundle
-- (under 'gameJsonKey') is deliberately excluded — it is content, regenerated at
-- load, not player data.
playerDataKeys :: GameEnv -> [MisoString]
playerDataKeys env =
  [progressKey, viewedKey, pretestKey, unlockedKey, formatOnCheckKey]
    ++ [ k | i <- [0 .. length (envLevels env) - 1], k <- [draftKey env i, legacyDraftKey i] ]

-- | Whether a key from an imported archive is player data we will restore. The
-- four fixed keys, plus any per-level draft (accepted even for an index beyond
-- the current game, matching how a stale draft is otherwise tolerated).
isPlayerDataKey :: T.Text -> Bool
isPlayerDataKey k =
  k `elem` map fromMisoString
             [progressKey, viewedKey, pretestKey, unlockedKey, formatOnCheckKey]
    || "rzk-game-draft-" `T.isPrefixOf` k

-- | The scratch key @download.js@ stashes a chosen import file under, read once
-- at startup by 'applyPendingImport'.
importScratchKey :: MisoString
importScratchKey = "rzk-game-import"

-- | Read every present player-data key, as @(key, value)@ text pairs.
gatherProgress :: GameEnv -> IO [(T.Text, T.Text)]
gatherProgress env = do
  let keys = playerDataKeys env
  vals <- mapM getLocalStorage keys
  pure [ (fromMisoString k, fromMisoString v)
       | (k, Just v) <- zip keys vals ]

-- | Remove every player-data key, leaving the loaded game bundle in place.
clearPlayerData :: GameEnv -> IO ()
clearPlayerData env = mapM_ removeLocalStorage (playerDataKeys env)

-- | Gather the progress and hand it to @download.js@ as one archive file. Called
-- through the DSL's 'js' QuasiQuoter (like 'renderProseInto') to avoid the @JSString@-arg
-- codegen bug.
exportProgress :: GameEnv -> IO ()
exportProgress env = do
  pairs <- gatherProgress env
  let ps = encodeArchive pairs
  [js| download ('rzk-game-progress.json', ${ps}) |]

-- | If @download.js@ stashed an import file (then reloaded), validate it with the
-- pure 'decodeArchive' and apply it: replace the player-data keys with the
-- archive's (a full replace, not a merge — so progress not in the archive is
-- cleared), then return the outcome for the initial model to surface. A malformed
-- or wrong-version archive is rejected with its message and changes nothing. The
-- scratch key is always consumed, so an import is applied at most once.
applyPendingImport :: GameEnv -> IO (Maybe (Either T.Text Int))
applyPendingImport env = do
  mraw <- getLocalStorage importScratchKey
  case mraw of
    Nothing  -> pure Nothing
    Just raw -> do
      removeLocalStorage importScratchKey
      case decodeArchive (fromMisoString raw) of
        Left err  -> pure (Just (Left err))
        Right kvs -> do
          let keep = [ (k, v) | (k, v) <- kvs, isPlayerDataKey k ]
          clearPlayerData env
          mapM_ (\(k, v) -> setLocalStorage (ms k) (ms v)) keep
          pure (Just (Right (length keep)))


updateModel :: GameEnv -> Action -> Effect parent props Model Action
updateModel env = \case
  SetEditable s -> do
    editable .= s
    dirty .= True            -- typed since the last check: the shown result is stale
    mix <- currentPuzzleIx
    case mix of
      Just ix -> io_ (saveDraft env ix s)
      Nothing -> pure ()
  ToggleMap -> mapOpen %= not
  SelectSlot i -> gotoSlot i
  -- A fragment from back/forward (or the initial URL, replayed at 'Init'): jump
  -- to the named slot, unless it is already current or the fragment is unknown.
  HashNav frag -> do
    cur <- use slotIx
    case anchorSlotIx env (fromMisoString frag) of
      Just j | j /= cur -> gotoSlot j
      _                 -> pure ()
  Reset -> withPuzzle $ \ix -> do
    e <- use editable
    history %= (e :)         -- a mistaken Reset can be undone
    let t = levelTemplate (nthLevel env ix)
    editable .= ms t
    setResult (checkLevel (nthLevel env ix) t)
    io_ (removeDraft env ix)     -- drop the draft so the template stays on next load
  Init -> do
    io (LoadState <$> readLoadedState env)
    mix <- currentPuzzleIx
    case mix of
      Just ix -> io (loadDraftAction env ix)  -- a puzzle slot 0: restore its draft
      Nothing -> pure ()                      -- a prose slot 0: LoadState marks it viewed
    -- Honour a slot named in the URL hash (a deep link, or a refresh that kept
    -- the fragment): popstate does not fire on load, so read it once here. A
    -- bare or unknown fragment leaves the player on slot 0.
    io (HashNav . uriFragment <$> getURI)
  LoadState ls -> do
    solved   .= lsSolved ls
    pretest  .= lsPretest ls
    unlocked .= lsUnlocked ls
    formatOnCheck .= lsFormatOnCheck ls
    -- If slot 0 is prose, it has already been "visited" at mount, so fold it in.
    i <- use slotIx
    let v  = lsViewed ls
        v' = case slotAt env i of
               SlotProse _ p -> Set.insert (proseId p) v
               _             -> v
    viewed .= v'
    if v' /= v then io_ (saveViewed v') else pure ()
  SetPretest pid ans -> do
    pretest %= Map.insert pid ans
    pt <- use pretest
    io_ (savePretest pt)
    -- "I already know this" satisfies the pre-test, so jump ahead to the next
    -- unfinished step — the player expects marking familiarity to skip the
    -- material, not to leave them on the page. "Not familiar" stays put (its
    -- remediation box has just appeared below).
    case ans of
      Familiar -> do
        cur <- use slotIx
        sv  <- use solved
        vw  <- use viewed
        case nextIncompleteFrom env cur sv vw pt of
          Just j  -> issue (SelectSlot j)
          Nothing -> pure ()
      NotFamiliar -> pure ()
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
        setResult (checkLevel (nthLevel env i) (fromMisoString s))
      else pure ()
  Refine ins -> withPuzzle $ \ix -> do
    foc <- use formatOnCheck
    e <- use editable
    history %= (e :)         -- remember the pre-refine text so the tap can be undone
    let e'  = maybeFormat foc (refineFirstHole ins (fromMisoString e))
        res = checkLevel (nthLevel env ix) e'
    editable .= ms e'
    setResult res
    io_ (saveDraft env ix (ms e'))
    recordSolved ix res
  Undo -> do
    hs  <- use history
    mix <- currentPuzzleIx
    case (hs, mix) of
      (prev : rest, Just ix) -> do
        history  .= rest
        editable .= prev
        setResult (checkLevel (nthLevel env ix) (fromMisoString prev))
        io_ (saveDraft env ix prev)
      _ -> pure ()
  Check -> withPuzzle $ \ix -> do
    foc <- use formatOnCheck
    e0 <- use editable
    let e = ms (maybeFormat foc (fromMisoString e0))
    -- With format-on-check on, a check first tidies the region in place (an
    -- undoable, saved edit), then checks the formatted text.
    if e /= e0
      then do history %= (e0 :); editable .= e; io_ (saveDraft env ix e)
      else pure ()
    let res = checkLevel (nthLevel env ix) (fromMisoString e)
    setResult res
    recordSolved ix res
  Format -> withPuzzle $ \ix -> do
    e <- use editable
    let e' = ms (formatEditable (fromMisoString e))
    -- Only act when formatting changed the text: an already-tidy region needs
    -- no undo entry, no re-check, and no save. Re-checking on a change keeps the
    -- squiggled line numbers aligned with the reflowed text.
    if e' == e
      then pure ()
      else do
        history %= (e :)         -- formatting can be undone
        editable .= e'
        setResult (checkLevel (nthLevel env ix) (fromMisoString e'))
        io_ (saveDraft env ix e')
  ExportProgress -> io_ (exportProgress env)
  ImportProgress -> io_ [js|pickImport()|]
  ResetProgress  -> confirmReset .= True
  CancelReset    -> confirmReset .= False
  ConfirmReset   -> do
    io_ (clearPlayerData env)
    solved   .= Set.empty
    viewed   .= Set.empty
    pretest  .= Map.empty
    unlocked .= Set.empty
    history  .= []
    formatOnCheck .= False    -- its key is player data too, cleared above
    confirmReset .= False
    io (pure (SelectSlot 0))   -- back to the start; re-seeds the editor and viewed
  DismissImportMsg -> importMsg .= Nothing
  SetFormatOnCheck b -> do
    formatOnCheck .= b
    io_ (saveFormatOnCheck b)
  RevealHint -> withPuzzle $ \ix -> do
    -- The button walks the plain hints one at a time; contextual (when-goal)
    -- hints surface on their own, so the count never needs to pass the plain
    -- hints (plus one "ask" to engage a level whose hints are all contextual).
    let cap = max (plainHintCount (levelHints (nthLevel env ix))) 1
    n <- use hintsShown
    if n < cap then hintsShown .= n + 1 else pure ()
  CopyText t -> io_ (copyToClipboard t)
  where
    -- Record a fresh check outcome: store it and clear the dirty flag, since the
    -- shown result now matches the editable text. Every check site goes through
    -- this so the "edited since last check" status stays accurate.
    setResult r = do result .= r; dirty .= False

    -- Apply the formatter only when format-on-check is on, leaving the text as
    -- typed otherwise. The formatter itself no-ops on a non-parsing fragment.
    maybeFormat :: Bool -> T.Text -> T.Text
    maybeFormat True  = formatEditable
    maybeFormat False = id

    -- Navigate to a slot: reset the per-level UI state, mirror the slot to the
    -- URL hash (so a refresh or copied link returns here), and set up the editor
    -- — a prose slot is marked viewed; a puzzle slot loads its template then its
    -- saved draft. Shared by 'SelectSlot' (a click) and 'HashNav' (back/forward).
    gotoSlot i = do
      history    .= []
      slotIx     .= i
      hintsShown .= 0          -- a fresh level starts with its hints hidden again
      mapOpen    .= False      -- collapse the map after a jump, back to content
      io_ (setHash (slotAnchorAt env i))
      case slotAt env i of
        SlotProse _ p -> do
          editable .= ""
          setResult NotChecked
          viewed %= Set.insert (proseId p)
          v <- use viewed
          io_ (saveViewed v)
        SlotPuzzle _ ix z -> do
          let t = levelTemplate (puzzleLevel z)
          editable .= ms t
          setResult (checkLevel (puzzleLevel z) t)
          io (loadDraftAction env ix)

    -- The current slot's global puzzle index, if it is a puzzle.
    currentPuzzleIx = do
      i <- use slotIx
      pure (puzzleIndexAt env i)

    -- Run an action only when the current slot is a puzzle, passing its index.
    withPuzzle k = do
      mix <- currentPuzzleIx
      case mix of
        Just ix -> k ix
        Nothing -> pure ()

    -- On a solved puzzle, record it and persist the updated set. We only write to
    -- storage when the set actually changes, to avoid redundant re-checks. A
    -- gated level whose proof uses ungranted lemmas does not count as solved,
    -- even when it type-checks — the gate notice surfaces the blocker.
    recordSolved i Solved = do
      e <- use editable
      s <- use solved
      if Set.member i s || not (gatePassed (nthLevel env i) (fromMisoString e))
        then pure ()
        else do
          let s' = Set.insert i s
          solved .= s'
          io_ (saveProgress env s')
    recordSolved _ _ = pure ()

viewModel :: GameEnv -> props -> Model -> View Model Action
viewModel env _ m =
  H.div_ []
    [ H.header_ [ P.class_ "game" ]
        [ H.h1_ [] [ text "Rzk Game" ]
        , H.p_ [ P.class_ "tagline" ]
            [ text "An interactive Rzk proof game — fill the holes." ]
        ]
    , navHeader env m
    , importBanner m
    , H.section_ [ P.class_ "level" ]
        ( case currentSlot env m of
            SlotProse  sid p    -> proseSlotView  env m sid p
            SlotPuzzle sid ix z -> puzzleSlotView env m sid ix z
        )
    ]

-- | A dismissible banner reporting the result of an import applied at the last
-- reload (see 'applyPendingImport'): how many items were restored, or why the
-- archive was rejected.
importBanner :: Model -> View Model Action
importBanner m = case m ^. importMsg of
  Nothing -> text ""
  Just r  -> H.div_ [ P.class_ (ms ("import-msg " <> cls :: T.Text)) ]
    [ H.span_ [] [ text (ms msg) ]
    , H.button_ [ P.class_ "import-dismiss", H.onClick DismissImportMsg
                , P.title_ "Dismiss" ] [ text "✕" ]
    ]
    where
      (cls, msg) = case r of
        Right n -> ("ok",  "Progress imported — " <> tshow n <> " item(s) restored.")
        Left e  -> ("err", "Import failed: " <> e)

-- | A thin, sticky bar that keeps the level content in focus: it shows where the
-- player is and the overall progress, with a toggle that reveals the full level
-- map on demand. The map is hidden by default and collapses again after a jump.
navHeader :: GameEnv -> Model -> View Model Action
navHeader env m =
  H.div_ [ P.class_ (ms ("mapbar-wrap" <> if open then " open" else "" :: T.Text)) ]
    [ H.div_ [ P.class_ "mapbar" ]
        [ H.button_ [ P.class_ "map-toggle", H.onClick ToggleMap ]
            [ text (if open then "✕  Close map" else "☰  Levels") ]
        , H.span_ [ P.class_ "mapbar-loc" ]
            [ text (ms (sectionTitleOf env (slotSectionId (currentSlot env m)))) ]
        , H.span_ [ P.class_ (ms (progCls :: T.Text)) ]
            [ text (ms (tshow done <> " / " <> tshow total)) ]
        , helpLink env
        ]
    , if open then levelMap env m else text ""
    ]
  where
    open          = m ^. mapOpen
    (done, total) = overallProgress env m
    progCls       = "mapbar-progress" <> if done == total && total > 0 then " done" else ""

-- | The persistent "How holes work" link (item A3). Shown only when the loaded
-- game has a prose page with the 'helpAnchor' id, so the engine carries no hard
-- dependency on any one game's content: a game without that page simply has no
-- link. Clicking it jumps to the page like any other slot.
helpLink :: GameEnv -> View Model Action
helpLink env = case anchorSlotIx env helpAnchor of
  Just i  -> H.button_ [ P.class_ "map-help", H.onClick (SelectSlot i)
                       , P.title_ "How holes work" ]
               [ text "❓ Holes" ]
  Nothing -> text ""

-- | The slot id of the hole-help page (item A4). A game that wants the help link
-- names its onboarding prose page with this id.
helpAnchor :: T.Text
helpAnchor = "how-holes-work"

-- | The section title for a section id (empty if unknown).
sectionTitleOf :: GameEnv -> T.Text -> T.Text
sectionTitleOf env sid = maybe "" sectionTitle (find ((== sid) . sectionId) (envSections env))

-- | The grouped level map: chapters group their sections under a heading (an
-- untitled chapter renders its sections top-level), each section a titled block
-- with its progress count and a row of slot buttons. Shown only when the map is
-- open. Navigation stays free — every slot is always reachable; locking only
-- affects a puzzle page.
levelMap :: GameEnv -> Model -> View Model Action
levelMap env m =
  H.div_ [ P.class_ "sections" ]
    (concatMap chapterBlock (envChapters env) ++ [ progressControls m ])
  where
    indexed = zip [0 ..] (envSlots env)
    -- A chapter: its heading (when titled) followed by its section blocks.
    chapterBlock ch =
      maybe [] (\c -> [ H.h2_ [ P.class_ "chapter-head" ] [ text (ms c) ] ])
            (chapterTitle ch)
        ++ map sectionBlock (chapterSections ch)
    sectionBlock sec =
      let sid       = sectionId sec
          mine      = [ (i, s) | (i, s) <- indexed, slotSectionId s == sid ]
          (d, t)    = sectionProgress (envSlots env) (m ^. solved) (m ^. viewed) (m ^. pretest) sid
      in H.div_ [ P.class_ "section-block" ]
           [ H.div_ [ P.class_ "section-head" ]
               [ H.span_ [ P.class_ "section-title" ] [ text (ms (sectionTitle sec)) ]
               , H.span_ [ P.class_ (ms (countCls d t)) ]
                   [ text (ms (tshow d <> " / " <> tshow t)) ]
               ]
           , H.div_ [ P.class_ "levels" ] (map (slotButton env m) mine)
           ]
    countCls :: Int -> Int -> T.Text
    countCls d t = "section-count" <> if d == t && t > 0 then " done" else ""

-- | Export / import / reset controls, at the foot of the level map. Export and
-- import move the whole progress archive between devices or back it up; reset
-- erases it, behind an in-place confirmation so a stray tap cannot wipe progress.
progressControls :: Model -> View Model Action
progressControls m =
  H.div_ [ P.class_ "progress-controls" ]
    [ H.button_ [ P.class_ "prog-btn", H.onClick ExportProgress ]
        [ text "⇩ Export progress" ]
    , H.button_ [ P.class_ "prog-btn", H.onClick ImportProgress ]
        [ text "⇧ Import progress" ]
    , if m ^. confirmReset
        then H.span_ [ P.class_ "reset-confirm" ]
               [ text "Erase all progress?"
               , H.button_ [ P.class_ "prog-btn danger", H.onClick ConfirmReset ]
                   [ text "Yes, reset" ]
               , H.button_ [ P.class_ "prog-btn", H.onClick CancelReset ]
                   [ text "Cancel" ]
               ]
        else H.button_ [ P.class_ "prog-btn danger", H.onClick ResetProgress ]
               [ text "⟲ Reset progress" ]
    ]

-- | One slot tile: a compact rounded square whose icon names the item's role
-- (prose, ordinary puzzle, pre-test, or a starred extra), with the puzzle's
-- number in the corner. State — current, viewed/solved, locked — is carried by
-- the tile's classes; the full label lives in the @title@ tooltip, so the map
-- stays succinct as sections and items grow. A locked tile shows a padlock.
slotButton :: GameEnv -> Model -> (Int, Slot) -> View Model Action
slotButton env m (i, s) =
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
            locked = levelLocked (envSlots env) (m ^. solved) (m ^. unlocked) (m ^. pretest) z
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
overallProgress :: GameEnv -> Model -> (Int, Int)
overallProgress env m =
  let req = filter slotRequired (envSlots env)
  in ( length (filter (slotDone (m ^. solved) (m ^. viewed) (m ^. pretest)) req)
     , length req )

-- | A section breadcrumb shown atop each slot page: the section title and its
-- "k / n done" count.
breadcrumb :: GameEnv -> Model -> T.Text -> View Model Action
breadcrumb env m sid =
  H.p_ [ P.class_ "breadcrumb" ]
    [ text (ms (title <> " · " <> tshow d <> " / " <> tshow t <> " done")) ]
  where
    title  = maybe "" sectionTitle (find ((== sid) . sectionId) (envSections env))
    (d, t) = sectionProgress (envSlots env) (m ^. solved) (m ^. viewed) (m ^. pretest) sid

-- | A prose pseudo-level page: the rendered text, a viewed mark, and a section
-- "complete" badge when reaching it finishes the section.
proseSlotView :: GameEnv -> Model -> T.Text -> Prose -> [View Model Action]
proseSlotView env m sid p =
  [ breadcrumb env m sid
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
  , sectionDoneBadge env m sid
  , navBar env m
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
puzzleSlotView :: GameEnv -> Model -> T.Text -> Int -> PuzzleItem -> [View Model Action]
puzzleSlotView env m sid ix z =
  [ breadcrumb env m sid
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
  <> [ advanceView env m solvedAccepted, navBar env m ]
  <> [ actionBar m | not locked ]   -- the controls, as a sticky footer bar
  where
    lvl       = puzzleLevel z
    locked    = levelLocked (envSlots env) (m ^. solved) (m ^. unlocked) (m ^. pretest) z
    titleMark = if Set.member ix (m ^. solved) then "✓ " else ""
    roleSuffix = case puzzleRole z of
      Extra   -> " ★"
      PreTest -> " — pre-test"
      Core    -> ""
    -- Inventory gating, computed in the engine. 'gate' is the prelude lemmas used
    -- but not granted; on a 'levelGated' level a violation withholds the solve
    -- (so the green box and the success cues stay hidden until the proof uses
    -- only granted moves), while a non-gated level only ever shows a soft notice.
    gate           = inventoryViolations lvl (fromMisoString (m ^. editable))
    solvedAccepted = m ^. result == Solved && gatePassed lvl (fromMisoString (m ^. editable))
    body
      | locked    = [ lockPanel env m z ]
      | otherwise =
          pretestControls env m z
          <> [ H.h3_ [] [ text "Your proof" ]
             , editorView (m ^. editable) (resultErrorLines (m ^. result))
             , H.h3_ [] [ text "Moves" ]
             , movesView m
             , inventoryView lvl
             , H.h3_ [] [ text "Result" ]
             , checkStatusView m
             -- A gated solve that uses ungranted lemmas is withheld: the red
             -- gate box replaces the green success box; otherwise the result
             -- shows normally, with any gate notice below it.
             , if m ^. result == Solved && not (null gate) && levelGated lvl
                 then text "" else resultView lvl (m ^. editable) (m ^. result)
             , gateView lvl (m ^. result) gate
             , hintsView m lvl
             , conclusionView m lvl solvedAccepted
             ]

-- | The self-assessment for a pre-test puzzle: two buttons, the current choice
-- highlighted, and a remediation box if the player said they are not familiar.
pretestControls :: GameEnv -> Model -> PuzzleItem -> [View Model Action]
pretestControls env m z
  | puzzleRole z /= PreTest = []
  | otherwise =
      [ H.div_ [ P.class_ "pretest" ]
          ( [ H.p_ [ P.class_ "pretest-q" ]
                [ text "Pre-test — are you already comfortable with this idea?" ]
            , H.div_ [ P.class_ "pretest-btns" ]
                [ choice Familiar    "I already know this"
                , choice NotFamiliar "Not familiar yet"
                ]
            , H.p_ [ P.class_ "pretest-note" ]
                [ text "\x201cI already know this\x201d counts the pre-test as done and jumps you to the next unfinished step." ]
            ]
            <> case ans of
                 Just NotFamiliar ->
                   [ remedyBox env "No problem — review this first, then come back:"
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
lockPanel :: GameEnv -> Model -> PuzzleItem -> View Model Action
lockPanel env m z =
  H.div_ [ P.class_ "locked" ]
    ( [ H.p_ [] [ text (ms msg) ]
      , H.div_ [ P.class_ "lock-jumps" ] (map jumpTo blockers)
      ]
      <> [ remedyBox env "Recommended before this level:" remedies | not (null remedies) ]
      <> [ H.button_ [ P.class_ "secondary", H.onClick (Unlock (puzzleId z)) ]
             [ text "Unlock anyway" ] ]
    )
  where
    blockers = unmetPrereqs (envSlots env) (m ^. solved) (m ^. pretest) z
    remedies = concatMap puzzleRemedy blockers
    names    = T.intercalate ", " (map (levelTitle . puzzleLevel) blockers)
    msg      = "🔒 Locked — finish " <> names <> " first."
    jumpTo pz = case puzzleSlotIndex env (puzzleId pz) of
      Just i  -> H.button_ [ P.class_ "remedy-link", H.onClick (SelectSlot i) ]
                   [ text (ms ("Go to: " <> levelTitle (puzzleLevel pz))) ]
      Nothing -> text ""

-- | A box of remediation links. External targets are anchors; in-game targets
-- are buttons that navigate to the relevant slot.
remedyBox :: GameEnv -> T.Text -> [Remedy] -> View Model Action
remedyBox env heading rs
  | null rs   = text ""
  | otherwise =
      H.div_ [ P.class_ "remedy" ]
        ( H.p_ [ P.class_ "remedy-head" ] [ text (ms heading) ]
        : map (remedyLink env) rs )

remedyLink :: GameEnv -> Remedy -> View Model Action
remedyLink env (Remedy lbl tgt) = case tgt of
  ToExternal url ->
    H.a_ [ P.href_ (ms url), P.target_ "_blank", P.class_ "remedy-link" ]
      [ text (ms lbl) ]
  ToSection sid -> jump (sectionFirstSlot env sid)
  ToLevel pid   -> jump (puzzleSlotIndex env pid)
  where
    jump = \case
      Just i  -> H.button_ [ P.class_ "remedy-link", H.onClick (SelectSlot i) ]
                   [ text (ms lbl) ]
      Nothing -> H.span_ [ P.class_ "remedy-link" ] [ text (ms lbl) ]

-- | The slot index of the first item in a section / of a puzzle by id.
sectionFirstSlot :: GameEnv -> T.Text -> Maybe Int
sectionFirstSlot env sid =
  fst <$> find ((== sid) . slotSectionId . snd) (zip [0 ..] (envSlots env))

puzzleSlotIndex :: GameEnv -> T.Text -> Maybe Int
puzzleSlotIndex env pid = fst <$> find (isPuz . snd) (zip [0 ..] (envSlots env))
  where
    isPuz (SlotPuzzle _ _ z) = puzzleId z == pid
    isPuz _                  = False

-- | A "section complete" badge, shown on a prose page once every required slot
-- of the section is done (so a summary block doubles as a completion marker).
sectionDoneBadge :: GameEnv -> Model -> T.Text -> View Model Action
sectionDoneBadge env m sid
  | sectionComplete (envSlots env) (m ^. solved) (m ^. viewed) (m ^. pretest) sid =
      H.p_ [ P.class_ "section-complete" ]
        [ text (ms ("🎉 Section complete: " <> title)) ]
  | otherwise = text ""
  where
    title = maybe "" sectionTitle (find ((== sid) . sectionId) (envSections env))

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
--
-- Each logical line is wrapped in its own inline @<span>@, with the @\n@
-- separators re-inserted as text between them (so the layer still matches the
-- textarea character for character). A line carrying a diagnostic gets the
-- @hl-errline@ class, which draws a wavy underline — the error squiggle. rzk
-- reports locations at line granularity, so a whole line is underlined.
editorView :: MisoString -> [Int] -> View Model Action
editorView code errLines =
  H.div_ [ P.class_ "editor-wrap" ]
    [ H.pre_ [ P.class_ "editor-hl" ]
        (intersperseNewlines
           [ lineSpan i toks | (i, toks) <- zip [1 ..] (highlightLines (fromMisoString code)) ])
    , H.textarea_
        [ P.class_ "editor"
        , P.rows_ "6"
        , P.value_ code
        , H.onInput SetEditable
        ]
    ]
  where
    errSet = Set.fromList errLines
    lineSpan i toks =
      H.span_ [ P.class_ (ms (lineCls i)) ]
        [ H.span_ [ P.class_ (ms (tokClassName cls)) ] [ text (ms txt) ]
        | Tok cls txt <- toks
        ]
    lineCls :: Int -> T.Text
    lineCls i = "hl-line" <> if Set.member i errSet then " hl-errline" else ""
    -- Put a literal newline back between the per-line spans (none after the last),
    -- so the rendered text reproduces the source exactly.
    intersperseNewlines = \case
      []       -> []
      [v]      -> [v]
      (v : vs) -> v : text "\n" : intersperseNewlines vs

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

-- | The control bar: Check / Format / Undo / Reset and the format-on-check
-- toggle, lifted out of the Moves panel into a sticky footer pinned to the
-- bottom of the level page, so the controls are always in the same place (muscle
-- memory) and never blend into the variable, per-hole move buttons. The Moves
-- panel stays in the document flow beside the goal and holes.
actionBar :: Model -> View Model Action
actionBar m =
  H.div_ [ P.class_ "action-bar" ]
    [ H.div_ [ P.class_ "buttons" ]
        [ H.button_ [ P.class_ "primary", H.onClick Check ] [ text "Check" ]
        , H.button_ [ P.class_ "secondary", H.onClick Format ] [ text "Format" ]
        , H.button_ ( [ P.class_ "secondary", H.onClick Undo ]
                        <> [ P.disabled_ | null (m ^. history) ] )
            [ text "Undo" ]
        , H.button_ [ P.class_ "secondary", H.onClick Reset ] [ text "Reset" ]
        , H.label_ [ P.class_ "format-on-check" ]
            [ H.input_ [ P.type_ "checkbox", P.checked_ (m ^. formatOnCheck)
                       , H.onChecked (\(Checked b) -> SetFormatOnCheck b) ]
            , text " Format on check" ]
        ]
    ]

-- | The collapsible "Allowed here" list: the lemmas and moves the level grants,
-- the visible reference for the inventory gate. Reuses 'levelInventory' (the
-- per-entry display strings) and is hidden on a level with an empty inventory.
inventoryView :: Level -> View Model Action
inventoryView lvl
  | null (levelInventory lvl) = text ""
  | otherwise =
      H.details_ [ P.class_ "inventory-wrap" ]
        [ H.summary_ [] [ text (ms summary) ]
        , H.ul_ [ P.class_ "inventory" ]
            [ H.li_ [] [ text (ms e) ] | e <- levelInventory lvl ]
        ]
  where
    summary :: T.Text
    summary = if levelGated lvl then "Allowed here (gated)" else "Allowed here"

-- | The inventory-gate notice: the prelude lemmas the proof uses that are
-- neither granted nor needed by the intended solution (see 'inventoryViolations',
-- whose allow-list is extended with the reference solution's names — so this
-- never fires on a lemma the solution itself must name). On a gated level it is a
-- blocking red box (the proof does not count until they are gone). On a non-gated
-- level it is a soft hint: the proof still counts, but the intended solution does
-- without these, so a shorter route exists. Empty when there are no violations.
gateView :: Level -> CheckResult -> [T.Text] -> View Model Action
gateView lvl res violations
  | null violations = text ""
  | levelGated lvl  =
      H.div_ [ P.class_ "gate gate-hard" ]
        [ H.p_ [] [ text (ms (hardMsg <> names)) ] ]
  | otherwise =
      H.div_ [ P.class_ "gate gate-soft" ]
        [ H.p_ [] [ text (ms ("Heads up — the intended solution does not use " <> names
                      <> ". Your proof still counts, but there is a shorter route without it.")) ] ]
  where
    names = T.intercalate ", " violations
    hardMsg = case res of
      Solved -> "🔒 So close — but this level grants only the moves under \x201c\&Allowed here\x201d, and your proof uses "
      _      -> "🔒 Not allowed here — this level grants only the moves under \x201c\&Allowed here\x201d, not "

-- | The focused hole's rendered goal, if the proof currently has holes. This is
-- what a hint's @when-goal@ trigger is matched against.
focusedGoal :: CheckResult -> Maybe T.Text
focusedGoal (Holes (h : _)) = Just (hvGoal h)
focusedGoal _               = Nothing

-- | The hint panel: the hints currently visible (plain hints up to the revealed
-- count, plus any contextual when-goal hint whose trigger matches the focused
-- goal), each rendered as prose. The reveal button walks the plain hints only —
-- it never surfaces a contextual hint out of context — so it disappears once
-- every plain hint is showing (and on a solved level, where hints are moot).
-- Hidden entirely on a level with no hints.
hintsView :: Model -> Level -> View Model Action
hintsView m lvl
  | null hs   = text ""
  | otherwise =
      H.div_ [ P.class_ "hints" ]
        ( [ H.h3_ [] [ text "Hints" ] ]
          <> [ hintCard i h | (i, h) <- vis ]
          <> [ revealButton | showButton ] )
  where
    hs         = levelHints lvl
    mgoal      = focusedGoal (m ^. result)
    n          = m ^. hintsShown
    vis        = visibleHints hs mgoal n
    plainN     = plainHintCount hs
    hasCtx     = any ((/= Nothing) . hintWhenGoal) hs
    notSolved  = case m ^. result of Solved -> False; _ -> True
    -- A plain hint left to reveal, or a first "ask" to engage an all-contextual
    -- level's goal-matched hints.
    showButton = notSolved
                   && (n < plainN || (plainN == 0 && n == 0 && hasCtx))
    revealButton =
      H.button_ [ P.class_ "hint-btn", H.onClick RevealHint ]
        [ text (if null vis then "💡 Stuck? Show a hint" else "💡 Show another hint") ]
    -- Each hint is injected as prose (Markdown/TeX via prose.js), keyed by slot
    -- and its position in the authored list so the hook re-fires on navigation
    -- and as a contextual hint appears or disappears.
    hintCard i h =
      H.div_ [ P.class_ "hint prose"
             , key_ (ms ("hint-" <> show (_slotIx m) <> "-" <> show i))
             , onCreatedWith (InitProse (ms (hintText h)))
             ] []

-- | When the level is solved, offer a step onward: the next /incomplete/ slot
-- (an unviewed prose or an unsolved required puzzle), searching forward and
-- wrapping past the end. A closing line shows once everything is done.
advanceView :: GameEnv -> Model -> Bool -> View Model Action
advanceView env m accepted
  | accepted =
      case nextIncomplete env m of
        Just j  -> H.div_ [ P.class_ "advance" ]
                     [ H.button_ [ H.onClick (SelectSlot j) ]
                         [ text (ms ("Next: " <> slotLabel (slotAt env j))) ] ]
        Nothing -> H.div_ [ P.class_ "advance" ]
                     [ H.p_ [ P.class_ "all-done" ]
                         [ text "🏆 You've finished every activity. The end — for now!" ] ]
  | otherwise = text ""

-- | The next incomplete /required/ slot, searching forward from the current one
-- and wrapping past the end. 'Nothing' when everything required is done.
nextIncomplete :: GameEnv -> Model -> Maybe Int
nextIncomplete env m =
  nextIncompleteFrom env (_slotIx m) (m ^. solved) (m ^. viewed) (m ^. pretest)

-- | 'nextIncomplete' over the bare progress components, so the update function
-- can call it without reassembling a 'Model'.
nextIncompleteFrom
  :: GameEnv -> Int -> Set Int -> Set T.Text -> Map T.Text PretestAnswer -> Maybe Int
nextIncompleteFrom env cur solvedIxs viewedIds answers = find incomplete order
  where
    n     = length (envSlots env)
    order = [ (cur + k) `mod` n | k <- [1 .. n - 1] ]
    incomplete i =
      let s = slotAt env i
      in slotRequired s && not (slotDone solvedIxs viewedIds answers s)

-- | A linear navigation bar over all slots: previous, the current slot's label,
-- then next. Adjacent navigation, disabled at the ends; the picker above remains
-- the way to jump anywhere.
navBar :: GameEnv -> Model -> View Model Action
navBar env m =
  H.div_ [ P.class_ "nav" ]
    [ navButton "prev" "← Previous: " (cur - 1) (cur > 0)
    , H.span_ [ P.class_ "nav-current" ]
        [ text (ms ("Step " <> tshow (cur + 1) <> " / " <> tshow (length (envSlots env)))) ]
    , navButton "next" "Next: " (cur + 1) (cur < length (envSlots env) - 1)
    ]
  where
    cur = _slotIx m
    -- When a neighbour exists, name it; at an end, fall back to a plain label.
    navButton dir prefix j enabled =
      H.button_ ( [ P.class_ (ms ("nav-" <> dir :: T.Text))
                  , H.onClick (SelectSlot j) ]
                    <> [ P.disabled_ | not enabled ] )
        [ text (ms (if enabled
                      then prefix <> slotLabel (slotAt env j)
                      else if dir == "prev" then "← Previous" else "Next →")) ]

-- | A short human label for a slot, for the nav bar.
slotLabel :: Slot -> T.Text
slotLabel (SlotProse  _ p)    = proseTitle p
slotLabel (SlotPuzzle _ ix z) = tshow (ix + 1) <> ". " <> levelTitle (puzzleLevel z)

-- | A ready-to-paste bug report for a checker crash: the level's prelude, the
-- player's current definition, and the error. The "Copy issue report" button in
-- the crash panel puts this on the clipboard, GitHub-Markdown formatted.
crashReport :: Level -> T.Text -> T.Text -> T.Text
crashReport lvl editable err = T.unlines
  [ "The rzk typechecker crashed in rzk-game."
  , ""
  , "**Prelude:**"
  , "```rzk"
  , T.stripEnd (levelPrelude lvl)
  , "```"
  , ""
  , "**Definition:**"
  , "```rzk"
  , T.stripEnd editable
  , "```"
  , ""
  , "**Error:**"
  , "```"
  , T.stripEnd err
  , "```"
  ]

-- | A small status line above the result: while the editor has been changed
-- since the shown result was checked, it flags that the result is stale. (With
-- the check running synchronously the result is otherwise always current; this
-- covers the gap after typing, before the next Check or tap.)
checkStatusView :: Model -> View Model Action
checkStatusView m
  | m ^. dirty && notChecked = text ""   -- nothing checked yet: no stale result to flag
  | m ^. dirty               =
      H.p_ [ P.class_ "check-stale" ]
        [ text "● Edited since last check — press Check to update the result." ]
  | otherwise                = text ""
  where notChecked = case m ^. result of NotChecked -> True; _ -> False

resultView :: Level -> MisoString -> CheckResult -> View Model Action
resultView lvl editable = \case
  NotChecked     -> H.pre_ [] [ text "(press Check)" ]
  ParseError e _ -> H.pre_ [ P.class_ "err" ] [ text (ms ("Parse error:\n" <> e)) ]
  -- The rzk type-error formatter is verbose (a "when typechecking …" trace per
  -- lambda layer). Lead with a friendly line and keep the full report in a
  -- height-capped, scrollable box so it does not run down the page. The line(s)
  -- the error points at are squiggled in the editor above (see 'editorView').
  TypeError e _  ->
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
  CheckerCrashed e ->
    H.div_ [ P.class_ "err" ]
      [ H.p_ [] [ text "⚠ The checker hit a bug on this input, not necessarily a mistake in your proof." ]
      , H.p_ []
          [ H.button_ [ P.class_ "copy-report"
                      , H.onClick (CopyText (ms (crashReport lvl (fromMisoString editable) e)))
                      , P.title_ "Copy a ready-to-paste issue report (prelude, your definition, and the error)" ]
              [ text "📋 Copy issue report" ]
          , text " then "
          , H.a_ [ P.href_ "https://github.com/rzk-lang/rzk-game/issues/new"
                 , P.target_ "_blank" ] [ text "open an issue" ]
          , text " and paste it."
          ]
      , H.pre_ [ P.class_ "errdump" ] [ text (ms e) ]
      ]

-- | The level conclusion prose. The div is keyed by slot, so it is recreated on
-- navigation (and the prose re-injected); it is revealed once the level solves.
conclusionView :: Model -> Level -> Bool -> View Model Action
conclusionView m lvl accepted =
  H.div_ [ P.class_ (ms cls)
         , key_ (ms ("concl-" <> show (_slotIx m)))
         , onCreatedWith (InitProse (ms (levelConclusion lvl)))
         ] []
  where
    cls :: T.Text
    cls = if accepted then "prose concl shown" else "prose concl hidden"

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
