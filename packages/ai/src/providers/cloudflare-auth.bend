import Base
import ../types.bend as T
import ../auth/types.bend as Auth
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/abort.bend as Abort

# upstream providers/cloudflare-auth.ts. Workers AI authenticates with the API
# key; AI Gateway sends it as cf-aig-authorization and removes the SDKs'
# Authorization and x-api-key headers. Both publish the account (and gateway)
# id as provider env, from which cloudflare-stream.bend materializes the
# endpoint. Upstream's interactive `login` is not ported: Bend's ApiKeyAuth
# has no login flow for any provider yet.

type CloudflareAuthKind is Data:
  WorkersAI{}
  AIGateway{}

def CLOUDFLARE_API_KEY() -> String: "CLOUDFLARE_API_KEY"
def CLOUDFLARE_ACCOUNT_ID() -> String: "CLOUDFLARE_ACCOUNT_ID"
def CLOUDFLARE_GATEWAY_ID() -> String: "CLOUDFLARE_GATEWAY_ID"

def Lookup() -> Data: Result<&2, &2, String, Maybe<&2, String>>

def abortedError() -> String: "The operation was aborted"

# Per-field merge: prefer the credential value, fall back to ambient env. A
# credential carrying only the API key still picks up the account / gateway id
# from the environment. A present credential value, even an empty one, wins.
def envField(name: String, env: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, String>:
  match env:
    case None{}: None{}
    case Some{fields}: R.get(String, fields, name)

def fromCredential(+name: String, credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, env}}: Bool.pick(Maybe<&2, String>, String.eq(name, CLOUDFLARE_API_KEY()), key, envField(name, env))
    case _: None{}

def ambientChecked(value: Maybe<&2, String>, cancelled: Bool) -> Lookup():
  match cancelled:
    case True{}: Fail{abortedError()}
    case False{}: Done{value}

def ambient(context: Auth.AuthContext, name: String, +signal: Abort.AbortSignal<Unit>, cancelled: Bool) -> IO(Lookup()):
  match cancelled:
    case True{}: IO.pure(Lookup(), Fail{abortedError()})
    case False{}:
      do IO<Lookup()>:
        value : Maybe<&2, String> <- Auth.envValue(context, name)
        after : Bool <- Abort.aborted(Unit, signal)
        return ambientChecked(value, after)

def lookedUp(context: Auth.AuthContext, name: String, +signal: Abort.AbortSignal<Unit>, stored: Maybe<&2, String>) -> IO(Lookup()):
  match stored:
    case Some{value}: IO.pure(Lookup(), Done{Some{value}})
    case None{}:
      do IO<Lookup()>:
        cancelled : Bool <- Abort.aborted(Unit, signal)
        ambient(context, name, signal, cancelled)

def resolveValue(+name: String, context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Lookup()):
  lookedUp(context, name, signal, fromCredential(name, credential))

# The resolved auth, once every required field is nonempty.
def gatewayHeaders(apiKey: String) -> T.ProviderHeaders():
  R.Record{[R.Property{"cf-aig-authorization", T.PresentValue{"Bearer " ++ apiKey}}, R.Property{"Authorization", T.NullValue{}}, R.Property{"x-api-key", T.NullValue{}}]}

def source(stored: Bool) -> Maybe<&2, String>:
  Some{Bool.pick(String, stored, "stored credential", CLOUDFLARE_API_KEY())}

def resolved(kind: CloudflareAuthKind, apiKey: Maybe<&2, String>, accountId: Maybe<&2, String>, gatewayId: Maybe<&2, String>, stored: Bool) -> Maybe<&2, Auth.AuthResult>:
  match kind apiKey accountId gatewayId:
    case WorkersAI{} Some{SCon{k, ks}} Some{SCon{a, as}} _:
      Some{Auth.AuthResult{Auth.ModelAuth{Some{SCon{k, ks}}, None{}, None{}}, Some{R.Record{[R.Property{CLOUDFLARE_ACCOUNT_ID(), SCon{a, as}}]}}, source(stored)}}
    case AIGateway{} Some{SCon{k, ks}} Some{SCon{a, as}} Some{SCon{g, gs}}:
      Some{Auth.AuthResult{Auth.ModelAuth{None{}, Some{gatewayHeaders(SCon{k, ks})}, None{}}, Some{R.Record{[R.Property{CLOUDFLARE_ACCOUNT_ID(), SCon{a, as}}, R.Property{CLOUDFLARE_GATEWAY_ID(), SCon{g, gs}}]}}, source(stored)}}
    case _ _ _ _: None{}

# Values are resolved in order (key, account, gateway) and the first failure
# (an abort) ends resolution.
def withGateway(kind: CloudflareAuthKind, apiKey: Maybe<&2, String>, accountId: Maybe<&2, String>, stored: Bool, gatewayId: Lookup()) -> Auth.AuthOutcome():
  match gatewayId:
    case Fail{cause}: Fail{cause}
    case Done{gateway}: Done{resolved(kind, apiKey, accountId, gateway, stored)}

def withAccount(context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>, apiKey: Maybe<&2, String>, kind: CloudflareAuthKind, accountId: Lookup()) -> IO(Auth.AuthOutcome()):
  match kind accountId:
    case _ Fail{cause}: IO.pure(Auth.AuthOutcome(), Fail{cause})
    case WorkersAI{} Done{account}: IO.pure(Auth.AuthOutcome(), Done{resolved(WorkersAI{}, apiKey, account, None{}, Maybe.is_some(&2, Auth.Credential, credential))})
    case AIGateway{} Done{account}:
      +stored = Maybe.is_some(&2, Auth.Credential, credential)
      do IO<Auth.AuthOutcome()>:
        gateway : Lookup() <- resolveValue(CLOUDFLARE_GATEWAY_ID(), context, credential, signal)
        return withGateway(AIGateway{}, apiKey, account, stored, gateway)

def withKey(kind: CloudflareAuthKind, +context: Auth.AuthContext, +credential: Maybe<&2, Auth.Credential>, +signal: Abort.AbortSignal<Unit>, apiKey: Lookup()) -> IO(Auth.AuthOutcome()):
  match apiKey:
    case Fail{cause}: IO.pure(Auth.AuthOutcome(), Fail{cause})
    case Done{key}:
      do IO<Auth.AuthOutcome()>:
        account : Lookup() <- resolveValue(CLOUDFLARE_ACCOUNT_ID(), context, credential, signal)
        withAccount(context, credential, signal, key, kind, account)

def resolveCloudflareEnv(kind: CloudflareAuthKind, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match input:
    case Auth.ResolveInput{+context, +credential, +signal}:
      do IO<Auth.AuthOutcome()>:
        apiKey : Lookup() <- resolveValue(CLOUDFLARE_API_KEY(), context, credential, signal)
        withKey(kind, context, credential, signal, apiKey)

def cloudflareAuth(kind: CloudflareAuthKind) -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~CloudflareAuthKind, ~Auth.ResolveInput, ~(Auth.AuthOutcome()), ~resolveCloudflareEnv, kind)
    return Auth.ApiKeyAuth{"Cloudflare API key", resolve}

def cloudflareWorkersAIAuth() -> IO(Auth.ApiKeyAuth): cloudflareAuth(WorkersAI{})

def cloudflareAIGatewayAuth() -> IO(Auth.ApiKeyAuth): cloudflareAuth(AIGateway{})
