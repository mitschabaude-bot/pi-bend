import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/callback.bend as C

def Payload() -> Data: R.Ref<String>
def ErrorValue() -> Data: R.Ref<String>
def Outcome() -> Data: Result<&2, &2, ErrorValue(), Payload()>
def Prepared() -> Data: Result<&2, &2, ErrorValue(), Loop.PreparedToolCallArguments<Payload(), Payload()>>
def ExecuteInput() -> Data: T.ToolExecutionInput<Payload(), Unit, Unit>
def ExecuteOutput() -> Data: Result<&2, &2, ErrorValue(), T.AgentToolResult<Unit>>

type Environment is Data:
  Environment{mode: U32, original: Payload(), fresh: Payload(), call: T.AgentToolCall(Payload()), error: ErrorValue(), count: R.Ref<U32>}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def mutate(mode: U32, call: T.AgentToolCall(Payload()), fresh: Payload()) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case 1: IO.pure(Unit, Unit{})
    case 2: IO.pure(Unit, Unit{})
    case _: R.write(Ai.ToolCall<Payload()>, call, Ai.ToolCall{"new-id", "new-name", fresh, Some{"new-signature"}, Some{"new-namespace"}})

def returned(mode: U32, original: Payload(), fresh: Payload(), error: ErrorValue()) -> Outcome():
  match mode:
    case 5: Fail{error}
    case 2: Done{fresh}
    case 3: Done{fresh}
    case _: Done{original}

def prepare(environment: Environment, args: Payload()) -> IO(Outcome()):
  match environment:
    case Environment{+mode, +original, +fresh, call, error, count}:
      do IO<Outcome()>:
        assertion(R.same(String, original, args), "adapter did not receive original argument identity")
        R.modify(U32, Unit, count, old => (U32.add(old, 1), Unit{}))
        mutate(mode, call, fresh)
        return returned(mode, original, fresh, error)

def forbidden(unused: Unit, input: ExecuteInput()) -> IO(ExecuteOutput()):
  IO.die(ExecuteOutput(), 1, "argument preparation must not execute tools")

def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def payloadName(value: Payload(), fresh: Payload()) -> String:
  Bool.pick(String, R.same(String, value, fresh), "fresh", "old")

def render(value: Ai.ToolCall<Payload()>, fresh: Payload()) -> String:
  match value:
    case Ai.ToolCall{id, name, args, signature, namespace}: id ++ "|" ++ name ++ "|" ++ optional(signature) ++ "|" ++ optional(namespace) ++ "|" ++ payloadName(args, fresh)

def describe(outcome: Prepared(), original: T.AgentToolCall(Payload()), fresh: Payload(), expectedError: ErrorValue()) -> IO(String):
  match outcome:
    case Fail{error}:
      do IO<String>:
        assertion(R.same(String, error, expectedError), "adapter failure identity changed")
        return "failure"
    case Done{Loop.OriginalCall{+value}}:
      do IO<String>:
        assertion(R.same(Ai.ToolCall<Payload()>, value, original), "unchanged arguments must preserve original call identity")
        current : Ai.ToolCall<Payload()> <- R.read(Ai.ToolCall<Payload()>, value)
        return "same|" ++ render(current, fresh)
    case Done{Loop.ReplacedCall{+value}}:
      do IO<String>:
        assertion(Bool.not(R.same(Ai.ToolCall<Payload()>, value, original)), "different arguments require a fresh call")
        current : Ai.ToolCall<Payload()> <- R.dispose(Ai.ToolCall<Payload()>, value)
        return "replaced|" ++ render(current, fresh)

def run(+mode: U32, expected: String) -> IO(Unit):
  do IO<Unit>:
    +original : Payload() <- R.new(String, "same")
    +fresh : Payload() <- R.new(String, "same")
    +call : T.AgentToolCall(Payload()) <- R.new(Ai.ToolCall<Payload()>, Ai.ToolCall{"old-id", "old-name", original, Some{"old-signature"}, Some{"old-namespace"}})
    +error : ErrorValue() <- R.new(String, "failure")
    +count : R.Ref<U32> <- R.new(U32, 0)
    +adapter : C.Callback<Payload(), Outcome()> <- C.create(~Environment, ~Payload(), ~Outcome(), ~prepare, Environment{mode, original, fresh, call, error, count})
    +execute : C.Callback<ExecuteInput(), ExecuteOutput()> <- C.create(~Unit, ~ExecuteInput(), ~ExecuteOutput(), ~forbidden, Unit{})
    tool : T.AgentTool<Unit, Payload(), Unit, Payload(), Unit, ErrorValue()> = T.AgentTool{"tool", "description", Unit{}, None{}, "label", Bool.pick(Maybe<&2, C.Callback<Payload(), Outcome()>>, U32.is_eq(mode, 0), None{}, Some{adapter}), execute, None{}, None{}}
    outcome : Prepared() <- Loop.prepareToolCallArguments(Unit, Payload(), Unit, Payload(), Unit, ErrorValue(), tool, call, R.same(String))
    description : String <- describe(outcome, call, fresh, error)
    invocations : U32 <- R.read(U32, count)
    current : Ai.ToolCall<Payload()> <- R.read(Ai.ToolCall<Payload()>, call)
    originalArgs : Payload() = Loop.callArguments(Payload(), current)
    +actual : String = description ++ "|calls:" ++ U32.show(invocations) ++ "|original:" ++ payloadName(originalArgs, fresh)
    assertion(String.eq(actual, expected), "tool-call preparation differs from upstream: " ++ actual)
    C.dispose(Payload(), Outcome(), adapter)
    C.dispose(ExecuteInput(), ExecuteOutput(), execute)
    oldCall : Ai.ToolCall<Payload()> <- R.dispose(Ai.ToolCall<Payload()>, call)
    oldCount : U32 <- R.dispose(U32, count)
    oldError : String <- R.dispose(String, error)
    old : String <- R.dispose(String, original)
    new : String <- R.dispose(String, fresh)
    return Unit{}

def adaptText(unused: Unit, raw: String) -> IO(Result<&2, &2, String, U32>):
  do IO<Result<&2, &2, String, U32>>:
    assertion(String.eq(raw, "raw"), "typed adapter input changed")
    return Done{7}

def different(prepared: U32, raw: String) -> Bool: False{}

def requireOriginal(outcome: Result<&2, &2, String, Loop.PreparedToolCallArguments<String, U32>>, expected: T.AgentToolCall(String)) -> IO(Unit):
  match outcome:
    case Done{Loop.OriginalCall{value}}: assertion(R.same(Ai.ToolCall<String>, value, expected), "absent adapter lost raw call type/identity")
    case _: IO.die(Unit, 1, "unexpected typed original branch")

def checkAdapted(current: Ai.ToolCall<U32>) -> IO(Unit):
  match current:
    case Ai.ToolCall{id, name, args, None{}, None{}}: assertion(String.eq(id, "id") && String.eq(name, "tool") && U32.is_eq(args, 7), "cross-type call projection changed fields")
    case _: IO.die(Unit, 1, "optional metadata changed")

def requireAdapted(outcome: Result<&2, &2, String, Loop.PreparedToolCallArguments<String, U32>>) -> IO(Unit):
  match outcome:
    case Done{Loop.ReplacedCall{value}}:
      do IO<Unit>:
        current : Ai.ToolCall<U32> <- R.dispose(Ai.ToolCall<U32>, value)
        checkAdapted(current)
    case _: IO.die(Unit, 1, "typed replacement branch missing")

def crossType() -> IO(Unit):
  do IO<Unit>:
    +call : T.AgentToolCall(String) <- R.new(Ai.ToolCall<String>, Ai.ToolCall{"id", "tool", "raw", None{}, None{}})
    original : Result<&2, &2, String, Loop.PreparedToolCallArguments<String, U32>> <- Loop.prepareArgumentsWith(String, U32, String, None{}, call, different)
    requireOriginal(original, call)
    +adapter : C.Callback<String, Result<&2, &2, String, U32>> <- C.create(~Unit, ~String, ~Result<&2, &2, String, U32>, ~adaptText, Unit{})
    replacement : Result<&2, &2, String, Loop.PreparedToolCallArguments<String, U32>> <- Loop.prepareArgumentsWith(String, U32, String, Some{adapter}, call, different)
    requireAdapted(replacement)
    old : Ai.ToolCall<String> <- R.dispose(Ai.ToolCall<String>, call)
    C.dispose(String, Result<&2, &2, String, U32>, adapter)
    IO.print("PASS distinct raw/prepared argument types without reference casts")
