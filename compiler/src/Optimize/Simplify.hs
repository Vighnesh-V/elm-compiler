module Optimize.Simplify
  ( simplify
  )
  where

import AST.Display ()

import qualified AST.Optimized as Opt
import Control.Arrow (second)
import qualified Debug.Trace as Debug
import qualified Data.Name as Name
import qualified Data.Map as Map
import Data.Map.Strict ((!))
import qualified Data.Set as Set
import qualified Data.List as List

showSet :: Show a => Set.Set a -> String
showSet = ("{" ++) . (++ "}") . List.intercalate ", " . List.map show . Set.elems

showMap :: (Show k, Show v) => Map.Map k v -> String
showMap = ("{" ++) . (++ "}") . List.intercalate ", " . List.map (\(k, v) -> show k ++ ": " ++ show v) . Map.assocs

buildUses :: Map.Map Opt.Global Opt.Node -> Map.Map Opt.Global (Set.Set Opt.Global)
buildUses graph =
  let usesList = Map.map (const Set.empty) graph in
  Map.foldrWithKey (\caller node uses ->
    let callees = nodeDeps node in
    Set.foldr (Map.alter (Just . \mv ->
      case mv of
        Just v -> Set.insert caller v
        Nothing -> Set.singleton caller
    )) uses callees
  ) usesList graph

mapNode :: (Opt.Expr -> Opt.Expr) -> Opt.Node -> Opt.Node
mapNode f (Opt.Define e set) = Opt.Define (f e) set
mapNode f (Opt.DefineTailFunc names e set) = Opt.DefineTailFunc names (f e) set
mapNode f (Opt.Cycle names l defs set) =
  Opt.Cycle names l' defs set
  where l' = map (\(n, e) -> (n, f e)) l
mapNode f (Opt.PortIncoming e set) = Opt.PortIncoming (f e) set
mapNode f (Opt.PortOutgoing e set) = Opt.PortOutgoing (f e) set
mapNode f n = n

mapExprInDef :: (Opt.Expr -> Opt.Expr) -> Opt.Def -> Opt.Def
mapExprInDef f (Opt.Def name e) = Opt.Def name (f e)
mapExprInDef f (Opt.TailDef name names e) = Opt.TailDef name names (f e)

mapExprInChoice :: (Opt.Expr -> Opt.Expr) -> Opt.Choice -> Opt.Choice
mapExprInChoice f (Opt.Inline e) = Opt.Inline (f e)
mapExprInChoice _ (Opt.Jump i) = Opt.Jump i

instance Functor Opt.Decider where
  fmap f (Opt.Leaf a) = Opt.Leaf (f a)
  fmap f (Opt.Chain testChain success failure) = Opt.Chain testChain (fmap f success) (fmap f failure)
  fmap f (Opt.FanOut path tests fallback) = Opt.FanOut path (List.map (second (fmap f)) tests) (fmap f fallback)

mapBoth :: (a -> b) -> (a, a) -> (b, b)
mapBoth f (x, y) = (f x, f y)

mapGlobalVarInExpr :: Opt.Global -> Opt.Expr -> Opt.Expr -> Opt.Expr
mapGlobalVarInExpr var replacement = go
  where
    go (Opt.VarGlobal v) | v == var = replacement
    go (Opt.List es) = Opt.List (List.map go es)
    -- TODO is it always good to inline within function bodies?
    go (Opt.Function args body) = Opt.Function args (go body)
    go (Opt.Call e es) = Opt.Call (go e) (List.map go es)
    go (Opt.TailCall name args) = Opt.TailCall name (List.map (second go) args)
    go (Opt.If cases defaultCase) = Opt.If (List.map (mapBoth go) cases) (go defaultCase)
    -- TODO here's where we might do local inlining?
    go (Opt.Let def e) = Opt.Let (mapExprInDef go def) (go e)
    go (Opt.Destruct destructor e) = Opt.Destruct destructor (go e)
    go (Opt.Case name1 name2 decider cases) =
      Opt.Case name1 name2 (fmap (mapExprInChoice go) decider) (List.map (second go) cases)
    go (Opt.Access e name) = Opt.Access (go e) name
    go (Opt.Update e fields) = Opt.Update (go e) (Map.map go fields)
    go (Opt.Record fields) = Opt.Record (Map.map go fields)
    go (Opt.Tuple e1 e2 e3) = Opt.Tuple (go e1) (go e2) (fmap go e3)
    go e = e

inlineHelp :: Opt.Global -> Map.Map Opt.Global Opt.Node -> Map.Map Opt.Global (Set.Set Opt.Global) -> Opt.Global -> Opt.Node -> Opt.Node
inlineHelp name deps uses d@(Opt.Global _ dLocalName) node
  | (uses ! d) == Set.singleton name =
      case nodeExpr (deps ! d) of
        Just replacement -> mapNode (mapGlobalVarInExpr d replacement) node
        Nothing -> node
  | otherwise = node

nodeExpr :: Opt.Node -> Maybe Opt.Expr
nodeExpr (Opt.Define e _) = Just e
nodeExpr (Opt.DefineTailFunc _ e _) = Just e
-- nodeExpr (Opt.Cycle _ _ defs _) = Just
nodeExpr (Opt.PortIncoming e _) = Just e
nodeExpr (Opt.PortOutgoing e _) = Just e
nodeExpr _ = Nothing

countKeys :: Map.Map a Int -> Set.Set a
countKeys = Map.keysSet . Map.filter (> 0)

nodeDeps :: Opt.Node -> Set.Set Opt.Global
nodeDeps (Opt.Define _ ds) = countKeys ds
nodeDeps (Opt.DefineTailFunc _ _ ds) = countKeys ds
nodeDeps (Opt.Cycle _ _ _ ds) = countKeys ds
nodeDeps _ = Set.empty

nodeNames :: Opt.Node -> [Name.Name]
nodeNames (Opt.DefineTailFunc names _ _) = names
nodeNames (Opt.Cycle names _ _ _) = names
nodeNames _ = []


-- deps :: Map Global Node ~ Map Global Expr + Map Global Dependencies
-- some Node contain Set Globals

simplify :: Opt.GlobalGraph -> Opt.GlobalGraph
simplify (Opt.GlobalGraph deps fields) =
  -- Debug.trace (showMap deps) $
  Debug.trace (showMap fields) $
  Opt.GlobalGraph (Map.foldrWithKey aux Map.empty deps) fields
  where
    uses = buildUses deps
    aux name node graph =
      let ds = nodeDeps node in
      let node' = Set.foldr (inlineHelp name deps uses) node ds in
      Map.insert name node' graph
