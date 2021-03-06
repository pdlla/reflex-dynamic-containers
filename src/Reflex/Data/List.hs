-----------------------------------------------------------------------------
-- |
-- Copyright   :  (C) 2020 Peter Lu
-- License     :  see the file LICENSE
--
-- Maintainer  :  pdlla <chippermonky@gmail.com>
-- Stability   :  experimental
--
-- A dynamic list which are a set of input and output events that wrap an
-- internal 'Dynamic [a]'. Just like haskell lists, DynamicList is probably not
-- what you want. Perhaps you are looking for 'Reflex.Data.Sequence' or
-- 'Reflex.Data.Stack'?
----------------------------------------------------------------------------
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RecursiveDo     #-}

module Reflex.Data.List
  ( DynamicList(..)
  , DynamicListConfig(..)
  , defaultDynamicListConfig
  , holdDynamicList
  )
where

import           Relude

import           Reflex
import           Reflex.Potato.Helpers

import           Control.Monad.Fix

import           Data.List.Index

data DynamicList t a = DynamicList {
  -- TODO rename to added/removed
  _dynamicList_added      :: Event t (Int, a)
  , _dynamicList_removed  :: Event t a
  , _dynamicList_contents :: Dynamic t [a]
}

data DynamicListConfig t a = DynamicListConfig {
  -- | event to add an element at a given index
  _dynamicListConfig_add       :: Event t (Int, a)
  -- | event to remove an element at given index
  , _dynamicListConfig_remove  :: Event t Int
  -- | event to add an element to front of list
  , _dynamicListConfig_push    :: Event t a
  -- | event to remove an element from front of list
  , _dynamicListConfig_pop     :: Event t ()
  -- | event to add an element to back of list
  , _dynamicListConfig_enqueue :: Event t a
  -- | event to remove an element from back of list
  , _dynamicListConfig_dequeue :: Event t ()
}

-- this is available since relude 0.6.0.0 as !!?
-- but nix/cabal can't seem to download 0.6.0.0 so I just do this instead
infix 9 !!!?
(!!!?) :: [a] -> Int -> Maybe a
(!!!?) xs i | i < 0     = Nothing
            | otherwise = go i xs
 where
  go :: Int -> [a] -> Maybe a
  go 0 (x : _ ) = Just x
  go j (_ : ys) = go (j - 1) ys
  go _ []       = Nothing
{-# INLINE (!!!?) #-}


-- TODO switch to Data.Default
defaultDynamicListConfig :: (Reflex t) => DynamicListConfig t a
defaultDynamicListConfig = DynamicListConfig
  { _dynamicListConfig_add     = never
  , _dynamicListConfig_remove  = never
  , _dynamicListConfig_push    = never
  , _dynamicListConfig_pop     = never
  , _dynamicListConfig_enqueue = never
  , _dynamicListConfig_dequeue = never
  }


data LState a = LSInserted (Int, a) | LSRemoved a | LSNothing
data DLCmd t a = DLCAdd (Int, a) | DLCRemove Int

-- | create a dynamic list
holdDynamicList
  :: forall t m a
   . (Reflex t, MonadHold t m, MonadFix m)
  => [a] -- ^ initial value
  -> DynamicListConfig t a
  -> m (DynamicList t a)
holdDynamicList initial (DynamicListConfig {..}) = mdo
  let _dynamicListConfig_add'  = _dynamicListConfig_add
      _dynamicListConfig_push' = fmap (\x -> (0, x)) _dynamicListConfig_push
      _dynamicListConfig_pop'  = fmap (const 0) _dynamicListConfig_pop
      _dynamicListConfig_enqueue' =
        attach (fmap length (current dlc)) _dynamicListConfig_enqueue
      _dynamicListConfig_dequeue' =
        tag (fmap ((+ (-1)) . length) (current dlc)) _dynamicListConfig_dequeue

      dlAdd =
        leftmost
          $     DLCAdd
          <<$>> [ _dynamicListConfig_add'
                , _dynamicListConfig_push'
                , _dynamicListConfig_enqueue'
                ]
      dlRemove =
        leftmost
          $     DLCRemove
          <<$>> [ _dynamicListConfig_remove
                , _dynamicListConfig_pop'
                , _dynamicListConfig_dequeue'
                ]

      -- TODO change to leftmost
      -- ensure these events never fire simultaneously as the indexing may be off
      changeEvent :: Event t (DLCmd t a)
      changeEvent = leftmostwarn "List" [dlRemove, dlAdd]

      foldfn :: DLCmd t a -> (LState a, [a]) -> Maybe (LState a, [a])
      foldfn op (_, xs) =
        let
          -- this code is a little convoluted because there use to be a "move" command that I since removed
            add' (index, x) xs' = do
              guard $ index >= 0 && index <= length xs'
              return $ insertAt index x xs'
            add :: (Int, a) -> Maybe (LState a, [a])
            add (index, x) = do
              xs' <- add' (index, x) xs
              return $ (LSInserted (index, x), xs')
            remove' index = do
              x <- xs !!!? index
              return $ (x, deleteAt index xs)
            remove :: Int -> Maybe (LState a, [a])
            remove index = do
              (x, xs') <- remove' index
              return $ (LSRemoved x, xs')
        in  case op of
              DLCAdd    x -> add x
              DLCRemove x -> remove x

  dynInt :: Dynamic t (LState a, [a]) <- foldDynMaybe foldfn
                                                      (LSNothing, initial)
                                                      changeEvent

  let evInt = fmap fst (updated dynInt)

      evAddSelect c = case c of
        LSInserted x -> Just x
        _            -> Nothing
      evRemoveSelect c = case c of
        LSRemoved x -> Just x
        _           -> Nothing

      dlc = fmap snd dynInt

  return $ DynamicList { _dynamicList_added    = fmapMaybe evAddSelect evInt
                       , _dynamicList_removed  = fmapMaybe evRemoveSelect evInt
                       , _dynamicList_contents = dlc
                       }
