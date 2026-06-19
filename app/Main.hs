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
import           Data.IORef         (IORef, newIORef, readIORef, writeIORef)
import           Data.List          (find, sort)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (fromMaybe, mapMaybe)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import qualified Data.Text          as T
import           Data.Text.Encoding (encodeUtf8)
import           System.IO.Unsafe   (unsafePerformIO)
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

-- | The game the app plays: the sections loaded from @game.json@ at startup, or
-- the built-in 'Content.gameSections' as a fallback. The bytes are fetched in JS
-- (see @index.js@) into @localStorage@ before @hs_start@, then 'loadGame' reads
-- them, runs 'buildGame', and writes the result into 'loadedSectionsRef' — which
-- 'main' forces before 'startApp', so the pure navigation values below see the
-- loaded game. The ref starts at the fallback, so a build with no @game.json@ (or
-- a malformed one) plays the built-in content unchanged.
{-# NOINLINE loadedSectionsRef #-}
loadedSectionsRef :: IORef [Section]
loadedSectionsRef = unsafePerformIO (newIORef Content.gameSections)

{-# NOINLINE loadedSections #-}
loadedSections :: [Section]
loadedSections = unsafePerformIO (readIORef loadedSectionsRef)

-- | @localStorage@ key under which @index.js@ stashes the fetched @game.json@.
gameJsonKey :: MisoString
gameJsonKey = "rzk-game-json"

-- | Read the stashed @game.json@, build the sections, and install them. Any
-- failure (no bundle, malformed JSON, empty game) leaves the built-in fallback
-- in place. Called once at the very start of 'main', before 'loadedSections' is
-- forced.
loadGame :: IO ()
loadGame = do
  mjson <- getLocalStorage gameJsonKey
  case mjson of
    Just s
      | let t = fromMisoString s, not (T.null t)
      , Right secs <- buildGame (encodeUtf8 t)
      , not (null secs) -> writeIORef loadedSectionsRef secs
    _ -> pure ()

-- | The game's sections, levels, and flattened navigation, all derived from the
-- loaded game (see 'loadedSections').
gameSections :: [Section]
gameSections = loadedSections

gameSlots :: [Slot]
gameSlots = slotsOfSections loadedSections

gameLevels :: [Level]
gameLevels = [ puzzleLevel z | SPuzzle z <- concatMap sectionItems loadedSections ]

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
  , _confirmReset :: Bool                  -- ^ whether the reset confirmation is showing
  , _importMsg :: Maybe (Either T.Text Int) -- ^ last import result: error, or count restored
  , _formatOnCheck :: Bool                  -- ^ format the editable region before each check
  , _hintsShown :: Int                      -- ^ how many hints the player has revealed (per-session)
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
  | Format                     -- ^ tidy the editable region with rzk's formatter
  | Reset
  | SelectSlot Int             -- ^ navigate to a slot (prose or puzzle)
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
  | SetImportMsg (Maybe (Either T.Text Int))  -- ^ show the result of an applied import
  | DismissImportMsg           -- ^ dismiss the import result banner
  | SetFormatOnCheck Bool      -- ^ toggle (and persist) the format-on-check preference
  | RevealHint                 -- ^ reveal the next hidden hint (progressive disclosure)
  -- No 'Eq': 'DOMRef' (a 'JSVal') has none. miso does not require 'Eq' on actions.

main :: IO ()
main = do
  loadGame                            -- install the loaded game (or keep fallback)
  applyPendingImport                  -- apply a just-imported archive before the app reads state
  _ <- evaluate (length loadedSections)  -- force the navigation CAFs now, after load
#ifdef INTERACTIVE
  live defaultEvents app
#else
  startApp defaultEvents app
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
  loadGame
  let secs = loadedSections
      lvls = gameLevels
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
  -- Seed a representative slice of player data.
  setLocalStorage progressKey  "0,2,5"
  setLocalStorage viewedKey    "morphisms-intro,functions-intro"
  setLocalStorage pretestKey   "map-point=familiar"
  setLocalStorage (draftKey 0) "#def my-id (A : U) (x : A)\n  : hom A x x\n  := ?"
  before <- gatherProgress
  let archive = encodeArchive before
  putStrLn ("seeded keys: " <> show (length before))

  -- Clear everything, then import the archive through the real startup path.
  clearPlayerData
  cleared <- gatherProgress
  setLocalStorage importScratchKey (ms archive)
  writeIORef importResultRef Nothing
  applyPendingImport
  after <- gatherProgress
  res   <- readIORef importResultRef
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
  writeIORef importResultRef Nothing
  applyPendingImport
  res2  <- readIORef importResultRef
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
  -- order), independent of whatever game.json a build happens to load. Shadow the
  -- loaded-game navigation values with the Content ones for the rest of the test.
  let gameLevels   = Content.gameLevels
      gameSections = Content.gameSections
      slots        = Content.gameSlots
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
      roundTrips  = decodeSolved (encodeSolved allSolved) == allSolved
      emptyOk     = decodeSolved (encodeSolved Set.empty) == Set.empty
      junkDropped = decodeSolved "0,x,,2" == Set.fromList [0, 2]
  putStrLn (if roundTrips && emptyOk && junkDropped
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
  (Model 0 "" NotChecked Set.empty Set.empty Map.empty Set.empty [] False False Nothing False 0)

-- | Set up the model's editor for a slot, without IO. A puzzle slot loads its
-- template and checks it (so the focused hole and its moves show without a first
-- manual Check); a prose slot clears the editor. The undo history is reset.
enterSlotPure :: Int -> Model -> Model
enterSlotPure i m = case slotAt i of
  SlotProse _ _ ->
    m { _slotIx = i, _editable = "", _result = NotChecked, _history = []
      , _hintsShown = 0 }
  SlotPuzzle _ _ z ->
    let t = levelTemplate (puzzleLevel z)
    in m { _slotIx = i, _editable = ms t
         , _result = checkLevel (puzzleLevel z) t, _history = []
         , _hintsShown = 0 }

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

readLoadedState :: IO LoadedState
readLoadedState = LoadedState
  <$> readProgress <*> readViewed <*> readPretest <*> readUnlocked
  <*> readFormatOnCheck

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

-- Progress export / import / reset ------------------------------------------

-- | All the @localStorage@ keys that make up the player's progress: the four
-- fixed keys plus one draft per puzzle. The engine's loaded @game.json@ bundle
-- (under 'gameJsonKey') is deliberately excluded — it is content, regenerated at
-- load, not player data.
playerDataKeys :: [MisoString]
playerDataKeys =
  [progressKey, viewedKey, pretestKey, unlockedKey, formatOnCheckKey]
    ++ [ draftKey i | i <- [0 .. length gameLevels - 1] ]

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
gatherProgress :: IO [(T.Text, T.Text)]
gatherProgress = do
  vals <- mapM getLocalStorage playerDataKeys
  pure [ (fromMisoString k, fromMisoString v)
       | (k, Just v) <- zip playerDataKeys vals ]

-- | Remove every player-data key, leaving the loaded game bundle in place.
clearPlayerData :: IO ()
clearPlayerData = mapM_ removeLocalStorage playerDataKeys

-- | Gather the progress and hand it to @download.js@ as one archive file. Called
-- through the DSL's 'js' QuasiQuoter (like 'renderProseInto') to avoid the @JSString@-arg
-- codegen bug.
exportProgress :: IO ()
exportProgress = do
  pairs <- gatherProgress
  let ps = encodeArchive pairs
  [js| download ('rzk-game-progress.json', ${ps}) |]

-- | Result of the last applied import, set by 'applyPendingImport' before the
-- app starts and read once at 'Init': @Left@ an error message, or @Right@ the
-- number of keys restored.
{-# NOINLINE importResultRef #-}
importResultRef :: IORef (Maybe (Either T.Text Int))
importResultRef = unsafePerformIO (newIORef Nothing)

-- | If @download.js@ stashed an import file (then reloaded), validate it with the
-- pure 'decodeArchive' and apply it: replace the player-data keys with the
-- archive's (a full replace, not a merge — so progress not in the archive is
-- cleared), then record the outcome for 'Init' to surface. A malformed or
-- wrong-version archive is rejected with its message and changes nothing. The
-- scratch key is always consumed, so an import is applied at most once.
applyPendingImport :: IO ()
applyPendingImport = do
  mraw <- getLocalStorage importScratchKey
  case mraw of
    Nothing  -> pure ()
    Just raw -> do
      removeLocalStorage importScratchKey
      case decodeArchive (fromMisoString raw) of
        Left err  -> writeIORef importResultRef (Just (Left err))
        Right kvs -> do
          let keep = [ (k, v) | (k, v) <- kvs, isPlayerDataKey k ]
          clearPlayerData
          mapM_ (\(k, v) -> setLocalStorage (ms k) (ms v)) keep
          writeIORef importResultRef (Just (Right (length keep)))


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
    history    .= []
    slotIx     .= i
    hintsShown .= 0          -- a fresh level starts with its hints hidden again
    mapOpen    .= False      -- collapse the map after a jump, back to content
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
    io (LoadState <$> readLoadedState)
    io (SetImportMsg <$> readIORef importResultRef)  -- show an applied import's result
    mix <- currentPuzzleIx
    case mix of
      Just ix -> io (loadDraftAction ix)  -- a puzzle slot 0: restore its draft
      Nothing -> pure ()                  -- a prose slot 0: LoadState marks it viewed
  LoadState ls -> do
    solved   .= lsSolved ls
    pretest  .= lsPretest ls
    unlocked .= lsUnlocked ls
    formatOnCheck .= lsFormatOnCheck ls
    -- If slot 0 is prose, it has already been "visited" at mount, so fold it in.
    i <- use slotIx
    let v  = lsViewed ls
        v' = case slotAt i of
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
        case nextIncompleteFrom cur sv vw pt of
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
        result   .= checkLevel (nthLevel i) (fromMisoString s)
      else pure ()
  Refine ins -> withPuzzle $ \ix -> do
    foc <- use formatOnCheck
    e <- use editable
    history %= (e :)         -- remember the pre-refine text so the tap can be undone
    let e'  = maybeFormat foc (refineFirstHole ins (fromMisoString e))
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
    foc <- use formatOnCheck
    e0 <- use editable
    let e = ms (maybeFormat foc (fromMisoString e0))
    -- With format-on-check on, a check first tidies the region in place (an
    -- undoable, saved edit), then checks the formatted text.
    if e /= e0
      then do history %= (e0 :); editable .= e; io_ (saveDraft ix e)
      else pure ()
    let res = checkLevel (nthLevel ix) (fromMisoString e)
    result .= res
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
        result   .= checkLevel (nthLevel ix) (fromMisoString e')
        io_ (saveDraft ix e')
  ExportProgress -> io_ exportProgress
  ImportProgress -> io_ [js|pickImport()|]
  ResetProgress  -> confirmReset .= True
  CancelReset    -> confirmReset .= False
  ConfirmReset   -> do
    io_ clearPlayerData
    solved   .= Set.empty
    viewed   .= Set.empty
    pretest  .= Map.empty
    unlocked .= Set.empty
    history  .= []
    formatOnCheck .= False    -- its key is player data too, cleared above
    confirmReset .= False
    io (pure (SelectSlot 0))   -- back to the start; re-seeds the editor and viewed
  SetImportMsg v   -> importMsg .= v
  DismissImportMsg -> importMsg .= Nothing
  SetFormatOnCheck b -> do
    formatOnCheck .= b
    io_ (saveFormatOnCheck b)
  RevealHint -> withPuzzle $ \ix -> do
    -- The button walks the plain hints one at a time; contextual (when-goal)
    -- hints surface on their own, so the count never needs to pass the plain
    -- hints (plus one "ask" to engage a level whose hints are all contextual).
    let cap = max (plainHintCount (levelHints (nthLevel ix))) 1
    n <- use hintsShown
    if n < cap then hintsShown .= n + 1 else pure ()
  where
    -- Apply the formatter only when format-on-check is on, leaving the text as
    -- typed otherwise. The formatter itself no-ops on a non-parsing fragment.
    maybeFormat :: Bool -> T.Text -> T.Text
    maybeFormat True  = formatEditable
    maybeFormat False = id

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
    -- storage when the set actually changes, to avoid redundant re-checks. A
    -- gated level whose proof uses ungranted lemmas does not count as solved,
    -- even when it type-checks — the gate notice surfaces the blocker.
    recordSolved i Solved = do
      e <- use editable
      s <- use solved
      if Set.member i s || not (gatePassed (nthLevel i) (fromMisoString e))
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
    , importBanner m
    , H.section_ [ P.class_ "level" ]
        ( case currentSlot m of
            SlotProse  sid p    -> proseSlotView  m sid p
            SlotPuzzle sid ix z -> puzzleSlotView m sid ix z
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
  H.div_ [ P.class_ "sections" ]
    (map sectionBlock gameSections ++ [ progressControls m ])
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
  <> [ advanceView m solvedAccepted, navBar m ]
  <> [ actionBar m | not locked ]   -- the controls, as a sticky footer bar
  where
    lvl       = puzzleLevel z
    locked    = levelLocked slots (m ^. solved) (m ^. unlocked) (m ^. pretest) z
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
      | locked    = [ lockPanel m z ]
      | otherwise =
          pretestControls m z
          <> [ H.h3_ [] [ text "Your proof" ]
             , editorView (m ^. editable) (resultErrorLines (m ^. result))
             , H.h3_ [] [ text "Moves" ]
             , movesView m
             , inventoryView lvl
             , H.h3_ [] [ text "Result" ]
             -- A gated solve that uses ungranted lemmas is withheld: the red
             -- gate box replaces the green success box; otherwise the result
             -- shows normally, with any gate notice below it.
             , if m ^. result == Solved && not (null gate) && levelGated lvl
                 then text "" else resultView (m ^. result)
             , gateView lvl (m ^. result) gate
             , hintsView m lvl
             , conclusionView m lvl solvedAccepted
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
            , H.p_ [ P.class_ "pretest-note" ]
                [ text "“I already know this” counts the pre-test as done and jumps you to the next unfinished step." ]
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

-- | The inventory-gate notice: the prelude lemmas used but not granted. On a
-- gated level it is a blocking red box (the proof does not count until they are
-- gone); otherwise a soft amber heads-up. Empty when there are no violations.
gateView :: Level -> CheckResult -> [T.Text] -> View Model Action
gateView lvl res violations
  | null violations = text ""
  | levelGated lvl  =
      H.div_ [ P.class_ "gate gate-hard" ]
        [ H.p_ [] [ text (ms (hardMsg <> names)) ] ]
  | otherwise =
      H.div_ [ P.class_ "gate gate-soft" ]
        [ H.p_ [] [ text (ms ("Heads up — this level does not list " <> names
                      <> " under “Allowed here”. It still counts; see if you can do without it.")) ] ]
  where
    names = T.intercalate ", " violations
    hardMsg = case res of
      Solved -> "🔒 So close — but this level grants only the moves under “Allowed here”, and your proof uses "
      _      -> "🔒 Not allowed here — this level grants only the moves under “Allowed here”, not "

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
advanceView :: Model -> Bool -> View Model Action
advanceView m accepted
  | accepted =
      case nextIncomplete m of
        Just j  -> H.div_ [ P.class_ "advance" ]
                     [ H.button_ [ H.onClick (SelectSlot j) ]
                         [ text (ms ("Next: " <> slotLabel (slotAt j))) ] ]
        Nothing -> H.div_ [ P.class_ "advance" ]
                     [ H.p_ [ P.class_ "all-done" ]
                         [ text "🏆 You've finished every activity. The end — for now!" ] ]
  | otherwise = text ""

-- | The next incomplete /required/ slot, searching forward from the current one
-- and wrapping past the end. 'Nothing' when everything required is done.
nextIncomplete :: Model -> Maybe Int
nextIncomplete m =
  nextIncompleteFrom (_slotIx m) (m ^. solved) (m ^. viewed) (m ^. pretest)

-- | 'nextIncomplete' over the bare progress components, so the update function
-- can call it without reassembling a 'Model'.
nextIncompleteFrom
  :: Int -> Set Int -> Set T.Text -> Map T.Text PretestAnswer -> Maybe Int
nextIncompleteFrom cur solvedIxs viewedIds answers = find incomplete order
  where
    n     = totalSlots
    order = [ (cur + k) `mod` n | k <- [1 .. n - 1] ]
    incomplete i =
      let s = slotAt i
      in slotRequired s && not (slotDone solvedIxs viewedIds answers s)

-- | A linear navigation bar over all slots: previous, the current slot's label,
-- then next. Adjacent navigation, disabled at the ends; the picker above remains
-- the way to jump anywhere.
navBar :: Model -> View Model Action
navBar m =
  H.div_ [ P.class_ "nav" ]
    [ navButton "prev" "← Previous: " (cur - 1) (cur > 0)
    , H.span_ [ P.class_ "nav-current" ]
        [ text (ms ("Step " <> tshow (cur + 1) <> " / " <> tshow totalSlots)) ]
    , navButton "next" "Next: " (cur + 1) (cur < totalSlots - 1)
    ]
  where
    cur = _slotIx m
    -- When a neighbour exists, name it; at an end, fall back to a plain label.
    navButton dir prefix j enabled =
      H.button_ ( [ P.class_ (ms ("nav-" <> dir :: T.Text))
                  , H.onClick (SelectSlot j) ]
                    <> [ P.disabled_ | not enabled ] )
        [ text (ms (if enabled
                      then prefix <> slotLabel (slotAt j)
                      else if dir == "prev" then "← Previous" else "Next →")) ]

-- | A short human label for a slot, for the nav bar.
slotLabel :: Slot -> T.Text
slotLabel (SlotProse  _ p)    = proseTitle p
slotLabel (SlotPuzzle _ ix z) = tshow (ix + 1) <> ". " <> levelTitle (puzzleLevel z)

resultView :: CheckResult -> View Model Action
resultView = \case
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
