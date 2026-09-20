import Base
import ./dns-server-source.bend as Source
import ./dns-server-initialize.bend as Initialize
import ./dns-tcp-servers.bend as Servers
import ./dns-search.bend as Search
import ./dns-name.bend as Name
import ./dns-address-search.bend as Network
import ./dns-id.bend as Id
import ./random-index.bend as Index
import ./abort.bend as Abort

# Explicit, already-resolved TCP configuration. OS loading, IPv6 interface
# resolution and resolver-option interpretation are separate boundaries.
type Config is Data:
  Config{servers: List<&2, Servers.Server>, domains: List<&2, Name.Name>, policy: Search.Policy, milliseconds: U32, maximum: U32, rotate: Bool}

type Owner is Type:
  Owner{config: Config, selector: Source.Owner<Servers.Server>}

type Resolver is Data:
  Resolver{source: Source.Source<Servers.Server>, domains: List<&2, Name.Name>, policy: Search.Policy, milliseconds: U32, maximum: U32}

type Replacement is Type:
  Updated{owner: Owner}
  Unchanged{error: Index.Error, owner: Owner}

def initialized(config: Config, result: Result<&2, &1, Index.Error, Source.Owner<Servers.Server>>) -> Result<&2, &1, Index.Error, Owner>:
  match result:
    case Fail{error}: Fail{error}
    case Done{selector}: Done{Owner{config, selector}}

def configured(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Config, servers: List<&2, Servers.Server>, rotate: Bool) -> IO(Result<&2, &1, Index.Error, Owner>):
  match rotate:
    case False{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Source.Owner<Servers.Server> <- Source.create(Servers.Server, servers)
        return Done{Owner{config, selector}}
    case True{}:
      do IO<Result<&2, &1, Index.Error, Owner>>:
        selector : Result<&2, &1, Index.Error, Source.Owner<Servers.Server>> <- Initialize.createWith(~Environment, ~draw, Servers.Server, environment, servers)
        return initialized(config, selector)

def createWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, config: Config) -> IO(Result<&2, &1, Index.Error, Owner>):
  match config:
    case Config{+servers, domains, policy, milliseconds, maximum, +rotate}:
      configured(~Environment, ~draw, environment, Config{servers, domains, policy, milliseconds, maximum, rotate}, servers, rotate)

def create(config: Config) -> IO(Result<&2, &1, Index.Error, Owner>):
  createWith(~Unit, ~Index.word, Unit{}, config)

def borrowed(config: Config, pair: Source.Owner<Servers.Server> & Source.Source<Servers.Server>) -> Owner & Resolver:
  match config pair:
    case Config{servers, +domains, +policy, +milliseconds, +maximum, rotate} Tuple{selector, source}:
      (Owner{Config{servers, domains, policy, milliseconds, maximum, rotate}, selector}, Resolver{source, domains, policy, milliseconds, maximum})

def borrow(owner: Owner) -> Owner & Resolver:
  match owner:
    case Owner{Config{servers, domains, policy, milliseconds, maximum, +rotate}, selector}:
      borrowed(Config{servers, domains, policy, milliseconds, maximum, rotate}, Source.borrow(Servers.Server, rotate, selector))

# Finish all borrowed operations before close or replacement. Configuration
# snapshots are immutable; a replacement never mutates an active snapshot.
def close(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{_, selector}: Source.close(Servers.Server, selector)

def replaced(previous: Owner, result: Result<&2, &1, Index.Error, Owner>) -> IO(Replacement):
  match result:
    case Fail{error}: IO.pure(Replacement, Unchanged{error, previous})
    case Done{next}:
      do IO<Replacement>:
        close(previous)
        return Updated{next}

# Construction failure returns the still-usable previous owner. On success,
# retire the previous selector only after its replacement has been created.
def replaceWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Index.Error, U32>), environment: Environment, previous: Owner, config: Config) -> IO(Replacement):
  do IO<Replacement>:
    next : Result<&2, &1, Index.Error, Owner> <- createWith(~Environment, ~draw, environment, config)
    replaced(previous, next)

def replace(previous: Owner, config: Config) -> IO(Replacement):
  replaceWith(~Unit, ~Index.word, Unit{}, previous, config)

# Rotation survives across calls; each search owns one deadline spanning all
# its candidate, alias and server attempts. The supplied parent stays borrowed.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  match resolver:
    case Resolver{source, domains, policy, milliseconds, maximum}:
      Network.searchSourceWith(~Environment, ~draw, ~Reason, environment, source, milliseconds, parent, kind, maximum, Search.start(name, dots, absolute, domains, policy))

def lookup(~Reason: Data, resolver: Resolver, parent: Abort.AbortSignal<Reason>, kind: U32, name: Name.Name, dots: U32, absolute: Bool) -> IO(Network.Report<Reason>):
  lookupWith(~Unit, ~Id.random, ~Reason, Unit{}, resolver, parent, kind, name, dots, absolute)
