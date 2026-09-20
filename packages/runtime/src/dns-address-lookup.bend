import Base
import ./abort.bend as Abort
import ./deadline.bend as Deadline
import ./abortable-connect.bend as Connect
import ./dns-tcp-query.bend as Query
import ./dns-address-answer.bend as Answer
import ./dns-message.bend as Message
import ./dns-query.bend as Request
import ./dns-name.bend as Name
import ./dns-response.bend as Response
import ./dns-id.bend as Id
import ./dns-tcp-servers.bend as Servers
import ./dns-server-source.bend as Selector
import ./dns-exchange-source.bend as ExchangeSource
import ./dns-transport.bend as Transport

type Error<-Reason: Data> is Data:
  Aborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  Transport{error: Transport.Error<Reason>}
  InvalidReadSize{}
  NoServers{}
  UnsupportedType{}
  UnsupportedClass{}
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

def resolved(-Reason: Data, name: Name.Name, kind: U32, history: Answer.History, result: Result<&2, &2, Servers.Error<Reason>, Query.Reply>) -> Progress<Reason>:
  match result:
    case Done{reply}: replied(Reason, name, kind, history, Done{reply})
    case Fail{Servers.NoServers{}}: Finished{Fail{NoServers{}}}
    case Fail{Servers.Failed{report}}: completed(Reason, name, kind, history, report)

def exchanged(-Reason: Data, name: Name.Name, kind: U32, history: Answer.History, result: Result<&2, &2, ExchangeSource.Error<Reason>, Query.Reply>) -> Progress<Reason>:
  match result:
    case Done{reply}: replied(Reason, name, kind, history, Done{reply})
    case Fail{ExchangeSource.TcpError{error}}: resolved(Reason, name, kind, history, Fail{error})
    case Fail{ExchangeSource.TransportError{error}}: Finished{Fail{Transport{error}}}

def cancelled(-Reason: Data, source: ExchangeSource.Source, why: Abort.AbortReason<Deadline.Cause<Reason>>) -> Progress<Reason>:
  match source:
    case ExchangeSource.TcpSource{_}: Finished{Fail{Exchange{Query.Connection{Connect.Aborted{why}}}}}
    case ExchangeSource.Configured{_, _}: Finished{Fail{Aborted{why}}}

# Observe cancellation again after entropy, before committing a rotation step.
def route(-Reason: Data, source: ExchangeSource.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, id: U32, options: Request.Options, +kind: U32, +name: Name.Name, history: Answer.History, maximum: U32, check: Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit>) -> IO(Progress<Reason>):
  match check:
    case Fail{why}: IO.pure(Progress<Reason>, cancelled(Reason, source, why))
    case Done{_}:
      do IO<Progress<Reason>>:
        result : Result<&2, &2, ExchangeSource.Error<Reason>, Query.Reply> <- ExchangeSource.exchangeRequest(Reason, source, signal, Request.create(options, id, Message.Question{name, kind, 1}), maximum)
        return exchanged(Reason, name, kind, history, result)

def identified(-Reason: Data, source: ExchangeSource.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, +kind: U32, +name: Name.Name, history: Answer.History, maximum: U32, value: Result<&2, &2, Id.Error, U32>) -> IO(Progress<Reason>):
  match value:
    case Fail{error}: IO.pure(Progress<Reason>, Finished{Fail{Identifier{error}}})
    case Done{id}:
      do IO<Progress<Reason>>:
        check : Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit> <- Abort.throwIfAborted(Deadline.Cause<Reason>, signal)
        route(Reason, source, signal, id, options, kind, name, history, maximum, check)

# Inspect the retained abort reason before drawing an ID. After the draw,
# identified checks again before selecting servers; connect also checks.
def ready(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, kind: U32, name: Name.Name, history: Answer.History, maximum: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Progress<Reason>):
  match reason:
    case Some{why}: IO.pure(Progress<Reason>, cancelled(Reason, source, why))
    case None{}:
      do IO<Progress<Reason>>:
        value : Result<&2, &2, Id.Error, U32> <- draw(environment)
        identified(Reason, source, signal, options, kind, name, history, maximum, value)

# Each follow-up draws a new ID for its question. Server failover and reset
# recovery reuse that ID under the same deadline. The environment is borrowed;
# its owner disposes resources after this call. Static injection needs no mutable callback registry.
@unsafe def drive(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, +environment: Environment, +source: ExchangeSource.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, +options: Request.Options, +kind: U32, +maximum: U32, progress: Progress<Reason>) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match progress:
    case Finished{result}: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, result)
    case Again{name, history}:
      do IO<Result<&2, &2, Error<Reason>, Answer.Selection>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        next : Progress<Reason> <- ready(~Environment, ~draw, Reason, environment, source, signal, options, kind, name, history, maximum, reason)
        drive(~Environment, ~draw, Reason, environment, source, signal, options, kind, maximum, next)

# Execute one name and its alias follow-ups under a caller-owned deadline.
# Validation precedes entropy/network effects. This function neither resets the
# deadline nor retires its signal, allowing an enclosing search to reuse it.
def exchangeChecked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, valid: Bool, available: Bool, environment: Environment, source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match valid available maximum:
    case False{} _ _: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{UnsupportedType{}})
    case True{} _ 0: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{InvalidReadSize{}})
    case True{} False{} _: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{NoServers{}})
    case True{} True{} size: drive(~Environment, ~draw, Reason, environment, source, signal, options, kind, size, Again{name, Answer.newHistory()})

# Use a caller-reserved identifier for the first question. Alias follow-ups
# still draw fresh identifiers through the supplied environment.
def exchangeIdentifiedChecked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, valid: Bool, available: Bool, readable: Bool, environment: Environment, source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, id: U32, kind: U32, name: Name.Name, +maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match valid available readable:
    case False{} _ _: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{UnsupportedType{}})
    case True{} _ False{}: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{InvalidReadSize{}})
    case True{} False{} True{}: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{NoServers{}})
    case True{} True{} True{}:
      +sharedEnvironment = environment
      +sharedSource = source
      +sharedSignal = signal
      +sharedOptions = options
      +sharedKind = kind
      +sharedMaximum = maximum
      do IO<Result<&2, &2, Error<Reason>, Answer.Selection>>:
        first : Progress<Reason> <- identified(Reason, sharedSource, sharedSignal, sharedOptions, sharedKind, name, Answer.newHistory(), sharedMaximum, Done{id})
        drive(~Environment, ~draw, Reason, sharedEnvironment, sharedSource, sharedSignal, sharedOptions, sharedKind, sharedMaximum, first)

def exchangeRequestWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, +source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, request: Request.Request, +maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  match request:
    case Request.Request{id, flags, Message.Question{name, +kind, 1}, extension}:
      exchangeIdentifiedChecked(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), ExchangeSource.available(source), U32.is_ne(maximum, 0), environment, source, signal, Request.Options{flags, extension}, id, kind, name, maximum)
    case _: IO.pure(Result<&2, &2, Error<Reason>, Answer.Selection>, Fail{UnsupportedClass{}})

def exchangeTransportOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, +source: ExchangeSource.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, +kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  exchangeChecked(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), ExchangeSource.available(source), environment, source, signal, options, kind, name, maximum)

def exchangeSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  exchangeTransportOptionsWith(~Environment, ~draw, Reason, environment, ExchangeSource.TcpSource{source}, signal, options, kind, name, maximum)

def exchangeSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  exchangeSourceOptionsWith(~Environment, ~draw, Reason, environment, source, signal, Request.defaults(), kind, name, maximum)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, options: Request.Options, kind: U32, name: Name.Name, maximum: U32, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Error<Reason>, Answer.Selection> <- exchangeSourceOptionsWith(~Environment, ~draw, Reason, environment, source, signal, options, kind, name, maximum)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def start(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, valid: Bool, available: Bool, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  match valid available maximum:
    case False{} _ _: IO.pure(Report<Reason>, Report{Fail{UnsupportedType{}}, None{}})
    case True{} _ 0: IO.pure(Report<Reason>, Report{Fail{InvalidReadSize{}}, None{}})
    case True{} False{} _: IO.pure(Report<Reason>, Report{Fail{NoServers{}}, None{}})
    case True{} True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(~Environment, ~draw, Reason, environment, source, options, kind, name, size, Deadline.borrow(Reason, scope))

def exchangeServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, servers: List<&2, Servers.Server>, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  exchangeSourceWith(~Environment, ~draw, Reason, environment, Selector.Fixed{servers}, signal, kind, name, maximum)

# The caller owns the selection source and retains it across lookup calls.
def lookupSourceOptionsWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, +source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Request.Options, +kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  start(~Environment, ~draw, Reason, U32.is_eq(kind, 1) || U32.is_eq(kind, 28), Selector.available(Servers.Server, source), environment, source, milliseconds, parent, options, kind, name, maximum)

def lookupSourceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceOptionsWith(~Environment, ~draw, Reason, environment, source, milliseconds, parent, Request.defaults(), kind, name, maximum)

def exchangeWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, kind: U32, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Answer.Selection>):
  exchangeServersWith(~Environment, ~draw, Reason, environment, Servers.Server{address, port} <> Nil{}, signal, kind, name, maximum)

# The injected source runs once per question, not per retry. It must return promptly;
# arbitrary user effects cannot be force-cancelled by the enclosing deadline.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Environment, ~draw, Reason, environment, Selector.Fixed{Servers.Server{address, port} <> Nil{}}, milliseconds, parent, kind, name, maximum)

# Preserve the deterministic entry point. Dedicated connections isolate delayed
# replies even when a caller reuses the same ID across alias follow-ups.
def lookup(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, id: U32, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWith(~U32, ~Id.fixed, Reason, id, address, port, milliseconds, parent, kind, name, maximum)

# OS entropy is the normal resolver source. Each draw is independent; random
# IDs can legitimately repeat. No uniqueness or reply-authentication guarantee.
def lookupRandom(-Reason: Data, address: Connect.Address, port: U32, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupWith(~Unit, ~Id.random, Reason, Unit{}, address, port, milliseconds, parent, kind, name, maximum)

# The supplied order is reused for each alias question. Rotation/configuration
# policy belongs to the caller; all attempts share this one owned deadline.
def lookupServersWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, servers: List<&2, Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, +kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Environment, ~draw, Reason, environment, Selector.Fixed{servers}, milliseconds, parent, kind, name, maximum)

def lookupServersRandom(-Reason: Data, servers: List<&2, Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupServersWith(~Unit, ~Id.random, Reason, Unit{}, servers, milliseconds, parent, kind, name, maximum)

def lookupSourceRandom(-Reason: Data, source: Selector.Source<Servers.Server>, milliseconds: U32, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, maximum: U32) -> IO(Report<Reason>):
  lookupSourceWith(~Unit, ~Id.random, Reason, Unit{}, source, milliseconds, parent, kind, name, maximum)
