import Base
import ../packages/runtime/src/dns-resolver.bend as Owner
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/dns-resolver.bend as System
import ../packages/runtime/src/resolver-config.bend as Resolver
import ../packages/runtime/src/resolver-config.bend as Transport
import ../packages/runtime/src/resolver-config.bend as Options
import ../packages/runtime/src/resolver-config.bend as Configuration
import ../packages/runtime/src/dns-transport.bend as Network
import ../packages/runtime/src/resolver-config.bend as Plan
import ../packages/runtime/src/resolver-config.bend as Timeout
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-system-servers.bend as SourceTest
import ./resolver-servers.bend as ServersTest
import ./resolver-file.bend as FileTest
import ./resolver-load.bend as LoadTest
import ./resolver-options.bend as OptionsTest
import ./resolver-request.bend as RequestTest

def limits(policy: Search.Policy, rotate: Bool, milliseconds: U32, maximum: U32) -> IO(Unit):
  match policy:
    case Search.Policy{ndots, defaults, search, noTld}: IO.print("config:" ++ U32.show(ndots) ++ OptionsTest.bit(defaults) ++ OptionsTest.bit(search) ++ OptionsTest.bit(noTld) ++ OptionsTest.bit(rotate) ++ ":" ++ U32.show(milliseconds) ++ ":" ++ U32.show(maximum))

def budget(entries: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> String:
  match entries:
    case Nil{}: ""
    case Plan.Attempt{_, _, duration} <> rest: U32.show(U32.from_nat(Timeout.seconds(duration))) ++ "," ++ budget(rest)

def transport(options: Options.OptionsOptions, servers: List<&2, Plan.Attempt<Endpoint.Endpoint>>) -> IO(Unit):
  match options:
    case Options.OptionsOptions{ndots, +timeout, +attempts, +features}: IO.print("transport:" ++ U32.show(timeout) ++ ":" ++ U32.show(attempts) ++ ":" ++ budget(servers) ++ ":" ++ OptionsTest.flags(OptionsTest.features(), Options.OptionsOptions{ndots, timeout, attempts, features}, ""))

def config(value: Resolver.Config<Endpoint.Endpoint>) -> IO(Unit):
  match value:
    case Resolver.Config{Transport.TransportPrepared{+options, +servers}, domains, milliseconds, maximum}:
      do IO<Unit>:
        limits(Configuration.policy(options), Options.enabled(Options.Rotate{}, options), milliseconds, maximum)
        IO.print(RequestTest.query(Configuration.requestOptions(Configuration.Configuration{options, domains})))
        ServersTest.servers(Network.entries(servers))
        transport(options, servers)

def invalid(error: Plan.Error) -> String:
  match error:
    case Plan.NoServers{}: "no-servers"
    case Plan.TooManyServers{}: "too-many"
    case Plan.InvalidTimeout{seconds}: "timeout:" ++ U32.show(seconds)

def seed(unused: Unit) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{0})

def created(value: Result<&2, &1, Index.Error, Owner.Owner>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit, 1, "owner creation failed")
    case Done{owner}:
      do IO<Unit>:
        Owner.close(owner)
        IO.print("owner:closed")

def initialize(+value: Resolver.Config<Endpoint.Endpoint>) -> IO(Unit):
  do IO<Unit>:
    config(value)
    owner : Result<&2, &1, Index.Error, Owner.Owner> <- Owner.createWith(~Unit, ~seed, Unit{}, value)
    created(owner)

def report(value: Result<&2, &2, System.SystemConfigError<String>, System.SystemConfigPrepared>) -> IO(Unit):
  match value:
    case Fail{System.InvalidTransport{source, error}}:
      do IO<Unit>:
        SourceTest.report(Done{source})
        IO.print("transport-rejected:" ++ invalid(error))
    case Fail{System.Loading{error}}: LoadTest.report(Fail{error})
    case Fail{System.InvalidOptions{source, errors}}:
      do IO<Unit>:
        SourceTest.report(Done{source})
        IO.print("rejected")
        OptionsTest.diagnostics(errors)
    case Done{System.SystemConfigPrepared{source, _, resolver}}:
      do IO<Unit>:
        SourceTest.report(Done{source})
        initialize(resolver)

def args(values: List<String>) -> IO(Unit):
  match values:
    case path <> chunk <> limit <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, System.SystemConfigError<String>, System.SystemConfigPrepared> <- System.loadWith(~String, ~FileTest.decode, path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), 4321, 17)
        report(value)
    case _: IO.die(Unit, 1, "expected path chunk limit")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
