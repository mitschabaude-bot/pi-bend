import Base
import ../packages/runtime/src/resolver-system-servers.bend as System
import ../packages/runtime/src/resolver-system-linux.bend as Linux
import ../packages/runtime/src/resolver-load.bend as Load
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-servers.bend as ServersTest
import ./resolver-hostname.bend as HostTest
import ./resolver-file.bend as FileTest
import ./resolver-load.bend as LoadTest

def unavailable(value: Maybe<&2, Linux.Unavailable>) -> String:
  match value:
    case None{}: "present"
    case Some{Linux.Unavailable{code, _}}: "unavailable:" ++ U32.show(code)

def report(value: Result<&2, &2, Load.Error<String>, System.Report>) -> IO(Unit):
  match value:
    case Fail{error}: LoadTest.report(Fail{error})
    case Done{System.Report{configuration, hostname, file}}:
      do IO<Unit>:
        ServersTest.configured(configuration)
        IO.print(HostTest.diagnostic(hostname))
        IO.print(unavailable(file))

def args(values: List<String>) -> IO(Unit):
  match values:
    case path <> chunk <> limit <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, Load.Error<String>, System.Report> <- System.loadWith(~String, ~FileTest.decode, path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)))
        report(value)
    case _: IO.die(Unit, 1, "expected path chunk limit")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
