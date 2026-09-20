import Base
import ./dns-resolver.bend as Resolver
import ./resolver-configuration.bend as Settings
import ./resolver-search.bend as Configuration
import ./resolver-transport.bend as Transport
import ./dns-exchange-source.bend as Exchange
import ./dns-server-source.bend as Source
import ./dns-udp-plan.bend as Plan
import ./socket-endpoint.bend as Endpoint
import ./dns-pair-search.bend as Network
import ./dns-pair-result.bend as Pair
import ./dns-name.bend as Name
import ./dns-id.bend as Id
import ./abort.bend as Abort

def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Source.Source<Plan.Attempt<Endpoint.Endpoint>>, config: Settings.Config<Endpoint.Endpoint>, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, plan: Configuration.Plan) -> IO(Network.Report<Reason>):
  match config plan:
    case Settings.Config{Transport.Prepared{options, _}, _, milliseconds, maximum} Configuration.Plan{request, cursor}: Network.searchWith(~Environment, ~draw, ~Reason, environment, Exchange.Configured{source, options}, milliseconds, parent, request, priority, maximum, cursor)

# Borrow the same persistent owner as single-family lookups. Immutable settings
# supply search, transport, request and deadline policy; rotation state persists
# across calls. Priority remains an explicit caller choice.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  match resolver:
    case Resolver.Resolver{+config, source}: planned(~Environment, ~draw, ~Reason, environment, source, config, parent, priority, Configuration.plan(Settings.search(Endpoint.Endpoint, config), name, dots, absolute))

def lookup(~Reason: Data, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  lookupWith(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, priority, name, dots, absolute)
