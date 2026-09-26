import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../../../ai/src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../../../ai/src/api/openai-responses.bend as Responses
import ./anthropic-provider.bend as Anthropic
import ./google-provider.bend as Google
import ./openai-completions-provider.bend as Completions
import ./stream-providers.bend as StreamProviders
import ../../../ai/src/api/openai-client.bend as Client
import ../../../ai/src/utils/tool-declaration.bend as Declaration
import ../../../ai/src/utils/validation.bend as Validation
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/providers.bend as Providers
import ../../../agent/src/stream-fn.bend as StreamFn
import ../../../agent/src/types.bend as T
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/abort.bend as Abort
import ../../../runtime/src/pi-user-agent.bend as UserAgent
import ../../../runtime/src/http-exchange.bend as HTTP
import ../../../runtime/src/http-message.bend as Message
import ../../../runtime/src/http-response.bend as Response
import ../../../runtime/src/dns-resolver.bend as DNS
import ../../../runtime/src/connection-driver.bend as Connect
import ../../../runtime/src/tls-trust.bend as Trust
import ../../../runtime/src/tls-socket.bend as TLS
import ../../../runtime/src/tls13-client.bend as TLSClient
import ../../../runtime/src/x509.bend as X509
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/idna.bend as IDNA
import ../../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/collation.bend as Collation
import ../utils/paths.bend as Paths
import ./auth-storage.bend as Storage
import ./runtime-credentials.bend as Runtime
import ./model-runtime.bend as Models
import ./system-prompt.bend as Prompt
import ./messages.bend as Messages
import ./session-manager.bend as S
import ./settings-manager.bend as Settings
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as W
import ../../../ai/src/models.bend as AiModels
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ./defaults.bend as Defaults
import ./resource-loader.bend as Resources
import ./package-manager.bend as PackageManager
import ./skills.bend as Skills
import ./prompt-templates.bend as Templates
import ./diagnostics.bend as Diagnostics
import ./tools/index.bend as Tools
import ../utils/tools-manager.bend as Manager
import ./tools/file-mutation-queue.bend as Queue
import ./extensions/context.bend as Ctx
import ./extensions/loader.bend as ExtensionLoader
import ./extensions/runner.bend as ExtensionRunner
import ./extensions/types.bend as ExtensionTypes
import ../extensions/index.bend as BuiltinExtensions
import ../config.bend as AppConfig
import ./provider-composer.bend as Composer

# The owned services behind one agent: transport, credentials, model runtime,
# settings-driven selection, tools and the Agent itself. This is the print-mode
# slice of upstream's AgentSessionServices/AgentSessionRuntime; the session
# record and persistence live in agent-session.bend. Extensions, skills and
# interactive mode are not ported yet.

def Error() -> Data: Tools.ToolError
def Details() -> Data: Tools.ToolDetails
# The agent's custom messages are pi's coding messages (bash executions,
# extension messages, branch and compaction summaries), as upstream's
# AgentMessage union; extension payloads are JSON values.
def Custom() -> Data: Messages.CodingMessage<V.Value>
def LoopConfig() -> Data: T.AgentLoopConfig<Unit, Details(), Custom(), Error(), Unit>
def Owner() -> Data: Agent.Agent<Unit, Details(), Custom(), Error(), Unit>
def Converter() -> Data: Agent.Converter(Unit, Details(), Custom(), Error())
def Stream() -> Data: T.StreamFn(Unit, Details(), LoopConfig(), Error())
def Outcome(-A: Type) -> Type: Result<&2, &1, String, A>

def render(error: Error()) -> String: Tools.errorMessage(error)
def fromString(message: String) -> Error(): Tools.Failure{message}
def declarationError(error: Declaration.DeclarationError) -> Error(): Tools.Failure{"Tool declaration encoding failed"}
def validationError(error: Validation.ToolValidationError) -> Error(): Tools.Failure{Maybe.default(&2, String, Validation.formatToolValidationError(error), "Tool schema validation failed")}
def streamError(error: StreamFn.MissingDefault) -> Error(): Tools.Failure{StreamFn.errorMessage(error)}
def entryError(error: Loop.ContinueError) -> Error(): Tools.Failure{Loop.errorMessage(error)}

# Transport
# ---------

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def files() -> Fetch.Files: Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}

def httpOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}}

def security(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> HTTP.Security:
  HTTP.WithTLS{authorizer, TLS.defaults()}

def providerConfig(authorizer: C.Callback<URL.Host, TLSClient.Authorization>, agent: String) -> Responses.Config:
  Responses.Config{urlContext(), Client.Defaults{agent, R.new(String), None{}, None{}}, files(), httpOptions(), security(authorizer), 65536n, False{}}

type Transport is Type:
  Transport{authorizer: C.Callback<URL.Host, TLSClient.Authorization>, runtime: Fetch.Runtime, fetch: Fetch.Fetch(Unit)}

def trustError(error: Trust.Error) -> String:
  match error:
    case Trust.Read{_}: "Could not read the certificate bundle"
    case Trust.Text{_}: "The certificate bundle is not valid PEM"
    case Trust.Certificate{_}: "The certificate bundle holds an invalid certificate"
    case Trust.UnsupportedLabel{_}: "The certificate bundle holds an unsupported PEM block"
    case Trust.EmptyBundle{}: "The certificate bundle holds no certificates"

def transportOf(authorizer: C.Callback<URL.Host, TLSClient.Authorization>, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> Outcome(Transport):
  match pair:
    case Tuple{runtime, fetch}: Done{Transport{authorizer, runtime, fetch}}

def withRuntime(+authorizer: C.Callback<URL.Host, TLSClient.Authorization>, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Outcome(Transport)):
  match result:
    case Fail{_}:
      do IO<Outcome(Transport)>:
        C.dispose(URL.Host, TLSClient.Authorization, authorizer)
        return Fail{"Could not initialize the network runtime"}
    case Done{runtime}:
      do IO<Outcome(Transport)>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callbackWithSecurity(~Unit, runtime, security(authorizer))
        return transportOf(authorizer, pair)

def withBundle(bundle: Result<&2, &2, Trust.Error, List<&2, X509.Certificate>>) -> IO(Outcome(Transport)):
  match bundle:
    case Fail{error}: IO.pure(Outcome(Transport), Fail{trustError(error)})
    case Done{anchors}:
      do IO<Outcome(Transport)>:
        +authorizer : C.Callback<URL.Host, TLSClient.Authorization> <- Trust.newSAN(Trust.SANPolicy{anchors, 256n})
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(files(), httpOptions())
        withRuntime(authorizer, runtime)

# The CA bundle path: SSL_CERT_FILE or the Debian/Ubuntu system bundle.
def createTransport(bundlePath: String) -> IO(Outcome(Transport)):
  do IO<Outcome(Transport)>:
    bundle : Result<&2, &2, Trust.Error, List<&2, X509.Certificate>> <- Trust.load(bundlePath, 4194304n)
    withBundle(bundle)

def disposeTransport(transport: Transport) -> IO(Unit):
  match transport:
    case Transport{authorizer, runtime, fetch}:
      do IO<Unit>:
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)
        C.dispose(URL.Host, TLSClient.Authorization, authorizer)

# Stream function
# ---------------

def project(config: LoopConfig()) -> Responses.SimpleStreamOptions(Unit, Unit, Error()):
  T.toSimpleStreamOptions(Unit, Details(), Custom(), Error(), Unit, config)

def failure(cause: Responses.Error<Unit, Error()>) -> Error():
  Tools.Failure{Responses.describe(~Unit, ~Error(), ~render, "openai", cause)}

def modelApi(model: Models.Model()) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _, _, _}: api

# upstream sdk buildRequestOptions: a request's timeout, retries and
# websocket connect timeout default to the settings. The settings are read
# when the runtime is created.
type RequestDefaults is Data:
  RequestDefaults{requestTimeout: F64, retryLimit: Maybe<&2, F64>, retryDelay: F64, connectTimeout: Maybe<&2, F64>}

def idleTimeout(+idle: W.U64) -> F64:
  Bool.pick(F64, F.isEqual(F.compare(F.fromU64(idle), F.fromU32(0))), F.fromU32(2147483647), F.fromU64(idle))

def defaultsFrom(retry: Settings.ResolvedProviderRetrySettings, idle: W.U64, connect: Maybe<&2, W.U64>) -> RequestDefaults:
  match retry:
    case Settings.ResolvedProviderRetrySettings{timeout, retries, delay}:
      RequestDefaults{Maybe.default(&2, F64, Maybe.map(&2, W.U64, F64, F.fromU64, timeout), idleTimeout(idle)), Maybe.map(&2, W.U64, F64, F.fromU64, retries), F.fromU64(delay), Maybe.map(&2, W.U64, F64, F.fromU64, connect)}

def requestDefaults(+settings: Settings.SettingsManager) -> RequestDefaults:
  defaultsFrom(Settings.getProviderRetrySettings(settings), Settings.getHttpIdleTimeoutMs(settings), Settings.getWebSocketConnectTimeoutMs(settings))

# Request auth comes from the model runtime; --api-key overrides the stored key.
type KeySource is Data:
  KeySource{models: Models.ModelRuntime, apiKey: Maybe<&2, String>}

type ProviderStreams is Data:
  ProviderStreams{responses: Responses.Config, fetch: Fetch.Fetch(Unit), defaults: RequestDefaults, keys: KeySource}

def selectedOptions(options: Maybe<&2, LoopConfig()>) -> Maybe<&2, Responses.SimpleStreamOptions(Unit, Unit, Error())>:
  Maybe.map(&2, LoopConfig(), Responses.SimpleStreamOptions(Unit, Unit, Error()), project, options)

# Like upstream's global fetch, requests share the runtime's fetch, so
# keep-alive connections carry over between turns.
def withRequest(fetch: Fetch.Fetch(Unit), preset: RequestDefaults, options: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>) -> Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>:
  match preset options:
    case RequestDefaults{timeout, retries, delay, connect} Ai.SimpleStreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, apiKey, Maybe.or(&2, Fetch.Fetch(Unit), shared, Some{fetch}), env, onPayload, onResponse, headers, Maybe.or(&2, F64, timeoutMs, Some{timeout}), Maybe.or(&2, F64, maxRetries, retries), Maybe.or(&2, F64, maxRetryDelayMs, Some{delay}), temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, Maybe.or(&2, F64, websocketConnectTimeoutMs, connect), metadata, toolChoice, reasoning, deferred, budgets}

def requestConfig(fetch: Fetch.Fetch(Unit), preset: RequestDefaults, config: LoopConfig()) -> LoopConfig():
  match config:
    case T.AgentLoopConfig{options, model, convert, transform, key, a, b, c, d, e, f, g, h}: T.AgentLoopConfig{withRequest(fetch, preset, options), model, convert, transform, key, a, b, c, d, e, f, g, h}

def selectedProvider(responses: Responses.Config, fetch: Fetch.Fetch(Unit), model: Models.Model(), context: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>, +options: Maybe<&2, LoopConfig()>, api: Ai.ModelApi) -> IO(Providers.Output(Unit, Error())):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.open(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.GoogleGenerativeAiApi{}: Google.open(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.OpenAICompletionsApi{}: Completions.open(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.PiMessagesApi{}: StreamProviders.piMessages(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.MistralConversationsApi{}: StreamProviders.mistral(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.BedrockConverseStreamApi{}: StreamProviders.bedrock(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.GoogleVertexApi{}: StreamProviders.vertex(fetch, urlContext(), model, context, selectedOptions(options))
    case _: Providers.openResponses(~LoopConfig(), ~Unit, ~Unit, ~Details(), ~Error(), ~project, ~render, ~failure, responses, T.StreamInput{model, context, options})

# upstream ModelRuntime.prepareRequest: each request resolves its model's
# auth; the request's own key and headers win over it, auth headers come
# first, the auth base URL replaces the model's and the environments merge.
# Without resolved auth the request goes out as prepared by the agent.
def withBaseUrl(model: Models.Model(), url: Maybe<&2, String>) -> Models.Model():
  match model url:
    case _ None{}: model
    case Ai.Model{id, name, api, provider, _, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat} Some{replaced}:
      Ai.Model{id, name, api, provider, replaced, reasoning, levels, input, limits, cost, cache, window, maxTokens, sampling, headers, compat}

def mergedEnv(auth: Maybe<&2, Ai.ProviderEnv()>, request: Maybe<&2, Ai.ProviderEnv()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match auth request:
    case None{} _: request
    case _ None{}: auth
    case Some{base} Some{extra}: Some{Composer.spread(String, base, R.entries(String, extra))}

def preparedOptions(auth: Auth.AuthResult, options: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>) -> Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>:
  match auth options:
    case Auth.AuthResult{Auth.ModelAuth{key, authHeaders, _}, authEnv, _} Ai.SimpleStreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, Maybe.or(&2, String, apiKey, key), shared, mergedEnv(authEnv, env), onPayload, onResponse, Models.mergeHeaders(authHeaders, headers), timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}

def preparedConfig(auth: Auth.AuthResult, config: LoopConfig()) -> LoopConfig():
  match config:
    case T.AgentLoopConfig{options, model, convert, transform, key, a, b, c, d, e, f, g, h}: T.AgentLoopConfig{preparedOptions(auth, options), model, convert, transform, key, a, b, c, d, e, f, g, h}

def requestEnv(options: Maybe<&2, LoopConfig()>) -> Maybe<&2, Ai.ProviderEnv()>:
  match options:
    case Some{T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, env, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}}: env
    case None{}: None{}

# The provider's streamSimple options (upstream provider.streamSimple's
# wrappers, e.g. OpenCode's session header).
def streamedConfig(streams: AiModels.ProviderStreams, model: Models.Model(), config: LoopConfig()) -> LoopConfig():
  match config:
    case T.AgentLoopConfig{options, m, convert, transform, key, a, b, c, d, e, f, g, h}: T.AgentLoopConfig{AiModels.streamSimpleOptions(Ai.JsonValue, Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error(), streams, model, options), m, convert, transform, key, a, b, c, d, e, f, g, h}

# The provider's stream then dispatches the model for the request's merged
# provider env (upstream provider.stream after prepareRequest).
def preparedRequest(responses: Responses.Config, fetch: Fetch.Fetch(Unit), +model: Models.Model(), context: Ai.TranscriptContext<V.Value, V.Value, Unit, Details()>, +options: Maybe<&2, LoopConfig()>, +streams: AiModels.ProviderStreams, resolution: Resolve.Resolution()) -> IO(Providers.Output(Unit, Error())):
  match resolution:
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{key, headers, +url}, +env, source}}}:
      +model = AiModels.streamModel(Ai.JsonValue, streams, withBaseUrl(model, url), mergedEnv(env, requestEnv(options)))
      selectedProvider(responses, fetch, model, context, Maybe.map(&2, LoopConfig(), LoopConfig(), value => streamedConfig(streams, model, preparedConfig(Auth.AuthResult{Auth.ModelAuth{key, headers, url}, env, source}, value)), options), modelApi(model))
    case _:
      +model = AiModels.streamModel(Ai.JsonValue, streams, model, requestEnv(options))
      selectedProvider(responses, fetch, model, context, Maybe.map(&2, LoopConfig(), LoopConfig(), value => streamedConfig(streams, model, value), options), modelApi(model))

def openProvider(config: ProviderStreams, input: Providers.Input(LoopConfig(), Unit, Details())) -> IO(Providers.Output(Unit, Error())):
  match config input:
    case ProviderStreams{responses, +fetch, defaults, KeySource{+models, apiKey}} T.StreamInput{+model, context, options}:
      do IO<Providers.Output(Unit, Error())>:
        resolution : Resolve.Resolution() <- Models.getModelAuth(models, model, Resolve.AuthResolutionOverrides{apiKey, None{}, None{}, None{}})
        streams : AiModels.ProviderStreams <- Models.getProviderStreams(models, Models.modelProvider(model))
        preparedRequest(responses, fetch, model, context, Maybe.map(&2, LoopConfig(), LoopConfig(), value => requestConfig(fetch, defaults, value), options), streams, resolution)

def createStream(authorizer: C.Callback<URL.Host, TLSClient.Authorization>, fetch: Fetch.Fetch(Unit), defaults: RequestDefaults, keys: KeySource) -> IO(Stream()):
  do IO<Stream()>:
    agent : String <- IO.try(String, UserAgent.get())
    C.create(~ProviderStreams, ~Providers.Input(LoopConfig(), Unit, Details()), ~Providers.Output(Unit, Error()), ~openProvider, ProviderStreams{providerConfig(authorizer, agent), fetch, defaults, keys})

# Request auth
# ------------

def keyOf(providerId: String, resolution: Resolve.Resolution()) -> Result<&2, &2, Error(), Maybe<&2, String>>:
  match resolution:
    case Fail{error}: Fail{Tools.Failure{Resolve.errorMessage(error)}}
    case Done{None{}}: Fail{Tools.Failure{"No API key found for " ++ providerId ++ ".\n\nRun pi to log in or set the provider's API key environment variable."}}
    case Done{Some{Auth.AuthResult{Auth.ModelAuth{apiKey, _, _}, _, _}}}: Done{apiKey}

# The agent asks for a key per request; --api-key overrides the stored one.
def resolveKeyFor(source: KeySource, +providerId: String) -> IO(Result<&2, &2, Error(), Maybe<&2, String>>):
  match source:
    case KeySource{models, apiKey}:
      do IO<Result<&2, &2, Error(), Maybe<&2, String>>>:
        resolution : Resolve.Resolution() <- Models.getAuth(models, providerId, Resolve.AuthResolutionOverrides{apiKey, None{}, None{}, None{}})
        return keyOf(providerId, resolution)

def resolveKey(source: KeySource, providerId: String) -> IO(Result<&2, &2, Error(), Maybe<&2, String>>):
  resolveKeyFor(source, providerId)

# Services
# --------

# What a resumed session contributes: its context messages, the model and
# thinking level it recorded (None when no thinking_level_change exists).
type SessionSeed is Data:
  SessionSeed{sessionId: String, messages: List<&2, T.AgentMessage<Unit, Details(), Custom()>>, model: Maybe<&2, S.SessionModel>, thinking: Maybe<&2, String>}

def emptySeed() -> SessionSeed: SessionSeed{"", Nil{}, None{}, None{}}

# Resource flags from the command line: extra skill and prompt template paths
# (resolved against the process cwd) and the --no-skills/--no-prompt-templates
# switches.
type ResourceOptions is Data:
  ResourceOptions{skillPaths: List<&2, String>, noSkills: Bool, promptPaths: List<&2, String>, noPromptTemplates: Bool}

def noResources() -> ResourceOptions: ResourceOptions{Nil{}, False{}, Nil{}, False{}}

# upstream createAgentSession's tool options: `tools` is the allowlist,
# `noTools` the default suppression when there is none (all tools, or the
# default built-ins only), `excludeTools` the denylist applied after both.
type NoTools is Data:
  NoToolsAll{}
  NoToolsBuiltin{}
type ToolSelection is Data:
  ToolSelection{tools: Maybe<&2, List<&2, String>>, noTools: Maybe<&2, NoTools>, excludeTools: Maybe<&2, List<&2, String>>}
def defaultToolSelection() -> ToolSelection: ToolSelection{None{}, None{}, None{}}

# The tool registry (the built-in tools that pass the allow- and denylists, in
# upstream's registry order) and the initially active tool names.
type ToolSetup is Data:
  ToolSetup{registry: List<&2, Tools.ToolName>, active: List<&2, String>}

def containsText(values: List<&2, String>, +name: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value, name) || containsText(rest, name)

def allowedOf(selection: ToolSelection) -> Maybe<&2, List<&2, String>>:
  match selection:
    case ToolSelection{Some{names}, _, _}: Some{names}
    case ToolSelection{None{}, Some{NoToolsAll{}}, _}: Some{Nil{}}
    case _: None{}

def excludedOf(selection: ToolSelection) -> List<&2, String>:
  match selection:
    case ToolSelection{_, _, excluded}: Maybe.default(&2, List<&2, String>, excluded, Nil{})

# upstream isAllowedTool
def isAllowedTool(allowed: Maybe<&2, List<&2, String>>, excluded: List<&2, String>, +name: String) -> Bool:
  Bool.and(Maybe.default(&2, Bool, Maybe.map(&2, List<&2, String>, Bool, names => containsText(names, name), allowed), True{}), Bool.not(containsText(excluded, name)))

def defaultActiveToolNames() -> List<&2, String>: ["read", "bash", "edit", "write"]

def initialRequested(selection: ToolSelection, configured: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match selection:
    case ToolSelection{Some{names}, _, _}: names
    case ToolSelection{None{}, Some{_}, _}: Nil{}
    case ToolSelection{None{}, None{}, _}: Maybe.default(&2, List<&2, String>, configured, defaultActiveToolNames())

def registryNames(names: List<&2, Tools.ToolName>, +allowed: Maybe<&2, List<&2, String>>, +excluded: List<&2, String>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = registryNames(rest, allowed, excluded)
      Bool.pick(List<&2, Tools.ToolName>, isAllowedTool(allowed, excluded, Tools.toolName(name)), name <> tail, tail)

def texts(names: List<&2, Tools.ToolName>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Tools.toolName(name) <> texts(rest)

def keptNames(names: List<&2, String>, +registry: List<&2, String>, +allowed: Maybe<&2, List<&2, String>>, +excluded: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = keptNames(rest, registry, allowed, excluded)
      Bool.pick(List<&2, String>, isAllowedTool(allowed, excluded, name) && containsText(registry, name), name <> tail, tail)

def listedFrom(names: List<&2, String>, +listed: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = listedFrom(rest, listed)
      Bool.pick(List<&2, String>, containsText(listed, name), name <> tail, tail)

def listedIn(names: List<&2, String>, allowed: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match allowed:
    case None{}: Nil{}
    case Some{listed}: listedFrom(names, listed)

def distinctNames(names: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: List.reverse(&2, String, seen)
    case +name <> rest: distinctNames(rest, Bool.pick(List<&2, String>, containsText(seen, name), seen, name <> seen))

# upstream createAgentSession and AgentSession._refreshToolRegistry for the
# built-in tools: the requested names that are allowed and registered, then
# every registered tool the allowlist names, without duplicates.
def resolveTools(+selection: ToolSelection, configured: Maybe<&2, List<&2, String>>) -> ToolSetup:
  +allowed = allowedOf(selection)
  +excluded = excludedOf(selection)
  +registry = registryNames(Tools.builtinToolNames(), allowed, excluded)
  +registered = texts(registry)
  ToolSetup{registry, distinctNames(List.append(&2, String, keptNames(initialRequested(selection, configured), registered, allowed, excluded), listedIn(registered, allowed)), Nil{})}

def activeNamesOf(setup: ToolSetup) -> List<&2, String>:
  match setup:
    case ToolSetup{_, active}: active

type CreateOptions is Data:
  CreateOptions{cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String, provider: Maybe<&2, String>, model: Maybe<&2, String>, apiKey: Maybe<&2, String>, thinking: Maybe<&2, Ai.ModelThinkingLevel>, systemPrompt: Maybe<&2, String>, appendSystemPrompt: List<&2, String>, tools: ToolSelection, contextFiles: Bool, seed: SessionSeed, settings: Settings.SettingsManager, resources: ResourceOptions}

def toolSetupOf(options: CreateOptions) -> ToolSetup:
  match options:
    case CreateOptions{_, _, _, _, _, _, _, _, _, _, _, selection, _, _, settings, _}: resolveTools(selection, Settings.getDefaultTools(settings))

# The model and thinking level the runtime settled on, for the session record.
type Selection is Data:
  Selection{model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel}

# What the session declares on each prompt: the system prompt sections and
# the executable tools (upstream _preparePromptAndToolLoadout's inputs), with
# the loaded skills and prompt templates that expand /skill: and /name input.
# What the prompt resources were prepared from.
type LoadoutSource is Data: LoadoutSource{environment: Paths.Environment, options: CreateOptions, packageDir: String}

# `source` rebuilds the prompt resources on reload (upstream AgentSession.reload).
# `registry` holds every tool that can be activated (upstream _toolRegistry);
# `tools` are the active ones, in activation order.
# `extensions` is the runtime's extension runner; the tools read its context.
type Loadout is Data:
  Loadout{sections: Prompt.SystemPromptSections(), tools: List<&2, Tools.Tool()>, skills: List<&2, Skills.Skill>, templates: List<&2, Templates.PromptTemplate>, extensions: Maybe<&2, ExtensionRunner.ExtensionRunner>, contextFiles: List<&2, Prompt.ContextFile>, source: Maybe<&2, LoadoutSource>, registry: List<&2, Tools.Tool()>}

# The system prompt with the resources it was built from.
type Prepared is Data:
  Prepared{sections: Prompt.SystemPromptSections(), skills: List<&2, Skills.Skill>, templates: List<&2, Templates.PromptTemplate>, contextFiles: List<&2, Prompt.ContextFile>}

type AgentRuntime is Type:
  AgentRuntime{transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), agent: Owner(), model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, loadout: Loadout}

def parsedNames(names: List<&2, String>) -> List<&2, Tools.ToolName>:
  match names:
    case Nil{}: Nil{}
    case name <> rest:
      +tail = parsedNames(rest)
      Maybe.default(&2, List<&2, Tools.ToolName>, Maybe.map(&2, Tools.ToolName, List<&2, Tools.ToolName>, found => found <> tail, Tools.parseToolName(name)), tail)

def snippets(names: List<&2, Tools.ToolName>, +record: R.Record<String>) -> R.Record<String>:
  match names:
    case Nil{}: record
    case +name <> rest: snippets(rest, R.set(String, record, Tools.toolName(name), Tools.promptSnippet(name)))

# The options the built-in tools are created with; the prompt guidelines
# follow them as upstream's tool definitions do.
def toolsOptions() -> Tools.ToolsOptions: Tools.defaultOptions()

def guidelines(names: List<&2, Tools.ToolName>, +record: R.Record<List<&2, String>>) -> R.Record<List<&2, String>>:
  match names:
    case Nil{}: record
    case +name <> rest: guidelines(rest, R.set(List<&2, String>, record, Tools.toolName(name), Tools.definitionGuidelines(name, toolsOptions())))

def toolNames(names: List<&2, Tools.ToolName>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Tools.toolName(name) <> toolNames(rest)

def nonemptyAppend(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case values: Some{String.join(values, "\n\n")}

# The system prompt options for the active tools (upstream _rebuildSystemPrompt).
def promptOptionsFor(options: CreateOptions, +names: List<&2, Tools.ToolName>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>) -> Prompt.BuildSystemPromptOptions:
  match options:
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, systemPrompt, appendSystemPrompt, _, _, _, _, _}:
      Prompt.BuildSystemPromptOptions{systemPrompt, None{}, Some{toolNames(names)}, Some{snippets(names, R.new(String))}, Some{guidelines(names, R.new(List<&2, String>))}, None{}, nonemptyAppend(appendSystemPrompt), None{}, cwd, Some{contextList}, Some{skills}}

def promptOptions(options: CreateOptions, active: List<&2, String>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>) -> Prompt.BuildSystemPromptOptions:
  promptOptionsFor(options, parsedNames(active), contextList, skills)

def documentationPaths(+packageDir: String) -> Prompt.DocumentationPaths:
  Prompt.DocumentationPaths{Path.join(packageDir, "README.md"), Path.join(packageDir, "docs"), Path.join(packageDir, "examples")}

def reportContextDiagnostics(issues: List<&2,Diagnostics.ResourceDiagnostic>) -> IO(Unit):
  match issues:
    case Nil{}: IO.pure(Unit,Unit{})
    case Diagnostics.ResourceDiagnostic{_,message,path,_} <> rest:
      do IO<Unit>:
        IO.print_err("Warning: " ++ Maybe.default(&2,String,Maybe.map(&2,String,String,value => value ++ ": ",path),"") ++ message)
        reportContextDiagnostics(rest)

def contextFilesFor(environment: Paths.Environment, options: CreateOptions) -> IO(Resources.ContextFiles):
  match options:
    case CreateOptions{cwd, agentDir, _, _, _, _, _, _, _, _, _, _, True{}, _, _, _}: Resources.loadProjectContextFiles(environment,Resources.Options{cwd,agentDir})
    case _: IO.pure(Resources.ContextFiles,Resources.ContextFiles{Nil{},Nil{}})

def contextFilesReported(result: Resources.ContextFiles) -> IO(List<&2,Prompt.ContextFile>):
  match result:
    case Resources.ContextFiles{loadedFiles,diagnostics}:
      do IO<List<&2,Prompt.ContextFile>>:
        reportContextDiagnostics(diagnostics)
        return loadedFiles

# Skills
# ------

def canonicalPath(+path: String) -> IO(String):
  do IO<String>:
    real : Result<&2, &2, FS.Error, String> <- FS.realpath(path)
    return Result.default(&2, &2, FS.Error, String, real, path)

def seenPath(seen: List<&2, String>, +path: String) -> Bool:
  match seen:
    case Nil{}: False{}
    case first <> rest: String.eq(first, path) || seenPath(rest, path)

def mergedFrom(+environment: Paths.Environment, +cwd: String, paths: List<&2, String>, +seen: List<&2, String>) -> IO(List<&2, String>):
  match paths:
    case Nil{}: IO.pure(List<&2, String>, Nil{})
    case +path <> +rest:
      +resolved = Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environment, path, cwd, Paths.PathInputOptions{True{}, True{}, None{}, False{}, False{}}), path)
      do IO<List<&2, String>>:
        +real : String <- canonicalPath(resolved)
        Bool.pick(Unit -> IO(List<&2, String>), seenPath(seen, real),
          _ => mergedFrom(environment, cwd, rest, seen),
          _ => do IO<List<&2, String>>:
            later : List<&2, String> <- mergedFrom(environment, cwd, rest, real <> seen)
            return resolved <> later)(Unit{})

def loadedSkills(result: Skills.LoadSkillsResult) -> List<&2, Skills.Skill>:
  match result:
    case Skills.LoadSkillsResult{skills, _}: skills

def skillsFrom(+environment: Paths.Environment, +cwd: String, agentDir: String, noSkills: Bool, paths: List<&2, String>) -> IO(List<&2, Skills.Skill>):
  match noSkills paths:
    case True{} Nil{}: IO.pure(List<&2, Skills.Skill>, Nil{})
    case _ _:
      do IO<List<&2, Skills.Skill>>:
        result : Skills.LoadSkillsResult <- Skills.loadSkills(environment, Skills.LoadSkillsOptions{cwd, agentDir, paths, False{}})
        return loadedSkills(result)

def resolvedSkills(resolved: PackageManager.ResolvedPaths) -> List<&2, String>:
  match resolved:
    case PackageManager.ResolvedPaths{skills, _, _}: PackageManager.enabledPaths(skills)

def skillSourceName(source: PackageManager.Source) -> String:
  match source:
    case PackageManager.Local{}: "local"
    case PackageManager.Auto{}: "auto"

def skillScope(scope: PackageManager.Scope) -> Skills.SourceScope:
  match scope:
    case PackageManager.ProjectScope{}: Skills.Project{}
    case PackageManager.UserScope{}: Skills.User{}

# upstream metadataByPath: every resolved resource's metadata, first path wins.
def resolvedResources(resolved: PackageManager.ResolvedPaths) -> List<&2, PackageManager.ResolvedResource>:
  match resolved:
    case PackageManager.ResolvedPaths{skills, prompts, themes}: List.append(&2, PackageManager.ResolvedResource, skills, List.append(&2, PackageManager.ResolvedResource, prompts, themes))

def resourceSource(metadata: PackageManager.PathMetadata, path: String) -> Skills.SourceInfo:
  match metadata:
    case PackageManager.PathMetadata{source, scope, baseDir}:
      Skills.SourceInfo{path, skillSourceName(source), skillScope(scope), Skills.TopLevel{}, baseDir}

# upstream findSourceInfoForPath: the resource at or above the path.
def findSourceInfoForPath(+path: String, resources: List<&2, PackageManager.ResolvedResource>) -> Maybe<&2, Skills.SourceInfo>:
  match resources:
    case Nil{}: None{}
    case PackageManager.ResolvedResource{root, _, metadata} <> rest:
      Bool.pick(Maybe<&2, Skills.SourceInfo>, Skills.under(path, root), Some{resourceSource(metadata, path)}, findSourceInfoForPath(path, rest))

def sourcedSkills(skills: List<&2, Skills.Skill>, +resources: List<&2, PackageManager.ResolvedResource>) -> List<&2, Skills.Skill>:
  match skills:
    case Nil{}: Nil{}
    case Skills.Skill{name, description, +path, baseDir, source, disabled} <> rest:
      +resolved = Maybe.default(&2, Skills.SourceInfo, findSourceInfoForPath(path, resources), source)
      Skills.Skill{name, description, path, baseDir, resolved, disabled} <> sourcedSkills(rest, resources)

def sourcedTemplates(templates: List<&2, Templates.PromptTemplate>, +resources: List<&2, PackageManager.ResolvedResource>) -> List<&2, Templates.PromptTemplate>:
  match templates:
    case Nil{}: Nil{}
    case Templates.PromptTemplate{name, description, hint, content, source, +file} <> rest:
      +resolved = Maybe.default(&2, Skills.SourceInfo, findSourceInfoForPath(file, resources), source)
      Templates.PromptTemplate{name, description, hint, content, resolved, file} <> sourcedTemplates(rest, resources)

def nonLocalPrefix(+value: String) -> Bool:
  String.starts_with(value, "npm:") || String.starts_with(value, "git:") || String.starts_with(value, "github:") || String.starts_with(value, "http:") || String.starts_with(value, "https:") || String.starts_with(value, "ssh:")

# upstream isLocalPath.
def isLocalPath(value: String) -> Bool: Bool.not(nonLocalPrefix(Text.trim(value)))

def processCwd(environment: Paths.Environment) -> String:
  match environment:
    case Paths.Environment{cwd, _, _}: cwd

# upstream resolveCliPaths: local command-line paths against the process cwd.
def cliPaths(+environment: Paths.Environment, paths: List<&2, String>) -> List<&2, String>:
  match paths:
    case Nil{}: Nil{}
    case +path <> rest:
      Bool.pick(String, isLocalPath(path), Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environment, path, processCwd(environment), Paths.defaults()), path), path) <> cliPaths(environment, rest)

def resolvedFor(+environment: Paths.Environment, options: CreateOptions) -> IO(PackageManager.ResolvedPaths):
  match options:
    case CreateOptions{cwd, agentDir, _, _, _, _, _, _, _, _, _, _, _, _, settings, _}: PackageManager.resolve(environment, settings, cwd, agentDir)

# upstream DefaultResourceLoader skills: the package manager's enabled skills
# (unless --no-skills) followed by --skill paths, deduplicated by canonical
# path and loaded without the default directories.
def skillsFor(+environment: Paths.Environment, options: CreateOptions, +resolved: PackageManager.ResolvedPaths) -> IO(List<&2, Skills.Skill>):
  match options:
    case CreateOptions{+cwd, +agentDir, _, _, _, _, _, _, _, _, _, _, _, _, _, ResourceOptions{skillPaths, +noSkills, _, _}}:
      do IO<List<&2, Skills.Skill>>:
        merged : List<&2, String> <- mergedFrom(environment, cwd, List.append(&2, String, Bool.pick(List<&2, String>, noSkills, Nil{}, resolvedSkills(resolved)), cliPaths(environment, skillPaths)), Nil{})
        loaded : List<&2, Skills.Skill> <- skillsFrom(environment, cwd, agentDir, noSkills, merged)
        return sourcedSkills(loaded, resolvedResources(resolved))

def resolvedPrompts(resolved: PackageManager.ResolvedPaths) -> List<&2, String>:
  match resolved:
    case PackageManager.ResolvedPaths{_, prompts, _}: PackageManager.enabledPaths(prompts)

def templateNamed(templates: List<&2, Templates.PromptTemplate>, +name: String) -> Bool:
  match templates:
    case Nil{}: False{}
    case Templates.PromptTemplate{known, _, _, _, _, _} <> rest: String.eq(known, name) || templateNamed(rest, name)

# upstream dedupePrompts: the first template of each name wins.
def dedupedTemplates(templates: List<&2, Templates.PromptTemplate>, +kept: List<&2, Templates.PromptTemplate>) -> List<&2, Templates.PromptTemplate>:
  match templates:
    case Nil{}: List.reverse(&2, Templates.PromptTemplate, kept)
    case Templates.PromptTemplate{+name, description, hint, content, source, file} <> +rest:
      Bool.pick(Unit -> List<&2, Templates.PromptTemplate>, templateNamed(kept, name),
        _ => dedupedTemplates(rest, kept),
        _ => dedupedTemplates(rest, Templates.PromptTemplate{name, description, hint, content, source, file} <> kept))(Unit{})

def loadedTemplates(result: Result<&2, &2, Paths.Error, Templates.LoadResult>) -> List<&2, Templates.PromptTemplate>:
  match result:
    case Fail{_}: Nil{}
    case Done{Templates.LoadResult{templates, _}}: dedupedTemplates(templates, Nil{})

def templatesFrom(+environment: Paths.Environment, +cwd: String, agentDir: String, noTemplates: Bool, paths: List<&2, String>) -> IO(List<&2, Templates.PromptTemplate>):
  match noTemplates paths:
    case True{} Nil{}: IO.pure(List<&2, Templates.PromptTemplate>, Nil{})
    case _ _:
      do IO<List<&2, Templates.PromptTemplate>>:
        result : Result<&2, &2, Paths.Error, Templates.LoadResult> <- Templates.loadPromptTemplates(environment, ".pi", Templates.LoadPromptTemplatesOptions{cwd, agentDir, paths, False{}})
        return loadedTemplates(result)

# upstream DefaultResourceLoader prompts, as for skills.
def templatesFor(+environment: Paths.Environment, options: CreateOptions, +resolved: PackageManager.ResolvedPaths) -> IO(List<&2, Templates.PromptTemplate>):
  match options:
    case CreateOptions{+cwd, +agentDir, _, _, _, _, _, _, _, _, _, _, _, _, _, ResourceOptions{_, _, promptPaths, +noTemplates}}:
      do IO<List<&2, Templates.PromptTemplate>>:
        merged : List<&2, String> <- mergedFrom(environment, cwd, List.append(&2, String, Bool.pick(List<&2, String>, noTemplates, Nil{}, resolvedPrompts(resolved)), cliPaths(environment, promptPaths)), Nil{})
        loaded : List<&2, Templates.PromptTemplate> <- templatesFrom(environment, cwd, agentDir, noTemplates, merged)
        return sourcedTemplates(loaded, resolvedResources(resolved))

def promptResult(value: Prompt.ResultOf(Prompt.SystemPromptSections())) -> Result<&2, &2, String, Prompt.SystemPromptSections()>:
  match value:
    case Done{sections}: Done{sections}
    case Fail{Prompt.InvalidSectionName{name}}: Fail{"Invalid system prompt section name: " ++ name}

def preparedWith(skills: List<&2, Skills.Skill>, templates: List<&2, Templates.PromptTemplate>, agentsFiles: List<&2, Prompt.ContextFile>, result: Result<&2, &2, String, Prompt.SystemPromptSections()>) -> Result<&2, &2, String, Prepared>:
  match result:
    case Fail{error}: Fail{error}
    case Done{sections}: Done{Prepared{sections, skills, templates, agentsFiles}}

# The system prompt sections again for other active tools, from the resources
# already loaded.
def sectionsForTools(source: LoadoutSource, active: List<&2, String>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>) -> Result<&2, &2, String, Prompt.SystemPromptSections()>:
  match source:
    case LoadoutSource{_, options, packageDir}: promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptions(options, active, contextList, skills)))

def preparedWithTools(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String, active: List<&2, String>) -> IO(Result<&2, &2, String, Prepared>):
  do IO<Result<&2, &2, String, Prepared>>:
    loaded : Resources.ContextFiles <- contextFilesFor(environment,options)
    +contextList : List<&2,Prompt.ContextFile> <- contextFilesReported(loaded)
    +resolved : PackageManager.ResolvedPaths <- resolvedFor(environment, options)
    +skills : List<&2, Skills.Skill> <- skillsFor(environment, options, resolved)
    templates : List<&2, Templates.PromptTemplate> <- templatesFor(environment, options, resolved)
    return preparedWith(skills, templates, contextList, promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptions(options, active, contextList, skills))))

def preparedFor(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String) -> IO(Result<&2, &2, String, Prepared>):
  preparedWithTools(environment, options, packageDir, activeNamesOf(toolSetupOf(options)))

def withSettings(options: CreateOptions, settings: Settings.SettingsManager) -> CreateOptions:
  match options:
    case CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, _, resources}: CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}
# Skills, prompt templates, context files and the system prompt again, under
# reloaded settings.
def reprepare(source: LoadoutSource, settings: Settings.SettingsManager, active: List<&2, String>) -> IO(Result<&2, &2, String, Prepared>):
  match source:
    case LoadoutSource{environment, options, packageDir}: preparedWithTools(environment, withSettings(options, settings), packageDir, active)
def sectionsOf(result: Result<&2, &2, String, Prepared>) -> Result<&2, &2, String, Prompt.SystemPromptSections()>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Prepared{sections, _, _, _}}: Done{sections}

def systemPromptFor(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String) -> IO(Result<&2, &2, String, Prompt.SystemPromptSections()>):
  do IO<Result<&2, &2, String, Prompt.SystemPromptSections()>>:
    prepared : Result<&2, &2, String, Prepared> <- preparedFor(environment, options, packageDir)
    return sectionsOf(prepared)

def levelOf(result: Models.ResolveCliModelResult) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match result:
    case Models.ResolveCliModelResult{_, level, _, _}: level

def noModels() -> String:
  "No models available.\n\nRun pi to log in with a provider, or set an API key environment variable such as OPENAI_API_KEY."

# A resolution error is a startup diagnostic (upstream main prints "Error: ").
def chosenFrom(models: Models.ModelRuntime, +settings: Settings.SettingsManager, error: Maybe<&2, String>, model: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Maybe<&2, Models.Model()>>):
  match error model:
    case Some{message} _: IO.pure(Result<&2, &2, String, Maybe<&2, Models.Model()>>, Fail{"Error: " ++ message})
    case None{} Some{chosen}: IO.pure(Result<&2, &2, String, Maybe<&2, Models.Model()>>, Done{Some{chosen}})
    case None{} None{}:
      do IO<Result<&2, &2, String, Maybe<&2, Models.Model()>>>:
        initial : Maybe<&2, Models.Model()> <- Models.findInitialModel(models, Settings.getDefaultProvider(settings), Settings.getDefaultModel(settings))
        return Done{initial}

def chosenModel(models: Models.ModelRuntime, settings: Settings.SettingsManager, resolved: Models.ResolveCliModelResult) -> IO(Result<&2, &2, String, Maybe<&2, Models.Model()>>):
  match resolved:
    case Models.ResolveCliModelResult{model, _, _, error}: chosenFrom(models, settings, error, model)

# The registered APIs stream through their native providers.
def supportedApi(api: Ai.ModelApi, +model: Models.Model()) -> Result<&2, &2, String, Maybe<&2, Models.Model()>>:
  match api:
    case Ai.OpenAIResponsesApi{}: Done{Some{model}}
    case Ai.OpenAICodexResponsesApi{}: Done{Some{model}}
    case Ai.AzureOpenAIResponsesApi{}: Done{Some{model}}
    case Ai.AnthropicMessagesApi{}: Done{Some{model}}
    case Ai.GoogleGenerativeAiApi{}: Done{Some{model}}
    case Ai.OpenAICompletionsApi{}: Done{Some{model}}
    case Ai.PiMessagesApi{}: Done{Some{model}}
    case Ai.MistralConversationsApi{}: Done{Some{model}}
    case Ai.BedrockConverseStreamApi{}: Done{Some{model}}
    case Ai.GoogleVertexApi{}: Done{Some{model}}
    case _: Fail{"Model " ++ Models.reference(model) ++ " uses an API this port does not stream yet."}

def supportedModel(+model: Models.Model()) -> Result<&2, &2, String, Maybe<&2, Models.Model()>>:
  supportedApi(modelApi(model), model)

def supported(selected: Maybe<&2, Models.Model()>) -> Result<&2, &2, String, Maybe<&2, Models.Model()>>:
  match selected:
    case None{}: Done{None{}}
    case Some{model}: supportedModel(model)

# A session's recorded model is restored when the command line names none
# and its provider has credentials; otherwise the usual resolution applies.
def authorizedRestore(+models: Models.ModelRuntime, found: Maybe<&2, Models.Model()>) -> IO(Maybe<&2, Models.Model()>):
  match found:
    case None{}: IO.pure(Maybe<&2, Models.Model()>, None{})
    case Some{+model}:
      do IO<Maybe<&2, Models.Model()>>:
        configured : Bool <- Models.hasConfiguredAuth(models, Models.modelProvider(model))
        return Bool.pick(Maybe<&2, Models.Model()>, configured, Some{model}, None{})

def restoredModel(+models: Models.ModelRuntime, seed: SessionSeed) -> IO(Maybe<&2, Models.Model()>):
  match seed:
    case SessionSeed{_, _, None{}, _}: IO.pure(Maybe<&2, Models.Model()>, None{})
    case SessionSeed{_, _, Some{S.SessionModel{provider, id}}, _}:
      do IO<Maybe<&2, Models.Model()>>:
        found : Maybe<&2, Models.Model()> <- Models.getModel(models, provider, id)
        authorizedRestore(models, found)

def chosenOrRestored(+models: Models.ModelRuntime, settings: Settings.SettingsManager, resolution: Models.ResolveCliModelResult, restored: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Maybe<&2, Models.Model()>>):
  match restored:
    case Some{model}: IO.pure(Result<&2, &2, String, Maybe<&2, Models.Model()>>, Done{Some{model}})
    case None{}: chosenModel(models, settings, resolution)

def restoreIf(+models: Models.ModelRuntime, named: Bool, seed: SessionSeed) -> IO(Maybe<&2, Models.Model()>):
  match named:
    case True{}: IO.pure(Maybe<&2, Models.Model()>, None{})
    case False{}: restoredModel(models, seed)

# upstream sorts an ambiguity's matches with localeCompare.
def collatedMatches(matches: List<&2, String>, loaded: Result<&2, &2, Collation.LoadError, Collation.Collator>) -> List<&2, String>:
  match loaded:
    case Done{collator}: Collation.sort(collator, matches)
    case Fail{_}: matches
def resolved(resolution: Models.Resolution, packageDir: String) -> IO(Models.ResolveCliModelResult):
  match resolution:
    case Models.Resolved{result}: IO.pure(Models.ResolveCliModelResult, result)
    case Models.AmbiguousAcross{cliModel, matches, hint}:
      do IO<Models.ResolveCliModelResult>:
        loaded : Result<&2, &2, Collation.LoadError, Collation.Collator> <- Collation.load(Path.join(packageDir, "packages/runtime/data"))
        return Models.ambiguityMessage(cliModel, collatedMatches(matches, loaded), hint)

# upstream main's --provider/--model resolution, reported as a warning.
def cliResolution(+models: Models.ModelRuntime, options: CreateOptions, packageDir: String) -> IO(Models.ResolveCliModelResult):
  match options:
    case CreateOptions{_, _, _, _, _, provider, cliModel, _, thinking, _, _, _, _, _, _, _}:
      do IO<Models.ResolveCliModelResult>:
        resolution : Models.Resolution <- Models.resolveCliModel(models, provider, cliModel, thinking)
        resolved(resolution, packageDir)

def reportResolution(resolution: Models.ResolveCliModelResult) -> IO(Unit):
  match resolution:
    case Models.ResolveCliModelResult{_, _, Some{warning}, _}: IO.print_err("Warning: " ++ warning)
    case _: IO.pure(Unit, Unit{})

# "--model <pattern>:<thinking>" sets the thinking level unless --thinking did.
def withSuffixThinking(options: CreateOptions, resolution: Models.ResolveCliModelResult) -> CreateOptions:
  match options resolution:
    case CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, None{}, systemPrompt, appendSystemPrompt, tools, contextFiles, seed, settings, resources} Models.ResolveCliModelResult{Some{_}, level, _, _}:
      CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, level, systemPrompt, appendSystemPrompt, tools, contextFiles, seed, settings, resources}
    case options _: options

def selectModel(+models: Models.ModelRuntime, options: CreateOptions, resolution: Models.ResolveCliModelResult) -> IO(Result<&2, &2, String, Maybe<&2, Models.Model()>>):
  match options:
    case CreateOptions{_, _, _, _, _, +provider, +cliModel, _, _, _, _, _, _, seed, settings, _}:
      do IO<Result<&2, &2, String, Maybe<&2, Models.Model()>>>:
        restored : Maybe<&2, Models.Model()> <- restoreIf(models, Maybe.is_some(&2, String, provider) || Maybe.is_some(&2, String, cliModel), seed)
        chosen : Result<&2, &2, String, Maybe<&2, Models.Model()>> <- chosenOrRestored(models, settings, resolution, restored)
        return Result.bind(&2, &2, String, Maybe<&2, Models.Model()>, Maybe<&2, Models.Model()>, chosen, supported)

def namedLevel(levels: List<&2, Ai.ModelThinkingLevel>, +text: String) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match levels:
    case Nil{}: None{}
    case +level <> rest: Bool.pick(Unit -> Maybe<&2, Ai.ModelThinkingLevel>, String.eq(Levels.name(level), text), _ => Some{level}, _ => namedLevel(rest, text))(Unit{})

def seededThinking(seed: SessionSeed) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match seed:
    case SessionSeed{_, _, _, None{}}: None{}
    case SessionSeed{_, _, _, Some{text}}: namedLevel(Levels.all(), text)

def hasSessionMessages(seed: SessionSeed) -> Bool:
  match seed:
    case SessionSeed{_, Nil{}, _, _}: False{}
    case _: True{}

# A resumed session restores its recorded level, or the settings default,
# or DEFAULT_THINKING_LEVEL.
def sessionThinking(+seed: SessionSeed, settingsDefault: Maybe<&2, Ai.ModelThinkingLevel>) -> Maybe<&2, Ai.ModelThinkingLevel>:
  Bool.pick(Maybe<&2, Ai.ModelThinkingLevel>, hasSessionMessages(seed), Some{Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.or(&2, Ai.ModelThinkingLevel, seededThinking(seed), settingsDefault), Defaults.DEFAULT_THINKING_LEVEL())}, None{})

# upstream createAgentSession: --thinking, else the resumed session's level,
# else the settings' per-model level, else the settings default, else
# DEFAULT_THINKING_LEVEL; clamped to the model's levels, and off without a
# model. A --model ":<level>" suffix arrives as the requested level.
def thinkingLevel(requested: Maybe<&2, Ai.ModelThinkingLevel>, seed: SessionSeed, +model: Models.Model(), +settings: Settings.SettingsManager) -> Ai.ModelThinkingLevel:
  +settingsDefault = Settings.getDefaultThinkingLevel(settings)
  +perModel = Settings.getModelThinkingLevel(Models.modelProvider(model), Models.modelId(model), settings)
  AiModels.clampThinkingLevel(Ai.JsonValue, model, Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.or(&2, Ai.ModelThinkingLevel, requested, Maybe.or(&2, Ai.ModelThinkingLevel, sessionThinking(seed, settingsDefault), Maybe.or(&2, Ai.ModelThinkingLevel, perModel, settingsDefault))), Defaults.DEFAULT_THINKING_LEVEL()))
def thinkingForSelection(+requested: Maybe<&2, Ai.ModelThinkingLevel>, +seed: SessionSeed, +settings: Settings.SettingsManager, selected: Maybe<&2, Models.Model()>) -> Ai.ModelThinkingLevel:
  match selected:
    case None{}: Ai.Off{}
    case Some{model}: thinkingLevel(requested, seed, model, settings)

def seededMessages(seed: SessionSeed) -> Maybe<&2, List<&2, T.AgentMessage<Unit, Details(), Custom()>>>:
  match seed:
    case SessionSeed{_, Nil{}, _, _}: None{}
    case SessionSeed{_, messages, _, _}: Some{messages}

def disabledImage() -> Ai.TextImageContent: Ai.TextImageText{Ai.TextContent{"Image reading is disabled.", None{}}}

def isDisabledNotice(block: Ai.TextImageContent) -> Bool:
  match block:
    case Ai.TextImageText{Ai.TextContent{"Image reading is disabled.", _}}: True{}
    case _: False{}

# Images become one placeholder text; consecutive placeholders collapse.
def withoutImages(blocks: List<&2, Ai.TextImageContent>, +previousNotice: Bool) -> List<&2, Ai.TextImageContent>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.TextImageImage{_} <> rest:
      +tail = withoutImages(rest, True{})
      Bool.pick(List<&2, Ai.TextImageContent>, previousNotice, tail, disabledImage() <> tail)
    case +block <> rest:
      +notice = isDisabledNotice(block)
      +tail = withoutImages(rest, notice)
      Bool.pick(List<&2, Ai.TextImageContent>, notice && previousNotice, tail, block <> tail)

def hasImage(blocks: List<&2, Ai.TextImageContent>) -> Bool:
  match blocks:
    case Nil{}: False{}
    case Ai.TextImageImage{_} <> _: True{}
    case _ <> rest: hasImage(rest)

def blockedContent(+blocks: List<&2, Ai.TextImageContent>) -> List<&2, Ai.TextImageContent>:
  Bool.pick(List<&2, Ai.TextImageContent>, hasImage(blocks), withoutImages(blocks, False{}), blocks)

def blockedMessage(message: Ai.Message<V.Value, V.Value, Unit, Details()>) -> Ai.Message<V.Value, V.Value, Unit, Details()>:
  match message:
    case Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks}, timestamp}}: Ai.User{Ai.UserMessage{Ai.UserBlocks{blockedContent(blocks)}, timestamp}}
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, blocks, details, usage, isError, timestamp}}: Ai.ToolResult{Ai.ToolResultMessage{id, name, blockedContent(blocks), details, usage, isError, timestamp}}
    case other: other

def blockedMessages(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: blockedMessage(message) <> blockedMessages(rest)

def converted(blockImages: Bool, +messages: List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>:
  match blockImages:
    case False{}: messages
    case True{}: blockedMessages(messages)

# Coding messages convert to LLM messages as upstream's convertToLlm does;
# with the blockImages setting, images are replaced by a placeholder text.
def convertMessages(blockImages: Bool, messages: T.AgentMessageArray(Unit, Details(), Custom())) -> IO(Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>):
  IO.pure(Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>, Done{converted(blockImages, Messages.convertToLlm(Unit, Details(), V.Value, messages))})

def createConverter(blockImages: Bool) -> IO(Converter()):
  C.create(~Bool, ~T.AgentMessageArray(Unit, Details(), Custom()), ~Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>, ~convertMessages, blockImages)

def disposeConverter(converter: Converter()) -> IO(Unit):
  C.dispose(T.AgentMessageArray(Unit, Details(), Custom()), Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, Unit, Details()>>>, converter)

def budget(value: Maybe<&2, W.U64>) -> Maybe<&2, F64>: Maybe.map(&2, W.U64, F64, F.fromU64, value)

def thinkingBudgets(value: Maybe<&2, Settings.ThinkingBudgetsSettings>) -> Maybe<&2, Ai.ThinkingBudgets>:
  match value:
    case None{}: None{}
    case Some{Settings.ThinkingBudgetsSettings{minimal, low, medium, high}}: Some{Ai.ThinkingBudgets{budget(minimal), budget(low), budget(medium), budget(high)}}

def maxRetryDelay(value: Settings.ResolvedProviderRetrySettings) -> F64:
  match value:
    case Settings.ResolvedProviderRetrySettings{_, _, delay}: F.fromU64(delay)

def seedSessionId(seed: SessionSeed) -> String:
  match seed:
    case SessionSeed{id, _, _, _}: id

# upstream createAgentSession's Agent options: no prompt or tools yet (the
# session declares its loadout with each prompt), the session id, the settings'
# steering/follow-up modes, transport, thinking budgets and retry delay.
def agentOptions(model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, stream: Stream(), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), +seed: SessionSeed, +settings: Settings.SettingsManager) -> Agent.AgentOptions<Unit, Details(), Custom(), Error(), Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{""}, model, Some{thinking}, Some{Nil{}}, seededMessages(seed)}}, Some{converter}, None{}, Some{stream}, Some{keys}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{Settings.getSteeringMode(settings)}, Some{Settings.getFollowUpMode(settings)}, Some{seedSessionId(seed)}, thinkingBudgets(Settings.getThinkingBudgets(settings)), Some{Settings.getTransport(settings)}, Some{maxRetryDelay(Settings.getProviderRetrySettings(settings))}, None{}}

# The tools download fd and rg through the agent's own fetch.
def environment(paths: Paths.Environment, cwd: String, agentDir: String, packageDir: String, fetch: Fetch.Fetch(Unit), queue: Queue.Queue, context: Ctx.ContextSource()) -> Tools.Environment:
  Tools.Environment{paths, cwd, Manager.ToolsManager{Path.join(agentDir, "bin"), urlContext(), Some{fetch}}, queue, Path.join(packageDir, "packages/runtime/data"), context}

def pathsError(error: FS.Error) -> String: "Could not resolve the working directory"

def disposeServices(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter()) -> IO(Unit):
  do IO<Unit>:
    disposeConverter(converter)
    C.dispose(String, Result<&2, &2, Error(), Maybe<&2, String>>, keys)
    Loop.disposeValidation(Error(), validator)
    StreamFn.dispose(Unit, Details(), LoopConfig(), Error(), registry)
    C.dispose(Providers.Input(LoopConfig(), Unit, Details()), Providers.Output(Unit, Error()), stream)
    Tools.disposeTools(tools)
    Queue.dispose(queue)
    Models.dispose(models)
    Auth.disposeStore(credentialStore)
    Runtime.dispose(credentials)
    Auth.disposeStore(storageStore)
    Storage.dispose(storage)
    disposeTransport(transport)

def disposeLoadout(loadout: Loadout) -> IO(Unit):
  match loadout:
    case Loadout{_, _, _, _, None{}, _, _, _}: IO.pure(Unit, Unit{})
    case Loadout{_, _, _, _, Some{runner}, _, _, _}: ExtensionRunner.dispose(runner)

# Assembly with cleanup on every failure path.
def constructed(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, loadout: Loadout, result: Result<&2, &2, StreamFn.MissingDefault, Owner()>) -> IO(Outcome(AgentRuntime)):
  match result:
    case Done{agent}: IO.pure(Outcome(AgentRuntime), Done{AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}})
    case Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter)
        disposeLoadout(loadout)
        return Fail{StreamFn.errorMessage(error)}

def disposeBase(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, extensions: ExtensionRunner.ExtensionRunner) -> IO(Unit):
  do IO<Unit>:
    ExtensionRunner.dispose(extensions)
    Models.dispose(models)
    Auth.disposeStore(credentialStore)
    Runtime.dispose(credentials)
    Auth.disposeStore(storageStore)
    Storage.dispose(storage)
    disposeTransport(transport)

def createToolList(names: List<&2, Tools.ToolName>, paths: Paths.Environment, cwd: String, agentDir: String, packageDir: String, fetch: Fetch.Fetch(Unit), context: Ctx.ContextSource(), borrowed: Queue.Owner & Queue.Queue) -> IO(Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)):
  match borrowed:
    case Tuple{queue, handle}:
      do IO<Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)>:
        owners : List<&1, Tools.ToolOwner> <- Tools.createTools(names, environment(paths, cwd, agentDir, packageDir, fetch, handle, context), toolsOptions())
        return (queue, Tools.borrowTools(owners))

def nameOfTool(tool: Tools.Tool()) -> String:
  match tool:
    case T.AgentTool{name, _, _, _, _, _, _, _, _}: name

def toolNamed(tools: List<&2, Tools.Tool()>, +name: String) -> Maybe<&2, Tools.Tool()>:
  match tools:
    case Nil{}: None{}
    case +tool <> rest: Bool.pick(Unit -> Maybe<&2, Tools.Tool()>, String.eq(nameOfTool(tool), name), _ => Some{tool}, _ => toolNamed(rest, name))(Unit{})

# upstream setActiveToolsByName: the registered tools named, in that order;
# unknown names are ignored.
def activeTools(+registry: List<&2, Tools.Tool()>, names: List<&2, String>) -> List<&2, Tools.Tool()>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +tail = activeTools(registry, rest)
      Maybe.default(&2, List<&2, Tools.Tool()>, Maybe.map(&2, Tools.Tool(), List<&2, Tools.Tool()>, tool => tool <> tail, toolNamed(registry, name)), tail)

def loadoutFrom(prepared: Prepared, +registry: List<&2, Tools.Tool()>, extensions: ExtensionRunner.ExtensionRunner, source: LoadoutSource) -> Loadout:
  match prepared source:
    case Prepared{sections, skills, templates, agentsFiles} LoadoutSource{paths, +options, packageDir}: Loadout{sections, activeTools(registry, activeNamesOf(toolSetupOf(options))), skills, templates, Some{extensions}, agentsFiles, Some{LoadoutSource{paths, options, packageDir}}, registry}

def assembled(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, created: Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>), +stream: Stream(), +registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), +validator: Loop.Validator(Error()), +keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, +converter: Converter(), prepared: Prepared, +model: Maybe<&2, Models.Model()>, +thinking: Ai.ModelThinkingLevel, seed: SessionSeed, settings: Settings.SettingsManager, extensions: ExtensionRunner.ExtensionRunner, source: LoadoutSource) -> IO(Outcome(AgentRuntime)):
  match created:
    case Tuple{queue, Tuple{owners, tools}}:
      do IO<Outcome(AgentRuntime)>:
        result : Result<&2, &2, StreamFn.MissingDefault, Owner()> <- Agent.new(~Unit, ~Details(), ~Custom(), ~Error(), ~Unit, agentOptions(model, thinking, stream, keys, converter, seed, settings), registry, validator, Tools.emptyDetails())
        constructed(transport, storage, storageStore, credentials, credentialStore, models, queue, owners, stream, registry, validator, keys, converter, model, thinking, loadoutFrom(prepared, tools, extensions, source), result)

def withModelFields(+cwd: String, +agentDir: String, packageDir: String, +apiKey: Maybe<&2, String>, requested: Maybe<&2, Ai.ModelThinkingLevel>, +seed: SessionSeed, +settings: Settings.SettingsManager, +names: List<&2, Tools.ToolName>, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, +models: Models.ModelRuntime, paths: Paths.Environment, +prompt: Result<&2, &2, String, Prepared>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>, source: LoadoutSource, +extensions: ExtensionRunner.ExtensionRunner) -> IO(Outcome(AgentRuntime)):
  match transport prompt selected:
    case Transport{+authorizer, runtime, +fetch} Done{prompt} Done{+model}:
      do IO<Outcome(AgentRuntime)>:
        queue : Queue.Owner <- Queue.create()
        +context : Ctx.ContextSource() <- IO.pure(Ctx.ContextSource(), Some{ExtensionRunner.createContext(extensions)})
        created : Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) <- createToolList(names, paths, cwd, agentDir, packageDir, fetch, context, Queue.borrow(queue))
        +stream : Stream() <- createStream(authorizer, fetch, requestDefaults(settings), KeySource{models, apiKey})
        +registry : StreamFn.Registry(Unit, Details(), LoopConfig(), Error()) <- StreamFn.create(Unit, Details(), LoopConfig(), Error())
        +validator : Loop.Validator(Error()) <- Loop.createPlain(~Error(), ~validationError)
        +keys : C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>> <- C.create(~KeySource, ~String, ~Result<&2, &2, Error(), Maybe<&2, String>>, ~resolveKey, KeySource{models, apiKey})
        +converter : Converter() <- createConverter(Settings.getBlockImages(settings))
        assembled(Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, created, stream, registry, validator, keys, converter, prompt, model, thinkingForSelection(requested, seed, settings, model), seed, settings, extensions, source)
    case transport Fail{error} _:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, credentials, credentialStore, models, extensions)
        return Fail{error}
    case transport _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, credentials, credentialStore, models, extensions)
        return Fail{error}

def registryOf(setup: ToolSetup) -> List<&2, Tools.ToolName>:
  match setup:
    case ToolSetup{registry, _}: registry

def withModel(+options: CreateOptions, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, +paths: Paths.Environment, prompt: Result<&2, &2, String, Prepared>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>, extensions: ExtensionRunner.ExtensionRunner) -> IO(Outcome(AgentRuntime)):
  match options:
    case CreateOptions{cwd, agentDir, _, _, +packageDir, _, _, apiKey, thinking, _, _, _, _, seed, settings, _}: withModelFields(cwd, agentDir, packageDir, apiKey, thinking, seed, settings, registryOf(toolSetupOf(options)), transport, storage, storageStore, credentials, credentialStore, models, paths, prompt, selected, LoadoutSource{paths, options, packageDir}, extensions)

# A runtime API key changes the provider's availability (upstream
# setRuntimeApiKey refreshes it).
def applyKey(credentials: Runtime.RuntimeCredentials, +models: Models.ModelRuntime, apiKey: Maybe<&2, String>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>) -> IO(Unit):
  match apiKey selected:
    case Some{key} Done{Some{model}}:
      +provider = Models.modelProvider(model)
      do IO<Unit>:
        Runtime.setRuntimeApiKey(credentials, provider, key)
        Models.refreshProviderAvailability(models, provider)
    case _ _: IO.pure(Unit, Unit{})

# Extensions (upstream resource loader and agent-session-services)
# ------------------------------------------------------------------

def cwdOf(options: CreateOptions) -> String:
  match options:
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: cwd

type Extensions is Data:
  Extensions{runner: ExtensionRunner.ExtensionRunner, loadErrors: List<&2, ExtensionTypes.LoadError>, providerErrors: List<&2, ExtensionTypes.ExtensionError>}

def runnerOf(extensions: Extensions) -> ExtensionRunner.ExtensionRunner:
  match extensions:
    case Extensions{runner, _, _}: runner

def loadMessages(errors: List<&2, ExtensionTypes.LoadError>) -> List<&2, String>:
  match errors:
    case Nil{}: Nil{}
    case ExtensionTypes.LoadError{path, error} <> rest: ("Error: Failed to load extension \"" ++ path ++ "\": " ++ error) <> loadMessages(rest)

def providerMessages(errors: List<&2, ExtensionTypes.ExtensionError>) -> List<&2, String>:
  match errors:
    case Nil{}: Nil{}
    case ExtensionTypes.ExtensionError{path, _, error, _} <> rest: ("Error: Extension \"" ++ path ++ "\" error: " ++ error) <> providerMessages(rest)

# upstream main: extension load and provider registration errors are runtime
# errors that stop startup, with a hint after load failures.
def extensionFailure(extensions: Extensions) -> Maybe<&2, String>:
  match extensions:
    case Extensions{_, Nil{}, Nil{}}: None{}
    case Extensions{_, Nil{}, providerErrors}: Some{String.join(providerMessages(providerErrors), "\n")}
    case Extensions{_, loadErrors, providerErrors}: Some{String.join(List.append(&2, String, providerMessages(providerErrors), loadMessages(loadErrors)), "\n") ++ "\nHint: Start without extensions using \"" ++ AppConfig.appName() ++ " -ne\"."}

def failedWith(failure: Maybe<&2, String>, prompt: Result<&2, &2, String, Prepared>) -> Result<&2, &2, String, Prepared>:
  match failure:
    case None{}: prompt
    case Some{message}: Fail{message}

# The built-in extensions load as inline factories and their queued providers
# join the model runtime (upstream createAgentSessionServices); the runner is
# created for the runtime. Upstream's following offline refresh restores
# cached catalogs: here each registration already refreshes, and built-in
# providers have no dynamic catalog, so it would only repeat the
# availability check.
def loadExtensions(+cwd: String, +models: Models.ModelRuntime) -> IO(Extensions):
  do IO<Extensions>:
    +runtime : ExtensionTypes.ExtensionRuntime() <- ExtensionLoader.createExtensionRuntime()
    loadErrors : List<&2, ExtensionTypes.LoadError> <- ExtensionLoader.loadExtensionFactories(runtime, BuiltinExtensions.builtInExtensions())
    providerErrors : List<&2, ExtensionTypes.ExtensionError> <- ExtensionLoader.bindProviders(runtime, models, None{})
    runner : ExtensionRunner.ExtensionRunner <- ExtensionRunner.create(runtime, cwd, models)
    return Extensions{runner, loadErrors, providerErrors}

def storageStep(+options: CreateOptions, +packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, +paths: Paths.Environment, borrowed: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Outcome(AgentRuntime)):
  match transport borrowed:
    case Transport{+authorizer, runtime, +fetch} Tuple{storage, view}:
      do IO<Outcome(AgentRuntime)>:
        +storageStore : Auth.CredentialStore <- Storage.store(view)
        +credentials : Runtime.RuntimeCredentials <- Runtime.create(storageStore)
        +credentialStore : Auth.CredentialStore <- Runtime.store(credentials)
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch, urlContext())
        anthropicOAuth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, urlContext())
        +models : Models.ModelRuntime <- Models.createWithAnthropic(credentialStore, oauth, Some{anthropicOAuth})
        +extensions : Extensions <- loadExtensions(cwdOf(options), models)
        +resolution : Models.ResolveCliModelResult <- cliResolution(models, options, packageDir)
        reportResolution(resolution)
        +selected : Result<&2, &2, String, Maybe<&2, Models.Model()>> <- selectModel(models, options, resolution)
        applyKey(credentials, models, apiKey, selected)
        prompt : Result<&2, &2, String, Prepared> <- preparedFor(paths, options, packageDir)
        withModel(withSuffixThinking(options, resolution), Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, paths, failedWith(extensionFailure(extensions), prompt), selected, runnerOf(extensions))

def withPathsFields(options: CreateOptions, authPath: String, packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, paths: Paths.Environment) -> IO(Outcome(AgentRuntime)):
  do IO<Outcome(AgentRuntime)>:
    storage : Storage.AuthStorageOwner <- Storage.create(authPath)
    storageStep(options, packageDir, apiKey, transport, paths, Storage.borrow(storage))

def withPaths(options: CreateOptions, transport: Transport, +paths: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Outcome(AgentRuntime)):
  match options paths:
    case _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeTransport(transport)
        return Fail{pathsError(error)}
    case CreateOptions{cwd, agentDir, +authPath, bundlePath, +packageDir, provider, model, +apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources} Done{paths}: withPathsFields(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}, authPath, packageDir, apiKey, transport, paths)

# --api-key applies to the selected model's provider for this process only.
def withTransport(+options: CreateOptions, transport: Outcome(Transport)) -> IO(Outcome(AgentRuntime)):
  match transport:
    case Fail{error}: IO.pure(Outcome(AgentRuntime), Fail{error})
    case Done{transport}:
      do IO<Outcome(AgentRuntime)>:
        paths : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(urlContext())
        withPaths(options, transport, paths)

def create(options: CreateOptions) -> IO(Outcome(AgentRuntime)):
  match options:
    case CreateOptions{cwd, agentDir, authPath, +bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}:
      do IO<Outcome(AgentRuntime)>:
        transport : Outcome(Transport) <- createTransport(bundlePath)
        withTransport(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}, transport)

def agentOf(runtime: AgentRuntime) -> AgentRuntime & Owner():
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, model, thinking, loadout}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, agent)
def managedTools(runtime: AgentRuntime,agentDir: String) -> AgentRuntime & Manager.ToolsManager:
  match runtime:
    case AgentRuntime{Transport{authorizer,network,+fetch},storage,storageStore,credentials,credentialStore,models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout}:
      (AgentRuntime{Transport{authorizer,network,fetch},storage,storageStore,credentials,credentialStore,models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout},Manager.ToolsManager{Path.join(agentDir,"bin"),urlContext(),Some{fetch}})

def selectionOf(runtime: AgentRuntime) -> AgentRuntime & Selection:
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, +model, +thinking, loadout}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, Selection{model, thinking})

def loadoutOf(runtime: AgentRuntime) -> AgentRuntime & Loadout:
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, +loadout}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, loadout)

# Adjust the startup selection before any SessionManager model entry is written.
def selectStartup(runtime: AgentRuntime,+chosen: Models.Model(),+level: Ai.ModelThinkingLevel) -> IO(AgentRuntime):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, _, _, loadout}:
      do IO<AgentRuntime>:
        Agent.setModel(Unit,Details(),Custom(),Error(),Unit,agent,chosen)
        Agent.setThinkingLevel(Unit,Details(),Custom(),Error(),Unit,agent,level)
        return AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, Some{chosen}, level, loadout}

def dispose(runtime: AgentRuntime) -> IO(Unit):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, _, _, loadout}:
      do IO<Unit>:
        Agent.dispose(Unit, Details(), Custom(), Error(), Unit, agent)
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter)
        disposeLoadout(loadout)
