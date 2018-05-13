{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE Rank2Types #-}

module Main where

import Text.Pandoc.JSON
import System.IO.Temp
import System.FilePath
import System.Console.GetOpt
import System.Process (readProcess)
import System.Environment (getArgs)
import System.Directory
import Data.Maybe (fromMaybe)
import Data.Reflection (Given, give, given)

pattern DitaaBlock code <- CodeBlock (_, ["ditaa"], _) code

data Config = Config
  { optDitaaCmd :: String
  , optImgDir :: Maybe FilePath
  , optAppID :: String
  } deriving Show

defaultConfig :: Config
defaultConfig = Config
  { optDitaaCmd = "ditaa"
  , optImgDir = Nothing
  , optAppID = "ditaa-md"
  }

options :: [OptDescr (Config -> Config)]
options =
  [ Option [] ["ditta-cmd"] (ReqArg (\s cfg -> cfg { optDitaaCmd = s }) "CMD") "ditaa command"
  , Option [] ["img-dir"] (ReqArg (\s cfg -> cfg { optImgDir = Just s }) "DIR") "image directory"
  ]

getOptions :: IO (Config, [String])
getOptions = do
  args <- getArgs
  case getOpt Permute options args of
    (c, n, []) -> return (foldl (flip id) defaultConfig c, n)
    (_, _, e)  -> ioError $ userError $ "error: " ++ concat e

main :: IO ()
main = do
  (cfg, _) <- getOptions
  withGivenConfig cfg $ do
    tmpDir <- createTmpDir
    toJSONFilter $ convertPandoc tmpDir

createTmpDir :: Given Config => IO FilePath
createTmpDir = case optImgDir given of
  Nothing -> do
    sysTmpDir <- getCanonicalTemporaryDirectory
    createTempDirectory sysTmpDir $ optAppID given
  Just imgDir -> do
    pwd <- getCurrentDirectory
    createTempDirectory pwd imgDir

withGivenConfig :: Config -> (Given Config => a) -> a
withGivenConfig cfg f = give cfg $ f

convertPandoc :: Given Config => FilePath -> Pandoc -> IO Pandoc
convertPandoc tmpDir (Pandoc meta blocks) = do
  newBlocks <- sequence $ map (ditaaBlockToImg tmpDir) numberedBlocks
  return $ Pandoc meta newBlocks
  where
    numberedBlocks = numberDitaaBlocks blocks 1

ditaaBlockToImg :: Given Config => FilePath -> (Block, Int) -> IO Block
ditaaBlockToImg tmpDir (DitaaBlock code, i) = do
  writeFile txtPath code
  readProcess ditaaCmd [txtPath, imgPath] ""
  return $ Para [Image nullAttr [Str imgTitle] (imgPath, "fig:" ++ imgTitle)]
  where
    imgTitle = optAppID given ++ show i
    ditaaCmd = optDitaaCmd given
    txtPath = tmpDir </> show i <.> "txt"
    imgPath = tmpDir </> show i <.> "png"
ditaaBlockToImg _ (b, _) = return b

numberDitaaBlocks :: [Block] -> Int -> [(Block, Int)]
numberDitaaBlocks [] !_ = []
numberDitaaBlocks (b@(DitaaBlock _) : bs) !i =
  (b, i) : numberDitaaBlocks bs (i + 1)
numberDitaaBlocks (b:bs) !i = (b, i) : numberDitaaBlocks bs i
