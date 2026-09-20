import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./abortable-socket.bend as SocketIO
import ./dns-tcp-query.bend as Query
import ./dns-tcp-recover.bend as Recover
import ./dns-tcp-session.bend as Session
import ./dns-tcp-connection.bend as TCP
import ./dns-tcp-frame.bend as Frame
import ./dns-message.bend as Message
import ./dns-query.bend as Request

type Server is Data:
  Server{address: Connect.Address, port: U32}

type Error<-Reason: Data> is Data:
  NoServers{}
  Failed{report: Query.Completed<Reason>}

type Decision<-Reason: Data> is Data:
  Answer{reply: Query.Reply}
  Next{report: Query.Completed<Reason>}
  Stop{report: Query.Completed<Reason>}

# Completed network failures can move to another server. Abort, local state,
# validation and adoption failures remain terminal and retain their details.
def retryable(-Reason: Data, error: Query.Error<Reason>) -> Bool:
  match error:
    case Query.Connection{Connect.SocketError{_, _}}: True{}
    case Query.Terminated{Session.EndOfStream{}}: True{}
    case Query.Terminated{Session.Transport{TCP.Transport{_, SocketIO.SocketError{_, _}}}}: True{}
    case Query.Terminated{Session.Transport{TCP.Framing{Frame.IncompleteFrame{}}}}: True{}
    case _: False{}

def failed(-Reason: Data, retry: Bool, report: Query.Completed<Reason>) -> Decision<Reason>:
  match retry:
    case True{}: Next{report}
    case False{}: Stop{report}

# Cleanup takes precedence over retry. DNS response codes and truncation are
# replies, not transport failures; their policy belongs above this layer.
def completed(-Reason: Data, report: Query.Completed<Reason>) -> Decision<Reason>:
  match report:
    case Query.Completed{Done{reply}, Done{_}}: Answer{reply}
    case Query.Completed{Fail{+error}, Done{_}}: failed(Reason, retryable(Reason, error), Query.Completed{Fail{error}, Done{Unit{}}})
    case other: Stop{other}

# One pass through the supplied order. The borrowed deadline and unchanged
# query span every attempt. Recover.exchange returns only after closing its
# resources; no detached attempt overlaps the following server.
def drive(-Reason: Data, servers: List<&2, Server>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, +maximum: U32, decision: Decision<Reason>) -> IO(Result<&2, &2, Error<Reason>, Query.Reply>):
  match servers decision:
    case _ Answer{reply}: IO.pure(Result<&2, &2, Error<Reason>, Query.Reply>, Done{reply})
    case _ Stop{report}: IO.pure(Result<&2, &2, Error<Reason>, Query.Reply>, Fail{Failed{report}})
    case Nil{} Next{report}: IO.pure(Result<&2, &2, Error<Reason>, Query.Reply>, Fail{Failed{report}})
    case Server{address, port} <> rest Next{_}:
      do IO<Result<&2, &2, Error<Reason>, Query.Reply>>:
        report : Query.Completed<Reason> <- Recover.exchangeRequest(Reason, address, port, signal, request, maximum)
        drive(Reason, rest, signal, request, maximum, completed(Reason, report))

def exchangeRequest(-Reason: Data, servers: List<&2, Server>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, +maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Query.Reply>):
  match servers:
    case Nil{}: IO.pure(Result<&2, &2, Error<Reason>, Query.Reply>, Fail{NoServers{}})
    case Server{address, port} <> rest:
      do IO<Result<&2, &2, Error<Reason>, Query.Reply>>:
        report : Query.Completed<Reason> <- Recover.exchangeRequest(Reason, address, port, signal, request, maximum)
        drive(Reason, rest, signal, request, maximum, completed(Reason, report))

def exchange(-Reason: Data, servers: List<&2, Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Query.Reply>):
  exchangeRequest(Reason, servers, signal, Request.plain(id, flags, question), maximum)
