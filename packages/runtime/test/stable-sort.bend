import Base
import ../src/stable-sort.bend as Sort
import ../src/string-split.bend as Split
import ./utf8-runner.bend as Text

type Item is Data:
  Item{key: U32, index: U32}

def before(left: Item, right: Item) -> Bool:
  match left right:
    case Item{a, _} Item{b, _}: U32.is_le(a, b)

def generated(fuel: Nat, seed: U32, +modulus: U32, +index: U32, reversed: List<&2, Item>) -> List<&2, Item>:
  match fuel:
    case Zero{}: List.reverse(&2, Item, reversed)
    case Succ{rest}:
      +next = (seed * 1664525 + 1013904223 : U32)
      generated(rest, next, modulus, (index + 1 : U32), Item{(next % modulus : U32), index} <> reversed)

def checksum(items: List<&2, Item>, count: U32, hash: U32) -> String:
  match items:
    case Nil{}: U32.show(count) ++ ";" ++ U32.show(hash)
    case Item{key, index} <> rest: checksum(rest, (count + 1 : U32), U32.xor((U32.xor((hash * 16777619 : U32), key) * 16777619 : U32), index))

def run(parts: List<&2, String>) -> String:
  match parts:
    case count <> seed <> modulus <> Nil{}: checksum(Sort.sort(~Item, ~before, generated(U32.to_nat(Text.decimal(count, 0)), Text.decimal(seed, 0), Text.decimal(modulus, 0), 0, Nil{})), 0, 2166136261)
    case _: "invalid-case"

def cases(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ';')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
