import Base
import ../../ai/src/types.bend as Ai
import ../../ai/src/models.bend as AiModels
import ../../ai/src/auth/types.bend as Auth
import ../../ai/src/auth/helpers.bend as AuthHelpers
import ../../ai/src/auth/context.bend as AuthContext
import ../../ai/src/auth/resolve.bend as Resolve
import ../../ai/src/auth/credential-store.bend as Credentials
import ../../agent/src/agent.bend as Agent
import ../../agent/src/types.bend as AgentTypes
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as Rf
import ../../runtime/src/record.bend as Record
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/f64.bend as F
import ../src/utils/paths.bend as Paths
import ../src/core/agent-runtime.bend as Runtime
import ../src/core/agent-session.bend as Session
import ../src/core/sdk.bend as Sdk
import ../src/core/settings-manager.bend as Settings
import ../src/core/model-runtime.bend as Models
import ../src/core/provider-composer.bend as Composer
import ../src/core/resource-loader.bend as Resources
import ../src/core/tools/index.bend as Tools
import ../src/core/extensions/loader.bend as Loader
import ../src/core/extensions/runner.bend as Runner
import ../src/core/extensions/types.bend as Ext

# Port of sdk-stream-options.test.ts: six request defaults/overrides plus
# assembled headers. The SDK Agent's stream function reaches an injected
# provider stream that captures the effective options without HTTP.
# Build: sh scripts/build-incremental.sh packages/coding-agent/test/sdk-stream-options.bend build/sdk-stream-options-native
# Check: python3 tests/sdk_suites_check.py --prefix build/ --lanes native-1,native-4 sdk-stream-options

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def zero() -> F64: F.fromU32(0)
def number(n: U32) -> F64: F.fromU32(n)
def equal(value: Maybe<&2, F64>, expected: U32) -> Bool:
  match value:
    case Some{found}: F.isEqual(F.compare(found, number(expected)))
    case None{}: False{}

def model(api: Ai.ModelApi, +id: String) -> Ai.Model<Ai.JsonValue>:
  Ai.Model{id, id, api, "capture-provider", "https://capture.invalid/v1", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, number(128000), number(4096), None{}, Some{Record.set(String, Record.new(String), "x-model", "model")}, None{}}

def provider(codex: Ai.Model<Ai.JsonValue>, completions: Ai.Model<Ai.JsonValue>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    key : Auth.ApiKeyAuth <- AuthHelpers.envApiKeyAuth("Capture key", ["PI_SDK_STREAM_UNUSED"])
    return AiModels.Provider{"capture-provider", "Capture Provider", "https://capture.invalid/v1", Auth.ProviderAuth{Some{key}, None{}}, [codex, completions], AiModels.ApiStreams{}, None{}, None{}}

def capture(slot: Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{_, _, options}:
      do IO<Composer.StreamOutput()>:
        Rf.write(Maybe<&2, Composer.StreamOptions()>, slot, options)
        return Fail{Tools.Failure{"captured"}}

def captured(result: Composer.StreamOutput()) -> Bool:
  match result:
    case Fail{Tools.Failure{"captured"}}: True{}
    case _: False{}

def optionValues(options: Composer.StreamOptions()) -> List<&2, Maybe<&2, F64>>:
  match options:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, _, timeout, retries, delay, _, _, _, _, _, _, connect, _, _, _, _, _}: [timeout, connect, retries, delay]

def optionAt(options: Composer.StreamOptions(), index: Nat) -> Maybe<&2, F64>:
  Maybe.default(&2, Maybe<&2, F64>, List.get(&2, Maybe<&2, F64>, optionValues(options), index), None{})

def headersOf(options: Composer.StreamOptions()) -> Maybe<&2, Ai.ProviderHeaders()>:
  match options:
    case Ai.SimpleStreamOptions{_, _, _, _, _, _, _, headers, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: headers

def headerValue(found: Maybe<&2, Ai.Nullable<String>>) -> String:
  match found:
    case Some{Ai.PresentValue{value}}: value
    case _: "-"

def header(headers: Ai.ProviderHeaders(), name: String) -> String: headerValue(Record.get(Ai.Nullable<String>, headers, name))

def assembled(found: Maybe<&2, Ai.ProviderHeaders()>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+headers}:
      String.eq(header(headers, "x-provider"), "provider") && String.eq(header(headers, "x-model"), "model") && String.eq(header(headers, "x-explicit"), "explicit") && String.eq(header(headers, "x-hook"), "provider:model:explicit") && String.eq(header(headers, "x-good"), "yes")

def failedHeader(_: Unit, _: Ext.HandlerCall<Ext.BeforeProviderHeadersEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>):
  IO.pure(Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>, Fail{"header handler boom"})

def goodHeader(_: Unit, call: Ext.HandlerCall<Ext.BeforeProviderHeadersEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>):
  match call:
    case Ext.HandlerCall{Ext.BeforeProviderHeadersEvent{+headers}, _}:
      +combined = header(headers, "x-provider") ++ ":" ++ header(headers, "x-model") ++ ":" ++ header(headers, "x-explicit")
      +updated = Record.set(Ai.Nullable<String>, headers, "x-hook", Ai.PresentValue{combined})
      IO.pure(Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>, Done{Some{Record.set(Ai.Nullable<String>, updated, "x-good", Ai.PresentValue{"yes"})}})

def subscriptions(first: Result<&2, &2, String, Loader.Unsubscribe>, second: Result<&2, &2, String, Loader.Unsubscribe>) -> Result<&2, &2, String, Unit>:
  match first second:
    case Fail{message} _: Fail{message}
    case _ Fail{message}: Fail{message}
    case _ _: Done{Unit{}}

def headerFactory(_: Unit, +api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    bad : Ext.ExtensionHandler(Ext.BeforeProviderHeadersEvent, Ai.ProviderHeaders()) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeProviderHeadersEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>, ~failedHeader, Unit{})
    good : Ext.ExtensionHandler(Ext.BeforeProviderHeadersEvent, Ai.ProviderHeaders()) <- C.create(~Unit, ~Ext.HandlerCall<Ext.BeforeProviderHeadersEvent>, ~Result<&2, &2, String, Maybe<&2, Ai.ProviderHeaders()>>, ~goodHeader, Unit{})
    first : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderHeaders{bad})
    second : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, Ext.OnBeforeProviderHeaders{good})
    return subscriptions(first, second)

def recordError(slot: Rf.Ref<List<&2, Ext.ExtensionError>>, error: Ext.ExtensionError) -> IO(Unit):
  Rf.modify(List<&2, Ext.ExtensionError>, Unit, slot, current => (List.append(&2, Ext.ExtensionError, current, [error]), Unit{}))

def failedAndContinued(found: List<&2, Ext.ExtensionError>) -> Bool:
  match found:
    case Ext.ExtensionError{_, "before_provider_headers", message, _} <> Nil{}: String.contains(message, "header handler boom")
    case _: False{}

def requiredRunner(found: Maybe<&2, Runner.ExtensionRunner>) -> IO(Runner.ExtensionRunner):
  match found:
    case Some{runner}: IO.pure(Runner.ExtensionRunner, runner)
    case None{}: IO.die(Runner.ExtensionRunner, 1, "missing extension runner")

def settingsOf(pair: Settings.FileSettingsStorage & Settings.SettingsManager) -> Settings.SettingsManager:
  match pair:
    case (_, value): value

def withOverrides(config: Runtime.LoopConfig(), timeout: Maybe<&2, F64>, connect: Maybe<&2, F64>, headers: Maybe<&2, Ai.ProviderHeaders()>) -> Runtime.LoopConfig():
  match config:
    case AgentTypes.AgentLoopConfig{Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, onPayload, onResponse, oldHeaders, oldTimeout, retries, delay, temperature, sampling, maxTokens, transport, cache, sessionId, oldConnect, metadata, toolChoice, reasoning, deferred, budgets}, model, convert, transform, getKey, finish, prepare, next, steer, follow, execution, beforeTool, afterTool}:
      AgentTypes.AgentLoopConfig{Ai.SimpleStreamOptions{signal, telemetry, key, fetch, env, onPayload, onResponse, Maybe.or(&2, Ai.ProviderHeaders(), headers, oldHeaders), Maybe.or(&2, F64, timeout, oldTimeout), retries, delay, temperature, sampling, maxTokens, transport, cache, sessionId, Maybe.or(&2, F64, connect, oldConnect), metadata, toolChoice, reasoning, deferred, budgets}, model, convert, transform, getKey, finish, prepare, next, steer, follow, execution, beforeTool, afterTool}

def requiredOption(found: Maybe<&2, Composer.StreamOptions()>) -> IO(Composer.StreamOptions()):
  match found:
    case Some{value}: IO.pure(Composer.StreamOptions(), value)
    case None{}: IO.die(Composer.StreamOptions(), 1, "provider did not capture options")

def request(+live: Session.AgentSession, +slot: Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, selected: Ai.Model<Ai.JsonValue>, timeout: Maybe<&2, F64>, connect: Maybe<&2, F64>, headers: Maybe<&2, Ai.ProviderHeaders()>) -> IO(Composer.StreamOptions()):
  do IO<Composer.StreamOptions()>:
    stream : Runtime.Stream() <- Agent.getStreamFunction(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live))
    base : Runtime.LoopConfig() <- Agent.getConfig(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live))
    result : Composer.StreamOutput() <- C.call(AgentTypes.StreamInput<V.Value, Runtime.Details(), Runtime.LoopConfig()>, Composer.StreamOutput(), stream, AgentTypes.StreamInput{selected, Ai.TranscriptContext{Nil{}}, Some{withOverrides(base, timeout, connect, headers)}})
    Bool.pick(Unit -> IO(Unit), captured(result), _ => IO.pure(Unit, Unit{}), _ => IO.die(Unit, 1, "request did not reach the fake provider"))(Unit{})
    seen : Maybe<&2, Composer.StreamOptions()> <- Rf.read(Maybe<&2, Composer.StreamOptions()>, slot)
    requiredOption(seen)

def registration(result: Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{message}: IO.die(Unit, 1, message)

def authorization(result: Result<&2, &2, Resolve.ModelsError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "runtime key setup failed")

def written(result: Result<&2, &2, FS.Error, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "settings fixture write failed")

def checkedSession(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, models: Models.ModelRuntime, +stream: Composer.ProviderStream(), +slot: Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, +errors: Rf.Ref<List<&2, Ext.ExtensionError>>, +codex: Ai.Model<Ai.JsonValue>, +completions: Ai.Model<Ai.JsonValue>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match pair:
    case Tuple{owner, +live}:
      do IO<Unit>:
        first : Composer.StreamOptions() <- request(live, slot, codex, None{}, None{}, None{})
        check(equal(optionAt(first, 0n), 1234), "forwards httpIdleTimeoutMs as timeoutMs for OpenAI Codex")
        second : Composer.StreamOptions() <- request(live, slot, completions, None{}, None{}, None{})
        check(equal(optionAt(second, 0n), 1234), "defaults timeoutMs from httpIdleTimeoutMs for all providers")
        third : Composer.StreamOptions() <- request(live, slot, codex, Some{zero()}, None{}, None{})
        check(equal(optionAt(third, 0n), 0), "lets request timeoutMs override httpIdleTimeoutMs for OpenAI Codex")
        fourth : Composer.StreamOptions() <- request(live, slot, codex, None{}, None{}, None{})
        check(equal(optionAt(fourth, 1n), 1234), "forwards websocketConnectTimeoutMs from settings")
        fifth : Composer.StreamOptions() <- request(live, slot, codex, None{}, Some{zero()}, None{})
        check(equal(optionAt(fifth, 1n), 0), "lets request websocketConnectTimeoutMs override settings")
        +sixth : Composer.StreamOptions() <- request(live, slot, completions, None{}, None{}, None{})
        check(equal(optionAt(sixth, 2n), 2) && equal(optionAt(sixth, 3n), 3000), "forwards provider retry settings")
        config : Composer.ProviderConfigInput = Composer.ProviderConfigInput{None{}, None{}, Some{"test-key"}, Some{Ai.OpenAICompletionsApi{}}, Some{stream}, Some{Record.set(String, Record.new(String), "x-provider", "provider")}, None{}, None{}}
        registered : Result<&2, &2, String, Unit> <- Models.registerProvider(models, "capture-provider", config)
        registration(registered)
        found : Maybe<&2, Runner.ExtensionRunner> <- Session.extensionRunner(live)
        +runner : Runner.ExtensionRunner <- requiredRunner(found)
        +listener : C.Callback<Ext.ExtensionError, Unit> <- C.create(~Rf.Ref<List<&2, Ext.ExtensionError>>, ~Ext.ExtensionError, ~Unit, ~recordError, errors)
        subscription : Runner.ErrorSubscription <- Runner.onError(runner, listener)
        +direct : Ai.ProviderHeaders() <- Runner.emitBeforeProviderHeaders(runner, Record.set(Ai.Nullable<String>, Record.new(Ai.Nullable<String>), "User-Agent", Ai.PresentValue{"kimchi/1.0"}))
        check(String.eq(header(direct, "User-Agent"), "kimchi/1.0") && String.eq(header(direct, "x-good"), "yes"), "before_provider_headers preserves existing headers and inserts new ones")
        directError : List<&2, Ext.ExtensionError> <- Rf.read(List<&2, Ext.ExtensionError>, errors)
        check(failedAndContinued(directError), "before_provider_headers isolates a throwing handler and applies the next")
        Rf.write(List<&2, Ext.ExtensionError>, errors, Nil{})
        explicit : Ai.ProviderHeaders() = Record.set(Ai.Nullable<String>, Record.new(Ai.Nullable<String>), "x-explicit", Ai.PresentValue{"explicit"})
        seventh : Composer.StreamOptions() <- request(live, slot, completions, None{}, None{}, Some{explicit})
        check(assembled(headersOf(seventh)), "runs before_provider_headers on assembled headers without forwarding the transform")
        seenError : List<&2, Ext.ExtensionError> <- Rf.read(List<&2, Ext.ExtensionError>, errors)
        Bool.pick(Unit -> IO(Unit), failedAndContinued(seenError), _ => IO.pure(Unit, Unit{}), _ => IO.die(Unit, 1, "SDK request did not report the header handler failure"))(Unit{})
        Runner.offError(runner, subscription)
        C.dispose(Ext.ExtensionError, Unit, listener)
        Sdk.dispose(owner)
        Resources.disposeDefaultResourceLoader(loader)
        IO.print("ok SDK stream options disposed")

def finished(result: Sdk.Outcome(), models: Models.ModelRuntime, stream: Composer.ProviderStream(), slot: Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, errors: Rf.Ref<List<&2, Ext.ExtensionError>>, codex: Ai.Model<Ai.JsonValue>, completions: Ai.Model<Ai.JsonValue>, loader: Resources.DefaultResourceLoader) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: checkedSession(Sdk.sessionOf(owner), models, stream, slot, errors, codex, completions, loader)

def run(+directory: String) -> IO(Unit):
  do IO<Unit>:
    wrote : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(FS.child(directory, "settings.json"), "{\"httpIdleTimeoutMs\":1234,\"websocketConnectTimeoutMs\":1234,\"retry\":{\"provider\":{\"maxRetries\":2,\"maxRetryDelayMs\":3000}}}")
    written(wrote)
    +slot : Rf.Ref<Maybe<&2, Composer.StreamOptions()>> <- Rf.new(Maybe<&2, Composer.StreamOptions()>, None{})
    +errors : Rf.Ref<List<&2, Ext.ExtensionError>> <- Rf.new(List<&2, Ext.ExtensionError>, Nil{})
    +stream : Composer.ProviderStream() <- C.create(~Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~capture, slot)
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    +codex : Ai.Model<Ai.JsonValue> = model(Ai.OpenAICodexResponsesApi{}, "capture-codex")
    +completions : Ai.Model<Ai.JsonValue> = model(Ai.OpenAICompletionsApi{}, "capture-completions")
    native : AiModels.Provider <- provider(codex, completions)
    registered : Result<&2, &2, String, Unit> <- Models.registerNativeProviderStream(models, native, Some{stream})
    registration(registered)
    authorized : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(models, "capture-provider", "test-key", None{})
    authorization(authorized)
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    +settings : Settings.SettingsManager = settingsOf(pair)
    factory : Ext.ExtensionFactory() <- C.create(~Unit, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(unit => api => headerFactory(unit, api)), Unit{})
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{directory, directory, Runtime.urlContext()}, Resources.defaultResourceLoaderOptions(directory, directory, settings), [Ext.InlineExtension{"headers", factory, False{}}])
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, Some{models}, Some{codex}, None{}, Nil{}, None{}, None{}, None{}, Some{Resources.loaderOf(loader)}, None{}, Some{settings}, Nil{}, None{}})
    finished(created, models, stream, slot, errors, codex, completions, loader)
    Models.dispose(models)
    Auth.disposeStore(store)
    C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), stream)
    previous : Maybe<&2, Composer.StreamOptions()> <- Rf.dispose(Maybe<&2, Composer.StreamOptions()>, slot)
    previousError : List<&2, Ext.ExtensionError> <- Rf.dispose(List<&2, Ext.ExtensionError>, errors)
    return Unit{}

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case directory <> Nil{}: run(directory)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)
