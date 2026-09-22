import Base
import ../packages/runtime/src/connection-driver.bend as Attempt
import ../packages/runtime/src/connection-driver.bend as Outcome
import ../packages/runtime/src/abortable-connect.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ./abortable-connect.bend as Endpoint
import ./connect-owned.bend as Test
import ../packages/runtime/test/utf8-runner.bend as Scalar

def failure(+mode: U32, expected: U32, error: Outcome.Error<String>) -> IO(Unit):
  match error:
    case Outcome.SocketFailure{code, _}: Test.assertion(U32.is_eq(mode, 1) && U32.is_eq(code, expected), "socket error")
    case Outcome.Aborted{Abort.Supplied{reason}}: Test.assertion((U32.is_eq(mode, 2) || U32.is_eq(mode, 5)) && String.eq(reason, "stop"), "parent reason")
    case Outcome.Aborted{Abort.DefaultAbort{}}: Test.assertion(U32.is_eq(mode, 3), "default parent")
    case Outcome.TimedOut{}: Test.assertion(U32.is_eq(mode, 4), "timeout")
    case Outcome.UnexpectedDefaultAbort{}: IO.die(Unit, 1, "unexpected child default")

def diagnostic(timed: Bool, +mode: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> IO(Unit):
  match timed reason:
    case False{} None{}: IO.pure(Unit, Unit{})
    case True{} None{}: Test.assertion(U32.is_lt(mode, 2), "missing deadline reason")
    case True{} Some{Abort.Supplied{Deadline.Expired{}}}: Test.assertion(U32.is_eq(mode, 4), "wrong expiry")
    case True{} Some{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{why}}}}: Test.assertion((U32.is_eq(mode, 2) || U32.is_eq(mode, 5)) && String.eq(why, "stop"), "inherited reason")
    case True{} Some{Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}}: Test.assertion(U32.is_eq(mode, 3), "inherited default")
    case _ _: IO.die(Unit, 1, "unexpected diagnostic")

def socketResult(mode: U32, expected: U32, result: Result<&2, &1, Outcome.Error<String>, Socket>) -> IO(Unit):
  match result:
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        Test.assertion(U32.is_eq(mode, 0), "unexpected success")
    case Fail{error}: failure(mode, expected, error)

def checked(+timed: Bool, +mode: U32, expected: U32, report: Attempt.AttemptReport<String, Socket>) -> IO(Unit):
  match report:
    case Attempt.AttemptReport{result, reason}:
      do IO<Unit>:
        diagnostic(timed, mode, reason)
        socketResult(mode, expected, result)

def duration(short: Bool) -> U32:
  match short:
    case True{}: 30
    case False{}: 10000

def once(timed: Bool, address: Connect.Address, port: U32, parent: Abort.AbortSignal<String>, mode: U32) -> IO(Attempt.AttemptReport<String, Socket>):
  match timed:
    case False{}: Attempt.final(~String, address, port, parent)
    case True{}: Attempt.timed(~String, address, port, parent, duration(U32.is_eq(mode, 4)))

def repeat(count: Nat, +timed: Bool, +mode: U32, +address: Connect.Address, +port: U32, +code: U32, +signal: Abort.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Attempt.AttemptReport<String, Socket> <- once(timed, address, port, signal, mode)
        checked(timed, mode, code, result)
        repeat(rest, timed, mode, address, port, code, signal)

def preabort(supplied: Bool, default: Bool, controller: Abort.AbortController<String>) -> IO(Unit):
  match supplied default:
    case True{} _:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        return Unit{}
    case False{} True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, None{})
        return Unit{}
    case False{} False{}: IO.pure(Unit, Unit{})

def run(cancel: Bool, +timed: Bool, +mode: U32, address: Connect.Address, port: U32, code: U32, +controller: Abort.AbortController<String>) -> IO(Unit):
  match cancel:
    case True{}:
      do IO<Unit>:
        task : Chan(Attempt.AttemptReport<String, Socket>) <- IO.fork(Attempt.AttemptReport<String, Socket>, once(timed, address, port, Abort.signal(String, controller), mode))
        IO.sleep(10)
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        result : Attempt.AttemptReport<String, Socket> <- IO.join(Attempt.AttemptReport<String, Socket>, task)
        checked(timed, mode, code, result)
    case False{}:
      do IO<Unit>:
        preabort(U32.is_eq(mode, 2), U32.is_eq(mode, 3), controller)
        repeat(16n, timed, mode, address, port, code, Abort.signal(String, controller))

# Inject settlement to test late diagnostics without depending on scheduler timing.
def fakeResult(success: Bool) -> Result<&2, &1, Connect.Error<Deadline.Cause<String>>, Unit>:
  match success:
    case True{}: Done{Unit{}}
    case False{}: Fail{Connect.SocketError{123, "original"}}

def fake(mode: U32, signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Result<&2, &1, Connect.Error<Deadline.Cause<String>>, Unit>):
  do IO<Result<&2, &1, Connect.Error<Deadline.Cause<String>>, Unit>>:
    won : Bool <- Abort.abort(Deadline.Cause<String>, Abort.AbortController{signal}, Some{Deadline.Expired{}})
    return fakeResult(U32.is_eq(mode, 6))

def fakeCheck(mode: U32, report: Attempt.AttemptReport<String, Unit>) -> IO(Unit):
  match report:
    case Attempt.AttemptReport{Done{Unit{}}, Some{Abort.Supplied{Deadline.Expired{}}}}: Test.assertion(U32.is_eq(mode, 6), "late success")
    case Attempt.AttemptReport{Fail{Outcome.SocketFailure{code, message}}, Some{Abort.Supplied{Deadline.Expired{}}}}: Test.assertion(U32.is_eq(mode, 7) && U32.is_eq(code, 123) && String.eq(message, "original"), "late failure")
    case _: IO.die(Unit, 1, "settled result overwritten or diagnostic lost")

def injected(+mode: U32, signal: Abort.AbortSignal<String>) -> IO(Unit):
  do IO<Unit>:
    report : Attempt.AttemptReport<String, Unit> <- Attempt.timedWith(~U32, ~String, ~Unit, ~fake, mode, signal, 10000)
    fakeCheck(mode, report)

def dispatch(native: Bool, timed: Bool, +mode: U32, family: Bool, port: U32, code: U32, controller: Abort.AbortController<String>) -> IO(Unit):
  match native:
    case True{}: run(U32.is_eq(mode, 5), timed, mode, Endpoint.address(family), port, code, controller)
    case False{}: injected(mode, Abort.signal(String, controller))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case timed <> +mode <> family <> port <> code <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        dispatch(U32.is_lt(Scalar.decimal(mode, 0), 6), String.eq(timed, "1"), Scalar.decimal(mode, 0), String.eq(family, "6"), Scalar.decimal(port, 0), Scalar.decimal(code, 0), controller)
        Abort.dispose(String, controller)
        IO.print("PASS connection attempt")
    case _: IO.die(Unit, 1, "expected timed, mode, family, port, error code")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
