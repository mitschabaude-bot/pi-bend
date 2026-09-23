import Base
import ../src/agent-loop.bend as W
import ../src/agent-loop.bend as Entry
import ../src/stream-fn.bend as Defaults
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as S
import ../../ai/test/model-types.bend as Model
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/u64.bend as Bits
import ./main-loop.bend as H
import ./validated-tool-execution.bend as Validation
import ./message-events.bend as Test
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/fetch.bend as Fetch

type Provider is Data:
  Provider{reply: String, expectedInput: String, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}

def convert(unused: Unit, messages: Validation.Messages()) -> IO(Validation.Converted()):
  IO.pure(Validation.Converted(), Done{H.converted(messages)})

def request(messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>, expected: String) -> Bool:
  match messages:
    case Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> Nil{}: String.eq(text, expected)
    case _: False{}

def provider(environment: Provider, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment input:
    case Provider{reply, expectedInput, calls, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        Test.assertion(request(messages, expectedInput), "provider receives the converted transcript only")
        ignored : U32 <- H.bump(calls)
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text(reply), Ai.Stop{})})
        return Done{T.borrowedStream(Unit, String, stream)}

def user() -> T.AgentMessage<Unit, String, String>:
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"Hello"}, F.fromU32(0)}}}

def context(mode: U32) -> Validation.Context():
  match mode:
    case 1: T.AgentContext{user() <> Nil{}, Some{Nil{}}}
    case 2: T.AgentContext{T.CustomMessage{"Hook content"} <> Nil{}, Some{Nil{}}}
    case _: T.AgentContext{Nil{}, Some{Nil{}}}

def verify(mode: U32, outcome: H.Outcome(), reply: String) -> IO(Unit):
  match mode outcome:
    case 3 Fail{error}: Test.assertion(String.eq(error, "Cannot continue: no messages in context"), "original continuation error")
    case 0 Done{T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{prompt}, _}}} <> T.LlmMessage{Ai.Assistant{message}} <> Nil{}}:
      Test.assertion(String.eq(prompt, "Hello") && String.eq(H.assistantName(message), "assistant:" ++ reply), "user and assistant message roles and ordered history")
    case 1 Done{T.LlmMessage{Ai.Assistant{message}} <> Nil{}}:
      Test.assertion(String.eq(H.assistantName(message), "assistant:" ++ reply), "continuation returns only the new assistant")
    case 2 Done{T.LlmMessage{Ai.Assistant{message}} <> Nil{}}:
      Test.assertion(String.eq(H.assistantName(message), "assistant:" ++ reply), "custom continuation returns only the new assistant")
    case _ _: Test.assertion(False{}, "upstream message role/history assertion")

def run(mode: U32, config: Validation.Config(), options: H.StreamOptions()) -> IO(Result<&2, &2, String, H.StreamRun()>):
  match mode:
    case 0:
      do IO<Result<&2, &2, String, H.StreamRun()>>:
        run : H.StreamRun() <- W.agentLoop(~Unit, ~String, ~String, ~String, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, user() <> Nil{}, context(0), config, options)
        return Done{run}
    case other: W.agentLoopContinue(~Unit, ~String, ~String, ~String, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, context(other), config, options)

def inspect(+mode: U32, created: Result<&2, &2, String, H.StreamRun()>, reply: String, expectedEvents: String) -> IO(Unit):
  match created:
    case Fail{error}: verify(mode, Fail{error}, reply)
    case Done{+run}:
      do IO<Unit>:
        outcome : H.Outcome() <- W.streamOutcome(Unit, String, String, String, run)
        verify(mode, outcome, reply)
        +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(Unit, String, String, String, run)
        events : List<&2, String> <- H.collectEvents(iterator, Nil{}, None{})
        Test.assertion(String.eq(String.join(events, "|"), expectedEvents), "original event types and absence of old user-message events")
        S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
        W.disposeStreamRun(Unit, String, String, String, run)

def selected(useDefault: Bool, registry: H.Registry(), provider: H.ProviderFunction()) -> H.Selection():
  match useDefault:
    case True{}: Defaults.Fallback{registry}
    case False{}: Defaults.Explicit{provider}

def scenario(name: String, +mode: U32, useDefault: Bool, +reply: String, expectedEvents: String) -> IO(Unit):
  do IO<Unit>:
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +providerCallback : H.ProviderFunction() <- C.create(~Provider, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, Provider{reply, Bool.pick(String, U32.is_eq(mode, 2), "Hook content", "Hello"), calls, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~Unit, ~Validation.Messages(), ~Validation.Converted(), ~convert, Unit{})
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~H.abort, Unit{})
    +registry : H.Registry() <- Defaults.create(Unit, String, Validation.Config(), String)
    Defaults.setDefaultStreamFn(Unit, String, Validation.Config(), String, registry, Some{providerCallback})
    config : Validation.Config() = T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"original"}, None{}), converter, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
    created : Result<&2, &2, String, H.StreamRun()> <- run(mode, config, W.Options{None{}, validator, aborted, "empty", selected(useDefault, registry, providerCallback)})
    inspect(mode, created, reply, expectedEvents)
    count : U32 <- R.read(U32, calls)
    Test.assertion(U32.is_eq(count, Bool.pick(U32, U32.is_eq(mode, 3), 0, 1)), "default provider called once; invalid continuation never calls it")
    Defaults.setDefaultStreamFn(Unit, String, Validation.Config(), String, registry, None{})
    Defaults.dispose(Unit, String, Validation.Config(), String, registry)
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    discarded : U32 <- R.dispose(U32, calls)
    IO.print("PASS " ++ name)

def TransformInput() -> Data: T.TransformContextInput<Validation.Messages()>
def TransformResult() -> Data: Result<&2, &2, String, Validation.Messages()>

type TranscriptFixture is Data:
  TranscriptFixture{mode: U32, log: H.Log(), streams: R.Ref<List<&2, H.StreamValue()>>}

def promptText(value: String) -> T.AgentMessage<Unit, String, String>:
  T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{value}, F.fromU32(0)}}}

def transcriptPrompts(mode: U32) -> Validation.Messages():
  match mode:
    case 0: T.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"Transcript prompt"}, None{}, Some{Nil{}}, None{}, F.fromU32(1)}}} <> user() <> Nil{}
    case 1: user() <> Nil{}
    case _: promptText("new message") <> Nil{}

def transcriptContext(mode: U32) -> Validation.Context():
  match mode:
    case 0: T.AgentContext{Nil{}, Some{Nil{}}}
    case 1: T.AgentContext{T.CustomMessage{"This is a notification"} <> Nil{}, Some{Nil{}}}
    case _: T.AgentContext{promptText("old message 1") <> T.LlmMessage{Ai.Assistant{H.assistant(H.text("old response 1"), Ai.Stop{})}} <> promptText("old message 2") <> T.LlmMessage{Ai.Assistant{H.assistant(H.text("old response 2"), Ai.Stop{})}} <> Nil{}, Some{Nil{}}}

def filterNotifications(messages: Validation.Messages()) -> List<&2, Ai.Message<V.Value, V.Value, Unit, String>>:
  match messages:
    case Nil{}: Nil{}
    case T.CustomMessage{_} <> rest: filterNotifications(rest)
    case T.LlmMessage{message} <> rest: message <> filterNotifications(rest)

def lastTwo(messages: Validation.Messages()) -> Validation.Messages():
  match messages:
    case first <> second <> Nil{}: first <> second <> Nil{}
    case first <> Nil{}: first <> Nil{}
    case _ <> rest: lastTwo(rest)
    case Nil{}: Nil{}

def transcriptTransform(recording: H.Log(), input: TransformInput()) -> IO(TransformResult()):
  match input:
    case T.TransformContextInput{+messages, _}:
      do IO<TransformResult()>:
        Test.assertion(String.eq(H.names(messages), "old message 1|assistant:old response 1|old message 2|assistant:old response 2|new message|"), "transform sees original history followed by prompt")
        H.log(recording, "transform")
        +pruned : Validation.Messages() = lastTwo(messages)
        Test.assertion(String.eq(H.names(pruned), "assistant:old response 2|new message|"), "transform retains last two messages")
        return Done{pruned}

def transcriptConvert(environment: TranscriptFixture, messages: Validation.Messages()) -> IO(Validation.Converted()):
  match environment:
    case TranscriptFixture{mode, recording, _}:
      +messages = messages
      do IO<Validation.Converted()>:
        H.log(recording, "convert:" ++ H.names(messages))
        return Done{filterNotifications(messages)}

def transcriptMatches(mode: U32, messages: List<&2, Ai.Message<V.Value, V.Value, Unit, String>>) -> Bool:
  match mode messages:
    case 0 Ai.System{Ai.SystemMessage{Ai.SystemText{content}, None{}, Some{Nil{}}, None{}, timestamp}} <> Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> Nil{}:
      String.eq(content, "Transcript prompt") && String.eq(text, "Hello") && Bits.equal(F.toBits(timestamp), F.toBits(F.fromU32(1)))
    case 1 Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> Nil{}: String.eq(text, "Hello")
    case 2 Ai.Assistant{message} <> Ai.User{Ai.UserMessage{Ai.UserText{text}, _}} <> Nil{}:
      String.eq(H.assistantName(message), "assistant:old response 2") && String.eq(text, "new message")
    case _ _: False{}

def transcriptProvider(environment: TranscriptFixture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match environment input:
    case TranscriptFixture{mode, recording, streams} T.StreamInput{_, Ai.TranscriptContext{messages}, _}:
      do IO<H.ProviderOutput()>:
        Test.assertion(transcriptMatches(mode, messages), "provider receives exact converted transcript and preserved system fields")
        H.log(recording, "provider")
        +stream : H.StreamValue() <- S.createAssistantMessageEventStream(~V.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, previous => (stream <> previous, Unit{}))
        S.push(Ai.AssistantMessageEvent<V.Value, Unit>, H.Assistant(), stream, Ai.StreamDone{Ai.DoneStop{}, H.assistant(H.text("Response"), Ai.Stop{})})
        return Done{T.borrowedStream(Unit, String, stream)}

def transcriptOutcome(+mode: U32, outcome: H.Outcome()) -> IO(Unit):
  match outcome:
    case Fail{_}: Test.assertion(False{}, "transcript loop succeeds")
    case Done{messages}:
      Test.assertion(String.eq(H.names(messages), Bool.pick(String, U32.is_eq(mode, 0), "system|Hello|assistant:Response|", Bool.pick(String, U32.is_eq(mode, 1), "Hello|assistant:Response|", "new message|assistant:Response|"))), "transformation changes provider input without replacing generated history")

def transcriptScenario(name: String, +mode: U32, expectedLog: String) -> IO(Unit):
  do IO<Unit>:
    +recording : H.Log() <- R.new(List<&2, String>, Nil{})
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +providerCallback : H.ProviderFunction() <- C.create(~TranscriptFixture, ~H.ProviderInput(), ~H.ProviderOutput(), ~transcriptProvider, TranscriptFixture{mode, recording, streams})
    +converter : C.Callback<Validation.Messages(), Validation.Converted()> <- C.create(~TranscriptFixture, ~Validation.Messages(), ~Validation.Converted(), ~transcriptConvert, TranscriptFixture{mode, recording, streams})
    +transformer : C.Callback<TransformInput(), TransformResult()> <- C.create(~H.Log(), ~TransformInput(), ~TransformResult(), ~transcriptTransform, recording)
    +validator : C.Callback<Validation.Input(), Validation.Checked()> <- C.create(~Unit, ~Validation.Input(), ~Validation.Checked(), ~Validation.validate, Unit{})
    +aborted : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~Unit, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~H.abort, Unit{})
    config : Validation.Config() = T.AgentLoopConfig{Ai.emptySimpleStreamOptions(Ai.JsonValue, Abort.AbortSignal<Unit>, Unit, Fetch.Fetch(Unit), String), Model.model(Ai.CustomModelApi{"original"}, None{}), converter, Bool.pick(Maybe<&2, C.Callback<TransformInput(), TransformResult()>>, U32.is_eq(mode, 2), Some{transformer}, None{}), None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
    +run : H.StreamRun() <- W.agentLoop(~Unit, ~String, ~String, ~String, ~Unit, ~H.render, ~H.declarationError, ~Defaults.errorMessage, ~Entry.errorMessage, transcriptPrompts(mode), transcriptContext(mode), config, W.Options{None{}, validator, aborted, "empty", Defaults.Explicit{providerCallback}})
    outcome : H.Outcome() <- W.streamOutcome(Unit, String, String, String, run)
    transcriptOutcome(mode, outcome)
    +iterator : S.Iterator<Validation.EventValue(), H.Outcome()> <- W.iterator(Unit, String, String, String, run)
    events : List<&2, String> <- H.collectEvents(iterator, Nil{}, None{})
    S.disposeIterator(Validation.EventValue(), H.Outcome(), iterator)
    W.disposeStreamRun(Unit, String, String, String, run)
    entries : List<&2, String> <- R.dispose(List<&2, String>, recording)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, entries), ";"), expectedLog), "transform precedes conversion; converter receives expected messages; provider runs once")
    C.dispose(H.ProviderInput(), H.ProviderOutput(), providerCallback)
    C.dispose(Validation.Messages(), Validation.Converted(), converter)
    C.dispose(TransformInput(), TransformResult(), transformer)
    C.dispose(Validation.Input(), Validation.Checked(), validator)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, aborted)
    owned : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(owned)
    IO.print("PASS " ++ name)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario("uses the configured default when a legacy caller omits streamFn", 0, True{}, "fallback", "agent_start|turn_start|message_start:Hello|message_end:Hello|message_start:assistant:fallback|message_end:assistant:fallback|turn_end|agent_end")
    scenario("should emit events with AgentMessage types", 0, False{}, "Hi there!", "agent_start|turn_start|message_start:Hello|message_end:Hello|message_start:assistant:Hi there!|message_end:assistant:Hi there!|turn_end|agent_end")
    scenario("should throw when context has no messages", 3, False{}, "", "")
    scenario("should continue from existing context without emitting user message events", 1, False{}, "Response", "agent_start|turn_start|message_start:assistant:Response|message_end:assistant:Response|turn_end|agent_end")
    scenario("should allow custom message types as last message (caller responsibility)", 2, False{}, "Response to custom message", "agent_start|turn_start|message_start:assistant:Response to custom message|message_end:assistant:Response to custom message|turn_end|agent_end")
    transcriptScenario("should build provider context exclusively from transcript messages", 0, "convert:system|Hello|;provider")
    transcriptScenario("should handle custom message types via convertToLlm", 1, "convert:This is a notification|Hello|;provider")
    transcriptScenario("should apply transformContext before convertToLlm", 2, "transform;convert:assistant:old response 2|new message|;provider")
