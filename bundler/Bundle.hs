{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The native bundle step: pack a @game.yaml@ and the level files it references
-- into the single @game.json@ the wasm app fetches.
--
-- The app parses only JSON (with aeson, which runs under the wasm backend), so
-- all YAML parsing happens here, on the host. We parse the @game.yaml@ table of
-- contents to a JSON 'Value', and for each referenced level file we split its
-- YAML front-matter from its Markdown body and parse the front-matter to JSON.
-- We then write
--
-- > { "config": <the game.yaml as JSON>,
-- >   "files":  { "<path>": { "meta": <front-matter>, "body": "<markdown>" }, … } }
--
-- 'RzkGame.Loader.buildGame' resolves each item's @file@ against @files@. File
-- paths are resolved relative to the directory of the @game.yaml@.
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
import           Data.Text.Encoding   (encodeUtf8)
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

  files <- traverse (readLevelFile gameDir) (refMap (fileRefs config))

  let bundle = A.object [ "config" A..= config, "files" A..= files ]
  createDirectoryIfMissing True (takeDirectory outJson)
  BL.writeFile outJson (A.encode bundle)
  putStrLn ("Wrote " <> outJson <> " ("
              <> show (Map.size files) <> " file(s) inlined from " <> gameDir <> ")")

-- | The references as a map keyed by the path as written in the spec — exactly
-- the key 'RzkGame.Loader' looks up.
refMap :: [Text] -> Map Text Text
refMap refs = Map.fromList [ (r, r) | r <- refs ]

-- | Read one level file (relative to the game directory), split its YAML
-- front-matter from its Markdown body, and parse the front-matter to a JSON
-- value. The body is kept verbatim for the loader's block / prose readers.
readLevelFile :: FilePath -> Text -> IO A.Value
readLevelFile gameDir rel = do
  raw <- TIO.readFile (gameDir </> T.unpack rel)
  let (front, body) = splitFrontMatter raw
  meta <- if T.null (T.strip front)
            then pure (A.object [])
            else case Y.decodeEither' (encodeUtf8 front) of
              Left err  -> die ("Cannot parse front-matter of " <> T.unpack rel
                                  <> ":\n" <> show err)
              Right v   -> pure (v :: A.Value)
  pure (A.object [ "meta" A..= meta, "body" A..= body ])

-- | Split a level file into its YAML front-matter and its Markdown body. A file
-- opens with a @---@ line, then the front-matter, then a closing @---@ line; the
-- body is everything after. A file with no leading @---@ has empty front-matter
-- and is all body.
splitFrontMatter :: Text -> (Text, Text)
splitFrontMatter txt = case T.lines txt of
  ("---" : rest) -> case break (== "---") rest of
    (front, _ : body) -> (T.unlines front, T.unlines body)
    (front, [])       -> (T.unlines front, "")
  _ -> ("", txt)

-- | Every distinct @file@ reference in the config, in first-seen order. We look
-- for any object carrying a @"file"@ string anywhere in the tree, which covers
-- both puzzle and prose references.
fileRefs :: A.Value -> [Text]
fileRefs = dedup . go
  where
    go (A.Object o) =
      [ f | Just (A.String f) <- [KM.lookup "file" o] ]
        <> concatMap go (toList o)
    go (A.Array a)  = concatMap go (toList a)
    go _            = []

    dedup = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
