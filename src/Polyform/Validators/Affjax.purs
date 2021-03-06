module Polyform.Validators.Affjax where

import Prelude

import Control.Monad.Error.Class (catchError)
import Data.Argonaut (Json, jsonParser)
import Data.Array (singleton)
import Data.Either (Either(..))
import Data.Functor.Variant (SProxy(..))
import Data.Variant (Variant, inj)
import Effect.Aff (Aff)
import Foreign.Object (Object)
import Network.HTTP.Affjax (AffjaxRequest, AffjaxResponse)
import Network.HTTP.Affjax (affjax) as Affjax
import Network.HTTP.Affjax.Response (Response, json, string)
import Network.HTTP.StatusCode (StatusCode(..))
import Polyform.Validation (V(Invalid, Valid), Validation, hoistFnMV, hoistFnV)
import Polyform.Validators.Json (JsError, object)

type HttpErrorRow (err :: # Type) = (wrongHttpStatus :: StatusCode | err)
type AffjaxErrorRow (err :: # Type) = (remoteError :: String | err)
type JsonErrorRow (err :: # Type) = (parsingError :: String | err)

affjax
  :: forall a err
   . (Response a)
  -> Validation
      Aff
      (Array (Variant (AffjaxErrorRow err)))
      AffjaxRequest
      (AffjaxResponse a)
affjax res = hoistFnMV $ \req → do
  (Valid [] <$> Affjax.affjax res req) `catchError` handler where
    handler e = pure (Invalid $ singleton $ (inj (SProxy :: SProxy "remoteError") $ show e))

status
  :: forall m err res
   . Monad m
  => (StatusCode -> Boolean)
  -> Validation m
      (Array (Variant (HttpErrorRow err)))
      (AffjaxResponse res)
      res
status isCorrect = hoistFnV checkStatus where
  checkStatus response =
    if isCorrect response.status then
      Valid [] response.response
    else
      Invalid $ singleton $ (inj (SProxy :: SProxy "wrongHttpStatus") response.status)

isStatusOK :: StatusCode -> Boolean
isStatusOK (StatusCode n) = (n == 200)

jsonFromRequest
  :: forall err
   . Validation
      Aff
      (Array (Variant(HttpErrorRow (AffjaxErrorRow (JsError err)))))
      AffjaxRequest
      (Object Json)
jsonFromRequest = object <<< status isStatusOK <<< affjax json

valJson
  :: forall m err
   . Monad m
  => Validation m
      (Array (Variant (JsonErrorRow err)))
      String
      Json
valJson = hoistFnV \response -> case jsonParser response of
  Right js -> Valid [] js
  Left error -> Invalid  $ singleton (inj (SProxy :: SProxy "parsingError") error)

affjaxJson
  :: forall errs
   . Validation
      Aff
      (Array (Variant (HttpErrorRow(AffjaxErrorRow (JsonErrorRow errs)))))
      AffjaxRequest
      Json
affjaxJson = valJson <<< status isStatusOK <<< affjax string
