import Base
import ../packages/runtime/src/hosts-load.bend as Load
import ../packages/runtime/src/hosts-file.bend as Parser
import ../packages/runtime/src/hosts.bend as Hosts
import ../packages/runtime/src/bounded-file.bend as File
import ../packages/runtime/src/file-fold.bend as Fold
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./hosts-file.bend as Output
import ./resolver-file.bend as Decoder

def report(name: String, value: Result<&2, &2, Load.Error<String>, List<&2, Hosts.Entry<Parser.Address>>>) -> IO(Unit):
  match value:
    case Done{entries}: IO.print(Output.report(name, Done{entries}))
    case Fail{Load.Parsing{error}}: IO.print(Output.report(name, Fail{error}))
    case Fail{Load.Loading{File.TooLarge{}}}: IO.print("large")
    case Fail{Load.Loading{File.Decode{error}}}: IO.print("decode:" ++ error)
    case Fail{Load.Loading{File.File{Fold.InvalidReadSize{}}}}: IO.print("size")
    case Fail{Load.Loading{File.File{Fold.Open{code, _}}}}: IO.print("open:" ++ U32.show(code))
    case Fail{Load.Loading{File.File{Fold.Read{code, _}}}}: IO.print("read:" ++ U32.show(code))

def read(reject: Bool, path: String, chunk: U32, limit: Nat) -> IO(Result<&2, &2, Load.Error<String>, List<&2, Hosts.Entry<Parser.Address>>>):
  match reject:
    case True{}: Load.readWith(~String, ~Decoder.reject, path, chunk, limit)
    case False{}: Load.readWith(~String, ~Decoder.decode, path, chunk, limit)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> path <> chunk <> limit <> name <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &2, Load.Error<String>, List<&2, Hosts.Entry<Parser.Address>>> <- read(String.eq(mode, "reject"), path, Scalar.decimal(chunk, 0), U32.to_nat(Scalar.decimal(limit, 0)))
        report(name, result)
    case _: IO.die(Unit, 1, "expected mode path chunk limit name")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
