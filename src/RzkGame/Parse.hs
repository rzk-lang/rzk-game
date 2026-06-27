{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | A total wrapper around rzk's parser.
--
-- rzk's layout resolver can /throw/ a pure error on malformed input — for
-- example an unbalanced @)@ (rzk-lang/rzk-game#46) — instead of returning a
-- 'Left'. Such an exception, forced anywhere downstream, freezes the wasm app:
-- there is no runtime to unwind to, so the page just stops. The checker catches
-- it as a /crash/, but the formatter and the loader call the parser without a
-- guard, so a stray parenthesis can hang the whole game.
--
-- 'safeParseModule' forces the parse to weak head normal form inside an
-- exception handler and turns a thrown error into a 'Left', so every caller —
-- the checker, the formatter, the loader — sees a recoverable parse failure.
-- Layout errors are raised while the parser consumes tokens, which WHNF forces,
-- so they are caught here rather than escaping.
module RzkGame.Parse
  ( safeParseModule
  ) where

import           Control.Exception       (SomeException, evaluate, try)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           System.IO.Unsafe        (unsafePerformIO)

import           Language.Rzk.Syntax     (parseModule)
import           Language.Rzk.Syntax.Abs (Module)

-- | 'parseModule', but total: a thrown layout/lex error becomes a 'Left'. The
-- @unsafePerformIO@ is referentially transparent — the parse is a pure function
-- of @src@ and we only observe whether it threw — and 'NOINLINE' keeps the
-- handler from being floated away.
safeParseModule :: Text -> Either Text Module
safeParseModule src = unsafePerformIO $ do
  outcome <- try (evaluate (parseModule src))
  pure $ case outcome of
    Right res                 -> res
    Left (e :: SomeException) -> Left (cleanError (T.pack (show e)))
{-# NOINLINE safeParseModule #-}

-- | Trim a thrown layout error to its informative head, dropping the
-- "Remaining tokens: …" dump the resolver appends.
cleanError :: Text -> Text
cleanError = T.strip . fst . T.breakOn "Remaining tokens"
