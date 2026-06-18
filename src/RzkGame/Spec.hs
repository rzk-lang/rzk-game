{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The game spec: the authorable schema and the @.rzk.md@ block splitter.
--
-- Phase 3 lifts the game content out of Haskell ('RzkGame.Content') into data.
-- An author writes a @game.yaml@ (the structure and prose) plus one
-- @levels/<id>.rzk.md@ per puzzle (the rzk code, split into tagged blocks). A
-- native bundle step packs the YAML — converted to JSON — and the inlined file
-- contents into a single @game.json@ bundle; 'RzkGame.Loader.buildGame' decodes
-- that bundle and rebuilds the same @['Section']@ the engine already consumes.
--
-- This module holds the half of that pipeline that is pure and parse-only: the
-- 'FromJSON' schema records (mirroring the 'RzkGame.Section' model field for
-- field) and the two text functions that recover a 'RzkGame.Level' from a
-- @.rzk.md@ source — 'splitLevelSource' and 'goalFromTemplate'. No rzk
-- type-checking happens here, so the splitter is exercised headlessly.
module RzkGame.Spec
  ( -- * Bundle and schema
    Bundle (..)
  , GameSpec (..)
  , SectionSpec (..)
  , ItemSpec (..)
  , ProseSpec (..)
  , PuzzleSpec (..)
  , RemedySpec (..)
    -- * Level-source splitting
  , splitLevelSource
  , goalFromTemplate
  ) where

import           Control.Applicative ((<|>))
import           Data.Aeson          (FromJSON (..), withObject, (.!=), (.:),
                                      (.:?))
import           Data.Char           (isSpace)
import           Data.Map.Strict     (Map)
import           Data.Text           (Text)
import qualified Data.Text           as T

-- | The single JSON bundle the wasm app fetches: the @game.yaml@ as JSON under
-- @config@, and every referenced file's contents inlined under @files@ (keyed by
-- the path the spec refers to, e.g. @"levels/my-id.rzk.md"@). Bundling YAML→JSON
-- and inlining the files happens in the native bundle step, so the app only ever
-- parses JSON (with aeson, which already runs under the wasm backend).
data Bundle = Bundle
  { bundleConfig :: GameSpec
  , bundleFiles  :: Map Text Text
  } deriving (Eq, Show)

instance FromJSON Bundle where
  parseJSON = withObject "Bundle" $ \o -> Bundle
    <$> o .: "config"
    <*> o .:? "files" .!= mempty

-- | The game configuration (the @game.yaml@): a title and the ordered sections.
data GameSpec = GameSpec
  { gsTitle    :: Text
  , gsSections :: [SectionSpec]
  } deriving (Eq, Show)

instance FromJSON GameSpec where
  parseJSON = withObject "GameSpec" $ \o -> GameSpec
    <$> o .:? "title" .!= ""
    <*> o .:? "sections" .!= []

-- | A section (a BOPPPS-style world): an id, a title, and ordered items.
data SectionSpec = SectionSpec
  { ssId    :: Text
  , ssTitle :: Text
  , ssItems :: [ItemSpec]
  } deriving (Eq, Show)

instance FromJSON SectionSpec where
  parseJSON = withObject "SectionSpec" $ \o -> SectionSpec
    <$> o .: "id"
    <*> o .:? "title" .!= ""
    <*> o .:? "items" .!= []

-- | One item in a section: either a prose pseudo-level or a puzzle. The JSON is
-- an object tagged by a single key — @{ "prose": … }@ or @{ "puzzle": … }@ —
-- which keeps the author's YAML readable and the items self-describing.
data ItemSpec
  = ItemProse  ProseSpec
  | ItemPuzzle PuzzleSpec
  deriving (Eq, Show)

instance FromJSON ItemSpec where
  parseJSON = withObject "ItemSpec" $ \o ->
        (ItemProse  <$> o .: "prose")
    <|> (ItemPuzzle <$> o .: "puzzle")

-- | A prose pseudo-level. The text is inline (@text@) or pulled from an inlined
-- file (@file@); 'role' is an optional BOPPPS tag (advisory, for labelling).
-- Unlike the 'RzkGame.Section' 'Prose' record, the schema also carries a short
-- 'psTitle' for the picker, since the model needs one.
data ProseSpec = ProseSpec
  { psId    :: Text
  , psTitle :: Text
  , psRole  :: Maybe Text
  , psText  :: Maybe Text
  , psFile  :: Maybe Text
  } deriving (Eq, Show)

instance FromJSON ProseSpec where
  parseJSON = withObject "ProseSpec" $ \o -> ProseSpec
    <$> o .: "id"
    <*> o .:? "title" .!= ""
    <*> o .:? "role"
    <*> o .:? "text"
    <*> o .:? "file"

-- | A puzzle. The prose fields (@title@/@statement@/@intro@/@conclusion@/
-- @inventory@) live here in the spec; the rzk code (prelude, template, solution)
-- comes from the referenced @file@, split by 'splitLevelSource'. @role@ is the
-- curriculum role (@core@/@pretest@/@extra@, default @core@); @prereqs@ and
-- @remedies@ are the locking metadata.
data PuzzleSpec = PuzzleSpec
  { pzId         :: Text
  , pzRole       :: Maybe Text
  , pzFile       :: Text
  , pzTitle      :: Text
  , pzStatement  :: Text
  , pzIntro      :: Text
  , pzConclusion :: Text
  , pzInventory  :: [Text]
  , pzPrereqs    :: [Text]
  , pzRemedies   :: [RemedySpec]
  } deriving (Eq, Show)

instance FromJSON PuzzleSpec where
  parseJSON = withObject "PuzzleSpec" $ \o -> PuzzleSpec
    <$> o .: "id"
    <*> o .:? "role"
    <*> o .: "file"
    <*> o .:? "title" .!= ""
    <*> o .:? "statement" .!= ""
    <*> o .:? "intro" .!= ""
    <*> o .:? "conclusion" .!= ""
    <*> o .:? "inventory" .!= []
    <*> o .:? "prereqs" .!= []
    <*> o .:? "remedies" .!= []

-- | A remediation pointer: a label plus exactly one target — an in-game @section@
-- id, an in-game @level@ (puzzle) id, or an external @url@.
data RemedySpec = RemedySpec
  { rsLabel   :: Text
  , rsSection :: Maybe Text
  , rsLevel   :: Maybe Text
  , rsUrl     :: Maybe Text
  } deriving (Eq, Show)

instance FromJSON RemedySpec where
  parseJSON = withObject "RemedySpec" $ \o -> RemedySpec
    <$> o .:? "label" .!= ""
    <*> o .:? "section"
    <*> o .:? "level"
    <*> o .:? "url"

-- | Split a @.rzk.md@ level source into its @(prelude, template, solution)@ rzk
-- code, by the role word on each fenced block (decision D2). A block opens with
-- a fence whose info string is @rzk <role>@ and closes with a bare @```@:
--
-- > ```rzk prelude
-- > #def id-hom … := …
-- > ```
--
-- The @prelude@ is every @prelude@ block concatenated in order; the @template@
-- and @solution@ are the single block of each role. Other fenced blocks (a plain
-- @```rzk@, or another language) and the surrounding Markdown prose are ignored.
-- Each block's body is rejoined with 'T.unlines' (so it carries a trailing
-- newline, matching the hand-authored 'RzkGame.Content' fields). Fails when a
-- @template@ or @solution@ block is missing or duplicated, or a fence is left
-- unterminated.
splitLevelSource :: Text -> Either Text (Text, Text, Text)
splitLevelSource src = do
  blocks   <- parseBlocks (T.lines src)
  template <- exactlyOne "template" [ b | ("template", b) <- blocks ]
  solution <- exactlyOne "solution" [ b | ("solution", b) <- blocks ]
  let prelude = T.concat [ T.unlines b | ("prelude", b) <- blocks ]
  pure (prelude, T.unlines template, T.unlines solution)
  where
    exactlyOne name = \case
      [b] -> Right b
      []  -> Left ("missing a `rzk " <> name <> "` block")
      _   -> Left ("expected exactly one `rzk " <> name <> "` block")

-- | Parse the fenced code blocks of a Markdown source into @(role, body lines)@
-- pairs, in order. Lines outside a recognised block are dropped.
parseBlocks :: [Text] -> Either Text [(Text, [Text])]
parseBlocks = go
  where
    go [] = Right []
    go (l : rest) = case fenceOpen l of
      Nothing   -> go rest
      Just role ->
        let (body, after) = break isFenceClose rest
        in case after of
             []        -> Left "unterminated ``` block in level source"
             (_ : ys)  -> case role of
               Just r  -> ((r, body) :) <$> go ys
               Nothing -> go ys

    -- A fence-open line. 'Nothing' if the line is not a fence; @Just (Just role)@
    -- for a recognised @rzk <role>@ block; @Just Nothing@ for any other fence
    -- (whose body we skip past but do not collect).
    fenceOpen :: Text -> Maybe (Maybe Text)
    fenceOpen line
      | "```" `T.isPrefixOf` s =
          case T.words (T.drop 3 s) of
            ("rzk" : r : _) | r `elem` roles -> Just (Just r)
            _                                -> Just Nothing
      | otherwise = Nothing
      where s = T.stripStart line
    roles = ["prelude", "template", "solution"]

    isFenceClose line = T.strip line == "```"

-- | Recover the goal — the pinned definition name and its required /closed/
-- Π-type — from a @template@ block's @#def@. The win-condition check appends
--
-- > #def __rzkgame_goal_check : <type> := <name>
--
-- so the type must be the closed Π-type that @<name>@ inhabits, with no binders
-- left on the left of the @:@.
--
-- Authors may write the template with grouped binders (the gentle style the
-- hand-authored levels use, e.g. @#def rut (A : U) (x y : A) … : T := \\ … → ?@)
-- /or/ already in closed form (@#def rut : (A : U) → … → T := …@). We recover the
-- closed type uniformly: split off the binder groups before the result-type
-- colon, expand each @(x y : A)@ into @(x : A) → (y : A)@, and join them with the
-- result type by @→@. A template already in closed form has no binders, so its
-- result type /is/ the closed type and passes through unchanged. The
-- reconstruction reproduces exactly what rzk's elaborator would assign, so the
-- recovered type matches the corresponding 'RzkGame.Content' @levelGoalType@.
goalFromTemplate :: Text -> Either Text (Text, Text)
goalFromTemplate template = do
  let header = snd (T.breakOn "#def" (fst (T.breakOn ":=" template)))
  rest <- if T.null header
            then Left "template has no `#def` to read the goal from"
            else Right (T.stripStart (T.drop (T.length "#def") header))
  let (name, afterName) = T.break isSpace rest
  if T.null name
    then Left "template `#def` has no name"
    else do
      (bindersText, resultType) <- splitResultColon afterName
      let binders   = concatMap expandBinder (parenGroups bindersText)
          closed    = T.intercalate " → " (binders ++ [normalise resultType])
      Right (name, closed)

-- | Split @<binders> : <result-type>@ at the first colon that sits at paren
-- depth zero — the one separating the binder groups from the result type. The
-- binder colons all sit inside parentheses, so they are skipped.
splitResultColon :: Text -> Either Text (Text, Text)
splitResultColon = go 0 []
  where
    go :: Int -> [Char] -> Text -> Either Text (Text, Text)
    go d acc t = case T.uncons t of
      Nothing -> Left "template `#def` has no result type (no top-level `:`)"
      Just (c, cs) -> case c of
        '('             -> go (d + 1) (c : acc) cs
        ')'             -> go (d - 1) (c : acc) cs
        ':' | d == 0    -> Right (T.pack (reverse acc), cs)
        _               -> go d (c : acc) cs

-- | The inner contents of each top-level parenthesised group in a binder list,
-- in order; text outside parentheses (whitespace) is ignored.
parenGroups :: Text -> [Text]
parenGroups = go 0 [] []
  where
    go :: Int -> [Char] -> [Text] -> Text -> [Text]
    go d cur acc t = case T.uncons t of
      Nothing -> reverse acc
      Just (c, cs) -> case c of
        '(' | d == 0   -> go 1 [] acc cs
            | otherwise -> go (d + 1) (c : cur) acc cs
        ')' | d == 1    -> go 0 [] (T.pack (reverse cur) : acc) cs
            | otherwise -> go (d - 1) (c : cur) acc cs
        _   | d == 0    -> go d cur acc cs
            | otherwise -> go d (c : cur) acc cs

-- | Expand one binder group @"x y : A"@ into the single-variable closed binders
-- @["(x : A)", "(y : A)"]@. A group with no @:@ (which should not occur in a
-- well-formed @#def@) expands to nothing.
expandBinder :: Text -> [Text]
expandBinder grp = case T.breakOn ":" grp of
  (_, t) | T.null t -> []
  (vars, ty0) ->
    let ty = normalise (T.drop 1 ty0)
    in [ "(" <> v <> " : " <> ty <> ")" | v <- T.words vars ]

-- | Collapse all runs of whitespace (including newlines and indentation) to
-- single spaces and trim, so a type written across several indented lines reads
-- as the single-spaced form the hand-authored @levelGoalType@s use.
normalise :: Text -> Text
normalise = T.unwords . T.words
