import Base
import ../packages/runtime/src/connection-plan.bend as Dispatch
import ../packages/runtime/src/http-connect.bend as HTTP
import ../packages/runtime/src/connection-driver.bend as Driver
import ../packages/runtime/src/connection-progress.bend as Progress
import ../packages/runtime/src/connection-order.bend as Order
import ../packages/runtime/src/http-host-route.bend as Route
import ../packages/runtime/src/hosts-resolve.bend as HostsResolve
import ../packages/runtime/src/hosts-file.bend as File
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/url-host.bend as Host
import ../packages/runtime/src/url-ipv4.bend as IPv4
import ../packages/runtime/src/url-ipv6.bend as IPv6
import ../packages/runtime/src/dns-resolver.bend as Resolver
import ../packages/runtime/src/resolver-configuration.bend as Settings
import ../packages/runtime/src/resolver-search.bend as Search
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/dns-udp-plan.bend as Plan
import ../packages/runtime/src/dns-pair-result.bend as Pair
import ../packages/runtime/src/dns-id.bend as Id
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./connection-driver.bend as Show

def draw(mode: U32) -> IO(Result<&2, &2, Id.Error, U32>):
  match mode:
    case 4: Id.random(Unit{})
    case _: IO.die(Result<&2, &2, Id.Error, U32>, 1, "unexpected DNS")

def preference(mode: U32, family: Bool) -> Order.Preference:
  match mode family:
    case 4 False{}: Order.IPv4First{}
    case _ _: Order.IPv6First{}

def host(mode: U32, family: Bool) -> Host.Host:
  match mode family:
    case 0 False{}: Host.IPv4{IPv4.Address{2130706433}}
    case 0 True{}: Host.IPv6{IPv6.Address{0, 0, 0, 1}}
    case 3 _: Host.Empty{}
    case _ _: Host.Domain{"unit"}

def database(mode: U32, family: Bool) -> Result<&2, &2, File.Failure, List<&2, Hosts.Entry<File.Address>>>:
  match mode family:
    case 0 _: File.parse("invalid file")
    case 2 _: File.parse("invalid file")
    case 4 _: File.parse("")
    case _ False{}: File.parse("127.0.0.1 unit\n::1 unit\n127.0.0.1 unit")
    case _ True{}: File.parse("::1 unit\n127.0.0.1 unit\n::1 unit")

def resolution(value: HTTP.Resolution(String, File.Failure)) -> IO(Unit):
  match value:
    case Done{Route.NumericAddress{_}}: IO.print("numeric")
    case Done{Route.Named{HostsResolve.FromHosts{_, _}}}: IO.print("hosts")
    case Done{Route.Named{HostsResolve.FailedSource{_}}}: IO.print("source-error")
    case Fail{Route.InvalidHost{}}: IO.print("invalid-host")
    case Done{Route.Named{HostsResolve.FromNetwork{_}}}: IO.print("dns")
    case _: IO.die(Unit, 1, "unexpected resolution")

def checked(value: Dispatch.Report<HTTP.Resolution(String, File.Failure), String, Socket>) -> IO(Unit):
  match value:
    case Dispatch.Unresolved{original}:
      do IO<Unit>:
        resolution(original)
        IO.print("unresolved")
    case Dispatch.Attempted{original, result}:
      do IO<Unit>:
        resolution(original)
        Show.socketReport(result)

def run(+mode: U32, +family: Bool, port: U32, pair: Resolver.Owner & Resolver.Resolver) -> IO(Unit):
  match pair:
    case (owner, resolver):
      do IO<Unit>:
        +parent : Abort.AbortController<String> <- Abort.new(String)
        value : Dispatch.Report<HTTP.Resolution(String, File.Failure), String, Socket> <- HTTP.openWith(~U32, ~draw, ~String, ~File.Failure, mode, resolver, Abort.signal(String, parent), Pair.IPv4First{}, preference(mode, family), Driver.Options{port, 30}, host(mode, family), database(mode, family))
        checked(value)
        Resolver.close(owner)
        Abort.dispose(String, parent)

def seed(value: U32) -> IO(Result<&2, &2, Index.Error, U32>):
  IO.pure(Result<&2, &2, Index.Error, U32>, Done{value})

def created(mode: U32, family: Bool, port: U32, result: Result<&2, &1, Index.Error, Resolver.Owner>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "resolver initialization")
    case Done{owner}: run(mode, family, port, Resolver.borrow(owner))

def prepared(mode: U32, family: Bool, port: U32, result: Result<&2, &2, Plan.Error, Settings.Config<Endpoint.Endpoint>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "configuration")
    case Done{config}:
      do IO<Unit>:
        owner : Result<&2, &1, Index.Error, Resolver.Owner> <- Resolver.createWith(~U32, ~seed, 0, config)
        created(mode, family, port, owner)

def configured(mode: U32, family: Bool, port: U32, dnsPort: U32) -> IO(Unit):
  prepared(mode, family, port, Settings.prepare(Endpoint.Endpoint, Endpoint.V4{IPv4.Address{2130706433}, dnsPort} <> Nil{}, 1000, 512, Search.prepare(Options.Options{1, 1, 1, Nil{}}, Nil{})))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case mode <> family <> port <> Nil{}: configured(Scalar.decimal(mode, 0), String.eq(family, "6"), Scalar.decimal(port, 0), 9)
    case mode <> family <> port <> dnsPort <> Nil{}: configured(Scalar.decimal(mode, 0), String.eq(family, "6"), Scalar.decimal(port, 0), Scalar.decimal(dnsPort, 0))
    case _: IO.die(Unit, 1, "expected mode family port [dns-port]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
