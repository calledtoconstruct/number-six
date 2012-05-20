-- | Main module, containing the 'numberSix' function needed to launch your bot.
--
{-# LANGUAGE OverloadedStrings #-}
module NumberSix
    ( numberSix
    , numberSixWith
    ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan.Strict (readChan, writeChan)
import Control.Concurrent.MVar (newMVar)
import Control.Monad (forever, forM, forM_)
import Data.Maybe (catMaybes)
import Prelude hiding (catch)

import qualified Data.ByteString.Char8 as SBC

import NumberSix.Irc
import NumberSix.Message
import NumberSix.Message.Encode
import NumberSix.Message.Decode
import NumberSix.Handlers
import NumberSix.Socket
import NumberSix.ExponentialBackoff
import NumberSix.Logger
import NumberSix.SandBox

-- | Run a single IRC connection
--
irc :: Logger                -- ^ Logger
    -> [UninitiazedHandler]  -- ^ Handlers
    -> IrcConfig             -- ^ Configuration
    -> IO ()
irc logger uninitialized config = withConnection' $ \inChan outChan -> do

    -- Create a god container
    gods <- newMVar []

    let environment = IrcEnvironment
            { ircConfig = config
            , ircWriter = writer outChan
            , ircLogger = logger
            , ircGods   = gods
            }

    -- Initialize handlers
    handlers' <- fmap catMaybes $ forM uninitialized $
        \h@(UninitiazedHandler name _ _) ->
            let state = IrcState
                    { ircEnvironment = environment
                    , ircMessage     = error "NumberSix: message not known yet"
                    , ircHandler     = error "Uninitialized handler"
                    }
            in sandBox logger name (Just 10) $ initializeHandler h state

    forever $ handleLine environment handlers' inChan
  where
    withConnection' =
        withConnection (SBC.unpack $ ircHost config) (ircPort config)

    -- Writer to the out channel
    writer chan message = do
        let bs = encode message
        writeChan chan $ SocketData bs
        logger $ "OUT: " <> bs

    -- Processes one line
    handleLine environment handlers' inChan = do
        SocketData l <- readChan inChan
        case decode l of
            Nothing -> logger "Parse error."
            Just message' -> do
                logger $ "IN: " <> l

                -- Run every handler on the message
                forM_ handlers' $ \h -> do
                    let state = IrcState
                            { ircEnvironment = environment
                            , ircMessage = message'
                            , ircHandler = h
                            }

                    -- Run the handler in a separate thread
                    _ <- forkIO $ sandBox_ logger (handlerName h) (Just 60) $
                        runHandler h state
                    return ()

-- | Launch a bots and block forever. All default handlers will be activated.
--
numberSix :: IrcConfig -> IO ()
numberSix = numberSixWith handlers

-- | Launch a bot with given 'SomeHandler's and block forever
--
numberSixWith :: [UninitiazedHandler] -> IrcConfig -> IO ()
numberSixWith handlers' config = do
    logger <- newLogger
    exponentialBackoff 30 (5 * 60) $ sandBox_ logger "numberSixWith" Nothing $
        irc logger handlers' config