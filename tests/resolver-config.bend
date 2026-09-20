import Base
import ../packages/runtime/src/resolver-config.bend as Config
import ./resolver-address.bend as AddressTest

def fields(values: List<&2, String>, result: String) -> String:
  match values:
    case Nil{}: result
    case +item <> rest: fields(rest, result ++ Nat.show(String.length(item)) ++ ":" ++ item)

def shown(value: Config.Entry) -> String:
  match value:
    case Config.Nameserver{token, parsed}: "server:" ++ fields(token <> Nil{}, "") ++ ":" ++ AddressTest.show(parsed)
    case Config.Domain{value}: "domain:" ++ fields(value <> Nil{}, "")
    case Config.Search{values}: "search:" ++ fields(values, "")
    case Config.Options{values}: "options:" ++ fields(values, "")
    case Config.Sortlist{values}: "sort:" ++ fields(values, "")
    case Config.Unknown{text}: "unknown:" ++ fields(text <> Nil{}, "")

def output(values: List<&2, Config.Entry>) -> IO(Unit):
  match values:
    case Nil{}: IO.print("END")
    case value <> rest:
      do IO<Unit>:
        IO.print(shown(value))
        output(rest)

def run(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        output(Config.parse(text))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
