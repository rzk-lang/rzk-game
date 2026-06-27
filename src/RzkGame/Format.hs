{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Tidying the player's editable region with rzk's own formatter.
--
-- rzk exposes a layout/whitespace formatter ('Rzk.Format.format') that works at
-- the token level: it reformats well-formed rzk source and is a no-op when the
-- source does not lex or resolve its layout. The engine wraps it with a parse
-- guard so a mid-edit fragment is never rewritten — we format only when the
-- editable region parses as a module, and otherwise return it unchanged. The
-- policy lives here (not in @Main@) so it is pure and natively testable, like
-- 'RzkGame.Save'.
module RzkGame.Format
  ( formatEditable
  , formatFixpoint
  , isWellFormatted
  ) where

import           Control.DeepSeq     (force)
import           Control.Exception   (SomeException, evaluate, try)
import           Data.Text           (Text)
import qualified Data.Text           as T
import           System.IO.Unsafe    (unsafePerformIO)

import           Rzk.Format          (format, isWellFormatted)

import           RzkGame.Parse       (safeParseModule)

-- | Format to a fixpoint. rzk's 'format' is not idempotent on every input — it
-- stabilises some forms (e.g. a cube product like @(2 × 2)@, where it inserts
-- the inner space only on a second pass) after one more pass. We iterate until
-- the text stops changing so the result is genuinely 'isWellFormatted', with a
-- small cap so a pathological oscillation cannot hang the caller.
formatFixpoint :: Text -> Text
formatFixpoint = go (10 :: Int)
  where
    go 0 x = x
    go n x = let y = format x in if y == x then x else go (n - 1) y

-- | Format the editable region of a level on demand.
--
-- The editable region is bare rzk source (a definition or two), without the
-- @#lang rzk-1@ pragma that the level's read-only prelude carries. rzk's
-- formatter needs no pragma (it lexes and reformats tokens), but 'parseModule'
-- requires one, so we prepend a pragma for the parse guard unless the region
-- already declares its own. We format only when the region parses as a complete
-- module — holes (@?@ / @?name@) parse fine, so a hole-bearing but otherwise
-- well-formed term formats cleanly, which is the common case mid-proof. A
-- fragment that does not parse is returned unchanged: a no-op, never a
-- corrupting rewrite.
formatEditable :: Text -> Text
formatEditable src = guardFormat src (formatPure src)
  where
    formatPure s
      | parses    = formatFixpoint s
      | otherwise = s
      where
        probe  = if "#lang" `T.isInfixOf` s then s else "#lang rzk-1\n" <> s
        parses = either (const False) (const True) (safeParseModule probe)

-- | Formatting is a best-effort tidy, so it must never crash the caller. The
-- parse guard goes through 'safeParseModule', but rzk's token-level 'format' is
-- itself a parser-adjacent call; should it throw on some input, fall back to the
-- original text rather than freezing the wasm app (rzk-lang/rzk-game#46).
guardFormat :: Text -> Text -> Text
guardFormat orig out = unsafePerformIO $ do
  outcome <- try (evaluate (force out))
  pure $ case outcome of
    Right t                   -> t
    Left (_ :: SomeException) -> orig
{-# NOINLINE guardFormat #-}
