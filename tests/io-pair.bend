import Base
import ../packages/runtime/src/io-pair.bend as Pair
import ../packages/runtime/src/ref.bend as Ref

# Affine payloads check that both can return owned values, not just Data.
type Owned is Type:
  Owned{label: String}

def present(value: Maybe<&1, Unit>) -> IO(Unit):
  match value:
    case Some{_}: IO.pure(Unit, Unit{})
    case None{}: IO.die(Unit, 1, "fixture gate closed")

def wait(gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&1, Unit> <- Chan.recv(Unit, gate)
    present(value)

def awaitTurn(first: Bool, gate: Chan(Unit)) -> IO(Unit):
  match first:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: wait(gate)

def release(first: Bool, gate: Chan(Unit)) -> IO(Unit):
  match first:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Unit, gate, Unit{})
        Ref.requireSent(sent)

def result(fail: Bool, code: U32, label: String) -> Result<&2, &1, U32, Owned>:
  match fail:
    case True{}: Fail{code}
    case False{}: Done{Owned{label}}

# Symmetric startup handshakes deadlock a sequential implementation. The turn
# gate fixes completion order without sleeps or scheduler timing assumptions.
def operation(+first: Bool, mine: Chan(Unit), peer: Chan(Unit), +turn: Chan(Unit), events: Ref.Ref<String>, +label: String, fail: Bool, code: U32) -> IO(Result<&2, &1, U32, Owned>):
  do IO<Result<&2, &1, U32, Owned>>:
    sent : Bool <- Chan.send(Unit, mine, Unit{})
    Ref.requireSent(sent)
    wait(peer)
    awaitTurn(first, turn)
    Ref.modify(String, Unit, events, previous => (previous ++ label, Unit{}))
    release(first, turn)
    return result(fail, code, label)

def show(value: Result<&2, &1, U32, Owned>) -> String:
  match value:
    case Fail{code}: "error:" ++ U32.show(code)
    case Done{Owned{label}}: "value:" ++ label

def report(pair: Result<&2, &1, U32, Owned> & Result<&2, &1, U32, Owned>) -> IO(Unit):
  match pair:
    case (left, right): IO.print(show(left) ++ "/" ++ show(right))

def run(+leftFirst: Bool, leftFail: Bool, rightFail: Bool) -> IO(Unit):
  do IO<Unit>:
    +leftReady : Chan(Unit) <- Chan.new(Unit, 1)
    +rightReady : Chan(Unit) <- Chan.new(Unit, 1)
    +turn : Chan(Unit) <- Chan.new(Unit, 1)
    +events : Ref.Ref<String> <- Ref.new(String, "")
    pair : Result<&2, &1, U32, Owned> & Result<&2, &1, U32, Owned> <- Pair.both(Result<&2, &1, U32, Owned>, Result<&2, &1, U32, Owned>, operation(leftFirst, leftReady, rightReady, turn, events, "L", leftFail, 41), operation(Bool.not(leftFirst), rightReady, leftReady, turn, events, "R", rightFail, 73))
    report(pair)
    log : String <- Ref.dispose(String, events)
    IO.print(log)
    Chan.close(Unit, leftReady)
    Chan.close(Unit, rightReady)
    Chan.close(Unit, turn)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> left <> right <> rest:
      do IO<Unit>:
        run(String.eq(first, "L"), String.eq(left, "fail"), String.eq(right, "fail"))
        args(rest)
    case _: IO.die(Unit, 1, "expected completion-order/left/right triples")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
