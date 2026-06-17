{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The L0 user interface: a textarea for the editable region, a Check button,
-- and a panel that renders the result — each unsolved hole's goal and
-- three-section context, a type error, or the success state. This is the
-- minimal rendering of the signed-off interaction model (textarea + panels).
module Main (main) where

import           Miso
import qualified Miso.Html          as H
import qualified Miso.Html.Property as P
import           Miso.Lens
import           Miso.String        (MisoString, fromMisoString, ms)

import qualified Data.Text          as T

import           RzkGame.Content    (hom2Level)
import           RzkGame.Level

-- | The level being played. (One hand-authored level for now.)
theLevel :: Level
theLevel = hom2Level

-- | UI state: the player's current text and the last check result.
data Model = Model
  { _editable :: MisoString
  , _result   :: CheckResult
  } deriving (Eq)

editable :: Lens Model MisoString
editable = lens _editable $ \m v -> m { _editable = v }

result :: Lens Model CheckResult
result = lens _result $ \m v -> m { _result = v }

data Action = SetEditable MisoString | Refine T.Text | Check | Reset
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

-- | Headless proof that the engine runs in wasm: check the starting template
-- (holes) and the reference solution (solved).
hsSelftest :: IO ()
hsSelftest = do
  putStrLn "== template (expect holes) =="
  putStrLn (T.unpack (renderResult (checkLevel theLevel (levelTemplate theLevel))))
  putStrLn "== solution (expect Solved) =="
  putStrLn (T.unpack (renderResult (checkLevel theLevel (levelSolution theLevel))))
  putStrLn "== tap-to-refine: refine f → give t (expect Solved) =="
  let step1 = refineFirstHole "f ?" (levelTemplate theLevel)
      step2 = refineFirstHole "t"   step1
  putStrLn (T.unpack (renderResult (checkLevel theLevel step2)))
  putStrLn "== garbage: replace ? with asd (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel theLevel (refineFirstHole "asd" (levelTemplate theLevel)))))
  putStrLn "== wrong branch: give s (expect TypeError) =="
  putStrLn (T.unpack (renderResult (checkLevel theLevel (refineFirstHole "s" (levelTemplate theLevel)))))
  putStrLn "== smart inventory: moves for the template hole =="
  case checkLevel theLevel (levelTemplate theLevel) of
    Holes (h : _) -> mapM_ (\(l, i) -> putStrLn (T.unpack (l <> "  ↦  " <> i)))
                           (holeActions h)
    r             -> putStrLn ("(expected holes, got " <> T.unpack (renderResult r) <> ")")
#endif
#endif

app :: App Model Action
app = component initModel updateModel viewModel

initModel :: Model
initModel = Model (ms template) (checkLevel theLevel template)
  where template = levelTemplate theLevel

updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  SetEditable s -> editable .= s
  Refine ins    -> do
    e <- use editable
    let e' = refineFirstHole ins (fromMisoString e)
    editable .= ms e'
    result   .= checkLevel theLevel e'
  Reset         -> do
    editable .= ms (levelTemplate theLevel)
    result   .= checkLevel theLevel (levelTemplate theLevel)
  Check         -> do
    e <- use editable
    result .= checkLevel theLevel (fromMisoString e)

viewModel :: props -> Model -> View Model Action
viewModel _ m =
  H.section_ [ P.class_ "level" ]
    [ H.h2_ [] [ text (ms (levelTitle theLevel)) ]
    , H.p_  [] [ text (ms (levelIntro theLevel)) ]

    , H.h3_ [] [ text "Goal" ]
    , H.pre_ [ P.class_ "goal" ] [ text (ms (levelStatement theLevel)) ]

    , H.h3_ [] [ text "Prelude (given)" ]
    , H.pre_ [ P.class_ "prelude" ] [ text (ms (levelPrelude theLevel)) ]

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
    , resultView (m ^. result)

    , H.h3_ [] [ text "Inventory" ]
    , H.ul_ [ P.class_ "inventory" ]
        [ H.li_ [] [ text (ms i) ] | i <- levelInventory theLevel ]
    ]

-- | The smart-inventory moves for the focused hole (the first unsolved one),
-- derived from the current source and result. There is nothing to refine when
-- the proof is solved, errs, or has not been checked.
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
      [ H.pre_ [] [ text "✓ Solved — no holes, typechecks. Level complete!" ]
      , H.p_   [] [ text (ms (levelConclusion theLevel)) ]
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
