{-# LANGUAGE RankNTypes #-}

module Properties where

import Optimal

import Control.Monad
import Control.Monad.ST

import Data.List
import Data.Ord

import Data.Array.Vector

import Data.Array.Vector.Algorithms.Optimal (Comparison)
import Data.Array.Vector.Algorithms.Radix (radix, passes, size)
import Data.Array.Vector.Algorithms.Combinators

import qualified Data.Map as M

import Test.QuickCheck

import Util

prop_sorted :: (UA e, Ord e) => UArr e -> Property
prop_sorted arr | lengthU arr < 2 = property True
                | otherwise       = check (headU arr) (tailU arr)
 where
 check e arr | nullU arr = property True
             | otherwise = e <= headU arr .&. check (headU arr) (tailU arr)

prop_fullsort :: (UA e, Ord e)
              => (forall s. MUArr e s -> ST s ()) -> UArr e -> Property
prop_fullsort algo arr = prop_sorted $ apply algo arr

prop_schwartzian :: (UA e, UA k, Ord k)
                 => (e -> k)
                 -> (forall e s. (UA e) => (e -> e -> Ordering) -> MUArr e s -> ST s ())
                 -> UArr e -> Property
prop_schwartzian f algo arr
  | lengthU arr < 2 = property True
  | otherwise       = let srt = apply (algo `usingKeys` f) arr
                      in check (headU srt) (tailU srt)
 where
 check e arr | nullU arr = property True
             | otherwise = f e <= f (headU arr) .&. check (headU arr) (tailU arr)

longGen :: (UA e, Arbitrary e) => Int -> Gen (UArr e)
longGen k = liftM2 (\l r -> toU (l ++ r)) (vectorOf k arbitrary) arbitrary

sanity :: Int
sanity = 100

prop_partialsort :: (UA e, Ord e, Arbitrary e, Show e)
                 => (forall s. MUArr e s -> Int -> ST s ())
                 -> Positive Int -> Property
prop_partialsort = prop_sized $ \algo k ->
  prop_sorted . takeU k . apply algo

prop_select :: (UA e, Ord e, Arbitrary e, Show e)
            => (forall s. MUArr e s -> Int -> ST s ())
            -> Positive Int -> Property
prop_select = prop_sized $ \algo k arr ->
  let (l, r) = splitAtU k $ apply algo arr
  in allU (\e -> allU (e <=) r) l

prop_sized :: (UA e, Arbitrary e, Show e, Testable prop)
           => ((forall s. MUArr e s -> ST s ()) -> Int -> UArr e -> prop)
           -> (forall s. MUArr e s -> Int -> ST s ())
           -> Positive Int -> Property
prop_sized prop algo (Positive k) =
  let k' = k `mod` sanity
  in forAll (longGen k') $ prop (\marr -> algo marr k') k'

prop_stable :: (forall e s. (UA e) => Comparison e -> MUArr e s -> ST s ())
            -> UArr Int -> Property
-- prop_stable algo arr = property $ apply algo arr == arr
prop_stable algo arr = stable $ apply (algo (comparing fstS)) $ zipU arr ix
 where
 ix = toU [1 .. lengthU arr]

stable arr | nullU arr = property True
           | otherwise = let e :*: i = headU arr
                         in allU (\(e' :*: i') -> e < e' || i < i') (tailU arr)
                            .&. stable (tailU arr)

prop_stable_radix :: (forall e s. UA e => 
                                  Int -> Int -> (Int -> e -> Int) -> MUArr e s -> ST s ())
                  -> UArr Int -> Property
prop_stable_radix algo arr =
  stable . apply (algo (passes e) (size e) (\k (e :*: _) -> radix k e))
         $ zipU arr ix
 where
 ix = toU [1 .. lengthU arr]
 e = headU arr
 
prop_optimal :: Int
             -> (forall e s. (UA e) => Comparison e -> MUArr e s -> Int -> ST s ())
             -> Property
prop_optimal n algo = label "sorting" sortn .&. label "stability" stabn
 where
 arrn  = toU [0..n-1]
 sortn = all ( (== arrn)
             . apply (\a -> algo compare a 0)
             . toU)
         $ permutations [0..n-1]
 stabn = all ( (== arrn)
             . sndS
             . unzipU
             . apply (\a -> algo (comparing fstS) a 0))
         $ stability n

type Bag e = M.Map e Int

toBag :: (UA e, Ord e) => UArr e -> Bag e
toBag = M.fromListWith (+) . flip zip (repeat 1) . fromU

prop_permutation :: (UA e, Ord e)
                 => (forall s. MUArr e s -> ST s ())
                 -> UArr e -> Property
prop_permutation algo arr = property $ 
                            toBag arr == toBag (apply algo arr)

newtype SortedArr e = Sorted (UArr e)

instance (Show e, UA e) => Show (SortedArr e) where
  show (Sorted a) = show a

instance (Arbitrary e, UA e, Ord e) => Arbitrary (SortedArr e) where
  arbitrary = fmap (Sorted . toU . sort) $ liftM2 (++) (vectorOf 20 arbitrary) arbitrary

ixRanges :: (UA e) => UArr e -> Gen (Int, Int)
ixRanges arr = do i <- fmap (`mod` len) arbitrary
                  j <- fmap (`mod` len) arbitrary
                  return $ if i < j then (i, j) else (j, i)
 where len = lengthU arr

prop_search_inrange :: (UA e, Ord e)
                    => (forall s. MUArr e s -> e -> Int -> Int -> ST s Int)
                    -> SortedArr e -> e -> Property
prop_search_inrange algo (Sorted arr) e = forAll (ixRanges arr) $ \(i, j) ->
  let k = runST (newMU len >>= \marr -> copyMU marr 0 arr >> algo marr e i j)
  in property $ i <= k && k <= j
 where
 len = lengthU arr

prop_search_lowbound :: (UA e, Ord e)
                     => (forall s. MUArr e s -> e -> ST s Int)
                     -> SortedArr e -> e -> Property
prop_search_lowbound algo (Sorted arr) e = property $ (k == 0   || indexU arr (k-1) < e)
                                                   && (k == len || indexU arr k >= e)
 where
 len = lengthU arr
 k = runST (newMU len >>= \marr -> copyMU marr 0 arr >> algo marr e)