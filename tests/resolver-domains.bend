import Base
import ../packages/runtime/src/resolver-config.bend as Domains
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Run
import ../packages/runtime/src/dns-message.bend as Response
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-search.bend as SearchTest
import ./dns-search-run.bend as RunTest

def error(value: Presentation.PresentationError) -> String:
  match value:
    case Presentation.PresentationInvalidByte{}: "byte"
    case Presentation.RawNul{}: "nul"
    case Presentation.EmptyLabel{}: "empty"
    case Presentation.LabelTooLong{}: "label"
    case Presentation.PresentationNameTooLong{}: "name"
    case Presentation.InvalidEscape{}: "escape"

def issues(values: List<&2, Domains.Issue>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case Domains.Issue{position, text, failure} <> rest:
      do IO<Unit>:
        IO.print("issue:" ++ Nat.show(position) ++ ":" ++ error(failure) ++ ":" ++ text)
        issues(rest)

def request(unused: Unit, value: Run.SearchRunRequest) -> IO(Run.Outcome<String, String>):
  match value:
    case Run.SearchRunRequest{origin, name}:
      do IO<Run.Outcome<String, String>>:
        IO.print("query:" ++ SearchTest.origin(origin) ++ ":" ++ SearchTest.name(Done{name}))
        IO.sleep(1)
        return Run.SearchRunFailed{Response.Missing{}}

def prepared(base: Name.Name, dots: U32, absolute: Bool, ndots: U32, notld: Bool, report: Domains.Report) -> IO(Unit):
  match report:
    case Domains.Report{domains, failures}:
      +cursor = Search.startDomains(base, dots, absolute, domains, Search.Policy{ndots, True{}, True{}, notld})
      do IO<Unit>:
        issues(failures)
        SearchTest.drain(10000n, 4294967295, 0, Search.next(cursor))
        result : Result<&2, &2, Run.SearchRunError<String>, String> <- Run.runSearch(~Unit, ~String, ~String, ~request, Unit{}, cursor)
        RunTest.report(result)

def texts(values: List<String>, reversed: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: List.reverse(&2, String, reversed)
    case text <> rest: texts(rest, text <> reversed)

def args(values: List<String>) -> IO(Unit):
  match values:
    case text <> dots <> absolute <> ndots <> notld <> domains:
      prepared(SearchTest.parsed(Presentation.parsePresentation(text)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), Scalar.decimal(ndots, 0), String.eq(notld, "1"), Domains.prepareDomains(texts(domains, Nil{})))
    case _: IO.die(Unit, 1, "expected base dots absolute ndots notld [domains ...]")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
