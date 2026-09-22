import Base
import ../packages/runtime/src/resolver-config.bend as Linux
import ../packages/runtime/src/resolver-config.bend as System
import ../packages/runtime/src/resolver-config.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/resolver-config.bend as Load
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Environment
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-hostname.bend as HostTest
import ./resolver-file.bend as FileTest
import ./resolver-system.bend as SystemTest

# Synthetic results exercise the same post-read path without faulting the OS.
def input(mode: String, code: U32) -> Result<&2, &2, File.FileError<String>, List<&2, Config.Entry>>:
  match mode:
    case "open": Fail{File.File{Fold.Open{code, "marker"}}}
    case "read": Fail{File.File{Fold.Read{code, "marker"}}}
    case "size": Fail{File.File{Fold.InvalidReadSize{}}}
    case "large": Fail{File.TooLarge{}}
    case "decode": Fail{File.Decode{"marker"}}
    case _: Done{Config.parse("search file.test\noptions ndots:3")}

def unavailable(value: Maybe<&2, Linux.Unavailable>) -> String:
  match value:
    case None{}: "file:present"
    case Some{Linux.Unavailable{code, message}}: "file:unavailable:" ++ U32.show(code) ++ ":" ++ Bool.pick(String, String.eq(message, "marker"), "marker", "os")

def report(value: Result<&2, &2, Load.LoadError<String>, Linux.SystemLinuxReport>) -> IO(Unit):
  match value:
    case Fail{error}: SystemTest.report(Fail{error})
    case Done{Linux.SystemLinuxReport{configuration, missing}}:
      do IO<Unit>:
        SystemTest.report(Done{configuration})
        IO.print(unavailable(missing))

def captured(+mode: String, value: String, chunk: U32, limit: Nat, source: HostTest.Source, environment: Result<&2, &2, Environment.EnvironmentError, Environment.Values>) -> IO(Result<&2, &2, Load.LoadError<String>, Linux.SystemLinuxReport>):
  match mode:
    case "file": Linux.capturedWithSystemLinux(~String, ~FileTest.decode, ~HostTest.Source, ~HostTest.lookup, source, value, chunk, limit, environment)
    case "env-fail": Linux.capturedWithSystemLinux(~String, ~FileTest.decode, ~HostTest.Source, ~HostTest.lookup, source, value, chunk, limit, Fail{Environment.EnvironmentError{"LOCALDOMAIN", 13, "marker"}})
    case "system": Linux.loadWithSystemLinux(~String, ~FileTest.decode, value, chunk, limit)
    case _:
      match environment:
        case Fail{error}: IO.pure(Result<&2, &2, Load.LoadError<String>, Linux.SystemLinuxReport>, Fail{Load.Environment{error}})
        case Done{values}: Linux.parsedWith(~String, ~HostTest.Source, ~HostTest.lookup, source, values, input(mode, Scalar.decimal(value, 0)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> value <> chunk <> limit <> fail <> name <> Nil{}:
      do IO<Unit>:
        environment : Result<&2, &2, Environment.EnvironmentError, Environment.Values> <- Environment.capture()
        result : Result<&2, &2, Load.LoadError<String>, Linux.SystemLinuxReport> <- captured(mode, value, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), HostTest.Source{String.eq(fail, "fail"), name}, environment)
        report(result)
    case _: IO.die(Unit, 1, "expected mode value chunk limit hostname-mode hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
