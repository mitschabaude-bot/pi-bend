import Base
import ./dns-message.bend as Message
import ./abort.bend as Abort
import ./resolver-config.bend as Plan
import ./deadline.bend as Deadline
import ./socket.bend as Endpoint
import ./socket.bend as Connect
import ./socket.bend as SocketIO
import ./socket.bend as Interrupt
import ./socket.bend as Datagram
import ./datagram-peer.bend as Peer
import ./ref.bend as Ref
import ./random.bend as Index

type End<-Reason: Data> is Data:
  Active{}
  AttemptExpired{}
  ParentAborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  UnexpectedDefaultAbort{}

# The parent is the caller's existing total-deadline signal. Creating an
# attempt does not restart that deadline or replace its original abort reason.
def checkedUdpAttemptScope(-Reason: Data, parent: Abort.AbortSignal<Deadline.Cause<Reason>>, budget: Result<&2, &2, Plan.MillisecondsError, U32>) -> IO(Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>):
  match budget:
    case Fail{error}: IO.pure(Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>, Fail{error})
    case Done{milliseconds}:
      do IO<Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>>:
        scope : Deadline.Scope<Deadline.Cause<Reason>> <- Deadline.create(Deadline.Cause<Reason>, milliseconds, parent)
        return Done{scope}

def createUdpAttemptScope(-Reason: Data, duration: Plan.Duration, parent: Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>):
  checkedUdpAttemptScope(Reason, parent, Plan.milliseconds(duration))

def classify(-Reason: Data, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>>) -> End<Reason>:
  match reason:
    case None{}: Active{}
    case Some{Abort.Supplied{Deadline.Expired{}}}: AttemptExpired{}
    case Some{Abort.Supplied{Deadline.ParentAbort{why}}}: ParentAborted{why}
    case Some{Abort.DefaultAbort{}}: UnexpectedDefaultAbort{}

# Call after all operations borrowing the child signal have settled. Deadline
# closure cancels its timer/observation and joins both watcher tasks.
def closeUdpAttemptScope(-Reason: Data, scope: Deadline.Scope<Deadline.Cause<Reason>>) -> IO(End<Reason>):
  do IO<End<Reason>>:
    reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>> <- Deadline.close(Deadline.Cause<Reason>, scope)
    return classify(Reason, reason)

type UdpQueryReply is Data:
  UdpQueryAnswer{message: Message.Message}
  UdpQueryTruncated{header: Message.Header}

type UdpQueryError<-Reason: Data> is Data:
  UdpQueryEncoding{error: Message.EdnsError}
  Aborted{reason: Abort.AbortReason<Reason>}
  Opening{error: Peer.Error}
  UdpQueryTransport{error: Datagram.DatagramError<Reason>}

def encode(request: Message.Request) -> Result<&2, &2, Message.EdnsError, List<&2, U32>>:
  Message.encodeQuery(request)

def messageEndpoint(value: Endpoint.Endpoint) -> Message.Endpoint:
  match value:
    case Endpoint.EndpointV4{ip, port}: Message.Endpoint{Message.V4{ip}, port}
    case Endpoint.EndpointV6{ip, port, scope}: Message.Endpoint{Message.V6{ip, scope}, port}

def transactionUdpQuery(route: Peer.Route, request: Message.Request) -> Message.Transaction:
  match route request:
    case Peer.Route{local, remote} Message.Request{id, flags, question, _}: Message.Transaction{messageEndpoint(local), messageEndpoint(remote), id, (flags / 2048 % 16 : U32), question}

type UdpQueryReading<-Reason: Data> is Type:
  UdpQueryContinue{socket: Socket}
  UdpQueryFinish{socket: Socket, result: Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>}

def inspectedUdpQuery(-Reason: Data, socket: Socket, decision: Message.Decision) -> UdpQueryReading<Reason>:
  match decision:
    case Message.Ignore{_}: UdpQueryContinue{socket}
    case Message.ResponseTruncated{header}: UdpQueryFinish{socket, Done{UdpQueryTruncated{header}}}
    case Message.Matched{message}: UdpQueryFinish{socket, Done{UdpQueryAnswer{message}}}

def receivedUdpQuery(-Reason: Data, expected: Message.Transaction, local: Endpoint.Endpoint, pair: Socket & Result<&2, &2, Datagram.DatagramError<Reason>, Datagram.Packet>) -> UdpQueryReading<Reason>:
  match pair:
    case (socket, Fail{error}): UdpQueryFinish{socket, Fail{UdpQueryTransport{error}}}
    # DNS messages are bounded at 65535 bytes. A larger truncated datagram is
    # ignored, never parsed as a complete message or trusted for TCP fallback.
    case (socket, Done{Datagram.Packet{_, True{}, _}}): UdpQueryContinue{socket}
    case (socket, Done{Datagram.Packet{peer, False{}, bytes}}): inspectedUdpQuery(Reason, socket, Message.inspectResponse(expected, messageEndpoint(peer), messageEndpoint(local), bytes))

# Each iteration awaits abort-aware IO under the same borrowed signal. Noise
# cannot reset the deadline, and rejected packets are not retained in a list.
@unsafe def readUdpQuery(-Reason: Data, +signal: Abort.AbortSignal<Reason>, +expected: Message.Transaction, +local: Endpoint.Endpoint, state: UdpQueryReading<Reason>) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match state:
    case UdpQueryFinish{socket, result}:
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        Socket.close(socket)
        return result
    case UdpQueryContinue{socket}:
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        packet : Socket & Result<&2, &2, Datagram.DatagramError<Reason>, Datagram.Packet> <- Datagram.recv(Reason, socket, 65535, signal)
        readUdpQuery(Reason, signal, expected, local, receivedUdpQuery(Reason, expected, local, packet))

def sentUdpQuery(-Reason: Data, signal: Abort.AbortSignal<Reason>, expected: Message.Transaction, local: Endpoint.Endpoint, pair: Socket & Result<&2, &2, Datagram.DatagramError<Reason>, Unit>) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        Socket.close(socket)
        return Fail{UdpQueryTransport{error}}
    case (socket, Done{_}): readUdpQuery(Reason, signal, expected, local, UdpQueryContinue{socket})

def ownedUdpQuery(-Reason: Data, +signal: Abort.AbortSignal<Reason>, request: Message.Request, bytes: List<&2, U32>, owner: Peer.Owner) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match owner:
    case Peer.Owner{socket, Peer.Route{+local, +remote}}:
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        result : Socket & Result<&2, &2, Datagram.DatagramError<Reason>, Unit> <- Datagram.send(Reason, socket, remote, bytes, signal)
        sentUdpQuery(Reason, signal, transactionUdpQuery(Peer.Route{local, remote}, request), local, result)

def opened(-Reason: Data, signal: Abort.AbortSignal<Reason>, request: Message.Request, bytes: List<&2, U32>, result: Result<&2, &1, Peer.Error, Peer.Owner>) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>, Fail{Opening{error}})
    case Done{owner}: ownedUdpQuery(Reason, signal, request, bytes, owner)

def checkedUdpQuery(-Reason: Data, destination: Endpoint.Endpoint, signal: Abort.AbortSignal<Reason>, request: Message.Request, bytes: List<&2, U32>, reason: Maybe<&2, Abort.AbortReason<Reason>>) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>, Fail{Aborted{why}})
    case None{}:
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        peer : Result<&2, &1, Peer.Error, Peer.Owner> <- Peer.create(destination)
        opened(Reason, signal, request, bytes, peer)

def preparedUdpQuery(-Reason: Data, destination: Endpoint.Endpoint, +signal: Abort.AbortSignal<Reason>, request: Message.Request, result: Result<&2, &2, Message.EdnsError, List<&2, U32>>) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>, Fail{UdpQueryEncoding{error}})
    case Done{bytes}:
      do IO<Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>>:
        reason : Maybe<&2, Abort.AbortReason<Reason>> <- Abort.reason(Reason, signal)
        checkedUdpQuery(Reason, destination, signal, request, bytes, reason)

# One query on a dedicated numeric peer. The caller owns the attempt scope;
# return only after the socket and all per-operation abort watchers are closed.
def exchangeRequestUdpQuery(-Reason: Data, destination: Endpoint.Endpoint, signal: Abort.AbortSignal<Reason>, +request: Message.Request) -> IO(Result<&2, &2, UdpQueryError<Reason>, UdpQueryReply>):
  preparedUdpQuery(Reason, destination, signal, request, encode(request))

# This policy runs only after transaction matching. A retryable RCODE takes
# precedence over truncation. Complete messages use validated EDNS status.
type Status is Data:
  Success{}
  FailureCode{}
  NotImplementedCode{}
  RefusedCode{}
  Other{code: U32}

type UdpPolicyRejection is Data:
  ServerFailure{}
  NotImplemented{}
  Refused{}
  UnhelpfulEmpty{}

type UdpPolicyDecision is Data:
  Accept{}
  UseTCP{}
  Retry{reason: UdpPolicyRejection}

def statusUdpPolicy(code: U32) -> Status:
  match code:
    case 0: Success{}
    case 2: FailureCode{}
    case 4: NotImplementedCode{}
    case 5: RefusedCode{}
    case other: Other{other}

def transport(truncated: Bool, ignoreTruncation: Bool) -> UdpPolicyDecision:
  match truncated ignoreTruncation:
    case True{} False{}: UseTCP{}
    case _ _: Accept{}

def success(unhelpful: Bool, truncated: Bool, ignoreTruncation: Bool) -> UdpPolicyDecision:
  match unhelpful:
    case True{}: Retry{UnhelpfulEmpty{}}
    case False{}: transport(truncated, ignoreTruncation)

def decide(statusUdpPolicy: Status, unhelpful: Bool, truncated: Bool, ignoreTruncation: Bool) -> UdpPolicyDecision:
  match statusUdpPolicy:
    case FailureCode{}: Retry{ServerFailure{}}
    case NotImplementedCode{}: Retry{NotImplemented{}}
    case RefusedCode{}: Retry{Refused{}}
    case Success{}: success(unhelpful, truncated, ignoreTruncation)
    case Other{_}: transport(truncated, ignoreTruncation)

# Authority records do not enter the reference's empty-reply decision. AA,
# RA, answer count and additional count do. Keep that distinction explicit.
def headerCode(code: U32, value: Message.Header, ignoreTruncation: Bool) -> UdpPolicyDecision:
  match value:
    case Message.Header{_, +flags, _, answers, _, additional}:
      decide(statusUdpPolicy(code), U32.is_eq(answers, 0) && U32.is_eq(U32.and(flags, 1152), 0) && U32.is_eq(additional, 0), U32.is_ne(U32.and(flags, 512), 0), ignoreTruncation)

# Only a validated truncated header is available on the incomplete-message
# path. Complete responses instead enter message() to validate the OPT record.
def headerPolicy(+value: Message.Header, ignoreTruncation: Bool) -> UdpPolicyDecision:
  headerCode(Message.responseCode(value, None{}), value, ignoreTruncation)

def inspectedUdpPolicy(+fields: Message.Header, ignoreTruncation: Bool, extension: Result<&2, &2, Message.EdnsResponseError, Maybe<&2, Message.Response>>) -> Result<&2, &2, Message.EdnsResponseError, UdpPolicyDecision>:
  match extension:
    case Fail{error}: Fail{error}
    case Done{value}: Done{headerCode(Message.responseCode(fields, value), fields, ignoreTruncation)}

def messageHeader(value: Message.Message) -> Message.Header:
  match value:
    case Message.Message{_, fields, _, _, _, _}: fields

def messageUdpPolicy(+value: Message.Message, ignoreTruncation: Bool) -> Result<&2, &2, Message.EdnsResponseError, UdpPolicyDecision>:
  inspectedUdpPolicy(messageHeader(value), ignoreTruncation, Message.inspect(value))

type UdpServersFailure<-Reason: Data> is Data:
  InvalidExtension{error: Message.EdnsResponseError}
  UdpServersRejected{header: Message.Header, reason: UdpPolicyRejection}
  InvalidDestination{}
  InvalidBudget{error: Plan.MillisecondsError}
  Exchange{error: UdpQueryError<Deadline.Cause<Deadline.Cause<Reason>>>}

type UdpServersReport<-Reason: Data> is Data:
  UdpServersReport{server: Endpoint.Endpoint, failure: UdpServersFailure<Reason>, deadline: End<Reason>}

type UdpServersReply is Data:
  UdpServersReply{server: Endpoint.Endpoint, value: UdpQueryReply}

type UdpServersError<-Reason: Data> is Data:
  NoAttempts{}
  UdpServersFailed{report: UdpServersReport<Reason>}
  InvalidCursor{}

type UdpServersDecision<-Reason: Data> is Data:
  UdpServersAnswer{reply: UdpServersReply}
  UdpServersNext{last: Maybe<&2, UdpServersReport<Reason>>}
  UdpServersStop{report: UdpServersReport<Reason>}

def expired(-Reason: Data, why: Abort.AbortReason<Deadline.Cause<Deadline.Cause<Reason>>>) -> Bool:
  match why:
    case Abort.Supplied{Deadline.Expired{}}: True{}
    case _: False{}

def retryableUdpServers(-Reason: Data, error: UdpQueryError<Deadline.Cause<Deadline.Cause<Reason>>>) -> Bool:
  match error:
    case UdpQueryTransport{Datagram.DatagramSocketError{_, _}}: True{}
    case Opening{Peer.Association{_, _}}: True{}
    case Aborted{why}: expired(Reason, why)
    case UdpQueryTransport{Datagram.DatagramAborted{why}}: expired(Reason, why)
    case _: False{}

def retryUdpServers(-Reason: Data, allowed: Bool, report: UdpServersReport<Reason>) -> UdpServersDecision<Reason>:
  match allowed:
    case True{}: UdpServersNext{Some{report}}
    case False{}: UdpServersStop{report}

def failedUdpServers(-Reason: Data, endpoint: Endpoint.Endpoint, +error: UdpQueryError<Deadline.Cause<Deadline.Cause<Reason>>>, end: End<Reason>) -> UdpServersDecision<Reason>:
  match end:
    case ParentAborted{why}: UdpServersStop{UdpServersReport{endpoint, Exchange{error}, ParentAborted{why}}}
    case UnexpectedDefaultAbort{}: UdpServersStop{UdpServersReport{endpoint, Exchange{error}, UnexpectedDefaultAbort{}}}
    case other: retryUdpServers(Reason, retryableUdpServers(Reason, error), UdpServersReport{endpoint, Exchange{error}, other})

def rejected(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, reason: UdpPolicyRejection, end: End<Reason>) -> UdpServersDecision<Reason>:
  match end:
    case ParentAborted{why}: UdpServersStop{UdpServersReport{endpoint, UdpServersRejected{header, reason}, ParentAborted{why}}}
    case UnexpectedDefaultAbort{}: UdpServersStop{UdpServersReport{endpoint, UdpServersRejected{header, reason}, UnexpectedDefaultAbort{}}}
    case other: UdpServersNext{Some{UdpServersReport{endpoint, UdpServersRejected{header, reason}, other}}}

def selectedUdpServers(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, reply: UdpQueryReply, end: End<Reason>, decision: UdpPolicyDecision) -> UdpServersDecision<Reason>:
  match decision:
    case Retry{reason}: rejected(Reason, endpoint, header, reason, end)
    case _: UdpServersAnswer{UdpServersReply{endpoint, reply}}

def responseHeader(reply: UdpQueryReply) -> Message.Header:
  match reply:
    case UdpQueryTruncated{header}: header
    case UdpQueryAnswer{Message.Message{_, header, _, _, _, _}}: header

def disposition(reply: UdpQueryReply) -> Result<&2, &2, Message.EdnsResponseError, UdpPolicyDecision>:
  match reply:
    case UdpQueryAnswer{message}: messageUdpPolicy(message, False{})
    case UdpQueryTruncated{header}: Done{headerPolicy(header, False{})}

def assessed(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, reply: UdpQueryReply, end: End<Reason>, result: Result<&2, &2, Message.EdnsResponseError, UdpPolicyDecision>) -> UdpServersDecision<Reason>:
  match result:
    case Fail{error}: UdpServersStop{UdpServersReport{endpoint, InvalidExtension{error}, end}}
    case Done{decision}: selectedUdpServers(Reason, endpoint, header, reply, end, decision)

def answered(-Reason: Data, endpoint: Endpoint.Endpoint, header: Message.Header, +reply: UdpQueryReply, end: End<Reason>) -> UdpServersDecision<Reason>:
  assessed(Reason, endpoint, header, reply, end, disposition(reply))

# An accepted reply remains a reply even when scope
# closure observes a later expiry. UdpServersFailed attempts retain cleanup-time reasons.
def completedUdpServers(-Reason: Data, endpoint: Endpoint.Endpoint, result: Result<&2, &2, UdpQueryError<Deadline.Cause<Deadline.Cause<Reason>>>, UdpQueryReply>, end: End<Reason>) -> UdpServersDecision<Reason>:
  match result:
    case Done{+reply}: answered(Reason, endpoint, responseHeader(reply), reply, end)
    case Fail{error}: failedUdpServers(Reason, endpoint, error, end)

def scopedUdpServers(-Reason: Data, +endpoint: Endpoint.Endpoint, request: Message.Request, pair: Deadline.Scope<Deadline.Cause<Reason>> & Abort.AbortSignal<Deadline.Cause<Deadline.Cause<Reason>>>) -> IO(UdpServersDecision<Reason>):
  match pair:
    case (scope, signal):
      do IO<UdpServersDecision<Reason>>:
        result : Result<&2, &2, UdpQueryError<Deadline.Cause<Deadline.Cause<Reason>>>, UdpQueryReply> <- exchangeRequestUdpQuery(Deadline.Cause<Deadline.Cause<Reason>>, endpoint, signal, request)
        end : End<Reason> <- closeUdpAttemptScope(Reason, scope)
        return completedUdpServers(Reason, endpoint, result, end)

def created(-Reason: Data, endpoint: Endpoint.Endpoint, request: Message.Request, result: Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>>) -> IO(UdpServersDecision<Reason>):
  match result:
    case Fail{error}: IO.pure(UdpServersDecision<Reason>, UdpServersStop{UdpServersReport{endpoint, InvalidBudget{error}, Active{}}})
    case Done{scope}: scopedUdpServers(Reason, endpoint, request, Deadline.borrow(Deadline.Cause<Reason>, scope))

def validPort(+port: U32) -> Bool: U32.is_gt(port, 0) && U32.is_le(port, 65535)

def valid(endpoint: Endpoint.Endpoint) -> Bool:
  match endpoint:
    case Endpoint.EndpointV4{_, port}: validPort(port)
    case Endpoint.EndpointV6{_, port, _}: validPort(port)

def checkedUdpServers(-Reason: Data, valid: Bool, endpoint: Endpoint.Endpoint, duration: Plan.Duration, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request) -> IO(UdpServersDecision<Reason>):
  match valid:
    case False{}: IO.pure(UdpServersDecision<Reason>, UdpServersStop{UdpServersReport{endpoint, InvalidDestination{}, Active{}}})
    case True{}:
      do IO<UdpServersDecision<Reason>>:
        scope : Result<&2, &1, Plan.MillisecondsError, Deadline.Scope<Deadline.Cause<Reason>>> <- createUdpAttemptScope(Reason, duration, signal)
        created(Reason, endpoint, request, scope)

def attempt(-Reason: Data, entry: Plan.Attempt<Endpoint.Endpoint>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request) -> IO(UdpServersDecision<Reason>):
  match entry:
    case Plan.Attempt{+endpoint, _, duration}: checkedUdpServers(Reason, valid(endpoint), endpoint, duration, signal, request)

def exhaustedUdpServers(-Reason: Data, last: Maybe<&2, UdpServersReport<Reason>>) -> Result<&2, &2, UdpServersError<Reason>, UdpServersReply>:
  match last:
    case None{}: Fail{NoAttempts{}}
    case Some{report}: Fail{UdpServersFailed{report}}

# The finite bound is the exact initial schedule size, never a packet budget.
# Each recursive step consumes one scheduled attempt; reads retain their own
# unchanged deadline regardless of how many unrelated packets they encounter.
def driveUdpServers(-Reason: Data, fuel: Nat, step: Plan.Step<Plan.Attempt<Endpoint.Endpoint>>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, decision: UdpServersDecision<Reason>) -> IO(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>):
  match fuel step decision:
    case _ _ UdpServersAnswer{reply}: IO.pure(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>, Done{reply})
    case _ _ UdpServersStop{report}: IO.pure(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>, Fail{UdpServersFailed{report}})
    case _ Plan.Exhausted{} UdpServersNext{last}: IO.pure(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>, exhaustedUdpServers(Reason, last))
    case Zero{} Plan.Try{_, _} UdpServersNext{_}: IO.pure(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>, Fail{InvalidCursor{}})
    case Succ{rest} Plan.Try{entry, next} UdpServersNext{_}:
      do IO<Result<&2, &2, UdpServersError<Reason>, UdpServersReply>>:
        result : UdpServersDecision<Reason> <- attempt(Reason, entry, signal, request)
        driveUdpServers(Reason, rest, Plan.next(Plan.Attempt<Endpoint.Endpoint>, next), signal, request, result)

# Entries are already positioned/timed/rotated. Borrow one total deadline and
# reuse the identical request through every attempt. Return the selected server
# with a reply so a later TCP fallback can target that same endpoint.
# Retryable response codes advance this same cursor. Truncation retains the
# selected endpoint for TCP fallback; EDNS negotiation remains above this layer.
def exchangeRequestUdpServers(-Reason: Data, +attempts: Nat, +servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request) -> IO(Result<&2, &2, UdpServersError<Reason>, UdpServersReply>):
  driveUdpServers(Reason, Nat.mul(attempts, List.length(&2, Plan.Attempt<Endpoint.Endpoint>, servers)), Plan.next(Plan.Attempt<Endpoint.Endpoint>, Plan.start(Plan.Attempt<Endpoint.Endpoint>, attempts, servers)), signal, request, UdpServersNext{None{}})

type Operation is Data:
  Sending{}
  ReadingLength{}
  ReadingPayload{}

def readOperation(reader: Message.Reader) -> Operation:
  match reader:
    case Message.Payload{_, _}: ReadingPayload{}
    case _: ReadingLength{}

type TcpConnectionError<-Reason: Data> is Data:
  Framing{error: Message.TcpFrameError}
  Transport{operation: Operation, error: SocketIO.Error<Reason>}
  InvalidReadSize{}

type Position<-Reason: Data> is Data:
  Reading{reader: Message.Reader, unread: List<&2, U32>}
  Ended{error: Maybe<&2, TcpConnectionError<Reason>>}

type Connection<-Reason: Data> is Type:
  Connection{socket: SocketIO.Owner<Reason>, position: Position<Reason>}

type Next<-Reason: Data> is Type:
  Next{connection: Connection<Reason>, result: Result<&2, &2, TcpConnectionError<Reason>, Maybe<&2, List<&2, U32>>>}

type Step<-Reason: Data> is Type:
  Ready{value: Next<Reason>}
  Pull{socket: SocketIO.Owner<Reason>, reader: Message.Reader}

def adopt(-Reason: Data, socket: SocketIO.Owner<Reason>) -> Connection<Reason>:
  Connection{socket, Reading{Message.newTcpFrame(), Nil{}}}

def terminal(-Reason: Data, error: Maybe<&2, TcpConnectionError<Reason>>) -> Result<&2, &2, TcpConnectionError<Reason>, Maybe<&2, List<&2, U32>>>:
  match error:
    case None{}: Done{None{}}
    case Some{why}: Fail{why}

def endedTcpConnection(-Reason: Data, socket: SocketIO.Owner<Reason>, +error: Maybe<&2, TcpConnectionError<Reason>>) -> Step<Reason>:
  Ready{Next{Connection{socket, Ended{error}}, terminal(Reason, error)}}

def decoded(-Reason: Data, socket: SocketIO.Owner<Reason>, result: Message.ReadResult) -> Step<Reason>:
  match result:
    case Message.More{reader}: Pull{socket, reader}
    case Message.Frame{bytes, rest}: Ready{Next{Connection{socket, Reading{Message.newTcpFrame(), rest}}, Done{Some{bytes}}}}
    case Message.TcpFrameFailed{error}: endedTcpConnection(Reason, socket, Some{Framing{error}})

def eof(-Reason: Data, socket: SocketIO.Owner<Reason>, result: Result<&2, &2, Message.TcpFrameError, Unit>) -> Step<Reason>:
  match result:
    case Done{_}: endedTcpConnection(Reason, socket, None{})
    case Fail{error}: endedTcpConnection(Reason, socket, Some{Framing{error}})

def received(-Reason: Data, reader: Message.Reader, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, List<&2, U32>>) -> Step<Reason>:
  match pair:
    case (socket, Fail{error}): endedTcpConnection(Reason, socket, Some{Transport{readOperation(reader), error}})
    case (socket, Done{Nil{}}): eof(Reason, socket, Message.finish(reader))
    case (socket, Done{byte <> rest}): decoded(Reason, socket, Message.read(reader, byte <> rest))

# Every recursive step awaits a read. A nonempty read advances the bounded
# frame; EOF and errors settle it. The checker cannot express IO progress.
@unsafe def driveTcpConnection(-Reason: Data, +maximum: U32, step: Step<Reason>) -> IO(Next<Reason>):
  match step:
    case Ready{value}: IO.pure(Next<Reason>, value)
    case Pull{socket, reader}:
      do IO<Next<Reason>>:
        result : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, List<&2, U32>> <- SocketIO.recvSocket(Reason, socket, maximum)
        driveTcpConnection(Reason, maximum, received(Reason, reader, result))

def inspected(-Reason: Data, reader: Message.Reader, unread: List<&2, U32>, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit>) -> Step<Reason>:
  match pair:
    case (socket, Fail{error}): endedTcpConnection(Reason, socket, Some{Transport{readOperation(reader), error}})
    case (socket, Done{_}): decoded(Reason, socket, Message.read(reader, unread))

def pendingTcpConnection(-Reason: Data, connection: Connection<Reason>) -> IO(Step<Reason>):
  match connection:
    case Connection{socket, Reading{reader, unread}}:
      do IO<Step<Reason>>:
        checked : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit> <- SocketIO.run(Reason, Unit, socket, owned => IO.pure(Socket & Result<&1, &1, U32 & String, Unit>, (owned, Done{Unit{}})))
        return inspected(Reason, reader, unread, checked)
    case Connection{socket, Ended{error}}: IO.pure(Step<Reason>, endedTcpConnection(Reason, socket, error))

# Check retained abort state even when a complete frame is already buffered.
# Terminal read results repeat without further IO. The caller must still close
# the affine connection, including after EOF or failure, to join its watcher.
def receiveTcpConnection(-Reason: Data, connection: Connection<Reason>, maximum: U32) -> IO(Next<Reason>):
  match maximum:
    case 0: IO.pure(Next<Reason>, Next{connection, Fail{InvalidReadSize{}}})
    case size:
      do IO<Next<Reason>>:
        step : Step<Reason> <- pendingTcpConnection(Reason, connection)
        driveTcpConnection(Reason, size, step)

def sent(-Reason: Data, position: Position<Reason>, pair: SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit>) -> Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>:
  match pair:
    case (socket, Done{_}): (Connection{socket, position}, Done{Unit{}})
    case (socket, Fail{error}): (Connection{socket, position}, Fail{Transport{Sending{}, error}})

def sendFrame(-Reason: Data, connection: Connection<Reason>, result: Result<&2, &2, Message.TcpFrameError, List<&2, U32>>) -> IO(Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>):
  match connection result:
    case owner Fail{error}: IO.pure(Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>, (owner, Fail{Framing{error}}))
    case Connection{socket, position} Done{wire}:
      do IO<Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>>:
        result : SocketIO.Owner<Reason> & Result<&2, &2, SocketIO.Error<Reason>, Unit> <- SocketIO.sendSocket(Reason, socket, wire)
        return sent(Reason, position, result)

# Encoding failure leaves the connection untouched. A transport write failure
# may follow a partial write; the caller must close rather than retry that frame.
# Multiple sends before receive support pipelining; transaction IDs are managed
# above this layer, and frames are returned in their actual arrival order.
def send(-Reason: Data, connection: Connection<Reason>, bytes: List<&2, U32>) -> IO(Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>):
  sendFrame(Reason, connection, Message.encodeTcpFrame(bytes))

def closeTcpConnection(-Reason: Data, connection: Connection<Reason>) -> IO(Result<&2, &2, Interrupt.InterruptError, Unit>):
  match connection:
    case Connection{socket, _}: SocketIO.close(Reason, socket)

# A snapshot of a connected socket's endpoints. No wildcard/requested messageEndpoint
# is substituted for the messageEndpoint actually selected by the operating system.
type Route is Data:
  Route{localTcpPeer: Message.Endpoint, remoteTcpPeer: Message.Endpoint}

type Peer<-Reason: Data> is Type:
  Peer{route: Route, connection: Connection<Reason>}

type TcpPeerError<-Reason: Data> is Data:
  Inspection{error: Endpoint.EndpointError}
  Adoption{error: SocketIO.Error<Reason>}

def adopted(-Reason: Data, route: Route, result: Result<&2, &1, SocketIO.Error<Reason>, SocketIO.Owner<Reason>>) -> Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>:
  match result:
    case Fail{error}: Fail{Adoption{error}}
    case Done{socket}: Done{Peer{route, adopt(Reason, socket)}}

def remoteTcpPeer(-Reason: Data, localTcpPeer: Message.Endpoint, signal: Abort.AbortSignal<Reason>, pair: Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint>) -> IO(Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{at}):
      do IO<Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>>:
        result : Result<&2, &1, SocketIO.Error<Reason>, SocketIO.Owner<Reason>> <- SocketIO.create(Reason, socket, signal)
        return adopted(Reason, Route{localTcpPeer, messageEndpoint(at)}, result)

def localTcpPeer(-Reason: Data, signal: Abort.AbortSignal<Reason>, pair: Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint>) -> IO(Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>):
  match pair:
    case (socket, Fail{error}):
      do IO<Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>>:
        Socket.close(socket)
        return Fail{Inspection{error}}
    case (socket, Done{at}):
      do IO<Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>>:
        result : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Peer{})
        remoteTcpPeer(Reason, messageEndpoint(at), signal, result)

# Consumes the connected socket, including on failure. Adoption checks retained
# abort after endpoint inspection and installs the connection's single watcher.
# Signal ownership stays with the caller until the TCP connection is closed.
def createTcpPeer(-Reason: Data, socket: Socket, signal: Abort.AbortSignal<Reason>) -> IO(Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>):
  do IO<Result<&2, &1, TcpPeerError<Reason>, Peer<Reason>>>:
    result : Socket & Result<&2, &2, Endpoint.EndpointError, Endpoint.Endpoint> <- Endpoint.get(socket, Endpoint.Local{})
    localTcpPeer(Reason, signal, result)

def buildTransaction(route: Route, id: U32, opcode: U32, question: Message.Question) -> Message.Transaction:
  match route:
    case Route{sentFrom, sentTo}: Message.Transaction{sentFrom, sentTo, id, opcode, question}

# Frame delivery remains explicit: a caller may dispatch out-of-order replies
# to several outstanding transactions without this layer discarding frames.
def inspect(route: Route, expected: Message.Transaction, wire: List<&2, U32>) -> Message.Decision:
  match route:
    case Route{receivedAt, receivedFrom}: Message.inspectStream(expected, receivedFrom, receivedAt, wire)

# One table belongs to one transport connection. Tokens are caller-owned
# correlation values, not callbacks or mutable promises.
# Tickets are scoped to one session history. Serial numbers never wrap;
# an exhausted session must be replaced instead of reusing a cancellation key.
type Ticket is Data:
  Ticket{id: U32, serial: U32}

type Entry<-Token: Data> is Data:
  Entry{transaction: Message.Transaction, token: Token, ticket: Ticket}

type Pending<-Token: Data> is Data:
  Pending{entries: Map<&2, Entry<Token>>, next: Maybe<&2, U32>}

type RegistrationError is Data:
  InvalidId{}
  DuplicateId{}
  Exhausted{}

type Registered<-Token: Data> is Data:
  Registered{pending: Pending<Token>, result: Result<&2, &2, RegistrationError, Ticket>}

type Rejection is Data:
  MissingId{}
  UnknownId{id: U32}
  Mismatch{reason: Message.Rejection}

type Delivery<-Token: Data> is Data:
  Ignored{reason: Rejection}
  Answer{token: Token, message: Message.Message}
  Truncated{token: Token, header: Message.Header}

type Received<-Token: Data> is Data:
  Received{pending: Pending<Token>, delivery: Delivery<Token>}

type Removed<-Token: Data> is Data:
  Removed{pending: Pending<Token>, entry: Maybe<&2, Entry<Token>>}

def new(-Token: Data) -> Pending<Token>:
  Pending{Map.new(&2, Entry<Token>), Some{0}}

def nextSerial(last: Bool, value: U32) -> Maybe<&2, U32>:
  match last:
    case True{}: None{}
    case False{}: Some{(value + 1 : U32)}

def inserted(-Token: Data, +serial: U32, +ticket: Ticket, key: String, entry: Entry<Token>, pair: Map<&2, Entry<Token>> & Bool) -> Registered<Token>:
  match pair:
    case (pendingEntries, True{}): Registered{Pending{pendingEntries, Some{serial}}, Fail{DuplicateId{}}}
    case (pendingEntries, False{}): Registered{Pending{Map.set(&2, Entry<Token>, pendingEntries, key, entry), nextSerial(U32.is_eq(serial, 4294967295), serial)}, Done{ticket}}

def registerId(-Token: Data, valid: Bool, pending: Pending<Token>, +id: U32, transaction: Message.Transaction, token: Token) -> Registered<Token>:
  match valid pending:
    case False{} pending: Registered{pending, Fail{InvalidId{}}}
    case True{} Pending{pendingEntries, None{}}: Registered{Pending{pendingEntries, None{}}, Fail{Exhausted{}}}
    case True{} Pending{pendingEntries, Some{+serial}}: inserted(Token, serial, Ticket{id, serial}, Message.key(id), Entry{transaction, token, Ticket{id, serial}}, Map.has(&2, Entry<Token>, pendingEntries, Message.key(id)))

# Register before sending. Duplicate IDs never replace an outstanding query.
# Random ID allocation, retries and deadlines belong to the transport driver.
def register(-Token: Data, pending: Pending<Token>, transaction: Message.Transaction, token: Token) -> Registered<Token>:
  match transaction:
    case Message.Transaction{from, to, +id, opcode, question}: registerId(Token, U32.is_le(id, 65535), pending, id, Message.Transaction{from, to, id, opcode, question}, token)

def removed(-Token: Data, next: Maybe<&2, U32>, pair: Map<&2, Entry<Token>> & Maybe<&2, Entry<Token>>) -> Removed<Token>:
  match pair:
    case (pendingEntries, entry): Removed{Pending{pendingEntries, next}, entry}

def removeId(-Token: Data, valid: Bool, pending: Pending<Token>, id: U32) -> Removed<Token>:
  match valid pending:
    case False{} pending: Removed{pending, None{}}
    case True{} Pending{pendingEntries, next}: removed(Token, next, Map.pop(&2, Entry<Token>, pendingEntries, Message.key(id)))

# The owner serializes registration/removal; an ID alone is not a capability
# for cancelling a later query after that ID has been reused.
def remove(-Token: Data, pending: Pending<Token>, +id: U32) -> Removed<Token>:
  removeId(Token, U32.is_le(id, 65535), pending, id)

def decided(-Token: Data, original: Pending<Token>, remaining: Pending<Token>, token: Token, decision: Message.Decision) -> Received<Token>:
  match decision:
    case Message.Ignore{reason}: Received{original, Ignored{Mismatch{reason}}}
    case Message.Matched{message}: Received{remaining, Answer{token, message}}
    case Message.ResponseTruncated{header}: Received{remaining, Truncated{token, header}}

def selectedPending(-Token: Data, original: Pending<Token>, id: U32, source: Message.Endpoint, destination: Message.Endpoint, wire: List<&2, U32>, value: Removed<Token>) -> Received<Token>:
  match value:
    case Removed{_, None{}}: Received{original, Ignored{UnknownId{id}}}
    case Removed{remaining, Some{Entry{transaction, token, _}}}: decided(Token, original, remaining, token, Message.inspectStream(transaction, source, destination, wire))

def identified(-Token: Data, valid: Bool, +pending: Pending<Token>, +id: U32, source: Message.Endpoint, destination: Message.Endpoint, wire: List<&2, U32>) -> Received<Token>:
  match valid:
    case False{}: Received{pending, Ignored{MissingId{}}}
    case True{}: selectedPending(Token, pending, id, source, destination, wire, remove(Token, pending, id))

# Read only the two ID octets to choose the expected transaction. The existing
# matcher then validates the complete response once. Ignored frames leave the
# table unchanged; accepted replies/truncation settle precisely one entry.
def receive(-Token: Data, pending: Pending<Token>, source: Message.Endpoint, destination: Message.Endpoint, wire: List<&2, U32>) -> Received<Token>:
  match wire:
    case +high <> +low <> rest: identified(Token, U32.is_le(high, 255) && U32.is_le(low, 255), pending, ((high * 256) + low : U32), source, destination, high <> low <> rest)
    case _: Received{pending, Ignored{MissingId{}}}

# Connection-wide settlement returns every still-pending correlation exactly
# once to the driver. Ordering is deliberately not a request-order guarantee.
def values(-Token: Data, pendingEntries: List<&2, Sigma<&2, &2, String, _ => Entry<Token>>>, reversed: List<&2, Entry<Token>>) -> List<&2, Entry<Token>>:
  match pendingEntries:
    case Nil{}: List.reverse(&2, Entry<Token>, reversed)
    case (_, entry) <> rest: values(Token, rest, entry <> reversed)

def drain(-Token: Data, pending: Pending<Token>) -> List<&2, Entry<Token>>:
  match pending:
    case Pending{pendingEntries, _}: values(Token, Map.to_list(&2, Entry<Token>, pendingEntries), Nil{})


def cancelMatch(-Token: Data, equal: Bool, original: Pending<Token>, remaining: Pending<Token>, entry: Entry<Token>) -> Removed<Token>:
  match equal:
    case True{}: Removed{remaining, Some{entry}}
    case False{}: Removed{original, None{}}

def cancelled(-Token: Data, original: Pending<Token>, serial: U32, value: Removed<Token>) -> Removed<Token>:
  match value:
    case Removed{_, None{}}: Removed{original, None{}}
    case Removed{remaining, Some{Entry{transaction, token, Ticket{id, +actual}}}}: cancelMatch(Token, U32.is_eq(serial, actual), original, remaining, Entry{transaction, token, Ticket{id, actual}})

# Stale or repeated cancellation is a no-op, including after ID reuse. This
# does not retract bytes already sent or prevent an indistinguishable delayed
# DNS reply after wire-ID reuse; the higher-level transport owns reuse policy.
def cancel(-Token: Data, +pending: Pending<Token>, ticket: Ticket) -> Removed<Token>:
  match ticket:
    case Ticket{id, serial}: cancelled(Token, pending, serial, remove(Token, pending, id))

type Failure<-Reason: Data> is Data:
  EndOfStream{}
  TcpSessionTransport{error: TcpConnectionError<Reason>}

type TcpSessionError<-Reason: Data> is Data:
  Query{error: Message.Error}
  Extension{error: Message.EdnsError}
  Registration{error: RegistrationError}
  TcpSessionInvalidReadSize{}
  Stopped{failure: Failure<Reason>}

type Session<-Reason: Data, -Token: Data> is Type:
  Session{route: Route, connection: Connection<Reason>, pending: Pending<Token>, ended: Maybe<&2, Failure<Reason>>}

type Outcome<-Reason: Data, -Token: Data> is Data:
  Submitted{ticket: Ticket}
  Cancelled{entry: Maybe<&2, Entry<Token>>}
  Rejected{error: TcpSessionError<Reason>}
  Response{delivery: Delivery<Token>}
  TcpSessionEnded{failure: Failure<Reason>, outstanding: List<&2, Entry<Token>>}

type TcpSessionStep<-Reason: Data, -Token: Data> is Type:
  TcpSessionStep{session: Session<Reason, Token>, event: Outcome<Reason, Token>}

type Closed<-Token: Data> is Data:
  Closed{outstanding: List<&2, Entry<Token>>, cleanup: Result<&2, &2, Interrupt.InterruptError, Unit>}

def adoptTcpSession(-Reason: Data, -Token: Data, peer: Peer<Reason>) -> Session<Reason, Token>:
  match peer:
    case Peer{route, connection}: Session{route, connection, new(Token), None{}}

def failedTcpSession(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, pending: Pending<Token>, +why: Failure<Reason>) -> TcpSessionStep<Reason, Token>:
  TcpSessionStep{Session{route, connection, new(Token), Some{why}}, TcpSessionEnded{why, drain(Token, pending)}}

def sentTcpSession(-Reason: Data, -Token: Data, ticket: Ticket, route: Route, pending: Pending<Token>, pair: Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit>) -> TcpSessionStep<Reason, Token>:
  match pair:
    case (connection, Done{_}): TcpSessionStep{Session{route, connection, pending, None{}}, Submitted{ticket}}
    case (connection, Fail{error}): failedTcpSession(Reason, Token, route, connection, pending, TcpSessionTransport{error})

def registered(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, wire: List<&2, U32>, value: Registered<Token>) -> IO(TcpSessionStep<Reason, Token>):
  match value:
    case Registered{pending, Fail{error}}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, None{}}, Rejected{Registration{error}}})
    case Registered{pending, Done{ticket}}:
      do IO<TcpSessionStep<Reason, Token>>:
        result : Connection<Reason> & Result<&2, &2, TcpConnectionError<Reason>, Unit> <- send(Reason, connection, wire)
        return sentTcpSession(Reason, Token, ticket, route, pending, result)

def encoded(-Reason: Data, -Token: Data, +route: Route, connection: Connection<Reason>, pending: Pending<Token>, id: U32, flags: U32, question: Message.Question, token: Token, result: Result<&2, &2, Message.Error, List<&2, U32>>) -> IO(TcpSessionStep<Reason, Token>):
  match result:
    case Fail{error}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, None{}}, Rejected{Query{error}}})
    case Done{wire}: registered(Reason, Token, route, connection, wire, register(Token, pending, buildTransaction(route, id, (flags / 2048 % 16 : U32), question), token))

# The affine session serializes operations. Several queries can be submitted
# before receiving; registration precedes the first byte written. A failed
# write may be partial, so it permanently ends this session and settles all
# pending requests, including the attempted submission. No frame is retried.
def submit(-Reason: Data, -Token: Data, session: Session<Reason, Token>, +id: U32, +flags: U32, +question: Message.Question, token: Token) -> IO(TcpSessionStep<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, Some{why}}, Rejected{Stopped{why}}})
    case Session{route, connection, pending, None{}}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Message.query(id, flags, question))

def extendedEncoded(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, pending: Pending<Token>, id: U32, flags: U32, question: Message.Question, token: Token, result: Result<&2, &2, Message.EdnsError, List<&2, U32>>) -> IO(TcpSessionStep<Reason, Token>):
  match result:
    case Fail{Message.EdnsMessage{error}}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Fail{error})
    case Fail{error}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, None{}}, Rejected{Extension{error}}})
    case Done{wire}: encoded(Reason, Token, route, connection, pending, id, flags, question, token, Done{wire})

# Use the same pending table and transport as plain queries. Validation errors
# leave the live session unchanged; an ended session takes precedence over
# encoding. Successful encoding still registers before the first byte written.
def submitEdns(-Reason: Data, -Token: Data, session: Session<Reason, Token>, +id: U32, +flags: U32, +question: Message.Question, token: Token, extension: Message.Query) -> IO(TcpSessionStep<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, Some{why}}, Rejected{Stopped{why}}})
    case Session{route, connection, pending, None{}}: extendedEncoded(Reason, Token, route, connection, pending, id, flags, question, token, Message.queryEdns(id, flags, question, extension))

# Both forms use the same registration, write and settlement implementation.
def submitRequest(-Reason: Data, -Token: Data, session: Session<Reason, Token>, request: Message.Request, token: Token) -> IO(TcpSessionStep<Reason, Token>):
  match request:
    case Message.Request{id, flags, question, None{}}: submit(Reason, Token, session, id, flags, question, token)
    case Message.Request{id, flags, question, Some{extension}}: submitEdns(Reason, Token, session, id, flags, question, token, extension)

def dispatched(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, value: Received<Token>) -> TcpSessionStep<Reason, Token>:
  match value:
    case Received{pending, delivery}: TcpSessionStep{Session{route, connection, pending, None{}}, Response{delivery}}

def packetTcpSession(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, pending: Pending<Token>, wire: List<&2, U32>) -> TcpSessionStep<Reason, Token>:
  match route:
    case Route{+local, +remote}: dispatched(Reason, Token, Route{local, remote}, connection, receive(Token, pending, remote, local, wire))

def receivedTcpSession(-Reason: Data, -Token: Data, route: Route, pending: Pending<Token>, next: Next<Reason>) -> TcpSessionStep<Reason, Token>:
  match next:
    case Next{connection, Fail{error}}: failedTcpSession(Reason, Token, route, connection, pending, TcpSessionTransport{error})
    case Next{connection, Done{None{}}}: failedTcpSession(Reason, Token, route, connection, pending, EndOfStream{})
    case Next{connection, Done{Some{wire}}}: packetTcpSession(Reason, Token, route, connection, pending, wire)

def readTcpSession(-Reason: Data, -Token: Data, session: Session<Reason, Token>, maximum: U32) -> IO(TcpSessionStep<Reason, Token>):
  match session:
    case Session{route, connection, pending, Some{+why}}: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{Session{route, connection, pending, Some{why}}, TcpSessionEnded{why, Nil{}}})
    case Session{route, connection, pending, None{}}:
      do IO<TcpSessionStep<Reason, Token>>:
        next : Next<Reason> <- receiveTcpConnection(Reason, connection, maximum)
        return receivedTcpSession(Reason, Token, route, pending, next)

# Return each frame decision, including ignored frames. The caller controls
# scheduling rather than an unbounded internal loop starving other commands.
def receiveTcpSession(-Reason: Data, -Token: Data, session: Session<Reason, Token>, maximum: U32) -> IO(TcpSessionStep<Reason, Token>):
  match maximum:
    case 0: IO.pure(TcpSessionStep<Reason, Token>, TcpSessionStep{session, Rejected{TcpSessionInvalidReadSize{}}})
    case size: readTcpSession(Reason, Token, session, size)

# Close is required even after TcpSessionEnded. It joins the connection watcher and
# returns any unsettled entries rather than silently abandoning callers.
def closeTcpSession(-Reason: Data, -Token: Data, session: Session<Reason, Token>) -> IO(Closed<Token>):
  match session:
    case Session{_, connection, pending, _}:
      do IO<Closed<Token>>:
        cleanup : Result<&2, &2, Interrupt.InterruptError, Unit> <- closeTcpConnection(Reason, connection)
        return Closed{drain(Token, pending), cleanup}


def cancelledTcpSession(-Reason: Data, -Token: Data, route: Route, connection: Connection<Reason>, ended: Maybe<&2, Failure<Reason>>, result: Removed<Token>) -> TcpSessionStep<Reason, Token>:
  match result:
    case Removed{pending, entry}: TcpSessionStep{Session{route, connection, pending, ended}, Cancelled{entry}}

# Local request cancellation does not shut down the shared TCP connection.
# Admission remains serialized by session ownership; no watcher is detached.
def cancelTcpSession(-Reason: Data, -Token: Data, session: Session<Reason, Token>, ticket: Ticket) -> TcpSessionStep<Reason, Token>:
  match session:
    case Session{route, connection, pending, ended}: cancelledTcpSession(Reason, Token, route, connection, ended, cancel(Token, pending, ticket))

type Reply is Data:
  TcpQueryAnswer{message: Message.Message}
  TcpQueryTruncated{header: Message.Header}

type TcpQueryError<-Reason: Data> is Data:
  TcpQueryInvalidReadSize{}
  TcpQueryConnection{error: Connect.Error<Deadline.Cause<Reason>>}
  TcpQueryAdoption{error: TcpPeerError<Deadline.Cause<Reason>>}
  Submission{error: TcpSessionError<Deadline.Cause<Reason>>}
  Terminated{failure: Failure<Deadline.Cause<Reason>>}
  InvalidState{}

# Preserve the primary result if socket cleanup also fails. A late deadline
# reason is diagnostic; it does not retroactively replace a completed reply.
type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, TcpQueryError<Reason>, Reply>, cleanup: Result<&2, &2, Interrupt.InterruptError, Unit>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Completed<-Reason: Data> is Data:
  Completed{result: Result<&2, &2, TcpQueryError<Reason>, Reply>, cleanup: Result<&2, &2, Interrupt.InterruptError, Unit>}

type TcpQueryReading<-Reason: Data> is Type:
  TcpQueryContinue{session: Session<Deadline.Cause<Reason>, Unit>}
  Finish{session: Session<Deadline.Cause<Reason>, Unit>, result: Result<&2, &2, TcpQueryError<Reason>, Reply>}

def cleaned(-Reason: Data, result: Result<&2, &2, TcpQueryError<Reason>, Reply>, closed: Closed<Unit>) -> Completed<Reason>:
  match closed:
    case Closed{_, status}: Completed{result, status}

def finish(-Reason: Data, session: Session<Deadline.Cause<Reason>, Unit>, result: Result<&2, &2, TcpQueryError<Reason>, Reply>) -> IO(Completed<Reason>):
  do IO<Completed<Reason>>:
    closed : Closed<Unit> <- closeTcpSession(Deadline.Cause<Reason>, Unit, session)
    return cleaned(Reason, result, closed)

def receivedTcpQuery(-Reason: Data, step: TcpSessionStep<Deadline.Cause<Reason>, Unit>) -> TcpQueryReading<Reason>:
  match step:
    case TcpSessionStep{session, Response{Ignored{_}}}: TcpQueryContinue{session}
    case TcpSessionStep{session, Response{Answer{_, message}}}: Finish{session, Done{TcpQueryAnswer{message}}}
    case TcpSessionStep{session, Response{Truncated{_, header}}}: Finish{session, Done{TcpQueryTruncated{header}}}
    case TcpSessionStep{session, TcpSessionEnded{failure, _}}: Finish{session, Fail{Terminated{failure}}}
    case TcpSessionStep{session, Rejected{error}}: Finish{session, Fail{Submission{error}}}
    case TcpSessionStep{session, _}: Finish{session, Fail{InvalidState{}}}

# A dedicated query connection has no other recipient for ignored frames.
# Each continuation awaits abort-aware socket IO; the same deadline remains
# active across all ignored replies. No retry or fresh timeout is introduced.
@unsafe def read(-Reason: Data, +maximum: U32, state: TcpQueryReading<Reason>) -> IO(Completed<Reason>):
  match state:
    case Finish{session, result}: finish(Reason, session, result)
    case TcpQueryContinue{session}:
      do IO<Completed<Reason>>:
        step : TcpSessionStep<Deadline.Cause<Reason>, Unit> <- receiveTcpSession(Deadline.Cause<Reason>, Unit, session, maximum)
        read(Reason, maximum, receivedTcpQuery(Reason, step))

def submitted(-Reason: Data, maximum: U32, step: TcpSessionStep<Deadline.Cause<Reason>, Unit>) -> IO(Completed<Reason>):
  match step:
    case TcpSessionStep{session, Submitted{_}}: read(Reason, maximum, TcpQueryContinue{session})
    case TcpSessionStep{session, Rejected{error}}: finish(Reason, session, Fail{Submission{error}})
    case TcpSessionStep{session, TcpSessionEnded{failure, _}}: finish(Reason, session, Fail{Terminated{failure}})
    case TcpSessionStep{session, _}: finish(Reason, session, Fail{InvalidState{}})

def adoptedTcpQuery(-Reason: Data, request: Message.Request, maximum: U32, result: Result<&2, &1, TcpPeerError<Deadline.Cause<Reason>>, Peer<Deadline.Cause<Reason>>>) -> IO(Completed<Reason>):
  match result:
    case Fail{error}: IO.pure(Completed<Reason>, Completed{Fail{TcpQueryAdoption{error}}, Done{Unit{}}})
    case Done{peer}:
      do IO<Completed<Reason>>:
        step : TcpSessionStep<Deadline.Cause<Reason>, Unit> <- submitRequest(Deadline.Cause<Reason>, Unit, adoptTcpSession(Deadline.Cause<Reason>, Unit, peer), request, Unit{})
        submitted(Reason, maximum, step)

def connected(-Reason: Data, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32, result: Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Socket>) -> IO(Completed<Reason>):
  match result:
    case Fail{error}: IO.pure(Completed<Reason>, Completed{Fail{TcpQueryConnection{error}}, Done{Unit{}}})
    case Done{socket}:
      do IO<Completed<Reason>>:
        result : Result<&2, &1, TcpPeerError<Deadline.Cause<Reason>>, Peer<Deadline.Cause<Reason>>> <- createTcpPeer(Deadline.Cause<Reason>, socket, signal)
        adoptedTcpQuery(Reason, request, maximum, result)

def reportTcpQuery(-Reason: Data, completed: Completed<Reason>, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> Report<Reason>:
  match completed:
    case Completed{result, cleanup}: Report{result, cleanup, reason}

# Borrow an existing deadline signal for one exchange. This permits a resolver
# to keep one total deadline across alias follow-ups; no timer is created here.
def exchangeRequestTcpQuery(-Reason: Data, address: Connect.Address, port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32) -> IO(Completed<Reason>):
  match maximum:
    case 0: IO.pure(Completed<Reason>, Completed{Fail{TcpQueryInvalidReadSize{}}, Done{Unit{}}})
    case size:
      do IO<Completed<Reason>>:
        result : Result<&2, &1, Connect.Error<Deadline.Cause<Reason>>, Socket> <- Connect.connect(Deadline.Cause<Reason>, address, port, signal)
        connected(Reason, signal, request, size, result)

def scoped(-Reason: Data, address: Connect.Address, port: U32, request: Message.Request, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, +signal):
      do IO<Report<Reason>>:
        completed : Completed<Reason> <- exchangeRequestTcpQuery(Reason, address, port, signal, request, maximum)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return reportTcpQuery(Reason, completed, reason)

# One exchange on a dedicated numeric TCP connection. The deadline spans
# connect, adoption, send and receive; teardown closes the session before its
# borrowed signal. Address selection, ID generation, retries, RCODE and answer
# trust/alias/cache policy remain outside this transport operation.
def queryRequest(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, request: Message.Request, maximum: U32) -> IO(Report<Reason>):
  match maximum:
    case 0: IO.pure(Report<Reason>, Report{Fail{TcpQueryInvalidReadSize{}}, Done{Unit{}}, None{}})
    case size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(Reason, address, port, request, size, Deadline.borrow(Reason, scope))

# Compatibility entry points construct the same explicit plain-query value.
def exchange(-Reason: Data, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Completed<Reason>):
  exchangeRequestTcpQuery(Reason, address, port, signal, Message.plainQuery(id, flags, question), maximum)

def query(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Report<Reason>):
  queryRequest(Reason, address, port, milliseconds, parent, Message.plainQuery(id, flags, question), maximum)

# The length-prefix read (including a partially read prefix) is the only
# recoverable reset site. Never unwrap failed cleanup or treat abort as errno.
def reset(-Reason: Data, report: Completed<Reason>) -> IO(Bool):
  match report:
    case Completed{Fail{Terminated{TcpSessionTransport{Transport{ReadingLength{}, SocketIO.SocketError{code, _}}}}}, Done{_}}: Socket.isConnectionReset(code)
    case _: IO.pure(Bool, False{})

def finishTcpRecover(-Reason: Data, retry: Bool, report: Completed<Reason>, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32) -> IO(Completed<Reason>):
  match retry:
    case False{}: IO.pure(Completed<Reason>, report)
    case True{}: exchangeRequestTcpQuery(Reason, address, port, signal, request, maximum)

# A closed failed exchange may be retried once against the same server. The
# second result is returned unchanged, so another reset cannot loop. Preserve
# query bytes/ID and borrow the same deadline across both connections.
def exchangeRequestTcpRecover(-Reason: Data, +address: Connect.Address, +port: U32, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, +maximum: U32) -> IO(Completed<Reason>):
  do IO<Completed<Reason>>:
    +report : Completed<Reason> <- exchangeRequestTcpQuery(Reason, address, port, signal, request, maximum)
    retry : Bool <- reset(Reason, report)
    finishTcpRecover(Reason, retry, report, address, port, signal, request, maximum)

def exchangeTcpRecover(-Reason: Data, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Completed<Reason>):
  exchangeRequestTcpRecover(Reason, address, port, signal, Message.plainQuery(id, flags, question), maximum)

type Server is Data:
  Server{address: Connect.Address, port: U32}

type TcpServersError<-Reason: Data> is Data:
  NoServers{}
  Failed{report: Completed<Reason>}

type Decision<-Reason: Data> is Data:
  TcpServersAnswer{reply: Reply}
  TcpServersNext{report: Completed<Reason>}
  Stop{report: Completed<Reason>}

# Completed network failures can move to another server. Abort, local state,
# validation and adoption failures remain terminal and retain their details.
def retryable(-Reason: Data, error: TcpQueryError<Reason>) -> Bool:
  match error:
    case TcpQueryConnection{Connect.SocketError{_, _}}: True{}
    case Terminated{EndOfStream{}}: True{}
    case Terminated{TcpSessionTransport{Transport{_, SocketIO.SocketError{_, _}}}}: True{}
    case Terminated{TcpSessionTransport{Framing{Message.IncompleteFrame{}}}}: True{}
    case _: False{}

def failed(-Reason: Data, retry: Bool, report: Completed<Reason>) -> Decision<Reason>:
  match retry:
    case True{}: TcpServersNext{report}
    case False{}: Stop{report}

# Cleanup takes precedence over retry. DNS response codes and truncation are
# replies, not transport failures; their policy belongs above this layer.
def completedTcpServers(-Reason: Data, report: Completed<Reason>) -> Decision<Reason>:
  match report:
    case Completed{Done{reply}, Done{_}}: TcpServersAnswer{reply}
    case Completed{Fail{+error}, Done{_}}: failed(Reason, retryable(Reason, error), Completed{Fail{error}, Done{Unit{}}})
    case other: Stop{other}

# One pass through the supplied order. The borrowed deadline and unchanged
# query span every attempt. exchange returns only after closing its
# resources; no detached attempt overlaps the following server.
def driveTcpServers(-Reason: Data, servers: List<&2, Server>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, +maximum: U32, decision: Decision<Reason>) -> IO(Result<&2, &2, TcpServersError<Reason>, Reply>):
  match servers decision:
    case _ TcpServersAnswer{reply}: IO.pure(Result<&2, &2, TcpServersError<Reason>, Reply>, Done{reply})
    case _ Stop{report}: IO.pure(Result<&2, &2, TcpServersError<Reason>, Reply>, Fail{Failed{report}})
    case Nil{} TcpServersNext{report}: IO.pure(Result<&2, &2, TcpServersError<Reason>, Reply>, Fail{Failed{report}})
    case Server{address, port} <> rest TcpServersNext{_}:
      do IO<Result<&2, &2, TcpServersError<Reason>, Reply>>:
        report : Completed<Reason> <- exchangeRequestTcpRecover(Reason, address, port, signal, request, maximum)
        driveTcpServers(Reason, rest, signal, request, maximum, completedTcpServers(Reason, report))

def exchangeRequestTcpServers(-Reason: Data, servers: List<&2, Server>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, +maximum: U32) -> IO(Result<&2, &2, TcpServersError<Reason>, Reply>):
  match servers:
    case Nil{}: IO.pure(Result<&2, &2, TcpServersError<Reason>, Reply>, Fail{NoServers{}})
    case Server{address, port} <> rest:
      do IO<Result<&2, &2, TcpServersError<Reason>, Reply>>:
        report : Completed<Reason> <- exchangeRequestTcpRecover(Reason, address, port, signal, request, maximum)
        driveTcpServers(Reason, rest, signal, request, maximum, completedTcpServers(Reason, report))

def exchangeTcpServers(-Reason: Data, servers: List<&2, Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, flags: U32, question: Message.Question, maximum: U32) -> IO(Result<&2, &2, TcpServersError<Reason>, Reply>):
  exchangeRequestTcpServers(Reason, servers, signal, Message.plainQuery(id, flags, question), maximum)

type Mode is Data:
  UDP{}
  TCP{}

# Inspect at most budget+1 cells. A packet exactly at the budget still fits.
def oversized(budget: Nat, bytes: List<&2, U32>) -> Bool:
  match budget bytes:
    case _ Nil{}: False{}
    case Zero{} _ <> _: True{}
    case Succ{rest} _ <> tail: oversized(rest, tail)

def automatic(large: Bool) -> Mode:
  match large:
    case True{}: TCP{}
    case False{}: UDP{}

# Match the reference's initial 512-byte threshold, including EDNS bytes.
# Advertising a larger response size does not change the query-size cutoff.
def select(forced: Bool, bytes: List<&2, U32>) -> Mode:
  match forced:
    case True{}: TCP{}
    case False{}: automatic(oversized(512n, bytes))

def encodedTransportChoice(forced: Bool, result: Result<&2, &2, Message.EdnsError, List<&2, U32>>) -> Result<&2, &2, Message.EdnsError, Mode>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{select(forced, bytes)}

# Validate even forced-TCP requests before opening any transport.
def prepare(forced: Bool, request: Message.Request) -> Result<&2, &2, Message.EdnsError, Mode>:
  encodedTransportChoice(forced, Message.encodeQuery(request))

type Error<-Reason: Data> is Data:
  Encoding{error: Message.EdnsError}
  Datagram{error: UdpServersError<Reason>}
  Stream{error: TcpServersError<Reason>}

type State<-Reason: Data> is Data:
  Complete{result: Result<&2, &2, Error<Reason>, Reply>}
  Continue{last: Maybe<&2, UdpServersReport<Reason>>}
  Fallback{servers: List<&2, Server>}

def server(value: Endpoint.Endpoint) -> Server:
  match value:
    case Endpoint.EndpointV4{ip, port}: Server{Connect.V4{ip}, port}
    case Endpoint.EndpointV6{ip, port, scope}: Server{Connect.V6{ip, scope}, port}

def entryTransport(value: Plan.Attempt<Endpoint.Endpoint>) -> Server:
  match value:
    case Plan.Attempt{endpoint, _, _}: server(endpoint)

def entries(values: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> List<&2, Server>:
  match values:
    case Nil{}: Nil{}
    case first <> rest: entryTransport(first) <> entries(rest)

def exhausted(-Reason: Data, result: Result<&2, &2, UdpServersError<Reason>, UdpServersReply>) -> Result<&2, &2, Error<Reason>, Reply>:
  match result:
    case Fail{error}: Fail{Datagram{error}}
    case Done{_}: Fail{Datagram{InvalidCursor{}}}

def transitioned(-Reason: Data, selected: Plan.Attempt<Endpoint.Endpoint>, next: Plan.Cursor<Plan.Attempt<Endpoint.Endpoint>>, decision: UdpServersDecision<Reason>) -> State<Reason>:
  match decision:
    case UdpServersNext{last}: Continue{last}
    case UdpServersStop{report}: Complete{Fail{Datagram{UdpServersFailed{report}}}}
    case UdpServersAnswer{UdpServersReply{_, UdpQueryAnswer{message}}}: Complete{Done{TcpQueryAnswer{message}}}
    case UdpServersAnswer{UdpServersReply{_, UdpQueryTruncated{_}}}: Fallback{entries(Plan.fallback(Plan.Attempt<Endpoint.Endpoint>, selected, next))}

def streamed(-Reason: Data, result: Result<&2, &2, TcpServersError<Reason>, Reply>) -> Result<&2, &2, Error<Reason>, Reply>:
  match result:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{Stream{error}}

# A UDP TC response switches to one TCP pass starting with that exact entry.
# TCP failures may advance only through the rest of this selected pass, never
# wrapping or restarting UDP. Recoverable TCP resets stay in Stream's owner.
def drive(-Reason: Data, fuel: Nat, step: Plan.Step<Plan.Attempt<Endpoint.Endpoint>>, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, +maximum: U32, state: State<Reason>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match fuel step state:
    case _ _ Complete{result}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, result)
    case _ _ Fallback{servers}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        result : Result<&2, &2, TcpServersError<Reason>, Reply> <- exchangeRequestTcpServers(Reason, servers, signal, request, maximum)
        return streamed(Reason, result)
    case _ Plan.Exhausted{} Continue{last}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, exhausted(Reason, exhaustedUdpServers(Reason, last)))
    case Zero{} Plan.Try{_, _} Continue{_}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Datagram{InvalidCursor{}}})
    case Succ{rest} Plan.Try{+selected, +next} Continue{_}:
      do IO<Result<&2, &2, Error<Reason>, Reply>>:
        decision : UdpServersDecision<Reason> <- attempt(Reason, selected, signal, request)
        drive(Reason, rest, Plan.next(Plan.Attempt<Endpoint.Endpoint>, next), signal, request, maximum, transitioned(Reason, selected, next, decision))

def prepared(-Reason: Data, +attempts: Nat, +servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32, choice: Result<&2, &2, Message.EdnsError, Mode>) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match choice:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Encoding{error}})
    case Done{UDP{}}: drive(Reason, Nat.mul(attempts, List.length(&2, Plan.Attempt<Endpoint.Endpoint>, servers)), Plan.next(Plan.Attempt<Endpoint.Endpoint>, Plan.start(Plan.Attempt<Endpoint.Endpoint>, attempts, servers)), signal, request, maximum, Continue{None{}})
    case Done{TCP{}}: drive(Reason, Zero{}, Plan.Exhausted{}, signal, request, maximum, Fallback{entries(servers)})

# Forced and oversized requests start with one TCP pass. Zero configured
# attempts never opens a transport, including when TCP is explicitly forced.
def exchangeWith(-Reason: Data, forced: Bool, attempts: Nat, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +request: Message.Request, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  match attempts:
    case Zero{}: IO.pure(Result<&2, &2, Error<Reason>, Reply>, Fail{Datagram{NoAttempts{}}})
    case count: prepared(Reason, count, servers, signal, request, maximum, prepare(forced, request))

# Borrow the same total deadline across initial selection, UDP and TCP.
def exchangeRequest(-Reason: Data, attempts: Nat, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Reply>):
  exchangeWith(Reason, False{}, attempts, servers, signal, request, maximum)

# Values returned by choose carry the next rotation state. The owning resolver
# serializes those transitions; no process-global counter or numeric wrap is
# needed. Initialization preserves the order supplied by the caller.
type ServerRotationState<-Server: Data> is Data:
  ServerRotationState{original: List<&2, Server>, current: List<&2, Server>}

type Chosen<-Server: Data> is Data:
  Chosen{servers: List<&2, Server>, next: ServerRotationState<Server>}

def start(-Server: Data, +servers: List<&2, Server>) -> ServerRotationState<Server>:
  ServerRotationState{servers, servers}

# Tail-recursive append of one item, avoiding Base's non-tail List.append.
def prependReversed(-Server: Data, reversed: List<&2, Server>, tail: List<&2, Server>) -> List<&2, Server>:
  match reversed:
    case Nil{}: tail
    case item <> rest: prependReversed(Server, rest, item <> tail)

def shift(-Server: Data, servers: List<&2, Server>) -> List<&2, Server>:
  match servers:
    case Nil{}: Nil{}
    case first <> rest: prependReversed(Server, List.reverse(&2, Server, rest), first <> Nil{})

# Split once, then join suffix and prefix. Initialization is linear in the
# list length, rather than repeatedly shifting the entire list.
def offsetList(-Server: Data, offset: Nat, servers: List<&2, Server>, reversed: List<&2, Server>) -> List<&2, Server>:
  match offset servers:
    case 0n suffix: prependReversed(Server, List.reverse(&2, Server, suffix), List.reverse(&2, Server, reversed))
    case 1n+rest first <> tail: offsetList(Server, rest, tail, first <> reversed)
    case _ Nil{}: List.reverse(&2, Server, reversed)

def positioned(-Server: Data, offset: Nat, +servers: List<&2, Server>, length: Nat) -> ServerRotationState<Server>:
  match length:
    case 0n: ServerRotationState{servers, servers}
    case count: ServerRotationState{servers, offsetList(Server, Nat.mod(offset, count), servers, Nil{})}

def countServers(-Server: Data, servers: List<&2, Server>, count: Nat) -> Nat:
  match servers:
    case Nil{}: count
    case _ <> rest: countServers(Server, rest, 1n+count)

# The seed chooses only the initial position. Disabled choices always return
# the configured order, and do not discard this retained position.
def startAt(-Server: Data, offset: Nat, +servers: List<&2, Server>) -> ServerRotationState<Server>:
  positioned(Server, offset, servers, countServers(Server, servers, 0n))

# Disabling rotation selects the original order without advancing the retained
# position. Enabled selections return the current order then move one place.
# Empty/singleton lists stay structurally unchanged; duplicates are preserved.
def choose(-Server: Data, enabled: Bool, state: ServerRotationState<Server>) -> Chosen<Server>:
  match enabled state:
    case False{} ServerRotationState{+original, current}: Chosen{original, ServerRotationState{original, current}}
    case True{} ServerRotationState{original, +current}: Chosen{current, ServerRotationState{original, shift(Server, current)}}

type Owner<-Server: Data> is Type:
  Owner{originalServerSource: List<&2, Server>, state: Ref.Ref<ServerRotationState<Server>>}

type ServerSource<-Server: Data> is Data:
  Fixed{servers: List<&2, Server>}
  Rotating{originalServerSource: List<&2, Server>, state: Ref.Ref<ServerRotationState<Server>>, enabled: Bool}

def create(-Server: Data, +servers: List<&2, Server>) -> IO(Owner<Server>):
  do IO<Owner<Server>>:
    state : Ref.Ref<ServerRotationState<Server>> <- Ref.new(ServerRotationState<Server>, start(Server, servers))
    return Owner{servers, state}

def createAt(-Server: Data, offset: Nat, +servers: List<&2, Server>) -> IO(Owner<Server>):
  do IO<Owner<Server>>:
    state : Ref.Ref<ServerRotationState<Server>> <- Ref.new(ServerRotationState<Server>, startAt(Server, offset, servers))
    return Owner{servers, state}

# Sources are borrowed. All uses must finish before the owner is closed.
def borrow(-Server: Data, enabled: Bool, owner: Owner<Server>) -> Owner<Server> & ServerSource<Server>:
  match owner:
    case Owner{+configured, +state}: (Owner{configured, state}, Rotating{configured, state, enabled})

def originalServerSource(-Server: Data, source: ServerSource<Server>) -> List<&2, Server>:
  match source:
    case Fixed{servers}: servers
    case Rotating{servers, _, _}: servers

def nonempty(-Server: Data, servers: List<&2, Server>) -> Bool:
  match servers:
    case Nil{}: False{}
    case _ <> _: True{}

def availableServerSource(-Server: Data, source: ServerSource<Server>) -> Bool:
  nonempty(Server, originalServerSource(Server, source))

def transition(-Server: Data, choice: Chosen<Server>) -> ServerRotationState<Server> & List<&2, Server>:
  match choice:
    case Chosen{servers, next}: (next, servers)

# The callback is pure and the state is exclusively held until its replacement
# is sent back. Concurrent selections each consume one distinct rotation step.
def chooseServerSource(-Server: Data, source: ServerSource<Server>) -> IO(List<&2, Server>):
  match source:
    case Fixed{servers}: IO.pure(List<&2, Server>, servers)
    case Rotating{_, state, enabled}: Ref.modify(ServerRotationState<Server>, List<&2, Server>, state, saved => transition(Server, choose(Server, enabled, saved)))

def close(-Server: Data, owner: Owner<Server>) -> IO(Unit):
  match owner:
    case Owner{_, state}:
      do IO<Unit>:
        retired : ServerRotationState<Server> <- Ref.dispose(ServerRotationState<Server>, state)
        return Unit{}

# Allocate the owner only after sampling succeeds. Failure owns no selector
# resources; the source environment remains with its caller.
def selectedServerInitialize(-Server: Data, servers: List<&2, Server>, result: Result<&2, &2, Index.Error, Nat>) -> IO(Result<&2, &1, Index.Error, Owner<Server>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &1, Index.Error, Owner<Server>>, Fail{error})
    case Done{offset}:
      do IO<Result<&2, &1, Index.Error, Owner<Server>>>:
        owner : Owner<Server> <- createAt(Server, offset, servers)
        return Done{owner}

def counted(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), -Server: Data, environment: Environment, servers: List<&2, Server>, count: Nat) -> IO(Result<&2, &1, Index.Error, Owner<Server>>):
  match count:
    case 0n: selectedServerInitialize(Server, servers, Done{0n})
    case size:
      do IO<Result<&2, &1, Index.Error, Owner<Server>>>:
        index : Result<&2, &2, Index.Error, Nat> <- Index.sampleWith(~Environment, ~draw, environment, size)
        selectedServerInitialize(Server, servers, index)

def createWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), -Server: Data, environment: Environment, +servers: List<&2, Server>) -> IO(Result<&2, &1, Index.Error, Owner<Server>>):
  counted(~Environment, ~draw, Server, environment, servers, countServers(Server, servers, 0n))

# Empty and singleton lists need no entropy. Larger lists receive a uniformly
# selected initial position, while disabled choices retain configured order.
def random(-Server: Data, servers: List<&2, Server>) -> IO(Result<&2, &1, Index.Error, Owner<Server>>):
  createWith(~Unit, ~Index.wordIndex, Server, Unit{}, servers)

# Both sources borrow an existing rotation owner. Selection happens inside
# exchange, after the lookup has drawn an ID and rechecked cancellation.
type Source is Data:
  TcpSource{source: ServerSource<Server>}
  Configured{source: ServerSource<Plan.Attempt<Endpoint.Endpoint>>, options: Plan.ResolverOptions}

type ExchangeSourceError<-Reason: Data> is Data:
  TcpError{error: TcpServersError<Reason>}
  TransportError{error: Error<Reason>}

def available(source: Source) -> Bool:
  match source:
    case TcpSource{selector}: availableServerSource(Server, selector)
    case Configured{selector, _}: availableServerSource(Plan.Attempt<Endpoint.Endpoint>, selector)

def tcp(-Reason: Data, value: Result<&2, &2, TcpServersError<Reason>, Reply>) -> Result<&2, &2, ExchangeSourceError<Reason>, Reply>:
  match value:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{TcpError{error}}

def native(-Reason: Data, value: Result<&2, &2, Error<Reason>, Reply>) -> Result<&2, &2, ExchangeSourceError<Reason>, Reply>:
  match value:
    case Done{reply}: Done{reply}
    case Fail{error}: Fail{TransportError{error}}

def attempts(options: Plan.ResolverOptions) -> Nat:
  match options:
    case Plan.ResolverOptions{_, _, count, _}: U32.to_nat(count)

def exchangeRequestExchangeSource(-Reason: Data, source: Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Message.Request, maximum: U32) -> IO(Result<&2, &2, ExchangeSourceError<Reason>, Reply>):
  match source:
    case TcpSource{selector}:
      do IO<Result<&2, &2, ExchangeSourceError<Reason>, Reply>>:
        servers : List<&2, Server> <- chooseServerSource(Server, selector)
        result : Result<&2, &2, TcpServersError<Reason>, Reply> <- exchangeRequestTcpServers(Reason, servers, signal, request, maximum)
        return tcp(Reason, result)
    case Configured{selector, +options}:
      do IO<Result<&2, &2, ExchangeSourceError<Reason>, Reply>>:
        servers : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, selector)
        result : Result<&2, &2, Error<Reason>, Reply> <- exchangeWith(Reason, Plan.enabled(Plan.UseTcp{}, options), attempts(options), servers, signal, request, maximum)
        return native(Reason, result)

# Select once, then share this immutable order across related questions.
# Callers validate input/entropy and observe cancellation before committing
# this rotation step. The snapshot holds no rotation handle and neither owns
# nor closes the original selector.
def snapshot(source: Source) -> IO(Source):
  match source:
    case TcpSource{selector}:
      do IO<Source>:
        servers : List<&2, Server> <- chooseServerSource(Server, selector)
        return TcpSource{Fixed{servers}}
    case Configured{selector, options}:
      do IO<Source>:
        servers : List<&2, Plan.Attempt<Endpoint.Endpoint>> <- chooseServerSource(Plan.Attempt<Endpoint.Endpoint>, selector)
        return Configured{Fixed{servers}, options}
