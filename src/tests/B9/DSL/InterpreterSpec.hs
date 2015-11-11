module B9.DSL.InterpreterSpec (spec) where
import B9 hiding (CloudInit)
import B9.B9IO
import B9.DSL
import B9.DSL.Interpreter
import B9.FileSystems
import B9.SpecExtra
import Control.Lens hiding (from, use)
import Test.Hspec
import Test.QuickCheck (property)

spec :: Spec
spec = do
    describe "compile (General)" $
        do it "traces documentation" $
               (doc "test") `shouldDoIo` (logTrace "test")
    fileInclusionSpec
    fsImgSpec
    candySpec
    localDirSpec
    cloudInitIsoImageSpec
    cloudInitMultiVfatImageSpec
    cloudInitDirSpec
    cloudInitWithContentSpec
    vmImageCreationSpec
    partitionedDiskSpec
    sharedImageSpec
    updateServerImageSpec
    containerExecutionSpec

-- * Examples for 'ReadOnlyFile' artifacts

fileInclusionSpec :: Spec
fileInclusionSpec =
    describe "FreeFile" $
    do it "has no effects if unused" $
           do let actual = do
                      externalFile "/tmp/test.file"
                  expected = return ()
              actual `shouldDoIo` expected
       it "is moved if only a single copy exists" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      export fH "/tmp/test.file.copy"
                  expected = do
                      src <- getRealPath "/tmp/test.file"
                      tmp <- mkTemp "test.file-1-copy" >>= ensureParentDir
                      dst' <- ensureParentDir "/tmp/test.file.copy"
                      copy src tmp
                      moveFile tmp dst'
              actual `shouldDoIo` expected
       it "is copied n-1 times and moved once for n copies" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      export fH "/tmp/test.file.copy1"
                      export fH "/tmp/test.file.copy2"
                      export fH "/tmp/test.file.copy3"
                      export fH "/tmp/test.file.copy4"
                  expected = do
                      src <- getRealPath "/tmp/test.file"
                      tmp <- mkTemp "test.file-1-copy" >>= ensureParentDir
                      dst1 <- ensureParentDir "/tmp/test.file.copy1"
                      dst2 <- ensureParentDir "/tmp/test.file.copy2"
                      dst3 <- ensureParentDir "/tmp/test.file.copy3"
                      dst4 <- ensureParentDir "/tmp/test.file.copy4"
                      copy src tmp
                      copy tmp dst1
                      copy tmp dst2
                      copy tmp dst3
                      moveFile tmp dst4
              actual `shouldDoIo` expected
       it "can be added to LocalDirectory" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      dirH <- newDirectory
                      add dirH SFreeFile (fileSpec "test.file", fH)
                  expected = do
                      ext <- getRealPath "/tmp/test.file"
                      src <- mkTemp "test.file-1-copy" >>= ensureParentDir
                      tmpDir <- mkTempDir "local-dir" >>= ensureParentDir
                      copy ext src
                      let dst = tmpDir </> "test.file"
                      moveFile src dst
              actual `shouldDoIo` expected
       it "can be added to FileSystemImage" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      fsH <-
                          create
                              SFileSystemBuilder
                              (FileSystemSpec ISO9660 "cidata" 1 MB)
                      add fsH SFreeFile (fileSpec "test.file", fH)
                  expected = do
                      ext <- getRealPath "/tmp/test.file"
                      src <- mkTemp "test.file-1-copy" >>= ensureParentDir
                      img <- mkTemp "ISO9660-cidata" >>= ensureParentDir
                      tmpDir <-
                          mkTempDir "ISO9660-cidata.d" >>= ensureParentDir
                      copy ext src
                      let dst = tmpDir </> "test.file"
                      moveFile src dst
                      createFileSystem
                          img
                          (FileSystemSpec ISO9660 "cidata" 1 MB)
                          tmpDir
                          [fileSpec "test.file"]
              actual `shouldDoIo` expected
       it
           "can be added to FileSystemImage, which can be exported and added to another FileSystemImage" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      fsH <-
                          create
                              SFileSystemBuilder
                              (FileSystemSpec ISO9660 "cidata" 1 MB)
                      add fsH SFreeFile (fileSpec "test.file", fH)
                      fileSysImgH <- convert fsH SFileSystemImage ()
                      fileSysFileH <- convert fileSysImgH SFreeFile ()
                      fsH2 <-
                          create
                              SFileSystemBuilder
                              (FileSystemSpec VFAT "blub" 1 MB)
                      add fsH2 SFreeFile (fileSpec "test1.iso", fileSysFileH)
                  expected = do
                      -- Allocate all /automatic/ file names:
                      ext <- getRealPath "/tmp/test.file"
                      src1 <- mkTemp "test.file-1-copy" >>= ensureParentDir
                      img1 <- mkTemp "ISO9660-cidata" >>= ensureParentDir
                      tmpDir1 <-
                          mkTempDir "ISO9660-cidata.d" >>= ensureParentDir
                      img2 <- mkTemp "VFAT-blub" >>= ensureParentDir
                      tmpDir2 <- mkTempDir "VFAT-blub.d" >>= ensureParentDir
                      -- Copy the input file to the directory from which the ISO
                      -- is created:
                      copy
                          ext
                          src1
                      let dst1 = tmpDir1 </> "test.file"
                      moveFile src1 dst1
                      -- Generate the first image:
                      createFileSystem
                          img1
                          (FileSystemSpec ISO9660 "cidata" 1 MB)
                          tmpDir1
                          [fileSpec "test.file"]
                      -- Generate the second image:
                      let dst2 = tmpDir2 </> "test1.iso"
                      moveFile img1 dst2
                      createFileSystem
                          img2
                          (FileSystemSpec VFAT "blub" 1 MB)
                          tmpDir2
                          [fileSpec "test1.iso"]
                      return ()
              actual `shouldDoIo` expected
       it "can be added to CloudInit" $
           do let actual = do
                      fH <- use "/tmp/test.file"
                      c <- newCloudInit "iid-1"
                      add c SFreeFile (fileSpec "test.file", fH)
                      writeCloudInitDir c "/tmp/ci.d"
                  expected = do
                      src <- mkTempDir "local-dir" >>= ensureParentDir
                      dst <- ensureParentDir "/tmp/ci.d"
                      moveDir src dst
              actual `shouldDoIo` expected
       it "can be exported from GeneratedContent" $
           do let actual = do
                      fcH <- createContent (FromString "test-content") "test-c"
                      fH <- convert fcH SFreeFile ()
                      void $ export fH "/tmp/rendered-content.file"
                  expected = do
                      src <- mkTemp "test-c-1"
                      src' <- ensureParentDir src
                      renderContentToFile
                          src'
                          (FromString "test-content")
                          (Environment [])
              actual `shouldDoIo` expected

-- * Spec for 'SFileSystemImage's

fsImgSpec :: Spec
fsImgSpec = do
    describe "compile SFileSystemImage" $
        do it "creates an empty Ext4 image" $
               shouldDoIo
                   (do fs <-
                           create
                               SFileSystemBuilder
                               (FileSystemSpec Ext4 "test-label" 10 MB)
                       fsImg <- convert fs SFileSystemImage ()
                       export fsImg "out-img.raw")
                   (do fs <- mkTemp "Ext4-test-label" >>= ensureParentDir
                       c <- mkTempDir "Ext4-test-label.d" >>= ensureParentDir
                       dest <- ensureParentDir "out-img.raw"
                       createFileSystem
                           fs
                           (FileSystemSpec Ext4 "test-label" 10 MB)
                           c
                           []
                       moveFile fs dest)
           it "shrinks an Ext4 image" $
               shouldDoIo
                   (do fs <-
                           create
                               SFileSystemBuilder
                               (FileSystemSpec Ext4 "test-label" 10 MB)
                       fsImg <- convert fs SFileSystemImage ()
                       fsImgShrunk <-
                           convert fsImg SFileSystemImage ShrinkFileSystem
                       export fsImgShrunk "out-img.raw")
                   (do fs <- mkTemp "Ext4-test-label" >>= ensureParentDir
                       c <- mkTempDir "Ext4-test-label.d" >>= ensureParentDir
                       r <-
                           mkTemp "Ext4-test-label-2-resized" >>=
                           ensureParentDir
                       dest <- ensureParentDir "out-img.raw"
                       createFileSystem
                           fs
                           (FileSystemSpec Ext4 "test-label" 10 MB)
                           c
                           []
                       moveFile fs r
                       resizeFileSystem r ShrinkFileSystem Ext4
                       moveFile r dest)
           it "can be exported to several differently resized images" $
               shouldDoIo
                   (do fs <-
                           create
                               SFileSystemBuilder
                               (FileSystemSpec Ext4 "test-label" 10 MB)
                       fsImg <- convert fs SFileSystemImage ()
                       fsImg10MB <-
                           convert
                               fsImg
                               SFileSystemImage
                               (FileSystemResize 10 MB)
                       fsImgShrunk <-
                           convert fsImg SFileSystemImage ShrinkFileSystem
                       export fsImg10MB "out1.raw"
                       export fsImgShrunk "out2.raw")
                   (do fs <- mkTemp "Ext4-test-label" >>= ensureParentDir
                       c <- mkTempDir "Ext4-test-label.d" >>= ensureParentDir
                       r1 <-
                           mkTemp "Ext4-test-label-2-resized" >>=
                           ensureParentDir
                       r2 <-
                           mkTemp "Ext4-test-label-2-resized" >>=
                           ensureParentDir
                       dest1 <- ensureParentDir "out1.raw"
                       dest2 <- ensureParentDir "out2.raw"
                       createFileSystem
                           fs
                           (FileSystemSpec Ext4 "test-label" 10 MB)
                           c
                           []
                       copy fs r1
                       moveFile fs r2
                       resizeFileSystem r1 (FileSystemResize 10 MB) Ext4
                       resizeFileSystem r2 ShrinkFileSystem Ext4
                       moveFile r1 dest1
                       moveFile r2 dest2)

-- * Spec for /candy/ functions.
candySpec :: Spec
candySpec = do
    describe "addFile" $
        it "strips the directory and  does not replace templates" $
        do let actual = do
                   d <- newDirectory
                   addFile d "/some/path/test.txt"
               expected = do
                   d <- newDirectory
                   addFileFull
                       d
                       (Source NoConversion "/some/path/test.txt")
                       (fileSpec "test.txt")
           actual `shouldDo` expected
    describe "addExe" $
        it "is equal to addFile, but changes permissions to 0755" $
        do let actual = do
                   d <- newDirectory
                   addExe d "/some/path/test.txt"
               expected = do
                   d <- newDirectory
                   addFileFull
                       d
                       (Source NoConversion "/some/path/test.txt")
                       (fileSpec "test.txt" & fileSpecPermissions .~
                        (0, 7, 5, 5))
           actual `shouldDo` expected
    describe "addFileP" $
        it "is equal to addFile, but changes permissions to the given value" $
        property $
        \perm ->
             do let actual = do
                        d <- newDirectory
                        addFileP d "/some/path/test.txt" perm
                    expected = do
                        d <- newDirectory
                        addFileFull
                            d
                            (Source NoConversion "/some/path/test.txt")
                            (fileSpec "test.txt" & fileSpecPermissions .~ perm)
                actual `does` expected
    describe "addTemplate" $
        it "strips the directory and replaces template variables" $
        do let actual = do
                   d <- newDirectory
                   addTemplate d "/some/path/test.txt"
               expected = do
                   d <- newDirectory
                   addFileFull
                       d
                       (Source ExpandVariables "/some/path/test.txt")
                       (fileSpec "test.txt")
           actual `shouldDo` expected
    describe "addTemplateExe" $
        it "is equal to addTemplate, but changes permissions to 0755" $
        do let actual = do
                   d <- newDirectory
                   addTemplateExe d "/some/path/test.txt"
               expected = do
                   d <- newDirectory
                   addFileFull
                       d
                       (Source ExpandVariables "/some/path/test.txt")
                       (fileSpec "test.txt" & fileSpecPermissions .~
                        (0, 7, 5, 5))
           actual `shouldDo` expected
    describe "addTemplateP" $
        it
            "is equal to addTemplate, but changes permissions to the given value" $
        property $
        \perm ->
             do let actual = do
                        d <- newDirectory
                        addTemplateP d "/some/path/test.txt" perm
                    expected = do
                        d <- newDirectory
                        addFileFull
                            d
                            (Source ExpandVariables "/some/path/test.txt")
                            (fileSpec "test.txt" & fileSpecPermissions .~ perm)
                actual `does` expected
    describe "mountAndShareSharedImage" $
        it "is implemented" $
        shouldDo
            (do env <- lxc "env"
                mountAndShareSharedImage "from" "to" "mp" env)
            (do env <- lxc "env"
                h <- fromShared "from"
                h' <- mount env h "mp"
                h' `sharedAs` "to")

-- * 'SLocalDirectory' examples

localDirSpec :: Spec
localDirSpec =
    describe "compile exportDir" $
    do it "creates a temporary intermediate directory" $
           let expectedCmds = mkTempDir "local-dir"
           in actualCmds `shouldDoIo` expectedCmds
       it "copies the temporary intermediate directory to all exports" $
           let exportsCmds = do
                   src' <- mkTempDir "local-dir" >>= ensureParentDir
                   dest' <- ensureParentDir "/tmp/test.d"
                   moveDir src' dest'
           in actualCmds `shouldDoIo` exportsCmds
  where
    actualCmds = do
        d <- newDirectory
        exportDir d "/tmp/test.d"

-- * Cloud init examples

minimalMetaData :: String -> Content
minimalMetaData iid =
    Concat
        [ FromString "#cloud-config\n"
        , RenderYaml (ASTObj [("instance-id", ASTString iid)])]

minimalUserData :: Content
minimalUserData = Concat [FromString "#cloud-config\n", RenderYaml (ASTObj [])]

cloudInitIsoImageSpec :: Spec
cloudInitIsoImageSpec =
    describe "compile cloudInitIsoImage" $
    do it "appends the build id to the instance id" $
           cloudInitIsoImage `shouldDoIo` B9.B9IO.getBuildId
       it "creates unique cloud-init handles" $
           dumpToResult
               (compile $
                do hnd1 <- cloudInitIsoImage
                   hnd2 <- cloudInitIsoImage
                   return (hnd1 == hnd2)) `shouldBe`
           False
       it "generates an iso image with meta- and user-data" $
           let (Handle _ iid,actualCmds) =
                   runPureDump (compile cloudInitIsoImage)
               expectedCmds = dumpToStrings expectedProg
               expectedProg = do
                   tmpIso <- mkTemp "ISO9660-cidata" >>= ensureParentDir
                   isoDir <- mkTempDir "ISO9660-cidata.d" >>= ensureParentDir
                   isoDst <- ensureParentDir "test.iso"
                   metaDataFile <-
                       mkTemp "iid-123-meta-data-2" >>= ensureParentDir
                   userDataFile <-
                       mkTemp "iid-123-user-data-3" >>= ensureParentDir
                   renderContentToFile
                       metaDataFile
                       (minimalMetaData iid)
                       (Environment [])
                   moveFile metaDataFile (isoDir </> "meta-data")
                   renderContentToFile
                       userDataFile
                       minimalUserData
                       (Environment [])
                   moveFile userDataFile (isoDir </> "user-data")
                   createFileSystem
                       tmpIso
                       (FileSystemSpec ISO9660 "cidata" 2 MB)
                       isoDir
                       [fileSpec "meta-data", fileSpec "user-data"]
                   moveFile tmpIso isoDst
           in actualCmds `should've` expectedCmds
  where
    cloudInitIsoImage :: Program (Handle 'CloudInit)
    cloudInitIsoImage = do
        i <- newCloudInit "iid-123"
        writeCloudInit i ISO9660 "test.iso"
        return i

cloudInitMultiVfatImageSpec :: Spec
cloudInitMultiVfatImageSpec =
    describe "compile cloudInitVfatImage" $
    do it "generates test1.vfat" $
           cloudInitVfatImage `shouldDoIo` (expectedProg "test1.vfat")
       it "generates test2.vfat" $
           cloudInitVfatImage `shouldDoIo` (expectedProg "test2.vfat")
  where
    expectedProg dstImg = do
        let files = [fileSpec "meta-data", fileSpec "user-data"]
            fsc = FileSystemSpec VFAT "cidata" 2 MB
            tmpDir = "/abs/path//BUILD/VFAT-cidata.d-XXXX"
            tmpImg = "/abs/path//BUILD/VFAT-cidata-XXXX"
        dstImg' <- ensureParentDir dstImg
        createFileSystem tmpImg fsc tmpDir files
        moveFile tmpImg dstImg'
    cloudInitVfatImage :: Program (Handle 'CloudInit)
    cloudInitVfatImage = do
        i <- newCloudInit "iid-123"
        writeCloudInit i VFAT "test1.vfat"
        writeCloudInit i VFAT "test2.vfat"
        return i

cloudInitDirSpec :: Spec
cloudInitDirSpec =
    describe "compile cloudInitDir" $
    do let (Handle _ iid,actualCmds) = runPureDump $ compile cloudInitDir
       it "generates a temporary directory" $
           do cloudInitDir `shouldDoIo` (mkTempDir "local-dir")
       it "renders user-data and meta-data into the temporary directory" $
           do let renderMetaData =
                      dumpToStrings $
                      do m <- mkTemp "iid-123-meta-data-2" >>= ensureParentDir
                         u <- mkTemp "iid-123-user-data-3" >>= ensureParentDir
                         renderContentToFile
                             m
                             (minimalMetaData iid)
                             (Environment [])
                         renderContentToFile
                             u
                             minimalUserData
                             (Environment [])
              actualCmds `should've` renderMetaData
       it "copies the temporary directory to the destination directories" $
           do let copyToOutputDir =
                      dumpToStrings $
                      do srcDir <- mkTempDir "local-dir" >>= ensureParentDir
                         destDir <- ensureParentDir "test.d"
                         moveDir srcDir destDir
              actualCmds `should've` copyToOutputDir
  where
    cloudInitDir :: Program (Handle 'CloudInit)
    cloudInitDir = do
        i <- newCloudInit "iid-123"
        writeCloudInitDir i "test.d"
        return i

cloudInitWithContentSpec :: Spec
cloudInitWithContentSpec =
    describe "compile cloudInitWithContent" $
    do it "merges meta-data" $
           cmds `should've`
           (dumpToStrings (renderContentToFile mdPath mdContent templateVars))
       it "merges user-data" $
           cmds `should've`
           (dumpToStrings (renderContentToFile udPath udContent templateVars))
  where
    mdPath = "/abs/path//BUILD/iid-123-meta-data-2-XXXX"
    udPath = "/abs/path//BUILD/iid-123-user-data-3-XXXX"
    templateVars = Environment [("x","3")]
    mdContent =
        Concat
            [ FromString "#cloud-config\n"
            , RenderYaml
                  (ASTMerge
                       [ ASTObj
                             [ ( "instance-id"
                               , ASTString iid)]
                       , ASTObj [("bootcmd", ASTArr [ASTString "ifdown eth0"])]
                       , ASTObj [("bootcmd", ASTArr [ASTString "ifup eth0"])]])]
    udContent =
        Concat
            [ FromString "#cloud-config\n"
            , RenderYaml
                  (ASTMerge
                       [ ASTObj []
                       , ASTObj [("write_files",
                                  ASTArr
                                  [ASTObj [("path", ASTString "file1.txt")
                                          ,("owner", ASTString "user1:group1")
                                          ,("permissions", ASTString "0642")
                                          ,("content", ASTEmbed (FromBinaryFile "/abs/path//abs/path//BUILD/contents-of-file1.txt-9-XXXX-TO-file1.txt-XXXX"))]])]
                       , ASTObj [("runcmd",ASTArr[ASTString "ls -la /tmp"])]])]
    (Handle _ iid, cmds) = runPureDump $ compile cloudInitWithContent
    cloudInitWithContent = do
        "x" $= "3"
        i <- newCloudInit "iid-123"
        writeCloudInit i ISO9660 "test.iso"
        addMetaData i (ASTObj [("bootcmd", ASTArr [ASTString "ifdown eth0"])])
        addMetaData i (ASTObj [("bootcmd", ASTArr [ASTString "ifup eth0"])])
        addFileFromContent i (FromString "file1") (FileSpec "file1.txt" (0,6,4,2) "user1" "group1")
        sh i "ls -la /tmp"
        return i

-- * vmImage tests

vmImageCreationSpec :: Spec
vmImageCreationSpec =
    describe "compile VmImage" $
    do it
           "converts an image from Raw to temporary QCow2 image, resizes it and moves it to the output path" $
           let expected = do
                   fs <- mkTemp "Ext4-image" >>= ensureParentDir
                   fsD <- mkTempDir "Ext4-image.d" >>= ensureParentDir
                   raw <- mkTemp "Ext4-image-2-Raw-image" >>= ensureParentDir
                   convSrc <- mkTemp "vm-image-Raw-5-conversion-src" >>= ensureParentDir
                   convDst <- mkTemp "vm-image-Raw-5-converted-to-QCow2" >>= ensureParentDir
                   resized <- mkTemp "resized-10-MB" >>= ensureParentDir
                   dest <- ensureParentDir "/tmp/test.qcow2"
                   convertVmImage convSrc Raw convDst QCow2
                   resizeVmImage resized 3 MB QCow2
                   moveFile resized dest
               actual = do
                   -- create a raw Ext4 image
                   rawFS <-
                       create SFileSystemBuilder (FileSystemSpec Ext4 "" 10 MB)
                   -- convert to qcow2
                   rawFS' <- convert rawFS SFileSystemImage ()
                   rawImg <- convert rawFS' SVmImage ()
                   qCowImg <- convert rawImg SVmImage (Left QCow2)
                   smallerImg <-
                       convert qCowImg SVmImage (Right (ImageSize 3 MB))
                   void $ export smallerImg "/tmp/test.qcow2"
           in actual `shouldDoIo` expected
       it "it converts an image from Raw to Vmdk" $
           let expected = do
                   src <- mkTemp "file-system-image-root"
                   conv <- mkTemp "converted-img-file"
                   src' <- getRealPath src
                   conv' <- ensureParentDir conv
                   convertVmImage src' Raw conv' Vmdk
                   dest' <- ensureParentDir "/tmp/test.vmdk"
                   moveFile conv' dest'
                   return ()
               actual = do
                   -- create a raw Ext4 image
                   rawFS <-
                       create
                           SFileSystemBuilder
                           (FileSystemSpec Ext4 "root" 10 MB)
                   rawImg <- convert rawFS SVmImage ()
                   vmdkImg <- convert rawImg SVmImage (Left Vmdk)
                   export vmdkImg "/tmp/test.vmdk"
           in actual `shouldDoIo` expected
       it
           "copies and moves an image if neither conversion nor resize is required" $
           let actual = do
                   rawFS <-
                       create
                           SFileSystemBuilder
                           (FileSystemSpec Ext4 "root" 10 MB)
                   rawImg <- convert rawFS SVmImage ()
                   export rawImg "/tmp/dest.raw"
               expected = do
                   src <- mkTemp "file-system-image-root"
                   tmp <- mkTemp "tmp-file"
                   raw' <- getRealPath src
                   tmp' <- ensureParentDir tmp
                   copy raw' tmp'
                   dst <- ensureParentDir "/tmp/dest.raw"
                   moveFile tmp' dst
           in actual `shouldDoIo` expected

-- * Partition extraction examples

partitionedDiskSpec :: Spec
partitionedDiskSpec =
    describe "compile PartionedVmImage" $
    do it "extracts the selected partition" $
           let actual = do
                   rawPartitionedFile <- use "/tmp/partitioned.raw"
                   partitionedImg <-
                       convert rawPartitionedFile SPartitionedVmImage ()
                   rawPart2File <- convert partitionedImg SFreeFile (MBRPartition 2)
                   export rawPart2File "/tmp/part2.raw"
               expected = do
                   src <- getRealPath "/tmp/partitioned.raw"
                   dst <- ensureParentDir "/tmp/part2.raw"
                   extractPartition (MBRPartition 2) src dst
           in actual `shouldDoIo` expected

-- * VmImage respository IO

sharedImageSpec :: Spec
sharedImageSpec =
    describe "compile ShareImageRepository" $
    it
        "supports lookup, get and put vm-image operations"
        (shouldDoIo
             (do imgH <- fromShared "source-image"
                 sharedAs imgH "out-shared")
             (do (_,cachedImg) <-
                     imageRepoLookup (SharedImageName "source-image")
                 cachedImg' <- getRealPath cachedImg
                 imageRepoPublish
                     cachedImg'
                     QCow2
                     (SharedImageName "out-shared")))

-- * LiveInstaller image generation

updateServerImageSpec :: Spec
updateServerImageSpec =
    describe "exportForUpdateServer" $
    do let actual = do
               -- TODO extract this to DSL.h:
               srcF <- use srcFile
               srcImg <- convert srcF SVmImage QCow2
               outDirH <- create SLocalDirectory ()
               usRoot <- convert outDirH SUpdateServerRoot ()
               add usRoot SVmImage (SharedImageName machine, srcImg)
               void $ export outDirH outDir
           srcFile = "source.qcow2"
           outDir = "EXPORT"
           machine = "webserver"
       it
           "converts an input image in arbitrary format to a temporary Raw image inside a given directory" $
           shouldDoIo
               actual
               (do tmpDir <- mkTempDir "local-dir"
                   let tmpImg = tmpBase </> "0.raw"
                       tmpSize = tmpBase </> "0.size"
                       tmpVersion = tmpBase </> "VERSION"
                       tmpBase =
                           tmpDir </> "machines" </> machine </> "disks/raw"
                   src <- getRealPath srcFile
                   mkDir tmpBase
                   convertVmImage src QCow2 tmpImg Raw
                   size <- B9.B9IO.readFileSize tmpImg
                   renderContentToFile
                       tmpSize
                       (FromString (show size))
                       (Environment [])
                   bId <- B9.B9IO.getBuildId
                   bT <- B9.B9IO.getBuildDate
                   renderContentToFile
                       tmpVersion
                       (FromString (printf "%s-%s" bId bT))
                       (Environment [])
                   dst' <- ensureParentDir outDir
                   moveDir tmpDir dst'
                   return ())

-- * Containerized Build Specs

containerExecutionSpec :: Spec
containerExecutionSpec =
    describe "lxc environment" $
    do let envSpec =
               ExecEnvSpec "test-env" LibVirtLXC $
               Resources AutomaticRamSize 2 X86_64
           testFileSpec1 =
               (FileSpec "/root/sub1/sub1.1/passwd" (0, 7, 6, 7) "root" "users")
           testFileSpec2 =
               (FileSpec "/build/issue" (0, 7, 7, 7) "root" "users")
           testProg = do
               e <- boot envSpec
               sh e "touch /test1"
               sh e "touch /test2"
               addFileFull e (Source NoConversion "/etc/issue") testFileSpec2
               addFileFull e (Source NoConversion "/etc/passwd") testFileSpec1
               rootImgFile <- use "test-in.qcow2"
               rootImg <- convert rootImgFile SVmImage QCow2
               rootOutImg <- mount e rootImg "/"
               void $ export rootOutImg "img-out.qcow"
       it "converts the input images into 'Raw' format" $
           testProg `shouldDoIo`
           do conv <- mkTemp "converted-img-file"
              src' <- getRealPath "test-in.qcow2"
              conv' <- ensureParentDir conv
              convertVmImage src' QCow2 conv' Raw
       it "exports the input images as new output images" $
           testProg `shouldDoIo`
           do conv <- mkTemp "converted-img-file"
              dest <- mkTemp "resized-img-file"
              conv' <- getRealPath conv
              dest' <- ensureParentDir dest
              moveFile conv' dest'
       it "copies one added file into a directory to mount" $
           shouldDoIo testProg $
           do incDir <- mkTempDir "included-files"
              includedFile1 <- mkTempIn incDir "added-file"
              -- export the ReadOnlyFile "/etc/passwd":
              realPathFile1 <- getRealPath "/etc/passwd"
              realPathCopyOfFile1 <- ensureParentDir includedFile1
              copy realPathFile1 realPathCopyOfFile1
       it "copies all added files into a directory to mount" $
           shouldDoIo testProg $
           do incDir <- mkTempDir "included-files"
              includedFile1 <- mkTempIn incDir "added-file"
              includedFile2 <- mkTempIn incDir "added-file"
              -- copy file 1
              realPathFile1 <- getRealPath "/etc/passwd"
              realPathCopyOfFile1 <- ensureParentDir includedFile1
              copy realPathFile1 realPathCopyOfFile1
              -- copy file 2
              realPathFile2 <- getRealPath "/etc/issue"
              realPathCopyOfFile2 <- ensureParentDir includedFile2
              copy realPathFile2 realPathCopyOfFile2
       it "generates a script to copy, chmod and chown all added files" $
           shouldDoIo testProg $
           do buildId <- B9.B9IO.getBuildId
              incDir <- mkTempDir "included-files"
              inc1 <- mkTempIn incDir "added-file"
              inc2 <- mkTempIn incDir "added-file"
              dest <- mkTemp "resized-img-file"
              let incScript =
                      incFileScript buildId inc2 testFileSpec2 <>
                      incFileScript buildId inc1 testFileSpec1
              executeInEnv
                  envSpec
                  incScript
                  [ SharedDirectoryRO
                        incDir
                        (MountPoint $ includedFileContainerPath buildId)]
                  [(Image dest Raw Ext4, MountPoint "/")]
       it "creates the output image AFTER script execution" $
           shouldDoIo testProg $
           do buildId <- B9.B9IO.getBuildId
              incDir <- mkTempDir "included-files"
              inc1 <- mkTempIn incDir "added-file"
              inc2 <- mkTempIn incDir "added-file"
              tmpImg <- mkTemp "tmp-file"
              destImg <- mkTemp "resized-img-file"
              let incScript =
                      incFileScript buildId inc2 testFileSpec2 <>
                      incFileScript buildId inc1 testFileSpec1
              executeInEnv
                  envSpec
                  incScript
                  [ SharedDirectoryRO
                        incDir
                        (MountPoint $ includedFileContainerPath buildId)]
                  [(Image destImg Raw Ext4, MountPoint "/")]
              tmpImg' <- ensureParentDir tmpImg
              destImg' <- ensureParentDir destImg
              moveFile tmpImg' destImg'

-- * DSL examples

dslExample1 :: Program ()
dslExample1 = do
    "x" $= "3"
    c <- newCloudInit "blah-ci"
    writeCloudInit c ISO9660 "test.iso"
    writeCloudInitDir c "test"
    writeCloudInit c VFAT "test.vfat"
    addMetaData c (ASTString "test")
    addUserData c (ASTString "test")
    e <- lxc "container-id"
    mountDirRW e "tmp" "/mnt/HOST_TMP"
    addFileFull
        e
        (Source ExpandVariables "httpd.conf.in")
        (fileSpec "/etc/httpd.conf")
    sh e "ls -la"
    addTemplate c "httpd.conf"
    sh c "ls -la"
    doc "From here there be dragons:"
    rootImage "fedora" "testv1-root" e
    dataImage "testv1-data" e
    {-
    img <- from "schlupfi"
    mountDir e "/tmp" "/mnt/HOST_TMP"
    sharedAs img "wupfi"
    resize img 64 GB
    resizeToMinimum img
    -}

dslExample2 :: Program ()
dslExample2 = do
    env <- lxc "c1"
    sh env "ls -lR /"
