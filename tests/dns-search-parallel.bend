import Base
import ../packages/runtime/src/dns-search-parallel.bend as Parallel
import ../packages/runtime/src/dns-search-run.bend as Run
import ../packages/runtime/src/dns-search.bend as Search
import ../packages/runtime/src/dns-name.bend as Name
import ../packages/runtime/src/dns-search-response.bend as Response
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/string-split.bend as Split
import ./io-pair.bend as Gate
import ./dns-search-run.bend as Prior
import ./dns-search.bend as Show

type Environment is Data:
  Environment{leftReady: Chan(Unit), rightReady: Chan(Unit), turn: Chan(Unit), leftFirst: Bool, leftScript: Ref.Ref<Prior.Source>, rightScript: Ref.Ref<Prior.Source>, events: Ref.Ref<String>}

def callback(+isLeft: Bool, request: Run.Request, environment: Environment) -> IO(Run.Outcome<String, String>):
  match request environment:
    case Run.Request{origin, name} Environment{+leftReady, +rightReady, +turn, +leftFirst, leftScript, rightScript, events}:
      +first = Bool.pick(Bool, isLeft, leftFirst, Bool.not(leftFirst))
      label = Bool.pick(String, isLeft, "L:", "R:") ++ Show.origin(origin) ++ ":" ++ Show.name(Done{name}) ++ ";"
      do IO<Run.Outcome<String, String>>:
        token : String <- Ref.modify(Prior.Source, String, Bool.pick(Ref.Ref<Prior.Source>, isLeft, leftScript, rightScript), value => Prior.take(value))
        sent : Bool <- Chan.send(Unit, Bool.pick(Chan(Unit), isLeft, leftReady, rightReady), Unit{})
        Ref.requireSent(sent)
        Gate.wait(Bool.pick(Chan(Unit), isLeft, rightReady, leftReady))
        Gate.awaitTurn(first, turn)
        Ref.modify(String, Unit, events, previous => (previous ++ label, Unit{}))
        Gate.release(first, turn)
        return Prior.outcome(token)

def left(environment: Environment, request: Run.Request) -> IO(Run.Outcome<String, String>): callback(True{}, request, environment)
def right(environment: Environment, request: Run.Request) -> IO(Run.Outcome<String, String>): callback(False{}, request, environment)

# This fixture merge is deliberately simple; it tests scheduling/search
# ownership, not a production DNS two-response error-precedence policy.
def merge(left: Run.Outcome<String, String>, right: Run.Outcome<String, String>) -> Run.Outcome<String, String>:
  match left right:
    case Run.Halt{error} _: Run.Halt{"left:" ++ error}
    case _ Run.Halt{error}: Run.Halt{"right:" ++ error}
    case Run.Answer{a} Run.Answer{b}: Run.Answer{a ++ "+" ++ b}
    case Run.Answer{value} _: Run.Answer{value}
    case _ Run.Answer{value}: Run.Answer{value}
    case _ _: Run.Failed{Response.Missing{}}

def run(first: String, leftTokens: String, rightTokens: String) -> IO(Unit):
  do IO<Unit>:
    +leftReady : Chan(Unit) <- Chan.new(Unit, 1)
    +rightReady : Chan(Unit) <- Chan.new(Unit, 1)
    +turn : Chan(Unit) <- Chan.new(Unit, 1)
    +leftScript : Ref.Ref<Prior.Source> <- Ref.new(Prior.Source, Prior.Source{Split.split(leftTokens, ','), 0})
    +rightScript : Ref.Ref<Prior.Source> <- Ref.new(Prior.Source, Prior.Source{Split.split(rightTokens, ','), 0})
    +events : Ref.Ref<String> <- Ref.new(String, "")
    value : Result<&2, &2, Run.Error<String>, String> <- Parallel.run(~Environment, ~Run.Outcome<String, String>, ~Run.Outcome<String, String>, ~String, ~String, ~left, ~right, ~merge, Environment{leftReady, rightReady, turn, String.eq(first, "L"), leftScript, rightScript, events}, Search.start(Name.Name{(97 <> Nil{}) <> Nil{}}, 0, False{}, Show.domainInput("x|y"), Search.Policy{1, True{}, True{}, False{}}))
    Prior.report(value)
    log : String <- Ref.dispose(String, events)
    IO.print(log)
    leftState : Prior.Source <- Ref.dispose(Prior.Source, leftScript)
    rightState : Prior.Source <- Ref.dispose(Prior.Source, rightScript)
    Prior.retired(leftState)
    Prior.retired(rightState)
    Chan.close(Unit, leftReady)
    Chan.close(Unit, rightReady)
    Chan.close(Unit, turn)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> leftTokens <> rightTokens <> rest:
      do IO<Unit>:
        run(first, leftTokens, rightTokens)
        args(rest)
    case _: IO.die(Unit, 1, "expected completion-order/left-script/right-script triples")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
