import Base
import ../packages/ai/src/api/openai-responses-cleartext-system-runtime.bend as S
import ../packages/runtime/src/resolver-system-config.bend as Config
import ../packages/runtime/src/resolver-system-servers.bend as Source
import ../packages/runtime/src/resolver-load.bend as Load
import ../packages/runtime/src/resolver-file.bend as ResolverFile
import ../packages/runtime/src/resolver-configuration.bend as Resolver
import ../packages/runtime/src/resolver-transport.bend as Transport
import ../packages/runtime/src/resolver-options.bend as Options
import ../packages/runtime/src/socket-endpoint.bend as Endpoint
import ../packages/runtime/src/dns-udp-plan.bend as Plan
import ../packages/runtime/src/hosts-load.bend as Hosts
import ../packages/runtime/src/hosts.bend as Database
import ../packages/runtime/src/hosts-file.bend as Parser
import ../packages/runtime/src/bounded-file.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/test/utf8-runner.bend as Scalar

def hosts(value: S.HostResult()) -> String:
  match value:
    case Done{entries}: "hosts:rows:" ++ Nat.show(List.length(&2, Database.Entry<Parser.Address>, entries))
    case Fail{Hosts.Parsing{_}}: "hosts:parse"
    case Fail{Hosts.Loading{File.Decode{_}}}: "hosts:decode"
    case Fail{Hosts.Loading{File.TooLarge{}}}: "hosts:large"
    case Fail{Hosts.Loading{File.File{Fold.Open{code, _}}}}: "hosts:open:" ++ U32.show(code)
    case Fail{_}: "hosts:other"

def source(value: Source.Report) -> String:
  match value:
    case Source.Report{_, _, None{}}: "source:available"
    case Source.Report{_, _, Some{_}}: "source:unavailable"

def settings(value: Resolver.Config<Endpoint.Endpoint>) -> String:
  match value:
    case Resolver.Config{Transport.Prepared{Options.Options{ndots, timeout, attempts, _}, servers}, _, milliseconds, maximum}:
      "settings:" ++ U32.show(ndots) ++ ":" ++ U32.show(timeout) ++ ":" ++ U32.show(attempts) ++ ":" ++ Nat.show(List.length(&2, Plan.Attempt<Endpoint.Endpoint>, servers)) ++ ":" ++ U32.show(milliseconds) ++ ":" ++ U32.show(maximum)

def report(value: Result<&2, &2, S.Error, S.Snapshot>) -> IO(Unit):
  match value:
    case Done{S.Snapshot{Config.Prepared{origin, _, resolver}, entries}}:
      do IO<Unit>:
        IO.print(source(origin))
        IO.print(settings(resolver))
        IO.print(hosts(entries))
    case Fail{S.ConfigurationFailure{Config.Loading{Load.File{ResolverFile.Decode{_}}}}}: IO.print("resolver:decode")
    case Fail{S.ConfigurationFailure{Config.Loading{Load.File{ResolverFile.TooLarge{}}}}}: IO.print("resolver:large")
    case Fail{S.ConfigurationFailure{Config.InvalidOptions{_, _}}}: IO.print("resolver:options")
    case Fail{S.ConfigurationFailure{Config.InvalidTransport{_, _}}}: IO.print("resolver:transport")
    case Fail{_}: IO.print("resolver:other")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case resolver <> hosts <> chunk <> limit <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, S.Error, S.Snapshot> <- S.load(S.Files{resolver, hosts, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), 4321, 4096})
        report(value)
    case _: IO.die(Unit, 1, "expected resolver hosts chunk limit")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
