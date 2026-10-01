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
import ../../ai/src/utils/event-stream.bend as Events
import ../../ai/src/utils/uuid.bend as Uuid
import ../../runtime/src/date.bend as Date
import ../src/core/session-manager.bend as Manager
import ../src/core/session-persistence.bend as Persistence
import ../src/core/cache-warmer.bend as Warmer
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
import ../src/core/extensions/context.bend as Ctx
import ../../ai/src/utils/transcript.bend as Transcript
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

# Port of all nine sdk-stream-options.test.ts cases. Forwarding uses an
# injected provider through the SDK Agent stream; cache warming runs a
# completed prompt through AgentSession. No external HTTP is required.
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

def provider(models: List<&2, Ai.Model<Ai.JsonValue>>) -> IO(AiModels.Provider):
  do IO<AiModels.Provider>:
    key : Auth.ApiKeyAuth <- AuthHelpers.envApiKeyAuth("Capture key", ["PI_SDK_STREAM_UNUSED"])
    return AiModels.Provider{"capture-provider", "Capture Provider", "https://capture.invalid/v1", Auth.ProviderAuth{Some{key}, None{}}, models, AiModels.ApiStreams{}, None{}, None{}}

def capture(slot: Rf.Ref<Maybe<&2, Composer.StreamOptions()>>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{_, _, options}:
      do IO<Composer.StreamOutput()>:
        Rf.write(Maybe<&2, Composer.StreamOptions()>, slot, Composer.simpleOptions(options))
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

def warmModel() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"capture-model", "Capture Model", Ai.AnthropicMessagesApi{}, "capture-provider", "https://capture.invalid/v1", False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{number(10), number(50), F.divide(number(1), number(4)), F.divide(number(25), number(2)), None{}}, Some{Ai.ModelPromptCache{Some{number(300)}, None{}}}, number(128000), number(4096), None{}, None{}, None{}}

def warmUsage() -> Ai.Usage:
  Ai.Usage{zero(), zero(), number(100000), zero(), None{}, None{}, number(100000), Ai.UsageCost{zero(), zero(), zero(), zero(), zero()}}

def warmReply(now: F64) -> Ai.AssistantMessage<V.Value, V.Value>:
  Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{"ok", None{}}}], "anthropic-messages", "capture-provider", "capture-model", None{}, None{}, None{}, None{}, warmUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, now}

def releaseCompleted(+events: Events.AssistantMessageEventStream(V.Value, V.Value)) -> IO(Result<&2, &2, Tools.ToolError, Unit>):
  do IO<Result<&2, &2, Tools.ToolError, Unit>>:
    Events.disposeAssistantMessageEventStream(V.Value, V.Value, events)
    return Done{Unit{}}

def completeRequest(calls: Rf.Ref<Nat>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  do IO<Composer.StreamOutput()>:
    Rf.modify(Nat, Unit, calls, count => (count + 1n, Unit{}))
    now : F64 <- Date.now()
    +events : Events.AssistantMessageEventStream(V.Value, V.Value) <- Events.createAssistantMessageEventStream(~V.Value, ~V.Value)
    Events.end(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Some{warmReply(now)})
    return Done{AgentTypes.StreamLease{events, releaseCompleted(events)}}

def requiredRecord(result: Persistence.Outcome(Session.Session())) -> IO(Session.Session()):
  match result:
    case Done{record}: IO.pure(Session.Session(), record)
    case Fail{error}: IO.die(Session.Session(), 1, Persistence.message(error))

def requiredState(result: Result<&2, &2, Manager.Error, Session.State()>) -> IO(Session.State()):
  match result:
    case Done{state}: IO.pure(Session.State(), state)
    case Fail{_}: IO.die(Session.State(), 1, "invalid restored cache-warming fixture")

def warmStamp(id: String, +now: F64) -> Manager.EntryStamp:
  Manager.EntryStamp{id, Maybe.default(&2, String, Date.formatIso(now), "1970-01-01T00:00:00.000Z")}

def populateWarmRecord(restored: Bool, record: Session.Session(), +now: F64) -> IO(Session.Session()):
  match restored record:
    case False{} record: IO.pure(Session.Session(), record)
    case True{} Persistence.Session{state, cwd, directory, file, persist, flushed, ids}:
      do IO<Session.Session()>:
        modelState : Session.State() <- requiredState(Manager.appendModelChange(V.Value, Tools.ToolDetails, V.Value, state, warmStamp("model", F.subtract(now, number(61000))), "capture-provider", "capture-model"))
        thinking : Session.State() <- requiredState(Manager.appendThinkingLevelChange(V.Value, Tools.ToolDetails, V.Value, modelState, warmStamp("thinking", F.subtract(now, number(60500))), "off"))
        user : Session.State() <- requiredState(Manager.appendMessage(V.Value, Tools.ToolDetails, V.Value, thinking, warmStamp("user", F.subtract(now, number(60000))), AgentTypes.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"test"}, F.subtract(now, number(60000))}}}))
        assistant : Session.State() <- requiredState(Manager.appendMessage(V.Value, Tools.ToolDetails, V.Value, user, warmStamp("assistant", F.subtract(now, number(59000))), AgentTypes.LlmMessage{Ai.Assistant{warmReply(F.subtract(now, number(59000)))}}))
        usage : Session.State() <- requiredState(Manager.appendUsage(V.Value, Tools.ToolDetails, V.Value, assistant, warmStamp("warm", F.subtract(now, number(58000))), "cache_warm", "capture-provider", "capture-model", warmUsage(), None{}))
        return Persistence.Session{usage, cwd, directory, file, persist, flushed, ids}

def scheduled(status: Warmer.CacheWarmingStatus, now: F64) -> Bool:
  match status:
    case Warmer.CacheWarmingStatus{Warmer.Scheduled{}, _, Some{next}, _, _}: F64.is_gt(next, now)
    case _: False{}

def inactive(status: Warmer.CacheWarmingStatus, +reason: String) -> Bool:
  match status:
    case Warmer.CacheWarmingStatus{Warmer.Inactive{}, Some{found}, None{}, _, _}: String.eq(found, reason)
    case _: False{}

def messagesOf(state: Session.AgentState()) -> List<&2, Session.Message()>:
  match state:
    case AgentTypes.AgentState{_, _, _, messages, _, _, _, _}: messages

def checkWarming(restored: Bool, +live: Session.AgentSession, calls: Rf.Ref<Nat>) -> IO(Unit):
  match restored:
    case True{}:
      do IO<Unit>:
        count : Nat <- Rf.read(Nat, calls)
        status : Warmer.CacheWarmingStatus <- Session.cacheWarmingStatus(live)
        check(Nat.is_eq(count, 0n) && inactive(status, "waiting for first request"), "waits for the next request instead of restoring cache warming")
    case False{}:
      do IO<Unit>:
        prompted : Result<&2, &2, String, Unit> <- Session.prompt(live, "test", Nil{}, None{})
        registration(prompted)
        +now : F64 <- Date.now()
        status : Warmer.CacheWarmingStatus <- Session.cacheWarmingStatus(live)
        Bool.pick(Unit -> IO(Unit), scheduled(status, now), _ => IO.pure(Unit, Unit{}), _ => IO.die(Unit, 1, "completed request did not schedule cache warming"))(Unit{})
        state : Session.AgentState() <- Agent.state(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live))
        +messages : List<&2, Session.Message()> = messagesOf(state)
        Agent.replaceMessages(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live), messages)
        Agent.setModel(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live), warmModel())
        same : Warmer.CacheWarmingStatus <- Session.cacheWarmingStatus(live)
        Bool.pick(Unit -> IO(Unit), scheduled(same, now), _ => IO.pure(Unit, Unit{}), _ => IO.die(Unit, 1, "equivalent native snapshots invalidated warming"))(Unit{})
        Agent.replaceMessages(V.Value, Runtime.Details(), Runtime.Custom(), Runtime.Error(), Unit, Session.agentOf(live), List.drop(&2, Session.Message(), messages, 1n))
        changed : Warmer.CacheWarmingStatus <- Session.cacheWarmingStatus(live)
        check(inactive(changed, "conversation context changed"), "schedules cache warming after a completed session request")

def finishWarm(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, restored: Bool, calls: Rf.Ref<Nat>) -> IO(Unit):
  match pair:
    case Tuple{owner, live}:
      do IO<Unit>:
        checkWarming(restored, live, calls)
        Sdk.dispose(owner)

def checkedWarmSession(result: Sdk.Outcome(), restored: Bool, calls: Rf.Ref<Nat>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{owner}: finishWarm(Sdk.sessionOf(owner), restored, calls)

def disposeIds(ids: Uuid.Generator) -> IO(Unit):
  match ids:
    case Uuid.Generator{state}:
      do IO<Unit>:
        previous : Uuid.State <- Rf.dispose(Uuid.State, state)
        return Unit{}

def cacheWarmingCase(+directory: String, +restored: Bool) -> IO(Unit):
  do IO<Unit>:
    wrote : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(FS.child(directory, "settings.json"), "{\"cacheWarming\":\"idle\"}")
    written(wrote)
    +calls : Rf.Ref<Nat> <- Rf.new(Nat, 0n)
    +stream : Composer.ProviderStream() <- C.create(~Rf.Ref<Nat>, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~completeRequest, calls)
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    context : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    native : AiModels.Provider <- provider([warmModel()])
    registered : Result<&2, &2, String, Unit> <- Models.registerNativeProviderStream(models, native, Some{stream})
    registration(registered)
    authorized : Result<&2, &2, Resolve.ModelsError, Unit> <- Models.setRuntimeApiKey(models, "capture-provider", "test-key", None{})
    authorization(authorized)
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    settings : Settings.SettingsManager = settingsOf(pair)
    +ids : Uuid.Generator <- Uuid.generator()
    createdRecord : Persistence.Outcome(Session.Session()) <- Session.memorySession(ids, directory, Persistence.noOptions())
    blank : Session.Session() <- requiredRecord(createdRecord)
    now : F64 <- Date.now()
    record : Session.Session() <- populateWarmRecord(restored, blank, now)
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, Some{models}, Some{warmModel()}, None{}, Nil{}, Some{Runtime.NoToolsAll{}}, None{}, None{}, None{}, Some{record}, Some{settings}, Nil{}, None{}})
    checkedWarmSession(created, restored, calls)
    Models.dispose(models)
    Auth.disposeStore(store)
    C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), stream)
    count : Nat <- Rf.dispose(Nat, calls)
    disposeIds(ids)


# Regression 8964: the provider and command are registered by distinct
# extensions. Consume the real stream through the command's bound registry.
type ExtensionStreamEvidence is Data:
  ExtensionStreamEvidence{options: Rf.Ref<Maybe<&2, Composer.RequestOptions>>, text: Rf.Ref<String>, reply: Rf.Ref<Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>>, raw: Bool}

def extensionReply() -> Ai.AssistantMessage<V.Value, V.Value>:
  Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{"custom provider response", None{}}}], "issue-8964-extension-api", "extension-provider", "custom-model", None{}, None{}, None{}, None{}, warmUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, zero()}

def extensionStream(slot: Rf.Ref<Maybe<&2, Composer.RequestOptions>>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  match request:
    case AgentTypes.StreamInput{_, _, options}:
      do IO<Composer.StreamOutput()>:
        Rf.write(Maybe<&2, Composer.RequestOptions>, slot, options)
        +events : Events.AssistantMessageEventStream(V.Value, V.Value) <- Events.createAssistantMessageEventStream(~V.Value, ~V.Value)
        Events.push(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Ai.TextDelta{zero(), "custom provider response", extensionReply()})
        Events.push(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events, Ai.StreamDone{Ai.DoneStop{}, extensionReply()})
        return Done{AgentTypes.StreamLease{events, releaseCompleted(events)}}

def providerFactory(stream: Composer.ProviderStream(), api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    definition : Composer.ProviderModelConfig = Composer.ProviderModelConfig{"custom-model", "Custom model", None{}, None{}, False{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{zero(), zero(), zero(), zero(), None{}}, None{}, number(128000), number(4096), None{}, None{}, None{}}
    Loader.registerProviderConfig(api, "extension-provider", Composer.ProviderConfigInput{None{}, Some{"https://extension.invalid"}, Some{"extension-key"}, Some{Ai.CustomModelApi{"issue-8964-extension-api"}}, Some{stream}, None{}, None{}, Some{[definition]}})

def extensionDelta(event: Ai.AssistantMessageEvent<V.Value, V.Value>) -> String:
  match event:
    case Ai.TextDelta{_, text, _}: text
    case _: ""

@unsafe def drainExtension(next: Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>>, +cursor: Events.Iterator<Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>>, text: String) -> IO(String):
  match next:
    case Events.End{}: IO.pure(String, text)
    case Events.Yield{event}:
      do IO<String>:
        next : Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)
        drainExtension(next, cursor, text ++ extensionDelta(event))

def extensionReleased(result: Result<&2, &2, Tools.ToolError, Unit>) -> Result<&2, &2, String, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{Tools.errorMessage(error)}

def consumeExtension(evidence: ExtensionStreamEvidence, output: Composer.StreamOutput()) -> IO(Result<&2, &2, String, Unit>):
  match evidence output:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{Tools.errorMessage(error)})
    case ExtensionStreamEvidence{_, text, reply, _} Done{AgentTypes.StreamLease{+events, release}}:
      do IO<Result<&2, &2, String, Unit>>:
        +cursor : Events.Iterator<Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>> <- Events.iterator(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events)
        first : Events.Iteration<Ai.AssistantMessageEvent<V.Value, V.Value>> <- Events.nextValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)
        content : String <- drainExtension(first, cursor, "")
        result : Ai.AssistantMessage<V.Value, V.Value> <- Events.resultValue(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, events)
        Rf.write(String, text, content)
        Rf.write(Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>, reply, Some{result})
        Events.disposeIterator(Ai.AssistantMessageEvent<V.Value, V.Value>, Ai.AssistantMessage<V.Value, V.Value>, cursor)
        released : Result<&2, &2, Tools.ToolError, Unit> <- release
        return extensionReleased(released)

def selectedExtensionStream(raw: Bool, registry: Models.ModelRuntime, model: Models.Model(), context: Ai.TranscriptContext<V.Value, V.Value, V.Value, Tools.ToolDetails>) -> IO(Composer.StreamOutput()):
  match raw:
    case True{}: Models.stream(registry, AgentTypes.StreamInput{model, context, None{}}, Models.noTransforms())
    case False{}: Models.streamSimple(registry, AgentTypes.StreamInput{model, context, None{}}, Models.noTransforms())

def extensionIsRaw(evidence: ExtensionStreamEvidence) -> Bool:
  match evidence: case ExtensionStreamEvidence{_, _, _, raw}: raw

def streamRegisteredExtension(+registry: Models.ModelRuntime, +evidence: ExtensionStreamEvidence, found: Maybe<&2, Models.Model()>) -> IO(Result<&2, &2, String, Unit>):
  match found:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{"registered model missing"})
    case Some{selected}:
      do IO<Result<&2, &2, String, Unit>>:
        transcript : Ai.Context<V.Value, V.Value, V.Value, Tools.ToolDetails> = Ai.Context{None{}, [Ai.User{Ai.UserMessage{Ai.UserText{"Hello"}, zero()}}], None{}}
        output : Composer.StreamOutput() <- selectedExtensionStream(extensionIsRaw(evidence), registry, selected, Transcript.normalizeContext(V.Value, V.Value, V.Value, Tools.ToolDetails, transcript))
        consumeExtension(evidence, output)

def streamExtension(evidence: ExtensionStreamEvidence, call: Ext.CommandCall) -> IO(Result<&2, &2, String, Unit>):
  match call:
    case Ext.CommandCall{_, context}:
      do IO<Result<&2, &2, String, Unit>>:
        +registry : Models.ModelRuntime = Ctx.modelRegistry(Ctx.commandContext(context))
        found : Maybe<&2, Models.Model()> <- Models.getModel(registry, "extension-provider", "custom-model")
        streamRegisteredExtension(registry, evidence, found)

def commandFactory(evidence: ExtensionStreamEvidence, api: Ext.ExtensionAPI) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    handler : Ext.CommandHandler() <- C.create(~ExtensionStreamEvidence, ~Ext.CommandCall, ~Result<&2, &2, String, Unit>, ~streamExtension, evidence)
    Loader.registerCommand(api, "stream-custom", Ext.CommandOptions{Some{"Stream custom provider"}, None{}, handler})

def extensionResult(reply: Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>) -> Bool:
  match reply:
    case Some{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"custom provider response", _}} <> Nil{}, _, _, _, _, _, _, _, _, Ai.Stop{}, _, _, _, _, _}}: True{}
    case _: False{}

def extensionOptionsMatch(captured: Maybe<&2, Composer.RequestOptions>, raw: Bool) -> Bool:
  match captured raw:
    case Some{Composer.SimpleOptions{Ai.SimpleStreamOptions{_, _, Some{"extension-key"}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}} False{}: True{}
    case Some{Composer.RawOptions{Composer.CommonOptions{Ai.StreamOptions{_, _, Some{"extension-key"}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}} True{}: True{}
    case _ _: False{}

def checkExtensionSession(pair: Sdk.CreateAgentSessionResult & Session.AgentSession, evidence: ExtensionStreamEvidence, isolated: Models.ModelRuntime, before: Maybe<&2, Models.Model()>) -> IO(Unit):
  match pair evidence:
    case Tuple{owner, +live} ExtensionStreamEvidence{slot, text, reply, +raw}:
      do IO<Unit>:
        prompted : Result<&2, &2, String, Unit> <- Session.prompt(live, "/stream-custom", Nil{}, None{})
        after : Maybe<&2, Models.Model()> <- Models.getModel(isolated, "extension-provider", "custom-model")
        captured : Maybe<&2, Composer.RequestOptions> <- Rf.read(Maybe<&2, Composer.RequestOptions>, slot)
        content : String <- Rf.read(String, text)
        result : Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>> <- Rf.read(Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>, reply)
        check(Maybe.is_none(&2, Models.Model(), before) && Maybe.is_none(&2, Models.Model(), after) && Result.is_done(&2, &2, String, Unit, prompted) && extensionOptionsMatch(captured, raw) && String.eq(content, "custom provider response") && extensionResult(result), Bool.pick(String, raw, "allows an extension command to use ctx.modelRegistry.stream", "allows an extension command to use ctx.modelRegistry.streamSimple"))
        Sdk.dispose(owner)

def checkExtensionOutcome(result: Sdk.Outcome(), evidence: ExtensionStreamEvidence, isolated: Models.ModelRuntime, before: Maybe<&2, Models.Model()>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{owner}: checkExtensionSession(Sdk.sessionOf(owner), evidence, isolated, before)

def extensionStreamingCase(+directory: String, raw: Bool) -> IO(Unit):
  do IO<Unit>:
    +slot : Rf.Ref<Maybe<&2, Composer.RequestOptions>> <- Rf.new(Maybe<&2, Composer.RequestOptions>, None{})
    +text : Rf.Ref<String> <- Rf.new(String, "")
    +reply : Rf.Ref<Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>> <- Rf.new(Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>, None{})
    +evidence : ExtensionStreamEvidence = ExtensionStreamEvidence{slot, text, reply, raw}
    +stream : Composer.ProviderStream() <- C.create(~Rf.Ref<Maybe<&2, Composer.RequestOptions>>, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~extensionStream, slot)
    first : Ext.ExtensionFactory() <- C.create(~Composer.ProviderStream(), ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~providerFactory, stream)
    second : Ext.ExtensionFactory() <- C.create(~ExtensionStreamEvidence, ~Ext.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~commandFactory, evidence)
    +store : Auth.CredentialStore <- Credentials.inMemoryCredentialStore()
    +context : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +models : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, context)
    isolatedContext : Auth.AuthContext <- AuthContext.defaultProviderAuthContext()
    +isolated : Models.ModelRuntime <- Models.fromProviders(Nil{}, store, isolatedContext)
    before : Maybe<&2, Models.Model()> <- Models.getModel(isolated, "extension-provider", "custom-model")
    pair : Settings.FileSettingsStorage & Settings.SettingsManager <- Settings.create(directory, directory, Settings.options())
    +settings : Settings.SettingsManager = settingsOf(pair)
    +loader : Resources.DefaultResourceLoader <- Resources.createDefaultResourceLoader(Paths.Environment{directory, directory, Runtime.urlContext()}, Resources.defaultResourceLoaderOptions(directory, directory, settings), [Ext.InlineExtension{"provider", first, False{}}, Ext.InlineExtension{"command", second, False{}}])
    Resources.reload(Resources.loaderOf(loader), Resources.ResourceLoaderReloadOptions{None{}})
    created : Sdk.Outcome() <- Sdk.createAgentSession(Sdk.CreateAgentSessionOptions{Some{directory}, Some{directory}, Some{models}, None{}, None{}, Nil{}, None{}, None{}, None{}, Some{Resources.loaderOf(loader)}, None{}, Some{settings}, Nil{}, None{}})
    checkExtensionOutcome(created, evidence, isolated, before)
    Resources.disposeDefaultResourceLoader(loader)
    Models.dispose(models)
    Models.dispose(isolated)
    Auth.disposeStore(store)
    C.dispose(Composer.StreamRequest(), Composer.StreamOutput(), stream)
    oldOptions : Maybe<&2, Composer.RequestOptions> <- Rf.dispose(Maybe<&2, Composer.RequestOptions>, slot)
    oldText : String <- Rf.dispose(String, text)
    oldReply : Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>> <- Rf.dispose(Maybe<&2, Ai.AssistantMessage<V.Value, V.Value>>, reply)
    return Unit{}

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
    native : AiModels.Provider <- provider([codex, completions])
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
    cacheWarmingCase(directory, False{})
    cacheWarmingCase(directory, True{})
    extensionStreamingCase(FS.child(directory, "extension-streaming"), False{})
    extensionStreamingCase(FS.child(directory, "extension-raw-streaming"), True{})

def runArgs(args: List<String>) -> IO(Unit):
  match args:
    case directory <> Nil{}: run(directory)
    case _: IO.die(Unit, 1, "expected isolated directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    runArgs(args)
