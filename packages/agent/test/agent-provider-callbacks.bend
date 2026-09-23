import Base
import ../src/agent.bend as Agent
import ../src/agent.bend as State
import ../src/agent.bend as Run
import ../src/agent-loop.bend as Loop
import ../src/stream-fn.bend as Provider
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/event-stream.bend as Stream
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/record.bend as Record
import ../../runtime/src/f64.bend as F
import ./agent.bend as Named
import ./agent-owner.bend as Owner
import ./agent-behavior.bend as Behavior
import ./agent-settings.bend as SettingsTest
import ./agent-run.bend as H
import ./message-events.bend as Test

def PayloadInput() -> Data: Ai.PayloadInput<Ai.JsonValue, Ai.Model<Ai.JsonValue>>
def PayloadResult() -> Data: Result<&2, &2, String, Maybe<&2, Ai.JsonValue>>
def Payload() -> Data: Ai.PayloadCallback(Ai.JsonValue, Ai.Model<Ai.JsonValue>, String)
def ResponseInput() -> Data: Ai.ResponseInput<Ai.Model<Ai.JsonValue>>
def ResponseResult() -> Data: Result<&2, &2, String, Unit>
def Response() -> Data: Ai.ResponseCallback(Ai.Model<Ai.JsonValue>, String)
def model(value: Ai.Model<Ai.JsonValue>) -> Bool:
  match value:
    case Ai.Model{"unknown", _, _, "unknown", _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}
def response() -> Ai.ProviderResponse:
  Ai.ProviderResponse{F.fromU32(200), Record.Record{Record.Property{"x-fixture", "yes"} <> Nil{}}}
def validResponse(value: Ai.ProviderResponse) -> Bool:
  match value:
    case Ai.ProviderResponse{status, Record.Record{Record.Property{"x-fixture", "yes"} <> Nil{}}}: SettingsTest.number(status, 200)
    case _: False{}
type Logged is Data:
  Logged{name: String, trace: R.Ref<String>}
def log(value: Logged) -> IO(Unit):
  match value:
    case Logged{name, trace}: R.modify(String, Unit, trace, old => (old ++ name ++ ";", Unit{}))
def payload(capture: Logged, input: PayloadInput()) -> IO(PayloadResult()):
  match input:
    case Ai.PayloadInput{_, suppliedModel}:
      do IO<PayloadResult()>:
        Test.assertion(model(suppliedModel), "payload callback receives provider request model")
        log(capture)
        return Done{Some{Ai.JsonNull{}}}
def observed(capture: Logged, input: ResponseInput()) -> IO(ResponseResult()):
  match input:
    case Ai.ResponseInput{value, suppliedModel}:
      do IO<ResponseResult()>:
        Test.assertion(model(suppliedModel) && validResponse(value), "response callback receives response metadata and model")
        log(capture)
        return Done{Unit{}}
type Bindings is Data:
  Bindings{payload: Maybe<&2, Payload()>, response: Maybe<&2, Response()>}
def install(+agent: Owner.Owner(), bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{payload, response}:
      do IO<Unit>:
        Agent.setOnPayload(Unit, Unit, String, String, Unit, agent, payload)
        Agent.setOnResponse(Unit, Unit, String, String, Unit, agent, response)
def read(+agent: Owner.Owner()) -> IO(Bindings):
  do IO<Bindings>:
    payload : Maybe<&2, Payload()> <- Agent.getOnPayload(Unit, Unit, String, String, Unit, agent)
    response : Maybe<&2, Response()> <- Agent.getOnResponse(Unit, Unit, String, String, Unit, agent)
    return Bindings{payload, response}
def samePayload(left: Maybe<&2, Payload()>, right: Maybe<&2, Payload()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(PayloadInput(), PayloadResult(), a, b)
    case _ _: False{}
def sameResponse(left: Maybe<&2, Response()>, right: Maybe<&2, Response()>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(ResponseInput(), ResponseResult(), a, b)
    case _ _: False{}
def same(left: Bindings, right: Bindings) -> Bool:
  match left right:
    case Bindings{a, b} Bindings{c, d}: samePayload(a, c) && sameResponse(b, d)
def config(value: H.Config()) -> Bindings:
  match value:
    case T.AgentLoopConfig{Ai.SimpleStreamOptions{_, _, _, _, _, payload, response, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}: Bindings{payload, response}
def payloadSuccess(value: PayloadResult()) -> Bool:
  match value:
    case Done{Some{Ai.JsonNull{}}}: True{}
    case _: False{}
def invokePayload(callback: Maybe<&2, Payload()>, suppliedModel: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        returned : PayloadResult() <- C.call(PayloadInput(), PayloadResult(), value, Ai.PayloadInput{Ai.JsonNull{}, suppliedModel})
        Test.assertion(payloadSuccess(returned), "provider observes payload callback return")
def responseSuccess(value: ResponseResult()) -> Bool:
  match value:
    case Done{Unit{}}: True{}
    case _: False{}
def invokeResponse(callback: Maybe<&2, Response()>, suppliedModel: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match callback:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}:
      do IO<Unit>:
        returned : ResponseResult() <- C.call(ResponseInput(), ResponseResult(), value, Ai.ResponseInput{response(), suppliedModel})
        Test.assertion(responseSuccess(returned), "provider awaits response callback completion")
def invoke(bindings: Bindings, +suppliedModel: Ai.Model<Ai.JsonValue>) -> IO(Unit):
  match bindings:
    case Bindings{payload, response}:
      do IO<Unit>:
        invokePayload(payload, suppliedModel)
        invokeResponse(response, suppliedModel)
type Capture is Data:
  Capture{slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Bindings, calls: R.Ref<U32>, trace: R.Ref<String>, streams: R.Ref<List<&2, H.StreamValue()>>}
def replaceFirst(index: U32, slot: R.Ref<Maybe<&2, Owner.Owner()>>, future: Bindings) -> IO(Unit):
  match index:
    case 0:
      do IO<Unit>:
        value : Maybe<&2, Owner.Owner()> <- R.read(Maybe<&2, Owner.Owner()>, slot)
        agent : Owner.Owner() <- SettingsTest.requireAgent(value)
        install(agent, future)
    case _: IO.pure(Unit, Unit{})
def provider(capture: Capture, input: H.ProviderInput()) -> IO(H.ProviderOutput()):
  match capture input:
    case Capture{slot, future, calls, trace, streams} T.StreamInput{suppliedModel, _, Some{options}}:
      do IO<H.ProviderOutput()>:
        invoke(config(options), suppliedModel)
        R.modify(String, Unit, trace, old => (old ++ "p;", Unit{}))
        +index : U32 <- R.modify(U32, U32, calls, old => SettingsTest.increment(old))
        replaceFirst(index, slot, future)
        +stream : H.StreamValue() <- Stream.createAssistantMessageEventStream(~Schema.Value, ~Unit)
        R.modify(List<&2, H.StreamValue()>, Unit, streams, old => (stream <> old, Unit{}))
        SettingsTest.push(index, stream)
        return Done{T.borrowedStream(Unit, String, stream)}
    case _ _: IO.die(H.ProviderOutput(), 1, "provider options missing")
def create(capture: Capture) -> IO(Named.Fixture):
  do IO<Named.Fixture>:
    +stream : Named.StreamFunction() <- C.create(~Capture, ~H.ProviderInput(), ~H.ProviderOutput(), ~provider, capture)
    +validator : Named.Validator() <- C.create(~U32, ~Loop.ToolValidationInput, ~Result<&2, &2, String, Schema.Value>, ~H.validate, 9)
    +executor : Named.Executor() <- C.create(~Unit, ~T.ToolExecutionInput<Unit>, ~Result<&2, &2, String, T.AgentToolResult<Unit>>, ~H.executeTool, Unit{})
    +registry : Named.Fallback() <- Provider.create(Unit, Unit, H.Config(), String)
    initial : State.AgentInitialState<Unit, Unit, String, String> = State.AgentInitialState{None{}, None{}, None{}, H.tools(9, executor), None{}}
    result : Result<&2, &2, Provider.MissingDefault, Owner.Owner()> <- Agent.new(~Unit, ~Unit, ~String, ~String, ~Unit, Named.options(Some{initial}, stream), registry, validator, Unit{})
    agent : Owner.Owner() <- Owner.requireOwner(result)
    return Named.Fixture{agent, stream, validator, executor, registry}


def exercise(+agent: Owner.Owner(), +first: Bindings, +second: Bindings) -> IO(Unit):
  do IO<Unit>:
    empty : Bindings <- read(agent)
    Test.assertion(same(empty, Bindings{None{}, None{}}), "provider callbacks initially absent")
    install(agent, first)
    assigned : Bindings <- read(agent)
    Test.assertion(same(assigned, first), "provider callback getters retain assigned handles")
    Behavior.prompt(agent, "first")
    replaced : Bindings <- read(agent)
    Test.assertion(same(replaced, second), "getter sees replacements after current run")
    Behavior.prompt(agent, "next")
    install(agent, Bindings{None{}, None{}})
    cleared : Bindings <- read(agent)
    Test.assertion(same(cleared, Bindings{None{}, None{}}), "provider callbacks can be cleared")
    Behavior.prompt(agent, "cleared")
def disposeBindings(bindings: Bindings) -> IO(Unit):
  match bindings:
    case Bindings{Some{payload}, Some{response}}:
      do IO<Unit>:
        C.dispose(PayloadInput(), PayloadResult(), payload)
        C.dispose(ResponseInput(), ResponseResult(), response)
    case _: IO.pure(Unit, Unit{})
def bindings(+trace: R.Ref<String>, suffix: String) -> IO(Bindings):
  do IO<Bindings>:
    +name : String = suffix
    payload : Payload() <- C.create(~Logged, ~PayloadInput(), ~PayloadResult(), ~payload, Logged{"p" ++ name, trace})
    response : Response() <- C.create(~Logged, ~ResponseInput(), ~ResponseResult(), ~observed, Logged{"r" ++ name, trace})
    return Bindings{Some{payload}, Some{response}}
def main() -> IO(Unit):
  do IO<Unit>:
    +slot : R.Ref<Maybe<&2, Owner.Owner()>> <- R.new(Maybe<&2, Owner.Owner()>, None{})
    +calls : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +streams : R.Ref<List<&2, H.StreamValue()>> <- R.new(List<&2, H.StreamValue()>, Nil{})
    +first : Bindings <- bindings(trace, "a")
    +second : Bindings <- bindings(trace, "b")
    +fixture : Named.Fixture <- create(Capture{slot, second, calls, trace, streams})
    +agent : Owner.Owner() = Named.getAgent(fixture)
    R.write(Maybe<&2, Owner.Owner()>, slot, Some{agent})
    exercise(agent, first, second)
    actual : String <- R.read(String, trace)
    Test.assertion(String.eq(actual, "pa;ra;p;pa;ra;p;pb;rb;p;p;"), "provider callback order and per-run capture match upstream")
    old : Maybe<&2, Owner.Owner()> <- R.dispose(Maybe<&2, Owner.Owner()>, slot)
    Named.dispose(fixture)
    invoke(first, State.defaultModel(Ai.JsonValue))
    invoke(second, State.defaultModel(Ai.JsonValue))
    disposeBindings(first)
    disposeBindings(second)
    old : U32 <- R.dispose(U32, calls)
    old : String <- R.dispose(String, trace)
    all : List<&2, H.StreamValue()> <- R.dispose(List<&2, H.StreamValue()>, streams)
    H.disposeStreams(all)
    IO.print("PASS Agent payload/response callback forwarding, capture, clearing and ownership")
