import Base
type Descriptor<-A: Data> is Data:
  DataProperty{value: A, writable: Bool}
  AccessorProperty{get: Maybe<&2, A>, set: Maybe<&2, A>, enumerable: Bool}
type Entry<-A: Data> is Data:
  Entry{key: String, descriptor: Descriptor<A>}
def check(values: List<&2, Entry<U32>>) -> IO(Unit):
  match values:
    case Entry{"a", AccessorProperty{Some{7}, None{}, True{}}} <> Nil{}: IO.print("PASS converted literal layout")
    case _: IO.die(Unit, 1, "wrong literal layout")
def main() -> IO(Unit):
  check(Entry{"a", AccessorProperty{Some{7}, None{}, True{}}} <> Nil{})
