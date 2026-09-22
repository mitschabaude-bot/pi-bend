import Base
import ../packages/runtime/src/dns-transport.bend as Attempt
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deferred.bend as Deferred
import ../packages/runtime/test/utf8-runner.bend as Scalar

def show(value: Attempt.End<String>) -> String:
  match value:
    case Attempt.Active{}: "active"
    case Attempt.AttemptExpired{}: "attempt"
    case Attempt.ParentAborted{Abort.Supplied{Deadline.Expired{}}}: "total"
    case Attempt.ParentAborted{Abort.Supplied{Deadline.ParentAbort{Abort.Supplied{why}}}}: "caller:" ++ why
    case Attempt.ParentAborted{Abort.Supplied{Deadline.ParentAbort{Abort.DefaultAbort{}}}}: "caller:default"
    case _: "unexpected"

def stopped(controller: Abort.AbortController<String>, default: Bool) -> IO(Unit):
  do IO<Unit>:
    won : Bool <- Abort.abort(String, controller, Bool.pick(Maybe<&2, String>, default, None{}, Some{"stop"}))
    return Unit{}

def before(mode: String, controller: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "pre": stopped(controller, False{})
    case "pre-default": stopped(controller, True{})
    case _: IO.pure(Unit, Unit{})

def later(mode: String, controller: Abort.AbortController<String>) -> IO(Unit):
  match mode:
    case "later":
      do IO<Unit>:
        IO.sleep(20)
        stopped(controller, False{})
    case _: IO.pure(Unit, Unit{})

def observed(observation: Deferred.Observation<Abort.AbortReason<Deadline.Cause<Deadline.Cause<String>>>>) -> IO(Unit):
  match observation:
    case Deferred.Observation{ticket, cancellation}:
      do IO<Unit>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<String>>>> <- Deferred.wait(Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<String>>>>, ticket)
        removed : Bool <- Deferred.cancel(Abort.AbortReason<Deadline.Cause<Deadline.Cause<String>>>, cancellation)
        IO.print("observed:" ++ show(Attempt.classify(String, reason)))

def await(mode: String, signal: Abort.AbortSignal<Deadline.Cause<Deadline.Cause<String>>>) -> IO(Unit):
  match mode:
    case "active": IO.pure(Unit, Unit{})
    case "maximum": IO.pure(Unit, Unit{})
    case _:
      do IO<Unit>:
        observation : Deferred.Observation<Abort.AbortReason<Deadline.Cause<Deadline.Cause<String>>>> <- Abort.observe(Deadline.Cause<Deadline.Cause<String>>, signal)
        observed(observation)

def borrowed(mode: String, pair: Deadline.Scope<Deadline.Cause<String>> & Abort.AbortSignal<Deadline.Cause<Deadline.Cause<String>>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        await(mode, signal)
        ended : Attempt.End<String> <- Attempt.closeUdpAttemptScope(String, scope)
        IO.print("closed:" ++ show(ended))

def created(mode: String, result: Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<String>>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("invalid")
    case Done{scope}: borrowed(mode, Deadline.borrow(Deadline.Cause<String>, scope))

def duration(mode: String) -> Timeout.Duration:
  match mode:
    case "invalid": Timeout.Duration{40n}
    case "maximum": Timeout.Duration{39n}
    case _: Timeout.Duration{0n}

def loop(count: Nat, +mode: String, +signal: Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match count:
    case Zero{}: IO.pure(Unit, Unit{})
    case Succ{rest}:
      do IO<Unit>:
        result : Result<&2, &1, Timeout.MillisecondsError, Deadline.Scope<Deadline.Cause<String>>> <- Attempt.createUdpAttemptScope(String, duration(mode), signal)
        created(mode, result)
        loop(rest, mode, signal)

def total(mode: String, count: Nat, pair: Deadline.Scope<String> & Abort.AbortSignal<Deadline.Cause<String>>) -> IO(Unit):
  match pair:
    case (scope, signal):
      do IO<Unit>:
        loop(count, mode, signal)
        ended : Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>> <- Deadline.close(String, scope)
        return Unit{}

def run(+mode: String, count: Nat) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<String> <- Abort.new(String)
    before(mode, controller)
    task : Chan(Unit) <- IO.fork(Unit, later(mode, controller))
    scope : Deadline.Scope<String> <- Deadline.create(String, Bool.pick(U32, String.eq(mode, "total"), 20, 5000), Abort.signal(String, controller))
    total(mode, count, Deadline.borrow(String, scope))
    IO.join(Unit, task)
    Abort.dispose(String, controller)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> count <> Nil{}: run(mode, U32.to_nat(Scalar.decimal(count, 0)))
    case _: IO.die(Unit, 1, "expected mode and count")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
