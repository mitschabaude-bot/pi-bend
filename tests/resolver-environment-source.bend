import Base
import ../packages/runtime/src/resolver-config.bend as Environment
import ./resolver-environment.bend as Output

def returned(missing: Bool, failed: Bool, empty: Bool, local: Bool) -> Result<&1, &1, U32 & String, String>:
  match missing failed empty:
    case True{} _ _: Fail{(2, "absent")}
    case False{} True{} _: Fail{(13, "lookup failed")}
    case False{} False{} True{}: Done{""}
    case False{} False{} False{}: Done{Bool.pick(String, local, "one two", "ndots:3")}

def lookupRepeated(+mode: String, +name: String) -> IO(Result<&1, &1, U32 & String, String>):
  +local = String.eq(name, "LOCALDOMAIN")
  do IO<Result<&1, &1, U32 & String, String>>:
    IO.print(name)
    return returned(String.eq(mode, "missing"), String.eq(mode, "both-fail") || (local && String.eq(mode, "local-fail")) || (Bool.not(local) && String.eq(mode, "options-fail")), String.eq(mode, "empty"), local)

def lookup(mode: String, name: String) -> IO(Result<&1, &1, U32 & String, String>):
  lookupRepeated(mode, name)

def args(values: List<String>) -> IO(Unit):
  match values:
    case mode <> Nil{}:
      do IO<Unit>:
        result : Result<&2, &2, Environment.EnvironmentError, Environment.Values> <- Environment.captureWith(~String, ~lookup, mode)
        Output.report("search file.test\noptions timeout:2", "host.default", result)
    case _: IO.die(Unit, 1, "expected mode")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
