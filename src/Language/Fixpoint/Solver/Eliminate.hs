{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE BangPatterns         #-}

module Language.Fixpoint.Solver.Eliminate (solverInfo) where

import qualified Data.HashSet        as S
import qualified Data.HashMap.Strict as M

import           Language.Fixpoint.Types.Config    (Config)
import           Language.Fixpoint.Types
import           Language.Fixpoint.Types.Visitor   (kvars, isConcC)
import           Language.Fixpoint.Graph           -- (depCuts, depNonCuts, elimVars)
import           Language.Fixpoint.Misc            (safeLookup, group, errorstar)

--------------------------------------------------------------------------------
solverInfo :: Config -> SInfo a -> SolverInfo a
--------------------------------------------------------------------------------
solverInfo cfg sI = SI sHyp sI' cD
  where
    cD             = elimDeps sI es nKs
    sI'            = cutSInfo   kI cKs sI
    sHyp           = solFromList [] kHyps
    kHyps          = nonCutHyps kI nKs sI
    kI             = kIndex  sI
    (es, cKs, nKs) = kutVars cfg sI

cutSInfo :: KIndex -> S.HashSet KVar -> SInfo a -> SInfo a
cutSInfo kI cKs si = si { ws = ws', cm = cm' }
  where
    ws'   = M.filterWithKey (\k _ -> S.member k cKs) (ws si)
    cm'   = M.filterWithKey (\i c -> S.member i cs || isConcC c) (cm si)
    cs    = S.fromList      (concatMap kCs cKs)
    kCs k = M.lookupDefault [] k kI

kutVars :: Config -> SInfo a -> ([CEdge], S.HashSet KVar, S.HashSet KVar)
kutVars cfg si   = (es, depCuts ds, depNonCuts ds)
  where
    (es, ds)     = elimVars cfg si

--------------------------------------------------------------------------------
-- | Map each `KVar` to the list of constraints on which it appears on RHS
--------------------------------------------------------------------------------
type KIndex = M.HashMap KVar [Integer]

--------------------------------------------------------------------------------
kIndex     :: SInfo a -> KIndex
--------------------------------------------------------------------------------
kIndex si  = group [(k, i) | (i, c) <- iCs, k <- rkvars c]
  where
    iCs    = M.toList (cm si)
    rkvars = kvars . crhs

nonCutHyps :: KIndex -> S.HashSet KVar -> SInfo a -> [(KVar, Hyp)]
nonCutHyps kI nKs si = [ (k, nonCutHyp kI si k) | k <- S.toList nKs ]

nonCutHyp  :: KIndex -> SInfo a -> KVar -> Hyp
nonCutHyp kI si k = nonCutCube <$> cs
  where
    cs            = getSubC   si <$> M.lookupDefault [] k kI

nonCutCube :: SimpC a -> Cube
nonCutCube c = Cube (senv c) (rhsSubst c) (subcId c) (stag c)


rhsSubst :: SimpC a -> Subst
rhsSubst             = rsu . crhs
  where
    rsu (PKVar _ su) = su
    rsu _            = errorstar "Eliminate.rhsSubst called on bad input"

getSubC :: SInfo a -> Integer -> SimpC a
getSubC si i = safeLookup msg i (cm si)
  where
    msg = "getSubC: " ++ show i
