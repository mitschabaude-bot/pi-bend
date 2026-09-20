import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./dns-tcp-query.bend as Query
import ./dns-address-answer.bend as Answer
import ./dns-message.bend as Message
import ./dns-name.bend as Name
import ./dns-response.bend as Response

type Error<-Reason: Data> is Data:
  InvalidReadSize{}
  UnsupportedType{}
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

# Each follow-up awaits a new, independently closed exchange under the same
# borrowed deadline signal. History includes all traversed alias owners, not
# just the final name of each response, so packet boundaries cannot hide loops.
@unsafe def drive(-Reason: Data, +address: Connect.Address, +port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +id: U32, +kind: U32, +maximum: U32, progress: Progress<Reason>) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match progress:
    case Finished{result}: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, result)
    case Again{+name, history}:
      do IO<Result<&2, &2, Error<Reason>, Answer.Selection>>:
        result : Query.Completed<Reason> <- Query.exchange(Reason, address, port, signal, id, 256, Message.Question{name, kind, 1}, maximum)
        drive(Reason, address, port, signal, id, kind, maximum, completed(Reason, name, kind, history, result))

def scoped(-Reason: Data, address: Connect.Address, port: U32, id: U32, kind: U32, name: Name.Name, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Error<Reason>, Answer.Selection> <- drive(Reason, address, port, signal, id, kind, maximum, Again{name, Answer.newHistory()})
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def start(-Reason: Data, valid: Bool, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  match valid maximum:
    case False{} _: IO.pure(Report<Reason>, Report{Fail{UnsupportedType{}}, None{}})
    case True{} 0: IO.pure(Report<Reason>, Report{Fail{InvalidReadSize{}}, None{}})
    case True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(Reason, address, port, id, kind, name, size, Deadline.borrow(Reason, scope))

# Query a caller-selected recursive server for an IN A/AAAA name. Every
# exchange uses a dedicated TCP connection, so a follow-up cannot receive a
# delayed frame from an earlier connection with the same caller-provided ID.
# Server configuration, ID entropy, retries, family ordering, cache/TTL policy
# and OS host-name lookup integration remain outside this operation.
def lookup(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, +kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  start(Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), address, port, milliseconds, parent, id, kind, name, maximum)
