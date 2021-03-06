-- |
-- random helper methods, nothing to see here
-- the only reason this is exposed is so I can use this in tests
-- if you find any of these useful and want more please see the same file in https://github.com/pdlla/potato-flow
{-# LANGUAGE RecursiveDo #-}

module Reflex.Potato.Helpers
  ( leftmostwarn
  , fanDSum
  , foldDynMergeWith
  , getLeft
  , getRight
  , getHere
  , getThere
  )
where

import           Relude

import           Reflex

import           Control.Monad.Fix

import qualified Data.Dependent.Map as DM
import qualified Data.Dependent.Sum as DS
import           Data.Wedge



-- | same as leftmost but outputs a warning if more than one event fires at once
leftmostwarn :: (Reflex t) => String -> [Event t a] -> Event t a
leftmostwarn label evs = r where
  combine = mergeList evs
  nowarn =
    fmapMaybe (\x -> if length x == 1 then Just (head x) else Nothing) combine
  warn =
    traceEventWith
        (const ("WARNING: multiple " <> label <> " events triggered"))
      $ fmapMaybe (\x -> if length x > 1 then Just (head x) else Nothing)
                  combine
  r = leftmost [nowarn, warn]


fanDSum
  :: forall t k
   . (Reflex t, DM.GCompare k)
  => Event t (DS.DSum k Identity)
  -> EventSelector t k
fanDSum ds = fan $ DM.fromAscList . (: []) <$> ds


foldDynMergeWith
  :: (Reflex t, MonadHold t m, MonadFix m)
  => b -- ^ initial value of dynamic
  -> [Event t (b -> b)]  -- ^ list of events producing a reducing method
  -> m (Dynamic t b)  -- ^ final output after all folding methods applied
foldDynMergeWith acc = foldDyn ($) acc . mergeWith (.)




getLeft :: Either a b -> Maybe a
getLeft (Left x) = Just x
getLeft _        = Nothing

getRight :: Either a b -> Maybe b
getRight (Right x) = Just x
getRight _         = Nothing


-- my additions
getHere :: Wedge a b -> Maybe a
getHere c = case c of
  Here x -> Just x
  _      -> Nothing

getThere :: Wedge a b -> Maybe b
getThere c = case c of
  There x -> Just x
  _       -> Nothing
