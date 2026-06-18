{-# LANGUAGE OverloadedStrings #-}

-- | Authoring tool: rewrite the read-only @prelude@ blocks of the @game/@ level
-- files in place with rzk's canonical formatting.
--
-- The prelude a player reads is fixed and pre-checked, so it is formatted once
-- in the source rather than per render. This tool is /not/ part of the normal
-- build (run it by hand via @make format-game@); the @rzk-game-spec@ suite then
-- checks that every prelude is 'isWellFormatted' and that @game/@ still
-- reproduces 'RzkGame.Content' exactly. Only the @```rzk prelude@ blocks are
-- touched — templates and reference solutions are left as authored.
module Main (main) where

import           Control.Monad    (forM_)
import           Data.List        (isSuffixOf, sort)
import           Data.Text        (Text)
import qualified Data.Text        as T
import qualified Data.Text.IO     as T
import           System.Directory (listDirectory)
import           System.FilePath  ((</>))

import           RzkGame.Format   (formatFixpoint)

levelsDir :: FilePath
levelsDir = "game/levels"

main :: IO ()
main = do
  files <- sort . filter (".rzk.md" `isSuffixOf`) <$> listDirectory levelsDir
  forM_ files $ \f -> do
    let path = levelsDir </> f
    src <- T.readFile path
    let src' = reformatPreludes src
    if src' == src
      then putStrLn ("ok   - " <> f)
      else T.writeFile path src' >> putStrLn ("fmt  - " <> f)

-- | Replace the body of every @```rzk prelude@ fenced block with its formatted
-- form, leaving all other lines (prose, template and solution blocks) untouched.
reformatPreludes :: Text -> Text
reformatPreludes = T.unlines . go . T.lines
  where
    go [] = []
    go (l : rest)
      | l == "```rzk prelude" =
          let (body, after) = break (== "```") rest
          in (l : T.lines (formatFixpoint (T.unlines body))) ++ go after
      | otherwise = l : go rest
