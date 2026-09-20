import Base
import ./connection-progress.bend as Progress
import ./connection-attempt.bend as Attempt
import ./connection-attempt-result.bend as Outcome
import ./abortable-connect.bend as Connect
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Entry<-Reason: Data> is Data:
  Entry{address: Connect.Address, mode: Progress.Mode, outcome: Result<&2, &2, Outcome.Error<Reason>, Unit>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Report<-Reason: Data, -Value: Type> is Type:
  Report{result: Result<&2, &1, Progress.Error<Reason>, Value>, attempts: List<&2, Entry<Reason>>}

type State<-Reason: Data, -Value: Type> is Type:
  Active{reversed: List<&2, Entry<Reason>>}
  Finished{report: Report<Reason, Value>}

def finish(-Reason: Data, -Value: Type, result: Result<&2, &1, Progress.Error<Reason>, Value>, reversed: List<&2, Entry<Reason>>) -> Report<Reason, Value>:
  Report{result, List.reverse(&2, Entry<Reason>, reversed)}

def empty(-Reason: Data, -Value: Type, history: List<&2, Entry<Reason>>) -> Report<Reason, Value>:
  match history:
    case Nil{}: finish(Reason, Value, Fail{Progress.NoAddresses{}}, Nil{})
    case first <> rest: finish(Reason, Value, Fail{Progress.Exhausted{}}, first <> rest)

# The connector closes all borrowed tasks before returning. Release consumes
# an owned success rejected by the parent-cancellation observation boundary.
def settle(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), history: List<&2, Entry<Reason>>, result: Result<&2, &1, Outcome.Error<Reason>, Value>, decision: Progress.Decision<Reason>) -> IO(State<Reason, Value>):
  match result decision:
    case Done{value} Progress.Accept{}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Done{value}, history)})
    case Done{value} Progress.Stop{error}:
      do IO<State<Reason, Value>>:
        release(value)
        return Finished{finish(Reason, Value, Fail{error}, history)}
    case Fail{_} Progress.Stop{error}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Fail{error}, history)})
    case Fail{_} Progress.Advance{}: IO.pure(State<Reason, Value>, Active{history})
    case Done{value} Progress.Advance{}:
      do IO<State<Reason, Value>>:
        release(value)
        IO.die(State<Reason, Value>, 1, "invalid connection decision")
    case Fail{_} Progress.Accept{}: IO.die(State<Reason, Value>, 1, "invalid connection decision")

def observed(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), parent: Abort.AbortSignal<Reason>, address: Connect.Address, mode: Progress.Mode, history: List<&2, Entry<Reason>>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>, pair: Result<&2, &1, Outcome.Error<Reason>, Value> & Result<&2, &2, Outcome.Error<Reason>, Unit>) -> IO(State<Reason, Value>):
  match pair:
    case (result, +outcome):
      do IO<State<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        settle(~Reason, ~Value, ~release, Entry{address, mode, outcome, deadline} <> history, result, Progress.decide(Reason, outcome, reason))

def completed(~Reason: Data, ~Value: Type, ~release: Value -> IO(Unit), parent: Abort.AbortSignal<Reason>, address: Connect.Address, mode: Progress.Mode, history: List<&2, Entry<Reason>>, report: Attempt.Report<Reason, Value>) -> IO(State<Reason, Value>):
  match report:
    case Attempt.Report{result, deadline}: observed(~Reason, ~Value, ~release, parent, address, mode, history, deadline, Progress.observed(Reason, Value, result))

def checked(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Progress.Mode -> Abort.AbortSignal<Reason> -> IO(Attempt.Report<Reason, Value>), ~release: Value -> IO(Unit), context: Context, +parent: Abort.AbortSignal<Reason>, +address: Connect.Address, +mode: Progress.Mode, history: List<&2, Entry<Reason>>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(State<Reason, Value>):
  match reason:
    case Some{why}: IO.pure(State<Reason, Value>, Finished{finish(Reason, Value, Fail{Progress.Aborted{why}}, history)})
    case None{}:
      do IO<State<Reason, Value>>:
        report : Attempt.Report<Reason, Value> <- connect(context, address, mode, parent)
        completed(~Reason, ~Value, ~release, parent, address, mode, history, report)

def exhausted(-Reason: Data, -Value: Type, history: List<&2, Entry<Reason>>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> Report<Reason, Value>:
  match reason:
    case Some{why}: finish(Reason, Value, Fail{Progress.Aborted{why}}, history)
    case None{}: empty(Reason, Value, history)

# Recursion consumes exactly one list cell per call. State cannot add addresses
# or restart earlier attempts, and Finished stops before inspecting the tail.
def drive(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Progress.Mode -> Abort.AbortSignal<Reason> -> IO(Attempt.Report<Reason, Value>), ~release: Value -> IO(Unit), +context: Context, +parent: Abort.AbortSignal<Reason>, remaining: List<&2, Connect.Address>, state: State<Reason, Value>) -> IO(Report<Reason, Value>):
  match remaining state:
    case _ Finished{report}: IO.pure(Report<Reason, Value>, report)
    case Nil{} Active{history}:
      do IO<Report<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        return exhausted(Reason, Value, history, reason)
    case first <> +rest Active{history}:
      do IO<Report<Reason, Value>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, parent)
        next : State<Reason, Value> <- checked(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, first, Progress.mode(Connect.Address, rest), history, reason)
        drive(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, rest, next)

# Address order is supplied by connection-order. History describes connector
# outcomes; cancellation can reject success before ownership is handed off.
def runWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Connect.Address -> Progress.Mode -> Abort.AbortSignal<Reason> -> IO(Attempt.Report<Reason, Value>), ~release: Value -> IO(Unit), context: Context, addresses: List<&2, Connect.Address>, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Value>):
  drive(~Context, ~Reason, ~Value, ~connect, ~release, context, parent, addresses, Active{Nil{}})

type Options is Data:
  Options{port: U32, attemptMilliseconds: U32}

def open(~Reason: Data, options: Options, address: Connect.Address, mode: Progress.Mode, parent: Abort.AbortSignal<Reason>) -> IO(Attempt.Report<Reason, Socket>):
  match options mode:
    case Options{port, milliseconds} Progress.NonFinal{}: Attempt.timed(~Reason, address, port, parent, milliseconds)
    case Options{port, _} Progress.Final{}: Attempt.final(~Reason, address, port, parent)

def run(~Reason: Data, options: Options, addresses: List<&2, Connect.Address>, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Socket>):
  runWith(~Options, ~Reason, ~Socket, ~open(~Reason), ~Socket.close, options, addresses, parent)
