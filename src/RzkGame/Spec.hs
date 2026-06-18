{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The game spec: the authorable schema and the level-file readers.
--
-- Phase 3 lifts the game content out of Haskell ('RzkGame.Content') into data.
-- A game is a /table of contents/ (@game.yaml@) plus one self-contained file per
-- item: a @levels/<id>.rzk.md@ for a puzzle (its metadata, prose, and rzk code)
-- or a @levels/<id>.md@ for a prose page. Each level file carries a YAML
-- front-matter header (the intrinsic metadata) followed by a Markdown body. The
-- table of contents only orders the files and adds /placement/ metadata — the
-- curriculum role, prerequisites, and remediation — which is about a level's
-- place in /this/ game, not the level itself. So a level file is portable across
-- games, and the locking graph stays visible in one place.
--
-- A native bundle step parses the YAML (the @game.yaml@ and each file's
-- front-matter), splits front-matter from body, and packs everything as JSON, so
-- the wasm app only ever parses JSON (decision D1). This module holds the pure
-- side: the 'FromJSON' schema records and the body readers — 'splitLevelSource'
-- (the rzk blocks), 'levelProse' (intro and conclusion), and 'goalFromTemplate'.
module RzkGame.Spec
  ( -- * Bundle and table of contents
    Bundle (..)
  , GameSpec (..)
  , SectionSpec (..)
  , ItemSpec (..)
  , ProseRef (..)
  , PuzzleRef (..)
  , RemedySpec (..)
    -- * Inlined level files
  , FileSpec (..)
  , Meta (..)
    -- * Reading a level body
  , splitLevelSource
  , levelProse
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
-- @config@, and every referenced level file inlined under @files@, keyed by the
-- path the table of contents refers to (e.g. @"levels/my-id.rzk.md"@). The
-- bundle step has already parsed each file's YAML front-matter and split it from
-- the body, so each inlined file is a 'FileSpec', not raw text.
data Bundle = Bundle
  { bundleConfig :: GameSpec
  , bundleFiles  :: Map Text FileSpec
  } deriving (Eq, Show)

instance FromJSON Bundle where
  parseJSON = withObject "Bundle" $ \o -> Bundle
    <$> o .: "config"
    <*> o .:? "files" .!= mempty

-- | The table of contents (the @game.yaml@): a title and the ordered sections.
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

-- | One item in a section: a reference to a prose or a puzzle file. The JSON is
-- tagged by a single key — @{ "prose": … }@ or @{ "puzzle": … }@ — so the table
-- of contents is self-describing and the loader never guesses an item's kind
-- from its file extension.
data ItemSpec
  = ItemProse  ProseRef
  | ItemPuzzle PuzzleRef
  deriving (Eq, Show)

instance FromJSON ItemSpec where
  parseJSON = withObject "ItemSpec" $ \o ->
        (ItemProse  <$> o .: "prose")
    <|> (ItemPuzzle <$> o .: "puzzle")

-- | A prose item: just a file reference. All of a prose page's metadata (id,
-- title, BOPPPS role) lives in that file's front-matter.
newtype ProseRef = ProseRef
  { prFile :: Text
  } deriving (Eq, Show)

instance FromJSON ProseRef where
  parseJSON = withObject "ProseRef" $ \o -> ProseRef <$> o .: "file"

-- | A puzzle item: a file reference plus the /placement/ metadata that belongs
-- to the table of contents rather than to the level itself — the curriculum
-- 'puRole' (@core@/@pretest@/@extra@, default @core@), the 'puPrereqs' (ids of
-- puzzles that must be satisfied to unlock this one), and the 'puRemedies'.
data PuzzleRef = PuzzleRef
  { puFile     :: Text
  , puRole     :: Maybe Text
  , puPrereqs  :: [Text]
  , puRemedies :: [RemedySpec]
  } deriving (Eq, Show)

instance FromJSON PuzzleRef where
  parseJSON = withObject "PuzzleRef" $ \o -> PuzzleRef
    <$> o .: "file"
    <*> o .:? "role"
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

-- | An inlined level file: its parsed front-matter 'Meta' and its Markdown
-- 'fileBody'. The bundle step produces these; the loader reads the body with
-- 'splitLevelSource' / 'levelProse' and combines it with the metadata.
data FileSpec = FileSpec
  { fileMeta :: Meta
  , fileBody :: Text
  } deriving (Eq, Show)

instance FromJSON FileSpec where
  parseJSON = withObject "FileSpec" $ \o -> FileSpec
    <$> o .:? "meta" .!= emptyMeta
    <*> o .:? "body" .!= ""

-- | A level file's front-matter: the metadata intrinsic to the level. A puzzle
-- uses 'metaStatement' and 'metaInventory'; a prose page uses only id, title,
-- and (BOPPPS) role. Unused fields default empty, so one record serves both.
data Meta = Meta
  { metaId        :: Text
  , metaTitle     :: Text
  , metaRole      :: Maybe Text
  , metaStatement :: Text
  , metaInventory :: [Text]
  } deriving (Eq, Show)

emptyMeta :: Meta
emptyMeta = Meta "" "" Nothing "" []

instance FromJSON Meta where
  parseJSON = withObject "Meta" $ \o -> Meta
    <$> o .:? "id" .!= ""
    <*> o .:? "title" .!= ""
    <*> o .:? "role"
    <*> o .:? "statement" .!= ""
    <*> o .:? "inventory" .!= []

-- | Split a level body into its @(prelude, template, solution)@ rzk code, by the
-- role word on each fenced block (decision D2). A block opens with a fence whose
-- info string is @rzk <role>@ and closes with a bare @```@:
--
-- > ```rzk prelude
-- > #def id-hom … := …
-- > ```
--
-- The @prelude@ is every @prelude@ block concatenated in order; the @template@
-- and @solution@ are the single block of each role. Other fenced blocks (a plain
-- @```rzk@ display block in the intro, or another language) and the surrounding
-- Markdown prose are ignored. Each block's body is rejoined with 'T.unlines' (so
-- it carries a trailing newline, matching the hand-authored 'RzkGame.Content'
-- fields). Fails when a @template@ or @solution@ block is missing or duplicated,
-- or a fence is left unterminated.
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

-- | The prose of a level body: its @(intro, conclusion)@. The intro is the
-- Markdown before the first role-tagged rzk block (so a plain @```rzk@ display
-- block stays part of the intro); the conclusion is the Markdown under a trailing
-- @## Conclusion@ heading. Either is empty when absent. The text is trimmed, to
-- match the hand-authored fields which carry no surrounding whitespace.
levelProse :: Text -> (Text, Text)
levelProse body = (intro, conclusion)
  where
    ls    = T.lines body
    intro = T.strip (T.unlines (takeWhile (not . isRoleFence) ls))
    conclusion = case dropWhile (not . isConclusionHeading) ls of
      (_ : rest) -> T.strip (T.unlines rest)
      []         -> ""
    isRoleFence l   = case fenceRole l of Just (Just _) -> True; _ -> False
    isConclusionHeading l = T.strip l == "## Conclusion"

-- | Parse the fenced code blocks of a Markdown source into @(role, body lines)@
-- pairs, in order. Lines outside a recognised block are dropped.
parseBlocks :: [Text] -> Either Text [(Text, [Text])]
parseBlocks = go
  where
    go [] = Right []
    go (l : rest) = case fenceRole l of
      Nothing   -> go rest
      Just role ->
        let (body, after) = break isFenceClose rest
        in case after of
             []        -> Left "unterminated ``` block in level source"
             (_ : ys)  -> case role of
               Just r  -> ((r, body) :) <$> go ys
               Nothing -> go ys

    isFenceClose line = T.strip line == "```"

-- | Classify a line as a code-fence opener. 'Nothing' if it is not a fence;
-- @Just (Just role)@ for a recognised @rzk <role>@ block; @Just Nothing@ for any
-- other fence (a plain @```rzk@, another language, or a bare closing @```@).
fenceRole :: Text -> Maybe (Maybe Text)
fenceRole line
  | "```" `T.isPrefixOf` s =
      case T.words (T.drop 3 s) of
        ("rzk" : r : _) | r `elem` ["prelude", "template", "solution"] -> Just (Just r)
        _                                                              -> Just Nothing
  | otherwise = Nothing
  where s = T.stripStart line

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
