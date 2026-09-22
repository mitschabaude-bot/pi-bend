import Base

# A constant generic tree: does it reach the static image or is it built at
# runtime by the program's entry?
type Tree<-V: Data> is Data:
  Empty{}
  Branch{key: U32, value: V, left: Tree<V>, right: Tree<V>}

type Entry is Data:
  Entry{point: U32, name: String}

def table() -> Tree<Entry>:
  Branch{50, Entry{50, "fifty"},
    Branch{25, Entry{25, "twenty-five"}, Branch{10, Entry{10, "ten"}, Empty{}, Empty{}}, Empty{}},
    Branch{75, Entry{75, "seventy-five"}, Empty{}, Branch{90, Entry{90, "ninety"}, Empty{}, Empty{}}}}

def lookup(-V: Data, tree: Tree<V>, +key: U32) -> Maybe<&2, V>:
  match tree:
    case Empty{}: None{}
    case Branch{+stored, value, left, right}:
      Bool.pick(Maybe<&2, V>, U32.is_eq(key, stored), Some{value}, Bool.pick(Maybe<&2, V>, U32.is_lt(key, stored), lookup(V, left, key), lookup(V, right, key)))

def name(found: Maybe<&2, Entry>) -> String:
  match found:
    case None{}: "?"
    case Some{Entry{_, text}}: text

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(name(lookup(Entry, table(), 75)))
    IO.print(name(lookup(Entry, table(), 11)))
