import Base
import ../packages/ai/src/api/openai-responses-driver.bend as Driver
import ../packages/ai/src/api/openai-responses-lifecycle.bend as Life
import ../packages/ai/src/types.bend as T
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/f64.bend as F

def render(provider: String, cause: String) -> String: provider ++ ": " ++ cause

def detail(value: T.AssistantMessage<Unit, Unit>) -> String:
  match value:
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, None{}, _, _, _}: "none"
    case T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, Some{text}, _, _, _}: text

def message() -> T.AssistantMessage<Unit, Unit>:
  T.AssistantMessage{Nil{}, "openai-responses", "openai", "test", None{}, None{}, None{}, None{}, T.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), T.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, T.Stop{}, None{}, None{}, None{}, None{}, F.fromU32(0)}

def emit(+mode: U32, value: T.AssistantMessageEvent<Unit, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match value:
    case T.Start{_}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("start")
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 4), Fail{"start"}, Done{Unit{}})
    case T.StreamDone{_, output}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("done:" ++ detail(output))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 5), Fail{"delivery"}, Done{Unit{}})
    case T.StreamError{_, output}:
      do IO<Result<&2, &2, String, Unit>>:
        IO.print("error:" ++ detail(output))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 6), Fail{"delivery"}, Done{Unit{}})
    case _: IO.pure(Result<&2, &2, String, Unit>, Fail{"unexpected event"})

def aborted(environment: Unit, input: Unit) -> IO(Bool): IO.pure(Bool, False{})
def close(environment: Unit, output: T.AssistantMessage<Unit, Unit>) -> IO(Unit): IO.print("close:" ++ detail(output))
def acquire(mode: U32) -> IO(Result<&2, &1, String, Unit>):
  IO.pure(Result<&2, &1, String, Unit>, Bool.pick(Result<&2, &1, String, Unit>, U32.is_eq(mode, 1), Fail{"request"}, Done{Unit{}}))
def process(+mode: U32, owner: Unit, output: T.AssistantMessage<Unit, Unit>) -> IO(Life.Processed<Unit, Unit, String>):
  IO.pure(Life.Processed<Unit, Unit, String>, Life.Processed{output, Bool.pick(Maybe<&2, String>, Bool.or(U32.is_eq(mode, 2), U32.is_eq(mode, 6)), Some{"processing"}, None{}), Bool.pick(Maybe<&2, String>, U32.is_eq(mode, 3), Some{"cleanup"}, None{})})
def release(owner: Unit) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    IO.print("release")
    return Done{Unit{}}
def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "none"
    case Some{text}: text

def report(value: Life.RunResult<Unit, Unit, String>) -> IO(Unit):
  match value:
    case Life.RunResult{terminal, cleanup, delivery}: IO.print("result:" ++ detail(Life.message(Unit, Unit, String, terminal)) ++ ":" ++ optional(cleanup) ++ ":" ++ optional(delivery))

def run(provider: String, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print("case:" ++ U32.show(mode))
    +sink : C.Callback<T.AssistantMessageEvent<Unit, Unit>, Result<&2, &2, String, Unit>> <- C.create(~U32, ~T.AssistantMessageEvent<Unit, Unit>, ~Result<&2, &2, String, Unit>, ~(m => value => emit(m, value)), mode)
    +signal : C.Callback<Unit, Bool> <- C.create(~Unit, ~Unit, ~Bool, ~aborted, Unit{})
    +finish : C.Callback<T.AssistantMessage<Unit, Unit>, Unit> <- C.create(~Unit, ~T.AssistantMessage<Unit, Unit>, ~Unit, ~close, Unit{})
    result : Life.RunResult<Unit, Unit, String> <- Driver.runWithContext(~String, ~String, ~render, Unit, Unit, Unit, Driver.Effects{sink, signal, finish}, message(), acquire(mode), process(mode), release, provider)
    report(result)
    C.dispose(T.AssistantMessageEvent<Unit, Unit>, Result<&2, &2, String, Unit>, sink)
    C.dispose(Unit, Bool, signal)
    C.dispose(T.AssistantMessage<Unit, Unit>, Unit, finish)

def cases(+provider: String) -> IO(Unit):
  do IO<Unit>:
    run(provider, 0)
    run(provider, 1)
    run(provider, 2)
    run(provider, 3)
    run(provider, 4)
    run(provider, 5)
    run(provider, 6)
def arguments(values: List<String>) -> IO(Unit):
  match values:
    case provider <> Nil{}: cases(provider)
    case _: IO.die(Unit, 1, "expected provider name")
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
