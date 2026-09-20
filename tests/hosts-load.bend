import Base
import ../packages/runtime/src/utf8-strict.bend as Strict
import ./utf8-strict.bend as StrictTest
import ../packages/runtime/src/hosts-load.bend as Load
import ../packages/runtime/src/hosts-file.bend as Parser
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/bounded-file.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./hosts-file.bend as Output
import ./resolver-file.bend as Decoder

def report(~DecodeError: Data, ~showError: DecodeError -> String, name: String, value: Result<&2, &2, Load.Error<DecodeError>, List<&2, Hosts.Entry<Parser.Address>>>) -> IO(Unit):
  match value:
    case Done{entries}: IO.print(Output.report(name, Done{entries}))
    case Fail{Load.Parsing{error}}: IO.print(Output.report(name, Fail{error}))
    case Fail{Load.Loading{File.TooLarge{}}}: IO.print("large")
    case Fail{Load.Loading{File.Decode{error}}}: IO.print("decode:" ++ showError(error))
    case Fail{Load.Loading{File.File{Fold.InvalidReadSize{}}}}: IO.print("size")
    case Fail{Load.Loading{File.File{Fold.Open{code, _}}}}: IO.print("open:" ++ U32.show(code))
    case Fail{Load.Loading{File.File{Fold.Read{code, _}}}}: IO.print("read:" ++ U32.show(code))

def read(reject: Bool, path: String, chunk: U32, limit: Nat) -> IO(Result<&2, &2, Load.Error<String>, List<&2, Hosts.Entry<Parser.Address>>>):
  match reject:
    case True{}: Load.readWith(~String, ~Decoder.reject, path, chunk, limit)
    case False{}: Load.readWith(~String, ~Decoder.decode, path, chunk, limit)

def unchanged(value: String) -> String: value

def run(strict: Bool, reject: Bool, path: String, chunk: U32, limit: Nat, name: String) -> IO(Unit):
  match strict:
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, Load.Error<Strict.Error>, List<&2, Hosts.Entry<Parser.Address>>> <- Load.read(path, chunk, limit)
        report(~Strict.Error, ~StrictTest.error, name, result)
    case False{}:
      do IO<Unit>:
        result : Result<&2, &2, Load.Error<String>, List<&2, Hosts.Entry<Parser.Address>>> <- read(reject, path, chunk, limit)
        report(~String, ~unchanged, name, result)

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> path <> chunk <> limit <> name <> Nil{}: run(String.eq(mode, "strict"), String.eq(mode, "reject"), path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)), name)
    case _: IO.die(Unit, 1, "expected mode path chunk limit name")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
