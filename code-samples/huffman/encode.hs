{-# LANGUAGE TupleSections #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

-- General imports
import Control.Applicative              ((<$>))
import Control.Monad.IO.Class
import Control.Monad.Trans.State.Strict
import Data.Foldable                    (sum, forM_)
import Data.Map.Strict                  (Map, (!))
import Lens.Family2                     (view)
import Prelude hiding                   (sum)
import System.Environment               (getArgs)
import System.IO
import qualified Data.Map.Strict        as M

-- Pipes imports
import Pipes
import Pipes.ByteString                  hiding (ByteString)
import Pipes.Parse
import qualified Pipes.Prelude                  as PP

-- Working with Binary
import Data.Binary hiding             (encodeFile)
import Data.Bits                      (setBit)
import Data.ByteString                (ByteString)
import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as BL

-- Huffman imports
import Huffman
import PQueue
import PreTree

main :: IO ()
main = do
    args     <- getArgs
    let (inp,out)  = case args of
                       i:o:_      -> (i,o)
                       _          -> error "Give input and output files."

    metadata <- analyzeFile inp
    let (len,tree) = case metadata of
                       Just (l,t) -> (l,t)
                       _          -> error "Empty file."

    encodeFile inp out len tree

-- returns the file length and the huffman encoding tree
analyzeFile :: FilePath -> IO (Maybe (Int, PreTree Word8))
analyzeFile fp = withFile fp ReadMode $ \hIn -> do
    fqs <- freqs (fromHandle hIn >-> bsToBytes)
    let len  = sum fqs
        tree = evalState (listQueueStateTable fqs >> buildTree) emptyPQ
    return $ fmap (len,) tree
  where
    freqs :: (Monad m, Ord a) => Producer a m () -> m (M.Map a Int)
    freqs = PP.fold (\m x -> M.insertWith (+) x 1 m) M.empty id


encodeFile :: FilePath -> FilePath -> Int -> PreTree Word8 -> IO ()
encodeFile inp out len tree =
    withFile inp ReadMode $ \hIn ->
    withFile out WriteMode $ \hOut -> do
      BL.hPut hOut $ encode len
      BL.hPut hOut $ encode tree
      let fileBs    = fromHandle hIn
          dirStream = fileBs
                  >-> bsToBytes
                  >-> encodeByte enctable
      runEffect $ view pack (dirsBytes dirStream)
              >-> toHandle hOut
  where
    enctable = ptTable tree

-- Transforms a stream of bytes into a stream of directions that encode
-- every byte.
encodeByte :: (Ord a, Monad m) => Map a Encoding -> Pipe a Direction m r
encodeByte enctable = PP.mapFoldable (enctable !)

-- Transform a Direction producer into a byte/Word8 producer.  Pads the
-- last byte with zeroes if the direction stream runs out mid-byte.
dirsBytes :: (MonadIO m, Functor m) => Producer Direction m r -> Producer Word8 m ()
dirsBytes p = do
    (res,lo) <- lift $ runStateT dirsBytesP p
    forM_ res $ \byte -> do
      yield byte
      dirsBytes lo

-- Parser that turns a stream of directions into a stream of bytes, by
-- condensing eight directions into one byte.  If the direction stream
-- stops mid-byte, pad it with zero's.  If direction stream is already
-- exhausted, return Nothing.
--
dirsBytesP :: (Monad m, Functor m) => Parser Direction m (Maybe Word8)
dirsBytesP = do
    isEnd <- isEndOfInput
    if isEnd
      then return Nothing
      else Just <$> go 0 0
  where
    go :: Monad m => Word8 -> Int -> Parser Direction m Word8
    go b 8 = return b
    go b i = do
      dir <- draw
      case dir of
        Just DLeft  -> go     b            (i + 1)
        Just DRight -> go     (setBit b i) (i + 1)
        Nothing     -> return b



-- Receive ByteStrings from upstream and send its Word8 components
-- downstream
bsToBytes :: Monad m => Pipe ByteString Word8 m r
bsToBytes = PP.mapFoldable B.unpack