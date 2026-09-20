import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./dns-tcp-peer.bend as Peer
import ./dns-tcp-session.bend as Session
import ./dns-pending.bend as Pending
import ./dns-message.bend as Message
import ./dns-query.bend as Request
import ./socket-interrupt.bend as Interrupt

type Reply is Data:
  Answer{message: Message.Message}
  Truncated{header: Message.Header}

type Error<-Reason: Data> is Data:
  InvalidReadSize{}
  Connection{error: Connect.Error<Deadline.Cause<Reason>>}
  Adoption{error: Peer.Error<Deadline.Cause<Reason>>}
  Submission{error: Session.Error<Deadline.Cause<Reason>>}
  Terminated{failure: Session.Failure<Deadline.Cause<Reason>>}
  InvalidState{}

# Preserve the primary result if socket cleanup also fails. A late deadline
# reason is diagnostic; it does not retroactively replace a completed reply.
type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, Error<Reason>, Reply>, cleanup: Result<&2, &2, Interrupt.Error, Unit>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Completed<-Reason: Data> is Data:
  Completed{result: Result<&2, &2, Error<Reason>, Reply>, cleanup: Result<&2, &2, Interrupt.Error, Unit>}

type Reading<-Reason: Data> is Type:
  Continue{session: Session.Session<Deadline.Cause<Reason>, Unit>}
  Finish{session: Session.Session<Deadline.Cause<Reason>, Unit>, result: Result<&2, &2, Error<Reason>, Reply>}

def cleaned(-Reason: Data, result: Result<&2, &2, Error<Reason>, Reply>, closed: Session.Closed<Unit>) -> Completed<Reason>:
  match closed:
    case Session.Closed{_, status}: Completed{result, status}

def finish(-Reason: Data, session: Session.Session<Deadline.Cause<Reason>, Unit>, result: Result<&2, &2, Error<Reason>, Reply>) -> IO(Completed<Reason>):
  do IO<Completed<Reason>>:
    closed : Session.Closed<Unit> <- Session.close(Deadline.Cause<Reason>, Unit, session)
    return cleaned(Reason, result, closed)

def received(-Reason: Data, step: Session.Step<Deadline.Cause<Reason>, Unit>) -> Reading<Reason>:
  match step:
    case Session.Step{session, Session.Response{Pending.Ignored{_}}}: Continue{session}
    case Session.Step{session, Session.Response{Pending.Answer{_, message}}}: Finish{session, Done{Answer{message}}}
    case Session.Step{session, Session.Response{Pending.Truncated{_, header}}}: Finish{session, Done{Truncated{header}}}
    case Session.Step{session, Session.Ended{failure, _}}: Finish{session, Fail{Terminated{failure}}}
    case Session.Step{session, Session.Rejected{error}}: Finish{session, Fail{Submission{error}}}
    case Session.Step{session, _}: Finish{session, Fail{InvalidState{}}}

# A dedicated query connection has no other recipient for ignored frames.
# Each continuation awaits abort-aware socket IO; the same deadline remains
# active across all ignored replies. No retry or fresh timeout is introduced.
@unsafe def read(-Reason: Data, +maximum: U32, state: Reading<Reason>) -> IO(Completed<Reason>):
  match state:
    case Finish{session, result}: finish(Reason, session, result)
    case Continue{session}:
      do IO<Completed<Reason>>:
        step : Session.Step<Deadline.Cause<Reason>, Unit> <- Session.receive(Deadline.Cause<Reason>, Unit, session, maximum)
        read(Reason, maximum, received(Reason, step))

def submitted(-Reason: Data, maximum: U32, step: Session.Step<Deadline.Cause<Reason>, Unit>) -> IO(Completed<Reason>):
  match step:
    case Session.Step{session, Session.Submitted{_}}: read(Reason, maximum, Continue{session})
    case Session.Step{session, Session.Rejected{error}}: finish(Reason, session, Fail{Submission{error}})
    case Session.Step{session, Session.Ended{failure, _}}: finish(Reason, session, Fail{Terminated{failure}})
    case Session.Step{session, _}: finish(Reason, session, Fail{InvalidState{}})

def adopted(-Reason: Data, request: Request.Request, maximum: U32, result: Result<&2, &1, Peer.Error<Deadline.Cause<Reason>>, Peer.Peer<Deadline.Cause<Reason>>>) -> IO(Completed<Reason>):
  match result:
    case Fail{error}: IO.pure(Completed<Reason>, Completed{Fail{Adoption{error}}, Done{Unit{}}})
    case Done{peer}:
      do IO<Completed<Reason>>:
        step : Session.Step<Deadline.Cause<Reason>, Unit> <- Session.submitRequest(Deadline.Cause<Reason>, Unit, Session.adopt(Deadline.Cause<Reason>, Unit, peer), request, Unit{})
        submitted(Reason, maximum, step)

def connected(-Reason: Data, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32, result: Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Socket>) -> IO(Completed<Reason>):
  match result:
    case Fail{error}: IO.pure(Completed<Reason>, Completed{Fail{Connection{error}}, Done{Unit{}}})
    case Done{socket}:
      do IO<Completed<Reason>>:
        result : Result<&2, &1, Peer.Error<Deadline.Cause<Reason>>, Peer.Peer<Deadline.Cause<Reason>>> <- Peer.create(Deadline.Cause<Reason>, socket, signal)
        adopted(Reason, request, maximum, result)

def report(-Reason: Data, completed: Completed<Reason>, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Report<Reason>:
  match completed:
    case Completed{result, cleanup}: Report{result, cleanup, reason}

# Borrow an existing deadline signal for one exchange. This permits a resolver
# to keep one total deadline across alias follow-ups; no timer is created here.
def exchangeRequest(-Reason: Data, address: Connect.Address, port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32) -> IO(Completed<Reason>):
  match maximum:
    case 0: IO.pure(Completed<Reason>, Completed{Fail{InvalidReadSize{}}, Done{Unit{}}})
    case size:
      do IO<Completed<Reason>>:
        result : Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Socket> <- Connect.connect(Deadline.Cause<Reason>, address, port, signal)
        connected(Reason, signal, request, size, result)

def scoped(-Reason: Data, address: Connect.Address, port: U32, request: Request.Request, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, +signal):
      do IO<Report<Reason>>:
        completed : Completed<Reason> <- exchangeRequest(Reason, address, port, signal, request, maximum)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return report(Reason, completed, reason)

# One exchange on a dedicated numeric TCP connection. The deadline spans
# connect, adoption, send and receive; teardown closes the session before its
# borrowed signal. Address selection, ID generation, retries, RCODE and answer
# trust/alias/cache policy remain outside this transport operation.
def queryRequest(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, request: Request.Request, maximum: U32) -> IO(Report<Reason>):
  match maximum:
    case 0: IO.pure(Report<Reason>, Report{Fail{InvalidReadSize{}}, Done{Unit{}}, None{}})
    case size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(Reason, address, port, request, size, Deadline.borrow(Reason, scope))

# Compatibility entry points construct the same explicit plain-query value.
def exchange(-Reason: Data, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Completed<Reason>):
  exchangeRequest(Reason, address, port, signal, Request.plain(id, flags, question), maximum)

def query(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Report<Reason>):
  queryRequest(Reason, address, port, milliseconds, parent, Request.plain(id, flags, question), maximum)
