{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The progress-archive codec: the player's saved state as a single versioned
-- JSON document, for export to a file and re-import.
--
-- The whole player state lives in a handful of @localStorage@ keys (the solved
-- set, viewed prose, pre-test answers, unlock overrides, and per-level drafts).
-- An archive is just those key/value pairs wrapped with a format @version@:
--
-- > { "version": 1,
-- >   "saved": { "rzk-game-progress": "0,1,2",
-- >              "rzk-game-draft-0": "#def …", … } }
--
-- The codec is deliberately generic over @[(key, value)]@ — it does not know
-- which keys are player data; the caller (the app) decides what to gather and,
-- on import, which keys to accept. That keeps this module pure and natively
-- testable, independent of the wasm-only @localStorage@ access in @Main@.
module RzkGame.Save
  ( archiveVersion
  , encodeArchive
  , decodeArchive
  ) where

import           Data.Aeson           (Value (..), eitherDecodeStrict', encode,
                                       object, (.=))
import qualified Data.Aeson.Key       as Key
import qualified Data.Aeson.KeyMap    as KM
import qualified Data.ByteString.Lazy as BL
import           Data.Text            (Text)
import qualified Data.Text            as T
import           Data.Text.Encoding   (decodeUtf8, encodeUtf8)

-- | The archive format version. Bumped only on an incompatible layout change;
-- an archive carrying any other version is rejected by 'decodeArchive' rather
-- than guessed at.
archiveVersion :: Int
archiveVersion = 1

-- | Serialise a list of key/value pairs to a versioned archive document. Keys
-- are assumed unique (they are distinct @localStorage@ keys); a repeated key
-- would collapse to its last value, as in a JSON object.
encodeArchive :: [(Text, Text)] -> Text
encodeArchive kvs =
  decodeUtf8 . BL.toStrict . encode $
    object
      [ "version" .= archiveVersion
      , "saved"   .= object [ Key.fromText k .= v | (k, v) <- kvs ]
      ]

-- | Parse an archive document back to its key/value pairs. Fails with a
-- human-readable message on malformed JSON, a missing or non-object shape, or an
-- unsupported @version@. Entries under @saved@ whose value is not a JSON string
-- are dropped (only string values are player data), so foreign junk cannot crash
-- a restore.
decodeArchive :: Text -> Either Text [(Text, Text)]
decodeArchive t =
  case eitherDecodeStrict' (encodeUtf8 t) of
    Left err  -> Left ("malformed archive JSON: " <> T.pack err)
    Right val -> parseArchive val

parseArchive :: Value -> Either Text [(Text, Text)]
parseArchive (Object o) = do
  checkVersion (KM.lookup "version" o)
  saved <- case KM.lookup "saved" o of
    Just (Object s) -> Right s
    Just _          -> Left "archive \"saved\" is not an object"
    Nothing         -> Left "archive has no \"saved\" field"
  Right [ (Key.toText k, s) | (k, String s) <- KM.toList saved ]
parseArchive _ = Left "archive is not a JSON object"

checkVersion :: Maybe Value -> Either Text ()
checkVersion = \case
  Just (Number n)
    | n == fromIntegral archiveVersion -> Right ()
    | otherwise -> Left ("unsupported archive version " <> T.pack (show n)
                          <> " (expected " <> T.pack (show archiveVersion) <> ")")
  Just _  -> Left "archive \"version\" is not a number"
  Nothing -> Left "archive has no \"version\" field"
