import Base
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-driver.bend as Progress
import ../packages/runtime/src/connection-driver.bend as Attempt
import ../packages/runtime/src/connection-driver.bend as Outcome
import ../packages/runtime/src/socket.bend as Connect
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/deadline.bend as Deadline
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./abortable-connect.bend as Endpoint

def modeName(mode: Progress.Mode) -> String:
  match mode:
    case Progress.Final{}: "final"
    case Progress.NonFinal{}: "timed"

def reasonName(reason: Abort.AbortReason<String>) -> String:
  match reason:
    case Abort.DefaultAbort{}: "default"
    case Abort.Supplied{why}: why

def errorName(error: Outcome.Error<String>) -> String:
  match error:
    case Outcome.SocketFailure{code, message}: "socket:" ++ U32.show(code) ++ ":" ++ message
    case Outcome.TimedOut{}: "timeout"
    case Outcome.Aborted{why}: "abort:" ++ reasonName(why)
    case Outcome.UnexpectedDefaultAbort{}: "unexpected"

def outcomeName(outcome: Result<&2, &2, Outcome.Error<String>, Unit>) -> String:
  match outcome:
    case Done{_}: "success"
    case Fail{error}: errorName(error)

def finalName(error: Progress.ProgressError<String>) -> String:
  match error:
    case Progress.ProgressNoAddresses{}: "empty"
    case Progress.Exhausted{}: "exhausted"
    case Progress.ProgressAborted{why}: "abort:" ++ reasonName(why)
    case Progress.ProgressUnexpectedDefaultAbort{}: "unexpected"

def diagnostic(reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<String>>>) -> String:
  match reason:
    case None{}: "none"
    case Some{Abort.Supplied{Deadline.Expired{}}}: "expiry"
    case Some{Abort.Supplied{Deadline.ParentAbort{why}}}: "parent:" ++ reasonName(why)
    case _: "unexpected"

def addressName(address: Connect.Address) -> String:
  match address:
    case Connect.V4{IPv4.Address{word}}: U32.show(word)
    case Connect.V6{_, _}: "ipv6"

def history(entries: List<&2, Driver.Entry<String>>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit, Unit{})
    case Driver.Entry{address, mode, outcome, deadline} <> rest:
      do IO<Unit>:
        IO.print("ENTRY " ++ addressName(address) ++ " " ++ modeName(mode) ++ " " ++ outcomeName(outcome) ++ " " ++ diagnostic(deadline))
        history(rest)

def failure(index: U32) -> Attempt.AttemptReport<String, Chan(Unit)>:
  Attempt.AttemptReport{Fail{Outcome.SocketFailure{index, "original"}}, Some{Abort.Supplied{Deadline.Expired{}}}}

def success() -> IO(Attempt.AttemptReport<String, Chan(Unit)>):
  do IO<Attempt.AttemptReport<String, Chan(Unit)>>:
    resource : Chan(Unit) <- Chan.new(Unit, 1)
    return Attempt.AttemptReport{Done{resource}, Some{Abort.Supplied{Deadline.Expired{}}}}

def choose(scenario: U32, index: U32, controller: Abort.AbortController<String>) -> IO(Attempt.AttemptReport<String, Chan(Unit)>):
  match scenario:
    case 1: success()
    case 2: IO.pure(Attempt.AttemptReport<String, Chan(Unit)>, Attempt.AttemptReport{Fail{Outcome.TimedOut{}}, Some{Abort.Supplied{Deadline.Expired{}}}})
    case 3: IO.pure(Attempt.AttemptReport<String, Chan(Unit)>, Attempt.AttemptReport{Fail{Outcome.Aborted{Abort.Supplied{"reported"}}}, Some{Abort.Supplied{Deadline.Expired{}}}})
    case 4: IO.pure(Attempt.AttemptReport<String, Chan(Unit)>, Attempt.AttemptReport{Fail{Outcome.UnexpectedDefaultAbort{}}, Some{Abort.Supplied{Deadline.Expired{}}}})
    case 5:
      do IO<Attempt.AttemptReport<String, Chan(Unit)>>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        return failure(index)
    case 6:
      do IO<Attempt.AttemptReport<String, Chan(Unit)>>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        success()
    case 8:
      do IO<Attempt.AttemptReport<String, Chan(Unit)>>:
        won : Bool <- Abort.abort(String, controller, None{})
        success()
    case _: IO.pure(Attempt.AttemptReport<String, Chan(Unit)>, failure(index))

def selected(target: Bool, scenario: U32, index: U32, controller: Abort.AbortController<String>) -> IO(Attempt.AttemptReport<String, Chan(Unit)>):
  match target:
    case True{}: choose(scenario, index, controller)
    case False{}: IO.pure(Attempt.AttemptReport<String, Chan(Unit)>, failure(index))

type Context is Data:
  Context{scenario: U32, target: U32, controller: Abort.AbortController<String>}

def fake(context: Context, address: Connect.Address, mode: Progress.Mode, signal: Abort.AbortSignal<String>) -> IO(Attempt.AttemptReport<String, Chan(Unit)>):
  match context address:
    case Context{scenario, target, controller} Connect.V4{IPv4.Address{+index}}:
      do IO<Attempt.AttemptReport<String, Chan(Unit)>>:
        IO.print("CALL " ++ U32.show(index) ++ " " ++ modeName(mode))
        selected(U32.is_eq(index, target), scenario, index, controller)
    case _ _: IO.die(Attempt.AttemptReport<String, Chan(Unit)>, 1, "unexpected injected address")

def release(resource: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Chan.close(Unit, resource)
    IO.print("RELEASE")

def taken(result: Result<&2, &1, Progress.ProgressError<String>, Chan(Unit)>) -> IO(Unit):
  match result:
    case Done{resource}:
      do IO<Unit>:
        Chan.close(Unit, resource)
        IO.print("RESULT success")
    case Fail{error}: IO.print("RESULT " ++ finalName(error))

def checked(report: Driver.Report<String, Chan(Unit)>) -> IO(Unit):
  match report:
    case Driver.Report{result, entries}:
      do IO<Unit>:
        history(entries)
        taken(result)

def addresses(count: Nat, +index: U32) -> List<&2, Connect.Address>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: Connect.V4{IPv4.Address{index}} <> addresses(rest, U32.add(index, 1))

def preabort(pre: Bool, controller: Abort.AbortController<String>) -> IO(Unit):
  match pre:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        won : Bool <- Abort.abort(String, controller, Some{"stop"})
        return Unit{}

def injected(scenario: U32, target: U32, count: U32, +controller: Abort.AbortController<String>) -> IO(Unit):
  do IO<Unit>:
    report : Driver.Report<String, Chan(Unit)> <- Driver.runWith(~Context, ~String, ~Chan(Unit), ~fake, ~release, Context{scenario, target, controller}, addresses(U32.to_nat(count), 1), Abort.signal(String, controller))
    checked(report)

def socketResult(result: Result<&2, &1, Progress.ProgressError<String>, Socket>) -> IO(Unit):
  match result:
    case Done{socket}:
      do IO<Unit>:
        Socket.close(socket)
        IO.print("RESULT success")
    case Fail{error}: IO.print("RESULT " ++ finalName(error))

def socketReport(report: Driver.Report<String, Socket>) -> IO(Unit):
  match report:
    case Driver.Report{result, entries}:
      do IO<Unit>:
        history(entries)
        socketResult(result)

def native(firstV6: Bool, secondV6: Bool, port: U32, signal: Abort.AbortSignal<String>) -> IO(Unit):
  do IO<Unit>:
    report : Driver.Report<String, Socket> <- Driver.run(~String, Driver.Options{port, 30}, Endpoint.address(firstV6) <> Endpoint.address(secondV6) <> Nil{}, signal)
    socketReport(report)

def dispatch(nativeMode: Bool, scenario: U32, +target: U32, count: U32, controller: Abort.AbortController<String>) -> IO(Unit):
  match nativeMode:
    case True{}: native(U32.is_eq(target, 6), U32.is_eq(target, 4), count, Abort.signal(String, controller))
    case False{}: injected(scenario, target, count, controller)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case +scenario <> target <> count <> Nil{}:
      do IO<Unit>:
        +controller : Abort.AbortController<String> <- Abort.new(String)
        preabort(U32.is_eq(Scalar.decimal(scenario, 0), 7), controller)
        dispatch(U32.is_eq(Scalar.decimal(scenario, 0), 10), Scalar.decimal(scenario, 0), Scalar.decimal(target, 0), Scalar.decimal(count, 0), controller)
        Abort.dispose(String, controller)
    case _: IO.die(Unit, 1, "expected scenario, target/family, count/port")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
