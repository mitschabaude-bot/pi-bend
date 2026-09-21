import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/api/openai-request-headers.bend as Request
import ../packages/ai/src/utils/provider-header-state.bend as S
import ../packages/runtime/src/http-header.bend as H
import ../packages/runtime/src/headers.bend as Headers
import ../packages/runtime/src/f64.bend as F

law explicit_timeout_is_retained:
  for value: F.F64
  {Request.effectiveTimeout(Some{value}) == value : F.F64}

law noninteger_timeout_is_rejected:
  for value: F.F64
  {Request.checkedTimeout(value, False{}) == Fail{Request.TimeoutNotInteger{value}} : Result<&2, &2, Request.Error, F.F64>}

law header_failure_preserves_cause:
  for cause: H.HeaderError
  {Request.assembled(Fail{cause}) == Fail{Request.HeaderFailure{cause}} : Result<&2, &2, Request.Error, Headers.Headers>}

law failed_authentication_has_no_headers:
  for state: S.State
  {Request.authenticate(state, False{}) == Fail{Request.MissingAuthentication{}} : Result<&2, &2, Request.Error, Headers.Headers>}

law accepted_authentication_preserves_headers:
  for state: S.State
  {Request.authenticate(state, True{}) == Done{S.headers(state)} : Result<&2, &2, Request.Error, Headers.Headers>}

law removal_allows_authentication_override:
  for other: Maybe<&2, T.Nullable<String>>
  {Request.authenticationAllowed(Some{T.NullValue{}}, other) == True{} : Bool}

law authentication_methods_are_interchangeable:
  for +authorization: Maybe<&2, T.Nullable<String>>
  for +apiKey: Maybe<&2, T.Nullable<String>>
  {Request.authenticationAllowed(authorization, apiKey) == Request.authenticationAllowed(apiKey, authorization) : Bool}

law nonempty_credential_allows_authentication:
  for head: Char
  for tail: String
  for other: Maybe<&2, T.Nullable<String>>
  {Request.authenticationAllowed(Some{T.PresentValue{SCon{head, tail}}}, other) == True{} : Bool}

law absent_credentials_are_rejected:
  {Request.authenticationAllowed(None{}, None{}) == False{} : Bool}

law timeout_failure_bypasses_header_construction:
  for configuration: Request.Defaults
  for apiKey: String
  for retryCount: Nat
  for client: Maybe<&2, T.ProviderHeaders()>
  for body: Maybe<&2, T.ProviderHeaders()>
  for request: Maybe<&2, T.ProviderHeaders()>
  for cause: Request.Error
  {Request.validated(configuration, apiKey, retryCount, client, body, request, Fail{cause}) == Fail{cause} : Result<&2, &2, Request.Error, Headers.Headers>}
