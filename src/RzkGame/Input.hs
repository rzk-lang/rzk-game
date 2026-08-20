{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Agda-style Unicode input for the editor.
--
-- Rzk's notation is Unicode throughout — @→@, @↦@, @≡@, @Δ¹@, @0₂@, @Σ@ — and
-- none of it has an ASCII spelling, so a player who types rather than taps the
-- Moves panel has no way to enter it. This module carries the same
-- backslash-abbreviation method Agda users already have in their fingers:
-- typing @\\to@ produces @→@.
--
-- The method is a pure text transformation ('applyAbbrev'), so it is testable
-- without a browser and cannot desync the editor's two layers. It fires in two
-- places, following Emacs quail (which is what @agda-input@ is):
--
--   * on a space, which commits the abbreviation. Quail swallows that space;
--     here it is kept, because every abbreviation this affects (@\to@, @\le@,
--     @\r@ — the ones that are a prefix of a longer key and so cannot fire on
--     their own) produces an infix operator that wants a space after it anyway.
--     Typing @A \to B@ therefore gives @A → B@, not @A →B@;
--   * as soon as an abbreviation is complete and no longer abbreviation extends
--     it, so @\\Sigma@ becomes @Σ@ without any further keystroke.
--
-- An abbreviation that is complete but /is/ a prefix of a longer one (@\\to@,
-- extended by @\\top@) waits for the space, and 'pendingAbbrev' lets the UI show
-- what is still on offer.
module RzkGame.Input
  ( translations
  , lookupAbbrev
  , completions
  , pendingAbbrev
  , applyAbbrev
  , insertionPoint
  ) where

import           Control.Applicative ((<|>))
import           Data.List  (find)
import           Data.Text  (Text)
import qualified Data.Text as T

-- | The abbreviation table: the key as typed after the backslash, and what it
-- produces. A curated subset of Agda's @agda-input-translations@ — the Unicode
-- these games actually use, plus the common Agda spellings for it, so a reader
-- who knows the Agda method does not have to learn a second one.
--
-- Order matters only for display ('completions'); lookup is exact.
translations :: [(Text, Text)]
translations =
  [ -- arrows and maps
    ("to", "→"), ("r", "→"), ("rightarrow", "→"), ("->", "→")
  , ("mapsto", "↦"), ("mapstochar", "↦")
  , ("l", "←"), ("leftarrow", "←")
  , ("<->", "↔"), ("leftrightarrow", "↔")
    -- relations
  , ("equiv", "≡"), ("==", "≡")
  , ("le", "≤"), ("<=", "≤")
  , ("ge", "≥"), (">=", "≥")
  , ("ne", "≠"), ("/=", "≠")
    -- type formers and operators
  , ("Sigma", "Σ"), ("GS", "Σ")
  , ("Pi", "Π"), ("GP", "Π")
  , ("Delta", "Δ"), ("GD", "Δ")
  , ("lambda", "λ"), ("Gl", "λ")
  , ("times", "×"), ("x", "×")
  , ("cdot", "·")
  , ("circ", "∘"), ("o", "∘")
    -- blackboard bold, for the inductive types a game declares
  , ("bN", "ℕ"), ("bb{N}", "ℕ"), ("Nat", "ℕ")
  , ("bZ", "ℤ"), ("bb{Z}", "ℤ")
  , ("bU", "𝕌"), ("bb{U}", "𝕌")
    -- sub- and superscripts, for the cube endpoints and the simplices
  , ("_0", "₀"), ("_1", "₁"), ("_2", "₂"), ("_3", "₃")
  , ("^0", "⁰"), ("^1", "¹"), ("^2", "²"), ("^3", "³")
    -- logic, for the shapes
  , ("top", "⊤"), ("bot", "⊥")
  , ("and", "∧"), ("wedge", "∧")
  , ("or", "∨"), ("vee", "∨")
  ]

-- | The character an abbreviation produces, if it is a complete one.
lookupAbbrev :: Text -> Maybe Text
lookupAbbrev k = snd <$> find ((== k) . fst) translations

-- | Every abbreviation the given (possibly partial) key starts, in table order.
-- The UI shows these while an abbreviation is being typed.
completions :: Text -> [(Text, Text)]
completions k = [ e | e@(key, _) <- translations, k `T.isPrefixOf` key ]

-- | Whether some /longer/ abbreviation extends this one, so a complete key must
-- still wait rather than fire (@to@ waits for @top@).
extendable :: Text -> Bool
extendable k = any (\(key, _) -> key /= k && k `T.isPrefixOf` key) translations

-- | The abbreviation being typed at the caret: the run of abbreviation
-- characters after the nearest preceding backslash, when there is one on this
-- line and nothing has broken it. 'Nothing' when no abbreviation is open.
pendingAbbrev :: Text -> Int -> Maybe Text
pendingAbbrev txt caret = do
  let before = T.take caret txt
      key    = T.takeWhileEnd isAbbrevChar before
      rest   = T.dropEnd (T.length key) before
  _ <- T.stripSuffix "\\" rest
  if null (completions key) then Nothing else Just key

-- | Characters an abbreviation may contain. Deliberately narrow: a letter, a
-- digit, and the few punctuation marks Agda's own keys use, so a stray backslash
-- in prose does not swallow a whole word.
isAbbrevChar :: Char -> Bool
isAbbrevChar c = c `elem` ("abcdefghijklmnopqrstuvwxyz"
                        <> "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                        <> "0123456789" <> "_^<>=-/{}" :: String)

-- | Apply the input method to a text at a caret, given the character just typed.
--
-- Returns the rewritten text and where the caret should end up, or 'Nothing'
-- when nothing fires. The caret is an offset in characters, counted the same way
-- a textarea's @selectionStart@ is.
applyAbbrev :: Text -> Int -> Maybe (Text, Int)
applyAbbrev txt caret = spaceCommit <|> autoCommit
  where
    before = T.take caret txt
    after  = T.drop caret txt

    -- The space just typed commits the abbreviation before it, and is kept.
    spaceCommit = do
      before' <- T.stripSuffix " " before
      (txt', caret') <- fire before' (pendingAbbrev before' (T.length before'))
      pure (T.take caret' txt' <> " " <> T.drop caret' txt', caret' + 1)

    -- A complete abbreviation that nothing longer extends fires on its own.
    autoCommit = do
      key <- pendingAbbrev txt caret
      if extendable key then Nothing else fire before (Just key)

    -- Replace the trailing @\key@ of the text left of the caret with its
    -- character, keeping everything to the right of the caret as it was.
    fire lhs mkey = do
      key <- mkey
      ch  <- lookupAbbrev key
      let kept = T.dropEnd (T.length key + 1) lhs   -- + 1 for the backslash
      pure (kept <> ch <> after, T.length kept + T.length ch)

-- | Where a single insertion turned one text into another, i.e. where the caret
-- now is. 'Nothing' when the change is not a plain insertion (a paste of several
-- characters, a deletion, a tap-to-fill), in which case the input method sits
-- this one out rather than guessing.
--
-- The editor's input event carries only the new value, so this recovers the
-- caret from the model's previous value instead of reading it from the DOM.
insertionPoint :: Text -> Text -> Maybe Int
insertionPoint old new
  | T.length new == T.length old + 1
  , let p = commonPrefixLen old new
  , T.drop p old == T.drop (p + 1) new
  = Just (p + 1)
  | otherwise = Nothing
  where
    commonPrefixLen a b = case T.commonPrefixes a b of
      Just (c, _, _) -> T.length c
      Nothing        -> 0
