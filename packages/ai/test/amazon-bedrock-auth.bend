import Base
import ../src/types.bend as T
import ../src/auth/types.bend as Auth
import ../src/providers/amazon-bedrock.bend as Bedrock
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/record.bend as R
import ../src/models.bend as Models
import ../../runtime/src/ref.bend as Ref

# The Bedrock resolve cases of upstream providers.test.ts ("builtin
# providers") plus native cases for the credential-source order of
# providers/amazon-bedrock.ts. Upstream "reports bedrock as configured from
# ambient AWS credentials" resolves through createModels().getAuth with a fake
# auth context; without a stored credential getAuth returns resolve's result,
# so these cases call ApiKeyAuth.resolve with the same context. The login half
# of "runs provider-owned Bedrock bearer token and AWS profile login flows"
# answers the prompts from a queue and records every prompt and event;
# login results render as `key|env`.
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

# Login
# -----

type Script is Data:
  Script{answers: Ref.Ref<List<&2, String>>, log: Ref.Ref<List<&2, String>>}

def optionIds(options: List<&2, Auth.AuthSelectOption>) -> List<&2, String>:
  match options:
    case Nil{}: Nil{}
    case Auth.AuthSelectOption{id, label, _} <> rest: (id ++ "=" ++ label) <> optionIds(rest)

def promptText(prompt: Auth.AuthPrompt) -> String:
  match prompt:
    case Auth.TextPrompt{message, _, _}: "text:" ++ message
    case Auth.SecretPrompt{message, _, _}: "secret:" ++ message
    case Auth.SelectPrompt{message, options, _}: "select:" ++ message ++ "[" ++ String.join(optionIds(options), ",") ++ "]"
    case Auth.ManualCodePrompt{message, _, _}: "code:" ++ message

def appended(+line: String, list: List<&2, String>) -> List<&2, String> & Unit: (List.append(&2, String, list, [line]), Unit{})

def popped(list: List<&2, String>) -> List<&2, String> & Result<&2, &2, String, String>:
  match list:
    case Nil{}: (Nil{}, Fail{"no scripted answer"})
    case next <> rest: (rest, Done{next})

def answer(script: Script, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match script:
    case Script{answers, log}:
      do IO<Result<&2, &2, String, String>>:
        Ref.modify(List<&2, String>, Unit, log, list => appended(promptText(prompt), list))
        Ref.modify(List<&2, String>, Result<&2, &2, String, String>, answers, popped)

def optionalText(value: Maybe<&2, String>) -> String:
  match value:
    case Some{text}: text
    case None{}: "-"

def linkLabels(links: List<&2, Auth.AuthInfoLink>) -> List<&2, String>:
  match links:
    case Nil{}: Nil{}
    case Auth.AuthInfoLink{_, label} <> rest: optionalText(label) <> linkLabels(rest)

def eventText(event: Auth.AuthEvent) -> String:
  match event:
    case Auth.InfoEvent{_, links}: "info[" ++ String.join(linkLabels(links), ",") ++ "]"
    case _: "other"

def record(script: Script, event: Auth.AuthEvent) -> IO(Unit):
  match script:
    case Script{_, log}: Ref.modify(List<&2, String>, Unit, log, list => appended(eventText(event), list))

def loginResult(result: Auth.LoginOutcome()) -> String:
  match result:
    case Fail{reason}: "error:" ++ reason
    case Done{Auth.ApiKeyCredential{key, env}}: optional(key) ++ "|" ++ envText(env)
    case Done{_}: "wrong credential type"

def callLogin(auth: Auth.ApiKeyAuth, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match auth:
    case Auth.ApiKeyAuth{_, Some{callback}, _}: C.call(Auth.ProviderAuthInteraction, Auth.LoginOutcome(), callback, interaction)
    case _: IO.pure(Auth.LoginOutcome(), Fail{"login unavailable"})

def loginText(answers: List<&2, String>, cancel: Bool) -> IO(String):
  do IO<String>:
    selected : Auth.ApiKeyAuth <- bedrock()
    +queue : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, answers)
    +log : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Bool.pick(IO(Bool), cancel, Abort.abort(Unit, controller, None{}), IO.pure(Bool, False{}))
    prompt : C.Callback<Auth.AuthPrompt, Result<&2, &2, String, String>> <- C.create(~Script, ~Auth.AuthPrompt, ~Result<&2, &2, String, String>, ~answer, Script{queue, log})
    notify : C.Callback<Auth.AuthEvent, Unit> <- C.create(~Script, ~Auth.AuthEvent, ~Unit, ~record, Script{queue, log})
    result : Auth.LoginOutcome() <- callLogin(selected, Auth.ProviderAuthInteraction{Abort.signal(Unit, controller), prompt, notify})
    lines : List<&2, String> <- Ref.read(List<&2, String>, log)
    Abort.dispose(Unit, controller)
    return loginResult(result) ++ " / " ++ String.join(lines, " ; ")

def selectLine() -> String: "select:Select Amazon Bedrock authentication method:[bearer-token=Bearer token,aws-profile=AWS profile,credential-chain=Existing AWS credential chain]"

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
    expect("runs provider-owned Bedrock bearer token and AWS profile login flows (bearer token)", loginText(["bearer-token", "bedrock-token"], False{}), "bedrock-token|- / " ++ selectLine() ++ " ; secret:Enter Amazon Bedrock bearer token")
    expect("runs provider-owned Bedrock bearer token and AWS profile login flows (AWS profile)", loginText(["aws-profile", "work"], False{}), "-|AWS_PROFILE=work / " ++ selectLine() ++ " ; info[AWS credential provider chain] ; text:Enter AWS profile name")
    expect("the credential-chain login stores an empty api key credential", loginText(["credential-chain", ""], False{}), "-|- / " ++ selectLine() ++ " ; info[AWS credential provider chain] ; text:Configure AWS credentials, then press Enter to continue")
    expect("an unknown login method is rejected after the notice", loginText(["other"], False{}), "error:Unknown Amazon Bedrock auth method: other / " ++ selectLine() ++ " ; info[AWS credential provider chain]")
    expect("an aborted login asks nothing", loginText(["bearer-token", "x"], True{}), "error:The operation was aborted / ")
