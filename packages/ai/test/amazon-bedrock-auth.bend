import Base
import ../src/types.bend as T
import ../src/auth/types.bend as Auth
import ../src/providers/amazon-bedrock.bend as Bedrock
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R
import ../src/models.bend as Models

# The Bedrock resolve cases of upstream providers.test.ts ("builtin
# providers") plus native cases for the credential-source order of
# providers/amazon-bedrock.ts. Upstream "reports bedrock as configured from
# ambient AWS credentials" resolves through createModels().getAuth with a fake
# auth context; without a stored credential getAuth returns resolve's result,
# so these cases call ApiKeyAuth.resolve with the same context. The login half
# of "runs provider-owned Bedrock bearer token and AWS profile login flows"
# needs select prompts and notify events, which LoginInteraction does not
# model; only its resolve assertion is ported.
# Results render as `key|headers|env|source` (`-` for absent).

def Env() -> Data: R.Record<String>

def lookup(env: Env(), name: String) -> IO(Maybe<&2, String>):
  IO.pure(Maybe<&2, String>, R.get(String, env, name))

def exists(env: Env(), path: String) -> IO(Bool): IO.pure(Bool, False{})

def fakeAuthContext(env: Env()) -> IO(Auth.AuthContext):
  do IO<Auth.AuthContext>:
    +values : Env() <- IO.pure(Env(), env)
    environment : C.Callback<String, Maybe<&2, String>> <- C.create(~Env(), ~String, ~Maybe<&2, String>, ~lookup, values)
    exists : C.Callback<String, Bool> <- C.create(~Env(), ~String, ~Bool, ~exists, values)
    return Auth.AuthContext{environment, exists}

def vars(entries: List<&2, R.Property<String>>) -> Env(): R.Record{entries}

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: text

def headerValue(value: T.Nullable<String>) -> String:
  match value:
    case T.NullValue{}: "null"
    case T.PresentValue{text}: text

def headerList(entries: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ ":" ++ headerValue(value)) <> headerList(rest)

def envList(entries: List<&2, R.Property<String>>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (name ++ "=" ++ value) <> envList(rest)

def headersText(headers: Maybe<&2, T.ProviderHeaders()>) -> String:
  match headers:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(headerList(entries), ",")

def envText(env: Maybe<&2, T.ProviderEnv()>) -> String:
  match env:
    case None{}: "-"
    case Some{R.Record{entries}}: String.join(envList(entries), ",")

def rendered(outcome: Auth.AuthOutcome()) -> String:
  match outcome:
    case Fail{message}: "error:" ++ message
    case Done{None{}}: "undefined"
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, headers, _}, env, source}}}:
      optional(key) ++ "|" ++ headersText(headers) ++ "|" ++ envText(env) ++ "|" ++ optional(source)

def resolveWith(auth: Auth.ApiKeyAuth, context: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.AuthOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_, _, resolve}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, Auth.ResolveInput{context, credential, signal})

def resolvedText(auth: IO(Auth.ApiKeyAuth), env: Env(), credential: Maybe<&2, Auth.Credential>, cancel: Bool) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- auth
    context : Auth.AuthContext <- fakeAuthContext(env)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Bool.pick(IO(Bool), cancel, Abort.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    outcome : Auth.AuthOutcome() <- resolveWith(selected, context, credential, Abort.signal(Unit, controller))
    Abort.dispose(Unit, controller)
    return rendered(outcome)

def expect(+name: String, actual: IO(String), +expected: String) -> IO(Unit):
  do IO<Unit>:
    +value : String <- actual
    Bool.pick(IO(Unit), String.eq(value, expected), IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name ++ ": " ++ value ++ " != " ++ expected))

def apiKeyAuth(provider: Models.Provider) -> IO(Auth.ApiKeyAuth):
  match provider:
    case Models.Provider{_, _, _, Auth.ProviderAuth{Some{auth}, _}, _, _, _}: IO.pure(Auth.ApiKeyAuth, auth)
    case _: IO.die(Auth.ApiKeyAuth, 1, "amazon-bedrock has no api key auth")

def bedrock() -> IO(Auth.ApiKeyAuth):
  do IO<Auth.ApiKeyAuth>:
    provider : Models.Provider <- Bedrock.amazonBedrockProvider()
    apiKeyAuth(provider)

def var(name: String, value: String) -> R.Property<String>: R.Property{name, value}

def stored(value: Maybe<&2, String>, env: Maybe<&2, T.ProviderEnv()>) -> Maybe<&2, Auth.Credential>:
  Some{Auth.ApiKeyCredential{value, env}}

def profileEnv(name: String) -> Maybe<&2, T.ProviderEnv()>: Some{R.Record{[var("AWS_PROFILE", name)]}}

def main() -> IO(Unit):
  do IO<Unit>:
    expect("runs provider-owned Bedrock bearer token and AWS profile login flows (stored profile resolve)", resolvedText(bedrock(), vars(Nil{}), stored(None{}, profileEnv("work")), False{}), "-|-|AWS_PROFILE=work|stored credential")
    expect("reports bedrock as configured from ambient AWS credentials without an api key", resolvedText(bedrock(), vars([var("AWS_PROFILE", "dev")]), None{}, False{}), "-|-|-|AWS_PROFILE")
    expect("reports bedrock as configured from ambient AWS credentials without an api key (unconfigured)", resolvedText(bedrock(), vars(Nil{}), None{}, False{}), "undefined")
    expect("a stored bearer token wins with its env", resolvedText(bedrock(), vars([var("AWS_BEARER_TOKEN_BEDROCK", "ambient")]), stored(Some{"token"}, profileEnv("work")), False{}), "token|-|AWS_PROFILE=work|stored credential")
    expect("an ambient bearer token precedes profiles", resolvedText(bedrock(), vars([var("AWS_BEARER_TOKEN_BEDROCK", "t"), var("AWS_PROFILE", "dev")]), None{}, False{}), "-|-|-|AWS_BEARER_TOKEN_BEDROCK")
    expect("an empty stored key falls through to the environment", resolvedText(bedrock(), vars([var("AWS_PROFILE", "dev")]), stored(Some{""}, None{}), False{}), "-|-|-|AWS_PROFILE")
    expect("an empty stored profile skips the ambient profile", resolvedText(bedrock(), vars([var("AWS_PROFILE", "dev")]), stored(None{}, profileEnv("")), False{}), "undefined")
    expect("access keys need both halves", resolvedText(bedrock(), vars([var("AWS_ACCESS_KEY_ID", "a")]), None{}, False{}), "undefined")
    expect("access keys", resolvedText(bedrock(), vars([var("AWS_ACCESS_KEY_ID", "a"), var("AWS_SECRET_ACCESS_KEY", "s")]), None{}, False{}), "-|-|-|AWS access keys")
    expect("ECS relative uri", resolvedText(bedrock(), vars([var("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2")]), None{}, False{}), "-|-|-|ECS task role")
    expect("ECS full uri", resolvedText(bedrock(), vars([var("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://x")]), None{}, False{}), "-|-|-|ECS task role")
    expect("web identity token file", resolvedText(bedrock(), vars([var("AWS_WEB_IDENTITY_TOKEN_FILE", "/t")]), None{}, False{}), "-|-|-|web identity token")
    expect("empty environment values do not count", resolvedText(bedrock(), vars([var("AWS_BEARER_TOKEN_BEDROCK", ""), var("AWS_PROFILE", "")]), None{}, False{}), "undefined")
    expect("an aborted signal stops an environment lookup", resolvedText(bedrock(), vars([var("AWS_PROFILE", "dev")]), None{}, True{}), "error:The operation was aborted")
    expect("a stored key needs no environment lookup under an aborted signal", resolvedText(bedrock(), vars(Nil{}), stored(Some{"token"}, None{}), True{}), "token|-|-|stored credential")
