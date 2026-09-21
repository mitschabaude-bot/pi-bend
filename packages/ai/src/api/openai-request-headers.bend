import Base
import ../types.bend as T
import ../utils/provider-headers.bend as Configuration
import ../utils/provider-header-state.bend as State
import ../../../runtime/src/http-header.bend as H
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64-decimal.bend as Decimal

# Runtime identity/platform fields are supplied by the native client; they do
# not claim that Bend is JavaScript or inherit a test oracle's Node version.
type Defaults is Data:
  Defaults{userAgent: String, platform: R.Record<String>, organization: Maybe<&2, String>, project: Maybe<&2, String>}

type Error is Data:
  TimeoutNotInteger{value: F.F64}
  TimeoutNegative{value: F.F64}
  TimeoutEncodingFailure{value: F.F64}
  HeaderFailure{cause: H.HeaderError}
  MissingAuthentication{}

def nullable(value: Maybe<&2, String>) -> T.Nullable<String>:
  match value:
    case None{}: T.NullValue{}
    case Some{text}: T.PresentValue{text}

def effectiveTimeout(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case None{}: F.fromU32(600000)
    case Some{milliseconds}: milliseconds

def isNegative(value: Maybe<&2, Cmp>) -> Bool:
  match value:
    case Some{LT{}}: True{}
    case _: False{}

def checkedTimeout(+value: F.F64, integral: Bool) -> Result<&2, &2, Error, F.F64>:
  match integral:
    case False{}: Fail{TimeoutNotInteger{value}}
    case True{}: Bool.pick(Result<&2, &2, Error, F.F64>, isNegative(F.compare(value, F.fromU32(0))), Fail{TimeoutNegative{value}}, Done{value})

def validateTimeout(+value: F.F64) -> Result<&2, &2, Error, F.F64>:
  checkedTimeout(value, F.isInteger(value))

def encodedTimeout(value: F.F64, encoded: Maybe<&2, String>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match encoded:
    case None{}: Fail{TimeoutEncodingFailure{value}}
    case Some{text}: Done{Some{text}}

def timeoutField(+value: F.F64, ordering: Maybe<&2, Cmp>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match ordering:
    case Some{EQ{}}: Done{None{}}
    case _: encodedTimeout(value, Decimal.toDecimal(F.truncate(F.divide(value, F.fromU32(1000)))))

def optionalTimeout(fields: T.ProviderHeaders(), value: Maybe<&2, String>) -> T.ProviderHeaders():
  match value:
    case None{}: fields
    case Some{text}: R.set(T.Nullable<String>, fields, "X-Stainless-Timeout", T.PresentValue{text})

def defaults(configuration: Defaults, retryCount: Nat, timeout: Maybe<&2, String>) -> T.ProviderHeaders():
  match configuration:
    case Defaults{userAgent, platform, organization, project}:
      base = {R.Record{R.Property{"Accept", T.PresentValue{"application/json"}} <> R.Property{"User-Agent", T.PresentValue{userAgent}} <> R.Property{"X-Stainless-Retry-Count", T.PresentValue{Nat.show(retryCount)}} <> Nil{}} : T.ProviderHeaders()}
      decorated = Configuration.overlayStrings(optionalTimeout(base, timeout), Some{platform})
      R.set(T.Nullable<String>, R.set(T.Nullable<String>, decorated, "OpenAI-Organization", nullable(organization)), "OpenAI-Project", nullable(project))

def authorization(apiKey: String) -> T.ProviderHeaders():
  R.Record{R.Property{"Authorization", T.PresentValue{"Bearer " ++ apiKey}} <> Nil{}}

def credentialAllows(+value: Maybe<&2, T.Nullable<String>>) -> Bool:
  State.nonempty(value) || State.removed(value)

def authenticationAllowed(authorization: Maybe<&2, T.Nullable<String>>, apiKey: Maybe<&2, T.Nullable<String>>) -> Bool:
  credentialAllows(authorization) || credentialAllows(apiKey)

def authenticated(+state: State.State) -> Bool:
  authenticationAllowed(State.lookup(state, "authorization"), State.lookup(state, "api-key"))

def authenticate(state: State.State, accepted: Bool) -> Result<&2, &2, Error, Headers.Headers>:
  match accepted:
    case False{}: Fail{MissingAuthentication{}}
    case True{}: Done{State.headers(state)}

def assembled(result: Result<&2, &2, H.HeaderError, State.State>) -> Result<&2, &2, Error, Headers.Headers>:
  match result:
    case Fail{cause}: Fail{HeaderFailure{cause}}
    case Done{+state}: authenticate(state, authenticated(state))

def layered(configuration: Defaults, apiKey: String, retryCount: Nat, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>, timeout: Result<&2, &2, Error, Maybe<&2, String>>) -> Result<&2, &2, Error, Headers.Headers>:
  match timeout:
    case Fail{cause}: Fail{cause}
    case Done{value}: assembled(State.build(Some{defaults(configuration, retryCount, value)} <> Some{authorization(apiKey)} <> client <> body <> request <> Nil{}))

def validated(configuration: Defaults, apiKey: String, retryCount: Nat, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>, timeout: Result<&2, &2, Error, F.F64>) -> Result<&2, &2, Error, Headers.Headers>:
  match timeout:
    case Fail{cause}: Fail{cause}
    case Done{+value}: layered(configuration, apiKey, retryCount, client, body, request, timeoutField(value, F.compare(value, F.fromU32(0))))

# OpenAI SDK request order: defaults/platform, credentials, client defaults,
# serializer headers, per-request overrides, then authentication validation.
# Pi disables SDK retries, so its adapter supplies retryCount = 0.
def build(configuration: Defaults, apiKey: String, retryCount: Nat, timeout: Maybe<&2, F.F64>, client: Maybe<&2, T.ProviderHeaders()>, body: Maybe<&2, T.ProviderHeaders()>, request: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Error, Headers.Headers>:
  validated(configuration, apiKey, retryCount, client, body, request, validateTimeout(effectiveTimeout(timeout)))
