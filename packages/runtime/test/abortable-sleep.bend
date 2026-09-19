import Base
import ../src/abort.bend as A
import ../src/abortable-sleep.bend as S

def expectDone(value: Result<&2, &2, A.AbortReason<String>, Unit>) -> IO(Unit):
  match value:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "unexpected sleep cancellation")

def expectReason(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "wrong sleep cancellation reason")

def expectCancelled(value: Result<&2, &2, A.AbortReason<String>, Unit>) -> IO(Unit):
  match value:
    case Fail{A.Supplied{why}}: expectReason(String.eq(why, "stop"))
    case _: IO.die(Unit, 1, "expected sleep cancellation")

def complete(count: Nat, +signal: A.AbortSignal<String>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 1, signal)
        expectDone(result)
        complete(rest, signal)

def main() -> IO(Unit):
  do IO<Unit>:
    +controller : A.AbortController<String> <- A.new(String)
    complete(32n, A.signal(String, controller))
    zero : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 0, A.signal(String, controller))
    expectDone(zero)
    task : Chan(Result<&2, &2, A.AbortReason<String>, Unit>) <- IO.fork(Result<&2, &2, A.AbortReason<String>, Unit>, S.sleep(String, 60000, A.signal(String, controller)))
    IO.sleep(5)
    won : Bool <- A.abort(String, controller, Some{"stop"})
    cancelled : Result<&2, &2, A.AbortReason<String>, Unit> <- IO.join(Result<&2, &2, A.AbortReason<String>, Unit>, task)
    expectCancelled(cancelled)
    pre : Result<&2, &2, A.AbortReason<String>, Unit> <- S.sleep(String, 60000, A.signal(String, controller))
    expectCancelled(pre)
    A.dispose(String, controller)
    IO.print("PASS abortable sleep")
