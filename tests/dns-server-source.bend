import Base
import ../packages/runtime/src/dns-server-source.bend as Source
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-server-rotation.bend as RotationTest

def launch(count: Nat, +source: Source.Source<U32>, reversed: List<&2, Chan(List<&2, U32>)>) -> IO(List<&2, Chan(List<&2, U32>)>):
  match count:
    case 0n: IO.pure(List<&2, Chan(List<&2, U32>)>, List.reverse(&2, Chan(List<&2, U32>), reversed))
    case 1n+rest:
      do IO<List<&2, Chan(List<&2, U32>)>>:
        task : Chan(List<&2, U32>) <- IO.fork(List<&2, U32>, Source.choose(U32, source))
        launch(rest, source, task <> reversed)

def joined(tasks: List<&2, Chan(List<&2, U32>)>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case task <> rest:
      do IO<Unit>:
        selected : List<&2, U32> <- IO.join(List<&2, U32>, task)
        IO.print(RotationTest.csv(selected, ""))
        joined(rest)

def run(count: Nat, pair: Source.Owner<U32> & Source.Source<U32>) -> IO(Unit):
  match pair:
    case (owner, +source):
      do IO<Unit>:
        tasks : List<&2, Chan(List<&2, U32>)> <- launch(count, source, Nil{})
        joined(tasks)
        final : List<&2, U32> <- Source.choose(U32, source)
        IO.print("next:" ++ RotationTest.csv(final, ""))
        Source.close(U32, owner)

def count(text: String, acc: Nat) -> Nat:
  match text:
    case SNil{}: acc
    case SCon{_, rest}: count(rest, 1n+acc)

def args(values: List<String>) -> IO(Unit):
  match values:
    case servers <> flags <> copies <> Nil{}:
      do IO<Unit>:
        owner : Source.Owner<U32> <- Source.create(U32, RotationTest.numbers(String.split(servers, ','), Nil{}))
        run(count(copies, 0n), Source.borrow(U32, String.eq(flags, "1"), owner))
    case _: IO.die(Unit, 1, "expected servers enabled and count-as-string")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
