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
import           Miso.Lens
import           Miso.String        (MisoString, fromMisoString, ms)

import qualified Data.Text          as T

import           RzkGame.Content    (gameLevels)
import           RzkGame.Level

-- | UI state: which level is being played, the player's current text, and the
-- last check result.
data Model = Model
  { _levelIx  :: Int
  , _editable :: MisoString
  , _result   :: CheckResult
  } deriving (Eq)

levelIx :: Lens Model Int
levelIx = lens _levelIx $ \m v -> m { _levelIx = v }

editable :: Lens Model MisoString
editable = lens _editable $ \m v -> m { _editable = v }

result :: Lens Model CheckResult
result = lens _result $ \m v -> m { _result = v }

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
  | Check
  | Reset
  | SelectLevel Int
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
  let lvl1 = head gameLevels
  putStrLn "== level 1 tap-to-refine: refine f → give t (expect Solved) =="
  let step1 = refineFirstHole "f ?" (levelTemplate lvl1)
      step2 = refineFirstHole "t"   step1
  putStrLn (T.unpack (renderResult (checkLevel lvl1 step2)))
  putStrLn "== level 1 garbage: replace ? with asd (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel lvl1 (refineFirstHole "asd" (levelTemplate lvl1)))))
  putStrLn "== level 1 wrong branch: give s (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel lvl1 (refineFirstHole "s" (levelTemplate lvl1)))))
  putStrLn "== level 1 smart inventory: moves for the template hole =="
  case checkLevel lvl1 (levelTemplate lvl1) of
    Holes (h : _) -> mapM_ (\(l, i) -> putStrLn (T.unpack (l <> "  ↦  " <> i)))
                           (holeActions h)
    r             -> putStrLn ("(expected holes, got " <> T.unpack (renderResult r) <> ")")
  let lvl2 = head (drop 1 gameLevels)
  putStrLn "== level 2 tap-to-refine: refine f → give s (expect Solved) =="
  putStrLn (T.unpack (renderResult
    (checkLevel lvl2 (refineFirstHole "s" (refineFirstHole "f ?" (levelTemplate lvl2))))))
#endif
#endif

app :: App Model Action
app = component initModel updateModel viewModel

initModel :: Model
initModel = loadLevel 0

-- | A fresh model for the level at the given index: its template, checked so
-- the focused hole and its moves show without a first manual Check.
loadLevel :: Int -> Model
loadLevel i = Model i (ms template) (checkLevel lvl template)
  where
    lvl      = nthLevel i
    template = levelTemplate lvl

updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  SetEditable s -> editable .= s
  SelectLevel i -> reload i
  Reset         -> use levelIx >>= reload
  Refine ins    -> do
    i <- use levelIx
    e <- use editable
    let e' = refineFirstHole ins (fromMisoString e)
    editable .= ms e'
    result   .= checkLevel (nthLevel i) e'
  Check         -> do
    i <- use levelIx
    e <- use editable
    result .= checkLevel (nthLevel i) (fromMisoString e)
  where
    -- Load a level's template into the model and check it, so the focused hole
    -- and its moves show without a first manual Check.
    reload i = do
      levelIx  .= i
      editable .= ms (levelTemplate (nthLevel i))
      result   .= checkLevel (nthLevel i) (levelTemplate (nthLevel i))

viewModel :: props -> Model -> View Model Action
viewModel _ m =
  H.section_ [ P.class_ "level" ]
    [ levelPicker m

    , H.h2_ [] [ text (ms (levelTitle lvl)) ]
    , H.p_  [] [ text (ms (levelIntro lvl)) ]

    , H.h3_ [] [ text "Goal" ]
    , H.pre_ [ P.class_ "goal" ] [ text (ms (levelStatement lvl)) ]

    , H.h3_ [] [ text "Prelude (given)" ]
    , H.pre_ [ P.class_ "prelude" ] [ text (ms (levelPrelude lvl)) ]

    , H.h3_ [] [ text "Your proof" ]
    , H.textarea_
        [ P.class_ "editor"
        , P.rows_ "5"
        , P.value_ (m ^. editable)
        , H.onInput SetEditable
        ]
    , H.h3_ [] [ text "Moves" ]
    , movesView m
    , H.div_ [ P.class_ "buttons" ]
        [ H.button_ [ H.onClick Check ] [ text "Check" ]
        , H.button_ [ H.onClick Reset ] [ text "Reset" ]
        ]

    , H.h3_ [] [ text "Result" ]
    , resultView lvl (m ^. result)
    , advanceView m

    , H.h3_ [] [ text "Inventory" ]
    , H.ul_ [ P.class_ "inventory" ]
        [ H.li_ [] [ text (ms i) ] | i <- levelInventory lvl ]
    ]
  where
    lvl = currentLevel m

-- | The level selector: one button per level, the current one highlighted.
levelPicker :: Model -> View Model Action
levelPicker m =
  H.div_ [ P.class_ "levels" ]
    [ H.button_
        ( H.onClick (SelectLevel i)
        : [ P.class_ "current" | i == _levelIx m ] )
        [ text (ms (T.pack (show (i + 1)) <> ". " <> levelTitle (nthLevel i))) ]
    | i <- [0 .. length gameLevels - 1]
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
            [ H.button_ [ P.class_ "refine", H.onClick (Refine ins) ] [ text (ms label) ]
            | (label, ins) <- moves
            ]
    _ -> H.p_ [ P.class_ "muted" ] [ text "Moves appear here when a hole is in focus." ]

-- | When the level is solved and another follows, offer a step onward.
advanceView :: Model -> View Model Action
advanceView m
  | Solved <- m ^. result, next < length gameLevels =
      H.div_ [ P.class_ "advance" ]
        [ H.button_ [ H.onClick (SelectLevel next) ] [ text "Next level →" ] ]
  | otherwise = text ""
  where
    next = _levelIx m + 1

resultView :: Level -> CheckResult -> View Model Action
resultView lvl = \case
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
      , H.p_   [] [ text (ms (levelConclusion lvl)) ]
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
