import Base
import ../packages/runtime/src/resolver-config.bend as Settings
import ../packages/runtime/src/resolver-config.bend as Config
import ../packages/runtime/src/resolver-config.bend as Address
import ./resolver-address.bend as AddressTest
import ./resolver-config.bend as ConfigTest

def servers(values: List<&2, Address.Address>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(AddressTest.show(Done{value}))
        servers(rest)

def report(value: Settings.Settings) -> IO(Unit):
  match value:
    case Settings.Settings{addresses, search, options, sort, Settings.Diagnostics{invalid, unknown}}:
      do IO<Unit>:
        servers(addresses)
        IO.print("search:" ++ ConfigTest.fields(search, ""))
        IO.print("options:" ++ ConfigTest.fields(options, ""))
        IO.print("sort:" ++ ConfigTest.fields(sort, ""))
        IO.print("invalid:" ++ ConfigTest.fields(invalid, ""))
        IO.print("unknown:" ++ ConfigTest.fields(unknown, ""))

def localDomains(present: Bool, text: String) -> Maybe<&2, List<&2, String>>:
  match present:
    case False{}: None{}
    case True{}: Some{Config.words(text, Config.Words{"", Nil{}})}

def args(values: List<String>) -> IO(Unit):
  match values:
    case text <> hostname <> present <> domains <> options <> Nil{}:
      report(Settings.configure(Config.parse(text), Settings.Overrides{Some{hostname}, localDomains(String.eq(present, "yes"), domains), Config.words(options, Config.Words{"", Nil{}})}))
    case _: IO.die(Unit, 1, "expected configuration hostname override-presence domains options")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
