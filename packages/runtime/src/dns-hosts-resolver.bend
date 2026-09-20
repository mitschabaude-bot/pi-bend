import Base
import ./hosts.bend as Hosts
import ./hosts-file.bend as File
import ./hosts-family.bend as HostsFamily
import ./hosts-resolve.bend as HostsResolve
import ./dns-search-text.bend as Text
import ./dns-presentation.bend as Presentation
import ./dns-resolver.bend as Resolver
import ./dns-address-search.bend as Network
import ./dns-id.bend as Id
import ./abort.bend as Abort

# This entry point resolves one address family. A combined-family operation
# requires its own scheduling/deadline policy, not an implicit sequential pair.
type Family is Data:
  IPv4{}
  IPv6{}

def hostsFamily(family: Family) -> HostsFamily.Family:
  match family:
    case IPv4{}: HostsFamily.IPv4Only{}
    case IPv6{}: HostsFamily.IPv6Only{}

def recordType(family: Family) -> U32:
  match family:
    case IPv4{}: 1
    case IPv6{}: 28

type DNS<-Reason: Data> is Data:
  InvalidName{error: Presentation.Error}
  Completed{report: Network.Report<Reason>}

def network(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, family: Family, input: Result<&2, &2, Presentation.Error, Text.Input>) -> IO(DNS<Reason>):
  match input:
    case Fail{error}: IO.pure(DNS<Reason>, InvalidName{error})
    case Done{Text.Input{name, dots, absolute}}:
      do IO<DNS<Reason>>:
        report : Network.Report<Reason> <- Resolver.lookupWith(~Environment, ~draw, ~Reason, environment, resolver, parent, recordType(family), name, dots, absolute)
        return Completed{report}

def execute(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, family: Family, plan: HostsResolve.Plan<Error>) -> IO(HostsResolve.Report<Error, DNS<Reason>>):
  match plan:
    case HostsResolve.SourceFailure{error}: IO.pure(HostsResolve.Report<Error, DNS<Reason>>, HostsResolve.FailedSource{error})
    case HostsResolve.Local{first, rest}: IO.pure(HostsResolve.Report<Error, DNS<Reason>>, HostsResolve.FromHosts{first, rest})
    case HostsResolve.Query{_, text}:
      do IO<HostsResolve.Report<Error, DNS<Reason>>>:
        report : DNS<Reason> <- network(~Environment, ~draw, ~Reason, environment, resolver, parent, family, Text.prepare(text))
        return HostsResolve.FromNetwork{report}

# Borrow the existing resolver and parent signal. Local hits and source errors
# do not parse DNS text, draw identifiers, rotate servers or create deadlines.
def lookupWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.Error, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, +family: Family, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(HostsResolve.Report<Error, DNS<Reason>>):
  execute(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, family, HostsResolve.plan(Error, hostsFamily(family), name, source))

def lookup(~Reason: Data, ~Error: Data, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, family: Family, name: String, source: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(HostsResolve.Report<Error, DNS<Reason>>):
  lookupWith(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, family, name, source)
