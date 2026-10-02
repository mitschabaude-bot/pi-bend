import Base
import ../src/auth/types.bend as Auth
import ../src/auth/resolve.bend as Resolve
import ../src/api/options.bend as Options
import ../src/api/lazy.bend as Lazy
import ../src/models.bend as Models
import ../src/providers/anthropic.bend as Anthropic
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/anthropic-auth-token.test.ts. upstream
# mocks the SDK constructor; natively the recording fetch observes the same
# request headers and body. Collection cases pass through Models.streamSimple,
# capture its provider dispatch, then send those applied options through the
# same real Anthropic request path.
def environment(values: R.Record<String>, name: String) -> IO(Maybe<&2, String>): IO.pure(Maybe<&2, String>, R.get(String, values, name))

def noFiles(unused: Unit, path: String) -> IO(Bool): IO.pure(Bool, False{})

def resolveWith(provider: Models.Provider, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match provider:
    case Models.Provider{_, _, _, Auth.ProviderAuth{Some{Auth.ApiKeyAuth{_, _, resolve, _}}, _}, _, _, _, _}: C.call(Auth.ResolveInput, Auth.AuthOutcome(), resolve, input)
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

def collectionContext() -> T.Context<V.Value, V.Value, V.Value, V.Value>:
  T.Context{Some{"System prompt."}, T.User{T.UserMessage{T.UserText{"Hello"}, F.fromU32(1)}} <> Nil{}, None{}}

def send(+selected: T.Model<T.JsonValue>, apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, mode: H.Mode) -> IO(H.Outcome):
  H.run(selected, context(), H.direct(H.streamOptions(apiKey, None{}, headers), None{}, None{}), mode)

type Applied is Data:
  Applied{apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>}

def capture(slot: Ref.Ref<Maybe<&2, Models.StreamInput>>, input: Models.StreamInput) -> IO(Lazy.OpenResult()):
  do IO<Lazy.OpenResult()>:
    Ref.write(Maybe<&2, Models.StreamInput>, slot, Some{input})
    return Fail{Resolve.ModelsError{Resolve.ProviderError{}, "request captured"}}

def withStreams(+provider: Models.Provider, raw: Models.ProviderStream(), simple: Models.ProviderStream()) -> Models.Provider:
  match provider:
    case Models.Provider{id, name, base, auth, models, _, refresh, filter}:
      Models.Provider{id, name, base, auth, models, Models.NativeStreams{[T.AnthropicMessagesApi{}], raw, simple}, refresh, filter}

def requestOptions(headers: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, Models.ModelsSimpleStreamOptions()>:
  match headers:
    case None{}: None{}
    case Some{values}: Some{Models.ModelsRequestOptions{T.SimpleStreamOptions{None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}, None{}}}

def appliedBase(base: Options.BaseOptions(Resolve.ModelsError)) -> IO(Applied):
  match base:
    case T.StreamOptions{_, _, key, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _}: IO.pure(Applied, Applied{key, headers})

def applied(input: Maybe<&2, Models.StreamInput>) -> IO(Applied):
  match input:
    case Some{Models.StreamInput{_, _, options}}: appliedBase(Options.requestBase(Resolve.ModelsError, options))
    case None{}: IO.die(Applied, 1, "Models.streamSimple did not dispatch the provider")

def sendApplied(selected: Applied) -> IO(H.Outcome):
  match selected:
    case Applied{key, headers}: send(anthropicModel(), key, headers, H.Send{})

def collectionSend(+values: R.Record<String>, headers: Maybe<&2, T.ProviderHeaders()>) -> IO(H.Outcome):
  do IO<H.Outcome>:
    +envCallback : C.Callback<String, Maybe<&2, String>> <- C.create(~R.Record<String>, ~String, ~Maybe<&2, String>, ~environment, values)
    +files : C.Callback<String, Bool> <- C.create(~Unit, ~String, ~Bool, ~noFiles, Unit{})
    +models : Models.Models <- Models.createModels(Models.CreateModelsOptions{None{}, None{}, Some{Auth.AuthContext{envCallback, files}}})
    +slot : Ref.Ref<Maybe<&2, Models.StreamInput>> <- Ref.new(Maybe<&2, Models.StreamInput>, None{})
    +raw : Models.ProviderStream() <- C.create(~Ref.Ref<Maybe<&2, Models.StreamInput>>, ~Models.StreamInput, ~Lazy.OpenResult(), ~capture, slot)
    +simple : Models.ProviderStream() <- C.create(~Ref.Ref<Maybe<&2, Models.StreamInput>>, ~Models.StreamInput, ~Lazy.OpenResult(), ~capture, slot)
    +provider : Models.Provider <- Anthropic.anthropicProvider(None{})
    +routed : Models.Provider = withStreams(provider, raw, simple)
    Models.setProvider(models, routed)
    ignored : Lazy.Message() <- Models.completeSimple(models, anthropicModel(), collectionContext(), requestOptions(headers))
    seen : Maybe<&2, Models.StreamInput> <- Ref.read(Maybe<&2, Models.StreamInput>, slot)
    selected : Applied <- applied(seen)
    Models.disposeModels(models)
    Models.disposeProvider(routed)
    C.dispose(Models.StreamInput, Lazy.OpenResult(), raw)
    C.dispose(Models.StreamInput, Lazy.OpenResult(), simple)
    previous : Maybe<&2, Models.StreamInput> <- Ref.dispose(Maybe<&2, Models.StreamInput>, slot)
    sendApplied(selected)

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

def contextualAuthToken() -> IO(Unit):
  +name = {"threads authContext ANTHROPIC_AUTH_TOKEN through request headers" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- collectionSend(env([R.Property{"ANTHROPIC_AUTH_TOKEN", "ctx-token"}]), None{})
    +request : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, H.requestBody(H.requestOf(outcome)))
    H.equalText(H.header(H.requestOf(outcome), "x-api-key"), None{}, name ++ ": apiKey")
    H.equalText(H.header(H.requestOf(outcome), "authorization"), Some{"Bearer ctx-token"}, name ++ ": Authorization")
    H.check(Bool.not(H.contains(H.header(H.requestOf(outcome), "anthropic-beta"), "oauth-2025-04-20")), name ++ ": no OAuth beta")
    H.equalJson(Some{T.JsonArray{strings(systemTexts(H.elements(H.fieldOf(request, "system"))))}}, "[\"System prompt.\"]", name ++ ": system")
    H.pass(name)

def contextualOAuthToken() -> IO(Unit):
  +name = {"preserves OAuth request shaping for ANTHROPIC_OAUTH_TOKEN" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- collectionSend(env([R.Property{"ANTHROPIC_OAUTH_TOKEN", "sk-ant-oat-test"}]), None{})
    H.equalText(H.header(H.requestOf(outcome), "x-api-key"), None{}, name ++ ": apiKey")
    H.equalText(H.header(H.requestOf(outcome), "authorization"), Some{"Bearer sk-ant-oat-test"}, name ++ ": authToken")
    H.check(H.contains(H.header(H.requestOf(outcome), "anthropic-beta"), "oauth-2025-04-20"), name ++ ": OAuth header beta")
    H.pass(name)

def explicitOverContextualAuth() -> IO(Unit):
  +name = {"lets explicit request headers override ANTHROPIC_AUTH_TOKEN" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- collectionSend(env([R.Property{"ANTHROPIC_AUTH_TOKEN", "ctx-token"}]), Some{H.headersOf([H.present("Authorization", "Bearer explicit-token")])})
    H.equalText(H.header(H.requestOf(outcome), "authorization"), Some{"Bearer explicit-token"}, name)
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
    contextualAuthToken()
    contextualOAuthToken()
    explicitOverContextualAuth()
    defaultAgent()
    customAgent()
    replacedBeta()
    suppressedBeta()
