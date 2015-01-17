module Main where

import Options.Applicative hiding (action)
import Options.Applicative.Help.Pretty
import B9

main :: IO ()
main = do
  b9Opts <- parseCommandLine
  result <- runB9 b9Opts
  exit result
  where
    exit success = when (not success) (exitWith (ExitFailure 128))

parseCommandLine :: IO B9Options
parseCommandLine =
  execParser (info (helper <*> (B9Options <$> globals <*> cmds <*> buildVars))
               (fullDesc
                <> progDesc "Build and run VM-Images inside LXC containers.\
                            \ Custom arguments follow after '--' and are\
                            \ accessable in many strings in project configs \
                            \ trough shell like variable references, i.e. \
                            \'${arg_N}' referes to positional argument $N.\n\
                            \\n\
                            \Repository names passed to the command line are\
                            \ looked up in the B9 configuration file, which is\
                            \ on Un*x like system per default located in: \
                            \ '~/.b9/b9.config'"
                <> headerDoc (Just helpHeader)))
  where
    helpHeader = linebreak <> text "B9 - a benign VM-Image build tool"

data B9Options = B9Options GlobalOpts
                           BuildAction
                           BuildVariables

data GlobalOpts = GlobalOpts { configFile :: Maybe SystemPath
                             , cliB9Config :: B9Config  }

type BuildAction = Maybe SystemPath -> ConfigParser -> B9Config -> IO Bool

runB9 :: B9Options -> IO Bool
runB9 (B9Options globalOpts action vars) = do
  let cfgWithArgs = cfgCli { envVars = envVars cfgCli ++ vars }
      cfgCli = cliB9Config globalOpts
      cfgFile = configFile globalOpts
  cp <- configure cfgFile cfgCli
  action cfgFile cp cfgWithArgs

runBuild :: [FilePath] -> BuildAction
runBuild projectFiles _cfgFile cp conf = do
  prjs <- mapM consult projectFiles
  buildProject (mconcat prjs) cp conf

runPrint :: [FilePath] -> BuildAction
runPrint projectFiles _cfgFile  cp conf = do
  prjs <- mapM consult projectFiles
  printProject (mconcat prjs) cp conf

runPush :: SharedImageName -> BuildAction
runPush name _cfgFile cp conf = impl
  where
    conf' = conf { keepTempDirs = False }
    impl = run "push" cp conf'
               (if not (isJust (repository conf'))
                   then do
                     errorL "No repository specified! \
                            \ Use '-r' to specify a repo BEFORE 'push'."
                     return False
                   else do
                     pushSharedImageLatestVersion name
                     return True)

runPull :: Maybe SharedImageName -> BuildAction
runPull mName _cfgFile cp conf =
  run "pull" cp conf' (pullRemoteRepos >> maybePullImage)
  where
    conf' = conf { keepTempDirs = False }
    maybePullImage = maybe (return True) pullLatestImage mName

runListSharedImages :: BuildAction
runListSharedImages _cfgFile cp conf = impl
  where
    conf' = conf { keepTempDirs = False }
    impl = do
      imgs <- run "list" cp conf' getSharedImages
      if null imgs
        then putStrLn "\n\nNO SHAREABLE IMAGES\n"
        else putStrLn "SHAREABLE IMAGES:"
      mapM_ (putStrLn . ppShow) imgs
      return True

runAddRepo :: RemoteRepo -> BuildAction
runAddRepo repo cfgFile cp _conf = do
  repo' <- remoteRepoCheckSshPrivKey repo
  case writeRemoteRepoConfig repo' cp of
     Left er ->
       error (printf "Failed to add remote repo '%s'\
                     \ to b9 configuration. The \
                     \error was: \"%s\"."
                     (show repo) (show er))

     Right cpWithRepo ->
       writeB9Config cfgFile cpWithRepo
  return True

globals :: Parser GlobalOpts
globals = toGlobalOpts
               <$> optional (strOption
                             (help "Path to users b9-configuration"
                             <> short 'c'
                             <> long "configuration-file"
                             <> metavar "FILENAME"))
               <*> switch (help "Log everything that happens to stdout"
                          <> short 'v'
                          <> long "verbose")
               <*> switch (help "Suppress non-error output"
                          <> short 'q'
                          <> long "quiet")
               <*> optional (strOption
                             (help "Path to a logfile"
                             <> short 'l'
                             <> long "log-file"
                             <> metavar "FILENAME"))
               <*> optional (strOption
                             (help "Output file for a command/timing profile"
                             <> long "profile-file"
                             <> metavar "FILENAME"))
               <*> optional (strOption
                             (help "Root directory for build directories"
                             <> short 'b'
                             <> long "build-root-dir"
                             <> metavar "DIRECTORY"))
               <*> switch (help "Keep build directories after exit"
                             <> short 'k'
                             <> long "keep-build-dir")
               <*> switch (help "Predictable build directory names"
                             <> short 'u'
                             <> long "predictable-build-dir")
               <*> optional (strOption
                             (help "Cache directory for shared images, default: '~/.b9/repo-cache'"
                             <> long "repo-cache"
                             <> metavar "DIRECTORY"))
               <*> optional (strOption
                             (help "Remote repository to share image to"
                              <> short 'r'
                              <> long "repo"
                              <> metavar "REPOSITORY_ID"))

  where
    toGlobalOpts ::  Maybe FilePath
              -> Bool
              -> Bool
              -> Maybe FilePath
              -> Maybe FilePath
              -> Maybe FilePath
              -> Bool
              -> Bool
              -> Maybe FilePath
              -> Maybe String
              -> GlobalOpts
    toGlobalOpts cfg verbose quiet logF profF buildRoot keep notUnique
                 mRepoCache repo =
      let minLogLevel = if verbose then Just LogTrace else
                          if quiet then Just LogError else Nothing
          b9cfg' = let b9cfg = mempty { verbosity = minLogLevel
                                      , logFile = logF
                                      , profileFile = profF
                                      , buildDirRoot = buildRoot
                                      , keepTempDirs = keep
                                      , uniqueBuildDirs = not notUnique
                                      , repository = repo
                                      }
                   in case mRepoCache of
                        Nothing -> b9cfg
                        Just repoCache ->
                          let rc = Path repoCache
                          in b9cfg { repositoryCache = rc }
      in GlobalOpts { configFile = (Path <$> cfg) <|> pure defaultB9ConfigFile
                    , cliB9Config = b9cfg' }

cmds :: Parser BuildAction
cmds = subparser (  command "build"
                             (info (runBuild <$> projectsParser)
                                   (progDesc "Merge all project files and\
                                             \ build."))
                  <> command "push"
                             (info (runPush <$> sharedImageNameParser)
                                   (progDesc "Push the lastest shared image\
                                             \ from cache to the selected \
                                             \ remote repository."))
                  <> command "pull"
                             (info (runPull <$> optional sharedImageNameParser)
                                   (progDesc "Either pull shared image meta\
                                             \ data from all repositories,\
                                             \ or only from just a selected one.\
                                             \ If additionally the name of a\
                                             \ shared images was specified,\
                                             \ pull the newest version\
                                             \ from either the selected repo,\
                                             \ or from the repo with the most\
                                             \ recent version."))
                  <> command "print"
                             (info (runPrint <$> projectsParser)
                                   (progDesc "Show the final project that\
                                             \ would be used by the 'build' \
                                             \ command."))
                  <> command "list"
                             (info (pure runListSharedImages)
                                   (progDesc "List shared images."))
                  <> command "add-repo"
                             (info (runAddRepo <$> remoteRepoParser)
                                   (progDesc "Add a remote repo.")))

projectsParser :: Parser [FilePath]
projectsParser = helper <*>
   some (strOption
          (help "Project file to load, specify multiple project\
                \ files to merge them into a single project."
          <> short 'f'
          <> long "project-file"
          <> metavar "FILENAME"
          <> noArgError (ErrorMsg "No project file specified!")))

buildVars :: Parser BuildVariables
buildVars = zip (("arg_"++) . show <$> ([1..] :: [Int]))
            <$> many (strArgument idm)


remoteRepoParser :: Parser RemoteRepo
remoteRepoParser =
  helper <*>
  (RemoteRepo <$> strArgument (help "The name of the remmote repository."
                              <> metavar "NAME")
              <*> strArgument (help "The (remote) repository root path."
                              <> metavar "REMOTE_DIRECTORY")
              <*> (SshPrivKey
                   <$> strArgument (help "Path to the SSH private\
                                         \ key file used for \
                                         \ authorization."
                                   <> metavar "SSH_PRIV_KEY_FILE"))
              <*> (SshRemoteHost
                   <$> ((,)
                        <$> strArgument (help "Repo hostname or IP"
                                        <> metavar "HOST")
                        <*> argument auto (help "SSH-Port number"
                                     <> value 22
                                     <> showDefault
                                     <> metavar "PORT")))
              <*> (SshRemoteUser <$> strArgument (help "SSH-User to login"
                                                 <> metavar "USER")))

sharedImageNameParser :: Parser SharedImageName
sharedImageNameParser =
  helper <*>
  (SharedImageName <$> strArgument
                         (help "Shared image name"
                         <> metavar "NAME"))
