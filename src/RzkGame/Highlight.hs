{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A tiny, lossless syntax tokeniser for Rzk source, used by the L1 editor to
-- render a highlighted layer behind the textarea.
--
-- It is deliberately lightweight: it recognises line comments, @#@-commands,
-- holes, and a handful of operators, and leaves everything else plain. The
-- concatenation of the token texts always equals the input
-- (@T.concat [t | Tok _ t <- highlight s] == s@), so the highlighted layer lines
-- up with the textarea character for character.
module RzkGame.Highlight
  ( TokClass (..)
  , Tok (..)
  , highlight
  , tokClassName
  ) where

import           Data.Char (isSpace)
import           Data.Text (Text)
import qualified Data.Text as T

-- | The lexical category of a token, mapped to a CSS class by 'tokClassName'.
data TokClass = Keyword | Hole | Comment | Op | Plain
  deriving (Eq, Show)

-- | A classified slice of the source.
data Tok = Tok TokClass Text
  deriving (Eq, Show)

-- | Operators and punctuation we colour, longest first so @:=@ beats @:@.
operators :: [Text]
operators = [ ":=", "≡", "≤", "→", "↦", "×", "·", "(", ")", ",", "|", ":" ]

-- | Characters that end a plain run (each begins a token we colour): the single
-- character operators plus the command and hole markers.
breakChars :: [Char]
breakChars = "≡≤→↦×·(),|:#?"

-- | Tokenise Rzk source losslessly.
highlight :: Text -> [Tok]
highlight t
  | T.null t              = []
  | "--" `T.isPrefixOf` t = let (c, rest) = T.break (== '\n') t
                            in Tok Comment c : highlight rest
  | T.head t == '#'       = let (w, rest) = T.span isWordChar (T.tail t)
                            in Tok Keyword (T.cons '#' w) : highlight rest
  | T.head t == '?'       = let (w, rest) = T.span isWordChar (T.tail t)
                            in Tok Hole (T.cons '?' w) : highlight rest
  | (op : _) <- prefixOps = Tok Op op : highlight (T.drop (T.length op) t)
  | otherwise             = let n = plainLen t
                            in Tok Plain (T.take n t) : highlight (T.drop n t)
  where
    prefixOps = [ op | op <- operators, op `T.isPrefixOf` t ]
    isWordChar c = not (isSpace c) && c `notElem` breakChars

-- | Length of the leading plain run: up to the next break character or comment
-- start. At least 1 whenever this is reached (the head is not a break character,
-- or another branch would have fired), so tokenising always makes progress.
plainLen :: Text -> Int
plainLen = go 0
  where
    go n s = case T.uncons s of
      Nothing -> n
      Just (c, s')
        | c `elem` breakChars                    -> n
        | c == '-', Just ('-', _) <- T.uncons s' -> n
        | otherwise                              -> go (n + 1) s'

-- | CSS class for a token category (paired with the rules in static/index.html).
tokClassName :: TokClass -> Text
tokClassName = \case
  Keyword -> "tok-kw"
  Hole    -> "tok-hole"
  Comment -> "tok-comment"
  Op      -> "tok-op"
  Plain   -> "tok-plain"
