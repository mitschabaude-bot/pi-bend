import Base
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

# The context borrows the ID environment, server selector and deadline signal.
# Each candidate closes its exchanges before returning.
type Context<-Environment: Data, -Reason: Data> is Data:
  Context{environment: Environment, source: Selector.Source<Servers.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, kind: U32, maximum: U32}

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
def completed(-Reason: Data, result: Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match result:
    case Fail{Lookup.Exchange{Query.Connection{Connect.SocketError{code, _}}}}: socketFailure(Reason, code)
    case Fail{Lookup.Exchange{Query.Terminated{Session.Transport{TCP.Transport{_, SocketIO.SocketError{code, _}}}}}}: socketFailure(Reason, code)
    case Fail{Lookup.Exchange{Query.Terminated{Session.EndOfStream{}}}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case Fail{Lookup.Exchange{Query.Terminated{Session.Transport{TCP.Framing{Frame.IncompleteFrame{}}}}}}: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, Run.Failed{Response.TemporaryFailure{}})
    case other: IO.pure(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>, outcome(Reason, other))

def request(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, context: Context<Environment, Reason>, request: Run.Request) -> IO(Run.Outcome<Lookup.Error<Reason>, Answer.Selection>):
  match context request:
    case Context{environment, source, signal, options, kind, maximum} Run.Request{_, name}:
      do IO<Run.Outcome<Lookup.Error<Reason>, Answer.Selection>>:
        result : Result<&2, &2, Lookup.Error<Reason>, Answer.Selection> <- Lookup.exchangeSourceOptionsWith(~Environment, ~draw, Reason, environment, source, signal, options, kind, name, maximum)
        completed(Reason, result)

def scopedOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, options: Request.Options, kind: U32, maximum: U32, cursor: Search.Cursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Run.Error<Lookup.Error<Reason>>, Answer.Selection> <- Run.run(~Context<Environment, Reason>, ~Lookup.Error<Reason>, ~Answer.Selection, ~request(~Environment, ~draw, ~Reason), Context{environment, source, signal, options, kind, maximum}, cursor)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def startOptions(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
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
def searchSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, +source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, +kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  startOptions(~Environment, ~draw, ~Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Selector.available(Servers.Server, source), environment, source, milliseconds, parent, options, kind, maximum, cursor)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, kind: U32, maximum: U32, cursor: Search.Cursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  scopedOptions(~Environment, ~draw, ~Reason, environment, source, Request.defaults(), kind, maximum, cursor, pair)

def start(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  startOptions(~Environment, ~draw, ~Reason, valid, available, environment, source, milliseconds, parent, Request.defaults(), kind, maximum, cursor)

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
