import Base
import ./resolver-search.bend as Configuration
import ./dns-name.bend as Name
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./dns-id.bend as Id
import ./dns-query.bend as Request
import ./dns-address-answer.bend as Answer
import ./dns-address-lookup.bend as Lookup
import ./dns-search.bend as Search
import ./dns-search-response.bend as Response
import ./dns-search-run.bend as Run
import ./dns-tcp-servers.bend as Servers
import ./dns-server-source.bend as Selector
import ./dns-tcp-query.bend as Query
import ./dns-tcp-session.bend as Session
import ./dns-tcp-connection.bend as TCP
import ./dns-tcp-frame.bend as Frame
import ./abortable-socket.bend as SocketIO
import ./dns-exchange-source.bend as ExchangeSource
import ./dns-transport.bend as Transport
import ./dns-udp-servers.bend as UDP
import ./dns-udp-query.bend as DatagramQuery
import ./dns-udp-policy.bend as UDPPolicy
import ./dns-udp-attempt-scope.bend as Attempt
import ./abortable-datagram.bend as DatagramIO
import ./datagram-peer.bend as Peer

# The context borrows the ID environment, server selector and deadline signal.
# Each candidate closes its exchanges before returning.
type Context<-Environment: Data, -Reason: Data> is Data:
  Context{environment: Environment, source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, kind: U32, maximum: U32}

type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, Run.Error<Lookup.Error<Reason>>, Answer.Selection>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

def responseCode(code: U32) -> Response.Cause:
  match code:
    case 2: Response.ServerFailure{}
    case 3: Response.Missing{}
    case _: Response.Unrecoverable{}

# Pure answer classification. The effectful completion adapter below handles
# platform socket codes; all remaining typed failures pass through intact.
def outcome(-Reason: Data, result: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>) -> Run.Outcome<Lookup.Error<Reason>, Answer.Selection>:
  match result:
    case Done{Answer.Selection{_, Nil{}}}: Run.Failed{Response.EmptyAnswer{}}
    case Done{selection}: Run.Answer{selection}
    case Fail{Lookup.Selection{Answer.ResponseCode{code}}}: Run.Failed{responseCode(code)}
    case Fail{error}: Run.Halt{error}

def socketCause(refused: Bool) -> Response.Cause:
  match refused:
    case True{}: Response.ConnectionRefused{}
    case False{}: Response.TemporaryFailure{}

def socketFailure(-Reason: Data, code: U32) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  do IO<Run.Outcome<Lookup.Error<Reason>, Answer.Selection>>:
    refused : Bool <- Socket.isConnectionRefused(code)
    return Run.Failed{socketCause(refused)}

# Only network failures enter search precedence. Abort variants and cleanup
# reports must never be classified by errno (even if they contain one).
def exchangeFailure(-Reason: Data, original: Lookup.Error<Reason>, error: Query.Error<Reason>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match error:
    case Query.Connection{Connect.SocketError{code, _}}: socketFailure(Reason, code)
    case Query.Terminated{Session.Transport{TCP.Transport{_, SocketIO.SocketError{code, _}}}}: socketFailure(Reason, code)
    case Query.Terminated{Session.EndOfStream{}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case Query.Terminated{Session.Transport{TCP.Framing{Frame.IncompleteFrame{}}}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case _: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Halt{original})

# A failed UDP report keeps both its primary failure and the reason observed
# while retiring its scope. Parent/default aborts override search continuation.
def datagramFailure(-Reason: Data, original: Lookup.Error<Reason>, failure: UDP.Failure<Reason>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match failure:
    case UDP.Rejected{_, UDPPolicy.ServerFailure{}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.ServerFailure{}})
    case UDP.Rejected{_, _}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case UDP.Exchange{DatagramQuery.Transport{DatagramIO.SocketError{code, _}}}: socketFailure(Reason, code)
    case UDP.Exchange{DatagramQuery.Opening{Peer.Association{code, _}}}: socketFailure(Reason, code)
    case UDP.Exchange{DatagramQuery.Aborted{Abort.Supplied{Deadline.Expired{}}}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case UDP.Exchange{DatagramQuery.Transport{DatagramIO.Aborted{Abort.Supplied{Deadline.Expired{}}}}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case _: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Halt{original})

def datagramCompleted(-Reason: Data, original: Lookup.Error<Reason>, report: UDP.Report<Reason>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match report:
    case UDP.Report{_, _, Attempt.ParentAborted{_}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Halt{original})
    case UDP.Report{_, _, Attempt.UnexpectedDefaultAbort{}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Halt{original})
    case UDP.Report{_, failure, _}: datagramFailure(Reason, original, failure)

# Only a clean TCP failure can be classified. Preserve the complete original
# native error for every halt, including a failure during stream cleanup.
def streamCompleted(-Reason: Data, original: Lookup.Error<Reason>, report: Query.Completed<Reason>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match report:
    case Query.Completed{Fail{error}, Done{_}}: exchangeFailure(Reason, original, error)
    case _: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Halt{original})

def completed(-Reason: Data, result: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match result:
    case Fail{Lookup.Transport{Transport.Datagram{UDP.Failed{+report}}}}: datagramCompleted(Reason, Lookup.Transport{Transport.Datagram{UDP.Failed{report}}}, report)
    case Fail{Lookup.Transport{Transport.Stream{Servers.Failed{+report}}}}: streamCompleted(Reason, Lookup.Transport{Transport.Stream{Servers.Failed{report}}}, report)
    case Fail{Lookup.Exchange{+error}}: exchangeFailure(Reason, Lookup.Exchange{error}, error)
    case other: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, outcome(Reason, other))

def request(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, context: Context<Environment, Reason>, request: Run.Request) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match context request:
    case Context{environment, source, signal, options, kind, maximum} Run.Request{_, name}:
      do IO<Run.Outcome<Lookup.Error<Reason>, Answer.Selection>>:
        result : Result<&2, &2, Lookup.Error<Reason>, Answer.Selection> <- Lookup.exchangeTransportOptionsWith(~Environment, ~draw, Reason, environment, source, signal, options, kind, name, maximum)
        completed(Reason, result)

def scopedOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: ExchangeSource.Source, options: Request.Options, kind: U32, maximum: U32, cursor: Search.Cursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Run.Error<Lookup.Error<Reason>>, Answer.Selection> <- Run.run(~Context<Environment, Reason>, ~Lookup.Error<Reason>, ~Answer.Selection, ~request(~Environment, ~draw, ~Reason), Context{environment, source, signal, options, kind, maximum}, cursor)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def startOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: ExchangeSource.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  match valid available maximum:
    case False{} _ _: IO.pure(Report<Reason>, Report{Fail{Run.Halted{Lookup.UnsupportedType{}}}, None{}})
    case True{} _ 0: IO.pure(Report<Reason>, Report{Fail{Run.Halted{Lookup.InvalidReadSize{}}}, None{}})
    case True{} False{} _: IO.pure(Report<Reason>, Report{Fail{Run.Halted{Lookup.NoServers{}}}, None{}})
    case True{} True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scopedOptions(~Environment, ~draw, ~Reason, environment, source, options, kind, size, cursor, Deadline.borrow(Reason, scope))

# One total deadline spans candidates, server attempts and alias follow-ups.
# The source must return promptly; arbitrary user IO cannot be force-cancelled.
def searchTransportOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, +source: ExchangeSource.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, +kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  startOptions(~Environment, ~draw, ~Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), ExchangeSource.available(source), environment, source, milliseconds, parent, options, kind, maximum, cursor)

def searchSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, +source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, +kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchTransportOptionsWith(~Environment, ~draw, ~Reason, environment, ExchangeSource.TcpSource{source}, milliseconds, parent, options, kind, maximum, cursor)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, kind: U32, maximum: U32, cursor: Search.Cursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  scopedOptions(~Environment, ~draw, ~Reason, environment, ExchangeSource.TcpSource{source}, Request.defaults(), kind, maximum, cursor, pair)

def start(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  startOptions(~Environment, ~draw, ~Reason, valid, available, environment, ExchangeSource.TcpSource{source}, milliseconds, parent, Request.defaults(), kind, maximum, cursor)

def searchSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, +source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchSourceOptionsWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, Request.defaults(), kind, maximum, cursor)

def searchSourceRandom(~Reason: Data, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchSourceWith(~Unit, ~Id.random, ~Reason, Unit{}, source, milliseconds, parent, kind, maximum, cursor)

# One total deadline spans candidates and all alias follow-ups. As in address
# lookup, the injected source must return promptly; arbitrary IO is not killed.
def searchServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, servers: List<&2, Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchSourceWith(~Environment, ~draw, ~Reason, environment, Selector.Fixed{servers}, milliseconds, parent, kind, maximum, cursor)

def searchServersRandom(~Reason: Data, servers: List<&2, Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchSourceRandom(~Reason, Selector.Fixed{servers}, milliseconds, parent, kind, maximum, cursor)

def searchWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchServersWith(~Environment, ~draw, ~Reason, environment, Servers.Server{address, port} <> Nil{}, milliseconds, parent, kind, maximum, cursor)

def searchRandom(~Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  searchWith(~Unit, ~Id.random, ~Reason, Unit{}, address, port, milliseconds, parent, kind, maximum, cursor)

# Resolved server ownership and the total deadline remain explicit. This layer
# consumes search/request policy, not timeout/attempt scheduling or reload.
def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, plan: Configuration.Plan) -> IO(Report<Reason>):
  match plan:
    case Configuration.Plan{options, cursor}: searchSourceOptionsWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, options, kind, maximum, cursor)

def searchConfiguredWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, configuration: Configuration.Configuration, name: Name.Name, dots: U32, absolute: Bool) -> IO(Report<Reason>):
  planned(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, kind, maximum, Configuration.plan(configuration, name, dots, absolute))
