import Base
import ../packages/runtime/src/dns-server-initialize.bend as Initialize
import ../packages/runtime/src/dns-server-source.bend as Source
import ../packages/runtime/src/random-index.bend as Index
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/string-split.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-server-rotation.bend as RotationTest
import ./dns-server-position.bend as PositionTest
import ./random-index.bend as IndexTest

type State is Data:
  State{calls: U32, words: List<&2, Result<&2, &2, Index.Error, U32>>}

def advance(state: State) -> State & Result<&2, &2, Index.Error, U32>:
  match state:
    case State{calls, Nil{}}: (State{(calls+1:U32), Nil{}}, Fail{Index.SourceFailure{99, "exhausted"}})
    case State{calls, first <> rest}: (State{(calls+1:U32), rest}, first)

def draw(source: Ref.Ref<State>) -> IO(Result<&2, &2, Index.Error, U32>):
  Ref.modify(State, Result<&2, &2, Index.Error, U32>, source, advance)

def word(text: String, failure: Bool) -> Result<&2, &2, Index.Error, U32>:
  match failure:
    case True{}: Fail{Index.SourceFailure{11, "unavailable"}}
    case False{}: Done{Scalar.decimal(text, 0)}

def words(parts: List<&2, String>, reversed: List<&2, Result<&2, &2, Index.Error, U32>>) -> List<&2, Result<&2, &2, Index.Error, U32>>:
  match parts:
    case Nil{}: List.reverse(&2, Result<&2, &2, Index.Error, U32>, reversed)
    case SNil{} <> rest: words(rest, reversed)
    case +text <> rest: words(rest, word(text, String.eq(text, "error")) <> reversed)

def finish(result: Result<&2, &1, Index.Error, Source.Owner<U32>>) -> IO(Unit):
  match result:
    case Fail{Index.SourceFailure{code, message}}: IO.print("error:" ++ U32.show(code) ++ ":" ++ message)
    case Fail{Index.InvalidBound{}}: IO.print("bound")
    case Fail{Index.InvalidBytes{}}: IO.print("bytes")
    case Done{owner}: PositionTest.owned("01111", owner)

def execute(real: Bool, source: Ref.Ref<State>, servers: List<&2, U32>) -> IO(Result<&2, &1, Index.Error, Source.Owner<U32>>):
  match real:
    case True{}: Initialize.random(U32, servers)
    case False{}: Initialize.createWith(~Ref.Ref<State>, ~draw, U32, source, servers)

def rendered(result: Result<&2, &2, Index.Error, Nat>) -> String:
  match result:
    case Done{value}: Nat.show(value)
    case Fail{Index.InvalidBound{}}: "bound"
    case Fail{Index.InvalidBytes{}}: "bytes"
    case Fail{Index.SourceFailure{code, message}}: "error:" ++ U32.show(code) ++ ":" ++ message

def run(indexOnly: Bool, mode: String, source: Ref.Ref<State>, text: String) -> IO(Unit):
  match indexOnly:
    case True{}:
      do IO<Unit>:
        result : Result<&2, &2, Index.Error, Nat> <- Index.sampleWith(~Ref.Ref<State>, ~draw, source, IndexTest.bound(text))
        IO.print(rendered(result))
    case False{}:
      do IO<Unit>:
        result : Result<&2, &1, Index.Error, Source.Owner<U32>> <- execute(String.eq(mode, "os"), source, RotationTest.numbers(Split.split(text, ','), Nil{}))
        finish(result)

def count(state: State) -> U32:
  match state:
    case State{calls, _}: calls

def args(values: List<String>) -> IO(Unit):
  match values:
    case +mode <> servers <> samples <> Nil{}:
      do IO<Unit>:
        +source : Ref.Ref<State> <- Ref.new(State, State{0, words(Split.split(samples, ','), Nil{})})
        run(String.eq(mode, "index"), mode, source, servers)
        retired : State <- Ref.dispose(State, source)
        IO.print("draws:" ++ U32.show(count(retired)))
    case _: IO.die(Unit, 1, "expected mode, servers and source words")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
