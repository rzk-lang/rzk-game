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
  , ChapterSpec (..)
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
  , inventoryType
  ) where

import           Control.Applicative ((<|>))
import           Data.Aeson          (FromJSON (..), Value (String), withObject,
                                      (.!=), (.:), (.:?))
import           Data.Aeson.Types    (Parser)
import           Data.Map.Strict     (Map)
import           Data.Text           (Text)
import qualified Data.Text           as T

import           Language.Rzk.Syntax     (printTree)
import           RzkGame.Parse           (safeParseModule)
import           Language.Rzk.Syntax.Abs

import           RzkGame.Level       (Hint (..), InventoryEntry (..))

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

-- | The table of contents (the @game.yaml@): a title and the ordered chapters.
data GameSpec = GameSpec
  { gsTitle    :: Text
  , gsChapters :: [ChapterSpec]
  } deriving (Eq, Show)

instance FromJSON GameSpec where
  parseJSON = withObject "GameSpec" $ \o -> GameSpec
    <$> o .:? "title" .!= ""
    <*> o .:? "chapters" .!= []

-- | A chapter: an optional title grouping a run of sections. The top level of a
-- @game.yaml@ is a list of these; an untitled chapter renders its sections with
-- no heading (a "top-level" group).
data ChapterSpec = ChapterSpec
  { csTitle    :: Maybe Text
  , csSections :: [SectionSpec]
  } deriving (Eq, Show)

instance FromJSON ChapterSpec where
  parseJSON = withObject "ChapterSpec" $ \o -> ChapterSpec
    <$> o .:? "title"
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
  , metaInventory :: [InventoryEntry]
  , metaForbidden :: [Text]
  , metaHints     :: [Hint]
  , metaGated     :: Bool
  } deriving (Eq, Show)

emptyMeta :: Meta
emptyMeta = Meta "" "" Nothing "" [] [] [] False


instance FromJSON Meta where
  parseJSON = withObject "Meta" $ \o -> Meta
    <$> o .:? "id" .!= ""
    <*> o .:? "title" .!= ""
    <*> o .:? "role"
    <*> o .:? "statement" .!= ""
    <*> (o .:? "inventory" .!= [] >>= traverse parseInventoryEntry)
    <*> o .:? "forbidden" .!= []
    <*> (o .:? "hints" .!= [] >>= traverse parseHint)
    <*> o .:? "gated" .!= False

-- | Read one inventory entry. It is either a bare name string (the type is then
-- looked up from the prelude) or @{ name, type?, synopsis? }@. 'InventoryEntry'
-- lives in 'RzkGame.Level', so it is decoded here without an orphan instance.
parseInventoryEntry :: Value -> Parser InventoryEntry
parseInventoryEntry (String s) = pure (InventoryEntry s Nothing Nothing)
parseInventoryEntry v = flip (withObject "InventoryEntry") v $ \o -> InventoryEntry
  <$> o .:  "name"
  <*> o .:? "type"
  <*> o .:? "synopsis"

-- | Read one front-matter hint: @{ text, when-goal? }@. The 'Hint' type lives in
-- 'RzkGame.Level', so we decode it here without an orphan 'FromJSON' instance.
-- @when-goal@ is the trigger string (optional); @text@ is the Markdown prose.
parseHint :: Value -> Parser Hint
parseHint = withObject "Hint" $ \o -> Hint
  <$> o .:? "text" .!= ""
  <*> o .:? "when-goal"

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

-- | Recover the goal — the pinned definition name, its required /closed/ Π-type,
-- and the @uses (…)@ assumptions it declares — from a @template@ block's @#def@.
-- The win-condition check appends
--
-- > #def __rzkgame_goal_check uses (…) : <type> := <name>
--
-- so the type must be the closed Π-type that @<name>@ inhabits, with no binders
-- left on the left of the @:@, and the @uses@ list must match what @<name>@
-- transitively needs (see 'RzkGame.Level.checkLevel').
--
-- We parse the template with rzk's own parser and read the @#def@'s name, its
-- @uses@ vars, and its parameter telescope, then fold the telescope into a Π over
-- the result type and print it back ('closedType'). Authors may write the
-- template with grouped binders (the gentle style the hand-authored levels use,
-- e.g. @#def rut (A : U) (x y : A) … : T := \\ … → ?@) /or/ already in closed form
-- (@#def rut : (A : U) → … → T := …@): a closed-form @#def@ simply has no
-- parameters, so its result type /is/ the closed type. The printed type is rzk's
-- canonical surface form, which matches the hand-authored 'RzkGame.Content'
-- @levelGoalType@.
goalFromTemplate :: Text -> Either Text (Text, Text, [Text])
goalFromTemplate template =
  case safeParseModule ("#lang rzk-1\n" <> template) of
    Left err                -> Left ("template does not parse: " <> err)
    Right (Module _ _ cmds) -> case [ c | c@CommandDefine{} <- cmds ] of
      (c : _) -> Right (commandName c, closedType c, commandUses c)
      []      -> Left "template has no `#def` to read the goal from"

-- | The as-written type of a prelude definition, looked up by name. Parses the
-- prelude and recovers the closed Π-type of the @#def@ or @#postulate@ of that
-- name the same way 'goalFromTemplate' recovers the goal — the original declared
-- type, not weak-head-normalised. 'Nothing' when the prelude does not parse or no
-- command defines that exact name (e.g. the name is a parameter, a projection, or
-- an applied expression), so the inventory simply shows no type for that entry.
inventoryType :: Text -> Text -> Maybe Text
inventoryType prelude wanted = case safeParseModule prelude of
  Left _                  -> Nothing
  Right (Module _ _ cmds) -> case [ c | c <- cmds, isDecl c, commandName c == wanted ] of
    (c : _) -> Just (closedType c)
    []      -> Nothing
  where
    isDecl CommandDefine{}    = True
    isDecl CommandPostulate{} = True
    isDecl _                  = False

-- | The closed Π-type a @#def@/@#postulate@ declares, as canonical surface text:
-- its parameter telescope ('foldParams') folded into a Π over the result type and
-- pretty-printed. Defined to return the result type unchanged for any other
-- command, but the callers only ever pass a declaration.
closedType :: Command -> Text
closedType cmd = T.pack (printTree (uncurry foldParams (commandSig cmd)))

-- | A declaration's @(parameters, result type)@; @([], …)@ for anything else.
commandSig :: Command -> ([Param], Term)
commandSig (CommandDefine _ _ _ ps ty _)  = (ps, ty)
commandSig (CommandPostulate _ _ _ ps ty) = (ps, ty)
commandSig c                              = ([], Universe (commandAnn c))

-- | Fold a parameter telescope into a Π-type over the result. Each binder group
-- @(x y : A)@ becomes @(x : A) → (y : A) → …@ (one Π per pattern), and a shape
-- binder @(t : I | φ)@ its extension Π. Untyped binders cannot appear in a
-- well-formed declaration signature, so they are dropped.
foldParams :: [Param] -> Term -> Term
foldParams ps body = foldr wrap body ps
  where
    wrap (ParamPatternType _ pats ty) acc =
      foldr (\p a -> TypeFun Nothing (ParamTermType Nothing (patTerm p) ty) a) acc pats
    wrap (ParamPatternShape _ pats sh tope) acc =
      foldr (\p a -> TypeFun Nothing (ParamTermShape Nothing (patTerm p) sh tope) a) acc pats
    wrap _ acc = acc

-- | A binder pattern as the term that names it in a Π parameter.
patTerm :: Pattern -> Term
patTerm (PatternVar _ v)        = Var Nothing v
patTerm (PatternPair _ p q)     = Pair Nothing (patTerm p) (patTerm q)
patTerm (PatternTuple _ p q rs) = Tuple Nothing (patTerm p) (patTerm q) (map patTerm rs)
patTerm (PatternUnit _)         = Unit Nothing

-- | The head name of a @#def@/@#postulate@ (empty for any other command).
commandName :: Command -> Text
commandName (CommandDefine _ v _ _ _ _)  = varText v
commandName (CommandPostulate _ v _ _ _) = varText v
commandName _                            = ""

-- | The @uses (…)@ assumption names a @#def@/@#postulate@ declares (empty when it
-- has no @uses@ clause, or for any other command).
commandUses :: Command -> [Text]
commandUses (CommandDefine _ _ (DeclUsedVars _ vs) _ _ _)  = map varText vs
commandUses (CommandPostulate _ _ (DeclUsedVars _ vs) _ _) = map varText vs
commandUses _                                             = []

varText :: VarIdent -> Text
varText (VarIdent _ (VarIdentToken t)) = t

commandAnn :: Command -> BNFC'Position
commandAnn (CommandDefine a _ _ _ _ _)  = a
commandAnn (CommandPostulate a _ _ _ _) = a
commandAnn _                            = Nothing
