import Base
import ../packages/runtime/src/resolver-config.bend as Load
import ../packages/runtime/src/resolver-config.bend as Environment
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-file.bend as FileTest

def report(result: Result<&2, &2, Load.LoadError<String>, Settings.Settings>) -> IO(Unit):
  match result:
    case Fail{Load.Environment{Environment.EnvironmentError{variable, code, _}}}: IO.print("environment:" ++ variable ++ ":" ++ U32.show(code))
    case Fail{Load.LoadFile{error}}: FileTest.report(Fail{error})
    case Done{settings}: FileTest.report(Done{settings})

def run(failCapture: Bool, path: String, chunk: U32, limit: Nat, hostname: String) -> IO(Result<&2, &2, Load.LoadError<String>, Settings.Settings>):
  match failCapture:
    case False{}: Load.loadWithLoad(~String, ~FileTest.decode, Some{hostname}, path, chunk, limit)
    case True{}: Load.captured(~String, ~FileTest.decode, Some{hostname}, path, chunk, limit, Fail{Environment.EnvironmentError{"LOCALDOMAIN", 13, "unavailable"}})

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> path <> chunk <> limit <> hostname <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &2, Load.LoadError<String>, Settings.Settings> <- run(String.eq(mode, "fail"), path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), hostname)
        report(result)
    case _: IO.die(Unit, 1, "expected mode path chunk limit hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
