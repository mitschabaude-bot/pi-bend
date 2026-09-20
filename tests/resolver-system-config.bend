import Base
import ../packages/runtime/src/resolver-system-config.bend as System
import ../packages/runtime/src/dns-tcp-resolver.bend as Resolver
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-system-servers.bend as SourceTest
import ./resolver-servers.bend as ServersTest
import ./resolver-file.bend as FileTest
import ./resolver-load.bend as LoadTest
import ./resolver-options.bend as OptionsTest
import ./resolver-request.bend as RequestTest

def config(value: Resolver.Config) -> IO(Unit):
  match value:
    case Resolver.Config{servers, _, Search.Policy{ndots, defaults, search, noTld}, request, milliseconds, maximum, rotate}:
      do IO<Unit>:
        IO.print("config:" ++ U32.show(ndots) ++ OptionsTest.bit(defaults) ++ OptionsTest.bit(search) ++ OptionsTest.bit(noTld) ++ OptionsTest.bit(rotate) ++ ":" ++ U32.show(milliseconds) ++ ":" ++ U32.show(maximum))
        IO.print(RequestTest.query(request))
        ServersTest.servers(servers)

def report(value: Result<&2, &2, System.Error<String>, System.Prepared>) -> IO(Unit):
  match value:
    case Fail{System.Loading{error}}: LoadTest.report(Fail{error})
    case Fail{System.InvalidOptions{source, errors}}:
      do IO<Unit>:
        SourceTest.report(Done{source})
        IO.print("rejected")
        OptionsTest.diagnostics(errors)
    case Done{System.Prepared{source, _, resolver}}:
      do IO<Unit>:
        SourceTest.report(Done{source})
        config(resolver)

def args(values: List<String>) -> IO(Unit):
  match values:
    case path <> chunk <> limit <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, System.Error<String>, System.Prepared> <- System.loadWith(~String, ~FileTest.decode, path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), 4321, 17)
        report(value)
    case _: IO.die(Unit, 1, "expected path chunk limit")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
