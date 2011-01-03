-- | Main module, containing the 'numberSix' function needed to launch your bot.
--
{-# LANGUAGE OverloadedStrings #-}
module NumberSix
    ( numberSix
    , numberSixWith
    ) where

import Control.Applicative ((<$>))
import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (try, SomeException (..))
import Control.Monad (forever, forM_)
import Data.Monoid (mappend)
import Control.Concurrent.Chan (readChan, writeChan)
import Control.Concurrent.MVar (newMVar)
import System.Environment (getProgName)

import qualified Data.ByteString as SB
import qualified Data.ByteString.Char8 as SBC

import NumberSix.Irc
import NumberSix.Message
import NumberSix.Message.Encode
import NumberSix.Message.Decode
import NumberSix.Handlers
import NumberSix.Socket

-- | Run a single IRC connection
--
irc :: [SomeHandler]  -- ^ Handlers
    -> IrcConfig      -- ^ Configuration
    -> IO ()
irc handlers' config = withConnection' $ \inChan outChan -> do

    -- Create a god container
    gods <- newMVar []

    let writer' m = do
            writeChan outChan $ encode m
            logger $ "SENT: " <> (SBC.pack $ show m)

        environment = IrcEnvironment
            { ircConfig = config
            , ircWriter = writer'
            , ircLogger = logger
            , ircGods   = gods
            }

    forever $ handleLine environment inChan
  where
    withConnection' =
        withConnection (SBC.unpack $ ircHost config) (ircPort config)

    logger message = do
        -- Create a logger
        logFileName <- (++ ".log") <$> getProgName
        SB.appendFile logFileName $ message `mappend` "\n"

    -- Processes one line
    handleLine environment inChan = readChan inChan >>= \l -> case decode l of
        Nothing -> logger "Parse error."
        Just message' -> do
            logger $ "RECEIVED: " <> (SBC.pack $ show message')

                -- Build an IRC state
            -- Run every handler on the message
            forM_ handlers' $ \h -> do
                let state = IrcState
                        { ircEnvironment = environment
                        , ircMessage = message'
                        , ircHandler = h
                        }

                -- Run the handler in a separate thread
                _ <- forkIO $ runSomeHandler h state
                return ()

-- | Launch a bots and block forever. All default handlers will be activated.
--
numberSix :: IrcConfig -> IO ()
numberSix = numberSixWith handlers

-- | Launch a bot with given 'SomeHandler's and block forever
--
numberSixWith :: [SomeHandler] -> IrcConfig -> IO ()
numberSixWith handlers' config = do
    _ <- forever $ do
        e <- try $ irc handlers' config
        putStrLn $ "Error: " ++ show (e :: Either SomeException ())
        threadDelay (30 * 1000000)
    return ()
