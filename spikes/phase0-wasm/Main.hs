{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE CPP               #-}
module Main where

import           Miso
import qualified Miso.Html as H
import           Miso.Lens
import           Miso.String (MisoString, ms)

import qualified Rzk.Main             as Rzk
import qualified Language.Rzk.Syntax  as RzkS
import           Rzk.TypeCheck        (typecheckModulesWithHoles,
                                       ppTypeErrorInScopedContext',
                                       OutputDirection (BottomUp))
import           Rzk.Diagnostic       (ppHoleInfo)
import qualified Data.Text            as T

-- | Model: a counter + the last rzk result (typecheck or holes query).
data Model = Model
  { _counter :: Int
  , _result  :: MisoString
  } deriving (Show, Eq)

counter :: Lens Model Int
counter = lens _counter $ \r f -> r { _counter = f }

result :: Lens Model MisoString
result = lens _result $ \r f -> r { _result = f }

data Action = AddOne | SubtractOne | CheckGood | InspectHoles
  deriving (Show, Eq)

-- 0C: whole-file pass/fail via typecheckString.
rzkCheck :: T.Text -> T.Text
rzkCheck input = case Rzk.typecheckString input of
  Left err -> "ERROR\n" <> err
  Right ok -> "OK\n" <> ok

-- Phase 2 core: the structured goal/context query at each hole.
rzkHoles :: T.Text -> T.Text
rzkHoles src =
  case RzkS.parseModule src of
    Left e  -> "parse error: " <> e
    Right m -> case typecheckModulesWithHoles [("level", m)] of
      Left err            ->
        "typecheck error:\n" <> T.pack (ppTypeErrorInScopedContext' BottomUp err)
      Right (_, _, holes) ->
        "HOLES FOUND: " <> T.pack (show (length holes)) <> "\n"
          <> T.pack (unlines (map ppHoleInfo holes))

goodSnippet :: T.Text
goodSnippet = "#lang rzk-1\n#define id (A : U) (a : A) : A := a\n"

-- The first hom2 level, mid-refine: \ (t , s) -> f ?  (an unfilled hole).
levelWithHole :: T.Text
levelWithHole = T.unlines
  [ "#lang rzk-1"
  , "#def Δ¹ : 2 → TOPE := \\ t → TOP"
  , "#def Δ² : (2 × 2) → TOPE := \\ (t , s) → s ≤ t"
  , "#def hom (A : U) (x y : A) : U := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]"
  , "#def id-hom (A : U) (x : A) : hom A x x := \\ t → x"
  , "#def hom2 (A : U) (x y z : A) (f : hom A x y) (g : hom A y z) (h : hom A x z) : U"
  , "  := ( (t , s) : Δ²) → A [ s ≡ 0₂ ↦ f t , t ≡ 1₂ ↦ g s , s ≡ t ↦ h s ]"
  , "#def rut (A : U) (x y : A) (f : hom A x y) : hom2 A x y y f (id-hom A y) f"
  , "  := \\ (t , s) → f ?"
  ]

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

-- Headless proof that the structured holes query runs inside wasm.
hsSelftest :: IO ()
hsSelftest = do
  putStrLn "== typecheckString (0C) =="
  putStrLn (T.unpack (rzkCheck goodSnippet))
  putStrLn "== typecheckModulesWithHoles (Phase 2 query) on hom2 level, mid-refine =="
  putStrLn (T.unpack (rzkHoles levelWithHole))
#endif
#endif

app :: App Model Action
app = component emptyModel updateModel viewModel

emptyModel :: Model
emptyModel = Model 0 "(press a button)"

updateModel :: Action -> Effect parent props Model Action
updateModel = \case
  AddOne       -> counter += 1
  SubtractOne  -> counter -= 1
  CheckGood    -> result .= ms (rzkCheck goodSnippet)
  InspectHoles -> result .= ms (rzkHoles levelWithHole)

viewModel :: props -> Model -> View Model Action
viewModel _ x =
  vfrag
    [ H.h2_ [] [ text "rzk + miso (wasm) — Phase 2 holes query" ]
    , H.button_ [ H.onClick CheckGood ]    [ text "typecheck a snippet" ]
    , H.button_ [ H.onClick InspectHoles ] [ text "inspect holes (goal/context)" ]
    , H.pre_ [] [ text (x ^. result) ]
    , H.button_ [ H.onClick AddOne ] [ text "+" ]
    , text (ms (x ^. counter))
    , H.button_ [ H.onClick SubtractOne ] [ text "-" ]
    ]
