import Base
import ./connection-attempt-result.bend as Outcome
import ./abortable-connect.bend as Connect
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Report<-Reason: Data, -Value: Type> is Type:
  Report{result: Result<&2, &1, Outcome.Error<Reason>, Value>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def scoped(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>), context: Context, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason, Value>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason, Value>>:
        result : Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value> <- connect(context, signal)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{Outcome.timed(Reason, Value, result), reason}

# The connector must settle all work borrowed from the child signal before
# returning. Close joins the deadline's tasks before exposing the affine value.
# Late expiry is retained as a diagnostic, not substituted for a settled result.
def timedWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Deadline.Cause<Reason>> -> IO(Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Value>), context: Context, parent: Abort.AbortSignal<Reason>, milliseconds: U32) -> IO(Report<Reason, Value>):
  do IO<Report<Reason, Value>>:
    scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
    scoped(~Context, ~Reason, ~Value, ~connect, context, Deadline.borrow(Reason, scope))

# Final attempts borrow the parent directly and allocate no family timer.
def finalWith(~Context: Data, ~Reason: Data, ~Value: Type, ~connect: Context -> Abort.AbortSignal<Reason> -> IO(Result<&2, &1, Connect.Error<Reason>, Value>), context: Context, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Value>):
  do IO<Report<Reason, Value>>:
    result : Result<&2, &1, Connect.Error<Reason>, Value> <- connect(context, parent)
    return Report{Outcome.plain(Reason, Value, result), None{}}

type Endpoint is Data:
  Endpoint{address: Connect.Address, port: U32}

def open(~Reason: Data, endpoint: Endpoint, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, Connect.Error<Reason>, Socket>):
  match endpoint:
    case Endpoint{address, port}: Connect.connect(Reason, address, port, signal)

def timed(~Reason: Data, address: Connect.Address, port: U32, parent: Abort.AbortSignal<Reason>, milliseconds: U32) -> IO(Report<Reason, Socket>):
  timedWith(~Endpoint, ~Reason, ~Socket, ~open(~Deadline.Cause<Reason>), Endpoint{address, port}, parent, milliseconds)

def final(~Reason: Data, address: Connect.Address, port: U32, parent: Abort.AbortSignal<Reason>) -> IO(Report<Reason, Socket>):
  finalWith(~Endpoint, ~Reason, ~Socket, ~open(~Reason), Endpoint{address, port}, parent)
