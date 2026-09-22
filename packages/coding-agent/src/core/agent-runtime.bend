import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/resolve.bend as Resolve
import ../../../ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../../../ai/src/api/openai-responses.bend as Responses
import ../../../ai/src/api/openai-client.bend as Client
import ../../../ai/src/utils/tool-declaration.bend as Declaration
import ../../../ai/src/utils/validation.bend as Validation
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/providers.bend as Providers
import ../../../agent/src/stream-fn.bend as StreamFn
import ../../../agent/src/types.bend as T
import ../../../runtime/src/fetch.bend as Fetch
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
import ./resource-loader.bend as Resources
import ./diagnostics.bend as Diagnostics
import ./tools/index.bend as Tools
import ./tools/file-mutation-queue.bend as Queue

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

# pi's user agent names the host platform; the port has no OS-info primitive yet.
def userAgent() -> String: "pi (bend)"

def files() -> Fetch.Files: Fetch.Files{"/etc/resolv.conf", "/etc/hosts", 4096, 1048576n, 5000, 65535}

def httpOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Message.Limits{8192n, 8192n, 65536n, 100n}}}

def security(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> HTTP.Security:
  HTTP.WithTLS{authorizer, TLS.defaults()}

def providerConfig(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> Responses.Config:
  Responses.Config{urlContext(), Client.Defaults{userAgent(), R.new(String), None{}, None{}}, files(), httpOptions(), security(authorizer), 65536n, False{}}

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

def createStream(authorizer: C.Callback<URL.Host, TLSClient.Authorization>) -> IO(Stream()):
  Providers.responses(~LoopConfig(), ~Unit, ~Unit, ~Details(), ~Error(), ~project, ~render, ~failure, providerConfig(authorizer))

# Request auth
# ------------

type KeySource is Data:
  KeySource{models: Models.ModelRuntime, apiKey: Maybe<&2, String>}

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

type CreateOptions is Data:
  CreateOptions{cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String, provider: Maybe<&2, String>, model: Maybe<&2, String>, apiKey: Maybe<&2, String>, thinking: Maybe<&2, Ai.ModelThinkingLevel>, systemPrompt: Maybe<&2, String>, appendSystemPrompt: List<&2, String>, tools: List<&2, Tools.ToolName>, contextFiles: Bool, seed: SessionSeed, settings: Settings.SettingsManager}

# The model and thinking level the runtime settled on, for the session record.
type Selection is Data:
  Selection{model: Models.Model(), thinking: Ai.ModelThinkingLevel}

type AgentRuntime is Type:
  AgentRuntime{transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), agent: Owner(), model: Models.Model(), thinking: Ai.ModelThinkingLevel}

def snippets(names: List<&2, Tools.ToolName>, +record: R.Record<String>) -> R.Record<String>:
  match names:
    case Nil{}: record
    case +name <> rest: snippets(rest, R.set(String, record, Tools.toolName(name), Tools.promptSnippet(name)))

def guidelines(names: List<&2, Tools.ToolName>, +record: R.Record<List<&2, String>>) -> R.Record<List<&2, String>>:
  match names:
    case Nil{}: record
    case +name <> rest: guidelines(rest, R.set(List<&2, String>, record, Tools.toolName(name), Tools.promptGuidelines(name)))

def toolNames(names: List<&2, Tools.ToolName>) -> List<&2, String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Tools.toolName(name) <> toolNames(rest)

def nonemptyAppend(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case values: Some{String.join(values, "\n\n")}

def promptOptions(options: CreateOptions, contextList: List<&2, Prompt.ContextFile>) -> Prompt.BuildSystemPromptOptions:
  match options:
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, systemPrompt, appendSystemPrompt, +names, _, _, _}:
      Prompt.BuildSystemPromptOptions{systemPrompt, None{}, Some{toolNames(names)}, Some{snippets(names, R.new(String))}, Some{guidelines(names, R.new(List<&2, String>))}, None{}, nonemptyAppend(appendSystemPrompt), None{}, cwd, Some{contextList}, None{}}

def reportContextDiagnostics(issues: List<&2,Diagnostics.ResourceDiagnostic>) -> IO(Unit):
  match issues:
    case Nil{}: IO.pure(Unit,Unit{})
    case Diagnostics.ResourceDiagnostic{_,message,path,_} <> rest:
      do IO<Unit>:
        IO.print_err("Warning: " ++ Maybe.default(&2,String,Maybe.map(&2,String,String,value => value ++ ": ",path),"") ++ message)
        reportContextDiagnostics(rest)

def contextFilesFor(environment: Paths.Environment, options: CreateOptions) -> IO(Resources.ContextFiles):
  match options:
    case CreateOptions{cwd, agentDir, _, _, _, _, _, _, _, _, _, _, True{}, _, _}: Resources.loadProjectContextFiles(environment,Resources.Options{cwd,agentDir})
    case _: IO.pure(Resources.ContextFiles,Resources.ContextFiles{Nil{},Nil{}})

def contextFilesReported(result: Resources.ContextFiles) -> IO(List<&2,Prompt.ContextFile>):
  match result:
    case Resources.ContextFiles{loadedFiles,diagnostics}:
      do IO<List<&2,Prompt.ContextFile>>:
        reportContextDiagnostics(diagnostics)
        return loadedFiles

def promptResult(value: Prompt.ResultOf(String)) -> Result<&2, &2, String, String>:
  match value:
    case Done{text}: Done{text}
    case Fail{Prompt.InvalidSectionName{name}}: Fail{"Invalid system prompt section name: " ++ name}

def systemPromptFor(environment: Paths.Environment, +options: CreateOptions, +packageDir: String) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    loaded : Resources.ContextFiles <- contextFilesFor(environment,options)
    contextList : List<&2,Prompt.ContextFile> <- contextFilesReported(loaded)
    return promptResult(Prompt.buildSystemPrompt(Prompt.DocumentationPaths{Path.join(packageDir, "README.md"), Path.join(packageDir, "docs"), Path.join(packageDir, "examples")}, promptOptions(options, contextList)))

def levelOf(result: Models.ResolveCliModelResult) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match result:
    case Models.ResolveCliModelResult{_, level, _, _}: level

def noModels() -> String:
  "No models available.\n\nRun pi to log in with a provider, or set an API key environment variable such as OPENAI_API_KEY."

def chosenFrom(models: Models.ModelRuntime, +settings: Settings.SettingsManager, error: Maybe<&2, String>, model: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Models.Model()>):
  match error model:
    case Some{message} _: IO.pure(Result<&2, &2, String, Models.Model()>, Fail{message})
    case None{} Some{chosen}: IO.pure(Result<&2, &2, String, Models.Model()>, Done{chosen})
    case None{} None{}:
      do IO<Result<&2, &2, String, Models.Model()>>:
        initial : Maybe<&2, Models.Model()> <- Models.findInitialModel(models, Settings.getDefaultProvider(settings), Settings.getDefaultModel(settings))
        return Maybe.default(&2, Result<&2, &2, String, Models.Model()>, Maybe.map(&2, Models.Model(), Result<&2, &2, String, Models.Model()>, found => Done{found}, initial), Fail{noModels()})

def chosenModel(models: Models.ModelRuntime, settings: Settings.SettingsManager, resolved: Models.ResolveCliModelResult) -> IO(Result<&2, &2, String, Models.Model()>):
  match resolved:
    case Models.ResolveCliModelResult{model, _, _, error}: chosenFrom(models, settings, error, model)

def modelApi(model: Models.Model()) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _}: api

# The OpenAI Responses and Codex Responses APIs stream through the modular provider.
def supportedApi(api: Ai.ModelApi, +model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  match api:
    case Ai.OpenAIResponsesApi{}: Done{model}
    case Ai.OpenAICodexResponsesApi{}: Done{model}
    case _: Fail{"Model " ++ Models.reference(model) ++ " uses an API this port does not stream yet (openai-responses and openai-codex-responses)."}

def supportedModel(+model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  supportedApi(modelApi(model), model)

def supported(model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  supportedModel(model)

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
    case SessionSeed{_, _, Some{S.SessionModel{provider, id}}, _}: authorizedRestore(models, Models.getModel(models, provider, id))

def chosenOrRestored(+models: Models.ModelRuntime, settings: Settings.SettingsManager, provider: Maybe<&2, String>, cliModel: Maybe<&2, String>, restored: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Models.Model()>):
  match restored:
    case Some{model}: IO.pure(Result<&2, &2, String, Models.Model()>, Done{model})
    case None{}: chosenModel(models, settings, Models.resolveCliModel(models, provider, cliModel))

def restoreIf(+models: Models.ModelRuntime, named: Bool, seed: SessionSeed) -> IO(Maybe<&2, Models.Model()>):
  match named:
    case True{}: IO.pure(Maybe<&2, Models.Model()>, None{})
    case False{}: restoredModel(models, seed)

def selectModel(+models: Models.ModelRuntime, options: CreateOptions) -> IO(Result<&2, &2, String, Models.Model()>):
  match options:
    case CreateOptions{_, _, _, _, _, +provider, +cliModel, _, _, _, _, _, _, seed, settings}:
      do IO<Result<&2, &2, String, Models.Model()>>:
        restored : Maybe<&2, Models.Model()> <- restoreIf(models, Maybe.is_some(&2, String, provider) || Maybe.is_some(&2, String, cliModel), seed)
        chosen : Result<&2, &2, String, Models.Model()> <- chosenOrRestored(models, settings, provider, cliModel, restored)
        return Result.bind(&2, &2, String, Models.Model(), Models.Model(), chosen, supported)

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

# A resumed session restores its recorded level, or the settings default.
def sessionThinking(+seed: SessionSeed, settingsDefault: Maybe<&2, Ai.ModelThinkingLevel>) -> Maybe<&2, Ai.ModelThinkingLevel>:
  Bool.pick(Maybe<&2, Ai.ModelThinkingLevel>, hasSessionMessages(seed), Some{Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.or(&2, Ai.ModelThinkingLevel, seededThinking(seed), settingsDefault), Ai.Off{})}, None{})

# upstream createAgentSession: --thinking, else the resumed session's level,
# else the settings' per-model level, else the settings default, else off;
# clamped to the model's levels. The :level model suffix is not applied yet.
def thinkingLevel(requested: Maybe<&2, Ai.ModelThinkingLevel>, seed: SessionSeed, +model: Models.Model(), +settings: Settings.SettingsManager) -> Ai.ModelThinkingLevel:
  +settingsDefault = Settings.getDefaultThinkingLevel(settings)
  +perModel = Settings.getModelThinkingLevel(Models.modelProvider(model), Models.modelId(model), settings)
  AiModels.clampThinkingLevel(Ai.JsonValue, model, Maybe.default(&2, Ai.ModelThinkingLevel, Maybe.or(&2, Ai.ModelThinkingLevel, requested, Maybe.or(&2, Ai.ModelThinkingLevel, sessionThinking(seed, settingsDefault), Maybe.or(&2, Ai.ModelThinkingLevel, perModel, settingsDefault))), Ai.Off{}))

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

# upstream createAgentSession's Agent options: the session id, the settings'
# steering/follow-up modes, transport, thinking budgets and retry delay.
def agentOptions(prompt: String, model: Models.Model(), thinking: Ai.ModelThinkingLevel, tools: List<&2, Tools.Tool()>, stream: Stream(), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), +seed: SessionSeed, +settings: Settings.SettingsManager) -> Agent.AgentOptions<Unit, Details(), Custom(), Error(), Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{prompt}, Some{model}, Some{thinking}, Some{tools}, seededMessages(seed)}}, Some{converter}, None{}, Some{stream}, Some{keys}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{Settings.getSteeringMode(settings)}, Some{Settings.getFollowUpMode(settings)}, Some{seedSessionId(seed)}, thinkingBudgets(Settings.getThinkingBudgets(settings)), Some{Settings.getTransport(settings)}, Some{maxRetryDelay(Settings.getProviderRetrySettings(settings))}, None{}}

def environment(paths: Paths.Environment, cwd: String, agentDir: String, queue: Queue.Queue) -> Tools.Environment:
  Tools.Environment{paths, cwd, Path.join(agentDir, "bin"), queue}

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

# Assembly with cleanup on every failure path.
def constructed(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, converter: Converter(), model: Models.Model(), thinking: Ai.ModelThinkingLevel, result: Result<&2, &2, StreamFn.MissingDefault, Owner()>) -> IO(Outcome(AgentRuntime)):
  match result:
    case Done{agent}: IO.pure(Outcome(AgentRuntime), Done{AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking}})
    case Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter)
        return Fail{StreamFn.errorMessage(error)}

def disposeBase(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime) -> IO(Unit):
  do IO<Unit>:
    Models.dispose(models)
    Auth.disposeStore(credentialStore)
    Runtime.dispose(credentials)
    Auth.disposeStore(storageStore)
    Storage.dispose(storage)
    disposeTransport(transport)

def createToolList(names: List<&2, Tools.ToolName>, paths: Paths.Environment, cwd: String, agentDir: String, borrowed: Queue.Owner & Queue.Queue) -> IO(Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)):
  match borrowed:
    case Tuple{queue, handle}:
      do IO<Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>)>:
        owners : List<&1, Tools.ToolOwner> <- Tools.createTools(names, environment(paths, cwd, agentDir, handle), Tools.defaultOptions())
        return (queue, Tools.borrowTools(owners))

def assembled(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, created: Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>), +stream: Stream(), +registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), +validator: Loop.Validator(Error()), +keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, +converter: Converter(), prompt: String, +model: Models.Model(), +thinking: Ai.ModelThinkingLevel, seed: SessionSeed, settings: Settings.SettingsManager) -> IO(Outcome(AgentRuntime)):
  match created:
    case Tuple{queue, Tuple{owners, tools}}:
      do IO<Outcome(AgentRuntime)>:
        result : Result<&2, &2, StreamFn.MissingDefault, Owner()> <- Agent.new(~Unit, ~Details(), ~Custom(), ~Error(), ~Unit, agentOptions(prompt, model, thinking, tools, stream, keys, converter, seed, settings), registry, validator, Tools.WriteDetails{})
        constructed(transport, storage, storageStore, credentials, credentialStore, models, queue, owners, stream, registry, validator, keys, converter, model, thinking, result)

def withModelFields(+cwd: String, +agentDir: String, apiKey: Maybe<&2, String>, requested: Maybe<&2, Ai.ModelThinkingLevel>, +seed: SessionSeed, +settings: Settings.SettingsManager, +names: List<&2, Tools.ToolName>, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, +models: Models.ModelRuntime, paths: Paths.Environment, +prompt: Result<&2, &2, String, String>, selected: Result<&2, &2, String, Models.Model()>) -> IO(Outcome(AgentRuntime)):
  match transport prompt selected:
    case Transport{+authorizer, runtime, fetch} Done{prompt} Done{+model}:
      do IO<Outcome(AgentRuntime)>:
        queue : Queue.Owner <- Queue.create()
        created : Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) <- createToolList(names, paths, cwd, agentDir, Queue.borrow(queue))
        +stream : Stream() <- createStream(authorizer)
        +registry : StreamFn.Registry(Unit, Details(), LoopConfig(), Error()) <- StreamFn.create(Unit, Details(), LoopConfig(), Error())
        +validator : Loop.Validator(Error()) <- Loop.createPlain(~Error(), ~validationError)
        +keys : C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>> <- C.create(~KeySource, ~String, ~Result<&2, &2, Error(), Maybe<&2, String>>, ~resolveKey, KeySource{models, apiKey})
        +converter : Converter() <- createConverter(Settings.getBlockImages(settings))
        assembled(Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, created, stream, registry, validator, keys, converter, prompt, model, thinkingLevel(requested, seed, model, settings), seed, settings)
    case transport Fail{error} _:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, credentials, credentialStore, models)
        return Fail{error}
    case transport _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeBase(transport, storage, storageStore, credentials, credentialStore, models)
        return Fail{error}

def withModel(options: CreateOptions, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, paths: Paths.Environment, prompt: Result<&2, &2, String, String>, selected: Result<&2, &2, String, Models.Model()>) -> IO(Outcome(AgentRuntime)):
  match options:
    case CreateOptions{cwd, agentDir, _, _, _, _, _, apiKey, thinking, _, _, names, _, seed, settings}: withModelFields(cwd, agentDir, apiKey, thinking, seed, settings, names, transport, storage, storageStore, credentials, credentialStore, models, paths, prompt, selected)

def applyKey(credentials: Runtime.RuntimeCredentials, apiKey: Maybe<&2, String>, selected: Result<&2, &2, String, Models.Model()>) -> IO(Unit):
  match apiKey selected:
    case Some{key} Done{model}: Runtime.setRuntimeApiKey(credentials, Models.modelProvider(model), key)
    case _ _: IO.pure(Unit, Unit{})

def storageStep(+options: CreateOptions, +packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, +paths: Paths.Environment, borrowed: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Outcome(AgentRuntime)):
  match transport borrowed:
    case Transport{+authorizer, runtime, +fetch} Tuple{storage, view}:
      do IO<Outcome(AgentRuntime)>:
        +storageStore : Auth.CredentialStore <- Storage.store(view)
        +credentials : Runtime.RuntimeCredentials <- Runtime.create(storageStore)
        +credentialStore : Auth.CredentialStore <- Runtime.store(credentials)
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch, urlContext())
        +models : Models.ModelRuntime <- Models.create(credentialStore, oauth)
        +selected : Result<&2, &2, String, Models.Model()> <- selectModel(models, options)
        applyKey(credentials, apiKey, selected)
        prompt : Result<&2, &2, String, String> <- systemPromptFor(paths, options, packageDir)
        withModel(options, Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, paths, prompt, selected)

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
    case CreateOptions{cwd, agentDir, +authPath, bundlePath, +packageDir, provider, model, +apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings} Done{paths}: withPathsFields(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings}, authPath, packageDir, apiKey, transport, paths)

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
    case CreateOptions{cwd, agentDir, authPath, +bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings}:
      do IO<Outcome(AgentRuntime)>:
        transport : Outcome(Transport) <- createTransport(bundlePath)
        withTransport(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles, seed, settings}, transport)

def agentOf(runtime: AgentRuntime) -> AgentRuntime & Owner():
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, +agent, model, thinking}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking}, agent)

def selectionOf(runtime: AgentRuntime) -> AgentRuntime & Selection:
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, +model, +thinking}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, model, thinking}, Selection{model, thinking})

def dispose(runtime: AgentRuntime) -> IO(Unit):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter, agent, _, _}:
      do IO<Unit>:
        Agent.dispose(Unit, Details(), Custom(), Error(), Unit, agent)
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, converter)
