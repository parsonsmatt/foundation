{-# LANGUAGE CPP #-}
module Foundation.Time.StopWatch
    ( StopWatchPrecise
    , startPrecise
    , stopPrecise
    ) where

import Foundation.Primitive.Imports
import Foundation.Primitive.Types.OffsetSize
import Foundation.Primitive.Types.Ptr
import Foundation.System.Bindings.Time
import Foundation.Time.Types
import Foundation.Primitive.Block.Mutable
import Foundation.Numerical
import Foreign.Storable

#if defined(mingw32_HOST_OS)
import System.Win32.Time
import Foundation.Primitive.Monad
#elif defined(__APPLE__)
import Foundation.System.Bindings.Macos
#else
import Foundation.Primitive.Monad
#endif

-- | A precise stop watch
--
-- The precision is higher than a normal stopwatch, but
-- also on some system it might not be able to record
-- longer period of time accurately (possibly wrapping)
newtype StopWatchPrecise =
#if defined(__APPLE__)
    StopWatchPrecise Word64
#elif defined(mingw32_HOST_OS)
    -- contain 2 LARGE_INTEGER (int64_t)
    StopWatchPrecise (MutableBlock Word8 (PrimState IO))
#else
    -- contains 2 timespec (16 bytes)
    StopWatchPrecise (MutableBlock Word8 (PrimState IO))
#endif

-- | Create a new precise stop watch
--
-- record the time at start of call
startPrecise :: IO StopWatchPrecise
startPrecise = do
#if defined(mingw32_HOST_OS)
    blk <- newPinned 16
    p   <- mutableGetAddr blk
    c_QueryPerformanceCounter (castPtr p `ptrPlus` 8)
    pure (StopWatchPrecise blk)
#elif defined(__APPLE__)
    StopWatchPrecise <$> sysMacos_absolute_time
#else
    blk <- newPinned (sizeOfCSize (size_CTimeSpec + size_CTimeSpec))
    p   <- mutableGetAddr blk
    _err1 <- sysTimeClockGetTime sysTime_CLOCK_MONOTONIC (castPtr p `ptrPlusCSz` size_CTimeSpec)
    pure (StopWatchPrecise blk)
#endif

-- | Get the number of nano seconds since the call to `startPrecise`
stopPrecise :: StopWatchPrecise -> IO NanoSeconds
stopPrecise (StopWatchPrecise blk) = do
#if defined(mingw32_HOST_OS)
    p <- mutableGetAddr blk
    c_QueryPerformanceCounter (castPtr p)
    let p64 = castPtr p :: Ptr Word64
    end   <- peek p64
    start <- peek (p64 `ptrPlus` 8)
    freq  <- queryPerformanceFrequency
    pure (NanoSeconds ((end - start) * freq))
#elif defined(__APPLE__)
    end <- sysMacos_absolute_time
    (numer,denom) <- do
            mti <- newPinned (sizeOfCSize size_MachTimebaseInfo)
            p <- mutableGetAddr mti
            n <- peek (castPtr (mti `ptrPlus` ofs_MachTimebaseInfo_numer))
            d <- peek (castPtr (mti `ptrPlus` ofs_MachTimebaseInfo_denom))
            pure (n, d)
    pure (NanoSeconds (((end - start) * numer) `div` denom))
#else
    p <- mutableGetAddr blk
    _err1 <- sysTimeClockGetTime sysTime_CLOCK_MONOTONIC (castPtr p)
    let p64 = castPtr p :: Ptr Word64
    endSec    <- peek p64
    startSec  <- peek (p64 `ptrPlusCSz` size_CTimeSpec)
    endNSec   <- peek (p64 `ptrPlus` ofs_CTimeSpec_NanoSeconds)
    startNSec <- peek (p64 `ptrPlus` (sizeAsOffset (sizeOfCSize size_CTimeSpec) + ofs_CTimeSpec_NanoSeconds))
    pure $ NanoSeconds $ (endSec * 1000000000 + endNSec) - (startSec * 1000000000 + startNSec)
#endif