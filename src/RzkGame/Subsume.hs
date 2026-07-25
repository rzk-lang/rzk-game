{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Term subsumption for the "requires typing" classifier.
--
-- A puzzle needs typing when its reference solution cannot be reached by taps
-- alone. To decide that, 'RzkGame.Level' walks the solution move by move; at each
-- step it needs a /subsumption/ test: does the reference solution fill the holes
-- of a candidate? Here a hole in the candidate is a wildcard that matches any
-- subterm, and everything else must match up to α-equivalence — a candidate
-- @\\ t → ?@ subsumes a solution @\\ x → f x@, the bound names notwithstanding.
--
-- We reuse rzk's free-foil core rather than a syntactic comparison. Each
-- definition body is closed (its free identifiers — the telescope parameters and
-- the prelude lemmas it names — are bound by an outer λ, the same set on both
-- sides so the free occurrences align), converted with rzk's 'toTermClosed', and
-- compared by 'subsumes', a transcription of free-foil's @alphaEquiv@ with one
-- extra rule: a hole on the left matches anything. The binder-renaming dance in
-- the scoped case is free-foil's own; only the hole rule and the recursive calls
-- differ.
module RzkGame.Subsume
  ( subsumesSolution
  ) where

import           Data.Coerce               (coerce)
import           Data.Data                 (Data, cast, gmapQ)
import           Data.List                 (nub, sort)
import           Data.Maybe                (listToMaybe)
import           Data.Text                 (Text)

import qualified Control.Monad.Foil          as Foil
import qualified Control.Monad.Foil.Relative as Foil (liftRM)
import           Control.Monad.Free.Foil     (AST (..), ScopedAST (..))
import           Data.ZipMatchK              (zipMatchWith2)

import           Language.Rzk.Foil.Convert   (toTermClosed)
import           Language.Rzk.Foil.Syntax    (TermSig (HoleF))
import qualified Language.Rzk.Foil.Syntax    as FT (Term)
import           Language.Rzk.Syntax.Abs     hiding (Var)
import           RzkGame.Parse               (safeParseModule)

-- | Does the reference solution @solSrc@ fill the holes of the candidate
-- @candSrc@? Both are the full source of a @#def@ with the /same/ signature (the
-- template's, only the body after @:=@ differing), as produced along a tap walk.
-- 'False' if either fails to parse or has no @#def@.
subsumesSolution :: Text -> Text -> Bool
subsumesSolution candSrc solSrc =
  case (defBody candSrc, defBody solSrc) of
    (Just candBody, Just solBody) ->
      let names = sort (nub (varIdentTokens candBody ++ varIdentTokens solBody))
      in subsumes Foil.emptyScope
           (toTermClosed (close names candBody))
           (toTermClosed (close names solBody))
    _ -> False

-- | The body term (right of @:=@) of the first @#def@ in a source fragment, if
-- it parses. The fragment is a bare block, so we prepend the @#lang@ pragma the
-- way 'RzkGame.Spec.goalFromTemplate' does.
defBody :: Text -> Maybe Term
defBody src = case safeParseModule ("#lang rzk-1\n" <> src) of
  Right (Module _ _ cmds) ->
    listToMaybe [ b | CommandDefine _ _ _ _ _ b <- cmds ]
  _ -> Nothing

-- | Close a body by binding the given names in an outer λ. The names are every
-- identifier occurring in /either/ body (telescope parameters and prelude
-- lemmas; rzk's built-in eliminators such as @first@ or @idJ@ are their own
-- syntax, not identifiers, so they need no binder). Binding the same set on both
-- sides in the same order makes matching free occurrences resolve to the same
-- bound name, so 'toTermClosed' is total and the two terms are comparable.
close :: [Text] -> Term -> Term
close []    body = body
close names body = Lambda Nothing (map param names) body
  where
    param n = ParamPattern Nothing (PatternVar Nothing (VarIdent Nothing (VarIdentToken n)))

-- | Every 'VarIdent' token occurring anywhere in a surface term (bound
-- occurrences included — an over-approximation is harmless, since a name bound
-- twice simply shadows). A small generic query over the BNFC syntax; no external
-- traversal library is pulled in for it.
varIdentTokens :: Data a => a -> [Text]
varIdentTokens x = here ++ concat (gmapQ varIdentTokens x)
  where
    here = case cast x :: Maybe VarIdent of
      Just (VarIdent _ (VarIdentToken t)) -> [t]
      _                                   -> []

-- | Subsumption up to α-equivalence with holes as wildcards: does @sol@ fill the
-- holes of @cand@? A transcription of free-foil's @alphaEquiv@ with the leading
-- hole rule added.
subsumes :: Foil.Distinct n => Foil.Scope n -> FT.Term n -> FT.Term n -> Bool
subsumes _scope (Node (HoleF _)) _ = True                  -- a hole matches anything
subsumes _scope (Var x) (Var y)    = x == coerce y
subsumes scope  (Node l) (Node r)  =
  case zipMatchWith2 (unit . subsumesScoped scope) (unit . subsumes scope) l r of
    Nothing -> False
    Just _  -> True
  where
    unit f a = if f a then Just () else Nothing
subsumes _ _ _ = False

-- | The scoped case, mirroring free-foil's @alphaEquivScoped@: unify the two
-- binders, then compare the bodies in the extended scope. The renaming is
-- free-foil's; only the recursive call into 'subsumes' differs.
subsumesScoped
  :: Foil.Distinct n
  => Foil.Scope n
  -> ScopedAST Foil.NameBinder TermSig n
  -> ScopedAST Foil.NameBinder TermSig n
  -> Bool
subsumesScoped scope (ScopedAST binder1 body1) (ScopedAST binder2 body2) =
  case Foil.unifyPatterns binder1 binder2 of
    Foil.SameNameBinders{} ->
      case Foil.assertDistinct binder1 of
        Foil.Distinct ->
          let scope1 = Foil.extendScopePattern binder1 scope
          in subsumes scope1 body1 body2
    Foil.RenameLeftNameBinder _ rename1to2 ->
      case Foil.assertDistinct binder2 of
        Foil.Distinct ->
          let scope2 = Foil.extendScopePattern binder2 scope
          in subsumes scope2
               (Foil.liftRM scope2 (Foil.fromNameBinderRenaming rename1to2) body1) body2
    Foil.RenameRightNameBinder _ rename2to1 ->
      case Foil.assertDistinct binder1 of
        Foil.Distinct ->
          let scope1 = Foil.extendScopePattern binder1 scope
          in subsumes scope1 body1
               (Foil.liftRM scope1 (Foil.fromNameBinderRenaming rename2to1) body2)
    Foil.RenameBothBinders binder' rename1 rename2 ->
      case Foil.assertDistinct binder' of
        Foil.Distinct ->
          let scope' = Foil.extendScopePattern binder' scope
          in subsumes scope'
               (Foil.liftRM scope' (Foil.fromNameBinderRenaming rename1) body1)
               (Foil.liftRM scope' (Foil.fromNameBinderRenaming rename2) body2)
    Foil.NotUnifiable -> False
