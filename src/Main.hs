{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Lens ((^.), (^?))
import Control.Monad.Trans (liftIO)
import Data.Aeson (FromJSON, Result (..), ToJSON, fromJSON, object, parseJSON, toJSON, withObject, (.:), (.=))
import Data.Aeson.Lens (key)
import GHC.Generics (Generic)
import qualified Network.Wreq as W
import System.Environment (getEnv)
import Web.Scotty (get, json, param, scotty)

-- {
-- sport_key: "americanfootball_nfl",
-- sport_nice: "NFL",
-- teams: [
-- "Las Vegas Raiders",
-- "Los Angeles Chargers"
-- ],
-- commence_time: 1608254400,
-- home_team: "Las Vegas Raiders",
-- sites: [],
-- sites_count: 14
-- },
data Odds = Odds
  { _sportKey :: String,
    _sportNice :: String,
    _teams :: [String],
    _commenceTime :: Integer,
    _homeTeam :: String,
    _sites :: [BookData],
    _sitesCount :: Integer
  }

-- {
-- site_key: "caesars",
-- site_nice: "Caesars",
-- last_update: 1608012983,
-- odds: {
-- h2h: [
-- -179,
-- 160
-- ]
-- }
-- },
data BookData = BookData
  { _siteKey :: String,
    _siteNice :: String,
    _lastUpdate :: Integer,
    _odds :: [Double]
  }

instance ToJSON BookData where
  toJSON BookData {_siteKey, _siteNice, _lastUpdate, _odds} =
    object
      [ "site_key" .= _siteKey,
        "site_nice" .= _siteNice,
        "last_update" .= _lastUpdate,
        "odds" .= _odds
      ]

instance FromJSON BookData where
  parseJSON =
    withObject
      "BookData"
      ( \obj -> do
          _siteKey <- obj .: "site_key"
          _siteNice <- obj .: "site_nice"
          _lastUpdate <- obj .: "last_update"
          _odds <- obj .: "odds"
          pure $ BookData {_siteKey, _siteNice, _lastUpdate, _odds}
      )

instance ToJSON Odds where
  toJSON Odds {_sportKey, _sportNice, _teams, _commenceTime, _homeTeam, _sites, _sitesCount} =
    object
      [ "sport_key" .= _sportKey,
        "sport_nice" .= _sportNice,
        "teams" .= _teams,
        "commence_time" .= _commenceTime,
        "home_team" .= _homeTeam,
        "sites" .= _sites,
        "sites_count" .= _sitesCount
      ]

instance ToJSON Sports where
  toJSON Sports {_key, _active, _group, _details, _title, _hasOutRights} =
    object
      [ "key" .= _key,
        "active" .= _active,
        "group" .= _group,
        "details" .= _details,
        "title" .= _title,
        "has_outrights" .= _hasOutRights
      ]

instance FromJSON Odds where
  parseJSON =
    withObject
      "Odds"
      ( \obj -> do
          _sportKey <- obj .: "sport_key"
          _sportNice <- obj .: "sports_nice"
          _teams <- obj .: "teams"
          _commenceTime <- obj .: "commence_time"
          _homeTeam <- obj .: "home_team"
          _sites <- BookData <$> obj .: "sites"
          _sitesCount <- obj .: "site_count"
          pure $ Odds {_sportKey, _sportNice, _teams, _commenceTime, _homeTeam, _sites, _sitesCount}
      )

instance FromJSON Sports where
  parseJSON =
    withObject
      "Sports"
      ( \obj -> do
          _key <- obj .: "key"
          _active <- obj .: "active"
          _group <- obj .: "group"
          _details <- obj .: "details"
          _title <- obj .: "title"
          _hasOutRights <- obj .: "has_outrights"
          pure $ Sports {_key, _active, _group, _details, _title, _hasOutRights}
      )

data Sports = Sports
  { _key :: String,
    _active :: Bool,
    _group :: String,
    _details :: String,
    _title :: String,
    _hasOutRights :: Bool
  }
  deriving (Generic, Show, Eq)

data Sport = CFB | NFL | MLB | MMA

data Region = AU | UK | EU | US

data Market = H2H | Spreads | Totals

data OddsFormat = American | Decimal

regionToOddsFormat :: Region -> OddsFormat
regionToOddsFormat US = American
regionToOddsFormat _ = Decimal

oddsFormatToString :: OddsFormat -> String
oddsFormatToString American = "american"
oddsFormatToString _ = "decimal"

marketToString :: Market -> String
marketToString m = case m of
  Spreads -> "spreads"
  H2H -> "h2h"
  Totals -> "totals"

regionToKey :: Region -> String
regionToKey a = case a of
  AU -> "au"
  UK -> "uk"
  US -> "us"
  EU -> "eu"

sportToKey :: Sport -> String
sportToKey sport = case sport of
  CFB -> "americanfootball_ncaaf"
  NFL -> "americanfootball_nfl"
  MLB -> "baseball_mlb"
  MMA -> "mma_mixed_martial_arts"

baseUrl :: String
baseUrl = "https://api.the-odds-api.com"

oddsApi :: String -> Sport -> Region -> Market -> String
oddsApi key s r m = "/v3/odds/?apiKey=" ++ key ++ "&sport=" ++ sport ++ "&region=" ++ region ++ "&mkt=" ++ mkt ++ "&oddsFormat=" ++ odds
  where
    sport = sportToKey s
    odds = (oddsFormatToString . regionToOddsFormat) r
    region = regionToKey r
    mkt = marketToString m

sportsApi :: String -> String
sportsApi key = "/v3/sports/?apiKey=" ++ key

-- /v3/odds/?apiKey={apiKey}&sport={sport}&region={region}&mkt={mkt}
--
createUrl :: String -> String
createUrl route = baseUrl ++ route

loadEnv :: IO String
loadEnv = do
  loadFile defaultConfig
  getEnv "odds_api"

getResultFromMaybe :: Maybe (Result [Sports]) -> [Sports]
getResultFromMaybe a = case a of
  Just x -> case x of
    Success val -> val
    Error _ -> []
  Nothing -> []

oddsFromMaybe :: Maybe (Result [Odds]) -> [Odds]
oddsFromMaybe a = case a of
  Just x -> case x of
    Success val -> val
    Error _ -> []
  Nothing -> []

getSportsData :: IO [Sports]
getSportsData = do
  env <- loadEnv
  let url = createUrl $ sportsApi env
  resp <- W.get url
  let body = resp ^. W.responseBody
  let dat = body ^? key "data"
  let x = fromJSON <$> dat
  (pure . getResultFromMaybe) x

getOddsData :: Sport -> Region -> Market -> IO [Odds]
getOddsData sport region market = do
  apiKey <- loadEnv
  let url = createUrl $ oddsApi apiKey sport region market
  resp <- W.get url
  let body = resp ^. W.responseBody
  let dat = body ^? key "data"
  let x = fromJSON <$> dat
  (pure . oddsFromMaybe) x

main :: IO ()
main = scotty 3000 $ do
  get "/getpicks" $ do
    a <- liftIO getSportsData
    json a

  get "/getOdds/:sport" $ do
    -- param sport needs to be key from getSportsData
    -- x <- param "sport"
    d <- liftIO $ getOddsData NFL US H2H
    json d
