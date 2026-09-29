import Base
import ../../../ai/src/api/openai-codex-sessions.bend as CodexSessions
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/providers/radius.bend as Radius
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../../../ai/src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../../../ai/src/api/openai-responses.bend as Responses
import ./anthropic-provider.bend as Anthropic
import ./google-provider.bend as Google
import ./openai-completions-provider.bend as Completions
import ./stream-providers.bend as StreamProviders
import ../../../ai/src/api/bedrock-converse-stream.bend as Bedrock
import ../../../ai/src/api/openai-client.bend as Client
import ../../../ai/src/utils/tool-declaration.bend as Declaration
import ../../../ai/src/utils/validation.bend as Validation
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/providers.bend as Providers
import ../../../agent/src/stream-fn.bend as StreamFn
import ../../../agent/src/types.bend as T
import ../../../runtime/src/fetch.bend as Fetch
import ../../../runtime/src/http-proxy.bend as Proxy
import ./http-dispatcher.bend as Dispatcher
import ../../../runtime/src/ref.bend as Ref
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
import ./tools/read.bend as Read
import ./tools/bash.bend as Bash
import ../utils/tools-manager.bend as Manager
import ./tools/file-mutation-queue.bend as Queue
import ./extensions/context.bend as Ctx
import ./extensions/tool-context.bend as ToolContext
import ./extensions/loader.bend as ExtensionLoader
import ./extensions/runner.bend as ExtensionRunner
import ./extensions/types.bend as ExtensionTypes
import ../config.bend as AppConfig
import ./provider-composer.bend as Composer

# The owned services behind one agent: transport, credentials, model runtime,
# settings-driven selection, tools and the Agent itself. This is the print-mode
# slice of upstream's AgentSessionServices/AgentSessionRuntime; the session
# record and persistence live in agent-session.bend.

def Error() -> Data: Tools.ToolError
def Details() -> Data: Tools.ToolDetails
# The agent's custom messages are pi's coding messages (bash executions,
# extension messages, branch and compaction summaries), as upstream's
# AgentMessage union; extension payloads are JSON values.
def Custom() -> Data: Messages.CodingMessage<V.Value>
def LoopConfig() -> Data: T.AgentLoopConfig<V.Value, Details(), Custom(), Error(), Unit>
def Owner() -> Data: Agent.Agent<V.Value, Details(), Custom(), Error(), Unit>
def Converter() -> Data: Agent.Converter(V.Value, Details(), Custom(), Error())
def Stream() -> Data: T.StreamFn(V.Value, Details(), LoopConfig(), Error())
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

def httpOptions() -> HTTP.Options: Dispatcher.httpOptions()

def security(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> HTTP.Security:
  HTTP.WithTLS{authorizer, TLS.defaults()}

def providerConfig(authorizer: C.Callback<URL.Host, TLSClient.Authorization>, agent: String) -> Responses.Config:
  Responses.Config{urlContext(), Client.Defaults{agent, R.new(String), None{}, None{}}, files(), httpOptions(), security(authorizer), 65536n, False{}}

type Transport is Type:
  Transport{authorizer: C.Callback<URL.Host, TLSClient.Authorization>, runtime: Fetch.Runtime, fetch: Fetch.Fetch(Unit), codexSessions: CodexSessions.Pool<Unit>}

def trustError(error: Trust.Error) -> String:
  match error:
    case Trust.Read{_}: "Could not read the certificate bundle"
    case Trust.Text{_}: "The certificate bundle is not valid PEM"
    case Trust.Certificate{_}: "The certificate bundle holds an invalid certificate"
    case Trust.UnsupportedLabel{_}: "The certificate bundle holds an unsupported PEM block"
    case Trust.EmptyBundle{}: "The certificate bundle holds no certificates"

def transportOf(codexSessions: CodexSessions.Pool<Unit>, authorizer: C.Callback<URL.Host, TLSClient.Authorization>, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> Outcome(Transport):
  match pair:
    case Tuple{runtime, fetch}: Done{Transport{authorizer, runtime, fetch, codexSessions}}

def withRuntime(+authorizer: C.Callback<URL.Host, TLSClient.Authorization>, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Outcome(Transport)):
  match result:
    case Fail{_}:
      do IO<Outcome(Transport)>:
        C.dispose(URL.Host, TLSClient.Authorization, authorizer)
        return Fail{"Could not initialize the network runtime"}
    case Done{runtime}:
      do IO<Outcome(Transport)>:
        pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callbackWithSecurity(~Unit, runtime, security(authorizer))
        codexSessions : CodexSessions.Pool<Unit> <- CodexSessions.create(Unit, CodexSessions.defaults())
        return transportOf(codexSessions, authorizer, pair)

def withProxies(anchors: List<&2, X509.Certificate>, proxies: Result<&2, &2, String, Proxy.Config>) -> IO(Outcome(Transport)):
  match proxies:
    case Fail{error}: IO.pure(Outcome(Transport), Fail{error})
    case Done{config}:
      do IO<Outcome(Transport)>:
        +authorizer : C.Callback<URL.Host, TLSClient.Authorization> <- Trust.newSAN(Trust.SANPolicy{anchors, 256n})
        runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.createWithProxy(files(), httpOptions(), config)
        withRuntime(authorizer, runtime)

# upstream applyHttpProxySettings + configureHttpDispatcher: every request
# goes through the proxies of the environment, where the httpProxy setting
# stands in for unset HTTP_PROXY/HTTPS_PROXY (undici's EnvHttpProxyAgent with
# CONNECT tunnels). An invalid proxy URL fails the transport, as undici's
# constructor throws.
def withBundle(httpProxy: Maybe<&2, String>, bundle: Result<&2, &2, Trust.Error, List<&2, X509.Certificate>>) -> IO(Outcome(Transport)):
  match bundle:
    case Fail{error}: IO.pure(Outcome(Transport), Fail{trustError(error)})
    case Done{anchors}:
      do IO<Outcome(Transport)>:
        proxies : Result<&2, &2, String, Proxy.Config> <- Proxy.fromEnvironmentWith(urlContext(), httpProxy)
        withProxies(anchors, proxies)

# The CA bundle path: SSL_CERT_FILE or the Debian/Ubuntu system bundle.
# `httpProxy` is the global settings' value (upstream main applies
# getGlobalSettings().httpProxy).
def createTransportWith(bundlePath: String, httpProxy: Maybe<&2, String>) -> IO(Outcome(Transport)):
  do IO<Outcome(Transport)>:
    bundle : Result<&2, &2, Trust.Error, List<&2, X509.Certificate>> <- Trust.load(bundlePath, 4194304n)
    withBundle(httpProxy, bundle)

# Without settings: the proxies of the environment alone.
def createTransport(bundlePath: String) -> IO(Outcome(Transport)): createTransportWith(bundlePath, None{})

def globalHttpProxy(settings: Settings.SettingsManager) -> Maybe<&2, String>: Settings.selectedHttpProxy(Settings.get(Settings.getGlobalSettings(settings), "httpProxy"))

def disposeTransport(transport: Transport) -> IO(Unit):
  match transport:
    case Transport{authorizer, runtime, fetch, codexSessions}:
      do IO<Unit>:
        CodexSessions.dispose(Unit, codexSessions)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(runtime)
        C.dispose(URL.Host, TLSClient.Authorization, authorizer)

# Stream function
# ---------------

def project(config: LoopConfig()) -> Responses.SimpleStreamOptions(Unit, Unit, Error()):
  T.toSimpleStreamOptions(V.Value, Details(), Custom(), Error(), Unit, config)

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

# The agent's stream function (upstream sdk's streamFn): each request gets
# the settings' defaults and goes through the model runtime, which resolves
# its auth and dispatches it to its provider. `headers` runs
# before_provider_headers on the assembled headers.
type ProviderStreams is Data:
  ProviderStreams{fetch: Fetch.Fetch(Unit), defaults: RequestDefaults, keys: KeySource, headers: Models.RequestTransforms}

def selectedOptions(options: Maybe<&2, Composer.StreamOptions()>) -> Maybe<&2, Composer.StreamOptions()>: options

# Like upstream's global fetch, requests share the runtime's fetch, so
# keep-alive connections carry over between turns.
def withRequest(fetch: Fetch.Fetch(Unit), preset: RequestDefaults, options: Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>) -> Ai.SimpleStreamOptions<Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), Error()>:
  match preset options:
    case RequestDefaults{timeout, retries, delay, connect} Ai.SimpleStreamOptions{signal, telemetry, apiKey, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, apiKey, Maybe.or(&2, Fetch.Fetch(Unit), shared, Some{fetch}), env, onPayload, onResponse, headers, Maybe.or(&2, F64, timeoutMs, Some{timeout}), Maybe.or(&2, F64, maxRetries, retries), Maybe.or(&2, F64, maxRetryDelayMs, Some{delay}), temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, Maybe.or(&2, F64, websocketConnectTimeoutMs, connect), metadata, toolChoice, reasoning, deferred, budgets}

def identityOptions(options: Composer.StreamOptions()) -> Responses.SimpleStreamOptions(Unit, Unit, Error()): options

# The network a proxied Bedrock request runs on: the transport's.
def bedrockHandler(config: Responses.Config) -> Bedrock.Handler:
  match config:
    case Responses.Config{_, _, files, options, security, _, _}: Bedrock.Handler{files, options, security}

# The built-in apis over the runtime's transport (upstream's api registry
# with the global fetch).
def selectedProvider(codexSessions: CodexSessions.Pool<Unit>, responses: Responses.Config, fetch: Fetch.Fetch(Unit), googleToolCalls: Ref.Ref<Nat>, model: Models.Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Details()>, +options: Maybe<&2, Composer.StreamOptions()>, api: Ai.ModelApi) -> IO(Providers.Output(V.Value, Error())):
  match api:
    case Ai.AnthropicMessagesApi{}: Anthropic.open(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.GoogleGenerativeAiApi{}: Google.open(fetch, urlContext(), googleToolCalls, model, context, selectedOptions(options))
    case Ai.OpenAICompletionsApi{}: Completions.open(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.PiMessagesApi{}: StreamProviders.piMessages(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.MistralConversationsApi{}: StreamProviders.mistral(fetch, urlContext(), model, context, selectedOptions(options))
    case Ai.BedrockConverseStreamApi{}: StreamProviders.bedrock(fetch, urlContext(), bedrockHandler(responses), model, context, selectedOptions(options))
    case Ai.GoogleVertexApi{}: StreamProviders.vertex(fetch, urlContext(), model, context, selectedOptions(options))
    case _: Providers.openResponsesWithSessions(~Composer.StreamOptions(), ~Unit, ~V.Value, ~Details(), ~Error(), ~identityOptions, ~render, ~failure, Some{codexSessions}, responses, T.StreamInput{model, context, options})

type ApiTransport is Data:
  ApiTransport{responses: Responses.Config, fetch: Fetch.Fetch(Unit), googleToolCalls: Ref.Ref<Nat>, codexSessions: CodexSessions.Pool<Unit>}

def openApi(transport: ApiTransport, request: Composer.StreamRequest()) -> IO(Providers.Output(V.Value, Error())):
  match transport request:
    case ApiTransport{responses, fetch, calls, codexSessions} T.StreamInput{+model, context, options}: selectedProvider(codexSessions, responses, fetch, calls, model, context, options, modelApi(model))

# The model runtime's api stream over this transport; the model runtime
# owns it once installed.
def createApiStream(codexSessions: CodexSessions.Pool<Unit>, authorizer: C.Callback<URL.Host, TLSClient.Authorization>, fetch: Fetch.Fetch(Unit)) -> IO(Composer.ProviderStream()):
  do IO<Composer.ProviderStream()>:
    agent : String <- IO.try(String, UserAgent.get())
    calls : Ref.Ref<Nat> <- Ref.new(Nat, 0n)
    C.create(~ApiTransport, ~Composer.StreamRequest(), ~Providers.Output(V.Value, Error()), ~openApi, ApiTransport{providerConfig(authorizer, agent), fetch, calls, codexSessions})

# --api-key: the request carries the runtime key unless it has its own.
def withKey(apiKey: Maybe<&2, String>, options: Composer.StreamOptions()) -> Composer.StreamOptions():
  match options:
    case Ai.SimpleStreamOptions{signal, telemetry, key, shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}:
      Ai.SimpleStreamOptions{signal, telemetry, Maybe.or(&2, String, key, apiKey), shared, env, onPayload, onResponse, headers, timeoutMs, maxRetries, maxRetryDelayMs, temperature, samplingParams, maxTokens, transport, cacheRetention, sessionId, websocketConnectTimeoutMs, metadata, toolChoice, reasoning, deferred, budgets}

def openProvider(config: ProviderStreams, input: Providers.Input(LoopConfig(), V.Value, Details())) -> IO(Providers.Output(V.Value, Error())):
  match config input:
    case ProviderStreams{+fetch, defaults, KeySource{+models, apiKey}, headers} T.StreamInput{model, context, options}:
      Models.streamSimple(models, T.StreamInput{model, context, Maybe.map(&2, LoopConfig(), Composer.StreamOptions(), value => withKey(apiKey, withRequest(fetch, defaults, project(value))), options)}, headers)

def createStream(fetch: Fetch.Fetch(Unit), defaults: RequestDefaults, keys: KeySource, headers: Models.RequestTransforms) -> IO(Stream()):
  C.create(~ProviderStreams, ~Providers.Input(LoopConfig(), V.Value, Details()), ~Providers.Output(V.Value, Error()), ~openProvider, ProviderStreams{fetch, defaults, keys, headers})

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
  SessionSeed{sessionId: String, messages: List<&2, T.AgentMessage<V.Value, Details(), Custom()>>, model: Maybe<&2, S.SessionModel>, thinking: Maybe<&2, String>}

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
# `builtins` configures the built-in tools. Upstream SDK callers get this
# through `customTools` built with createBashToolDefinition(cwd, options) and
# the like, which replace the built-ins of the same name. Native SDK callers
# can pass those definitions through customTools or configure these built-in
# options directly. Settings still supply what upstream's _buildRuntime takes from
# them (read autoResizeImages, bash commandPrefix and shellPath) where the
# caller leaves it unset.
type NoTools is Data:
  NoToolsAll{}
  NoToolsBuiltin{}
type ToolSelection is Data:
  ToolSelection{tools: Maybe<&2, List<&2, String>>, noTools: Maybe<&2, NoTools>, excludeTools: Maybe<&2, List<&2, String>>, builtins: Maybe<&2, Tools.ToolsOptions>}
def defaultToolSelection() -> ToolSelection: ToolSelection{None{}, None{}, None{}, None{}}

def builtinsOf(selection: ToolSelection) -> Tools.ToolsOptions:
  match selection:
    case ToolSelection{_, _, _, builtins}: Maybe.default(&2, Tools.ToolsOptions, builtins, Tools.defaultOptions())

def orSetting(-A: Data, value: Maybe<&2, A>, setting: Maybe<&2, A>) -> Maybe<&2, A>:
  match value:
    case Some{found}: Some{found}
    case None{}: setting

def readWithSettings(read: Maybe<&2, Read.ReadToolOptions>, autoResize: Bool) -> Read.ReadToolOptions:
  match read:
    case None{}: Read.ReadToolOptions{Some{autoResize}, None{}, None{}, None{}}
    case Some{Read.ReadToolOptions{resize, profile, operations, processor}}: Read.ReadToolOptions{orSetting(Bool, resize, Some{autoResize}), profile, operations, processor}

def bashWithSettings(bash: Maybe<&2, Bash.BashToolOptions>, prefix: Maybe<&2, String>, shellPath: Maybe<&2, String>) -> Bash.BashToolOptions:
  match bash:
    case None{}: Bash.BashToolOptions{None{}, prefix, shellPath, None{}, None{}}
    case Some{Bash.BashToolOptions{operations, ownPrefix, ownShell, expose, hook}}: Bash.BashToolOptions{operations, orSetting(String, ownPrefix, prefix), orSetting(String, ownShell, shellPath), expose, hook}

# upstream _buildRuntime: createAllToolDefinitions(cwd, {read: {autoResizeImages},
# bash: {commandPrefix, shellPath}}) from the settings.
def toolsOptionsFor(builtins: Tools.ToolsOptions, +settings: Settings.SettingsManager, paths: Paths.Environment) -> Tools.ToolsOptions:
  match builtins:
    case Tools.ToolsOptions{read, bash, edit, write, find, grep, ls}:
      Tools.ToolsOptions{Some{readWithSettings(read, Settings.getImageAutoResize(settings))}, Some{bashWithSettings(bash, Settings.getShellCommandPrefix(settings), Result.default(&2, &2, Paths.Error, Maybe<&2, String>, Settings.getShellPath(paths, settings), None{}))}, edit, write, find, grep, ls}

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
    case ToolSelection{Some{names}, _, _, _}: Some{names}
    case ToolSelection{None{}, Some{NoToolsAll{}}, _, _}: Some{Nil{}}
    case _: None{}

def excludedOf(selection: ToolSelection) -> List<&2, String>:
  match selection:
    case ToolSelection{_, _, excluded, _}: Maybe.default(&2, List<&2, String>, excluded, Nil{})

# upstream isAllowedTool
def isAllowedTool(allowed: Maybe<&2, List<&2, String>>, excluded: List<&2, String>, +name: String) -> Bool:
  Bool.and(Maybe.default(&2, Bool, Maybe.map(&2, List<&2, String>, Bool, names => containsText(names, name), allowed), True{}), Bool.not(containsText(excluded, name)))

def defaultActiveToolNames() -> List<&2, String>: ["read", "bash", "edit", "write"]

def initialRequested(selection: ToolSelection, configured: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match selection:
    case ToolSelection{Some{names}, _, _, _}: names
    case ToolSelection{None{}, Some{_}, _, _}: Nil{}
    case ToolSelection{None{}, None{}, _, _}: Maybe.default(&2, List<&2, String>, configured, defaultActiveToolNames())

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
# `resourceLoader` is the injected ResourceLoader of an SDK session (upstream
# AgentSession.resourceLoader); without one the resources come from the
# options (the CLI path).
type LoadoutSource is Data: LoadoutSource{environment: Paths.Environment, options: CreateOptions, packageDir: String, resourceLoader: Maybe<&2, Resources.ResourceLoader>}

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
  AgentRuntime{transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(V.Value, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), agent: Owner(), model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, loadout: Loadout}

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
def guidelines(names: List<&2, Tools.ToolName>, +builtins: Tools.ToolsOptions, +record: R.Record<List<&2, String>>) -> R.Record<List<&2, String>>:
  match names:
    case Nil{}: record
    case +name <> rest: guidelines(rest, builtins, R.set(List<&2, String>, record, Tools.toolName(name), Tools.definitionGuidelines(name, builtins)))

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
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, systemPrompt, appendSystemPrompt, selection, _, _, _, _}:
      Prompt.BuildSystemPromptOptions{systemPrompt, None{}, Some{toolNames(names)}, Some{snippets(names, R.new(String))}, Some{guidelines(names, builtinsOf(selection), R.new(List<&2, String>))}, None{}, nonemptyAppend(appendSystemPrompt), None{}, cwd, Some{contextList}, Some{skills}}

def promptOptions(options: CreateOptions, active: List<&2, String>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>) -> Prompt.BuildSystemPromptOptions:
  promptOptionsFor(options, parsedNames(active), contextList, skills)

# Prompt snippets and guidelines of registered non-built-in tools (upstream
# _toolPromptSnippets and _toolPromptGuidelines for extension tools); they
# override a built-in tool's of the same name.
type ToolPrompts is Data:
  ToolPrompts{snippets: R.Record<String>, guidelines: R.Record<List<&2, String>>}

def noToolPrompts() -> ToolPrompts: ToolPrompts{R.new(String), R.new(List<&2, String>)}

def mergedRecord(-V: Data, extra: List<&2, R.Property<V>>, +base: R.Record<V>) -> R.Record<V>:
  match extra:
    case Nil{}: base
    case R.Property{name, value} <> rest: mergedRecord(V, rest, R.set(V, base, name, value))

# upstream _rebuildSystemPrompt: every active tool is selected; built-in tools
# have their snippets and guidelines, registered tools theirs.
def promptOptionsWith(options: CreateOptions, +active: List<&2, String>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>, prompts: ToolPrompts) -> Prompt.BuildSystemPromptOptions:
  match options prompts:
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, systemPrompt, appendSystemPrompt, selection, _, _, _, _} ToolPrompts{extraSnippets, extraGuidelines}:
      +names = parsedNames(active)
      Prompt.BuildSystemPromptOptions{systemPrompt, None{}, Some{active}, Some{mergedRecord(String, R.entries(String, extraSnippets), snippets(names, R.new(String)))}, Some{mergedRecord(List<&2, String>, R.entries(List<&2, String>, extraGuidelines), guidelines(names, builtinsOf(selection), R.new(List<&2, String>)))}, None{}, nonemptyAppend(appendSystemPrompt), None{}, cwd, Some{contextList}, Some{skills}}

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

def resolvedFor(+environment: Paths.Environment, options: CreateOptions, existing: Maybe<&2, PackageManager.ResolvedPaths>) -> IO(PackageManager.ResolvedPaths):
  match existing options:
    case Some{paths} _: IO.pure(PackageManager.ResolvedPaths, paths)
    case None{} CreateOptions{cwd, agentDir, _, _, _, _, _, _, _, _, _, _, _, _, settings, _}: PackageManager.resolve(environment, settings, cwd, agentDir)

# upstream DefaultResourceLoader skills: the package manager's enabled skills
# (unless --no-skills) followed by --skill paths, deduplicated by canonical
# path and loaded without the default directories.
def skillsFor(+environment: Paths.Environment, options: CreateOptions, +resolved: PackageManager.ResolvedPaths) -> IO(List<&2, Skills.Skill>):
  match options:
    case CreateOptions{+cwd, +agentDir, _, _, _, _, _, _, _, _, _, _, _, _, _, ResourceOptions{skillPaths, +noSkills, _, _}}:
      do IO<List<&2, Skills.Skill>>:
        loaded : Resources.SkillsResult <- Resources.loadSkillResources(environment, cwd, agentDir, noSkills, skillPaths, resolved)
        return Resources.skillsOf(loaded)

# upstream DefaultResourceLoader prompts, as for skills.
def templatesFor(+environment: Paths.Environment, options: CreateOptions, +resolved: PackageManager.ResolvedPaths) -> IO(List<&2, Templates.PromptTemplate>):
  match options:
    case CreateOptions{+cwd, +agentDir, _, _, _, _, _, _, _, _, _, _, _, _, _, ResourceOptions{_, _, promptPaths, +noTemplates}}:
      do IO<List<&2, Templates.PromptTemplate>>:
        loaded : Resources.PromptsResult <- Resources.loadPromptResources(environment, cwd, agentDir, noTemplates, promptPaths, resolved)
        return Resources.promptsOf(loaded)

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
    case LoadoutSource{_, options, packageDir, _}: promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptions(options, active, contextList, skills)))

# The sections for the active tools with registered tools' prompts.
def sectionsForToolsWith(source: LoadoutSource, active: List<&2, String>, contextList: List<&2, Prompt.ContextFile>, skills: List<&2, Skills.Skill>, prompts: ToolPrompts) -> Result<&2, &2, String, Prompt.SystemPromptSections()>:
  match source:
    case LoadoutSource{_, options, packageDir, _}: promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptionsWith(options, active, contextList, skills, prompts)))

def preparedWithTools(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String, active: List<&2, String>, existing: Maybe<&2, PackageManager.ResolvedPaths>) -> IO(Result<&2, &2, String, Prepared>):
  do IO<Result<&2, &2, String, Prepared>>:
    loaded : Resources.ContextFiles <- contextFilesFor(environment,options)
    +contextList : List<&2,Prompt.ContextFile> <- contextFilesReported(loaded)
    +resolved : PackageManager.ResolvedPaths <- resolvedFor(environment, options, existing)
    +skills : List<&2, Skills.Skill> <- skillsFor(environment, options, resolved)
    templates : List<&2, Templates.PromptTemplate> <- templatesFor(environment, options, resolved)
    return preparedWith(skills, templates, contextList, promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptions(options, active, contextList, skills))))

def preparedFor(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String, existing: Maybe<&2, PackageManager.ResolvedPaths>) -> IO(Result<&2, &2, String, Prepared>):
  preparedWithTools(environment, options, packageDir, activeNamesOf(toolSetupOf(options)), existing)

# The system prompt and its appended text from a resource loader.
def withLoadedPrompt(options: CreateOptions, systemPrompt: Maybe<&2, String>, append: List<&2, String>) -> CreateOptions:
  match options:
    case CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, _, _, names, contextFiles, seed, settings, resources}: CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, append, names, contextFiles, seed, settings, resources}

# upstream _buildRuntime's resources from an injected ResourceLoader: its
# skills, prompt templates, context files, system prompt and appended text.
def preparedFromLoader(+loader: Resources.ResourceLoader, options: CreateOptions, +packageDir: String, active: List<&2, String>) -> IO(Result<&2, &2, String, Prepared>):
  do IO<Result<&2, &2, String, Prepared>>:
    +skills : Resources.SkillsResult <- Resources.getSkills(loader)
    prompts : Resources.PromptsResult <- Resources.getPrompts(loader)
    +files : Resources.AgentsFilesResult <- Resources.getAgentsFiles(loader)
    system : Maybe<&2, String> <- Resources.getSystemPrompt(loader)
    append : List<&2, String> <- Resources.getAppendSystemPrompt(loader)
    +contextList : List<&2, Prompt.ContextFile> = Resources.agentsFilesOf(files)
    +loaded : List<&2, Skills.Skill> = Resources.skillsOf(skills)
    return preparedWith(loaded, Resources.promptsOf(prompts), contextList, promptResult(Prompt.buildSystemPromptSections(documentationPaths(packageDir), promptOptions(withLoadedPrompt(options, system, append), active, contextList, loaded))))

def withSettings(options: CreateOptions, settings: Settings.SettingsManager) -> CreateOptions:
  match options:
    case CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, _, resources}: CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}
# Skills, prompt templates, context files and the system prompt again, under
# reloaded settings.
def reprepare(source: LoadoutSource, settings: Settings.SettingsManager, active: List<&2, String>) -> IO(Result<&2, &2, String, Prepared>):
  match source:
    case LoadoutSource{environment, options, packageDir, None{}}: preparedWithTools(environment, withSettings(options, settings), packageDir, active, None{})
    case LoadoutSource{_, options, packageDir, Some{+loader}}:
      do IO<Result<&2, &2, String, Prepared>>:
        Resources.reload(loader, Resources.ResourceLoaderReloadOptions{Some{settings}})
        preparedFromLoader(loader, options, packageDir, active)
def sectionsOf(result: Result<&2, &2, String, Prepared>) -> Result<&2, &2, String, Prompt.SystemPromptSections()>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Prepared{sections, _, _, _}}: Done{sections}

def systemPromptFor(+environment: Paths.Environment, +options: CreateOptions, +packageDir: String) -> IO(Result<&2, &2, String, Prompt.SystemPromptSections()>):
  do IO<Result<&2, &2, String, Prompt.SystemPromptSections()>>:
    prepared : Result<&2, &2, String, Prepared> <- preparedFor(environment, options, packageDir, None{})
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

def seededMessages(seed: SessionSeed) -> Maybe<&2, List<&2, T.AgentMessage<V.Value, Details(), Custom()>>>:
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

def blockedMessage(message: Ai.Message<V.Value, V.Value, V.Value, Details()>) -> Ai.Message<V.Value, V.Value, V.Value, Details()>:
  match message:
    case Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks}, timestamp}}: Ai.User{Ai.UserMessage{Ai.UserBlocks{blockedContent(blocks)}, timestamp}}
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, blocks, details, usage, isError, timestamp}}: Ai.ToolResult{Ai.ToolResultMessage{id, name, blockedContent(blocks), details, usage, isError, timestamp}}
    case other: other

def blockedMessages(messages: List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>) -> List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: blockedMessage(message) <> blockedMessages(rest)

def converted(blockImages: Bool, +messages: List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>) -> List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>:
  match blockImages:
    case False{}: messages
    case True{}: blockedMessages(messages)

# Coding messages convert to LLM messages as upstream's convertToLlm does;
# with the blockImages setting, images are replaced by a placeholder text.
def convertMessages(blockImages: Bool, messages: T.AgentMessageArray(V.Value, Details(), Custom())) -> IO(Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>):
  IO.pure(Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>, Done{converted(blockImages, Messages.convertToLlm(V.Value, Details(), V.Value, messages))})

def createConverter(blockImages: Bool) -> IO(Converter()):
  C.create(~Bool, ~T.AgentMessageArray(V.Value, Details(), Custom()), ~Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>, ~convertMessages, blockImages)

def convertWithSettings(settings: Ref.Ref<Settings.SettingsManager>, messages: T.AgentMessageArray(V.Value, Details(), Custom())) -> IO(Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>):
  do IO<Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>>:
    current : Settings.SettingsManager <- Ref.read(Settings.SettingsManager, settings)
    convertMessages(Settings.getBlockImages(current), messages)

def createSettingsConverter(settings: Ref.Ref<Settings.SettingsManager>) -> IO(Converter()):
  C.create(~Ref.Ref<Settings.SettingsManager>, ~T.AgentMessageArray(V.Value, Details(), Custom()), ~Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>, ~convertWithSettings, settings)

def disposeConverter(converter: Converter()) -> IO(Unit):
  C.dispose(T.AgentMessageArray(V.Value, Details(), Custom()), Result<&2, &2, Error(), List<&2, Ai.Message<V.Value, V.Value, V.Value, Details()>>>, converter)

def installSettingsConverter(agent: Owner(), previous: Converter(), settings: Ref.Ref<Settings.SettingsManager>) -> IO(Converter()):
  do IO<Converter()>:
    +current : Converter() <- createSettingsConverter(settings)
    Agent.setConvertToLlm(V.Value, Details(), Custom(), Error(), Unit, agent, current)
    disposeConverter(previous)
    return current

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
def agentOptions(model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, stream: Stream(), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), +seed: SessionSeed, +settings: Settings.SettingsManager) -> Agent.AgentOptions<V.Value, Details(), Custom(), Error(), Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{""}, model, Some{thinking}, Some{Nil{}}, seededMessages(seed)}}, Some{converter}, None{}, Some{stream}, Some{keys}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{Settings.getSteeringMode(settings)}, Some{Settings.getFollowUpMode(settings)}, Some{seedSessionId(seed)}, thinkingBudgets(Settings.getThinkingBudgets(settings)), Some{Settings.getTransport(settings)}, Some{maxRetryDelay(Settings.getProviderRetrySettings(settings))}, None{}}

# The tools download fd and rg through the agent's own fetch.
def environment(paths: Paths.Environment, cwd: String, agentDir: String, packageDir: String, fetch: Fetch.Fetch(Unit), queue: Queue.Queue, context: ToolContext.ContextSource()) -> Tools.Environment:
  Tools.Environment{paths, cwd, Manager.ToolsManager{Path.join(agentDir, "bin"), urlContext(), Some{fetch}}, queue, Path.join(packageDir, "packages/runtime/data"), context}

def pathsError(error: FS.Error) -> String: "Could not resolve the working directory"

def disposeServices(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(V.Value, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter()) -> IO(Unit):
  do IO<Unit>:
    disposeConverter(converter)
    C.dispose(String, Result<&2, &2, Error(), Maybe<&2, String>>, keys)
    Loop.disposeValidation(Error(), validator)
    StreamFn.dispose(V.Value, Details(), LoopConfig(), Error(), registry)
    C.dispose(Providers.Input(LoopConfig(), V.Value, Details()), Providers.Output(V.Value, Error()), stream)
    Tools.disposeTools(tools)
    Queue.dispose(queue)
    Models.dispose(models)
    Auth.disposeStore(storageStore)
    Storage.dispose(storage)
    disposeTransport(transport)

def disposeLoadout(loadout: Loadout) -> IO(Unit):
  match loadout:
    case Loadout{_, _, _, _, None{}, _, _, _}: IO.pure(Unit, Unit{})
    case Loadout{_, _, _, _, Some{runner}, _, _, _}: ExtensionRunner.dispose(runner)

# Assembly with cleanup on every failure path.
def constructed(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(V.Value, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), model: Maybe<&2, Models.Model()>, thinking: Ai.ModelThinkingLevel, loadout: Loadout, result: Result<&2, &2, StreamFn.MissingDefault, Owner()>) -> IO(Outcome(AgentRuntime)):
  match result:
    case Done{agent}: IO.pure(Outcome(AgentRuntime), Done{AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}})
    case Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeServices(transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter)
        disposeLoadout(loadout)
        return Fail{StreamFn.errorMessage(error)}

def disposeBase(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, extensions: ExtensionRunner.ExtensionRunner) -> IO(Unit):
  do IO<Unit>:
    ExtensionRunner.dispose(extensions)
    Models.dispose(models)
    Auth.disposeStore(storageStore)
    Storage.dispose(storage)
    disposeTransport(transport)

def createToolList(names: List<&2, Tools.ToolName>, builtins: Tools.ToolsOptions, paths: Paths.Environment, cwd: String, agentDir: String, packageDir: String, fetch: Fetch.Fetch(Unit), context: ToolContext.ContextSource(), borrowed: Queue.Owner & Queue.Queue) -> IO(Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)):
  match borrowed:
    case Tuple{queue, handle}:
      do IO<Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)>:
        owners : List<&1, Tools.ToolOwner> <- Tools.createTools(names, environment(paths, cwd, agentDir, packageDir, fetch, handle, context), builtins)
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
    case Prepared{sections, skills, templates, agentsFiles} LoadoutSource{paths, +options, packageDir, loader}: Loadout{sections, activeTools(registry, activeNamesOf(toolSetupOf(options))), skills, templates, Some{extensions}, agentsFiles, Some{LoadoutSource{paths, options, packageDir, loader}}, registry}

def assembled(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, created: Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>), +stream: Stream(), +registry: StreamFn.Registry(V.Value, Details(), LoopConfig(), Error()), +validator: Loop.Validator(Error()), +keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, +converter: Converter(), prepared: Prepared, +model: Maybe<&2, Models.Model()>, +thinking: Ai.ModelThinkingLevel, seed: SessionSeed, settings: Settings.SettingsManager, extensions: ExtensionRunner.ExtensionRunner, source: LoadoutSource) -> IO(Outcome(AgentRuntime)):
  match created:
    case Tuple{queue, Tuple{owners, tools}}:
      do IO<Outcome(AgentRuntime)>:
        result : Result<&2, &2, StreamFn.MissingDefault, Owner()> <- Agent.new(~V.Value, ~Details(), ~Custom(), ~Error(), ~Unit, agentOptions(model, thinking, stream, keys, converter, seed, settings), registry, validator, Tools.emptyDetails())
        constructed(transport, storage, storageStore, models, queue, owners, stream, registry, validator, keys, converter, model, thinking, loadoutFrom(prepared, tools, extensions, source), result)

def withModelFields(+cwd: String, +agentDir: String, packageDir: String, +apiKey: Maybe<&2, String>, requested: Maybe<&2, Ai.ModelThinkingLevel>, +seed: SessionSeed, +settings: Settings.SettingsManager, +names: List<&2, Tools.ToolName>, builtins: Tools.ToolsOptions, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, +models: Models.ModelRuntime, +paths: Paths.Environment, +prompt: Result<&2, &2, String, Prepared>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>, source: LoadoutSource, +extensions: ExtensionRunner.ExtensionRunner) -> IO(Outcome(AgentRuntime)):
  match transport prompt selected:
    case Transport{+authorizer, runtime, +fetch, +codexSessions} Done{prompt} Done{+model}:
      do IO<Outcome(AgentRuntime)>:
        queue : Queue.Owner <- Queue.create()
        +context : ToolContext.ContextSource() <- IO.pure(ToolContext.ContextSource(), ExtensionRunner.toolContext(extensions))
        created : Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) <- createToolList(names, toolsOptionsFor(builtins, settings, paths), paths, cwd, agentDir, packageDir, fetch, context, Queue.borrow(queue))
        apiStream : Composer.ProviderStream() <- createApiStream(codexSessions, authorizer, fetch)
        Models.setApiStreams(models, Some{apiStream})
        +stream : Stream() <- createStream(fetch, requestDefaults(settings), KeySource{models, apiKey}, Models.noTransforms())
        +registry : StreamFn.Registry(V.Value, Details(), LoopConfig(), Error()) <- StreamFn.create(V.Value, Details(), LoopConfig(), Error())
        +validator : Loop.Validator(Error()) <- Loop.createPlain(~Error(), ~validationError)
        +keys : C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>> <- C.create(~KeySource, ~String, ~Result<&2, &2, Error(), Maybe<&2, String>>, ~resolveKey, KeySource{models, apiKey})
        +converter : Converter() <- createConverter(Settings.getBlockImages(settings))
        assembled(Transport{authorizer, runtime, fetch, codexSessions}, storage, storageStore, models, created, stream, registry, validator, keys, converter, prompt, model, thinkingForSelection(requested, seed, settings, model), seed, settings, extensions, source)
    case transport Fail{error} _:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, models, extensions)
        return Fail{error}
    case transport _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, models, extensions)
        return Fail{error}

def registryOf(setup: ToolSetup) -> List<&2, Tools.ToolName>:
  match setup:
    case ToolSetup{registry, _}: registry

def withModel(+options: CreateOptions, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, models: Models.ModelRuntime, +paths: Paths.Environment, prompt: Result<&2, &2, String, Prepared>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>, extensions: ExtensionRunner.ExtensionRunner) -> IO(Outcome(AgentRuntime)):
  match options:
    case CreateOptions{cwd, agentDir, _, _, +packageDir, _, _, apiKey, thinking, _, _, +selection, _, seed, settings, _}: withModelFields(cwd, agentDir, packageDir, apiKey, thinking, seed, settings, registryOf(toolSetupOf(options)), builtinsOf(selection), transport, storage, storageStore, models, paths, prompt, selected, LoadoutSource{paths, options, packageDir, None{}}, extensions)

# A runtime API key changes the provider's availability (upstream
# setRuntimeApiKey refreshes it).
def applyKey(+models: Models.ModelRuntime, apiKey: Maybe<&2, String>, selected: Result<&2, &2, String, Maybe<&2, Models.Model()>>) -> IO(Result<&2, &2, Resolve.ModelsError, Unit>):
  match apiKey selected:
    case Some{key} Done{Some{model}}:
      +provider = Models.modelProvider(model)
      Models.setRuntimeApiKey(models, provider, key, None{})
    case _ _: IO.pure(Result<&2, &2, Resolve.ModelsError, Unit>, Done{Unit{}})

def keyFailure(result: Result<&2, &2, Resolve.ModelsError, Unit>) -> Maybe<&2, String>:
  match result:
    case Done{_}: None{}
    case Fail{error}: Some{Resolve.errorMessage(error)}

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
type ExtensionLoadout is Type:
  ExtensionLoadout{factories: List<&1, ExtensionTypes.InlineExtension>, errors: List<&2, ExtensionTypes.LoadError>, resolved: Maybe<&2, PackageManager.ResolvedPaths>}
def loadExtensions(+cwd: String, +models: Models.ModelRuntime, factories: List<&1, ExtensionTypes.InlineExtension>, errors: List<&2, ExtensionTypes.LoadError>) -> IO(Extensions):
  do IO<Extensions>:
    +runtime : ExtensionTypes.ExtensionRuntime() <- ExtensionLoader.createExtensionRuntime()
    loadErrors : List<&2, ExtensionTypes.LoadError> <- ExtensionLoader.loadExtensionFactories(runtime, factories)
    providerErrors : List<&2, ExtensionTypes.ExtensionError> <- ExtensionLoader.bindProviders(runtime, models, None{})
    runner : ExtensionRunner.ExtensionRunner <- ExtensionRunner.create(runtime, cwd, models)
    return Extensions{runner, List.append(&2, ExtensionTypes.LoadError, errors, loadErrors), providerErrors}

def storageStep(+options: CreateOptions, +packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, +paths: Paths.Environment, borrowed: Storage.AuthStorageOwner & Storage.AuthStorage, loadout: ExtensionLoadout) -> IO(Outcome(AgentRuntime)):
  match transport borrowed loadout:
    case Transport{+authorizer, runtime, +fetch, +codexSessions} Tuple{storage, view} ExtensionLoadout{factories, errors, resolved}:
      do IO<Outcome(AgentRuntime)>:
        +storageStore : Auth.CredentialStore <- Storage.store(view)
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch, urlContext())
        anthropicOAuth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, urlContext())
        +models : Models.ModelRuntime <- Models.createWithAnthropic(storageStore, oauth, Some{anthropicOAuth}, Radius.RadiusTransport{fetch, urlContext()})
        +extensions : Extensions <- loadExtensions(cwdOf(options), models, factories, errors)
        +resolution : Models.ResolveCliModelResult <- cliResolution(models, options, packageDir)
        reportResolution(resolution)
        +selected : Result<&2, &2, String, Maybe<&2, Models.Model()>> <- selectModel(models, options, resolution)
        key : Result<&2, &2, Resolve.ModelsError, Unit> <- applyKey(models, apiKey, selected)
        prompt : Result<&2, &2, String, Prepared> <- preparedFor(paths, options, packageDir, resolved)
        withModel(withSuffixThinking(options, resolution), Transport{authorizer, runtime, fetch, codexSessions}, storage, storageStore, models, paths, failedWith(extensionFailure(extensions), failedWith(keyFailure(key), prompt)), selected, runnerOf(extensions))

def withPathsFields(options: CreateOptions, authPath: String, packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, paths: Paths.Environment, loadout: ExtensionLoadout) -> IO(Outcome(AgentRuntime)):
  do IO<Outcome(AgentRuntime)>:
    storage : Storage.AuthStorageOwner <- Storage.create(authPath)
    storageStep(options, packageDir, apiKey, transport, paths, Storage.borrow(storage), loadout)

def withPaths(options: CreateOptions, transport: Transport, +paths: Result<&2, &2, FS.Error, Paths.Environment>, loadout: ExtensionLoadout) -> IO(Outcome(AgentRuntime)):
  match options paths:
    case _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeTransport(transport)
        return Fail{pathsError(error)}
    case CreateOptions{cwd, agentDir, +authPath, bundlePath, +packageDir, provider, model, +apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources} Done{paths}: withPathsFields(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}, authPath, packageDir, apiKey, transport, paths, loadout)

# --api-key applies to the selected model's provider for this process only.
def withTransport(+options: CreateOptions, transport: Outcome(Transport), loadout: ExtensionLoadout) -> IO(Outcome(AgentRuntime)):
  match transport:
    case Fail{error}: IO.pure(Outcome(AgentRuntime), Fail{error})
    case Done{transport}:
      do IO<Outcome(AgentRuntime)>:
        paths : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(urlContext())
        withPaths(options, transport, paths, loadout)

def createWithExtensions(options: CreateOptions, loadout: ExtensionLoadout) -> IO(Outcome(AgentRuntime)):
  match options:
    case CreateOptions{cwd, agentDir, authPath, +bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, +settings, resources}:
      do IO<Outcome(AgentRuntime)>:
        transport : Outcome(Transport) <- createTransportWith(bundlePath, globalHttpProxy(settings))
        withTransport(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings, resources}, transport, loadout)

def create(options: CreateOptions) -> IO(Outcome(AgentRuntime)):
  createWithExtensions(options, ExtensionLoadout{Nil{}, Nil{}, None{}})

def agentOf(runtime: AgentRuntime) -> AgentRuntime & Owner():
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, model, thinking, loadout}: (AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, agent)
def managedTools(runtime: AgentRuntime,agentDir: String) -> AgentRuntime & Manager.ToolsManager:
  match runtime:
    case AgentRuntime{Transport{authorizer,network,+fetch,codexSessions},storage,storageStore,models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout}:
      (AgentRuntime{Transport{authorizer,network,fetch,codexSessions},storage,storageStore,models,queue,tools,stream,registry,validator,keys,converter,agent,model,thinking,loadout},Manager.ToolsManager{Path.join(agentDir,"bin"),urlContext(),Some{fetch}})

def selectionOf(runtime: AgentRuntime) -> AgentRuntime & Selection:
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, +model, +thinking, loadout}: (AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, Selection{model, thinking})

def loadoutOf(runtime: AgentRuntime) -> AgentRuntime & Loadout:
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, +loadout}: (AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking, loadout}, loadout)

# Adjust the startup selection before any SessionManager model entry is written.
def selectStartup(runtime: AgentRuntime,+chosen: Models.Model(),+level: Ai.ModelThinkingLevel) -> IO(AgentRuntime):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, _, _, loadout}:
      do IO<AgentRuntime>:
        Agent.setModel(V.Value,Details(),Custom(),Error(),Unit,agent,chosen)
        Agent.setThinkingLevel(V.Value,Details(),Custom(),Error(),Unit,agent,level)
        return AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, Some{chosen}, level, loadout}

def withSettingsConverter(runtime: AgentRuntime, settings: Ref.Ref<Settings.SettingsManager>) -> IO(AgentRuntime):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, model, thinking, loadout}:
      do IO<AgentRuntime>:
        current : Converter() <- installSettingsConverter(agent, converter, settings)
        return AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, current, agent, model, thinking, loadout}

def dispose(runtime: AgentRuntime) -> IO(Unit):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter, agent, _, _, loadout}:
      do IO<Unit>:
        Agent.dispose(V.Value, Details(), Custom(), Error(), Unit, agent)
        disposeServices(transport, storage, storageStore, models, queue, tools, stream, registry, validator, keys, converter)
        disposeLoadout(loadout)
