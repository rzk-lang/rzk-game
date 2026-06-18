{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The native bundle step: pack a @game.yaml@ and the @.rzk.md@ files it
-- references into the single @game.json@ the wasm app fetches.
--
-- The app parses only JSON (with aeson, which runs under the wasm backend), so
-- the YAML→JSON conversion and the file inlining happen here, on the host. We
-- parse the YAML to a JSON 'Value', collect every @file@ reference in it, read
-- each file's contents, and write
--
-- > { "config": <the game.yaml as JSON>, "files": { "<path>": "<contents>", … } }
--
-- 'RzkGame.Loader.buildGame' then resolves each puzzle's @file@ against @files@.
-- File paths are resolved relative to the directory of the @game.yaml@.
--
-- Usage: @rzk-game-bundle [GAME_YAML] [OUT_JSON]@ (defaults:
-- @game/game.yaml@ and @public/game.json@).
module Main (main) where

import qualified Data.Aeson           as A
import qualified Data.Aeson.KeyMap    as KM
import qualified Data.ByteString.Lazy as BL
import           Data.Foldable        (toList)
import           Data.Map.Strict      (Map)
import qualified Data.Map.Strict      as Map
import           Data.Text            (Text)
import qualified Data.Text            as T
import qualified Data.Text.IO         as TIO
import qualified Data.Yaml            as Y
import           System.Directory     (createDirectoryIfMissing)
import           System.Environment   (getArgs)
import           System.Exit          (die)
import           System.FilePath      (takeDirectory, (</>))

main :: IO ()
main = do
  args <- getArgs
  let (gameYaml, outJson) = case args of
        []          -> ("game/game.yaml", "public/game.json")
        [g]         -> (g, "public/game.json")
        (g : o : _) -> (g, o)
      gameDir = takeDirectory gameYaml

  config <- Y.decodeFileEither gameYaml >>= \case
    Left err  -> die ("Cannot parse " <> gameYaml <> ":\n" <> Y.prettyPrintParseException err)
    Right cfg -> pure (cfg :: A.Value)

  files <- readReferenced gameDir (fileRefs config)

  let bundle = A.object [ "config" A..= config, "files" A..= files ]
  createDirectoryIfMissing True (takeDirectory outJson)
  BL.writeFile outJson (A.encode bundle)
  putStrLn ("Wrote " <> outJson <> " ("
              <> show (Map.size files) <> " file(s) inlined from " <> gameDir <> ")")

-- | Read every referenced file (relative to the game directory) into a map keyed
-- by the path as written in the spec — exactly the key 'RzkGame.Loader' looks up.
readReferenced :: FilePath -> [Text] -> IO (Map Text Text)
readReferenced gameDir refs =
  Map.fromList <$> mapM (\r -> (,) r <$> TIO.readFile (gameDir </> T.unpack r)) refs

-- | Every distinct @file@ reference in the config, in first-seen order. We look
-- for any object carrying a @"file"@ string anywhere in the tree, which covers
-- both puzzle and prose file references.
fileRefs :: A.Value -> [Text]
fileRefs = dedup . go
  where
    go (A.Object o) =
      [ f | Just (A.String f) <- [KM.lookup "file" o] ]
        <> concatMap go (toList o)
    go (A.Array a)  = concatMap go (toList a)
    go _            = []

    dedup = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
