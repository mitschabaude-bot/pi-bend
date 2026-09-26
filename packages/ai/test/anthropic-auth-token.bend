import Base
import ../src/auth/types.bend as Auth
import ../src/models.bend as Models
import ../src/providers/anthropic.bend as Anthropic
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R

# pi-mono f07218c4d packages/ai/test/anthropic-auth-token.test.ts. upstream
# mocks the SDK constructor; natively the recording fetch observes the same
# request headers and body. The `createModels(...).streamSimple` cases need
# the Models registry's stream convenience, which is not ported.
def environment(values: R.Record<String>, name: String) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, R.get(String, values, name))

def noFiles(unused: Unit, path: String) -> IO(Bool): IO.pure(Bool, False{})

def resolveWith(provider: Models.Provider, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match provider:
    case Models.Provider{_, _, _, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, _, resolve}}, _}, _, _, _}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, input)
    case _: IO.pure(Auth.AuthOutcome(), Fail{"no api key auth"})

def env(entries: List<&2, R.Property<String>>) -> R.Record<String>: R.Record{entries}

def resolved(values: R.Record<String>) -> IO(Auth.AuthOutcome()):
  do IO<Auth.AuthOutcome()>:
    provider : Models.Provider <- Anthropic.anthropicProvider(None{})
    +env : C.Callback<String, Maybe<&2, String>> <- C.create(~R.Record<String>, ~String, ~Maybe<&2, String>, ~environment, values)
    +files : C.Callback<String, Bool> <- C.create(~Unit, ~String, ~Bool, ~noFiles, Unit{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    result : Auth.AuthOutcome() <- resolveWith(provider, Auth.ResolveInput{Auth.AuthContext{env, files}, None{}, Abort.signal(Unit, controller)})
    Abort.dispose(Unit, controller)
    return result

def bearerResult(outcome: Auth.AuthOutcome()) -> Bool:
  match outcome:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{None{}, Some{R.Record{R.Property{"Authorization", T.PresentValue{"Bearer auth-token"}} <> Nil{}}}, None{}}, None{}, Some{"ANTHROPIC_AUTH_TOKEN"}}}}: True{}
    case _: False{}

def keyResult(outcome: Auth.AuthOutcome()) -> Bool:
  match outcome:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{"oauth-token"}, None{}, None{}}, None{}, Some{"ANTHROPIC_OAUTH_TOKEN"}}}}: True{}
    case _: False{}

def authToken() -> IO(Unit):
  +name = {"resolves ANTHROPIC_AUTH_TOKEN as a bearer Authorization header" : String}
  do IO<Unit>:
    outcome : Auth.AuthOutcome() <- resolved(env(R.Property{"ANTHROPIC_AUTH_TOKEN", "auth-token"} <> R.Property{"ANTHROPIC_OAUTH_TOKEN", "oauth-token"} <> R.Property{"ANTHROPIC_API_KEY", "api-key"} <> Nil{}))
    H.check(bearerResult(outcome), name)
    H.pass(name)

def oauthToken() -> IO(Unit):
  +name = {"preserves ANTHROPIC_OAUTH_TOKEN as OAuth-shaped API auth" : String}
  do IO<Unit>:
    outcome : Auth.AuthOutcome() <- resolved(env(R.Property{"ANTHROPIC_OAUTH_TOKEN", "oauth-token"} <> R.Property{"ANTHROPIC_API_KEY", "api-key"} <> Nil{}))
    H.check(keyResult(outcome), name)
    H.pass(name)

def model(+id: String, provider: String, base: String) -> T.Model<T.JsonValue>:
  T.Model{id, id, T.AnthropicMessagesApi{}, provider, base, False{}, None{}, T.InputText{} <> Nil{}, None{}, H.zeroCost(), None{}, F.fromU32(100000), F.fromU32(4096), None{}, None{}, None{}}

def anthropicModel() -> T.Model<T.JsonValue>: model("claude-test", "anthropic", "https://api.anthropic.com")

def kimiCodingModel() -> T.Model<T.JsonValue>: model("kimi-for-coding", "kimi-coding", "https://api.kimi.com/coding")

def context() -> H.Context(): H.contextWith(Some{"System prompt."}, H.user("Hello", 1) <> Nil{}, None{})

def send(+selected: T.Model<T.JsonValue>, apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, mode: H.Mode) -> IO(H.Outcome):
  H.run(selected, context(), H.direct(H.streamOptions(apiKey, None{}, headers), None{}, None{}), mode)

def textOf(value: Maybe<&2, T.JsonValue>, rest: List<&2, String>) -> List<&2, String>:
  match value:
    case Some{T.JsonString{text}}: text <> rest
    case _: rest

def systemTexts(values: List<&2, T.JsonValue>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: textOf(H.fieldOf(Some{value}, "text"), systemTexts(rest))

def strings(values: List<&2, String>) -> List<&2, T.JsonValue>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: T.JsonString{value} <> strings(rest)

def headerAuth() -> IO(Unit):
  +name = {"uses Authorization headers without OAuth-mode request shaping" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- send(anthropicModel(), None{}, Some{H.headersOf(H.present("Authorization", "Bearer gateway-token") <> Nil{})}, H.Send{})
    +request : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, H.requestBody(H.requestOf(outcome)))
    H.equalText(H.header(H.requestOf(outcome), "x-api-key"), None{}, name ++ ": apiKey")
    H.equalText(H.header(H.requestOf(outcome), "authorization"), Some{"Bearer gateway-token"}, name ++ ": Authorization")
    H.check(Bool.not(H.contains(H.header(H.requestOf(outcome), "anthropic-beta"), "oauth-2025-04-20")), name ++ ": no OAuth beta")
    H.check(Bool.not(H.containsString(H.elements(H.fieldOf(request, "betas")), "oauth-2025-04-20")), name ++ ": no OAuth beta in body")
    H.equalJson(Some{T.JsonArray{strings(systemTexts(H.elements(H.fieldOf(request, "system"))))}}, "[\"System prompt.\"]", name ++ ": system")
    H.pass(name)

def defaultAgent() -> IO(Unit):
  +name = {"uses pi's User-Agent by default for Anthropic Messages requests" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- send(anthropicModel(), Some{"anthropic-key"}, None{}, H.Send{})
    +agent : String <- H.piUserAgent()
    H.check(String.starts_with(agent, "pi ("), name ++ ": pi identity " ++ agent)
    H.equalText(H.header(H.requestOf(outcome), "user-agent"), Some{agent}, name)
    H.pass(name)

def customAgent() -> IO(Unit):
  +name = {"lets explicit headers override the default Anthropic Messages User-Agent" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- send(kimiCodingModel(), Some{"kimi-key"}, Some{H.headersOf(H.present("User-Agent", "custom-client") <> Nil{})}, H.Send{})
    H.equalText(H.header(H.requestOf(outcome), "user-agent"), Some{"custom-client"}, name)
    H.pass(name)

def replacedBeta() -> IO(Unit):
  +name = {"preserves explicit Anthropic beta header replacement" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- send(anthropicModel(), Some{"anthropic-key"}, Some{H.headersOf(H.present("anthropic-beta", "custom-beta") <> Nil{})}, H.Capture{})
    H.equalJson(H.fieldOf(H.payloadOf(outcome), "betas"), "[\"custom-beta\"]", name)
    H.pass(name)

def suppressedBeta() -> IO(Unit):
  +name = {"preserves explicit Anthropic beta header suppression" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- send(anthropicModel(), Some{"anthropic-key"}, Some{H.headersOf(H.removed("anthropic-beta") <> Nil{})}, H.Capture{})
    H.check(Maybe.is_some(&2, T.JsonValue, H.payloadOf(outcome)), name ++ ": payload captured")
    H.absent(H.fieldOf(H.payloadOf(outcome), "betas"), name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    authToken()
    oauthToken()
    headerAuth()
    defaultAgent()
    customAgent()
    replacedBeta()
    suppressedBeta()
