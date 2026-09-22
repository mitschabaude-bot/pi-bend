import Base
import ../packages/runtime/src/resolver-config.bend as Hostname
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Environment
import ../packages/runtime/src/resolver-config.bend as Settings
import ./resolver-settings.bend as Output

type Source is Data:
  Source{fail: Bool, name: String}

def returned(fail: Bool, name: String) -> Result<&1, &1, U32 & String, String>:
  match fail:
    case True{}: Fail{(5, "hostname unavailable")}
    case False{}: Done{name}

def lookup(source: Source) -> IO(Result<&1, &1, U32 & String, String>):
  match source:
    case Source{fail, name}:
      do IO<Result<&1, &1, U32 & String, String>>:
        IO.print("called")
        return returned(fail, name)

def optional(present: Bool, name: String) -> Maybe<&2, String>:
  match present:
    case True{}: Some{name}
    case False{}: None{}

def environment(present: Bool, name: String) -> Environment.Values:
  Environment.Values{optional(present, name), None{}}

def diagnostic(value: Maybe<&2, Hostname.Failure>) -> String:
  match value:
    case None{}: "none"
    case Some{Hostname.Failure{code, message}}: "failure:" ++ U32.show(code) ++ ":" ++ message

def report(entries: List<&2, Config.Entry>, values: Environment.Values, result: Hostname.HostnameReport) -> IO(Unit):
  match result:
    case Hostname.HostnameReport{hostname, failure}:
      do IO<Unit>:
        Output.report(Settings.configure(entries, Environment.overrides(hostname, values)))
        IO.print(diagnostic(failure))

def args(args: List<String>) -> IO(Unit):
  match args:
    case text <> present <> local <> mode <> name <> Nil{}:
      +entries = Config.parse(text)
      +values = environment(String.eq(present, "yes"), local)
      do IO<Unit>:
        result : Hostname.HostnameReport <- Hostname.resolveWith(~Source, ~lookup, Source{String.eq(mode, "fail"), name}, entries, values)
        report(entries, values, result)
    case _: IO.die(Unit, 1, "expected config presence localdomain mode hostname")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
