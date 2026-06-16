{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

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

data Action = SetEditable MisoString | Check | Reset
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
#endif
#endif

app :: App Model Action
app = component initModel updateModel viewModel

initModel :: Model
initModel = Model (ms (levelTemplate theLevel)) NotChecked

updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  SetEditable s -> editable .= s
  Reset         -> do
    editable .= ms (levelTemplate theLevel)
    result   .= NotChecked
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

resultView :: CheckResult -> View Model Action
resultView = \case
  NotChecked   -> H.pre_ [] [ text "(press Check)" ]
  ParseError e -> H.pre_ [ P.class_ "err" ] [ text (ms ("Parse error:\n" <> e)) ]
  TypeError e  -> H.pre_ [ P.class_ "err" ] [ text (ms ("Type error:\n" <> e)) ]
  Solved       ->
    H.div_ [ P.class_ "ok" ]
      [ H.pre_ [] [ text "✓ Solved — no holes, typechecks. Level complete!" ]
      , H.p_   [] [ text (ms (levelConclusion theLevel)) ]
      ]
  Holes hs ->
    H.div_ [ P.class_ "holes" ]
      ( H.p_ [] [ text (ms (T.pack (show (length hs)) <> " hole(s) remaining")) ]
      : [ H.pre_ [ P.class_ "hole" ] [ text (ms h) ] | h <- hs ]
      )
