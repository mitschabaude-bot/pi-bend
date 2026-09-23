import Base
import ../src/agent.bend as H
import ../src/agent.bend as Binding
import ./agent-loop-config.bend as ConfigFixture
import ../src/agent.bend as Life
import ../src/types.bend as T
import ../src/agent.bend as Failure
import ../../runtime/src/f64.bend as F
import ../../ai/src/types.bend as Ai
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/ref.bend as R
import ./agent-queues.bend as Fixture
import ./message-events.bend as Test
import ../../runtime/src/schema-value.bend as Schema

def Turn() -> Data: T.AgentTurnContext<Unit, Unit, String, String>
def Update() -> Data: T.AgentLoopTurnUpdate<Unit, Unit, String, String>
def Options() -> Data: H.Hooks<Turn(), Update(), String>
def Adapters() -> Data: H.Adapters<Turn(), Update(), String>
def PrepareResult() -> Data: H.PrepareResult(Update(), String)
type Environment is Data:
  Environment{label: String, fail: Bool, log: R.Ref<String>}
type Handlers is Data:
  Handlers{legacy: H.LegacyHook(Update(), String), context: H.ContextHook(Turn(), Update(), String)}
def marker(turn: Turn()) -> String:
  match turn:
    case T.AgentTurnContext{_, Nil{}, T.AgentContext{T.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{+text}, _}}} <> Nil{}, Some{Nil{}}}, T.CustomMessage{other} <> Nil{}}:
      Bool.pick(String, String.eq(text, other), text, "wrong context")
    case _: "wrong context"
def turn(+text: String) -> Turn():
  T.AgentTurnContext{Ai.AssistantMessage{Nil{}, "api", "provider", "model", None{}, None{}, None{}, None{}, Failure.emptyUsage(), Ai.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}, Nil{}, T.AgentContext{Fixture.user(text) <> Nil{}, Some{Nil{}}}, T.CustomMessage{text} <> Nil{}}
def signalKey(signal: Maybe<&2, H.HooksSignal()>) -> IO(String):
  match signal:
    case None{}: IO.pure(String, "none")
    case Some{value}:
      do IO<String>:
        aborted : Bool <- Abort.aborted(Unit, value)
        return Bool.pick(String, aborted, "aborted", "live")
def record(log: R.Ref<String>, label: String, context: String, signal: Maybe<&2, H.HooksSignal()>) -> IO(Unit):
  do IO<Unit>:
    state : String <- signalKey(signal)
    R.modify(String, Unit, log, previous => (previous ++ label ++ "@" ++ context ++ "@" ++ state ++ ";", Unit{}))
def preparation(environment: Environment, context: String, signal: Maybe<&2, H.HooksSignal()>) -> IO(PrepareResult()):
  match environment:
    case Environment{+label, fail, log}:
      do IO<PrepareResult()>:
        record(log, label, context, signal)
        return Bool.pick(PrepareResult(), fail, Fail{label}, Done{Some{T.AgentLoopTurnUpdate{None{}, Some{T.CustomMessage{label} <> Nil{}}, None{}, Some{Ai.Off{}}}}})
def legacyBody(environment: Environment, signal: Maybe<&2, H.HooksSignal()>) -> IO(PrepareResult()): preparation(environment, "-", signal)
def contextBody(environment: Environment, input: T.ToolHookInput<Turn()>) -> IO(PrepareResult()):
  match input:
    case T.ToolHookInput{context, signal}: preparation(environment, marker(context), signal)
def handlers(+version: String, +fail: Bool, +log: R.Ref<String>) -> IO(Handlers):
  do IO<Handlers>:
    legacy : H.LegacyHook(Update(), String) <- C.create(~Environment, ~Maybe<&2, H.HooksSignal()>, ~PrepareResult(), ~legacyBody, Environment{"legacy" ++ version, fail, log})
    context : H.ContextHook(Turn(), Update(), String) <- C.create(~Environment, ~T.ToolHookInput<Turn()>, ~PrepareResult(), ~contextBody, Environment{"context" ++ version, fail, log})
    return Handlers{legacy, context}
def options(handlers: Handlers, +mode: U32) -> Options():
  match handlers:
    case Handlers{legacy, context}: H.Hooks{Bool.pick(Maybe<&2, H.LegacyHook(Update(), String)>, U32.is_eq(mode, 1) || U32.is_eq(mode, 3), Some{legacy}, None{}), Bool.pick(Maybe<&2, H.ContextHook(Turn(), Update(), String)>, U32.is_ge(mode, 2), Some{context}, None{})}
def prepareKey(result: PrepareResult()) -> String:
  match result:
    case Fail{error}: "error:" ++ error
    case Done{None{}}: "none"
    case Done{Some{T.AgentLoopTurnUpdate{None{}, Some{T.CustomMessage{label} <> Nil{}}, None{}, Some{Ai.Off{}}}}}: label
    case _: "wrong update"
def callPrepare(callback: Maybe<&2, C.Callback<Turn(), PrepareResult()>>, context: Turn()) -> IO(String):
  match callback:
    case None{}: IO.pure(String, "missing")
    case Some{value}:
      do IO<String>:
        result : PrepareResult() <- C.call(Turn(), PrepareResult(), value, context)
        return prepareKey(result)
def checkpoint(adapters: Adapters(), +name: String) -> IO(String):
  match adapters:
    case H.Adapters{prepare}: callPrepare(prepare, turn(name))
def disposeHandlers(handlers: Handlers) -> IO(Unit):
  match handlers:
    case Handlers{legacy, context}:
      do IO<Unit>:
        C.dispose(Maybe<&2, H.HooksSignal()>, PrepareResult(), legacy)
        C.dispose(T.ToolHookInput<Turn()>, PrepareResult(), context)
def claim(result: Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Unit>>) -> IO(Life.ActiveRun):
  match result:
    case Done{Life.Claimed{run, _}}: IO.pure(Life.ActiveRun, run)
    case _: IO.die(Life.ActiveRun, 1, "fixture could not start run")
def fromConfig(config: ConfigFixture.Config()) -> Adapters():
  match config:
    case T.AgentLoopConfig{_, _, _, _, _, _, _, prepare, _, _, _, _, _}: H.Adapters{prepare}
def throughConfig(adapters: Adapters(), converter: C.Callback<ConfigFixture.Messages(), ConfigFixture.Converted()>) -> Adapters():
  fromConfig(Binding.applyHooks(Unit, Unit, String, String, Unit, ConfigFixture.base(converter), adapters))
def scenario(initial: U32, later: U32, +fail: Bool, +expected: String) -> IO(Unit):
  do IO<Unit>:
    +converter : C.Callback<ConfigFixture.Messages(), ConfigFixture.Converted()> <- C.create(~Unit, ~ConfigFixture.Messages(), ~ConfigFixture.Converted(), ~ConfigFixture.converterBody, Unit{})
    +log : R.Ref<String> <- R.new(String, "")
    +a : Handlers <- handlers("A", fail, log)
    +b : Handlers <- handlers("B", fail, log)
    +current : R.Ref<Options()> <- R.new(Options(), options(a, initial))
    +lifecycle : Life.Lifecycle<Unit> <- Life.newLifecycle(Unit, Unit{})
    created : Adapters() <- H.createHooks(~Unit, ~Turn(), ~Update(), ~String, lifecycle, current)
    +original : Adapters() = throughConfig(created, converter)
    first : String <- checkpoint(original, "initial")
    claimed : Result<&2, &2, Life.ClaimError<String>, Life.Claimed<Unit>> <- Life.claimLifecycle(Unit, String, Unit, lifecycle, state => Done{Life.Prepared{state, Unit{}}})
    run : Life.ActiveRun <- claim(claimed)
    R.write(Options(), current, options(b, later))
    second : String <- checkpoint(original, "active")
    createdFresh : Adapters() <- H.createHooks(~Unit, ~Turn(), ~Update(), ~String, lifecycle, current)
    +fresh : Adapters() = throughConfig(createdFresh, converter)
    third : String <- checkpoint(fresh, "fresh")
    Life.abortLifecycle(Unit, lifecycle)
    fourth : String <- checkpoint(original, "aborted")
    finished : Bool <- Life.finishOwnedRun(Unit, lifecycle, run, state => state)
    Test.assertion(finished, "fixture finishes its run")
    R.write(Options(), current, options(b, 0))
    fifth : String <- checkpoint(original, "idle")
    trace : String <- R.read(String, log)
    +actual : String = trace ++ "#" ++ first ++ "," ++ second ++ "," ++ third ++ "," ++ fourth ++ "," ++ fifth
    Test.assertion(String.eq(actual, expected), "hook adaptation differs: " ++ actual ++ " != " ++ expected)
    H.disposeHooks(Turn(), Update(), String, original)
    H.disposeHooks(Turn(), Update(), String, fresh)
    old : Options() <- R.dispose(Options(), current)
    Life.disposeLifecycle(Unit, lifecycle)
    disposeHandlers(a)
    disposeHandlers(b)
    C.dispose(ConfigFixture.Messages(), ConfigFixture.Converted(), converter)
    oldLog : String <- R.dispose(String, log)
    return Unit{}
