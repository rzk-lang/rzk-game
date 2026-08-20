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
--
-- Parentheses are classified by nesting depth rather than lumped in with the
-- other operators, and an unmatched one is called out. Rzk terms nest deeply
-- (@first (first (is-segal-A ? ? ? ? ?))@), and a missing @)@ is the beginner
-- mistake the parser reports least helpfully, so the depth is worth showing.
module RzkGame.Highlight
  ( TokClass (..)
  , Tok (..)
  , highlight
  , highlightLines
  , tokClassName
  , parenDepthColours
  , parenBalance
  , errorSpan
  ) where

import           Data.Char  (isSpace)
import           Data.List  (mapAccumL)
import           Data.Maybe (fromMaybe)
import qualified Data.Set  as Set
import           Data.Text  (Text)
import qualified Data.Text as T

-- | The lexical category of a token, mapped to a CSS class by 'tokClassName'.
--
-- A 'Paren' carries the nesting depth it sits at (an opening bracket and the
-- closing one that matches it carry the same depth, so a pair is one colour);
-- 'ParenBad' is a bracket with no partner.
data TokClass = Keyword | Hole | Comment | Op | Paren Int | ParenBad | Plain
  deriving (Eq, Show)

-- | A classified slice of the source.
data Tok = Tok TokClass Text
  deriving (Eq, Show)

-- | How many colours the depth cycle uses before repeating.
parenDepthColours :: Int
parenDepthColours = 4

-- | Operators and punctuation we colour, longest first so @:=@ beats @:@.
-- Parentheses are handled before this list (see 'lexFrom'), since they are
-- classified by depth rather than as plain operators.
operators :: [Text]
operators = [ ":=", "≡", "≤", "→", "↦", "×", "·", ",", "|", ":" ]

-- | Characters that end a plain run (each begins a token we colour): the single
-- character operators plus the command and hole markers.
breakChars :: [Char]
breakChars = "≡≤→↦×·(),|:#?"

-- | Tokenise Rzk source losslessly.
highlight :: Text -> [Tok]
highlight t = concat (markUnmatched [fst (lexFrom 0 t)])

-- | Tokenise source one logical line at a time, so the editor overlay can wrap
-- each line in its own element (to squiggle an error line). Splitting on @\n@
-- first is lossless — @T.intercalate \"\\n\"@ inverts it — and each line lexes
-- the same as it would in context, since no token (a comment included) spans a
-- newline within a single line. The caller re-inserts the @\n@ separators.
--
-- The nesting depth is threaded from line to line, so a bracket opened on one
-- line and closed three lines down is still recognised as a pair.
highlightLines :: Text -> [[Tok]]
highlightLines =
  markUnmatched . snd . mapAccumL step 0 . T.splitOn "\n"
  where
    step depth line = let (toks, depth') = lexFrom depth line in (depth', toks)

-- | Tokenise from a given nesting depth, returning the depth left open.
lexFrom :: Int -> Text -> ([Tok], Int)
lexFrom = go
  where
    go depth t
      | T.null t              = ([], depth)
      | "--" `T.isPrefixOf` t = let (c, rest) = T.break (== '\n') t
                                in emit depth (Tok Comment c) rest
      | T.head t == '#'       = let (w, rest) = T.span isWordChar (T.tail t)
                                in emit depth (Tok Keyword (T.cons '#' w)) rest
      | T.head t == '?'       = let (w, rest) = T.span isWordChar (T.tail t)
                                in emit depth (Tok Hole (T.cons '?' w)) rest
      -- An opening bracket takes the current depth and deepens; a closing one
      -- returns to the depth of its partner. A @)@ with nothing open is stray:
      -- it is marked here, and the depth stays at zero so the rest of the line
      -- keeps its colours instead of going negative.
      | T.head t == '('       = emit (depth + 1) (Tok (Paren depth) "(") (T.tail t)
      | T.head t == ')'       =
          if depth <= 0
            then emit 0 (Tok ParenBad ")") (T.tail t)
            else emit (depth - 1) (Tok (Paren (depth - 1)) ")") (T.tail t)
      | (op : _) <- prefixOps t = emit depth (Tok Op op) (T.drop (T.length op) t)
      | otherwise             = let n = plainLen t
                                in emit depth (Tok Plain (T.take n t)) (T.drop n t)

    emit depth tok rest = let (toks, depth') = go depth rest in (tok : toks, depth')
    prefixOps t = [ op | op <- operators, op `T.isPrefixOf` t ]
    isWordChar c = not (isSpace c) && c `notElem` breakChars

-- | Mark every opening bracket that is never closed as 'ParenBad'.
--
-- 'lexFrom' can only catch the stray @)@, since an unclosed @(@ is not known to
-- be unclosed until the source runs out. This pass walks the tokens keeping a
-- stack of the open brackets seen so far; whatever is still on the stack at the
-- end had no partner. Positions are counted over the flattened token stream and
-- the grouping is restored afterwards, so it works for both 'highlight' (one
-- group) and 'highlightLines' (one group per line).
markUnmatched :: [[Tok]] -> [[Tok]]
markUnmatched groups = regroup (map length groups) (map mark (zip [0 ..] flat))
  where
    flat = concat groups
    -- The stack of open brackets, by position, left over once the source runs
    -- out: exactly the ones with no partner.
    unclosed = Set.fromList (foldl push [] (zip [0 :: Int ..] flat))
    push open (i, t) = case t of
      Tok Paren{} "(" -> i : open
      Tok Paren{} ")" -> drop 1 open
      _               -> open
    mark (i, Tok cls txt)
      | Set.member i unclosed = Tok ParenBad txt
      | otherwise             = Tok cls txt
    regroup [] _        = []
    regroup (n : ns) ts = let (h, r) = splitAt n ts in h : regroup ns r

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

-- | @(unclosed, stray)@: how many @(@ are never closed, and how many @)@ have
-- nothing open. Both zero means the source is balanced. Used for the editor's
-- status note, where a bracket count is a more useful thing to say than rzk's
-- parse error at the end of the file.
parenBalance :: Text -> (Int, Int)
parenBalance = foldl step (0, 0) . concat . highlightLines
  where
    step (unclosed, stray) = \case
      Tok ParenBad "(" -> (unclosed + 1, stray)
      Tok ParenBad ")" -> (unclosed, stray + 1)
      _                -> (unclosed, stray)

-- | The columns to underline for an error reported at a given column.
--
-- rzk locates a type error at a point, the first character of the offending
-- sub-term, and says nothing about where that sub-term ends. Underlining from
-- there to the end of the line would trail past it; underlining the whole line
-- (which is what happens with no column at all) starts before it. Bracketing is
-- the structure available without re-parsing: a sub-term reported inside a
-- bracket group ends no later than that group does, so the underline runs to
-- just before the closing bracket.
--
-- Returns an inclusive @(start, end)@ in 1-based columns. Falls back to the end
-- of the line when the reported column is not inside a group that closes on this
-- line, which is the honest answer — nothing here bounds it any tighter.
-- Brackets inside a comment do not count, since a comment is one token.
errorSpan :: Text -> Int -> (Int, Int)
errorSpan line start = (start, fromMaybe eol closeBefore)
  where
    eol  = T.length line
    -- Bracket columns on this line, as (column, isOpen).
    brackets = go 1 (highlight line)
      where
        go _ [] = []
        go c (Tok cls txt : ts)
          | isParen cls, txt == "(" = (c, True)  : go (c + n) ts
          | isParen cls, txt == ")" = (c, False) : go (c + n) ts
          | otherwise               = go (c + n) ts
          where n = T.length txt
        isParen Paren{} = True
        isParen ParenBad = True
        isParen _        = False
    -- The innermost group still open just before the reported column.
    enclosing = case foldl step [] (takeWhile ((< start) . fst) brackets) of
      c : _ -> Just c
      []    -> Nothing
      where
        step open (c, True)  = c : open
        step open (_, False) = drop 1 open
    -- Where that group closes, if it closes on this line.
    closeBefore = do
      open <- enclosing
      let after = dropWhile ((<= open) . fst) brackets
      close <- closeOf (0 :: Int) after
      pure (max start (close - 1))
    closeOf _ [] = Nothing
    closeOf depth ((c, isOpen) : rest)
      | isOpen        = closeOf (depth + 1) rest
      | depth == 0    = Just c
      | otherwise     = closeOf (depth - 1) rest

-- | CSS class for a token category (paired with the rules in static/index.html).
tokClassName :: TokClass -> Text
tokClassName = \case
  Keyword  -> "tok-kw"
  Hole     -> "tok-hole"
  Comment  -> "tok-comment"
  Op       -> "tok-op"
  Paren d  -> "tok-paren-" <> T.pack (show (d `mod` parenDepthColours))
  ParenBad -> "tok-paren-bad"
  Plain    -> "tok-plain"
