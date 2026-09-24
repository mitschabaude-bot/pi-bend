import Base
import ./tool-call-sequential.bend as S
import ./validated-tool-execution.bend as H
import ./message-events.bend as Test
import ../../ai/test/model-types.bend as Model
import ../src/agent-loop.bend as Execution
import ../src/agent-loop.bend as Call
import ../src/agent-loop.bend as Batch
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../src/agent-loop.bend as E
import ../../ai/src/types.bend as Ai
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as Record
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/abort.bend as Abort

def Run() -> Data: Execution.Execution<Unit, String, String, String>

type Gates is Data:
  Gates{started: Chan(String), ended: Chan(String), first: Chan(Unit), second: Chan(Unit), third: Chan(Unit)}
type Execution is Data:
  Execution{gates: Gates, retained: R.Ref<List<&2, S.Update()>>}
type Recording is Data:
  Recording{events: R.Ref<List<&2, String>>, gates: Gates, failure: Bool}

def selected(id: String, gates: Gates) -> Chan(Unit):
  match id gates:
    case "one" Gates{_, _, first, _, _}: first
    case "two" Gates{_, _, _, second, _}: second
    case _ Gates{_, _, _, _, third}: third

def announce(gates: Gates, id: String) -> IO(Unit):
  match gates:
    case Gates{started, _, _, _, _}:
      do IO<Unit>:
        sent : Bool <- Chan.send(String, started, id)
        R.requireSent(sent)

def execute(environment: Execution, input: H.ExecuteInput()) -> IO(H.ExecuteOutput()):
  match environment input:
    case Execution{+gates, retained} T.ToolExecutionInput{+id, arguments, Some{_}, Some{+update}}:
      do IO<H.ExecuteOutput()>:
        Test.assertion(V.equal(arguments, H.field(V.Text{"changed by hook"})), "parallel execution receives hook-updated arguments without revalidation")
        R.modify(List<&2, S.Update()>, Unit, retained, callbacks => (update <> callbacks, Unit{}))
        C.call(T.AgentToolResult<String>, Unit, update, T.AgentToolResult{Nil{}, Some{"progress"}, None{}, None{}})
        announce(gates, id)
        released : Maybe<&1, Unit> <- Chan.recv(Unit, selected(id, gates))
        return Done{T.AgentToolResult{Nil{}, Some{"executed"}, None{}, None{}}}
    case _ _: IO.die(H.ExecuteOutput(), 1, "unexpected parallel execution input")

def notifyEnd(ended: Chan(String), event: H.EventValue()) -> IO(Unit):
  match event:
    case T.ToolExecutionEnd{id, _, _, _}:
      do IO<Unit>:
        sent : Bool <- Chan.send(String, ended, id)
        R.requireSent(sent)
    case _: IO.pure(Unit, Unit{})

def emit(environment: Recording, event: H.EventValue()) -> IO(E.Emission<String>):
  match environment:
    case Recording{events, Gates{_, ended, _, _, _}, failure}:
      do IO<E.Emission<String>>:
        +observed : H.EventValue() = event
        +name : String = S.key(observed)
        R.modify(List<&2, String>, Unit, events, values => (name <> values, Unit{}))
        notifyEnd(ended, observed)
        return E.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, failure && String.eq(name, "end:two"), Fail{"delivery failed"}, Done{Unit{}})}

def fullContext(context: H.Context()) -> Bool:
  match context:
    case T.AgentContext{T.CustomMessage{_} <> T.CustomMessage{_} <> T.CustomMessage{_} <> Nil{}, _}: True{}
    case _: False{}

def after(count: R.Ref<U32>, input: S.AfterInput()) -> IO(S.AfterOutput()):
  match input:
    case T.ToolHookInput{T.AfterToolCallContext{_, _, arguments, T.AgentToolResult{_, Some{details}, _, _}, False{}, context}, _}:
      do IO<S.AfterOutput()>:
        Test.assertion(fullContext(context) && V.equal(arguments, H.field(V.Text{"changed by hook"})) && String.eq(details, "executed"), "every after hook receives final preparation context and its execution result")
        R.modify(U32, Unit, count, value => ((value + 1 : U32), Unit{}))
        return Done{Some{T.AfterToolCallResult{None{}, Some{"finalized"}, None{}, None{}, Some{True{}}}}}
    case _: IO.die(S.AfterOutput(), 1, "unexpected after-hook input")

def release(gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, gate, Unit{})
    R.requireSent(sent)

def ended(expected: String, actual: Maybe<&1, String>) -> IO(Unit):
  match actual:
    case Some{value}: Test.assertion(String.eq(expected, value), "controlled execution-end ordering")
    case None{}: Test.assertion(False{}, "missing execution-end event")

def finish(failure: Bool, +run: Run(), gates: Gates) -> IO(S.Outcome()):
  match failure gates:
    case False{} Gates{_, +end, first, second, third}:
      do IO<S.Outcome()>:
        release(third)
        thirdEnded : Maybe<&1, String> <- Chan.recv(String, end)
        ended("three", thirdEnded)
        release(second)
        secondEnded : Maybe<&1, String> <- Chan.recv(String, end)
        ended("two", secondEnded)
        release(first)
        Execution.executionResult(Unit, String, String, String, run)
    case True{} Gates{_, end, first, second, third}:
      do IO<S.Outcome()>:
        release(second)
        secondEnded : Maybe<&1, String> <- Chan.recv(String, end)
        ended("two", secondEnded)
        # First and third remain blocked until the failed batch result arrives.
        result : S.Outcome() <- Execution.executionResult(Unit, String, String, String, run)
        release(third)
        release(first)
        return result

def checked(outcome: S.Outcome(), failure: Bool) -> IO(Unit):
  match outcome failure:
    case Fail{error} True{}: Test.assertion(String.eq(error, "delivery failed"), "parallel delivery failure remains a batch error")
    case Done{Batch.Batch{context, values, terminate}} False{}:
      Test.assertion(fullContext(context) && terminate && S.messages(values, False{} <> False{} <> False{} <> Nil{}, "one" <> "two" <> "three" <> Nil{}), "ordered messages and all-call termination after reverse execution completion")
    case _ _: Test.assertion(False{}, "unexpected parallel outcome")

def started(actual: Maybe<&1, String>) -> String:
  match actual:
    case Some{value}: value
    case None{}: "missing"

def began(+a: String, +b: String, +c: String) -> Bool:
  Bool.not(String.eq(a, b)) && Bool.not(String.eq(b, c)) && Bool.not(String.eq(a, c))

def failureEnds(values: List<&2, String>) -> Bool:
  match values:
    case "end:two" <> +a <> +b <> Nil{}:
      (String.eq(a, "end:one") && String.eq(b, "end:three")) || (String.eq(a, "end:three") && String.eq(b, "end:one"))
    case _: False{}

def isUpdate(+value: String) -> Bool:
  String.eq(value, "update:one") || String.eq(value, "update:two") || String.eq(value, "update:three")

def eventOrder(values: List<&2, String>, failure: Bool) -> Bool:
  match values:
    case a <> b <> c <> +u1 <> +u2 <> +u3 <> +remaining:
      S.equal(a <> b <> c <> Nil{}, "start:one" <> "start:two" <> "start:three" <> Nil{}) && isUpdate(u1) && isUpdate(u2) && isUpdate(u3) && began(u1, u2, u3) && Bool.pick(Bool, failure, failureEnds(remaining), S.equal(remaining, "end:three" <> "end:two" <> "end:one" <> "message_start:one" <> "message_end:one" <> "message_start:two" <> "message_end:two" <> "message_start:three" <> "message_end:three" <> Nil{}))
    case _: False{}

def late(callbacks: List<&2, S.Update()>) -> IO(Unit):
  match callbacks:
    case Nil{}: IO.pure(Unit, Unit{})
    case callback <> rest:
      do IO<Unit>:
        S.late(Some{callback})
        late(rest)

def active(+failure: Bool, +run: Run(), +gates: Gates) -> IO(Unit):
  match run gates:
    case Execution.Concurrent{_} Gates{+start, _, _, _, _}:
      do IO<Unit>:
        a : Maybe<&1, String> <- Chan.recv(String, start)
        b : Maybe<&1, String> <- Chan.recv(String, start)
        c : Maybe<&1, String> <- Chan.recv(String, start)
        Test.assertion(began(started(a), started(b), started(c)), "all three real tool executors start before any gate opens")
        outcome : S.Outcome() <- finish(failure, run, gates)
        checked(outcome, failure)
        Execution.disposeExecution(Unit, String, String, String, run)
    case _ _: Test.assertion(False{}, "parallel preparation unexpectedly failed")

def contents(calls: List<&2, Ai.ToolCall<V.Value>>) -> List<&2, Ai.AssistantContent<V.Value>>:
  match calls:
    case Nil{}: Nil{}
    case call <> rest: Ai.AssistantToolCall{call} <> contents(rest)

def scenario(+failure: Bool) -> IO(Unit):
  do IO<Unit>:
    +events : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +signal : R.Ref<Bool> <- R.new(Bool, False{})
    +hooks : R.Ref<U32> <- R.new(U32, 0)
    +retained : R.Ref<List<&2, S.Update()>> <- R.new(List<&2, S.Update()>, Nil{})
    +started : Chan(String) <- Chan.new(String, 3)
    +ended : Chan(String) <- Chan.new(String, 3)
    +first : Chan(Unit) <- Chan.new(Unit, 1)
    +second : Chan(Unit) <- Chan.new(Unit, 1)
    +third : Chan(Unit) <- Chan.new(Unit, 1)
    +gates : Gates = Gates{started, ended, first, second, third}
    +executor : C.Callback<H.ExecuteInput(), H.ExecuteOutput()> <- C.create(~Execution, ~H.ExecuteInput(), ~H.ExecuteOutput(), ~execute, Execution{gates, retained})
    +validator : C.Callback<H.Input(), H.Checked()> <- C.create(~Unit, ~H.Input(), ~H.Checked(), ~H.validate, Unit{})
    +converter : C.Callback<H.Messages(), H.Converted()> <- C.create(~Unit, ~H.Messages(), ~H.Converted(), ~H.convert, Unit{})
    +beforeHook : C.Callback<S.BeforeInput(), S.BeforeOutput()> <- C.create(~Bool, ~S.BeforeInput(), ~S.BeforeOutput(), ~S.before, False{})
    +hook : C.Callback<S.AfterInput(), S.AfterOutput()> <- C.create(~R.Ref<U32>, ~S.AfterInput(), ~S.AfterOutput(), ~after, hooks)
    +abort : C.Callback<Maybe<&2, Abort.AbortSignal<Unit>>, Bool> <- C.create(~R.Ref<Bool>, ~Maybe<&2, Abort.AbortSignal<Unit>>, ~Bool, ~S.aborted, signal)
    +emitter : C.Callback<H.EventValue(), E.Emission<String>> <- C.create(~Recording, ~H.EventValue(), ~E.Emission<String>, ~emit, Recording{events, gates, failure})
    +sink : C.Callback<H.EventValue(), Result<&2, &2, String, Unit>> <- Loop.createAwaitedEventSink(~Unit, ~String, ~String, ~T.AgentToolResult<String>, ~T.AgentToolResult<String>, ~String, emitter)
    +owners : Call.Owners(String, String) <- Call.newOwners(String, String)
    schema : V.Value = V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"object"}} <> Record.Property{"properties", H.field(V.ObjectValue{Record.Record{Record.Property{"type", V.Text{"number"}} <> Nil{}}})} <> Record.Property{"required", V.ArrayValue{V.Text{"value"} <> Nil{}}} <> Nil{}}}
    context : H.Context() = T.AgentContext{Nil{}, Some{T.AgentTool{"echo", "", schema, None{}, "Echo", None{}, executor, None{}, None{}} <> Nil{}}}
    +zero : F64 = F.fromU32(0)
    +arguments : V.Value = H.field(V.Text{"42"})
    calls : List<&2, Ai.ToolCall<V.Value>> = Ai.ToolCall{"one", "echo", arguments, None{}, None{}} <> Ai.ToolCall{"two", "echo", arguments, None{}, None{}} <> Ai.ToolCall{"three", "echo", arguments, None{}, None{}} <> Nil{}
    assistant : Ai.AssistantMessage<V.Value, Unit> = Ai.AssistantMessage{contents(calls), "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Test.usage(Ai.UsageCost{zero, zero, zero, zero, zero}), Ai.ToolUse{}, None{}, None{}, None{}, None{}, zero}
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    capture : Call.CallCapture<Unit, String, String, String, Unit> = Call.CallCapture{assistant, S.configuration(converter, beforeHook, hook), Some{Abort.signal(Unit, controller)}, validator, abort, emitter, sink, owners, "empty"}
    run : Run() <- Execution.executeToolCalls(~Unit, ~String, ~String, ~String, ~Unit, ~S.render, capture, context)
    active(failure, run, gates)
    saved : List<&2, S.Update()> <- R.read(List<&2, S.Update()>, retained)
    late(saved)
    recorded : List<&2, String> <- R.read(List<&2, String>, events)
    Test.assertion(eventOrder(List.reverse(&2, String, recorded), failure), "preparation before execution, reverse ends, ordered messages, no late updates")
    actualHooks : U32 <- R.read(U32, hooks)
    Test.assertion(U32.is_eq(actualHooks, 3), "siblings finish their after hooks even after batch failure")
    C.dispose(H.ExecuteInput(), H.ExecuteOutput(), executor)
    saved : List<&2, S.Update()> <- R.dispose(List<&2, S.Update()>, retained)
    Call.disposeOwners(String, String, owners)
    C.dispose(H.Input(), H.Checked(), validator)
    C.dispose(H.Messages(), H.Converted(), converter)
    C.dispose(S.BeforeInput(), S.BeforeOutput(), beforeHook)
    C.dispose(S.AfterInput(), S.AfterOutput(), hook)
    C.dispose(Maybe<&2, Abort.AbortSignal<Unit>>, Bool, abort)
    C.dispose(H.EventValue(), Result<&2, &2, String, Unit>, sink)
    C.dispose(H.EventValue(), E.Emission<String>, emitter)
    dropped : List<&2, String> <- R.dispose(List<&2, String>, events)
    dropped : Bool <- R.dispose(Bool, signal)
    dropped : U32 <- R.dispose(U32, hooks)
    Chan.close(String, started)
    Chan.close(String, ended)
    Chan.close(Unit, first)
    Chan.close(Unit, second)
    Chan.close(Unit, third)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{})
    scenario(True{})
    IO.print("PASS routed gated parallel lifecycle: concurrent execution, final preparation context, ordered messages, prompt failure and surviving siblings")
