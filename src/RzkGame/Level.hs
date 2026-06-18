{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | The level model and the check against rzk.
--
-- A level is a read-only /prelude/ (already-checked definitions) plus an
-- /editable/ region the player fills in. Checking concatenates the two, parses
-- and typechecks the result in lenient hole mode, and classifies the outcome.
-- The player wins when the editable region typechecks with no remaining holes.
module RzkGame.Level
  ( Level (..)
  , Hint (..)
  , CheckResult (..)
  , HoleView (..)
  , MoveKind (..)
  , checkLevel
  , holeActions
  , refineFirstHole
  , renderResult
  , resultErrorLines
  , hintMatchesGoal
  , visibleHints
  , plainHintCount
  , inventoryViolations
  , gatePassed
  ) where

import           Data.Char            (isDigit, isSpace)
import           Data.List            (nub)
import           Data.Maybe           (mapMaybe, maybeToList)
import           Data.Text            (Text)
import qualified Data.Text            as T
import           Text.Read            (readMaybe)

import           RzkGame.Highlight    (Tok (..), TokClass (Plain), highlight)

import           Language.Rzk.Syntax  (parseModule)
import           Rzk.Diagnostic       (locationOfTypeError)
import           Rzk.TypeCheck        (HoleEntry (..), HoleInfo (..),
                                       LocationInfo (..),
                                       OutputDirection (BottomUp),
                                       ppTypeErrorInScopedContext',
                                       typecheckModulesWithHoles)

-- | A single level. The text fields are Rzk source or human-readable prose.
data Level = Level
  { levelTitle      :: Text   -- ^ short title
  , levelIntro      :: Text   -- ^ prose shown before the goal
  , levelStatement  :: Text   -- ^ the goal, human-readable
  , levelPrelude    :: Text   -- ^ read-only, pre-checked definitions
  , levelTemplate   :: Text   -- ^ the editable region's starting text (with a @?@)
  , levelSolution   :: Text   -- ^ a reference solution (for self-tests)
  , levelGoalName   :: Text   -- ^ the definition the player must produce
  , levelGoalType   :: Text   -- ^ its required (closed) type, enforced on check
  , levelInventory  :: [Text] -- ^ names available to the player
  , levelHints      :: [Hint] -- ^ authored hints, revealed on request
  , levelGated      :: Bool   -- ^ make an inventory violation fail the check
  , levelConclusion :: Text   -- ^ prose shown on success
  } deriving (Eq, Show)

-- | An authored hint, shown when the player is stuck. 'hintText' is Markdown
-- prose (rendered like the intros). 'hintWhenGoal' is an optional trigger: when
-- it is a (case-sensitive) infix of the focused hole's rendered goal, the hint
-- is auto-surfaced (see 'hintMatchesGoal'). A hint with no trigger is only ever
-- reached by the ordered, one-at-a-time reveal.
data Hint = Hint
  { hintText     :: Text
  , hintWhenGoal :: Maybe Text
  } deriving (Eq, Show)

-- | Whether a hint's @when-goal@ trigger fires for a rendered goal text. The
-- match is deliberately simple — a case-sensitive infix test on the already
-- rendered goal, not structural unification — so an author can reason about it
-- by reading the goal panel. A hint with no trigger never auto-surfaces.
hintMatchesGoal :: Hint -> Text -> Bool
hintMatchesGoal h goal = case hintWhenGoal h of
  Nothing  -> False
  Just sub -> not (T.null sub) && sub `T.isInfixOf` goal

-- | The number of /plain/ hints in a list — those with no @when-goal@. These are
-- the ones the player reveals one at a time; see 'visibleHints'.
plainHintCount :: [Hint] -> Int
plainHintCount = length . filter ((== Nothing) . hintWhenGoal)

-- | Which hints to show, paired with their position in the authored list (so the
-- UI can key them stably). Two kinds of hint behave differently:
--
--   * a /plain/ hint (no @when-goal@) is revealed one at a time by the player —
--     the first @shown@ plain hints, by author order, are visible;
--   * a /contextual/ hint (with a @when-goal@) is shown only once the player has
--     revealed at least one hint (so a pristine level the player has not engaged
--     with is never spoiled) /and/ its trigger matches the focused @goal@.
--
-- A contextual hint is therefore never reached by the manual reveal and never
-- shown out of context: it appears exactly while it is relevant and disappears
-- when the goal moves on. The result keeps the authored order.
visibleHints :: [Hint] -> Maybe Text -> Int -> [(Int, Hint)]
visibleHints hints mgoal shown = go 0 0 hints
  where
    engaged = shown > 0
    go _ _ [] = []
    go i r (h : rest) = case hintWhenGoal h of
      Nothing
        | r < shown -> (i, h) : go (i + 1) (r + 1) rest
        | otherwise ->          go (i + 1) (r + 1) rest
      Just _
        | engaged && maybe False (hintMatchesGoal h) mgoal
                    -> (i, h) : go (i + 1) r rest
        | otherwise ->          go (i + 1) r rest

-- | The outcome of checking an editable region against a level.
--
-- 'ParseError' and 'TypeError' carry, besides the formatted message, the line(s)
-- to squiggle in the editor — expressed relative to the /editable/ region
-- (1-based), so the UI can underline them directly. rzk records locations at
-- line granularity only (the column is discarded, and core terms keep no
-- per-node position), so a diagnostic points at the enclosing command's line.
-- An error outside the editable region (in the read-only prelude, or in the
-- synthetic goal-check appended by 'checkLevel') maps to no line: it is reported
-- as a message with nothing to underline.
data CheckResult
  = NotChecked              -- ^ nothing checked yet
  | ParseError Text (Maybe Int) -- ^ the source did not parse (+ editable line)
  | TypeError Text [Int]    -- ^ a genuine type error (+ editable lines to squiggle)
  | Holes [HoleView]        -- ^ unsolved holes, each with its goal + local context
  | Solved                  -- ^ typechecks with no remaining holes
  deriving (Eq, Show)

-- | The editable-region line(s) a result wants squiggled (empty when there is
-- nothing to underline). Consumed by the editor overlay.
resultErrorLines :: CheckResult -> [Int]
resultErrorLines = \case
  ParseError _ ml -> maybeToList ml
  TypeError _ ls  -> ls
  _               -> []

-- | A single hole with every part pre-rendered to display text, so the UI can
-- lay it out as panels (goal / context / cube variables / topes) without
-- depending on rzk's internal term representation. The global environment is
-- deliberately excluded by rzk (it belongs in a searchable inventory, not the
-- goal panel); local hypotheses are split into term variables and cube
-- variables, matching the cube/tope layer of simplicial type theory.
data HoleView = HoleView
  { hvName     :: Maybe Text     -- ^ the @?name@, if the hole was named
  , hvGoal     :: Text           -- ^ the goal, shown as @(b : ty | tope)@ for a shape
  , hvContext  :: [(Text, Text)] -- ^ term hypotheses, as @(name, type)@
  , hvCubeVars :: [(Text, Text)] -- ^ cube variables, as @(name, type)@
  , hvTopes    :: [Text]         -- ^ tope assumptions
  , hvMoves    :: [Text]         -- ^ elimination/context moves (rzk's @holeCandidates@)
  , hvIntros   :: [Text]         -- ^ introduction moves (rzk's @holeIntroductions@)
  } deriving (Eq, Show)

-- | Convert rzk's structured 'HoleInfo' into a display-ready 'HoleView'. Each
-- field is already in user-facing names, so we just render it to text here.
toHoleView :: HoleInfo -> HoleView
toHoleView HoleInfo{..} = HoleView
  { hvName     = (\n -> "?" <> tshow n) <$> holeName
  , hvGoal     = case holeGoalShape of
      Nothing        -> tshow holeGoal
      Just (s, tope) -> "(" <> tshow s <> " : " <> tshow holeGoal
                          <> " | " <> tshow tope <> ")"
  , hvContext  = map entry holeTermVars
  , hvCubeVars = map entry holeCubeVars
  , hvTopes    = map tshow holeTopes
  , hvMoves    = map (humanize . tshow) holeCandidates
  , hvIntros   = map (humanize . tshow) holeIntroductions
  }
  where
    entry e = (tshow (holeEntryName e), tshow (holeEntryType e))

tshow :: Show a => a -> Text
tshow = T.pack . show

-- | The /inventory gating/ check: the prelude lemmas the editable region uses
-- in its proof but that the level does not grant. rzk has no usage restriction,
-- so this is computed in the engine, not the type-checker.
--
-- We intersect three name sets: the names the prelude /defines/
-- ('preludeDefinedNames', the @#def@/@#postulate@ heads), the names the editable
-- proof /references/ ('referencedNames'), and the level's allow-list (the
-- leading token of each 'levelInventory' entry). A name that is prelude-defined
-- and used but not granted is a violation.
--
-- Two deliberate restrictions keep a violation to a /real/ prelude lemma. First,
-- only the proof /bodies/ are scanned (the text after each @:=@), never the type
-- signatures, so the type formers a goal mentions (@hom@, @hom2@, @Δ¹@, …) are
-- not flagged. Second, intersecting with the prelude-defined names drops local
-- hypotheses and rzk keywords, which are never prelude-defined. A level with an
-- empty inventory gates nothing (the inventory was unused before Phase 5), so the
-- old behaviour is preserved.
inventoryViolations :: Level -> Text -> [Text]
inventoryViolations lvl editable
  | null (levelInventory lvl) = []
  | otherwise =
      nub [ n | n <- referencedNames editable
              , n `elem` defined, n `notElem` allowed ]
  where
    defined = preludeDefinedNames (levelPrelude lvl)
    allowed = mapMaybe firstToken (levelInventory lvl)
    firstToken e = case T.words e of (n : _) -> Just n; [] -> Nothing

-- | The names a prelude /defines/: the first word after each @#def@ or
-- @#postulate@ command. Continuation lines (indented, no command) are skipped.
preludeDefinedNames :: Text -> [Text]
preludeDefinedNames = mapMaybe defName . T.lines
  where
    defName line = case T.words (T.stripStart line) of
      (cmd : n : _) | cmd `elem` ["#def", "#postulate"] -> Just n
      _                                                 -> Nothing

-- | The identifiers a proof /body/ references. The body is the text after each
-- @:=@ up to the next command (@#@), so type signatures are excluded. We reuse
-- the lossless 'highlight' tokeniser and read the words out of its 'Plain'
-- tokens, rather than re-lexing by hand.
referencedNames :: Text -> [Text]
referencedNames src =
  [ w | Tok Plain t <- highlight (proofBodies src), w <- T.words t ]
  where
    proofBodies = T.unwords . map (fst . T.breakOn "#") . drop 1 . T.splitOn ":="

-- | Whether the editable region passes the level's gate: trivially true on a
-- level that does not opt into 'levelGated', otherwise true only when there are
-- no inventory violations. A gated level with a violation does not count as
-- solved even if it type-checks (the UI surfaces the violation as the blocker);
-- a non-gated level only ever shows a soft notice, so its solve still stands.
gatePassed :: Level -> Text -> Bool
gatePassed lvl editable =
  not (levelGated lvl) || null (inventoryViolations lvl editable)

-- | Best-effort line number from a parse error message. rzk's parser formats its
-- errors as @"syntax error at line L column C …"@ (and layout errors likewise),
-- so we read the first number after @"line "@. The column is present in the text
-- but not used: the editor squiggles whole lines (see 'CheckResult').
parseErrorLine :: Text -> Maybe Int
parseErrorLine msg =
  let after  = T.drop 5 (snd (T.breakOn "line " msg))  -- text past "line "
      digits = T.takeWhile isDigit (T.dropWhile (not . isDigit) after)
  in if T.null digits then Nothing else readMaybe (T.unpack digits)

-- | Check an editable region against a level. The prelude is prepended, so the
-- player's text is checked in the context of the given definitions.
--
-- The win condition is /not/ merely that the source typechecks with no holes:
-- an empty editable region would then pass on the prelude alone. Instead the
-- level pins the definition the player must produce ('levelGoalName') and its
-- required type ('levelGoalType'), and we append a synthetic check
--
-- > #def __rzkgame_goal_check : <levelGoalType> := <levelGoalName>
--
-- so the proof only counts as solved when a definition of that name with that
-- type is in scope and hole-free. The player is free to add helper definitions;
-- only the named goal is pinned. A missing or mistyped goal makes the synthetic
-- check fail to typecheck, and is reported like any other error.
checkLevel :: Level -> Text -> CheckResult
checkLevel lvl editable =
  let goalCheck = "\n#def __rzkgame_goal_check : " <> levelGoalType lvl
                    <> "\n  := " <> levelGoalName lvl
      src = levelPrelude lvl <> "\n" <> editable <> goalCheck
  in case parseModule src of
       Left err -> ParseError err (toEditableLine =<< parseErrorLine err)
       Right m  ->
         case typecheckModulesWithHoles [("level", m)] of
           -- A fatal error short-circuits to 'Left'; recoverable type errors
           -- (e.g. an unbound variable or a type mismatch) come back in the
           -- middle field. Both must be reported — only the holes-aware
           -- elaboration records unsolved holes separately. A real type error
           -- takes priority over any holes the partial term still has.
           Left err -> TypeError (ppErr err) (errorLines err)
           Right (_, err : _, _) -> TypeError (ppErr err) (errorLines err)
           Right (_, [], holes)
             | null holes -> Solved
             | otherwise  -> Holes (map toHoleView holes)
  where
    ppErr = T.pack . ppTypeErrorInScopedContext' BottomUp

    -- The editable region is concatenated after the prelude and a separating
    -- newline, so its first character sits this many lines into 'src' (1-based).
    editableStart = T.count "\n" (levelPrelude lvl) + 2
    editableSpan  = T.count "\n" editable + 1

    -- Map an absolute 'src' line to a 1-based line within the editable region,
    -- dropping lines that fall in the prelude or the synthetic goal-check.
    toEditableLine :: Int -> Maybe Int
    toEditableLine l =
      let r = l - editableStart + 1
      in if r >= 1 && r <= editableSpan then Just r else Nothing

    -- A type error's line, mapped into the editable region (empty when it has no
    -- recorded location, or the location is outside the editable region).
    errorLines err =
      mapMaybe toEditableLine
        (maybeToList (locationLine =<< locationOfTypeError err))

-- | Tap-to-refine: replace the first hole (@?@) in the text with the given
-- insertion. This is how a tap turns into an edit — the engine re-checks the
-- rewritten text, so no engine-side refinement logic is needed. If there is no
-- hole, the text is returned unchanged.
--
-- The insertion is parenthesised (see 'parenthesize') so an application spine or
-- a lambda cannot re-associate or fail to parse in the hole's position.
refineFirstHole :: Text -> Text -> Text
refineFirstHole insertion src =
  case T.breakOn "?" src of
    (_, after) | T.null after -> src
    (before, after)           -> before <> parenthesize insertion <> T.drop 1 after

-- | Wrap a refinement insertion in parentheses, unless it does not need them: a
-- bare atom (no internal whitespace, e.g. @x@, @refl@, @recBOT@) and a term that
-- is already a single parenthesised group (e.g. @(? , ?)@) are left as is. This
-- keeps the rewritten proof parseable without sprinkling redundant parentheses.
parenthesize :: Text -> Text
parenthesize ins
  | not (T.any isSpace s)             = ins
  | "(" `T.isPrefixOf` s && wrapsWhole s = ins
  | otherwise                         = "(" <> ins <> ")"
  where
    s = T.strip ins

-- | Does the leading @(@ of a string close only at its final character — i.e. is
-- the whole string a single parenthesised group, rather than two adjacent ones?
wrapsWhole :: Text -> Bool
wrapsWhole s = go (0 :: Int) 0 (T.unpack s)
  where
    n = T.length s
    go _ _ []           = False
    go depth i (c : cs) =
      let depth' = case c of '(' -> depth + 1; ')' -> depth - 1; _ -> depth
      in if depth' == 0 then i == n - 1 else go depth' (i + 1) cs

-- | The kind of a tap-to-fill move, used to colour-code the move button and
-- separate the move's kind from its filler term in the UI.
--
--   * 'Intro' builds a value of the goal by its constructor;
--   * 'Give' is an elimination spine over a hypothesis or a context-driven move.
data MoveKind = Intro | Give
  deriving (Eq, Show)

-- | Smart inventory: the tap-to-fill moves offered for a focused hole, computed
-- type-directed by rzk rather than by string heuristics here. Each move is its
-- 'MoveKind' paired with the filler term that is dropped onto the first @?@
-- (whose carried holes become the next moves):
--
--   * 'Intro' moves build a value of the goal by its constructor (rzk's
--     @holeIntroductions@): @\\ (t , s) → ?@, @(? , ?)@, @refl@, a tope
--     constructor, …;
--   * 'Give' moves are elimination spines over the hypotheses and context-driven
--     moves like @recBOT@ / @recOR@ (rzk's @holeCandidates@).
--
-- Introductions come first: they make progress on the goal's own structure,
-- which is usually what a fresh @?@ needs. We keep rzk's order within each kind
-- and only drop duplicates.
holeActions :: HoleView -> [(MoveKind, Text)]
holeActions HoleView{..} =
     [ (Intro, m) | m <- nub hvIntros ]
  <> [ (Give,  m) | m <- nub hvMoves ]

-- | Render rzk's notation as the ASCII the levels use in prose and reference
-- solutions, so a tapped move reads the same as the text the player would type.
-- Projections @π₁@ / @π₂@ become @first@ / @second@, and the tope constants
-- @⊤@ / @⊥@ become @TOP@ / @BOT@. All forms parse in rzk either way; the other
-- tope operators (@≡@, @≤@, @∧@, @∨@, @↦@) already match the level notation.
--
-- The choices follow the sHoTT style guide's use-of-unicode conventions
-- (https://rzk-lang.github.io/sHoTT/STYLEGUIDE/#use-of-unicode-characters):
-- @first@ / @second@ and the @TOP@ / @BOT@ keywords are written in ASCII, while
-- the relational tope operators are kept in their unicode form.
humanize :: Text -> Text
humanize = T.replace "π₁" "first" . T.replace "π₂" "second"
         . T.replace "⊤" "TOP"    . T.replace "⊥" "BOT"

-- | A plain-text rendering of a result, for self-tests and logs.
renderResult :: CheckResult -> Text
renderResult = \case
  NotChecked      -> "(not checked)"
  ParseError e ml -> "Parse error" <> atLine (maybeToList ml) <> ":\n" <> e
  TypeError e ls  -> "Type error" <> atLine ls <> ":\n" <> e
  Holes hs        -> tshow (length hs) <> " hole(s):\n\n"
                       <> T.intercalate "\n" (map renderHoleView hs)
  Solved          -> "Solved: no holes, typechecks."
  where
    -- A " (at line N)" / " (at lines N, M)" suffix for the self-test/log output.
    atLine []  = ""
    atLine [l] = " (at line " <> tshow l <> ")"
    atLine ls  = " (at lines " <> T.intercalate ", " (map tshow ls) <> ")"

-- | A plain-text rendering of a single hole, mirroring rzk's @ppHoleInfo@ for
-- the self-tests and logs.
renderHoleView :: HoleView -> Text
renderHoleView HoleView{..} = T.unlines $
  [ "Hole" <> maybe "" (" " <>) hvName
  , "  goal:"
  , "    " <> hvGoal
  ]
  <> section "context" hvContext
  <> section "cube variables" hvCubeVars
  <> (if null hvTopes then [] else "  tope context:" : map ("    " <>) hvTopes)
  where
    section title entries
      | null entries = []
      | otherwise = ("  " <> title <> ":")
          : [ "    " <> n <> " : " <> ty | (n, ty) <- entries ]
