module NumberSix.Handlers.Tell
    ( handler
    ) where

import Control.Applicative ((<$>))
import Data.Maybe (fromMaybe)
import Control.Monad (forM_)

import NumberSix.Irc
import NumberSix.Util
import NumberSix.Util.Redis

handler :: Handler
handler = Handler
    { handlerName = "tell"
    , handlerHooks = [storeHook, loadHook]
    }

storeHook :: Irc ()
storeHook = onBangCommand "!tell" $ do
    text <- getBangCommandText
    sender <- getSender
    time <- prettyTime
    let (recipient, message) = breakWord text
        tell = (sender, time, message)
    messages <- fromMaybe [] <$> getItem recipient
    setItem recipient $ messages ++ [tell]
    writeChannelReply $ "I'll pass that on when " ++ recipient ++ " is here."

loadHook :: Irc ()
loadHook = onCommand "privmsg" $ do
    sender <- getSender
    items <- getItem sender
    case items of
        Nothing -> return ()
        Just l -> do
            forM_ l $ \(from, time, message) ->
                writeChannelReply $ from ++ " (" ++ time ++ "): " ++ message
            deleteItem sender
