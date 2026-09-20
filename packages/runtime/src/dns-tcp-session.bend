import Base
import ./dns-pending.bend as Pending
import ./dns-tcp-peer.bend as Peer
import ./dns-tcp-connection.bend as TCP
import ./dns-message.bend as Message
import ./dns-edns.bend as Edns
import ./socket-interrupt.bend as Interrupt

type Failure<-Reason: Data> is Data:
  EndOfStream{}
  Transport{error: TCP.Error<Reason>}

type Error<-Reason: Data> is Data:
  Query{error: Message.Error}
  Extension{error: Edns.Error}
  Registration{error: Pending.RegistrationError}
  InvalidReadSize{}
  Stopped{failure: Failure<Reason>}

type Session<-Reason: Data, -Token: Data> is Type:
  Session{route: Peer.Route, connection: TCP.Connection<Reason>, pending: Pending.Pending<Token>, ended: Maybe<&2, Failure<Reason>>}

type Outcome<-Reason: Data, -Token: Data> is Data:
  Submitted{ticket: Pending.Ticket}
  Cancelled{entry: Maybe<&2, Pending.Entry<Token>>}
  Rejected{error: Error<Reason>}
  Response{delivery: Pending.Delivery<Token>}
  Ended{failure: Failure<Reason>, outstanding: List<&2, Pending.Entry<Token>>}

type Step<-Reason: Data, -Token: Data> is Type:
  Step{session: Session<Reason, Token>, event: Outcome<Reason, Token>}

type Closed<-Token: Data> is Data:
  Closed{outstanding: List<&2, Pending.Entry<Token>>, cleanup: Result<&2, &2, Interrupt.Error, Unit>}

def adopt(-Reason: Data, -Token: Data, peer: Peer.Peer<Reason>) -> Session<Reason, Token>:
  match peer:
    case Peer.Peer{route, connection}: Session{route, connection, Pending.new(Token), None{}}

def failed(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, pending: Pending.Pending<Token>, +why: Failure<Reason>) -> Step<Reason, Token>:
  Step{Session{route, connection, Pending.new(Token), Some{why}}, Ended{why, Pending.drain(Token, pending)}}

def sent(-Reason: Data, -Token: Data, ticket: Pending.Ticket, route: Peer.Route, pending: Pending.Pending<Token>, pair: TCP.Connection<Reason> & Result<&2, &2, TCP.Error<Reason>, Unit>) -> Step<Reason, Token>:
  match pair:
    case (connection, Done{_}): Step{Session{route, connection, pending, None{}}, Submitted{ticket}}
    case (connection, Fail{error}): failed(Reason, Token, route, connection, pending, Transport{error})

def registered(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, wire: List<&2, U32>, value: Pending.Registered<Token>) -> IO(Step<Reason, Token>):
  match value:
    case Pending.Registered{pending, Fail{error}}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, None{}}, Rejected{Registration{error}}})
    case Pending.Registered{pending, Done{ticket}}:
      do IO<Step<Reason, Token>>:
        result : TCP.Connection<Reason> & Result<&2, &2, TCP.Error<Reason>, Unit> <- TCP.send(Reason, connection, wire)
        return sent(Reason, Token, ticket, route, pending, result)

def encoded(-Reason: Data, -Token: Data, +route: Peer.Route, connection: TCP.Connection<Reason>, pending: Pending.Pending<Token>, id: U32, flags: U32, question: Message.Question, token: Token, result: Result<&2, &2, Message.Error, List<&2, U32>>) -> IO(Step<Reason, Token>):
  match result:
    case Fail{error}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, None{}}, Rejected{Query{error}}})
    case Done{wire}: registered(Reason, Token, route, connection, wire, Pending.register(Token, pending, Peer.transaction(route, id, (flags / 2048 % 16 : U32), question), token))

# The affine session serializes operations. Several queries can be submitted
# before receiving; registration precedes the first byte written. A failed
# write may be partial, so it permanently ends this session and settles all
# pending requests, including the attempted submission. No frame is retried.
def submit(-Reason: Data, -Token: Data, session: Session<Reason, Token>, +id: U32, +flags: U32, +question: Message.Question, token: Token) -> IO(Step<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, Some{why}}, Rejected{Stopped{why}}})
    case Session{route, connection, pending, None{}}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Message.query(id, flags, question))

def extendedEncoded(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, pending: Pending.Pending<Token>, id: U32, flags: U32, question: Message.Question, token: Token, result: Result<&2, &2, Edns.Error, List<&2, U32>>) -> IO(Step<Reason, Token>):
  match result:
    case Fail{Edns.Message{error}}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Fail{error})
    case Fail{error}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, None{}}, Rejected{Extension{error}}})
    case Done{wire}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Done{wire})

# Use the same pending table and transport as plain queries. Validation errors
# leave the live session unchanged; an ended session takes precedence over
# encoding. Successful encoding still registers before the first byte written.
def submitEdns(-Reason: Data, -Token: Data, session: Session<Reason, Token>, +id: U32, +flags: U32, +question: Message.Question, token: Token, extension: Edns.Query) -> IO(Step<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, Some{why}}, Rejected{Stopped{why}}})
    case Session{route, connection, pending, None{}}: extendedEncoded(Reason, Token, route, connection, pending, id, flags, question, token, Edns.query(id, flags, question, extension))

def dispatched(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, value: Pending.Received<Token>) -> Step<Reason, Token>:
  match value:
    case Pending.Received{pending, delivery}: Step{Session{route, connection, pending, None{}}, Response{delivery}}

def packet(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, pending: Pending.Pending<Token>, wire: List<&2, U32>) -> Step<Reason, Token>:
  match route:
    case Peer.Route{+local, +remote}: dispatched(Reason, Token, Peer.Route{local, remote}, connection, Pending.receive(Token, pending, remote, local, wire))

def received(-Reason: Data, -Token: Data, route: Peer.Route, pending: Pending.Pending<Token>, next: TCP.Next<Reason>) -> Step<Reason, Token>:
  match next:
    case TCP.Next{connection, Fail{error}}: failed(Reason, Token, route, connection, pending, Transport{error})
    case TCP.Next{connection, Done{None{}}}: failed(Reason, Token, route, connection, pending, EndOfStream{})
    case TCP.Next{connection, Done{Some{wire}}}: packet(Reason, Token, route, connection, pending, wire)

def read(-Reason: Data, -Token: Data, session: Session<Reason, Token>, maximum: U32) -> IO(Step<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(Step<Reason, Token>, Step{Session{route, connection, pending, Some{why}}, Ended{why, Nil{}}})
    case Session{route, connection, pending, None{}}:
      do IO<Step<Reason, Token>>:
        next : TCP.Next<Reason> <- TCP.receive(Reason, connection, maximum)
        return received(Reason, Token, route, pending, next)

# Return each frame decision, including ignored frames. The caller controls
# scheduling rather than an unbounded internal loop starving other commands.
def receive(-Reason: Data, -Token: Data, session: Session<Reason, Token>, maximum: U32) -> IO(Step<Reason, Token>):
  match maximum:
    case 0: IO.pure(Step<Reason, Token>, Step{session, Rejected{InvalidReadSize{}}})
    case size: read(Reason, Token, session, size)

# Close is required even after Ended. It joins the connection watcher and
# returns any unsettled entries rather than silently abandoning callers.
def close(-Reason: Data, -Token: Data, session: Session<Reason, Token>) -> IO(Closed<Token>):
  match session:
    case Session{_, connection, pending, _}:
      do IO<Closed<Token>>:
        cleanup : Result<&2, &2, Interrupt.Error, Unit> <- TCP.close(Reason, connection)
        return Closed{Pending.drain(Token, pending), cleanup}


def cancelled(-Reason: Data, -Token: Data, route: Peer.Route, connection: TCP.Connection<Reason>, ended: Maybe<&2, Failure<Reason>>, result: Pending.Removed<Token>) -> Step<Reason, Token>:
  match result:
    case Pending.Removed{pending, entry}: Step{Session{route, connection, pending, ended}, Cancelled{entry}}

# Local request cancellation does not shut down the shared TCP connection.
# Admission remains serialized by session ownership; no watcher is detached.
def cancel(-Reason: Data, -Token: Data, session: Session<Reason, Token>, ticket: Pending.Ticket) -> Step<Reason, Token>:
  match session:
    case Session{route, connection, pending, ended}: cancelled(Reason, Token, route, connection, ended, Pending.cancel(Token, pending, ticket))
