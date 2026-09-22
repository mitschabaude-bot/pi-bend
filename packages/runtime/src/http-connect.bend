import Base
import ./http-host-resolver.bend as Resolve
import ./http-host-route.bend as Route
import ./http-addresses.bend as Addresses
import ./connection-driver.bend as Dispatch
import ./connection-driver.bend as Order
import ./connection-driver.bend as Driver
import ./abortable-connect.bend as Connect
import ./hosts.bend as HostsResolve
import ./dns-resolver.bend as Named
import ./dns-resolver.bend as Resolver
import ./dns-resolver.bend as Pair
import ./dns-message.bend as Id
import ./url-host.bend as Host
import ./hosts.bend as Hosts
import ./hosts.bend as File
import ./abort.bend as Abort

def Resolution(-Reason: Data, -Error: Data) -> Data:
  Result<&2, &2, Route.Error, Route.Resolution<HostsResolve.Report<Error, Named.PairHostsResolverDNS<Reason>>>>

# Both adapters are injectable. The ID source and connector are independent;
# resolution error priority and connection family preference are also distinct.
def resolveWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Context: Data, ~Reason: Data, ~Error: Data, ~Value: Type, ~connect: Context -> List<&2, Connect.Address> -> IO(Driver.Report<Reason, Value>), environment: Environment, context: Context, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Order.Preference, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Value>):
  do IO<Dispatch.PlanReport<Resolution(Reason, Error), Reason, Value>>:
    resolution : Resolution(Reason, Error) <- Resolve.resolveWith(~Environment, ~draw, ~Reason, ~Error, environment, resolver, parent, priority, host, hosts)
    Dispatch.executeWith(Context, Resolution(Reason, Error), Reason, Value, connect, context, preference, Addresses.prepare(Reason, Error, resolution))

type Connection<-Reason: Data> is Data:
  Connection{options: Driver.Options, parent: Abort.AbortSignal<Reason>}

def native(~Reason: Data, context: Connection<Reason>, addresses: List<&2, Connect.Address>) -> IO(Driver.Report<Reason, Socket>):
  match context:
    case Connection{options, parent}: Driver.run(~Reason, options, addresses, parent)

# Establish TCP only. The caller still owns resolver/parent and must complete
# TLS (when required) before sending HTTP application data over this socket.
def openWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Id.IdError, U32>), ~Reason: Data, ~Error: Data, environment: Environment, resolver: Resolver.Resolver, +parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Order.Preference, options: Driver.Options, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Socket>):
  resolveWith(~Environment, ~draw, ~Connection<Reason>, ~Reason, ~Error, ~Socket, ~native(~Reason), environment, Connection{options, parent}, resolver, parent, priority, preference, host, hosts)

def open(~Reason: Data, ~Error: Data, resolver: Resolver.Resolver, parent: Abort.AbortSignal<Reason>, priority: Pair.Priority, preference: Order.Preference, options: Driver.Options, host: Host.Host, hosts: Result<&2, &2, Error, List<&2, Hosts.Entry<File.Address>>>) -> IO(Dispatch.PlanReport<Resolution(Reason, Error), Reason, Socket>):
  openWith(~Unit, ~Id.random, ~Reason, ~Error, Unit{}, resolver, parent, priority, preference, options, host, hosts)
