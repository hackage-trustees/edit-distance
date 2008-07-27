{-# LANGUAGE PatternGuards, ScopedTypeVariables, BangPatterns #-}

module Text.EditDistance.STUArray (
        levenshteinDistance, restrictedDamerauLevenshteinDistance
    ) where

import Text.EditDistance.EditCosts

import Control.Monad
import Control.Monad.ST
import Data.Array.ST
import Data.Array.MArray


levenshteinDistance :: EditCosts -> String -> String -> Int
levenshteinDistance costs str1 str2 = runST (levenshteinDistanceST costs str1 str2)

levenshteinDistanceST :: EditCosts -> String -> String -> ST s Int
levenshteinDistanceST costs str1 str2 = do
    -- Create string arrays
    str1_array <- stringToArray str1
    str2_array <- stringToArray str2
    
    -- Create array of costs for a single row. Say we index costs by (i, j) where i is the column index and j the row index.
    -- Rows correspond to characters of str2 and columns to characters of str1. We can get away with just storing a single
    -- row of costs at a time, which is this one
    cost_row <- newArray_ (0, str1_len) :: ST s (STUArray s Int Int)
    
     -- Fill out the first row (j = 0)
    forM_ [1..str1_len] $ \i -> writeArray cost_row i (deletionCost costs * i)
    
    -- Fill out the remaining rows (j >= 1)
    forM_ [1..str2_len] $ levenshteinDistanceSTRowWorker costs str1_len str1_array str2_array cost_row
    
    -- Return an actual answer
    readArray cost_row str1_len
  where
    str1_len = length str1
    str2_len = length str2

levenshteinDistanceSTRowWorker :: EditCosts -> Int -> STUArray s Int Char -> STUArray s Int Char -> STUArray s Int Int -> Int -> ST s ()
levenshteinDistanceSTRowWorker !costs !str1_len !str1_array !str2_array !cost_row !j = do
    row_char <- readArray str2_array j
    
    -- Initialize the first element of the row (i = 0)
    here_up <- readArray cost_row 0
    let here = insertionCost costs * j
    writeArray cost_row 0 here
    
    -- Fill the remaining elements of the row (i >= 1)
    foldM (colWorker row_char) (here, here_up) [1..str1_len]
    
    return ()
  where
    colWorker row_char (!left, !left_up) !i = do
        col_char <- readArray str1_array i
        
        here_up <- readArray cost_row i
        let here = standardCosts costs row_char col_char left left_up here_up
        writeArray cost_row i here
        return (here, here_up)


restrictedDamerauLevenshteinDistance :: EditCosts -> String -> String -> Int
restrictedDamerauLevenshteinDistance costs str1 str2 = runST (restrictedDamerauLevenshteinDistanceST costs str1 str2)

restrictedDamerauLevenshteinDistanceST :: EditCosts -> String -> String -> ST s Int
restrictedDamerauLevenshteinDistanceST costs str1 str2 = do
    -- Create string arrays
    str1_array <- stringToArray str1
    str2_array <- stringToArray str2
    
    -- Create array of costs for a single row. Say we index costs by (i, j) where i is the column index and j the row index.
    -- Rows correspond to characters of str2 and columns to characters of str1. We can get away with just storing two
    -- rows of costs at a time, which are these two
    cost_row  <- newArray_ (0, str1_len) :: ST s (STUArray s Int Int)
    cost_row' <- newArray_ (0, str1_len) :: ST s (STUArray s Int Int)
    
    -- Fill out the first row (j = 0)
    forM_ [1..str1_len] $ \i -> writeArray cost_row i (deletionCost costs * i)
    
    if (str2_len == 0)
      then readArray cost_row str1_len
      else do
        -- Fill out the second row (j = 1)
        row_char <- readArray str2_array 1

        -- Initialize the first element of the row (i = 0)
        zero_up <- readArray cost_row 0
        let zero = insertionCost costs
        writeArray cost_row' 0 zero

        -- Fill the remaining elements of the row (i >= 1)
        foldM (firstRowColWorker str1_array row_char cost_row cost_row') (zero, zero_up) [1..str1_len]
        
        -- Fill out the remaining rows (j >= 2)
        (_, final_row, _) <- foldM (restrictedDamerauLevenshteinDistanceSTRowWorker costs str1_len str1_array str2_array) (cost_row, cost_row', row_char) [2..str2_len]
        
        -- Return an actual answer
        readArray final_row str1_len
  where
    str1_len = length str1
    str2_len = length str2
    
    firstRowColWorker !str1_array !row_char !cost_row !cost_row' (!left, !left_up) !i = do
        col_char <- readArray str1_array i
        
        here_up <- readArray cost_row i
        let here = standardCosts costs row_char col_char left left_up here_up
        writeArray cost_row' i here
        return (here, here_up)

restrictedDamerauLevenshteinDistanceSTRowWorker :: EditCosts -> Int -> STUArray s Int Char -> STUArray s Int Char -> (STUArray s Int Int, STUArray s Int Int, Char) -> Int -> ST s (STUArray s Int Int, STUArray s Int Int, Char)
restrictedDamerauLevenshteinDistanceSTRowWorker !costs !str1_len !str1_array !str2_array (!cost_row, !cost_row', !prev_row_char) !j = do
    row_char <- readArray str2_array j
    
    -- Initialize the first element of the row (i = 0)
    zero_up_up <- readArray cost_row  0
    zero_up    <- readArray cost_row' 0
    let zero = insertionCost costs * j
    writeArray cost_row 0 zero
    
    -- Initialize the second element of the row (i = 1)
    when (str1_len > 0) $ do
        col_char <- readArray str1_array 1
        one_up_up <- readArray cost_row  1
        one_up    <- readArray cost_row' 1
        let one = standardCosts costs row_char col_char zero zero_up one_up
        writeArray cost_row 1 one
        
        -- Fill the remaining elements of the row (i >= 2)
        foldM (colWorker row_char) (zero_up_up, one_up_up, one_up, one) [2..str1_len]
        return ()
    
    return (cost_row', cost_row, row_char)
  where
    colWorker row_char (!left_left_up_up, !left_up_up, !left_up, !left) !i = do
        prev_col_char <- readArray str1_array (i - 1)
        col_char <- readArray str1_array i
        
        here_up_up <- readArray cost_row  i
        here_up    <- readArray cost_row' i
        let here_standard_only = standardCosts costs row_char col_char left left_up here_up
            here = if prev_row_char == col_char && prev_col_char == row_char
                   then here_standard_only `min` (left_left_up_up + (transpositionCost costs))
                   else here_standard_only
        
        writeArray cost_row i here
        return (left_up_up, here_up_up, here_up, here)


{-# INLINE standardCosts #-}
standardCosts :: EditCosts -> Char -> Char -> Int -> Int -> Int -> Int
standardCosts !costs !row_char !col_char !cost_left !cost_left_up !cost_up = deletion_cost `min` insertion_cost `min` subst_cost
  where
    deletion_cost  = cost_left + deletionCost costs
    insertion_cost = cost_up + insertionCost costs
    subst_cost     = cost_left_up + if row_char == col_char then 0 else substitutionCost costs

stringToArray :: String -> ST s (STUArray s Int Char)
stringToArray str = do
    array <- newArray_ (1, length str)
    forM_ (zip [1..] str) (uncurry (writeArray array))
    return array

{-
showArray :: STUArray s (Int, Int) Int -> ST s String
showArray array = do
    ((il, jl), (iu, ju)) <- getBounds array
    flip (flip foldM "") [(i, j) | i <- [il..iu], j <- [jl.. ju]] $ \rest (i, j) -> do
        elt <- readArray array (i, j)
        return $ rest ++ show (i, j) ++ ": " ++ show elt ++ ", "
-}