import Base
import ../src/agent-loop.bend as Loop
import ../src/agent-loop.bend as E
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/ref.bend as R
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/f64.bend as F

def Input() -> Data: T.ToolExecutionInput<String>
def Output() -> Data: Result<&2, &2, String, T.AgentToolResult<String>>
def EventValue() -> Data: T.AgentEvent<Unit, String, String, T.AgentToolResult<String>, T.AgentToolResult<String>>
def Outcome() -> Data: Result<&2, &2, String, Loop.ExecutedToolCallOutcome<String>>
def Update() -> Data: T.AgentToolUpdateCallback(String)
type ToolState is Data:
  ToolState{saved: R.Ref<Maybe<&2, Update()>>, returned: Chan(Unit), fail: Bool, updates: Bool}
type EmitState is Data:
  EmitState{log: R.Ref<List<&2, String>>, first: Chan(Unit), second: Chan(Unit), fail: Bool, immediate: Bool}

def partial(+text: String) -> T.AgentToolResult<String>:
  T.AgentToolResult{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}, text, None{}, None{}}

def update(callback: Update(), text: String) -> IO(Unit):
  C.call(T.AgentToolResult<String>, Unit, callback, partial(text))

def sendUpdates(enabled: Bool, +callback: Update()) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        update(callback, "first")
        update(callback, "second")

def execute(state: ToolState, input: Input()) -> IO(Output()):
  match state input:
    case ToolState{saved, returned, fail, updates} T.ToolExecutionInput{id, args, Some{_}, Some{+callback}}:
      do IO<Output()>:
        Test.assertion(String.eq(id, "call") && Schema.equal(args, Schema.Number{F.fromU32(123)}), "tool execution lost id/validated arguments")
        R.write(Maybe<&2, Update()>, saved, Some{callback})
        sendUpdates(updates, callback)
        sent : Bool <- Chan.send(Unit, returned, Unit{})
        return Bool.pick(Output(), fail, Fail{"tool failed"}, Done{partial("done")})
    case _ _: IO.die(Output(), 1, "tool execution lost signal/update callback")

def listened(gate: Chan(Unit), +error: String) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    released : Maybe<&1, Unit> <- Chan.recv(Unit, gate)
    return Bool.pick(Result<&2, &2, String, Unit>, String.is_empty(error), Done{Unit{}}, Fail{error})

def delivery(immediate: Bool, gate: Chan(Unit), +error: String) -> IO(E.Emission<String>):
  match immediate:
    case True{}: IO.pure(E.Emission<String>, E.EmissionReady{Bool.pick(Result<&2, &2, String, Unit>, String.is_empty(error), Done{Unit{}}, Fail{error})})
    case False{}: E.startEmission(String, listened(gate, error))

def emit(state: EmitState, event: EventValue()) -> IO(E.Emission<String>):
  match state event:
    case EmitState{log, first, second, fail, +immediate} T.ToolExecutionUpdate{id, name, raw, T.AgentToolResult{_, +details, _, _}}:
      do IO<E.Emission<String>>:
        Test.assertion(String.eq(id, "call") && String.eq(name, "echo") && Schema.equal(raw, Schema.Text{"raw"}), "update must preserve original call arguments")
        R.modify(List<&2, String>, Unit, log, entries => (details <> entries, Unit{}))
        returnGate : Chan(Unit) = Bool.pick(Chan(Unit), String.eq(details, "first"), first, second)
        error : String = Bool.pick(String, fail && (immediate || String.eq(details, "first")), Bool.pick(String, String.eq(details, "first"), "listener failed", "second listener failed"), "")
        delivery(immediate, returnGate, error)
    case _ _: IO.die(E.Emission<String>, 1, "unexpected execution event")

def finish(action: IO(Outcome()), done: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    outcome : Outcome() <- action
    won : Bool <- D.resolve(Unit, done, Unit{})
    return outcome

def check(outcome: Outcome(), +toolFailed: Bool, listenerFailed: Bool) -> IO(Unit):
  match outcome:
    case Fail{error}: Test.assertion(listenerFailed && String.eq(error, "listener failed"), "update failure must escape execution")
    case Done{Loop.ExecutedToolCallOutcome{T.AgentToolResult{Ai.TextImageText{Ai.TextContent{message, _}} <> Nil{}, details, _, _}, isError}}:
      Test.assertion(Bool.not(listenerFailed) && Bool.not(Bool.xor(isError, toolFailed)) && String.eq(message, Bool.pick(String, toolFailed, "tool failed", "done")) && String.eq(details, Bool.pick(String, toolFailed, "empty details", "done")), "tool result/error conversion differs")
    case _: Test.assertion(False{}, "unexpected execution result shape")

def send(gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Unit, gate, Unit{})
    return Unit{}

def stillPending(done: D.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    observed : Maybe<&2, Unit> <- D.peek(Unit, done)
    Test.assertion(Maybe.is_none(&2, Unit, observed), "execution ended before accepted listeners settled")

def releaseFirst(delayed: Bool, first: Chan(Unit), done: D.Deferred<Unit>) -> IO(Unit):
  match delayed:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        stillPending(done)
        send(first)

def releaseSecond(delayed: Bool, fail: Bool, second: Chan(Unit), done: D.Deferred<Unit>) -> IO(Unit):
  match delayed fail:
    case True{} False{}:
      do IO<Unit>:
        stillPending(done)
        send(second)
    case _ _: IO.pure(Unit, Unit{})

def late(value: Maybe<&2, Update()>) -> IO(Unit):
  match value:
    case None{}: Test.assertion(False{}, "tool did not retain callback")
    case Some{callback}: update(callback, "late")

def scenario(+toolFailed: Bool, +listenerFailed: Bool, +hasUpdates: Bool, +immediate: Bool) -> IO(Unit):
  do IO<Unit>:
    +saved : R.Ref<Maybe<&2, Update()>> <- R.new(Maybe<&2, Update()>, None{})
    +returned : Chan(Unit) <- Chan.new(Unit, 1)
    +first : Chan(Unit) <- Chan.new(Unit, 1)
    +second : Chan(Unit) <- Chan.new(Unit, 1)
    +done : D.Deferred<Unit> <- D.new(Unit)
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +emitter : C.Callback<EventValue(), E.Emission<String>> <- C.create(~EmitState, ~EventValue(), ~E.Emission<String>, ~emit, EmitState{log, first, second, listenerFailed, immediate})
    +executor : C.Callback<Input(), Output()> <- C.create(~ToolState, ~Input(), ~Output(), ~execute, ToolState{saved, returned, toolFailed, hasUpdates})
    +call : Ai.ToolCall<Schema.Value> = Ai.ToolCall{"call", "echo", Schema.Text{"raw"}, None{}, None{}}
    +updates : Loop.ToolUpdateRun<String, String> <- Loop.createToolUpdateRun(~Unit, ~String, ~String, ~String, call, emitter)
    prepared : Loop.PreparedToolCall<String, String> = Loop.PreparedToolCall{call, T.AgentTool{"echo", "", Schema.Null{}, None{}, "", None{}, executor, None{}, None{}}, Schema.Number{F.fromU32(123)}}
    controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    running : Chan(Outcome()) <- IO.fork(Outcome(), finish(Loop.executePreparedToolCall(String, String, prepared, Some{Abort.signal(Unit, controller)}, updates, "empty details", error => error), done))
    # Both update invocations must return while their listeners are blocked.
    toolReturned : Maybe<&1, Unit> <- Chan.recv(Unit, returned)
    +delayed : Bool = hasUpdates && Bool.not(immediate)
    releaseFirst(delayed, first, done)
    releaseSecond(delayed, listenerFailed, second, done)
    outcome : Outcome() <- IO.join(Outcome(), running)
    check(outcome, toolFailed, listenerFailed && hasUpdates)
    retained : Maybe<&2, Update()> <- R.read(Maybe<&2, Update()>, saved)
    late(retained)
    observed : List<&2, String> <- R.read(List<&2, String>, log)
    Test.assertion(String.eq(String.join(List.reverse(&2, String, observed), "|"), Bool.pick(String, hasUpdates, "first|second", "")), "update start order or late-update rejection changed")
    Bool.pick(IO(Unit), delayed && listenerFailed, send(second), IO.pure(Unit, Unit{}))
    alias : Maybe<&2, Update()> <- R.dispose(Maybe<&2, Update()>, saved)
    C.dispose(Input(), Output(), executor)
    Loop.disposeToolUpdateRun(String, String, updates)
    C.dispose(EventValue(), E.Emission<String>, emitter)
    entries : List<&2, String> <- R.dispose(List<&2, String>, log)
    D.dispose(Unit, done)
    Chan.close(Unit, returned)
    Chan.close(Unit, first)
    Chan.close(Unit, second)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(False{}, False{}, True{}, False{})
    scenario(True{}, False{}, True{}, False{})
    scenario(False{}, True{}, True{}, False{})
    scenario(True{}, True{}, True{}, False{})
    scenario(False{}, False{}, False{}, False{})
    scenario(True{}, False{}, False{}, False{})
    scenario(False{}, False{}, True{}, True{})
    scenario(False{}, True{}, True{}, True{})
    IO.print("PASS prepared execution, ordered update starts, overlapping listeners, error precedence and retained late callbacks")
