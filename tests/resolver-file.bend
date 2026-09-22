import Base
import ../packages/runtime/src/resolver-config.bend as File
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/src/utf8.bend as UTF8
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./resolver-settings.bend as Output

# Test-selected replacement decoding preserves a leading BOM as source text.
def decode(bytes: List<&2, U32>) -> Result<&2, &2, String, String>:
  Done{UTF8.complete(UTF8.decode(UTF8.Decoder{UTF8.Ready{}, True{}}, bytes))}

def reject(bytes: List<&2, U32>) -> Result<&2, &2, String, String>:
  Fail{"selected decoder rejected input"}

def report(value: Result<&2, &2, File.FileError<String>, Settings.Settings>) -> IO(Unit):
  match value:
    case Done{settings}: Output.report(settings)
    case Fail{File.TooLarge{}}: IO.print("large")
    case Fail{File.Decode{error}}: IO.print("decode:" ++ error)
    case Fail{File.File{Fold.InvalidReadSize{}}}: IO.print("size")
    case Fail{File.File{Fold.Open{code, _}}}: IO.print("open:" ++ U32.show(code))
    case Fail{File.File{Fold.Read{code, _}}}: IO.print("read:" ++ U32.show(code))

def read(rejectInput: Bool, path: String, chunk: U32, limit: Nat, overrides: Settings.Overrides) -> IO(Result<&2, &2, File.FileError<String>, Settings.Settings>):
  match rejectInput:
    case False{}: File.loadWith(~String, ~decode, path, chunk, limit, overrides)
    case True{}: File.loadWith(~String, ~reject, path, chunk, limit, overrides)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> path <> chunk <> limit <> hostname <> present <> domains <> options <> Nil{}:
      do IO<Unit>:
        value : Result<&2, &2, File.FileError<String>, Settings.Settings> <- read(String.eq(mode, "reject"), path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), Settings.Overrides{Some{hostname}, Output.localDomains(String.eq(present, "yes"), domains), Config.words(options, Config.Words{"", Nil{}})})
        report(value)
    case _: IO.die(Unit, 1, "expected mode path chunk limit hostname override-presence domains options")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
