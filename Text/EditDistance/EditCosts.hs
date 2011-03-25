{-# OPTIONS_GHC -funbox-strict-fields #-}

module Text.EditDistance.EditCosts where

data EditCosts = EditCosts {
    deletionCost :: !Int,
    insertionCost :: !Int,
    substitutionCost :: !(Either Int (Char -> Char -> Int)),
    transpositionCost :: !Int
  }

instance Eq EditCosts where
  (==) a@EditCosts{substitutionCost = Left as} b@EditCosts{substitutionCost = Left bs} = 
    (as == bs) && 
    (deletionCost a == deletionCost b) && 
    (insertionCost a == insertionCost b) &&
    (transpositionCost a == transpositionCost b)  
  (==) _ _  = False

defaultEditCosts :: EditCosts
defaultEditCosts = EditCosts {
    deletionCost = 1,
    insertionCost = 1,
    substitutionCost = Left 1,
    transpositionCost = 1
}