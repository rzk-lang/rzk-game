{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Native, headless tests for the Phase 3 data pipeline.
--
-- These run under ordinary GHC (no wasm), so they exercise the pure parts —
-- 'RzkGame.Spec' (the schema, the @.rzk.md@ body readers, the goal
-- reconstruction) and 'RzkGame.Loader.buildGame' — and also play every loaded
-- level through the real rzk 'checkLevel'. The headline test round-trips the
-- built-in /Morphisms/ section through a synthesized @game.json@ bundle and
-- asserts 'buildGame' reproduces it exactly: the goal name and type are /not/
-- stored in the bundle, so a faithful reproduction proves the reconstruction.
module Main (main) where

import           Control.Exception    (SomeException, try)
import           Data.Aeson           (Value, encode, object, (.=))
import qualified Data.Aeson.Key       as Key
import qualified Data.ByteString      as BS
import qualified Data.ByteString.Lazy as BL
import           Data.Text            (Text)
import qualified Data.Text            as T
import           System.Exit          (exitFailure)
import           Data.IORef

import           RzkGame.Content      (gameLevels, gameSections)
import           RzkGame.Level
import           RzkGame.Loader       (buildGame)
import           RzkGame.Section
import           RzkGame.Spec         (goalFromTemplate, levelProse,
                                      splitLevelSource)

main :: IO ()
main = do
  failed <- newIORef (0 :: Int)
  let check name ok = do
        putStrLn ((if ok then "ok   - " else "FAIL - ") <> name)
        if ok then pure () else modifyIORef' failed (+ 1)

  -- 1. goalFromTemplate reconstructs the pinned goal of every built-in level.
  putStrLn "== goalFromTemplate: every level's closed goal type is recovered =="
  flip mapM_ (zip [1 :: Int ..] gameLevels) $ \(n, lvl) ->
    check ("level " <> show n <> " (" <> T.unpack (levelTitle lvl) <> ") goal")
          (goalFromTemplate (levelTemplate lvl)
             == Right (levelGoalName lvl, levelGoalType lvl))

  -- 2. The block splitter recovers the three role blocks (ignoring prose and
  --    other fences); levelProse recovers the intro and the conclusion.
  putStrLn "== splitLevelSource / levelProse: a sample body reads correctly =="
  check "splitter result" (splitLevelSource sampleBody == Right
    ( "#lang rzk-1\n#def hom (A : U) (x y : A) : U\n  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]\n"
    , "#def my-id (A : U) (x : A)\n  : hom A x x\n  := ?\n"
    , "#def my-id (A : U) (x : A)\n  : hom A x x\n  := \\ t → x\n" ))
  check "splitter then goal" (case splitLevelSource sampleBody of
    Right (_, tmpl, _) -> goalFromTemplate tmpl == Right ("my-id", "(A : U) → (x : A) → hom A x x")
    _                  -> False)
  check "levelProse intro/conclusion"
    (levelProse sampleBody
       == ("Some intro prose, ignored by the splitter.", "That was the conclusion."))

  -- 3. buildGame round-trips the built-in Morphisms section: synthesize a bundle
  --    from it, decode it, and require an exact match. The goal name/type and the
  --    intro/conclusion are recovered, not stored, so this pins the readers too.
  putStrLn "== buildGame: the Morphisms section round-trips through a JSON bundle =="
  let morphisms = head gameSections
  case buildGame (BL.toStrict (encode (bundleFor "Round-trip" [morphisms]))) of
    Left err   -> check ("buildGame error: " <> T.unpack err) False
    Right secs -> do
      check "round-trips to one section" (length secs == 1)
      check "section equals RzkGame.Content morphisms" (secs == [morphisms])

  -- 4. Every loaded level actually plays: its template has holes, its reference
  --    solution solves. This runs the real rzk type-checker on the loaded model.
  putStrLn "== play: each loaded Morphisms level holes on its template and solves =="
  case buildGame (BL.toStrict (encode (bundleFor "Play" [head gameSections]))) of
    Left err   -> check ("buildGame error: " <> T.unpack err) False
    Right secs -> flip mapM_ (loadedLevels secs) $ \lvl -> do
      check (T.unpack (levelTitle lvl) <> ": template holes")
            (isHoles (checkLevel lvl (levelTemplate lvl)))
      check (T.unpack (levelTitle lvl) <> ": solution solves")
            (checkLevel lvl (levelSolution lvl) == Solved)

  -- 5. The authored game/ files, as bundled by `make bundle`, reproduce the
  --    built-in Morphisms section exactly. Skipped when public/game.json is
  --    absent (so `cabal test` runs standalone before a bundle has been built).
  putStrLn "== bundle: the authored game/ files reproduce Morphisms (run `make bundle` first) =="
  ejson <- try (BS.readFile "public/game.json") :: IO (Either SomeException BS.ByteString)
  case ejson of
    Left _     -> putStrLn "skip - public/game.json not found (run `make bundle`)"
    Right json -> case buildGame json of
      Left err   -> check ("buildGame on public/game.json: " <> T.unpack err) False
      Right secs -> do
        check "first bundled section equals Content morphisms"
              (not (null secs) && head secs == head gameSections)
        flip mapM_ (loadedLevels (take 1 secs)) $ \lvl ->
          check (T.unpack (levelTitle lvl) <> ": bundled solution solves")
                (checkLevel lvl (levelSolution lvl) == Solved)

  n <- readIORef failed
  if n == 0
    then putStrLn "\nAll Phase 3 spec/loader tests passed."
    else putStrLn ("\n" <> show n <> " test(s) FAILED.") >> exitFailure

-- | The puzzle levels of a loaded section list, in order.
loadedLevels :: [Section] -> [Level]
loadedLevels secs = [ puzzleLevel z | SPuzzle z <- concatMap sectionItems secs ]

isHoles :: CheckResult -> Bool
isHoles (Holes _) = True
isHoles _         = False

-- | A sample level body: intro prose, the three role blocks (and a non-rzk fence
-- to ignore), and a trailing conclusion — the shape a level file's body has once
-- the bundler has stripped its front-matter.
sampleBody :: Text
sampleBody = T.unlines
  [ "Some intro prose, ignored by the splitter."
  , ""
  , "```rzk prelude"
  , "#lang rzk-1"
  , "#def hom (A : U) (x y : A) : U"
  , "  := (t : Δ¹) → A [ t ≡ 0₂ ↦ x , t ≡ 1₂ ↦ y ]"
  , "```"
  , ""
  , "```haskell"
  , "ignored = True"
  , "```"
  , ""
  , "```rzk template"
  , "#def my-id (A : U) (x : A)"
  , "  : hom A x x"
  , "  := ?"
  , "```"
  , ""
  , "```rzk solution"
  , "#def my-id (A : U) (x : A)"
  , "  : hom A x x"
  , "  := \\ t → x"
  , "```"
  , ""
  , "## Conclusion"
  , ""
  , "That was the conclusion."
  ]

-- | Synthesize a @game.json@ bundle 'Value' from sections, re-deriving each
-- item's table-of-contents reference and its inlined file (front-matter @meta@ +
-- Markdown @body@). This is the inverse of the loader, so a test can round-trip
-- the built-in model through 'buildGame' without hand-writing JSON literals.
bundleFor :: Text -> [Section] -> Value
bundleFor title secs = object
  [ "config" .= object [ "title" .= title, "sections" .= map sectionV secs ]
  , "files"  .= object [ Key.fromText (refPath it) .= fileV it
                       | s <- secs, it <- sectionItems s ]
  ]

sectionV :: Section -> Value
sectionV s = object
  [ "id"    .= sectionId s
  , "title" .= sectionTitle s
  , "items" .= map itemV (sectionItems s)
  ]

-- | The table-of-contents entry: a tagged file reference, plus a puzzle's
-- placement metadata (role and prereqs).
itemV :: SectionItem -> Value
itemV (SProse p)  = object [ "prose"  .= object [ "file" .= refPath (SProse p) ] ]
itemV (SPuzzle z) = object [ "puzzle" .= object
  [ "file"    .= refPath (SPuzzle z)
  , "role"    .= roleWord (puzzleRole z)
  , "prereqs" .= puzzlePrereqs z
  ] ]

-- | The inlined file for an item: its front-matter @meta@ and its @body@.
fileV :: SectionItem -> Value
fileV (SProse p) = object
  [ "meta" .= object
      [ "id" .= proseId p, "title" .= proseTitle p
      , "role" .= fmap bopppsWord (proseRole p) ]
  , "body" .= proseText p
  ]
fileV (SPuzzle z) = object
  [ "meta" .= object
      [ "id" .= puzzleId z, "title" .= levelTitle lvl
      , "statement" .= levelStatement lvl, "inventory" .= levelInventory lvl ]
  , "body" .= levelBody lvl
  ]
  where lvl = puzzleLevel z

refPath :: SectionItem -> Text
refPath (SProse p)  = "levels/" <> proseId p <> ".md"
refPath (SPuzzle z) = "levels/" <> puzzleId z <> ".rzk.md"

-- | Re-assemble a level body from its fields (the inverse of 'splitLevelSource'
-- and 'levelProse'): intro, the three re-fenced rzk blocks, then a @## Conclusion@
-- section. Block bodies are emitted as @T.lines@ between fences, which the
-- splitter rejoins with 'T.unlines' to reproduce each field exactly.
levelBody :: Level -> Text
levelBody lvl = T.concat
  [ levelIntro lvl, "\n\n"
  , fenced "prelude"  (levelPrelude lvl)
  , fenced "template" (levelTemplate lvl)
  , fenced "solution" (levelSolution lvl)
  , "## Conclusion\n\n", levelConclusion lvl, "\n"
  ]
  where
    fenced role body = T.unlines (("```rzk " <> role) : T.lines body <> ["```", ""])

bopppsWord :: Boppps -> Text
bopppsWord = \case
  BridgeIn      -> "bridge-in"
  Outcomes      -> "outcomes"
  Participatory -> "participatory"
  PostTest      -> "post-test"
  Summary       -> "summary"
  Note          -> "note"

roleWord :: LevelRole -> Text
roleWord = \case
  Core    -> "core"
  PreTest -> "pretest"
  Extra   -> "extra"
