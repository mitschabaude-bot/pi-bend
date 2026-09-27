import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/agent/src/agent.bend as AgentCore
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/event-stream.bend as Stream
import ../packages/ai/src/utils/model-api.bend as ModelApi
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/model-runtime.bend as Models
import ../packages/coding-agent/src/core/provider-composer.bend as Composer
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/session-persistence.bend as Sessions
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/core/compaction/compaction.bend as Compaction
import ../packages/coding-agent/src/core/compaction/utils.bend as CompactionUtils
import ../packages/coding-agent/src/core/extensions/context.bend as Ctx
import ../packages/coding-agent/src/core/extensions/loader.bend as Loader
import ../packages/coding-agent/src/core/extensions/runner.bend as Runner
import ../packages/coding-agent/src/core/extensions/types.bend as T
import ../packages/coding-agent/examples/extensions/custom-compaction.bend as CustomCompaction
import ./model-runtime-fixture.bend as Fixture

# upstream test/compaction-extensions-example.test.ts ("Documentation
# example"). Upstream mocks ctx.modelRegistry with find/complete stubs; here
# the example runs against a real model runtime whose "google" provider has
# an extension registration (registerProvider(name, config)) with a known API
# key and a streamSimple that records each request and answers "custom
# provider summary". The two type-check cases compile their handlers (the
# Bend checker is the type check) and register them through the loader.

def check(ok: Bool, +name: String, +detail: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  " ++ detail))(Unit{})

def Outcome() -> Data: Result<&2, &2, String, Unit>

def subscribedOk(result: Result<&2, &2, String, Loader.Unsubscribe>) -> Outcome():
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{Unit{}}

def handlerCount(runner: Runner.ExtensionRunner, +event: String) -> IO(Nat):
  do IO<Nat>:
    handlers : List<&2, Runner.Dispatch> <- Runner.snapshot(runner, event)
    return List.length(&2, Runner.Dispatch, handlers)

def emptyModels() -> IO(Models.ModelRuntime): Fixture.create(Nil{})

def loaded(extension: T.InlineExtension) -> IO(Runner.ExtensionRunner):
  do IO<Runner.ExtensionRunner>:
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, [extension])
    models : Models.ModelRuntime <- emptyModels()
    Runner.create(runtime, "/tmp/pi-compaction-example", models)

# "custom compaction example should type-check correctly"
# -------------------------------------------------------
# The example from extensions.md: everything the handler reads is on the
# event and the context, and it returns compaction content for the kept
# entry.

def userText(message: T.AgentMessage()) -> Maybe<&2, String>:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text}, _}}}: Some{"- " ++ String.take(text, 100n)}
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{_}, _}}}: Some{"- [complex]"}
    case _: None{}

def withLine(line: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match line:
    case None{}: rest
    case Some{text}: text <> rest

def userLines(messages: List<&2, T.AgentMessage()>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: withLine(userText(message), userLines(rest))

def documented(event: T.SessionBeforeCompactEvent, manager: Maybe<&2, Ctx.ReadonlySessionManager()>, models: Models.ModelRuntime) -> Maybe<&2, T.SessionBeforeCompactResult>:
  match event:
    case T.SessionBeforeCompactEvent{Compaction.CompactionPreparation{firstKeptEntryId, messagesToSummarize, turnPrefixMessages, isSplitTurn, tokensBefore, _, _, _}, branchEntries, _, _, _, _}:
      Some{T.SessionBeforeCompactResult{None{}, Some{Compaction.CompactionResult{"User requests:\n" ++ String.join(userLines(messagesToSummarize), "\n"), firstKeptEntryId, tokensBefore, None{}, None{}, None{}}}}}

def documentedHandler(unit: Unit, call: T.HandlerCall<T.SessionBeforeCompactEvent>) -> IO(Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>>):
  match call:
    case T.HandlerCall{event, +ctx}:
      do IO<Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>>>:
        # sessionManager, modelRegistry and model come from ctx
        manager : Maybe<&2, Ctx.ReadonlySessionManager()> <- Ctx.sessionManager(ctx)
        return Done{documented(event, manager, Ctx.modelRegistry(ctx))}

def exampleExtension(api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    handler : T.ExtensionHandler(T.SessionBeforeCompactEvent, T.SessionBeforeCompactResult) <- C.create(~Unit, ~T.HandlerCall<T.SessionBeforeCompactEvent>, ~Result<&2, &2, String, Maybe<&2, T.SessionBeforeCompactResult>>, ~documentedHandler, Unit{})
    result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, T.OnSessionBeforeCompact{handler})
    return subscribedOk(result)

def typeChecks() -> IO(Unit):
  do IO<Unit>:
    runner : Runner.ExtensionRunner <- loaded(T.InlineExtension{"example", exampleExtension, False{}})
    +count : Nat <- handlerCount(runner, "session_before_compact")
    check(Nat.is_eq(count, 1n), "custom compaction example should type-check correctly", Nat.show(count) ++ " handlers")

# "compact event should have correct fields"
# -----------------------------------------

def compactFields(unit: Unit, call: T.HandlerCall<T.SessionCompactEvent>) -> IO(Result<&2, &2, String, Maybe<&2, Unit>>):
  match call:
    case T.HandlerCall{T.SessionCompactEvent{S.Compaction{S.CompactionEntry{_, summary, _, tokensBefore, _, _, _, _}}, fromExtension, _, _}, _}: IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Done{None{}})
    case _: IO.pure(Result<&2, &2, String, Maybe<&2, Unit>>, Fail{"compactionEntry is not a compaction"})

def checkCompactEvent(api: T.ExtensionAPI) -> IO(Outcome()):
  do IO<Outcome()>:
    handler : T.ExtensionHandler(T.SessionCompactEvent, Unit) <- C.create(~Unit, ~T.HandlerCall<T.SessionCompactEvent>, ~Result<&2, &2, String, Maybe<&2, Unit>>, ~compactFields, Unit{})
    result : Result<&2, &2, String, Loader.Unsubscribe> <- Loader.on(api, T.OnSessionCompact{handler})
    return subscribedOk(result)

def compactEventFields() -> IO(Unit):
  do IO<Unit>:
    runner : Runner.ExtensionRunner <- loaded(T.InlineExtension{"compact-event", checkCompactEvent, False{}})
    +count : Nat <- handlerCount(runner, "session_compact")
    check(Nat.is_eq(count, 1n), "compact event should have correct fields", Nat.show(count) ++ " handlers")

# "custom compaction example dispatches through modelRegistry.complete"
# --------------------------------------------------------------------

# What the provider saw of one request.
type Seen is Data:
  Seen{provider: String, model: String, messages: Nat, maxTokens: Maybe<&2, F64>, apiKey: Maybe<&2, String>}

def usage() -> Ai.Usage:
  Ai.Usage{F.fromU32(1), F.fromU32(2), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(3), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}

def summaryReply(+model: Ai.Model<Ai.JsonValue>) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{[Ai.AssistantText{Ai.TextContent{"custom provider summary", None{}}}], ModelApi.name(ModelApi.modelApi(Ai.JsonValue, model)), Ai.modelProvider(model), Ai.modelId(model), None{}, None{}, None{}, None{}, usage(), Ai.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}

def seenOf(+model: Ai.Model<Ai.JsonValue>, context: Ai.TranscriptContext<V.Value, V.Value, Unit, Tools.ToolDetails>, options: Maybe<&2, Composer.StreamOptions()>) -> Seen:
  match context options:
    case Ai.TranscriptContext{messages} Some{Ai.SimpleStreamOptions{_, _, apiKey, _, _, _, _, _, _, _, _, _, _, maxTokens, _, _, _, _, _, _, _, _, _}}: Seen{Ai.modelProvider(model), Ai.modelId(model), List.length(&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>, messages), maxTokens, apiKey}
    case Ai.TranscriptContext{messages} None{}: Seen{Ai.modelProvider(model), Ai.modelId(model), List.length(&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>, messages), None{}, None{}}

def capture(seen: R.Ref<List<&2, Seen>>, request: Composer.StreamRequest()) -> IO(Composer.StreamOutput()):
  match request:
    case Agent.StreamInput{+model, context, options}:
      do IO<Composer.StreamOutput()>:
        R.modify(List<&2, Seen>, Unit, seen, earlier => (List.append(&2, Seen, earlier, [seenOf(model, context, options)]), Unit{}))
        +events : Stream.AssistantMessageEventStream(V.Value, Unit) <- Stream.createAssistantMessageEventStream(~V.Value, ~Unit)
        Stream.push(Ai.AssistantMessageEvent<V.Value, Unit>, Ai.AssistantMessage<V.Value, Unit>, events, Ai.StreamDone{Ai.DoneStop{}, summaryReply(model)})
        return Done{Agent.borrowedStream(Unit, Tools.ToolError, events)}

def geminiFlash() -> Ai.Model<Ai.JsonValue>:
  Ai.Model{"gemini-2.5-flash", "Gemini 2.5 Flash", Ai.GoogleGenerativeAiApi{}, "google", "https://generativelanguage.googleapis.com/v1beta", True{}, None{}, [Ai.InputText{}], None{}, Ai.ModelCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}}, None{}, F.fromU32(1000000), F.fromU32(65536), None{}, None{}, None{}}

def userMessage(text: String) -> T.AgentMessage():
  Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{[Ai.TextImageText{Ai.TextContent{text, None{}}}]}, F.fromU32(0)}}}

def preparation() -> Compaction.CompactionPreparation<Unit, Tools.ToolDetails, V.Value>:
  Compaction.CompactionPreparation{"entry-1", [userMessage("please remember this")], Nil{}, False{}, F.fromU32(42), None{}, CompactionUtils.createFileOps(), Compaction.DEFAULT_COMPACTION_SETTINGS()}

def shownMaybe(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "undefined"
    case Some{text}: text

def shownNumber(value: Maybe<&2, F64>) -> String:
  match value:
    case None{}: "undefined"
    case Some{number}: F64.show(number)

def shownSeen(seen: List<&2, Seen>) -> String:
  match seen:
    case Nil{}: ""
    case Seen{provider, model, messages, maxTokens, apiKey} <> rest: "(" ++ provider ++ "/" ++ model ++ " messages=" ++ Nat.show(messages) ++ " maxTokens=" ++ shownNumber(maxTokens) ++ " apiKey=" ++ shownMaybe(apiKey) ++ ")" ++ shownSeen(rest)

def shownResult(result: Maybe<&2, T.SessionBeforeCompactResult>) -> String:
  match result:
    case Some{T.SessionBeforeCompactResult{None{}, Some{Compaction.CompactionResult{summary, firstKept, tokensBefore, _, _, _}}}}: summary ++ " | " ++ firstKept ++ " | " ++ F64.show(tokensBefore)
    case _: "no compaction"

def dispatchesThroughComplete() -> IO(Unit):
  do IO<Unit>:
    +seen : R.Ref<List<&2, Seen>> <- R.new(List<&2, Seen>, Nil{})
    +models : Models.ModelRuntime <- Fixture.create([Fixture.Source{"google", "PI_EXAMPLE_UNSET_GEMINI_KEY", [geminiFlash()]}])
    stream : Composer.ProviderStream() <- C.create(~R.Ref<List<&2, Seen>>, ~Composer.StreamRequest(), ~Composer.StreamOutput(), ~capture, seen)
    registered : Outcome() <- Models.registerProvider(models, "google", Composer.ProviderConfigInput{None{}, None{}, Some{"registry-test-key"}, Some{Ai.GoogleGenerativeAiApi{}}, Some{stream}, None{}, None{}, None{}})
    +runtime : T.ExtensionRuntime() <- Loader.createExtensionRuntime()
    errors : List<&2, T.LoadError> <- Loader.loadExtensionFactories(runtime, [T.InlineExtension{"custom-compaction", CustomCompaction.customCompaction, False{}}])
    +runner : Runner.ExtensionRunner <- Runner.create(runtime, "/tmp/pi-compaction-example", models)
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +result : Maybe<&2, T.SessionBeforeCompactResult> <- Runner.emitSessionBeforeCompact(runner, T.SessionBeforeCompactEvent{preparation(), Nil{}, None{}, T.ManualReason{}, False{}, Abort.signal(Unit, controller)})
    +requests : List<&2, Seen> <- R.read(List<&2, Seen>, seen)
    # complete(model, {messages}, {maxTokens: 8192}) and no apiKey of the
    # example's own: the request carries the registry's key.
    check(String.eq(shownSeen(requests), "(google/gemini-2.5-flash messages=1 maxTokens=8192 apiKey=registry-test-key)") && String.eq(shownResult(result), "custom provider summary | entry-1 | 42"), "custom compaction example dispatches through modelRegistry.complete", shownSeen(requests) ++ " -> " ++ shownResult(result))

def main() -> IO(Unit):
  do IO<Unit>:
    typeChecks()
    dispatchesThroughComplete()
    compactEventFields()
