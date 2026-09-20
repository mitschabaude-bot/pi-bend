import Base
import ./dns-address-pair.bend as Exchange
import ./dns-pair-setup.bend as Setup
import ./dns-pair-result.bend as Pair
import ./dns-pair-classify.bend as Classify
import ./dns-address-lookup.bend as Lookup
import ./dns-address-answer.bend as Answer
import ./dns-search-run.bend as Run
import ./dns-search.bend as Search
import ./dns-exchange-source.bend as Source
import ./dns-query.bend as Query
import ./dns-id.bend as Id
import ./abort.bend as Abort
import ./deadline.bend as Deadline

type Failure<-Reason: Data> is Data:
  SetupFailed{error: Setup.Error<Reason>}
  QueryFailed{reports: Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>}

type Report<-Reason: Data> is Data:
  Report{result: Result<&2, &2, Run.Error<Failure<Reason>>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>, deadline: Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>>}

type Context<-Environment: Data, -Reason: Data> is Data:
  Context{environment: Environment, source: Source.Source, signal: Abort.AbortSignal<Deadline.Cause<Reason>>, options: Query.Options, priority: Pair.Priority, maximum: U32}

def merged(-Reason: Data, outcome: Run.Outcome<Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>) -> Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>:
  match outcome:
    case Run.Answer{reports}: Run.Answer{reports}
    case Run.Failed{cause}: Run.Failed{cause}
    case Run.Halt{reports}: Run.Halt{QueryFailed{reports}}

def completed(~Reason: Data, priority: Pair.Priority, result: Result<&2, &2, Setup.Error<Reason>, Exchange.Reports<Reason>>) -> IO(Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>):
  match result:
    case Fail{error}: IO.pure(Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>, Run.Halt{SetupFailed{error}})
    case Done{Exchange.Reports{ipv4, ipv6}}:
      do IO<Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>>:
        a : Pair.Classified<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>> <- Classify.classify(~Reason, ipv4)
        b : Pair.Classified<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>> <- Classify.classify(~Reason, ipv6)
        return merged(Reason, Pair.merge(Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>, priority, a, b))

def request(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, context: Context<Environment, Reason>, request: Run.Request) -> IO(Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>):
  match context request:
    case Context{environment, source, signal, options, priority, maximum} Run.Request{_, name}:
      do IO<Run.Outcome<Failure<Reason>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>>>:
        result : Result<&2, &2, Setup.Error<Reason>, Exchange.Reports<Reason>> <- Exchange.exchangeWith(~Environment, ~draw, Reason, environment, source, signal, options, name, maximum)
        completed(~Reason, priority, result)

def scoped(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Source.Source, options: Query.Options, priority: Pair.Priority, maximum: U32, cursor: Search.Cursor, pair: Deadline.Scope<Reason> & Abort.AbortSignal<Deadline.Cause<Reason>>) -> IO(Report<Reason>):
  match pair:
    case (scope, signal):
      do IO<Report<Reason>>:
        result : Result<&2, &2, Run.Error<Failure<Reason>>, Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>> <- Run.run(~Context<Environment, Reason>, ~Failure<Reason>, ~Pair.Reports<Result<&2, &2, Lookup.Error<Reason>, Answer.Selection>>, ~request(~Environment, ~draw, ~Reason), Context{environment, source, signal, options, priority, maximum}, cursor)
        reason : Maybe<&2, Abort.AbortReason<Deadline.Cause<Reason>>> <- Deadline.close(Reason, scope)
        return Report{result, reason}

def start(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, available: Bool, environment: Environment, source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Query.Options, priority: Pair.Priority, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  match available maximum:
    case _ 0: IO.pure(Report<Reason>, Report{Fail{Run.Halted{SetupFailed{Setup.InvalidReadSize{}}}}, None{}})
    case False{} _: IO.pure(Report<Reason>, Report{Fail{Run.Halted{SetupFailed{Setup.NoServers{}}}}, None{}})
    case True{} size:
      do IO<Report<Reason>>:
        scope : Deadline.Scope<Reason> <- Deadline.create(Reason, milliseconds, parent)
        scoped(~Environment, ~draw, ~Reason, environment, source, options, priority, size, cursor, Deadline.borrow(Reason, scope))

# Both families finish for a candidate before the shared search cursor advances.
# One owned deadline spans every candidate and alias. Priority is explicit;
# this API does not choose an application default or emulate receipt order.
def searchWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, +source: Source.Source, milliseconds: U32, parent: Abort.AbortSignal<Reason>, options: Query.Options, priority: Pair.Priority, maximum: U32, cursor: Search.Cursor) -> IO(Report<Reason>):
  start(~Environment, ~draw, ~Reason, Source.available(source), environment, source, milliseconds, parent, options, priority, maximum, cursor)
