import Base
import ../packages/runtime/src/dns-transport.bend as Rotation
import ../packages/runtime/src/dns-transport.bend as Source
import ../packages/runtime/test/utf8-runner.bend as Scalar
import ./dns-server-rotation.bend as Test
import ../packages/runtime/src/string-split.bend as Split

def selected(pair: Source.Owner<U32> & Source.ServerSourceSource<U32>) -> IO(Source.Owner<U32>):
  match pair:
    case (owner, source):
      do IO<Source.Owner<U32>>:
        values : List<&2, U32> <- Source.chooseServerSource(U32, source)
        IO.print(Test.csv(values, ""))
        return owner

def owned(flags: String, owner: Source.Owner<U32>) -> IO(Unit):
  match flags:
    case SNil{}: Source.close(U32, owner)
    case SCon{flag, rest}:
      do IO<Unit>:
        next : Source.Owner<U32> <- selected(Source.borrow(U32, Char.is_eq(flag, '1'), owner))
        owned(rest, next)

def args(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case servers <> offset <> +flags <> rest:
      +items = Test.numbers(Split.split(servers, ','), Nil{})
      +position = U32.to_nat(Scalar.decimal(offset, 0))
      do IO<Unit>:
        Test.run(flags, Rotation.startAt(U32, position, items))
        owner : Source.Owner<U32> <- Source.createAt(U32, position, items)
        owned(flags, owner)
        args(rest)
    case _: IO.die(Unit, 1, "expected server list, initial offset and flags")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
