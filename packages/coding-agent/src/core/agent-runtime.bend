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
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/posix-path.bend as Path
import ../utils/paths.bend as Paths
import ./auth-storage.bend as Storage
import ./runtime-credentials.bend as Runtime
import ./model-runtime.bend as Models
import ./system-prompt.bend as Prompt
import ./tools/index.bend as Tools
import ./tools/file-mutation-queue.bend as Queue

# The owned services behind one agent: transport, credentials, model runtime,
# tools and the Agent itself. This is the print-mode slice of upstream's
# AgentSessionServices/AgentSessionRuntime: no session persistence,
# extensions, skills, settings or interactive mode yet.

def Error() -> Data: Tools.ToolError
def Details() -> Data: Tools.ToolDetails
def LoopConfig() -> Data: T.AgentLoopConfig<Unit, Details(), Unit, Error(), Unit>
def Owner() -> Data: Agent.Agent<Unit, Details(), Unit, Error(), Unit>
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
  T.toSimpleStreamOptions(Unit, Details(), Unit, Error(), Unit, config)

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

# Context files
# -------------

def contextCandidates() -> List<&2, String>: ["AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"]

def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{FEFF}', rest}: rest
    case other: other

def contextRead(path: String, bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, Prompt.ContextFile>:
  match bytes:
    case Fail{_}: None{}
    case Done{octets}: Some{Prompt.ContextFile{path, stripBom(Utf8.decodeBytes(octets))}}

def contextFileAt(+path: String, isFile: Result<&1, &1, U32 & String, Bool>) -> IO(Maybe<&2, Prompt.ContextFile>):
  match isFile:
    case Done{True{}}:
      do IO<Maybe<&2, Prompt.ContextFile>>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        return contextRead(path, bytes)
    case _: IO.pure(Maybe<&2, Prompt.ContextFile>, None{})

# The first existing candidate in a directory.
def loadContextFileFromDir(+directory: String, candidates: List<&2, String>, found: Maybe<&2, Prompt.ContextFile>) -> IO(Maybe<&2, Prompt.ContextFile>):
  match candidates found:
    case _ Some{file}: IO.pure(Maybe<&2, Prompt.ContextFile>, Some{file})
    case Nil{} None{}: IO.pure(Maybe<&2, Prompt.ContextFile>, None{})
    case +name <> rest None{}:
      do IO<Maybe<&2, Prompt.ContextFile>>:
        isFile : Result<&1, &1, U32 & String, Bool> <- File.is_file(Path.join(directory, name))
        file : Maybe<&2, Prompt.ContextFile> <- contextFileAt(Path.join(directory, name), isFile)
        loadContextFileFromDir(directory, rest, file)

def prepend(found: Maybe<&2, Prompt.ContextFile>, files: List<&2, Prompt.ContextFile>) -> List<&2, Prompt.ContextFile>:
  match found:
    case None{}: files
    case Some{file}: file <> files

# Ancestor directories from the root down to cwd, nearest last.
def ancestorContextFiles(fuel: Nat, +directory: String, files: List<&2, Prompt.ContextFile>, atRoot: Bool) -> IO(List<&2, Prompt.ContextFile>):
  match fuel atRoot:
    case _ True{}: IO.pure(List<&2, Prompt.ContextFile>, files)
    case 0n False{}: IO.pure(List<&2, Prompt.ContextFile>, files)
    case 1n+n False{}:
      +parent = Path.join(directory, "..")
      do IO<List<&2, Prompt.ContextFile>>:
        found : Maybe<&2, Prompt.ContextFile> <- loadContextFileFromDir(directory, contextCandidates(), None{})
        ancestorContextFiles(n, parent, prepend(found, files), String.eq(parent, directory))

# The global context file, then ancestor files from the root down. The git
# worktree shadowing rule of upstream is not ported.
def loadProjectContextFiles(cwd: String, agentDir: String) -> IO(List<&2, Prompt.ContextFile>):
  do IO<List<&2, Prompt.ContextFile>>:
    global : Maybe<&2, Prompt.ContextFile> <- loadContextFileFromDir(agentDir, contextCandidates(), None{})
    ancestors : List<&2, Prompt.ContextFile> <- ancestorContextFiles(64n, cwd, Nil{}, False{})
    return prepend(global, ancestors)

# Services
# --------

type CreateOptions is Data:
  CreateOptions{cwd: String, agentDir: String, authPath: String, bundlePath: String, packageDir: String, provider: Maybe<&2, String>, model: Maybe<&2, String>, apiKey: Maybe<&2, String>, thinking: Maybe<&2, Ai.ModelThinkingLevel>, systemPrompt: Maybe<&2, String>, appendSystemPrompt: List<&2, String>, tools: List<&2, Tools.ToolName>, contextFiles: Bool}

type AgentRuntime is Type:
  AgentRuntime{transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, agent: Owner(), model: Models.Model()}

def snippets(names: List<&2, Tools.ToolName>, record: R.Record<String>) -> R.Record<String>:
  match names:
    case Nil{}: record
    case +name <> rest: snippets(rest, R.set(String, record, Tools.toolName(name), Tools.promptSnippet(name)))

def guidelines(names: List<&2, Tools.ToolName>, record: R.Record<List<&2, String>>) -> R.Record<List<&2, String>>:
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
    case CreateOptions{cwd, _, _, _, _, _, _, _, _, systemPrompt, appendSystemPrompt, +names, _}:
      Prompt.BuildSystemPromptOptions{systemPrompt, None{}, Some{toolNames(names)}, Some{snippets(names, R.new(String))}, Some{guidelines(names, R.new(List<&2, String>))}, None{}, nonemptyAppend(appendSystemPrompt), None{}, cwd, Some{contextList}, None{}}

def contextFilesFor(options: CreateOptions) -> IO(List<&2, Prompt.ContextFile>):
  match options:
    case CreateOptions{cwd, agentDir, _, _, _, _, _, _, _, _, _, _, True{}}: loadProjectContextFiles(cwd, agentDir)
    case _: IO.pure(List<&2, Prompt.ContextFile>, Nil{})

def systemPromptFor(+options: CreateOptions, packageDir: String) -> IO(Result<&2, &2, String, String>):
  do IO<Result<&2, &2, String, String>>:
    contextList : List<&2, Prompt.ContextFile> <- contextFilesFor(options)
    return Prompt.buildSystemPrompt(promptOptions(options, contextList), Prompt.docsPaths(packageDir))

def levelOf(result: Models.ResolveCliModelResult) -> Maybe<&2, Ai.ModelThinkingLevel>:
  match result:
    case Models.ResolveCliModelResult{_, level, _, _}: level

def noModels() -> String:
  "No models available.\n\nRun pi to log in with a provider, or set an API key environment variable such as OPENAI_API_KEY."

def chosenFrom(models: Models.ModelRuntime, error: Maybe<&2, String>, model: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Models.Model()>):
  match error model:
    case Some{message} _: IO.pure(Result<&2, &2, String, Models.Model()>, Fail{message})
    case None{} Some{chosen}: IO.pure(Result<&2, &2, String, Models.Model()>, Done{chosen})
    case None{} None{}:
      do IO<Result<&2, &2, String, Models.Model()>>:
        initial : Maybe<&2, Models.Model()> <- Models.findInitialModel(models)
        return Maybe.default(&2, Result<&2, &2, String, Models.Model()>, Maybe.map(&2, Models.Model(), Result<&2, &2, String, Models.Model()>, found => Done{found}, initial), Fail{noModels()})

def chosenModel(models: Models.ModelRuntime, resolved: Models.ResolveCliModelResult) -> IO(Result<&2, &2, String, Models.Model()>):
  match resolved:
    case Models.ResolveCliModelResult{model, _, _, error}: chosenFrom(models, error, model)

def modelApi(model: Models.Model()) -> Ai.ModelApi:
  match model:
    case Ai.Model{_, _, api, _, _, _, _, _, _, _, _, _, _, _}: api

# The OpenAI Responses and Codex Responses APIs stream through the modular provider.
def supportedApi(api: Ai.ModelApi, model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  match api:
    case Ai.OpenAIResponsesApi{}: Done{model}
    case Ai.OpenAICodexResponsesApi{}: Done{model}
    case _: Fail{"Model " ++ Models.reference(model) ++ " uses an API this port does not stream yet (openai-responses and openai-codex-responses)."}

def supportedModel(+model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  supportedApi(modelApi(model), model)

def supported(model: Models.Model()) -> Result<&2, &2, String, Models.Model()>:
  supportedModel(model)

def selectModel(+models: Models.ModelRuntime, options: CreateOptions) -> IO(Result<&2, &2, String, Models.Model()>):
  match options:
    case CreateOptions{_, _, _, _, _, provider, cliModel, _, _, _, _, _, _}:
      do IO<Result<&2, &2, String, Models.Model()>>:
        chosen : Result<&2, &2, String, Models.Model()> <- chosenModel(models, Models.resolveCliModel(models, provider, cliModel))
        return Result.bind(&2, &2, String, Models.Model(), Models.Model(), chosen, supported)

# --thinking, otherwise off (the model pattern's :level suffix is not applied yet).
def thinkingLevel(requested: Maybe<&2, Ai.ModelThinkingLevel>) -> Ai.ModelThinkingLevel:
  Maybe.default(&2, Ai.ModelThinkingLevel, requested, Ai.Off{})

def agentOptions(prompt: String, model: Models.Model(), thinking: Ai.ModelThinkingLevel, tools: List<&2, Tools.Tool()>, stream: Stream(), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>) -> Agent.AgentOptions<Unit, Details(), Unit, Error(), Unit>:
  Agent.AgentOptions{Some{Agent.AgentInitialState{Some{prompt}, Some{model}, Some{thinking}, Some{tools}, None{}}}, None{}, None{}, Some{stream}, Some{keys}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}

def environment(paths: Paths.Environment, cwd: String, agentDir: String, queue: Queue.Queue) -> Tools.Environment:
  Tools.Environment{paths, cwd, Path.join(agentDir, "bin"), queue}

def pathsError(error: FS.Error) -> String: "Could not resolve the working directory"

def disposeServices(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>) -> IO(Unit):
  do IO<Unit>:
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
def constructed(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, queue: Queue.Owner, tools: List<&1, Tools.ToolOwner>, stream: Stream(), registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), validator: Loop.Validator(Error()), keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, model: Models.Model(), result: Result<&2, &2, StreamFn.MissingDefault, Owner()>) -> IO(Outcome(AgentRuntime)):
  match result:
    case Done{agent}: IO.pure(Outcome(AgentRuntime), Done{AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, agent, model}})
    case Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys)
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

def assembled(transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, models: Models.ModelRuntime, created: Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>), +stream: Stream(), +registry: StreamFn.Registry(Unit, Details(), LoopConfig(), Error()), +validator: Loop.Validator(Error()), +keys: C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>>, prompt: String, +model: Models.Model(), thinking: Ai.ModelThinkingLevel) -> IO(Outcome(AgentRuntime)):
  match created:
    case Tuple{queue, Tuple{owners, tools}}:
      do IO<Outcome(AgentRuntime)>:
        result : Result<&2, &2, StreamFn.MissingDefault, Owner()> <- Agent.new(~Unit, ~Details(), ~Unit, ~Error(), ~Unit, agentOptions(prompt, model, thinking, tools, stream, keys), registry, validator, Tools.WriteDetails{})
        constructed(transport, storage, storageStore, credentials, credentialStore, models, queue, owners, stream, registry, validator, keys, model, result)

def withModelFields(+cwd: String, +agentDir: String, apiKey: Maybe<&2, String>, thinking: Ai.ModelThinkingLevel, +names: List<&2, Tools.ToolName>, transport: Transport, storage: Storage.AuthStorageOwner, storageStore: Auth.CredentialStore, credentials: Runtime.RuntimeCredentials, credentialStore: Auth.CredentialStore, +models: Models.ModelRuntime, paths: Paths.Environment, prompt: Result<&2, &2, String, String>, selected: Result<&2, &2, String, Models.Model()>) -> IO(Outcome(AgentRuntime)):
  match transport prompt selected:
    case Transport{+authorizer, runtime, fetch} Done{prompt} Done{+model}:
      do IO<Outcome(AgentRuntime)>:
        queue : Queue.Owner <- Queue.create()
        created : Queue.Owner & (List<&1, Tools.ToolOwner> & List<&2, Tools.Tool()>) <- createToolList(names, paths, cwd, agentDir, Queue.borrow(queue))
        +stream : Stream() <- createStream(authorizer)
        +registry : StreamFn.Registry(Unit, Details(), LoopConfig(), Error()) <- StreamFn.create(Unit, Details(), LoopConfig(), Error())
        +validator : Loop.Validator(Error()) <- Loop.createPlain(~Error(), ~validationError)
        +keys : C.Callback<String, Result<&2, &2, Error(), Maybe<&2, String>>> <- C.create(~KeySource, ~String, ~Result<&2, &2, Error(), Maybe<&2, String>>, ~resolveKey, KeySource{models, apiKey})
        assembled(Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, created, stream, registry, validator, keys, prompt, model, thinking)
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
    case CreateOptions{cwd, agentDir, _, _, _, _, _, apiKey, thinking, _, _, names, _}: withModelFields(cwd, agentDir, apiKey, thinkingLevel(thinking), names, transport, storage, storageStore, credentials, credentialStore, models, paths, prompt, selected)

def applyKey(credentials: Runtime.RuntimeCredentials, apiKey: Maybe<&2, String>, selected: Result<&2, &2, String, Models.Model()>) -> IO(Unit):
  match apiKey selected:
    case Some{key} Done{model}: Runtime.setRuntimeApiKey(credentials, Models.modelProvider(model), key)
    case _ _: IO.pure(Unit, Unit{})

def storageStep(+options: CreateOptions, +packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, paths: Paths.Environment, borrowed: Storage.AuthStorageOwner & Storage.AuthStorage) -> IO(Outcome(AgentRuntime)):
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
        prompt : Result<&2, &2, String, String> <- systemPromptFor(options, packageDir)
        withModel(options, Transport{authorizer, runtime, fetch}, storage, storageStore, credentials, credentialStore, models, paths, prompt, selected)

def withPathsFields(options: CreateOptions, authPath: String, packageDir: String, apiKey: Maybe<&2, String>, transport: Transport, paths: Paths.Environment) -> IO(Outcome(AgentRuntime)):
  do IO<Outcome(AgentRuntime)>:
    storage : Storage.AuthStorageOwner <- Storage.create(authPath)
    storageStep(options, packageDir, apiKey, transport, paths, Storage.borrow(storage))

def withPaths(options: CreateOptions, transport: Transport, paths: Result<&2, &2, FS.Error, Paths.Environment>) -> IO(Outcome(AgentRuntime)):
  match options paths:
    case _ Fail{error}:
      do IO<Outcome(AgentRuntime)>:
        disposeTransport(transport)
        return Fail{pathsError(error)}
    case CreateOptions{cwd, agentDir, +authPath, bundlePath, +packageDir, provider, model, +apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles} Done{paths}: withPathsFields(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles}, authPath, packageDir, apiKey, transport, paths)

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
    case CreateOptions{cwd, agentDir, authPath, +bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles}:
      do IO<Outcome(AgentRuntime)>:
        transport : Outcome(Transport) <- createTransport(bundlePath)
        withTransport(CreateOptions{cwd, agentDir, authPath, bundlePath, packageDir, provider, model, apiKey, thinking, systemPrompt, appendSystemPrompt, names, contextFiles}, transport)

def agentOf(runtime: AgentRuntime) -> AgentRuntime & Owner():
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, +agent, model}: (AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, agent, model}, agent)

def dispose(runtime: AgentRuntime) -> IO(Unit):
  match runtime:
    case AgentRuntime{transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys, agent, _}:
      do IO<Unit>:
        Agent.dispose(Unit, Details(), Unit, Error(), Unit, agent)
        disposeServices(transport, storage, storageStore, credentials, credentialStore, models, queue, tools, stream, registry, validator, keys)
