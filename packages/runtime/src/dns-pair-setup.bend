import Base
import ./dns-pair-queries.bend as Pair
import ./dns-query.bend as Request
import ./dns-name.bend as Name
import ./dns-id.bend as Id
import ./dns-exchange-source.bend as Source
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Error<-Reason: Data> is Data:
  InvalidReadSize{}
  NoServers{}
  Aborted{reason: Abort.AbortReason<Deadline.Cause<Reason>>}
  Identifier{family: Pair.Family, error: Id.Error}
  Encoding{error: Pair.Error}

type Prepared is Data:
  Prepared{queries: Pair.Queries, source: Source.Source}

def validated(-Reason: Data, source: Source.Source, value: Result<&2, &2, Pair.Error, Pair.Queries>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match value:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Encoding{error}})
    case Done{queries}:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        snapshot : Source.Source <- Source.snapshot(source)
        return Done{Prepared{queries, snapshot}}

def committed(-Reason: Data, source: Source.Source, queries: Pair.Queries, check: Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match check:
    case Fail{reason}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Aborted{reason}})
    case Done{_}: validated(Reason, source, Pair.validate(queries))

def second(-Reason: Data, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, id4: U32, result: Result<&2, &2, Id.Error, U32>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Identifier{Pair.IPv6{}, error}})
    case Done{id6}:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        check : Result<&2, &2, Abort.AbortReason<Deadline.Cause<Reason>>, Unit> <- Abort.throwIfAborted(Deadline.Cause<Reason>, signal)
        committed(Reason, source, Pair.create(options, id4, id6, name), check)

def next(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, id4: U32, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Aborted{why}})
    case None{}:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        result : Result<&2, &2, Id.Error, U32> <- draw(environment)
        second(Reason, source, signal, options, name, id4, result)

def first(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, result: Result<&2, &2, Id.Error, U32>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Identifier{Pair.IPv4{}, error}})
    case Done{id4}:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        next(~Environment, ~draw, Reason, environment, source, signal, options, name, id4, reason)

def ready(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, +environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, reason: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match reason:
    case Some{why}: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{Aborted{why}})
    case None{}:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        result : Result<&2, &2, Id.Error, U32> <- draw(environment)
        first(~Environment, ~draw, Reason, environment, source, signal, options, name, result)

def checked(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, available: Bool, maximum: U32, environment: Environment, source: Source.Source, +signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  match available maximum:
    case _ 0: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{InvalidReadSize{}})
    case False{} _: IO.pure(Result<&2, &2, Error<Reason>, Prepared>, Fail{NoServers{}})
    case True{} _:
      do IO<Result<&2, &2, Error<Reason>, Prepared>>:
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Abort.reason(Deadline.Cause<Reason>, signal)
        ready(~Environment, ~draw, Reason, environment, source, signal, options, name, reason)

# Reserve IDs in family order, checking the retained abort state before each
# draw and before the single rotation commit. IDs may repeat: dedicated query
# connections/sockets and question matching provide transaction isolation.
def prepareWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), -Reason: Data, environment: Environment, +source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Request.Options, name: Name.Name, maximum: U32) -> IO(Result<&2, &2, Error<Reason>, Prepared>):
  checked(~Environment, ~draw, Reason, Source.available(source), maximum, environment, source, signal, options, name)
