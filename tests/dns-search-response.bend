import Base
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-search-response.bend as Response
import ../packages/runtime/src/dns-presentation.bend as Presentation
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-search.bend as SearchTest

def cause(value: String) -> Response.Cause:
  match value:
    case SCon{'d', SNil{}}: Response.EmptyAnswer{}
    case SCon{'s', SNil{}}: Response.ServerFailure{}
    case SCon{'t', SNil{}}: Response.TemporaryFailure{}
    case SCon{'f', SNil{}}: Response.Unrecoverable{}
    case SCon{'r', SNil{}}: Response.ConnectionRefused{}
    case _: Response.Missing{}

def error(value: Response.Error) -> String:
  match value:
    case Response.NotFound{}: "1"
    case Response.TryAgain{}: "2"
    case Response.NoRecovery{}: "3"
    case Response.NoData{}: "4"

type Progress is Data:
  Run{script: List<&2, String>, decision: Response.Decision}
  Success{}

def applied(success: Bool, token: String, script: List<&2, String>, origin: Search.Origin, cursor: Search.Cursor, history: Response.History) -> Progress:
  match success:
    case True{}: Success{}
    case False{}: Run{script, Response.failed(origin, cause(token), cursor, history)}

def consume(script: List<&2, String>, origin: Search.Origin, cursor: Search.Cursor, history: Response.History) -> Progress:
  match script:
    case Nil{}: Run{Nil{}, Response.failed(origin, Response.Missing{}, cursor, history)}
    case +token <> rest: applied(String.eq(token, "a"), token, rest, origin, cursor, history)

def advanced(script: List<&2, String>, history: Response.History, step: Search.Step) -> IO(Progress):
  match step:
    case Search.Exhausted{}: IO.pure(Progress, Run{Nil{}, Response.Stop{Response.exhausted(history)}})
    case Search.Candidate{+from, value, next}:
      do IO<Progress>:
        IO.print(SearchTest.origin(from) ++ ":" ++ SearchTest.name(value))
        return consume(script, from, next, history)

# Finite fixture traces; production policy itself is pure and nonrecursive.
def drive(fuel: Nat, progress: Progress) -> IO(Unit):
  match fuel progress:
    case _ Success{}: IO.print("ok")
    case _ Run{_, Response.Stop{why}}: IO.print("error:" ++ error(why))
    case Zero{} _: IO.die(Unit, 1, "fixture fuel exhausted")
    case Succ{rest} Run{script, Response.Continue{cursor, history}}:
      do IO<Unit>:
        next : Progress <- advanced(script, history, Search.next(cursor))
        drive(rest, next)

def argument(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case text <> dots <> absolute <> ndots <> defnames <> search <> notld <> suffixes <> script <> Nil{}:
      drive(100n, Run{Split.split(script, ','), Response.Continue{Search.start(SearchTest.parsed(Presentation.parse(text)), Scalar.decimal(dots, 0), String.eq(absolute, "1"), SearchTest.domainInput(suffixes), Search.Policy{Scalar.decimal(ndots, 0), String.eq(defnames, "1"), String.eq(search, "1"), String.eq(notld, "1")}), Response.new()}})
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
