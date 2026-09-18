import Base
import ../src/agent.bend as Agent
import ../src/agent-options.bend as Options
import ../src/agent-state.bend as State
import ../src/agent-run.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as Schema
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-settings.bend as SettingsTest
import ./agent-run.bend as H
import ./message-events.bend as Test

def Converter() -> Data: Options.Converter(Unit, Unit, Unit, String, String)
def TransformInput() -> Data: T.TransformContextInput<H.Messages(), Run.Signal()>
def Transformed() -> Data: Result<&2, &2, String, H.Messages()>
def Transform() -> Data: C.Callback<TransformInput(), Transformed()>
type Logged is Data:
  Logged{name: String, trace: R.Ref<String>}
def append(log: Logged) -> IO(Unit):
  match log:
    case Logged{name, trace}: R.modify(String, Unit, trace, old => (old ++ name ++ ";", Unit{}))
def convert(log: Logged, messages: H.Messages()) -> IO(H.Converted()):
  do IO<H.Converted()>:
    append(log)
    H.converter(Unit{}, messages)
def transform(log: Logged, input: TransformInput()) -> IO(Transformed()):
  match input:
    case T.TransformContextInput{messages, _}:
      do IO<Transformed()>:
        append(log)
        return Done{messages}
type Bindings is Data:
  Bindings{stream: Named.StreamFunction(), convert: Converter(), transform: Transform()}
def install(+agent: Owner.Owner(), bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{stream, convert, transform}:
      do IO<Unit>:
        Agent.setStreamFunction(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, stream)
        Agent.setConvertToLlm(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, convert)
        Agent.setTransformContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, Some{transform})
def replaceFirst(index: U32, slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Maybe<&2, Bindings>) -> IO(Unit):
  match index future:
    case 0 Some{bindings}:
      do IO<Unit>:
        value : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(value)
        install(agent, bindings)
    case _ _: IO.pure(Unit, Unit{})
type ProviderCapture is Data:
  ProviderCapture{log: Logged, slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Maybe<&2, Bindings>, calls: R.Ref<U32>, streams: R.Ref<List<&2, H.StreamValue()>>}
def provider(capture: ProviderCapture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture:
    case ProviderCapture{log, slot, future, calls, streams}:
      do IO<H.ProviderOutput()>:
        append(log)
        +index : U32 <- R.modify(U32, U32, calls, old => SettingsTest.increment(old))
        replaceFirst(index, slot, future)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Unit, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        SettingsTest.push(index, stream)
        return Done{stream}
type Fixture is Data:
  Fixture{base: Named.Fixture, original: Converter(), first: Bindings, second: Bindings}
def create(+slot: R.Ref<Maybe<&2, Owner.Owner()>>, +trace: R.Ref<String>, +calls: R.Ref<U32>, +streams: R.Ref<List<&2, H.StreamValue()>>) -> IO(Fixture):
  do IO<Fixture>:
    +convertA : Converter() <- C.create(~Logged, ~H.Messages(), ~H.Converted(), ~convert, Logged{"ca", trace})
    +convertB : Converter() <- C.create(~Logged, ~H.Messages(), ~H.Converted(), ~convert, Logged{"cb", trace})
    +transformA : Transform() <- C.create(~Logged, ~TransformInput(), ~Transformed(), ~transform, Logged{"ta", trace})
    +transformB : Transform() <- C.create(~Logged, ~TransformInput(), ~Transformed(), ~transform, Logged{"tb", trace})
    +streamB : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, ProviderCapture{Logged{"pb", trace}, slot, None{}, calls, streams})
    +second : Bindings = Bindings{streamB, convertB, transformB}
    +streamA : Named.StreamFunction() <- C.create(~ProviderCapture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, ProviderCapture{Logged{"pa", trace}, slot, Some{second}, calls, streams})
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput<Schema.Value, Unit, Unit>, ~Result<&2, &2, String, Unit>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit, Run.Signal(), Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +registry : Named.Fallback() <- Provider.create(Schema.Value, Unit, Unit, Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Schema.Value, Unit, Unit, Unit, String, Unit, Run.Signal(), String, Unit> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~Unit, ~String, ~Unit, ~String, ~Unit, ~Unit, ~Unit, Named.options(Some{initial}, streamA), registry, validator, Unit{})
    +agent : Owner.Owner() <- Owner.requireOwner(result)
    original : Converter() <- Agent.getConvertToLlm(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
    return Fixture{Named.Fixture{agent, streamA, validator, executor, registry}, original, Bindings{streamA, convertA, transformA}, second}
def sameTransform(value: Maybe<&2, Transform()>, expected: Transform()) -> Bool:
  match value:
    case Some{actual}: C.same(TransformInput(), Transformed(), actual, expected)
    case _: False{}
def checkGetters(+agent: Owner.Owner(), bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{stream, convert, transform}:
      do IO<Unit>:
        actualStream : Named.StreamFunction() <- Agent.getStreamFunction(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        actualConvert : Converter() <- Agent.getConvertToLlm(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        actualTransform : Maybe<&2, Transform()> <- Agent.getTransformContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(C.same(H.ProviderInput(), H.ProviderOutput(), actualStream, stream) && C.same(H.Messages(), H.Converted(), actualConvert, convert) && sameTransform(actualTransform, transform), "getters retain the assigned callback handles")
def emptyConverted(value: H.Converted()) -> Bool:
  match value:
    case Done{Nil{}}: True{}
    case _: False{}
def exercise(fixture: Fixture, slot: R.Ref<Maybe<&2, Owner.Owner()>>) -> IO(Unit):
  match fixture:
    case Fixture{base, original, +first, +second}:
      do IO<Unit>:
        +agent : Owner.Owner() = Named.getAgent(base)
        R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
        absent : Maybe<&2, Transform()> <- Agent.getTransformContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(Maybe.is_none(&2, Transform(), absent), "transform is initially absent")
        install(agent, first)
        checkGetters(agent, first)
        Behavior.prompt(agent, "first")
        checkGetters(agent, second)
        Behavior.prompt(agent, "next")
        Agent.setTransformContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent, None{})
        cleared : Maybe<&2, Transform()> <- Agent.getTransformContext(Unit, Unit, Unit, String, Unit, String, Unit, Unit, Unit, agent)
        Test.assertion(Maybe.is_none(&2, Transform(), cleared), "transform can be cleared")
        Behavior.prompt(agent, "without transform")
        old : H.Converted() <- C.call(H.Messages(), H.Converted(), original, T.CustomMessage{"filtered"} <> Nil{})
        Test.assertion(emptyConverted(old), "owned default converter survives replacement until owner disposal")
def disposeBindings(bindings: Bindings, disposeStream: Bool) -> IO(Unit):
  match bindings:
    case Bindings{stream, +convert, +transform}:
      do IO<Unit>:
        old : H.Converted() <- C.call(H.Messages(), H.Converted(), convert, Nil{})
        Test.assertion(emptyConverted(old), "borrowed converter survives Agent disposal")
        old : Transformed() <- C.call(TransformInput(), Transformed(), transform, T.TransformContextInput{Nil{}, None{}})
        C.dispose(H.Messages(), H.Converted(), convert)
        C.dispose(TransformInput(), Transformed(), transform)
        Bool.pick(IO(Unit), disposeStream, C.dispose(H.ProviderInput(), H.ProviderOutput(), stream), IO.pure(Unit, Unit{}))
def dispose(fixture: Fixture) -> IO(Unit):
  match fixture:
    case Fixture{base, _, first, second}:
      do IO<Unit>:
        Named.dispose(base)
        disposeBindings(first, False{})
        disposeBindings(second, True{})
def main() -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +trace : R.Ref<String> <- R.new(String, "")
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +fixture : Fixture <- create(slot, trace, calls, streams)
    exercise(fixture, slot)
    observed : String <- R.read(String, trace)
    Test.assertion(String.eq(observed, "ta;ca;pa;ta;ca;pa;tb;cb;pb;cb;pb;"), "replacement affects next run while current run retains transform/converter/provider and order")
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    dispose(fixture)
    old : String <- R.dispose(String, trace)
    old : U32 <- R.dispose(U32, calls)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent provider/converter/transform replacement, capture and ownership")
