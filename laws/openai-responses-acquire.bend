import Base
import ../packages/ai/src/api/openai-responses-acquire.bend as A
import ../packages/ai/src/api/openai-responses-envelope.bend as E
import ../packages/ai/src/api/openai-responses-prepare.bend as P
import ../packages/ai/src/api/openai-responses-policy.bend as Policy
import ../packages/ai/src/api/openai-request-headers.bend as H
import ../packages/ai/src/utils/provider-retry.bend as Retry
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/url-absolute.bend as URL
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/callback.bend as C

law preparation_preserves_client_and_payload:
  for url: URL.Context
  for defaults: H.Defaults
  for timeout: Maybe<&2, F.F64>
  for key: String
  for base: String
  for headers: T.ProviderHeaders()
  for payload: T.JsonValue
  for compat: Policy.ResolvedCompat
  for grammar: R.Record<String>
  for retention: T.CacheRetention
  {A.prepared(url, defaults, timeout, P.Prepared{key, base, headers, payload, compat, grammar, retention}) == (A.Client{url, defaults, key, headers, base, timeout}, payload) : A.Client & T.JsonValue}

law invalid_envelope_has_no_transport_effect:
  for -Error: Data
  for -State: Type
  for encode: E.Error -> Error
  for request: C.Callback<E.Request, A.Outcome(Error, State)>
  for cause: E.Error
  {A.dispatch(Error, State, encode, request, Fail{cause}) == IO.pure(A.Outcome(Error, State), Fail{Retry.Other{encode(cause)}}) : IO(A.Outcome(Error, State))}

law valid_envelope_transfers_unchanged:
  for -Error: Data
  for -State: Type
  for encode: E.Error -> Error
  for request: C.Callback<E.Request, A.Outcome(Error, State)>
  for wire: E.Request
  {A.dispatch(Error, State, encode, request, Done{wire}) == C.call(E.Request, A.Outcome(Error, State), request, wire) : IO(A.Outcome(Error, State))}
