import Base
import ../packages/runtime/src/dns-message.bend as Search
import ../packages/runtime/src/dns-message.bend as Name
import ../packages/runtime/src/dns-message.bend as Presentation
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-presentation.bend as NameTest

def parsed(value: Result<&2, &2, Presentation.PresentationError, Presentation.PresentationParsed>) -> Name.Name:
  match value:
    case Done{Presentation.PresentationParsed{name, _}}: name
    case Fail{_}: Name.Name{Nil{} <> Nil{}}

def domains(parts: List<&2, String>, reversed: List<&2, Name.Name>) -> List<&2, Name.Name>:
  match parts:
    case Nil{}: List.reverse(&2, Name.Name, reversed)
    case text <> rest: domains(rest, parsed(Presentation.parsePresentation(text)) <> reversed)

def domainInput(text: String) -> List<&2, Name.Name>:
  match text:
    case SNil{}: Nil{}
    case other: domains(Split.split(other, '|'), Nil{})

def origin(value: Search.Origin) -> String:
  match value:
    case Search.Initial{}: "initial"
    case Search.Final{}: "final"
    case Search.Suffix{index}: "suffix:" ++ Nat.show(index)

def name(value: Result<&2, &2, Name.NameErrorOfMessage, Name.Name>) -> String:
  match value:
    case Fail{_}: "invalid"
    case Done{value}: NameTest.wire(Name.encodeName(value))

def stopped(stop: Bool, cursor: Search.SearchCursor) -> Search.SearchCursor:
  match stop:
    case True{}: Search.stopSearch(cursor)
    case False{}: cursor

# Fuel is fixture-only; production cursor progress is its finite domain list
# plus at most two direct-name phases.
def drain(fuel: Nat, +stopAt: U32, +count: U32, step: Search.Step) -> IO(Unit):
  match fuel step:
    case _ Search.Exhausted{}: IO.print("END")
    case Zero{} _: IO.die(Unit, 1, "fixture fuel exhausted")
    case Succ{rest} Search.Candidate{from, value, next}:
      do IO<Unit>:
        IO.print(origin(from) ++ ":" ++ name(value))
        drain(rest, stopAt, (count + 1 : U32), Search.next(stopped(U32.is_eq(count, stopAt), next)))

def argument(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case text <> dots <> absolute <> ndots <> defnames <> search <> notld <> suffixes <> stop <> Nil{}:
      drain(10000n, Scalar.decimal(stop, 0), 0, Search.next(Search.start(parsed(Presentation.parsePresentation(text)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), domainInput(suffixes), Search.Policy{Scalar.decimal(ndots, 0), String.eq(defnames, "1"), String.eq(search, "1"), String.eq(notld, "1")})))
    case _: IO.die(Unit, 1, "invalid fixture arguments")

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        argument(Split.split(text, ';'))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
