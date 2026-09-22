import Base
import ./http-exchange-plan.bend as Plan
import ./http-connect.bend as Connect
import ./connection-driver.bend as Dispatch
import ./connection-driver.bend as Driver
import ./connection-driver.bend as Progress
import ./connection-driver.bend as Order
import ./http-buffered-request.bend as Request
import ./http-socket-exchange.bend as Exchange
import ./http-response-stream.bend as Response
import ./dns-resolver.bend as Resolver
import ./dns-resolver.bend as Pair
import ./dns-message.bend as Id
import ./hosts.bend as Hosts
import ./hosts.bend as File
import ./abort.bend as Abort

type Error<-Reason: Data> is Data:
  ConnectionFailure{error: Progress.ProgressError<Reason>}
  ExchangeFailure{error: Exchange.StartError<Reason>}

type Report<-Reason: Data, -SourceError: Data> is Type:
  Rejected{error: Plan.Error}
  Unresolved{resolution: Connect.Resolution(Reason, SourceError)}
  Attempted{resolution: Connect.Resolution(Reason, SourceError), attempts: List<&2, Driver.Entry<Reason>>, result: Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>}

type Options is Data:
  Options{priority: Pair.Priority, preference: Order.Preference, attemptMilliseconds: U32, maximum: U32, limits: Response.Limits}

def started(-Reason: Data, result: Result<&2, &1, Exchange.StartError<Reason>, Exchange.Exchange<Reason>>) -> Result<&2, &1, Error<Reason>, Exchange.Exchange<Reason>>:
  match result:
    case Fail{error}: Fail{ExchangeFailure{error}}
    case Done{exchange}: Done{exchange}

# Socket adoption consumes the socket on all paths and rechecks the same
# retained parent signal before request IO. The full connection log survives.
def connected(~Reason: Data, ~SourceError: Data, signal: Abort.AbortSignal<Reason>, request: Request.Prepared, maximum: U32, limits: Response.Limits, report: Dispatch.PlanReport<Connect.Resolution(Reason, SourceError), Reason, Socket>) -> IO(Report<Reason, SourceError>):
  match report:
    case Dispatch.Unresolved{resolution}: IO.pure(Report<Reason, SourceError>, Unresolved{resolution})
    case Dispatch.Attempted{resolution, Driver.Report{Fail{error}, attempts}}: IO.pure(Report<Reason, SourceError>, Attempted{resolution, attempts, Fail{ConnectionFailure{error}}})
    case Dispatch.Attempted{resolution, Driver.Report{Done{socket}, attempts}}:
      do IO<Report<Reason, SourceError>>:
        result : Result<&2, &1, Exchange.StartError<Reason>, Exchange.Exchange<Reason>> <- Exchange.start(~Reason, socket, signal, request, maximum, limits)
        return Attempted{resolution, attempts, started(Reason, result)}

def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~SourceError: Data, environment: Environment, resolver: Resolver.Resolver, +signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<File.Address>>>, options: Options, plan: Plan.Plan<Request.Prepared>) -> IO(Report<Reason, SourceError>):
  match options plan:
    case _ Plan.Rejected{error}: IO.pure(Report<Reason, SourceError>, Rejected{error})
    case Options{priority, preference, duration, _, limits} Plan.Start{host, port, +request, +maximum}:
      do IO<Report<Reason, SourceError>>:
        report : Dispatch.PlanReport<Connect.Resolution(Reason, SourceError), Reason, Socket> <- Connect.openWith(~Environment, ~draw, ~Reason, ~SourceError, environment, resolver, signal, priority, preference, Driver.Options{port, duration}, host, hosts)
        connected(~Reason, ~SourceError, signal, request, maximum, limits, report)

# A caller retains resolver and signal ownership. On success it must consume
# or close the exchange before disposing the signal; upload/read tasks belong
# to that exchange. This is the cleartext path, not a TLS implementation.
def startWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~SourceError: Data, environment: Environment, resolver: Resolver.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<File.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  match options request:
    case Options{priority, preference, duration, +maximum, limits} Request.URLPrepared{endpoint, prepared}:
      planned(~Environment, ~draw, ~Reason, ~SourceError, environment, resolver, signal, hosts, Options{priority, preference, duration, maximum, limits}, Plan.prepare(Request.Prepared, endpoint, prepared, maximum))

def start(~Reason: Data, ~SourceError: Data, resolver: Resolver.Resolver, signal: Abort.AbortSignal<Reason>, hosts: Result<&2, &2, SourceError, List<&2, Hosts.Entry<File.Address>>>, options: Options, request: Request.URLPrepared) -> IO(Report<Reason, SourceError>):
  startWith(~Unit, ~Id.random, ~Reason, ~SourceError, Unit{}, resolver, signal, hosts, options, request)
