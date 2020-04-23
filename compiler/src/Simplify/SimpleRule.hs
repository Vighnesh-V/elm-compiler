module Simplify.SimpleRule (SimpleRule(..), simpleRules) where

import AST.Optimized
import qualified Data.Name as Name
import Data.Name (Name)
import qualified Elm.ModuleName as ModuleName
import qualified Elm.Package as Pkg

data SimpleRule = SimpleRule { func :: Global
                             , replace :: [Expr] -> Maybe Expr
                             }

global :: Pkg.Name -> String -> String -> Global
global pkg _module funcName =
  Global
  (ModuleName.Canonical pkg (Name.fromChars _module))
  (Name.fromChars funcName)

revFxn = global Pkg.core "List" "reverse"
andBop = global Pkg.core "Basics" "and"
mapFxn = global Pkg.core "List" "map"
foldFxn = global Pkg.core "List" "fold"

reverseLiteral :: SimpleRule
reverseLiteral = SimpleRule revFxn rewrite
  where
    rewrite [List l] = Just $ List (reverse l)
    rewrite _ = Nothing

applyAnd :: SimpleRule
applyAnd = SimpleRule andBop rewrite
  where
    rewrite [Bool b1, Bool b2] = Just $ Bool (b1 && b2)
    rewrite [Bool False, expr] = Just $ Bool False
    rewrite [expr, Bool False] = Just $ Bool False
    rewrite [Bool True, expr] = Just $ expr
    rewrite [expr, Bool True] = Just $ expr
    rewrite _ = Nothing

functionComposition :: SimpleRule
functionComposition = SimpleRule mapFxn rewrite 
  where
    rewrite [Function args body, Call ]

simpleRules = [reverseLiteral, applyAnd]
