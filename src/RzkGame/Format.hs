{-# LANGUAGE OverloadedStrings #-}

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
  , isWellFormatted
  ) where

import           Data.Text           (Text)
import qualified Data.Text           as T

import           Language.Rzk.Syntax (parseModule)
import           Rzk.Format          (format, isWellFormatted)

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
formatEditable src
  | parses    = format src
  | otherwise = src
  where
    probe  = if "#lang" `T.isInfixOf` src then src else "#lang rzk-1\n" <> src
    parses = either (const False) (const True) (parseModule probe)
