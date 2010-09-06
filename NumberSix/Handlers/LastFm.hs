-- | Get a user's last listened track on last.fm
--
module NumberSix.Handlers.LastFm
    ( handler
    ) where

import Data.Maybe (fromMaybe)

import Text.HTML.TagSoup

import NumberSix.Irc
import NumberSix.Util.Http

lastFm :: String -> Irc [String]
lastFm query = httpScrape url $ \tags -> fromMaybe ["Not found"] $ do
    TagText artist <- nextTag tags (TagOpen "artist" [])
    TagText name <- nextTag tags (TagOpen "name" [])
    TagText url <- nextTag tags (TagOpen "url" [])
    return $ [ query ++ " last listened to: " ++ name ++ " by " ++ artist
             , url
             ]
  where
    url =  "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user="
        ++ urlEncode query ++ "&api_key=87b8b81da496639cb5a295d78e5f8f4d"

handler :: Handler
handler = makeBangHandler "lastfm" "!lastfm" lastFm
