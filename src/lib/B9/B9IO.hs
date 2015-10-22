-- | A /pure/ abstraction off the IO related actions done in B9. This is useful
-- to enable unit testing, OS-independence and debugging.

{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE DeriveFunctor #-}
module B9.B9IO where

import Control.Monad.Free
import Control.Monad.Trans.Writer.Lazy
import System.FilePath

-- | Programs representing imperative, /impure/ IO actions required by B9 to
-- create, convert and install VM images or cloud init disks.  Pure 'Action's
-- are combined to a free monad. This seperation from actually doing the IO and
-- modelling the IO actions as pure data enables unit testing and debugging.
type IoProgram = Free Action

-- | Execute an 'IoProgram' using a monadic interpretation function.
run :: Monad m => (forall a. Action a -> m a) -> IoProgram b -> m b
run = foldFree

-- | Pure commands for disk image creation and conversion, lxc interaction, file
-- IO and libvirt lxc interaction.
data Action next
    = LogTrace String
               next
    | GetBuildDir (FilePath -> next)
    | GetBuildId (String -> next)
    | MkTemp FilePath (FilePath -> next)
    deriving (Functor)

-- | Log a string, but only when trace logging is enabled, e.g. when
-- debugging
logTrace :: String -> IoProgram ()
logTrace str = liftF $ LogTrace str ()

-- | Get the (temporary) directory of the current b9 execution
getBuildDir :: IoProgram FilePath
getBuildDir = liftF $ GetBuildDir id

-- | Get a arbitrary random number selected when B9 starts, that serves as
-- unique id.
getBuildId :: IoProgram String
getBuildId = liftF $ GetBuildId id

-- | Create a unique file path inside the build directory starting with a given
-- prefix and ending with a unique random token.
mkTemp :: FilePath -> IoProgram FilePath
mkTemp prefix = liftF $ MkTemp prefix id

-- | Testing support
dumpToStrings :: IoProgram a -> [String]
dumpToStrings = snd . runPureDump

dumpToResult :: IoProgram a -> a
dumpToResult = fst . runPureDump

runPureDump :: IoProgram a -> (a, [String])
runPureDump p = runWriter (run dump p)
  where
    dump :: Action a -> Writer [String] a
    dump (LogTrace s n) = do
        tell ["logTrace " ++ s]
        return n
    dump (GetBuildDir n) = do
        tell ["getBuildDir"]
        return (n "/BUILD")
    dump (GetBuildId n) = do
        tell ["getBuildId"]
        return (n "build-id-1234")
    dump (MkTemp prefix n) = do
        tell ["mkTemp " ++ prefix]
        return (n ("/BUILD" </> prefix <.> "-XXXX"))