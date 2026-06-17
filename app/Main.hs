{-# LANGUAGE CPP               #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The L0 user interface: a level picker, a textarea for the editable region,
-- the derived tap-to-refine moves, a Check button, and a panel that renders the
-- result — each unsolved hole's goal and three-section context, a type error, or
-- the success state with a path on to the next level. This is the minimal
-- rendering of the signed-off interaction model (textarea + panels).
module Main (main) where

import           Miso
import qualified Miso.Html          as H
import qualified Miso.Html.Property as P
import           Miso.DSL           (fromJSValUnchecked, jsg1)
import           Miso.Property      (textProp)
import           Miso.Lens
import           Miso.String        (MisoString, fromMisoString, ms)

import           Control.Monad      (when)
import           Data.List          (find)
import           Data.Maybe         (fromMaybe, mapMaybe)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import qualified Data.Text          as T
import           Text.Read          (readMaybe)

import           RzkGame.Content    (apHomLevel, composeLevel,
                                     composeWitnessLevel, constTriangleLevel,
                                     gameLevels, hom2Level, homLeftUnitLevel,
                                     idMorphismLevel, mapPointLevel)
import           RzkGame.Highlight  (Tok (..), highlight, tokClassName)
import           RzkGame.Level

-- | Render a level's Markdown/TeX prose to HTML by calling the global
-- @renderProse@ (marked + KaTeX; see @prose.js@) through miso's JS DSL. Called
-- once per level load; the result is stored in the model and injected as
-- @innerHTML@. We go through @jsg1@ rather than a raw @foreign import@ because
-- marshalling a @JSString@ argument directly trips a codegen bug in the current
-- wasm toolchain.
js_renderProse :: MisoString -> IO MisoString
js_renderProse src = jsg1 "renderProse" src >>= fromJSValUnchecked

-- | UI state: which level is being played, the player's current text, the last
-- check result, and the set of solved levels (by index). The solved set is
-- persisted to @localStorage@, so progress survives a reload.
data Model = Model
  { _levelIx  :: Int
  , _editable :: MisoString
  , _result   :: CheckResult
  , _solved   :: Set Int
  , _history  :: [MisoString]   -- ^ prior editable states (newest first), for Undo
  , _proseIntro :: MisoString   -- ^ the level intro, rendered to HTML (Markdown/TeX)
  , _proseConcl :: MisoString   -- ^ the level conclusion, rendered to HTML
  } deriving (Eq)

levelIx :: Lens Model Int
levelIx = lens _levelIx $ \m v -> m { _levelIx = v }

editable :: Lens Model MisoString
editable = lens _editable $ \m v -> m { _editable = v }

result :: Lens Model CheckResult
result = lens _result $ \m v -> m { _result = v }

solved :: Lens Model (Set Int)
solved = lens _solved $ \m v -> m { _solved = v }

history :: Lens Model [MisoString]
history = lens _history $ \m v -> m { _history = v }

proseIntro :: Lens Model MisoString
proseIntro = lens _proseIntro $ \m v -> m { _proseIntro = v }

proseConcl :: Lens Model MisoString
proseConcl = lens _proseConcl $ \m v -> m { _proseConcl = v }

-- | The level currently being played.
currentLevel :: Model -> Level
currentLevel m = nthLevel (_levelIx m)

-- | Index the level list. (Miso's DSL re-exports @(!!)@ as a JS property
-- accessor, shadowing Prelude's list index, so we avoid it here.)
nthLevel :: Int -> Level
nthLevel i = head (drop i gameLevels)

data Action
  = SetEditable MisoString
  | Refine T.Text
  | Undo                    -- ^ revert the last tap-to-refine or Reset
  | Check
  | Reset
  | SelectLevel Int
  | Init                    -- ^ dispatched at mount: load saved progress + draft
  | SetSolved (Set Int)
  | ApplyText Int MisoString  -- ^ install a level's restored draft (or template)
  | SetProse Int MisoString MisoString  -- ^ install a level's rendered prose
  deriving (Eq)

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
-- the first level's tap-to-refine, the type-error paths, and the smart
-- inventory.
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
#endif
#endif

app :: App Model Action
app = (component initModel updateModel viewModel)
  { mount = Just Init }   -- seed the solved set and the level-0 draft from storage

initModel :: Model
initModel = loadLevel 0

-- | A fresh model for the level at the given index: its template, checked so
-- the focused hole and its moves show without a first manual Check. The solved
-- set starts empty; @LoadProgress@ fills it from storage at mount.
loadLevel :: Int -> Model
loadLevel i = Model i (ms template) (checkLevel lvl template) Set.empty [] "" ""
  where
    lvl      = nthLevel i
    template = levelTemplate lvl

-- | The localStorage key under which the solved set is persisted.
progressKey :: MisoString
progressKey = "rzk-game-progress"

-- | The solved set is stored as a comma-separated list of level indices, e.g.
-- @"0,1"@. Unparseable or out-of-range entries are dropped on load, so a stale
-- value from an older level list cannot crash the game.
encodeSolved :: Set Int -> MisoString
encodeSolved = ms . T.intercalate "," . map (T.pack . show) . Set.toList

decodeSolved :: MisoString -> Set Int
decodeSolved =
  Set.fromList . mapMaybe (readMaybe . T.unpack) . T.splitOn "," . fromMisoString

-- | Read the persisted solved set (empty if nothing is stored).
readProgress :: IO (Set Int)
readProgress = maybe Set.empty decodeSolved <$> getLocalStorage progressKey

-- | Persist the solved set.
saveProgress :: Set Int -> IO ()
saveProgress = setLocalStorage progressKey . encodeSolved

-- | Per-level draft storage. Each level's in-progress text is saved under its
-- own key, so the raw source needs no escaping (unlike a single packed value).
-- A draft for a level no longer in the list simply lingers, harmlessly unread.
draftKey :: Int -> MisoString
draftKey i = "rzk-game-draft-" <> ms (show i)

-- | Save / clear a level's draft.
saveDraft :: Int -> MisoString -> IO ()
saveDraft i = setLocalStorage (draftKey i)

removeDraft :: Int -> IO ()
removeDraft = removeLocalStorage . draftKey

-- | Read a level's saved draft, falling back to its template when none is
-- stored, and return the action that installs it. The index is carried so the
-- update can ignore a stale read after a quick level switch.
loadDraftAction :: Int -> IO Action
loadDraftAction i =
  ApplyText i . fromMaybe (ms (levelTemplate (nthLevel i))) <$> getLocalStorage (draftKey i)

-- | Render a level's intro and conclusion prose (Markdown/TeX → HTML) and return
-- the action that installs them. Carries the index so a stale render after a
-- quick level switch is ignored.
loadProseAction :: Int -> IO Action
loadProseAction i = do
  let lvl = nthLevel i
  intro <- js_renderProse (ms (levelIntro lvl))
  concl <- js_renderProse (ms (levelConclusion lvl))
  pure (SetProse i intro concl)

updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  SetEditable s -> do
    editable .= s
    i <- use levelIx
    io_ (saveDraft i s)
  SelectLevel i -> do
    history .= []            -- each level keeps its own, fresh undo history
    reload i
    io (loadDraftAction i)   -- override the template with a saved draft, if any
    io (loadProseAction i)   -- render this level's prose
  Reset         -> do
    i <- use levelIx
    e <- use editable
    history %= (e :)         -- a mistaken Reset can be undone
    reload i
    io_ (removeDraft i)      -- drop the draft so the template stays on next load
  Init          -> do
    io (SetSolved <$> readProgress)
    i <- use levelIx
    io (loadDraftAction i)
    io (loadProseAction i)
  SetSolved s   -> solved .= s
  SetProse i intro concl -> do
    cur <- use levelIx
    when (cur == i) $ do
      proseIntro .= intro
      proseConcl .= concl
  ApplyText i s -> do
    -- Ignore a draft that arrived after the player moved to another level.
    cur <- use levelIx
    when (cur == i) $ do
      editable .= s
      result   .= checkLevel (nthLevel i) (fromMisoString s)
  Refine ins    -> do
    i <- use levelIx
    e <- use editable
    history %= (e :)         -- remember the pre-refine text so the tap can be undone
    let e'  = refineFirstHole ins (fromMisoString e)
        res = checkLevel (nthLevel i) e'
    editable .= ms e'
    result   .= res
    io_ (saveDraft i (ms e'))
    recordSolved i res
  Undo          -> do
    hs <- use history
    case hs of
      []            -> pure ()
      (prev : rest) -> do
        i <- use levelIx
        history  .= rest
        editable .= prev
        result   .= checkLevel (nthLevel i) (fromMisoString prev)
        io_ (saveDraft i prev)
  Check         -> do
    i <- use levelIx
    e <- use editable
    let res = checkLevel (nthLevel i) (fromMisoString e)
    result .= res
    recordSolved i res
  where
    -- Load a level's template into the model and check it, so the focused hole
    -- and its moves show without a first manual Check (and immediately, before
    -- any saved draft is read back). The solved set is left untouched, so
    -- switching levels preserves progress.
    reload i = do
      levelIx  .= i
      editable .= ms (levelTemplate (nthLevel i))
      result   .= checkLevel (nthLevel i) (levelTemplate (nthLevel i))

    -- On a solved level, record it and persist the updated set. We only write to
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
    , H.section_ [ P.class_ "level" ]
        [ levelPicker m

        , H.h2_ [] [ text (ms (titleMark <> levelTitle lvl)) ]
        , H.div_ [ P.class_ "prose", textProp "innerHTML" (m ^. proseIntro) ] []

        , H.h3_ [] [ text "Goal" ]
        , H.pre_ [ P.class_ "goal" ] [ text (ms (levelStatement lvl)) ]

        , preludeView lvl

        , H.h3_ [] [ text "Your proof" ]
        , editorView (m ^. editable)
        , H.h3_ [] [ text "Moves" ]
        , movesView m
        , H.div_ [ P.class_ "buttons" ]
            [ H.button_ [ P.class_ "primary",   H.onClick Check ] [ text "Check" ]
            , H.button_ ( [ P.class_ "secondary", H.onClick Undo ]
                            <> [ P.disabled_ | null (m ^. history) ] )
                [ text "Undo" ]
            , H.button_ [ P.class_ "secondary", H.onClick Reset ] [ text "Reset" ]
            ]

        , H.h3_ [] [ text "Result" ]
        , resultView (m ^. proseConcl) (m ^. result)
        , advanceView m
        , navBar m
        ]
    ]
  where
    lvl       = currentLevel m
    -- A solved tick on the current level's heading, echoing the level picker.
    titleMark = if isSolved m (_levelIx m) then "✓ " else ""

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

-- | The level selector: one button per level, the current one highlighted and
-- each solved one marked with a tick. Navigation stays free — every level is
-- always reachable. A badge underneath counts progress towards completion.
levelPicker :: Model -> View Model Action
levelPicker m =
  H.div_ []
    [ H.div_ [ P.class_ "levels" ] (map button [0 .. total - 1])
    , progressBadge m
    ]
  where
    total    = length gameLevels
    button i = H.button_
      [ H.onClick (SelectLevel i), P.class_ (ms (cls i)) ]
      [ text (ms (mark i <> T.pack (show (i + 1)) <> ". " <> levelTitle (nthLevel i))) ]
    cls i = T.unwords $ ["current" | i == _levelIx m]
                     <> ["solved"  | isSolved m i]
    mark i = if isSolved m i then "✓ " else ""

-- | Whether the level at the given index has been solved.
isSolved :: Model -> Int -> Bool
isSolved m i = Set.member i (m ^. solved)

-- | How many of the current levels are solved (stale stored indices, beyond the
-- present level list, do not count).
solvedCount :: Model -> Int
solvedCount m = length (filter (isSolved m) [0 .. length gameLevels - 1])

-- | A progress line under the picker: an "N / M solved" count, or a trophy when
-- every level is done.
progressBadge :: Model -> View Model Action
progressBadge m
  | done == total && total > 0 =
      H.p_ [ P.class_ "progress done" ]
        [ text (ms ("🏆 All " <> T.pack (show total) <> " levels solved!")) ]
  | otherwise =
      H.p_ [ P.class_ "progress" ]
        [ text (ms (T.pack (show done) <> " / " <> T.pack (show total) <> " solved")) ]
  where
    done  = solvedCount m
    total = length gameLevels

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

-- | When the level is solved, offer a step onward: the next /unsolved/ level,
-- searching forward and wrapping past the end, so the button still helps on the
-- last level when an earlier one is unfinished. A closing line shows once every
-- level is done.
advanceView :: Model -> View Model Action
advanceView m
  | Solved <- m ^. result =
      case nextUnsolved m of
        Just j  -> H.div_ [ P.class_ "advance" ]
                     [ H.button_ [ H.onClick (SelectLevel j) ]
                         [ text "Next unsolved level →" ] ]
        Nothing -> H.div_ [ P.class_ "advance" ]
                     [ H.p_ [ P.class_ "all-done" ]
                         [ text "🏆 You've solved every level. The end — for now!" ] ]
  | otherwise = text ""

-- | The next unsolved level, searching forward from the current one and wrapping
-- past the end (the current level is excluded). 'Nothing' when all are solved.
nextUnsolved :: Model -> Maybe Int
nextUnsolved m = find (not . isSolved m) order
  where
    n     = length gameLevels
    order = [ (_levelIx m + k) `mod` n | k <- [1 .. n - 1] ]

-- | A linear navigation bar: previous level, the current level's number, title,
-- and solved status, then next level. Adjacent navigation, disabled at the ends;
-- the level picker above remains the way to jump anywhere.
navBar :: Model -> View Model Action
navBar m =
  H.div_ [ P.class_ "nav" ]
    [ navButton "← Previous" (cur - 1) (cur > 0)
    , H.span_ [ P.class_ "nav-current" ]
        [ text (ms ( "Level " <> tshow (cur + 1) <> " / " <> tshow total
                       <> " — " <> levelTitle (nthLevel cur)
                       <> (if isSolved m cur then " ✓" else "") )) ]
    , navButton "Next →" (cur + 1) (cur < total - 1)
    ]
  where
    cur    = _levelIx m
    total  = length gameLevels
    tshow  = T.pack . show
    navButton lbl j enabled =
      H.button_ ( [ H.onClick (SelectLevel j) ] <> [ P.disabled_ | not enabled ] )
        [ text lbl ]

resultView :: MisoString -> CheckResult -> View Model Action
resultView conclHtml = \case
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
      [ H.pre_ [] [ text "✓ Solved — no holes, typechecks. Level complete!" ]
      , H.div_ [ P.class_ "prose", textProp "innerHTML" conclHtml ] []
      ]
  Holes hs ->
    H.div_ [ P.class_ "holes" ]
      ( H.p_ [] [ text (ms (T.pack (show (length hs)) <> " hole(s) remaining")) ]
      : map holeView hs
      )

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
