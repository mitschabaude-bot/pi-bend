import Base
import ./client.bend as Client
import ../../../../ai/src/models.bend as Models
import ../../../../ai/src/models-store.bend as Store
import ../../../../ai/src/types.bend as T
import ../../../../ai/src/auth/types.bend as Auth
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/date.bend as Date
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/url.bend as URL

def LLAMA_PROVIDER_ID() -> String: "llama.cpp"
def DEFAULT_LLAMA_SERVER_URL() -> String: "http://127.0.0.1:8080"
def Model() -> Data: T.Model<T.JsonValue>

type Transport is Data:
  Transport{fetch: Fetch.Fetch(Unit), urlContext: URL.Context, environment: Auth.AuthContext}

type LlamaProviderController is Data:
  LlamaProviderController{provider: Models.Provider}

def selectable(model: Client.LlamaModelInfo, autoload: Bool) -> Bool:
  match model:
    case Client.LlamaModelInfo{_, _, Client.Status{Client.Loaded{}, _, _, _, _}, _, _, _}: True{}
    case Client.LlamaModelInfo{_, _, Client.Status{Client.Sleeping{}, _, _, _, _}, _, _, _}: True{}
    case Client.LlamaModelInfo{_, _, Client.Status{Client.Unloaded{}, _, failed, _, _}, _, Some{"preset"}, _}: autoload && Bool.not(Maybe.default(&2, Bool, failed, False{}))
    case _: False{}

def hasImage(values: List<&2, String>) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value, "image") || hasImage(rest)

def imageInput(architecture: Maybe<&2, Client.Architecture>) -> Bool:
  match architecture:
    case Some{Client.Architecture{Some{values}, _}}: hasImage(values)
    case _: False{}

def positiveWindow(value: Maybe<&2, F64>) -> F64:
  match value:
    case Some{+size}: Bool.pick(F64, F64.is_gt(size, F.fromU32(0)), size, F.fromU32(128000))
    case None{}: F.fromU32(128000)

def window(meta: Maybe<&2, Client.Metadata>) -> F64:
  match meta:
    case Some{Client.Metadata{current, trained, _, _}}: positiveWindow(Maybe.or(&2, F64, current, trained))
    case None{}: F.fromU32(128000)

def thinkingLevels() -> T.ThinkingLevelMap:
  T.ThinkingLevelMap{[T.ThinkingLevelMapping{T.Off{}, Some{T.PresentValue{"off"}}}, T.ThinkingLevelMapping{T.Thinking{T.Minimal{}}, Some{T.NullValue{}}}, T.ThinkingLevelMapping{T.Thinking{T.Low{}}, Some{T.NullValue{}}}, T.ThinkingLevelMapping{T.Thinking{T.Medium{}}, Some{T.PresentValue{"medium"}}}, T.ThinkingLevelMapping{T.Thinking{T.High{}}, Some{T.NullValue{}}}, T.ThinkingLevelMapping{T.Thinking{T.XHigh{}}, Some{T.NullValue{}}}]}

def compatibility(enabled: Bool) -> T.OpenAICompletionsCompat:
  T.OpenAICompletionsCompat{Some{False{}}, Some{False{}}, Some{False{}}, Some{True{}}, None{}, Some{T.MaxTokens{}}, None{}, None{}, None{}, None{}, Bool.pick(Maybe<&2, T.ThinkingFormat>, enabled, Some{T.QwenChatTemplateThinking{}}, None{}), None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{False{}}, None{}, None{}, None{}, None{}, None{}}

def reasoning(props: Maybe<&2, Client.LlamaServerProps>) -> Bool:
  match props:
    case Some{Client.LlamaServerProps{_, Some{template}}}: String.contains(template, "enable_thinking")
    case _: False{}

def toPiModel(model: Client.LlamaModelInfo, +serverUrl: String, props: Maybe<&2, Client.LlamaServerProps>) -> Model():
  match model:
    case Client.LlamaModelInfo{+id, _, _, arch, _, meta}:
      +enabled = reasoning(props)
      +context = window(meta)
      +zero = F.fromU32(0)
      T.Model{id, id, T.OpenAICompletionsApi{}, LLAMA_PROVIDER_ID(), serverUrl ++ "/v1", enabled, Bool.pick(Maybe<&2, T.ThinkingLevelMap>, enabled, Some{thinkingLevels()}, None{}), Bool.pick(List<&2, T.ModelInput>, imageInput(arch), [T.InputText{}, T.InputImage{}], [T.InputText{}]), None{}, T.ModelCost{zero, zero, zero, zero, None{}}, None{}, context, context, None{}, None{}, Some{compatibility(enabled)}}

def catalogModels(values: List<&2, Client.LlamaModelInfo>, +serverUrl: String, +autoload: Bool) -> List<&2, Model()>:
  match values:
    case Nil{}: Nil{}
    case +model <> rest:
      Bool.pick(List<&2, Model()> -> List<&2, Model()>, selectable(model, autoload), tail => toPiModel(model, serverUrl, None{}) <> tail, tail => tail)(catalogModels(rest, serverUrl, autoload))

def replacedModels(provider: Models.Provider, models: List<&2, Model()>) -> Models.Provider:
  match provider:
    case Models.Provider{id, name, url, auth, _, streams, refresh}: Models.Provider{id, name, url, auth, models, streams, refresh}

# setCatalog returns the next immutable controller. Accepted refresh
# publications update the model runtime's live catalog separately.
def setCatalog(context: URL.Context, controller: LlamaProviderController, catalog: List<&2, Client.LlamaModelInfo>, server: String, autoload: Bool) -> Result<&2, &2, String, LlamaProviderController>:
  match controller:
    case LlamaProviderController{provider}:
      Result.map(&2, &2, String, String, LlamaProviderController, url => LlamaProviderController{replacedModels(provider, catalogModels(catalog, url, autoload))}, Client.normalizeLlamaServerUrl(context, server))

def storedEnv(credential: Maybe<&2, Auth.Credential>) -> R.Record<String>:
  match credential:
    case Some{Auth.ApiKeyCredential{_, Some{env}}}: env
    case _: R.new(String)

def storedKey(credential: Maybe<&2, Auth.Credential>) -> Maybe<&2, String>:
  match credential:
    case Some{Auth.ApiKeyCredential{key, _}}: key
    case _: None{}

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def trimmed(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{text}: nonempty(Some{String.trim(text)})

def normalizedServer(context: URL.Context, value: Maybe<&2, String>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match value:
    case None{}: Done{None{}}
    case Some{text}: Result.map(&2, &2, String, String, Maybe<&2, String>, url => Some{url}, Client.normalizeLlamaServerUrl(context, text))

def configuredServer(+context: URL.Context, env: Auth.AuthContext, stored: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match stored:
    case Some{text}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, normalizedServer(context, Some{text}))
    case None{}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        value : Maybe<&2, String> <- Auth.envValue(env, "LLAMA_BASE_URL")
        return normalizedServer(context, trimmed(value))

def resolveServerUrl(context: URL.Context, environment: Auth.AuthContext, credential: Maybe<&2, Auth.Credential>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  configuredServer(context, environment, trimmed(R.get(String, storedEnv(credential), "LLAMA_BASE_URL")))

def resolvedKey(env: Auth.AuthContext, stored: Maybe<&2, String>) -> IO(String):
  match stored:
    case Some{value}: IO.pure(String, value)
    case None{}:
      do IO<String>:
        value : Maybe<&2, String> <- Auth.envValue(env, "LLAMA_API_KEY")
        return Maybe.default(&2, String, value, "local")

def authResolved(+input: Auth.ResolveInput, url: Result<&2, &2, String, Maybe<&2, String>>) -> IO(Auth.AuthOutcome()):
  match input url:
    case _ Fail{error}: IO.pure(Auth.AuthOutcome(), Fail{error})
    case _ Done{None{}}: IO.pure(Auth.AuthOutcome(), Done{None{}})
    case Auth.ResolveInput{env, +credential, _} Done{Some{+server}}:
      do IO<Auth.AuthOutcome()>:
        key : String <- resolvedKey(env, storedKey(credential))
        return Done{Some{Auth.AuthResult{Auth.ModelAuth{Some{key}, None{}, Some{server ++ "/v1"}}, Some{R.set(String, storedEnv(credential), "LLAMA_BASE_URL", server)}, Some{Bool.pick(String, Maybe.is_none(&2, Auth.Credential, credential), "LLAMA_BASE_URL", "stored credential")}}}}

def resolve(transport: Transport, +input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()):
  match transport input:
    case Transport{_, context, _} Auth.ResolveInput{env, credential, _}:
      do IO<Auth.AuthOutcome()>:
        url : Result<&2, &2, String, Maybe<&2, String>> <- resolveServerUrl(context, env, credential)
        authResolved(input, url)

def ask(interaction: Auth.ProviderAuthInteraction, prompt: Auth.AuthPrompt) -> IO(Result<&2, &2, String, String>):
  match interaction:
    case Auth.ProviderAuthInteraction{_, callback, _}: C.call(Auth.AuthPrompt, Result<&2, &2, String, String>, callback, prompt)

def interactionSignal(interaction: Auth.ProviderAuthInteraction) -> Abort.AbortSignal<Unit>:
  match interaction:
    case Auth.ProviderAuthInteraction{signal, _, _}: signal

def verifiedLogin(client: Result<&2, &2, String, Client.LlamaClient>, +url: String, key: Maybe<&2, String>, signal: Abort.AbortSignal<Unit>) -> IO(Auth.LoginOutcome()):
  match client:
    case Fail{error}: IO.pure(Auth.LoginOutcome(), Fail{error})
    case Done{value}:
      do IO<Auth.LoginOutcome()>:
        models : Result<&2, &2, String, List<&2, Client.LlamaModelInfo>> <- Client.list(value, False{}, signal)
        return Result.map(&2, &2, String, List<&2, Client.LlamaModelInfo>, Auth.Credential, _ => Auth.ApiKeyCredential{key, Some{R.Record{[R.Property{"LLAMA_BASE_URL", url}]}}}, models)

def loginKey(transport: Transport, interaction: Auth.ProviderAuthInteraction, +url: String, answer: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match transport answer:
    case _ Fail{error}: IO.pure(Auth.LoginOutcome(), Fail{error})
    case Transport{fetch, context, _} Done{text}:
      +key = nonempty(Some{String.trim(text)})
      verifiedLogin(Client.create(fetch, context, url, key), url, key, interactionSignal(interaction))

def loginUrl(+transport: Transport, +interaction: Auth.ProviderAuthInteraction, url: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match url:
    case Fail{error}: IO.pure(Auth.LoginOutcome(), Fail{error})
    case Done{+server}:
      do IO<Auth.LoginOutcome()>:
        answer : Result<&2, &2, String, String> <- ask(interaction, Auth.SecretPrompt{"API key (optional)", None{}, Some{interactionSignal(interaction)}})
        loginKey(transport, interaction, server, answer)

def enteredServer(+transport: Transport, interaction: Auth.ProviderAuthInteraction, fallback: String, answer: Result<&2, &2, String, String>) -> IO(Auth.LoginOutcome()):
  match transport answer:
    case _ Fail{error}: IO.pure(Auth.LoginOutcome(), Fail{error})
    case Transport{_, context, _} Done{text}:
      +entered = String.trim(text)
      loginUrl(transport, interaction, Client.normalizeLlamaServerUrl(context, Bool.pick(String, String.is_empty(entered), fallback, entered)))

def login(+transport: Transport, +interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()):
  match transport:
    case Transport{_, _, environment}:
      do IO<Auth.LoginOutcome()>:
        value : Maybe<&2, String> <- Auth.envValue(environment, "LLAMA_BASE_URL")
        +fallback : String <- IO.pure(String, Maybe.default(&2, String, value, DEFAULT_LLAMA_SERVER_URL()))
        answer : Result<&2, &2, String, String> <- ask(interaction, Auth.TextPrompt{"llama.cpp server URL", Some{fallback}, Some{interactionSignal(interaction)}})
        enteredServer(transport, interaction, fallback, answer)

# Refresh restores cached models without contacting the router. Network
# publication replaces that catalog only while this refresh remains current.
def credentialOf(context: Models.RefreshModelsContext) -> Maybe<&2, Auth.Credential>:
  match context:
    case Models.RefreshModelsContext{credential, _, _, _, _, _}: credential

def ours(model: Model()) -> Bool:
  match model:
    case T.Model{_, _, T.OpenAICompletionsApi{}, "llama.cpp", _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def cachedModels(values: List<&2, Model()>) -> List<&2, Model()>:
  match values:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = cachedModels(rest)
      Bool.pick(List<&2, Model()>, ours(model), model <> tail, tail)

def restore(context: Models.RefreshModelsContext) -> IO(Bool):
  match context:
    case Models.RefreshModelsContext{_, None{}, _, _, _, _}: IO.pure(Bool, True{})
    case Models.RefreshModelsContext{_, Some{Store.ModelsStoreEntry{models, _, _, _}}, callback, _, _, _}:
      C.call(Models.ModelsPublication, Bool, callback, Models.ModelsPublication{Models.KeepStored{}, Some{cachedModels(models)}})

def unloadedPreset(model: Client.LlamaModelInfo) -> Bool:
  match model:
    case Client.LlamaModelInfo{_, _, Client.Status{Client.Unloaded{}, _, _, _, _}, _, Some{"preset"}, _}: True{}
    case _: False{}

def hasUnloadedPreset(values: List<&2, Client.LlamaModelInfo>) -> Bool:
  match values:
    case Nil{}: False{}
    case model <> rest: unloadedPreset(model) || hasUnloadedPreset(rest)

def selectedModels(values: List<&2, Client.LlamaModelInfo>, +autoload: Bool) -> List<&2, Client.LlamaModelInfo>:
  match values:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = selectedModels(rest, autoload)
      Bool.pick(List<&2, Client.LlamaModelInfo>, selectable(model, autoload), model <> tail, tail)

def routerAutoload(value: Result<&2, &2, String, Client.LlamaServerProps>) -> Bool:
  match value:
    case Done{Client.LlamaServerProps{Some{True{}}, _}}: True{}
    case _: False{}

def autoloadEnabled(client: Client.LlamaClient, models: List<&2, Client.LlamaModelInfo>, signal: Abort.AbortSignal<Unit>) -> IO(Bool):
  Bool.pick(Unit -> IO(Bool), hasUnloadedPreset(models), _ => do IO<Bool>:
    value : Result<&2, &2, String, Client.LlamaServerProps> <- Client.props(client, None{}, signal)
    return routerAutoload(value)
  , _ => IO.pure(Bool, False{}))(Unit{})

def modelWithProps(+client: Client.LlamaClient, +server: String, model: Client.LlamaModelInfo, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Model()>):
  match model:
    case Client.LlamaModelInfo{+id, aliases, Client.Status{Client.Loaded{}, args, failed, exit, progress}, arch, source, meta}:
      loaded = {Client.LlamaModelInfo{id, aliases, Client.Status{Client.Loaded{}, args, failed, exit, progress}, arch, source, meta}: Client.LlamaModelInfo}
      do IO<Result<&2, &2, String, Model()>>:
        properties : Result<&2, &2, String, Client.LlamaServerProps> <- Client.props(client, Some{id}, signal)
        return Result.map(&2, &2, String, Client.LlamaServerProps, Model(), props => toPiModel(loaded, server, Some{props}), properties)
    case other: IO.pure(Result<&2, &2, String, Model()>, Done{toPiModel(other, server, None{})})

def modelTasks(values: List<&2, Client.LlamaModelInfo>, +client: Client.LlamaClient, +server: String, +signal: Abort.AbortSignal<Unit>) -> IO(List<&1, Chan(Result<&2, &2, String, Model()>)>):
  match values:
    case Nil{}: IO.pure(List<&1, Chan(Result<&2, &2, String, Model()>)>, Nil{})
    case model <> rest:
      do IO<List<&1, Chan(Result<&2, &2, String, Model()>)>>:
        task : Chan(Result<&2, &2, String, Model()>) <- IO.fork(Result<&2, &2, String, Model()>, modelWithProps(client, server, model, signal))
        tasks : List<&1, Chan(Result<&2, &2, String, Model()>)> <- modelTasks(rest, client, server, signal)
        return task <> tasks

def joinedModel(value: Result<&2, &2, String, Model()>, rest: Result<&2, &2, String, List<&2, Model()>>) -> Result<&2, &2, String, List<&2, Model()>>:
  match value rest:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{model} Done{tail}: Done{model <> tail}

def joinModels(tasks: List<&1, Chan(Result<&2, &2, String, Model()>)>) -> IO(Result<&2, &2, String, List<&2, Model()>>):
  match tasks:
    case Nil{}: IO.pure(Result<&2, &2, String, List<&2, Model()>>, Done{Nil{}})
    case task <> rest:
      do IO<Result<&2, &2, String, List<&2, Model()>>>:
        model : Result<&2, &2, String, Model()> <- IO.join(Result<&2, &2, String, Model()>, task)
        tail : Result<&2, &2, String, List<&2, Model()>> <- joinModels(rest)
        return joinedModel(model, tail)

def publishModels(+context: Models.RefreshModelsContext, result: Result<&2, &2, String, List<&2, Model()>>, aborted: Bool) -> IO(Result<&2, &2, String, Unit>):
  match result aborted:
    case _ True{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Fail{error} False{}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{+models} False{}:
      do IO<Result<&2, &2, String, Unit>>:
        now : F64 <- Date.now()
        accepted : Bool <- Models.published(context, Models.ModelsPublication{Models.StoreEntry{Store.ModelsStoreEntry{models, None{}, Some{now}, None{}}}, Some{models}})
        return Done{Unit{}}

def catalogLoaded(+client: Client.LlamaClient, +server: String, +context: Models.RefreshModelsContext, result: Result<&2, &2, String, List<&2, Client.LlamaModelInfo>>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{+catalog}:
      do IO<Result<&2, &2, String, Unit>>:
        autoload : Bool <- autoloadEnabled(client, catalog, Models.signalOf(context))
        tasks : List<&1, Chan(Result<&2, &2, String, Model()>)> <- modelTasks(selectedModels(catalog, autoload), client, server, Models.signalOf(context))
        models : Result<&2, &2, String, List<&2, Model()>> <- joinModels(tasks)
        aborted : Bool <- Abort.aborted(Unit, Models.signalOf(context))
        publishModels(context, models, aborted)

def refreshing(client: Result<&2, &2, String, Client.LlamaClient>, server: String, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  match client:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{+value}:
      do IO<Result<&2, &2, String, Unit>>:
        catalog : Result<&2, &2, String, List<&2, Client.LlamaModelInfo>> <- Client.list(value, False{}, Models.signalOf(context))
        catalogLoaded(value, server, context, catalog)

def refreshServer(transport: Transport, +context: Models.RefreshModelsContext, url: Result<&2, &2, String, Maybe<&2, String>>) -> IO(Result<&2, &2, String, Unit>):
  match transport url:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case _ Done{None{}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case Transport{fetch, address, _} Done{Some{+server}}: refreshing(Client.create(fetch, address, server, storedKey(credentialOf(context))), server, context)

def networkRefresh(+transport: Transport, +context: Models.RefreshModelsContext, allowed: Bool) -> IO(Result<&2, &2, String, Unit>):
  match transport allowed:
    case Transport{_, address, _} True{}: refreshServer(transport, context, normalizedServer(address, trimmed(R.get(String, storedEnv(credentialOf(context)), "LLAMA_BASE_URL"))))
    case _ False{}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})

def apiKeyCredential(value: Maybe<&2, Auth.Credential>) -> Bool:
  match value:
    case Some{Auth.ApiKeyCredential{_, _}}: True{}
    case _: False{}

def refresh(transport: Transport, +context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    accepted : Bool <- restore(context)
    aborted : Bool <- Abort.aborted(Unit, Models.signalOf(context))
    networkRefresh(transport, context, accepted && Models.networkAllowed(context) && Bool.not(aborted) && apiKeyCredential(credentialOf(context)))

# Callback entry points have the linear argument shape of the shared native
# interfaces; implementations retain immutable inputs where later IO needs them.
def resolveCallback(transport: Transport, input: Auth.ResolveInput) -> IO(Auth.AuthOutcome()): resolve(transport, input)
def loginCallback(transport: Transport, interaction: Auth.ProviderAuthInteraction) -> IO(Auth.LoginOutcome()): login(transport, interaction)
def refreshCallback(transport: Transport, context: Models.RefreshModelsContext) -> IO(Result<&2, &2, String, Unit>): refresh(transport, context)

def createLlamaProvider(+transport: Transport) -> IO(LlamaProviderController):
  do IO<LlamaProviderController>:
    login : C.Callback<Auth.ProviderAuthInteraction, Auth.LoginOutcome()> <- C.create(~Transport, ~Auth.ProviderAuthInteraction, ~Auth.LoginOutcome(), ~loginCallback, transport)
    resolve : C.Callback<Auth.ResolveInput, Auth.AuthOutcome()> <- C.create(~Transport, ~Auth.ResolveInput, ~Auth.AuthOutcome(), ~resolveCallback, transport)
    refresh : Models.RefreshModels() <- C.create(~Transport, ~Models.RefreshModelsContext, ~Result<&2, &2, String, Unit>, ~refreshCallback, transport)
    return LlamaProviderController{Models.Provider{LLAMA_PROVIDER_ID(), "llama.cpp", DEFAULT_LLAMA_SERVER_URL() ++ "/v1", Auth.ProviderAuth{Some{Auth.ApiKeyAuth{"llama.cpp server", Some{login}, resolve}}, None{}}, Nil{}, Models.ApiStreams{}, Some{refresh}}}
