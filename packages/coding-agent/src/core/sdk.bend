import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/auth/types.bend as Auth
import ../../../ai/src/auth/oauth/openai-codex.bend as CodexOAuth
import ../../../ai/src/auth/oauth/anthropic.bend as AnthropicOAuth
import ../../../ai/src/providers/radius.bend as Radius
import ../../../ai/src/utils/uuid.bend as Uuid
import ../../../agent/src/agent.bend as Agent
import ../../../agent/src/agent-loop.bend as Loop
import ../../../agent/src/providers.bend as Providers
import ../../../agent/src/stream-fn.bend as StreamFn
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/fetch.bend as Fetch
import ../config.bend as AppConfig
import ../utils/paths.bend as Paths
import ./agent-runtime.bend as Runtime
import ./agent-session.bend as Session
import ./auth-guidance.bend as AuthGuidance
import ./auth-storage.bend as Storage
import ./extensions/runner.bend as ExtensionRunner
import ./extensions/types.bend as ExtensionTypes
import ./model-runtime.bend as Models
import ./provider-composer.bend as Composer
import ./resource-loader.bend as Resources
import ./session-manager.bend as S
import ./session-persistence.bend as Sessions
import ./settings-manager.bend as Settings
import ./tools/index.bend as Tools
import ./tools/file-mutation-queue.bend as Queue

# upstream core/sdk.ts: createAgentSession, the one entry point that
# assembles an AgentSession from injectable services. Each service is used
# as given, or created with upstream's defaults: the model runtime from
# agentDir's auth.json and models.json, the settings of cwd and agentDir, a
# persisted session in agentDir's session directory for cwd, and a
# DefaultResourceLoader, reloaded. What the SDK created, it owns until
# `dispose`; injected services stay their caller's.

# upstream CreateAgentSessionOptions. sessionStartEvent metadata is not exposed yet.
type CreateAgentSessionOptions is Data:
  CreateAgentSessionOptions{cwd: Maybe<&2, String>, agentDir: Maybe<&2, String>, modelRuntime: Maybe<&2, Models.ModelRuntime>, model: Maybe<&2, Models.Model()>, thinkingLevel: Maybe<&2, Ai.ModelThinkingLevel>, scopedModels: List<&2, Models.ScopedModel>, noTools: Maybe<&2, Runtime.NoTools>, tools: Maybe<&2, List<&2, String>>, excludeTools: Maybe<&2, List<&2, String>>, resourceLoader: Maybe<&2, Resources.ResourceLoader>, sessionManager: Maybe<&2, Session.Session()>, settingsManager: Maybe<&2, Settings.SettingsManager>, customTools: List<&2, ExtensionTypes.ToolDefinition>}

def createAgentSessionOptions() -> CreateAgentSessionOptions:
  CreateAgentSessionOptions{None{}, None{}, None{}, None{}, None{}, Nil{}, None{}, None{}, None{}, None{}, None{}, None{}, Nil{}}

# The model runtime and the credential stores behind it, when the SDK
# created them.
type OwnedModels is Type:
  InjectedModels{}
  CreatedModels{storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore}

type OwnedLoader is Type:
  InjectedLoader{}
  CreatedLoader{loader: Resources.DefaultResourceLoader}

# Everything the session runs on that the SDK owns.
type Services is Type:
  Services{transport: Runtime.Transport, models: Models.ModelRuntime, ownedModels: OwnedModels, loader: OwnedLoader, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Runtime.Stream(), registry: StreamFn.Registry(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error()), validator: Loop.Validator(Runtime.Error()), keys: C.Callback<String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>>, converter: Runtime.Converter(), runner: ExtensionRunner.ExtensionRunner}

# upstream CreateAgentSessionResult.
type CreateAgentSessionResult is Type:
  CreateAgentSessionResult{session: Session.AgentSession, extensionsResult: Resources.LoadExtensionsResult, modelFallbackMessage: Maybe<&2, String>, services: Services}

def sessionOf(result: CreateAgentSessionResult) -> CreateAgentSessionResult & Session.AgentSession:
  match result:
    case CreateAgentSessionResult{+session, extensions, fallback, services}: (CreateAgentSessionResult{session, extensions, fallback, services}, session)

def disposeOwnedModels(+models: Models.ModelRuntime, owned: OwnedModels) -> IO(Unit):
  match owned:
    case InjectedModels{}: Models.setApiStreams(models, None{})
    case CreatedModels{storage, storageStore}:
      do IO<Unit>:
        Models.dispose(models)
        Auth.disposeStore(storageStore)
        Storage.dispose(storage)

def disposeLoader(loader: OwnedLoader) -> IO(Unit):
  match loader:
    case InjectedLoader{}: IO.pure(Unit, Unit{})
    case CreatedLoader{created}: Resources.disposeDefaultResourceLoader(created)

def disposeServices(services: Services) -> IO(Unit):
  match services:
    case Services{transport, models, owned, loader, queue, tools, stream, registry, validator, keys, converter, runner}:
      do IO<Unit>:
        ExtensionRunner.dispose(runner)
        Runtime.disposeConverter(converter)
        C.dispose(String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>, keys)
        Loop.disposeValidation(Runtime.Error(), validator)
        StreamFn.dispose(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error(), registry)
        C.dispose(Providers.Input(Runtime.LoopConfig(), V.Value, Runtime.Details()), Providers.Output(V.Value, Runtime.Error()), stream)
        Tools.disposeTools(tools)
        Queue.dispose(queue)
        disposeLoader(loader)
        disposeOwnedModels(models, owned)
        Runtime.disposeTransport(transport)

# upstream session.dispose(), with the services the SDK created.
def dispose(result: CreateAgentSessionResult) -> IO(Unit):
  match result:
    case CreateAgentSessionResult{+session, _, _, services}:
      do IO<Unit>:
        Session.dispose(session)
        Agent.dispose(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(session))
        disposeServices(services)

# Defaults
# --------

def orElse(value: Maybe<&2, String>, fallback: String) -> String: Maybe.default(&2, String, value, fallback)

def resolvedPath(+environment: Paths.Environment, +path: String) -> String:
  Result.default(&2, &2, Paths.Error, String, Paths.resolvePath(environment, path, "", Paths.defaults()), path)

def sessionCwd(session: Maybe<&2, Session.Session()>) -> Maybe<&2, String>:
  match session:
    case None{}: None{}
    case Some{found}: Some{Sessions.getCwd(V.Value, Tools.ToolDetails, V.Value, found)}

def processCwd(environment: Paths.Environment) -> String:
  match environment:
    case Paths.Environment{cwd, _, _}: cwd

# upstream: options.cwd, else the session manager's cwd, else process.cwd().
def cwdFor(+environment: Paths.Environment, options: CreateAgentSessionOptions) -> String:
  match options:
    case CreateAgentSessionOptions{cwd, _, _, _, _, _, _, _, _, _, session, _, _}: resolvedPath(environment, Maybe.default(&2, String, Maybe.or(&2, String, cwd, sessionCwd(session)), processCwd(environment)))

def agentDirFor(+environment: Paths.Environment, requested: Maybe<&2, String>) -> IO(String):
  match requested:
    case Some{path}: IO.pure(String, resolvedPath(environment, path))
    case None{}:
      do IO<String>:
        located : AppConfig.Located() <- AppConfig.getAgentDir()
        return Result.default(&2, &2, FS.Error, String, located, ".pi/agent")

# Model runtime (upstream ModelRuntime.create({ authPath, modelsPath }))
# ----------------------------------------------------------------------

type ModelsChoice is Type:
  ModelsChoice{models: Models.ModelRuntime, owned: OwnedModels}

def createdModels(+agentDir: String, +fetch: Fetch.Fetch(Unit), pair: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(ModelsChoice):
  match pair:
    case (storage, view):
      do IO<ModelsChoice>:
        +storageStore : Auth.CredentialStore <- Storage.store(view)
        oauth : Auth.OAuthAuth <- CodexOAuth.openaiCodexOAuth(fetch, Runtime.urlContext())
        anthropicOAuth : Auth.OAuthAuth <- AnthropicOAuth.anthropicOAuth(fetch, Runtime.urlContext())
        models : Models.ModelRuntime <- Models.createWithOptions(storageStore, oauth, Some{anthropicOAuth}, Radius.RadiusTransport{fetch, Runtime.urlContext()}, Some{Path.join(agentDir, "models.json")}, Models.createOptions())
        return ModelsChoice{models, CreatedModels{storage, storageStore}}

def modelsFor(injected: Maybe<&2, Models.ModelRuntime>, +agentDir: String, +fetch: Fetch.Fetch(Unit)) -> IO(ModelsChoice):
  match injected:
    case Some{models}: IO.pure(ModelsChoice, ModelsChoice{models, InjectedModels{}})
    case None{}:
      do IO<ModelsChoice>:
        storage : Storage.AuthStorageOwner <- Storage.create(Path.join(agentDir, "auth.json"))
        createdModels(agentDir, fetch, Storage.borrow(storage))

# Settings, session and resources
# -------------------------------

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, manager): manager

def settingsFor(injected: Maybe<&2, Settings.SettingsManager>, +cwd: String, +agentDir: String) -> IO(Settings.SettingsManager):
  match injected:
    case Some{settings}: IO.pure(Settings.SettingsManager, settings)
    case None{}:
      do IO<Settings.SettingsManager>:
        created : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(cwd, agentDir, Settings.options())
        return settingsOf(created)

def createdSession(created: Sessions.Outcome(Session.Session())) -> Result<&2, &2, String, Session.Session()>:
  match created:
    case Done{session}: Done{session}
    case Fail{error}: Fail{Sessions.message(error)}

# upstream SessionManager.create(cwd, getDefaultSessionDir(cwd, agentDir)).
def sessionFor(injected: Maybe<&2, Session.Session()>, +cwd: String, +agentDir: String) -> IO(Result<&2, &2, String, Session.Session()>):
  match injected:
    case Some{session}: IO.pure(Result<&2, &2, String, Session.Session()>, Done{session})
    case None{}:
      do IO<Result<&2, &2, String, Session.Session()>>:
        ids : Uuid.Generator <- Uuid.generator()
        created : Sessions.Outcome(Session.Session()) <- Session.createSession(ids, cwd, Some{Sessions.getDefaultSessionDirPath(cwd, agentDir)}, agentDir, Sessions.noOptions())
        return createdSession(created)

type LoaderChoice is Type:
  LoaderChoice{loader: Resources.ResourceLoader, owned: OwnedLoader}

def loaderFor(injected: Maybe<&2, Resources.ResourceLoader>, +environment: Paths.Environment, +cwd: String, +agentDir: String, +settings: Settings.SettingsManager) -> IO(LoaderChoice):
  match injected:
    case Some{loader}: IO.pure(LoaderChoice, LoaderChoice{loader, InjectedLoader{}})
    case None{}:
      do IO<LoaderChoice>:
        +created : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(environment, Resources.defaultResourceLoaderOptions(cwd, agentDir, settings), Nil{})
        Resources.reload(Resources.loaderOf(created), Resources.ResourceLoaderReloadOptions{None{}})
        return LoaderChoice{Resources.loaderOf(created), CreatedLoader{created}}

# The session record's context (upstream buildSessionContext and the branch's
# thinking_level_change entries).
def hasThinkingEntry(entries: List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>) -> Bool:
  match entries:
    case Nil{}: False{}
    case S.ThinkingLevelChangeEntry{_, _} <> _: True{}
    case _ <> rest: hasThinkingEntry(rest)

def seedFrom(+id: String, context: Result<&2, &2, S.Error, S.SessionContext<V.Value, Tools.ToolDetails, V.Value>>, branch: Result<&2, &2, S.Error, List<&2, S.SessionEntry<V.Value, Tools.ToolDetails, V.Value>>>) -> Runtime.SessionSeed:
  match context branch:
    case Done{S.SessionContext{messages, thinkingLevel, model}} Done{entries}: Runtime.SessionSeed{id, messages, model, Bool.pick(Maybe<&2, String>, hasThinkingEntry(entries), Some{thinkingLevel}, None{})}
    case _ _: Runtime.SessionSeed{id, Nil{}, None{}, None{}}

def seedOf(+session: Session.Session()) -> Runtime.SessionSeed:
  +state = Sessions.stateOf(V.Value, Tools.ToolDetails, V.Value, session)
  seedFrom(S.getSessionId(V.Value, Tools.ToolDetails, V.Value, state), S.sessionContext(V.Value, Tools.ToolDetails, V.Value, state), S.getBranch(V.Value, Tools.ToolDetails, V.Value, state, S.Latest{}))

# Model selection (upstream createAgentSession)
# --------------------------------------------

type ModelSelection is Data:
  ModelSelection{model: Maybe<&2, Models.Model()>, fallbackMessage: Maybe<&2, String>}

def seedModelName(seed: Runtime.SessionSeed) -> Maybe<&2, String>:
  match seed:
    case Runtime.SessionSeed{_, _, Some{S.SessionModel{provider, id}}, _}: Some{provider ++ "/" ++ id}
    case _: None{}

def restoreFailure(+seed: Runtime.SessionSeed, restored: Maybe<&2, Models.Model()>) -> Maybe<&2, String>:
  match restored:
    case Some{_}: None{}
    case None{}: Maybe.map(&2, String, String, name => "Could not restore model " ++ name, Bool.pick(Maybe<&2, String>, Runtime.hasSessionMessages(seed), seedModelName(seed), None{}))

def initialSelection(+docsPath: String, initial: Maybe<&2, Models.Model()>, failure: Maybe<&2, String>) -> ModelSelection:
  match initial failure:
    case None{} _: ModelSelection{None{}, Some{AuthGuidance.formatNoModelsAvailableMessage(docsPath)}}
    case Some{+model} None{}: ModelSelection{Some{model}, None{}}
    case Some{+model} Some{message}: ModelSelection{Some{model}, Some{message ++ ". Using " ++ Models.reference(model)}}

def withInitial(+docsPath: String, +models: Models.ModelRuntime, +settings: Settings.SettingsManager, failure: Maybe<&2, String>) -> IO(ModelSelection):
  do IO<ModelSelection>:
    initial : Maybe<&2, Models.Model()> <- Models.findInitialModel(models, Settings.getDefaultProvider(settings), Settings.getDefaultModel(settings))
    return initialSelection(docsPath, initial, failure)

def restoredSelection(+docsPath: String, +models: Models.ModelRuntime, +settings: Settings.SettingsManager, +seed: Runtime.SessionSeed, restored: Maybe<&2, Models.Model()>) -> IO(ModelSelection):
  match restored:
    case Some{model}: IO.pure(ModelSelection, ModelSelection{Some{model}, None{}})
    case None{}: withInitial(docsPath, models, settings, restoreFailure(seed, None{}))

# upstream: the given model, else the session's recorded model when its
# provider has auth, else findInitialModel (settings default, then provider
# defaults), with a fallback message when the recorded model was lost.
def selectModel(+docsPath: String, +models: Models.ModelRuntime, +settings: Settings.SettingsManager, +seed: Runtime.SessionSeed, requested: Maybe<&2, Models.Model()>) -> IO(ModelSelection):
  match requested:
    case Some{model}: IO.pure(ModelSelection, ModelSelection{Some{model}, None{}})
    case None{}:
      do IO<ModelSelection>:
        restored : Maybe<&2, Models.Model()> <- Bool.pick(Unit -> IO(Maybe<&2, Models.Model()>), Runtime.hasSessionMessages(seed), _ => Runtime.restoredModel(models, seed), _ => IO.pure(Maybe<&2, Models.Model()>, None{}))(Unit{})
        restoredSelection(docsPath, models, settings, seed, restored)

# Assembly
# --------

def selectionOf(options: CreateAgentSessionOptions) -> Runtime.ToolSelection:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, _, _, noTools, tools, exclude, _, _, _, _}: Runtime.ToolSelection{tools, noTools, exclude, None{}}

# The CLI's create options the runtime helpers read (system prompt, tools,
# thinking level); resources come from the loader.
def createOptionsFor(+cwd: String, +agentDir: String, +packageDir: String, +bundlePath: String, thinking: Maybe<&2, Ai.ModelThinkingLevel>, selection: Runtime.ToolSelection, seed: Runtime.SessionSeed, settings: Settings.SettingsManager) -> Runtime.CreateOptions:
  Runtime.CreateOptions{cwd, agentDir, Path.join(agentDir, "auth.json"), bundlePath, packageDir, None{}, None{}, None{}, thinking, None{}, Nil{}, selection, False{}, seed, settings, Runtime.noResources()}

# upstream: a resumed session records a missing thinking level; a new one
# records its model and thinking level.
def appendedOr(+session: Session.Session(), appended: Sessions.Outcome(Session.Appended())) -> Session.Session():
  match appended:
    case Done{Sessions.Appended{next, _}}: next
    case Fail{_}: session

def recordedModel(+session: Session.Session(), model: Maybe<&2, Models.Model()>) -> IO(Session.Session()):
  match model:
    case None{}: IO.pure(Session.Session(), session)
    case Some{found}:
      do IO<Session.Session()>:
        appended : Sessions.Outcome(Session.Appended()) <- Session.recordModel(session, found)
        return appendedOr(session, appended)

def recordedThinking(+session: Session.Session(), level: Ai.ModelThinkingLevel) -> IO(Session.Session()):
  do IO<Session.Session()>:
    appended : Sessions.Outcome(Session.Appended()) <- Session.recordThinking(session, level)
    return appendedOr(session, appended)

def seedHasThinking(seed: Runtime.SessionSeed) -> Bool:
  match seed:
    case Runtime.SessionSeed{_, _, _, Some{_}}: True{}
    case _: False{}

def newSessionRecord(+session: Session.Session(), model: Maybe<&2, Models.Model()>, level: Ai.ModelThinkingLevel) -> IO(Session.Session()):
  do IO<Session.Session()>:
    withModel : Session.Session() <- recordedModel(session, model)
    recordedThinking(withModel, level)

def recordStartup(+session: Session.Session(), +seed: Runtime.SessionSeed, model: Maybe<&2, Models.Model()>, +level: Ai.ModelThinkingLevel) -> IO(Session.Session()):
  Bool.pick(Unit -> IO(Session.Session()), Runtime.hasSessionMessages(seed), _ => Bool.pick(Unit -> IO(Session.Session()), seedHasThinking(seed), _ => IO.pure(Session.Session(), session), _ => recordedThinking(session, level))(Unit{}), _ => newSessionRecord(session, model, level))(Unit{})

# createAgentSession
# ------------------

def selectionModel(selection: ModelSelection) -> Maybe<&2, Models.Model()>:
  match selection:
    case ModelSelection{model, _}: model

def selectionMessage(selection: ModelSelection) -> Maybe<&2, String>:
  match selection:
    case ModelSelection{_, message}: message

def requestedModel(options: CreateAgentSessionOptions) -> Maybe<&2, Models.Model()>:
  match options:
    case CreateAgentSessionOptions{_, _, _, model, _, _, _, _, _, _, _, _, _}: model

def requestedThinking(options: CreateAgentSessionOptions) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, thinking, _, _, _, _, _, _, _, _}: thinking

def scopedOf(options: CreateAgentSessionOptions) -> List<&2, Models.ScopedModel>:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, _, scoped, _, _, _, _, _, _, _}: scoped

def loaderOption(options: CreateAgentSessionOptions) -> Maybe<&2, Resources.ResourceLoader>:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, _, _, _, _, _, loader, _, _, _}: loader

def sessionOption(options: CreateAgentSessionOptions) -> Maybe<&2, Session.Session()>:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, _, _, _, _, _, _, session, _, _}: session

def settingsOption(options: CreateAgentSessionOptions) -> Maybe<&2, Settings.SettingsManager>:
  match options:
    case CreateAgentSessionOptions{_, _, _, _, _, _, _, _, _, _, _, settings, _}: settings

def modelsOption(options: CreateAgentSessionOptions) -> Maybe<&2, Models.ModelRuntime>:
  match options:
    case CreateAgentSessionOptions{_, _, models, _, _, _, _, _, _, _, _, _, _}: models

def agentDirOption(options: CreateAgentSessionOptions) -> Maybe<&2, String>:
  match options:
    case CreateAgentSessionOptions{_, agentDir, _, _, _, _, _, _, _, _, _, _, _}: agentDir
def customToolsOf(options: CreateAgentSessionOptions) -> List<&2, ExtensionTypes.ToolDefinition>:
  match options:
    case CreateAgentSessionOptions{_,_,_,_,_,_,_,_,_,_,_,_,custom}: custom

def Outcome() -> Type: Result<&2, &1, String, CreateAgentSessionResult>

def extensionsRuntime(result: Resources.LoadExtensionsResult) -> ExtensionTypes.ExtensionRuntime():
  match result:
    case Resources.LoadExtensionsResult{_, _, runtime}: runtime

# What the agent is assembled from once the services exist.
type Assembly is Data:
  Assembly{environment: Paths.Environment, cwd: String, agentDir: String, packageDir: String, settings: Settings.SettingsManager, options: CreateAgentSessionOptions}

def failedAgent(transport: Runtime.Transport, choice: ModelsChoice, loader: OwnedLoader, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Runtime.Stream(), registry: StreamFn.Registry(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error()), validator: Loop.Validator(Runtime.Error()), keys: C.Callback<String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>>, converter: Runtime.Converter(), runner: ExtensionRunner.ExtensionRunner, message: String) -> IO(Outcome()):
  match choice:
    case ModelsChoice{models, owned}:
      do IO<Outcome()>:
        disposeServices(Services{transport, models, owned, loader, queue, tools, stream, registry, validator, keys, converter, runner})
        return Fail{message}

def withAgent(+assembly: Assembly, transport: Runtime.Transport, choice: ModelsChoice, loaderChoice: LoaderChoice, +extensions: Resources.LoadExtensionsResult, +session: Session.Session(), +seed: Runtime.SessionSeed, +selection: ModelSelection, +thinking: Ai.ModelThinkingLevel, +options: Runtime.CreateOptions, prepared: Result<&2, &2, String, Runtime.Prepared>, queue: Queue.Owner, created: List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>, +stream: Runtime.Stream(), +registry: StreamFn.Registry(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error()), +validator: Loop.Validator(Runtime.Error()), +keys: C.Callback<String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>>, +converter: Runtime.Converter(), +runner: ExtensionRunner.ExtensionRunner, agent: Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()>) -> IO(Outcome()):
  match assembly choice loaderChoice created prepared agent:
    case Assembly{environment, +cwd, _, +packageDir, +settings, +sdkOptions} ModelsChoice{+models, owned} LoaderChoice{+loader, ownedLoader} Tuple{owners, tools} Done{prepared} Done{+agent}:
      do IO<Outcome()>:
        recorded : Session.Session() <- recordStartup(session, seed, selectionModel(selection), thinking)
        +loadout : Runtime.Loadout = Runtime.loadoutFrom(prepared, tools, runner, Runtime.LoadoutSource{environment, options, packageDir, Some{loader}})
        live : Session.AgentSession <- Session.createWithTools(agent, recorded, settings, cwd, loadout, models, scopedOf(sdkOptions), customToolsOf(sdkOptions))
        return Done{CreateAgentSessionResult{live, extensions, selectionMessage(selection), Services{transport, models, owned, ownedLoader, queue, owners, stream, registry, validator, keys, converter, runner}}}
    case _ ModelsChoice{models, owned} LoaderChoice{_, ownedLoader} Tuple{owners, _} Fail{message} Done{agent}:
      do IO<Outcome()>:
        Agent.dispose(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, agent)
        failedAgent(transport, ModelsChoice{models, owned}, ownedLoader, queue, owners, stream, registry, validator, keys, converter, runner, message)
    case _ ModelsChoice{models, owned} LoaderChoice{_, ownedLoader} Tuple{owners, _} _ Fail{error}: failedAgent(transport, ModelsChoice{models, owned}, ownedLoader, queue, owners, stream, registry, validator, keys, converter, runner, StreamFn.errorMessage(error))

def withAgentCreated(+assembly: Assembly, transport: Runtime.Transport, choice: ModelsChoice, loaderChoice: LoaderChoice, +extensions: Resources.LoadExtensionsResult, +session: Session.Session(), +seed: Runtime.SessionSeed, +selection: ModelSelection, +thinking: Ai.ModelThinkingLevel, +options: Runtime.CreateOptions, prepared: Result<&2, &2, String, Runtime.Prepared>, created: Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>), +stream: Runtime.Stream(), +registry: StreamFn.Registry(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error()), +validator: Loop.Validator(Runtime.Error()), +keys: C.Callback<String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>>, +converter: Runtime.Converter(), +runner: ExtensionRunner.ExtensionRunner, agent: Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()>) -> IO(Outcome()):
  match created:
    case Tuple{queue, pair}: withAgent(assembly, transport, choice, loaderChoice, extensions, session, seed, selection, thinking, options, prepared, queue, pair, stream, registry, validator, keys, converter, runner, agent)

def withResources(+assembly: Assembly, transport: Runtime.Transport, choice: ModelsChoice, loaderChoice: LoaderChoice, +session: Session.Session()) -> IO(Outcome()):
  match assembly transport choice loaderChoice:
    case Assembly{+environment, +cwd, +agentDir, +packageDir, +settings, +sdkOptions} Runtime.Transport{+authorizer, network, +fetch, +codexSessions} ModelsChoice{+models, owned} LoaderChoice{+loader, ownedLoader}:
      do IO<Outcome()>:
        +extensions : Resources.LoadExtensionsResult <- Resources.getExtensions(loader)
        +runner : ExtensionRunner.ExtensionRunner <- ExtensionRunner.create(extensionsRuntime(extensions), cwd, models)
        +seed : Runtime.SessionSeed = seedOf(session)
        +selection : ModelSelection <- selectModel(Path.join(packageDir, "docs"), models, settings, seed, requestedModel(sdkOptions))
        +thinking : Ai.ModelThinkingLevel = Runtime.thinkingForSelection(requestedThinking(sdkOptions), seed, settings, selectionModel(selection))
        +toolSelection : Runtime.ToolSelection = selectionOf(sdkOptions)
        +setup : Runtime.ToolSetup = Runtime.resolveTools(toolSelection, Settings.getDefaultTools(settings))
        system : Maybe<&2, String> <- Resources.getSystemPrompt(loader)
        append : List<&2, String> <- Resources.getAppendSystemPrompt(loader)
        +options : Runtime.CreateOptions = Runtime.withLoadedPrompt(createOptionsFor(cwd, agentDir, packageDir, "", Some{thinking}, toolSelection, seed, settings), system, append)
        prepared : Result<&2, &2, String, Runtime.Prepared> <- Runtime.preparedFromLoader(loader, options, packageDir, Runtime.activeNamesOf(setup))
        queue : Queue.Owner <- Queue.create()
        created : Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) <- Runtime.createToolList(Runtime.registryOf(setup), Runtime.toolsOptionsFor(Runtime.builtinsOf(toolSelection), settings, environment), environment, cwd, agentDir, packageDir, fetch, ExtensionRunner.toolContext(runner), Queue.borrow(queue))
        apiStream : Composer.ProviderStream() <- Runtime.createApiStream(codexSessions, authorizer, fetch)
        Models.setApiStreams(models, Some{apiStream})
        +stream : Runtime.Stream() <- Runtime.createStream(fetch, Runtime.requestDefaults(settings), Runtime.KeySource{models, None{}}, Models.noTransforms())
        +registry : StreamFn.Registry(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error()) <- StreamFn.create(V.Value, Runtime.Details(), Runtime.LoopConfig(), Runtime.Error())
        +validator : Loop.Validator(Runtime.Error()) <- Loop.createPlain(~Runtime.Error(), ~Runtime.validationError)
        +keys : C.Callback<String, Result<&2, &2, Runtime.Error(), Maybe<&2, String>>> <- C.create(~Runtime.KeySource, ~String, ~Result<&2, &2, Runtime.Error(), Maybe<&2, String>>, ~Runtime.resolveKey, Runtime.KeySource{models, None{}})
        +converter : Runtime.Converter() <- Runtime.createConverter(Settings.getBlockImages(settings))
        agent : Result<&2, &2, StreamFn.MissingDefault, Runtime.Owner()> <- Agent.new(~V.Value, ~Runtime.Details(), ~Runtime.Custom(), ~Runtime.Error(), ~Unit, Runtime.agentOptions(selectionModel(selection), thinking, stream, keys, converter, seed, settings), registry, validator, Tools.emptyDetails())
        withAgentCreated(Assembly{environment, cwd, agentDir, packageDir, settings, sdkOptions}, Runtime.Transport{authorizer, network, fetch, codexSessions}, ModelsChoice{models, owned}, LoaderChoice{loader, ownedLoader}, extensions, session, seed, selection, thinking, options, prepared, created, stream, registry, validator, keys, converter, runner, agent)

def failedSession(transport: Runtime.Transport, choice: ModelsChoice, message: String) -> IO(Outcome()):
  match choice:
    case ModelsChoice{models, owned}:
      do IO<Outcome()>:
        disposeOwnedModels(models, owned)
        Runtime.disposeTransport(transport)
        return Fail{message}

def withSessionRecord(+assembly: Assembly, transport: Runtime.Transport, choice: ModelsChoice, session: Result<&2, &2, String, Session.Session()>) -> IO(Outcome()):
  match session assembly:
    case Fail{message} _: failedSession(transport, choice, message)
    case Done{+record} Assembly{+environment, +cwd, +agentDir, +packageDir, +settings, +sdkOptions}:
      do IO<Outcome()>:
        loaderChoice : LoaderChoice <- loaderFor(loaderOption(sdkOptions), environment, cwd, agentDir, settings)
        withResources(Assembly{environment, cwd, agentDir, packageDir, settings, sdkOptions}, transport, choice, loaderChoice, record)

def withTransport(+assembly: Assembly, transport: Runtime.Outcome(Runtime.Transport)) -> IO(Outcome()):
  match transport assembly:
    case Fail{message} _: IO.pure(Outcome(), Fail{message})
    case Done{Runtime.Transport{authorizer, network, +fetch, codexSessions}} Assembly{environment, +cwd, +agentDir, packageDir, settings, +sdkOptions}:
      do IO<Outcome()>:
        choice : ModelsChoice <- modelsFor(modelsOption(sdkOptions), agentDir, fetch)
        session : Result<&2, &2, String, Session.Session()> <- sessionFor(sessionOption(sdkOptions), cwd, agentDir)
        withSessionRecord(Assembly{environment, cwd, agentDir, packageDir, settings, sdkOptions}, Runtime.Transport{authorizer, network, fetch, codexSessions}, choice, session)

def bundlePath(value: Result<&1, &1, U32 & String, String>) -> String:
  match value:
    case Done{SCon{c, cs}}: SCon{c, cs}
    case _: "/etc/ssl/certs/ca-certificates.crt"

def withEnvironment(+environment: Paths.Environment, +options: CreateAgentSessionOptions) -> IO(Outcome()):
  do IO<Outcome()>:
    +cwd : String = cwdFor(environment, options)
    +agentDir : String <- agentDirFor(environment, agentDirOption(options))
    packageDir : String <- AppConfig.getPackageDir()
    bundle : Result<&1, &1, U32 & String, String> <- IO.get_env("SSL_CERT_FILE")
    +settings : Settings.SettingsManager <- settingsFor(settingsOption(options), cwd, agentDir)
    transport : Runtime.Outcome(Runtime.Transport) <- Runtime.createTransportWith(bundlePath(bundle), Runtime.globalHttpProxy(settings))
    withTransport(Assembly{environment, cwd, agentDir, packageDir, settings, options}, transport)

def locatedEnvironment(+options: CreateAgentSessionOptions, environment: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Outcome()):
  match environment:
    case Fail{_}: IO.pure(Outcome(), Fail{"Could not resolve the working directory"})
    case Done{found}: withEnvironment(found, options)

# upstream createAgentSession(options).
def createAgentSession(options: CreateAgentSessionOptions) -> IO(Outcome()):
  do IO<Outcome()>:
    environment : Result<&2, &2, FS.Error, Paths.Environment> <- Paths.loadEnvironment(Runtime.urlContext())
    locatedEnvironment(options, environment)
