import Base
import ../packages/ai/src/utils/provider-owned-acquire.bend as A
import ../packages/runtime/src/ref.bend as R
import ../packages/runtime/test/utf8-runner.bend as Scalar

type Runtime is Type:
  Runtime{token: R.Ref<U32>}
type Response is Type:
  Response{token: R.Ref<U32>}

def prepared(mode: U32, value: U32) -> IO(Result<&2, &2, String, U32>):
  do IO<Result<&2, &2, String, U32>>:
    IO.print("prepare")
    return Bool.pick(Result<&2, &2, String, U32>, U32.is_eq(mode, 0), Fail{"payload fixture"}, Done{value})

def initialized(fail: Bool) -> IO(Result<&2, &1, String, Runtime>):
  match fail:
    case True{}: IO.pure(Result<&2, &1, String, Runtime>, Fail{"initialization fixture"})
    case False{}:
      do IO<Result<&2, &1, String, Runtime>>:
        token : R.Ref<U32> <- R.new(U32, 11)
        return Done{Runtime{token}}

def initialize(mode: U32) -> IO(Result<&2, &1, String, Runtime>):
  do IO<Result<&2, &1, String, Runtime>>:
    IO.print("initialize")
    initialized(U32.is_eq(mode, 1))

def acquired(runtime: Runtime, fail: Bool) -> IO(Runtime & Result<&2, &1, String, Response>):
  match fail:
    case True{}: IO.pure(Runtime & Result<&2, &1, String, Response>, (runtime, Fail{"request fixture"}))
    case False{}:
      do IO<Runtime & Result<&2, &1, String, Response>>:
        token : R.Ref<U32> <- R.new(U32, 22)
        return (runtime, Done{Response{token}})

def acquire(mode: U32, payload: U32, runtime: Runtime) -> IO(Runtime & Result<&2, &1, String, Response>):
  do IO<Runtime & Result<&2, &1, String, Response>>:
    IO.print("request:" ++ U32.show(payload))
    acquired(runtime, U32.is_eq(mode, 2))

def retire(runtime: Runtime) -> IO(Unit):
  match runtime:
    case Runtime{token}:
      do IO<Unit>:
        value : U32 <- R.dispose(U32, token)
        IO.print("runtime-close:" ++ U32.show(value))

def close(mode: U32, response: Response) -> IO(Result<&2, &2, String, Unit>):
  match response:
    case Response{token}:
      do IO<Result<&2, &2, String, Unit>>:
        value : U32 <- R.dispose(U32, token)
        IO.print("response-close:" ++ U32.show(value))
        return Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(mode, 4), Fail{"close fixture"}, Done{Unit{}})

def released(value: Result<&2, &2, String, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.print("released")
    case Fail{cause}: IO.print("release-error:" ++ cause)

def received(mode: U32, result: Result<&2, &1, A.Error<String, String>, A.Owner<Runtime, Response>>) -> IO(Unit):
  match result:
    case Fail{A.InitializationFailure{cause}}: IO.print("init-error:" ++ cause)
    case Fail{A.AcquisitionFailure{cause}}: IO.print("request-error:" ++ cause)
    case Done{owner}:
      do IO<Unit>:
        IO.print("acquired")
        result : Result<&2, &2, String, Unit> <- A.release(String, Runtime, Response, close(mode), retire, owner)
        released(result)

def run(+mode: U32, value: U32) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &1, A.Error<String, String>, A.Owner<Runtime, Response>> <- A.run(U32, String, String, Runtime, Response, prepared(mode, value), initialize(mode), acquire(mode), retire)
    received(mode, result)

def cases(values: List<String>) -> IO(Unit):
  match values:
    case mode <> value <> rest:
      do IO<Unit>:
        run(Scalar.decimal(mode, 0), Scalar.decimal(value, 0))
        cases(rest)
    case Nil{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "expected mode/value pairs")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
