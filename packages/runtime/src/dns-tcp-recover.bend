import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./abortable-socket.bend as SocketIO
import ./dns-tcp-query.bend as Query
import ./dns-tcp-session.bend as Session
import ./dns-tcp-connection.bend as TCP
import ./dns-message.bend as Message
import ./dns-query.bend as Request

# The length-prefix read (including a partially read prefix) is the only
# recoverable reset site. Never unwrap failed cleanup or treat abort as errno.
def reset(-Reason: Data, report: Query.Completed<Reason>) -> IO(Bool):
  match report:
    case Query.Completed{Fail{Query.Terminated{Session.Transport{TCP.Transport{TCP.ReadingLength{}, SocketIO.SocketError{code, _}}}}}, Done{_}}: Socket.isConnectionReset(code)
    case _: IO.pure(Bool, False{})

def finish(-Reason: Data, retry: Bool, report: Query.Completed<Reason>, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, maximum: U32) -> IO(Query.Completed<Reason>):
  match retry:
    case False{}: IO.pure(Query.Completed<Reason>, report)
    case True{}: Query.exchangeRequest(Reason, address, port, signal, request, maximum)

# A closed failed exchange may be retried once against the same server. The
# second result is returned unchanged, so another reset cannot loop. Preserve
# query bytes/ID and borrow the same deadline across both connections.
def exchangeRequest(-Reason: Data, +address: Connect.Address, +port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Request.Request, +maximum: U32) -> IO(Query.Completed<Reason>):
  do IO<Query.Completed<Reason>>:
    +report : Query.Completed<Reason> <- Query.exchangeRequest(Reason, address, port, signal, request, maximum)
    retry : Bool <- reset(Reason, report)
    finish(Reason, retry, report, address, port, signal, request, maximum)

def exchange(-Reason: Data, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Query.Completed<Reason>):
  exchangeRequest(Reason, address, port, signal, Request.plain(id, flags, question), maximum)
