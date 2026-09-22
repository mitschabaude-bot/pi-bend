import Base
import ./http-host-route.bend as Route
import ./url-host.bend as Host
import ./dns-resolver.bend as Named
import ./dns-resolver.bend as Resolver
import ./dns-resolver.bend as Pair
import ./dns-message.bend as Id
import ./hosts.bend as Hosts
import ./hosts.bend as File
import ./hosts.bend as HostsResolve
import ./abort.bend as Abort

type Context<-Environment: Data, -Reason: Data, -Error: Data> is Data:
  Context{environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>}

def named(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, context: Context<Environment, Reason, Error>, name: String) -> IO(HostsResolve.Report<Error, Named.PairHostsResolverDNS<Reason>>):
  match context:
    case Context{environment, resolver, parent, priority, hosts}: Named.lookupWithPairHostsResolver(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, priority, name, hosts)

# Numeric URL hosts bypass hosts results and DNS, including failed hosts
# snapshots. Domain hosts retain the complete existing hosts/DNS report. The
# resolver and parent remain borrowed; this layer creates no connection.
def resolveWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Result<&2, &2, Route.Error, Route.Resolution<HostsResolve.Report<Error, Named.PairHostsResolverDNS<Reason>>>>):
  Route.resolveWith(~Context<Environment, Reason, Error>, ~HostsResolve.Report<Error, Named.PairHostsResolverDNS<Reason>>, ~named(~Environment, ~draw, ~Reason, ~Error), Context{environment, resolver, parent, priority, hosts}, host)

def resolve(~Reason: Data, ~Error: Data, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Result<&2, &2, Route.Error, Route.Resolution<HostsResolve.Report<Error, Named.PairHostsResolverDNS<Reason>>>>):
  resolveWith(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, host, hosts)
