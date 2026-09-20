import Base
import ./resolver-search.bend as Configuration
import ./resolver-options.bend as Options
import ./dns-server-source.bend as Source
import ./dns-server-initialize.bend as Initialize
import ./dns-name.bend as Name
import ./dns-address-search.bend as Network
import ./dns-id.bend as Id
import ./random-index.bend as Index
import ./abort.bend as Abort

import ./resolver-configuration.bend as Settings
import ./resolver-transport.bend as Transport
import ./dns-udp-plan.bend as Plan
import ./socket-endpoint.bend as Endpoint
import ./dns-exchange-source.bend as Exchange

# Own only rotation state. Immutable validated settings are retained across
# borrows; every lookup derives search and wire policy from the same options.
type Owner is Type:
  Owner{config: Settings.Config<Endpoint.Endpoint>, selector: Source.Owner<Plan.Attempt<Endpoint.Endpoint>>}

type Resolver is Data:
  Resolver{config: Settings.Config<Endpoint.Endpoint>, source: Source.Source<Plan.Attempt<Endpoint.Endpoint>>}

type Replacement is Type:
  Updated{owner: Owner}
  Unchanged{error: Index.Error, owner: Owner}

def initialized(config: Settings.Config<Endpoint.Endpoint>, result: Result<&2, &1, Index.Error, Source.Owner<Plan.Attempt<Endpoint.Endpoint>>>) -> Result<&2, &1, Index.Error, Owner>:
  match result:
    case Fail{error}: Fail{error}
    case Done{selector}: Done{Owner{config, selector}}

def configured(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Settings.Config<Endpoint.Endpoint>, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>, rotate: Bool) -> IO(Result<&2, &1, Index.Error, Owner>):
  match rotate:
    case False{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Source.Owner<Plan.Attempt<Endpoint.Endpoint>> <- Source.create(Plan.Attempt<Endpoint.Endpoint>, servers)
        return Done{Owner{config, selector}}
    case True{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Result<&2, &1, Index.Error, Source.Owner<Plan.Attempt<Endpoint.Endpoint>>> <- Initialize.createWith(~Environment, ~draw, Plan.Attempt<Endpoint.Endpoint>, environment, servers)
        return initialized(config, selector)

def createWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Settings.Config<Endpoint.Endpoint>) -> IO(Result<&2, &1, Index.Error, Owner>):
  match config:
    case Settings.Config{Transport.Prepared{+options, +servers}, domains, milliseconds, maximum}:
      configured(~Environment, ~draw, environment, Settings.Config{Transport.Prepared{options, servers}, domains, milliseconds, maximum}, servers, Options.enabled(Options.Rotate{}, options))

def create(config: Settings.Config<Endpoint.Endpoint>) -> IO(Result<&2, &1, Index.Error, Owner>):
  createWith(~Unit, ~Index.word, Unit{}, config)

def borrowed(+config: Settings.Config<Endpoint.Endpoint>, pair: Source.Owner<Plan.Attempt<Endpoint.Endpoint>> & Source.Source<Plan.Attempt<Endpoint.Endpoint>>) -> Owner & Resolver:
  match pair:
    case (selector, source): (Owner{config, selector}, Resolver{config, source})

def borrow(owner: Owner) -> Owner & Resolver:
  match owner:
    case Owner{+config, selector}: borrowed(config, Source.borrow(Plan.Attempt<Endpoint.Endpoint>, Settings.rotating(Endpoint.Endpoint, config), selector))

# Finish all borrowed operations before close or replacement. Configuration
# snapshots are immutable; a replacement never mutates an active snapshot.
def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_, selector}: Source.close(Plan.Attempt<Endpoint.Endpoint>, selector)

def replaced(previous: Owner, result: Result<&2, &1, Index.Error, Owner>) -> IO(Replacement):
  match result:
    case Fail{error}: IO.pure(Replacement, Unchanged{error, previous})
    case Done{next}:
      do IO<Replacement>:
        close(previous)
        return Updated{next}

# Construction failure returns the still-usable previous owner. On success,
# retire the previous selector only after its replacement has been created.
def replaceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, previous: Owner, config: Settings.Config<Endpoint.Endpoint>) -> IO(Replacement):
  do IO<Replacement>:
    next : Result<&2, &1, Index.Error, Owner> <- createWith(~Environment, ~draw, environment, config)
    replaced(previous, next)

def replace(previous: Owner, config: Settings.Config<Endpoint.Endpoint>) -> IO(Replacement):
  replaceWith(~Unit, ~Index.word, Unit{}, previous, config)

# Rotation survives across calls; each search owns one deadline spanning all
# its candidate, alias and server attempts. The supplied parent stays borrowed.
def planned(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, source: Source.Source<Plan.Attempt<Endpoint.Endpoint>>, config: Settings.Config<Endpoint.Endpoint>, parent: Abort.AbortSignal<Reason>, kind: U32, plan: Configuration.Plan) -> IO(Network.Report<Reason>):
  match config plan:
    case Settings.Config{Transport.Prepared{options, _}, _, milliseconds, maximum} Configuration.Plan{request, cursor}: Network.searchTransportOptionsWith(~Environment, ~draw, ~Reason, environment, Exchange.Configured{source, options}, milliseconds, parent, request, kind, maximum, cursor)

def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  match resolver:
    case Resolver{+config, source}:
      planned(~Environment, ~draw, ~Reason, environment, source, config, parent, kind, Configuration.plan(Settings.search(Endpoint.Endpoint, config), name, dots, absolute))

def lookup(~Reason: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  lookupWith(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, kind, name, dots, absolute)
