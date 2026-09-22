import Base
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-search.bend as SearchTest
import ./dns-search-response.bend as ResponseTest

type Source is Data:
  Source{remaining: List<&2, String>, calls: U32}

def take(state: Source) -> Source & String:
  match state:
    case Source{Nil{}, count}: (Source{Nil{}, (count + 1 : U32)}, "n")
    case Source{token <> rest, count}: (Source{rest, (count + 1 : U32)}, token)

def outcome(token: String) -> Run.Outcome<String, String>:
  match token:
    case SCon{'a', SNil{}}: Run.Answer{"exact answer payload"}
    case SCon{'h', rest}: Run.SearchHalt{rest}
    case other: Run.SearchRunFailed{ResponseTest.cause(other)}

def request(source: Ref.Ref<Source>, request: Run.SearchRunRequest) -> IO(Run.Outcome<String, String>):
  match request:
    case Run.SearchRunRequest{origin, name}:
      do IO<Run.Outcome<String, String>>:
        IO.print(SearchTest.origin(origin) ++ ":" ++ SearchTest.name(Done{name}))
        token : String <- Ref.modify(Source, String, source, state => take(state))
        # Exercise real async suspension before the driver resumes.
        IO.sleep(1)
        return outcome(token)

def report(value: Result<&2, &2, Run.SearchRunError<String>, String>) -> IO(Unit):
  match value:
    case Done{value}: IO.print("ok:" ++ value)
    case Fail{Run.Halted{failure}}: IO.print("halt:" ++ failure)
    case Fail{Run.NoAnswer{error}}: IO.print("error:" ++ ResponseTest.error(error))

def retired(state: Source) -> IO(Unit):
  match state:
    case Source{_, count}: IO.print("calls:" ++ U32.show(count))

def argument(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case text <> dots <> absolute <> ndots <> defnames <> search <> notld <> suffixes <> script <> Nil{}:
      do IO<Unit>:
        +source : Ref.Ref<Source> <- Ref.new(Source, Source{Split.split(script, ','), 0})
        result : Result<&2, &2, Run.SearchRunError<String>, String> <- Run.runSearchRun(~Ref.Ref<Source>, ~String, ~String, ~request, source, Search.start(SearchTest.parsed(Presentation.parsePresentation(text)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), SearchTest.domainInput(suffixes), Search.Policy{Scalar.decimal(ndots, 0), String.eq(defnames, "1"), String.eq(search, "1"), String.eq(notld, "1")}))
        report(result)
        state : Source <- Ref.dispose(Source, source)
        retired(state)
    case _: IO.die(Unit, 1, "invalid fixture arguments")

def all(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        argument(Split.split(text, ';'))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    all(args)
