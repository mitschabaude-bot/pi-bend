import Base

# Immutable balanced search data. Generated tables carry their checked height;
# each branch stores one unique key and partitions its children by key.
type Tree<-V: Data> is Data:
  Empty{}
  Branch{key: U32, value: V, left: Tree<V>, right: Tree<V>}

type Table<-V: Data> is Data:
  Table{height: Nat, root: Tree<V>}

type Search<-V: Data> is Data:
  Found{value: Maybe<&2, V>}
  Next{tree: Tree<V>}

def selected(-V: Data, left: Tree<V>, right: Tree<V>, value: V, less: Bool, equal: Bool) -> Search<V>:
  match less equal:
    case True{} _: Next{left}
    case False{} True{}: Found{Some{value}}
    case False{} False{}: Next{right}

def step(-V: Data, tree: Tree<V>, +key: U32) -> Search<V>:
  match tree:
    case Empty{}: Found{None{}}
    case Branch{+stored, value, left, right}: selected(V, left, right, value, U32.is_lt(key, stored), U32.is_eq(key, stored))

def search(-V: Data, fuel: Nat, +key: U32, state: Search<V>) -> Maybe<&2, V>:
  match fuel state:
    case _ Found{value}: value
    case Zero{} _: None{}
    case Succ{rest} Next{tree}: search(V, rest, key, step(V, tree, key))

def get(-V: Data, table: Table<V>, key: U32) -> Maybe<&2, V>:
  match table:
    case Table{height, root}: search(V, Succ{height}, key, Next{root})
