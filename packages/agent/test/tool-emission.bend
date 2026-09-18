import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C
import ../../runtime/src/deferred.bend as D
import ../../runtime/src/f64.bend as N

def EventValue() -> Data: T.AgentEvent<Unit, Unit, Unit, String, Unit, Unit, R.Ref<T.AgentToolResult<String>>>
def Outcome() -> Data: Result<&2, &2, String, Unit>
def Sink() -> Data: Loop.AgentEventSink(Unit, Unit, Unit, String, Unit, Unit, R.Ref<T.AgentToolResult<String>>, String)

type Environment is Data:
  Environment{mode: U32, log: R.Ref<List<&2, String>>, message: R.Ref<Ai.ToolResultMessage<String>>, result: R.Ref<T.AgentToolResult<String>>, ready: D.Deferred<Unit>, gate: D.Deferred<Unit>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def append(log: R.Ref<List<&2, String>>, text: String) -> IO(Unit):
  R.modify(List<&2, String>, Unit, log, current => (text <> current, Unit{}))

def message(details: String) -> Ai.ToolResultMessage<String>:
  Ai.ToolResultMessage{"id", "tool", Nil{}, Some{details}, None{}, False{}, N.fromU32(0)}

def result(details: String) -> T.AgentToolResult<String>:
  T.AgentToolResult{Nil{}, details, None{}, None{}}

def detail(value: Ai.ToolResultMessage<String>) -> String:
  match value:
    case Ai.ToolResultMessage{_, _, _, Some{text}, _, _, _}: text
    case _: "unexpected details"

def gate(ready: D.Deferred<Unit>, release: D.Deferred<Unit>) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- D.resolve(Unit, ready, Unit{})
    D.result(Unit, release)

def started(mode: U32, value: R.Ref<Ai.ToolResultMessage<String>>) -> IO(Outcome()):
  match mode:
    case 1: IO.pure(Outcome(), Fail{"start failure"})
    case _:
      do IO<Outcome()>:
        R.write(Ai.ToolResultMessage<String>, value, message("after"))
        return Done{Unit{}}

def ended(mode: U32) -> Outcome():
  match mode:
    case 2: Fail{"end failure"}
    case _: Done{Unit{}}

def executionOutcome(mode: U32) -> Outcome():
  match mode:
    case 4: Fail{"execution failure"}
    case _: Done{Unit{}}

def body(environment: Environment, event: EventValue()) -> IO(Outcome()):
  match environment event:
    case Environment{mode, log, expected, _, ready, release} T.MessageStart{T.LlmMessage{Ai.ToolResult{+value}}}:
      do IO<Outcome()>:
        assertion(R.same(Ai.ToolResultMessage<String>, expected, value), "message_start lost original message identity")
        current : Ai.ToolResultMessage<String> <- R.read(Ai.ToolResultMessage<String>, value)
        append(log, "message_start:" ++ detail(current))
        gate(ready, release)
        started(mode, value)
    case Environment{mode, log, expected, _, _, _} T.MessageEnd{T.LlmMessage{Ai.ToolResult{+value}}}:
      do IO<Outcome()>:
        assertion(R.same(Ai.ToolResultMessage<String>, expected, value), "message_end lost original message identity")
        current : Ai.ToolResultMessage<String> <- R.read(Ai.ToolResultMessage<String>, value)
        append(log, "message_end:" ++ detail(current))
        return ended(mode)
    case Environment{mode, log, _, expected, ready, release} T.ToolExecutionEnd{id, name, +value, isError}:
      do IO<Outcome()>:
        assertion(R.same(T.AgentToolResult<String>, expected, value), "execution_end lost finalized result identity")
        assertion(isError, "execution error flag changed")
        append(log, "tool_execution_end:" ++ id ++ ":" ++ name ++ ":true")
        gate(ready, release)
        R.write(T.AgentToolResult<String>, value, result("updated"))
        return executionOutcome(mode)
    case _ _: IO.die(Outcome(), 1, "unexpected emitted event")

def emit(mode: U32, value: R.Ref<Ai.ToolResultMessage<String>>, finalized: Loop.FinalizedToolCallOutcome<Unit, String>, sink: Sink()) -> IO(Outcome()):
  match mode:
    case 3: Loop.emitToolExecutionEnd(Unit, Unit, Unit, String, Unit, Unit, String, finalized, sink)
    case 4: Loop.emitToolExecutionEnd(Unit, Unit, Unit, String, Unit, Unit, String, finalized, sink)
    case _: Loop.emitToolResultMessage(Unit, Unit, Unit, String, Unit, Unit, R.Ref<T.AgentToolResult<String>>, String, value, sink)

def task(mode: U32, value: R.Ref<Ai.ToolResultMessage<String>>, finalized: Loop.FinalizedToolCallOutcome<Unit, String>, sink: Sink(), completed: D.Deferred<Unit>) -> IO(Outcome()):
  do IO<Outcome()>:
    outcome : Outcome() <- emit(mode, value, finalized, sink)
    won : Bool <- D.resolve(Unit, completed, Unit{})
    return outcome

def outcomeText(outcome: Outcome()) -> String:
  match outcome:
    case Done{Unit{}}: "done"
    case Fail{error}: error

def checkResult(mode: U32, value: T.AgentToolResult<String>) -> IO(Unit):
  match mode value:
    case 3 T.AgentToolResult{_, details, _, _}: assertion(String.eq(details, "updated"), "execution callback mutation lost")
    case 4 T.AgentToolResult{_, details, _, _}: assertion(String.eq(details, "updated"), "failed execution callback mutation lost")
    case _ _: IO.pure(Unit, Unit{})

def single(values: List<&2, String>) -> Bool:
  match values:
    case _ <> Nil{}: True{}
    case _: False{}

def run(+mode: U32, expectedTrace: String, expectedOutcome: String) -> IO(Unit):
  do IO<Unit>:
    +value : R.Ref<Ai.ToolResultMessage<String>> <- R.new(Ai.ToolResultMessage<String>, message("before"))
    +resultValue : R.Ref<T.AgentToolResult<String>> <- R.new(T.AgentToolResult<String>, result("original"))
    +call : T.AgentToolCall(Unit) <- R.new(Ai.ToolCall<Unit>, Ai.ToolCall{"id", "tool", Unit{}, None{}, None{}})
    +log : R.Ref<List<&2, String>> <- R.new(List<&2, String>, Nil{})
    +ready : D.Deferred<Unit> <- D.new(Unit)
    +release : D.Deferred<Unit> <- D.new(Unit)
    +completed : D.Deferred<Unit> <- D.new(Unit)
    +sink : Sink() <- C.create(~Environment, ~EventValue(), ~Outcome(), ~body, Environment{mode, log, value, resultValue, ready, release})
    running : Chan(Outcome()) <- IO.fork(Outcome(), task(mode, value, Loop.FinalizedToolCallOutcome{call, resultValue, True{}}, sink, completed))
    D.result(Unit, ready)
    pending : Maybe<&2, Unit> <- D.peek(Unit, completed)
    assertion(Maybe.is_none(&2, Unit, pending), "emitter completed while its listener was suspended")
    before : List<&2, String> <- R.read(List<&2, String>, log)
    assertion(single(before), "later event emitted before first listener settled")
    won : Bool <- D.resolve(Unit, release, Unit{})
    outcome : Outcome() <- IO.join(Outcome(), running)
    assertion(String.eq(outcomeText(outcome), expectedOutcome), "listener failure did not propagate unchanged")
    recorded : List<&2, String> <- R.read(List<&2, String>, log)
    assertion(String.eq(String.join(List.reverse(&2, String, recorded), "|"), expectedTrace), "tool event order/payload differs from upstream")
    finalResult : T.AgentToolResult<String> <- R.read(T.AgentToolResult<String>, resultValue)
    checkResult(mode, finalResult)
    C.dispose(EventValue(), Outcome(), sink)
    oldMessage : Ai.ToolResultMessage<String> <- R.dispose(Ai.ToolResultMessage<String>, value)
    oldResult : T.AgentToolResult<String> <- R.dispose(T.AgentToolResult<String>, resultValue)
    oldCall : Ai.ToolCall<Unit> <- R.dispose(Ai.ToolCall<Unit>, call)
    oldLog : List<&2, String> <- R.dispose(List<&2, String>, log)
    D.dispose(Unit, ready)
    D.dispose(Unit, release)
    D.dispose(Unit, completed)
