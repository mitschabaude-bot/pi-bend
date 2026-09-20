import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./dns-tcp-query.bend as Query
import ./dns-address-answer.bend as Answer
import ./dns-message.bend as Message
import ./dns-name.bend as Name
import ./dns-response.bend as Response
import ./dns-id.bend as Id

type Error<-Reason: Data> is Data:
  InvalidReadSize{}
  UnsupportedType{}
  Identifier{error: Id.Error}
  Exchange{error: Query.Error<Reason>}
  Selection{error: Answer.Error}
  Truncated{header: Message.Header}
  Cleanup{report: Query.Completed<Reason>}

type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, Error<Reason>, Answer.Selection>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Progress<-Reason: Data> is Data:
  Again{name: Name.Name, history: Answer.History}
  Finished{result: Result<&2, &2, Error<Reason>, Answer.Selection>}

def empty(-Reason: Data, same: Bool, name: Name.Name, history: Answer.History) -> Progress<Reason>:
  match same:
    case True{}: Finished{Done{Answer.Selection{name, Nil{}}}}
    case False{}: Again{name, history}

def selected(-Reason: Data, previous: Name.Name, value: Result<&2, &2, Answer.Error, Answer.Trace>) -> Progress<Reason>:
  match value:
    case Fail{error}: Finished{Fail{Selection{error}}}
    case Done{Answer.Trace{Answer.Selection{+name, Nil{}}, history}}: empty(Reason, Response.sameName(previous, name), name, history)
    case Done{Answer.Trace{selection, _}}: Finished{Done{selection}}

def replied(-Reason: Data, +name: Name.Name, kind: U32, history: Answer.History, result: Result<&2, &2, Query.Error<Reason>, Query.Reply>) -> Progress<Reason>:
  match result:
    case Fail{error}: Finished{Fail{Exchange{error}}}
    case Done{Query.Truncated{header}}: Finished{Fail{Truncated{header}}}
    case Done{Query.Answer{message}}: selected(Reason, name, Answer.selectWithHistory(history, kind, name, message))

def completed(-Reason: Data, name: Name.Name, kind: U32, history: Answer.History, value: Query.Completed<Reason>) -> Progress<Reason>:
  match value:
    case Query.Completed{result, Done{_}}: replied(Reason, name, kind, history, result)
    case Query.Completed{result, Fail{error}}: Finished{Fail{Cleanup{Query.Completed{result, Fail{error}}}}}

def identified(-Reason: Data, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +kind: U32, +name: Name.Name, history: Answer.History, maximum: U32, value: Result<&2, &2, Id.Error, U32>) -> IO(Progress<Reason>):
  match value:
    case Fail{error}: IO.pure(Progress<Reason>, Finished{Fail{Identifier{error}}})
    case Done{id}:
      do IO<Progress<Reason>>:
        result : Query.Completed<Reason> <- Query.exchange(Reason, address, port, signal, id, 256, Message.Question{name, kind, 1}, maximum)
        return completed(Reason, name, kind, history, result)

# Inspect the retained abort reason before invoking the source. Connect also
# checks the signal, covering an abort that arrives while the source runs.
def ready(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Name.Name, history: Answer.History, maximum: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Progress<Reason>):
  match reason:
    case Some{why}: IO.pure(Progress<Reason>, Finished{Fail{Exchange{Query.Connection{Connect.Aborted{why}}}}})
    case None{}:
      do IO<Progress<Reason>>:
        value : Result<&2, &2, Id.Error, U32> <- draw(environment)
        identified(Reason, address, port, signal, kind, name, history, maximum, value)

# Each follow-up draws a new ID and awaits an independently closed exchange
# under the same deadline. The environment is borrowed; its owner disposes any
# resources after this call. Static injection needs no mutable callback registry.
@unsafe def drive(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, +environment: Environment, +address: Connect.Address, +port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +kind: U32, +maximum: U32, progress: Progress<Reason>) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match progress:
    case Finished{result}: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, result)
    case Again{name, history}:
      do IO<Result<&2, &2, Error<Reason>, Answer.Selection>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        next : Progress<Reason> <- ready(~Environment, ~draw, Reason, environment, address, port, signal, kind, name, history, maximum, reason)
        drive(~Environment, ~draw, Reason, environment, address, port, signal, kind, maximum, next)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, kind: U32, name: Name.Name, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Error<Reason>, Answer.Selection> <- drive(~Environment, ~draw, Reason, environment, address, port, signal, kind, maximum, Again{name, Answer.newHistory()})
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def start(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, valid: Bool, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  match valid maximum:
    case False{} _: IO.pure(Report<Reason>, Report{Fail{UnsupportedType{}}, None{}})
    case True{} 0: IO.pure(Report<Reason>, Report{Fail{InvalidReadSize{}}, None{}})
    case True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(~Environment, ~draw, Reason, environment, address, port, kind, name, size, Deadline.borrow(Reason, scope))

# The injected source runs once before each exchange. It must return promptly;
# arbitrary user effects cannot be force-cancelled by the enclosing deadline.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  start(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), environment, address, port, milliseconds, parent, kind, name, maximum)

# Preserve the deterministic entry point. Dedicated connections isolate delayed
# replies even when a caller reuses the same ID across alias follow-ups.
def lookup(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWith(~U32, ~Id.fixed, Reason, id, address, port, milliseconds, parent, kind, name, maximum)

# OS entropy is the normal resolver source. Each draw is independent; random
# IDs can legitimately repeat. No uniqueness or reply-authentication guarantee.
def lookupRandom(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWith(~Unit, ~Id.random, Reason, Unit{}, address, port, milliseconds, parent, kind, name, maximum)
