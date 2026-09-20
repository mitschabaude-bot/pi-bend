import Base
import ../packages/runtime/src/resolver-system.bend as System
import ../packages/runtime/src/resolver-load.bend as Load
import ../packages/runtime/src/resolver-environment.bend as Environment
import ../packages/runtime/src/resolver-settings.bend as Settings
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-hostname.bend as HostTest
import ./resolver-file.bend as FileTest
import ./resolver-settings.bend as SettingsTest
import ./resolver-load.bend as LoadTest

def report(value: Result<&2, &2, Load.Error<String>, System.Report>) -> IO(Unit):
  match value:
    case Fail{error}: LoadTest.report(Fail{error})
    case Done{System.Report{settings, failure}}:
      do IO<Unit>:
        SettingsTest.report(settings)
        IO.print(HostTest.diagnostic(failure))

def captureResult(fail: Bool, value: Result<&2, &2, Environment.Error, Environment.Values>) -> Result<&2, &2, Environment.Error, Environment.Values>:
  match fail:
    case True{}: Fail{Environment.Error{"LOCALDOMAIN", 13, "unavailable"}}
    case False{}: value

def run(real: Bool, +mode: String, path: String, chunk: U32, limit: Nat, name: String) -> IO(Result<&2, &2, Load.Error<String>, System.Report>):
  match real:
    case True{}: System.loadWith(~String, ~FileTest.decode, path, chunk, limit)
    case False{}:
      do IO<Result<&2, &2, Load.Error<String>, System.Report>>:
        environment : Result<&2, &2, Environment.Error, Environment.Values> <- Environment.capture()
        System.capturedWith(~String, ~FileTest.decode, ~HostTest.Source, ~HostTest.lookup, HostTest.Source{String.eq(mode, "fail"), name}, path, chunk, limit, captureResult(String.eq(mode, "env-fail"), environment))

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> path <> chunk <> limit <> name <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &2, Load.Error<String>, System.Report> <- run(String.eq(mode, "system"), mode, path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), name)
        report(result)
    case _: IO.die(Unit, 1, "expected mode path chunk limit hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
