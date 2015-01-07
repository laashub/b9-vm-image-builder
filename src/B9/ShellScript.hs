module B9.ShellScript ( writeSh
                      , CmdVerbosity (..)
                      , Cwd (..)
                      , User (..)
                      , Script (..)
                      ) where

import Control.Monad.Reader
import Control.Applicative ( (<$>), (<*>) )
import Data.List ( intercalate )
import System.Directory ( getTemporaryDirectory
                        , getPermissions
                        , setPermissions
                        , setOwnerExecutable
                        , createDirectoryIfMissing )
import System.IO ( writeFile )

data Script = In FilePath [Script]
            | As String [Script]
            | IgnoreErrors Bool [Script]
            | Verbosity CmdVerbosity [Script]
            | Begin [Script]
            | Run FilePath [String]

data Ctx = Ctx { ctxCwd :: Cwd
               , ctxUser :: User
               , ctxIgnoreErrors :: Bool
               , ctxVerbosity :: CmdVerbosity }

toCmds :: Script -> [Cmd]
toCmds s = runReader (toLLC s) (Ctx NoCwd NoUser False Debug)
  where
    toLLC :: Script -> Reader Ctx [Cmd]
    toLLC (In d cs) = local (\ ctx -> ctx { ctxCwd = (Cwd d) })
                      (toLLC (Begin cs))
    toLLC (As u cs) = local (\ ctx -> ctx { ctxUser = (User u) })
                      (toLLC (Begin cs))
    toLLC (IgnoreErrors b cs) = local (\ ctx -> ctx { ctxIgnoreErrors = b })
                                (toLLC (Begin cs))
    toLLC (Verbosity v cs) = local (\ ctx -> ctx { ctxVerbosity = v})
                             (toLLC (Begin cs))
    toLLC (Begin cs) = concat <$> mapM toLLC cs
    toLLC (Run cmd args) = do
      c <- reader ctxCwd
      u <- reader ctxUser
      i <- reader ctxIgnoreErrors
      v <- reader ctxVerbosity
      return [Cmd cmd args u c i v]


data Cmd = Cmd { cmdPath :: String
               , cmdArgs :: [String]
               , cmdUser :: User
               , cmdCwd :: Cwd
               , cmdErrorChecking :: Bool
               , cmdVerbosity :: CmdVerbosity
               }
data CmdVerbosity = Debug | Verbose | OnlyStdErr | Quiet deriving Show
data Cwd = Cwd FilePath | NoCwd
data User = User String | NoUser

writeSh :: FilePath -> Script -> IO ()
writeSh file script = do
  writeFile file (toBash $ toCmds script)
  getPermissions file >>= setPermissions file . setOwnerExecutable True

toBash :: [Cmd] -> String
toBash cmds =
  intercalate "\n\n" $
  bashHeader ++ (cmdToBash <$> cmds)

bashHeader = [ "#!/bin/bash"
             , "set -e" ]

cmdToBash :: Cmd -> String
cmdToBash c@(Cmd cmd args user cwd ignoreErrors verbosity) =
  intercalate "\n" $ disableErrorChecking
                     ++ pushd cwdQ
                     ++ execCmd
                     ++ popd cwdQ
                     ++ reenableErrorChecking
  where
    execCmd = [ unwords (runuser ++ [cmd] ++ args ++ redirectOutput) ]
      where runuser = case user of
              NoUser -> []
              User "root" -> []
              User u -> ["runuser", "-p", "-u", u]
    pushd NoCwd = [ ]
    pushd (Cwd cwdPath) = [ unwords (["pushd", cwdPath] ++ redirectOutput) ]
    popd NoCwd = [ ]
    popd (Cwd cwdPath) = [ unwords (["popd"] ++ redirectOutput ++ ["#", cwdPath]) ]
    disableErrorChecking = ["set +e" | ignoreErrors]
    reenableErrorChecking = ["set -e" | ignoreErrors]
    cwdQ = case cwd of
      NoCwd -> NoCwd
      Cwd d -> Cwd ("'" ++ d ++ "'")
    redirectOutput = case verbosity of
      Debug -> []
      Verbose -> []
      OnlyStdErr -> [">", "/dev/null"]
      Quiet -> ["&>", "/dev/null"]
