import Base
import ../packages/runtime/src/resolver-system-linux.bend as Linux
import ../packages/runtime/src/resolver-system.bend as System
import ../packages/runtime/src/resolver-file.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/resolver-load.bend as Load
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-environment.bend as Environment
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-hostname.bend as HostTest
import ./resolver-file.bend as FileTest
import ./resolver-system.bend as SystemTest

type Mode is Data:
  Open{}
  Read{}
  Size{}
  Large{}
  Decode{}
  Success{}
  FileMode{}
  EnvironmentFailure{}
  SystemMode{}

def mode(+text: String) -> Mode:
  Bool.pick(Mode, String.eq(text, "open"), Open{},
    Bool.pick(Mode, String.eq(text, "read"), Read{},
      Bool.pick(Mode, String.eq(text, "size"), Size{},
        Bool.pick(Mode, String.eq(text, "large"), Large{},
          Bool.pick(Mode, String.eq(text, "decode"), Decode{},
            Bool.pick(Mode, String.eq(text, "file"), FileMode{},
              Bool.pick(Mode, String.eq(text, "env-fail"), EnvironmentFailure{},
                Bool.pick(Mode, String.eq(text, "system"), SystemMode{}, Success{}))))))))

# Synthetic results exercise the same post-read path without faulting the OS.
def input(mode: Mode, code: U32) -> Result<&2, &2, File.Error<String>, List<&2, Config.Entry>>:
  match mode:
    case Open{}: Fail{File.File{Fold.Open{code, "marker"}}}
    case Read{}: Fail{File.File{Fold.Read{code, "marker"}}}
    case Size{}: Fail{File.File{Fold.InvalidReadSize{}}}
    case Large{}: Fail{File.TooLarge{}}
    case Decode{}: Fail{File.Decode{"marker"}}
    case _: Done{Config.parse("search file.test\noptions ndots:3")}

def unavailable(value: Maybe<&2, Linux.Unavailable>) -> String:
  match value:
    case None{}: "file:present"
    case Some{Linux.Unavailable{code, message}}: "file:unavailable:" ++ U32.show(code) ++ ":" ++ Bool.pick(String, String.eq(message, "marker"), "marker", "os")

def report(value: Result<&2, &2, Load.Error<String>, Linux.Report>) -> IO(Unit):
  match value:
    case Fail{error}: SystemTest.report(Fail{error})
    case Done{Linux.Report{configuration, missing}}:
      do IO<Unit>:
        SystemTest.report(Done{configuration})
        IO.print(unavailable(missing))

def captured(+mode: Mode, value: String, chunk: U32, limit: Nat, source: HostTest.Source, environment: Result<&2, &2, Environment.Error, Environment.Values>) -> IO(Result<&2, &2, Load.Error<String>, Linux.Report>):
  match mode:
    case FileMode{}: Linux.capturedWith(~String, ~FileTest.decode, ~HostTest.Source, ~HostTest.lookup, source, value, chunk, limit, environment)
    case EnvironmentFailure{}: Linux.capturedWith(~String, ~FileTest.decode, ~HostTest.Source, ~HostTest.lookup, source, value, chunk, limit, Fail{Environment.Error{"LOCALDOMAIN", 13, "marker"}})
    case SystemMode{}: Linux.loadWith(~String, ~FileTest.decode, value, chunk, limit)
    case _:
      match environment:
        case Fail{error}: IO.pure(Result<&2, &2, Load.Error<String>, Linux.Report>, Fail{Load.Environment{error}})
        case Done{values}: Linux.parsedWith(~String, ~HostTest.Source, ~HostTest.lookup, source, values, input(mode, Scalar.decimal(value, 0)))

def args(values: List<String>) -> IO(Unit):
  match values:
    case command <> value <> chunk <> limit <> fail <> name <> Nil{}:
      do IO<Unit>:
        environment : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
        result : Result<&2, &2, Load.Error<String>, Linux.Report> <- captured(mode(command), value, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), HostTest.Source{String.eq(fail, "fail"), name}, environment)
        report(result)
    case _: IO.die(Unit, 1, "expected mode value chunk limit hostname-mode hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
