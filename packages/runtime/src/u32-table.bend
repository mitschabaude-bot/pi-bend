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

# Find the value belonging to the greatest key <= the query. Range tables use
# this with an explicit upper bound in the returned value.
type FloorSearch<-V: Data> is Data:
  FloorFound{value: Maybe<&2, V>}
  FloorNext{tree: Tree<V>, best: Maybe<&2, V>}

def floorSelected(-V: Data, left: Tree<V>, right: Tree<V>, value: V, best: Maybe<&2, V>, less: Bool, equal: Bool) -> FloorSearch<V>:
  match less equal:
    case True{} _: FloorNext{left, best}
    case False{} True{}: FloorFound{Some{value}}
    case False{} False{}: FloorNext{right, Some{value}}

def floorStep(-V: Data, tree: Tree<V>, best: Maybe<&2, V>, +key: U32) -> FloorSearch<V>:
  match tree:
    case Empty{}: FloorFound{best}
    case Branch{+stored, value, left, right}: floorSelected(V, left, right, value, best, U32.is_lt(key, stored), U32.is_eq(key, stored))

def floorSearch(-V: Data, fuel: Nat, +key: U32, state: FloorSearch<V>) -> Maybe<&2, V>:
  match fuel state:
    case _ FloorFound{value}: value
    case Zero{} FloorNext{_, best}: best
    case Succ{rest} FloorNext{tree, best}: floorSearch(V, rest, key, floorStep(V, tree, best, key))

def floor(-V: Data, table: Table<V>, key: U32) -> Maybe<&2, V>:
  match table:
    case Table{height, root}: floorSearch(V, Succ{height}, key, FloorNext{root, None{}})

# Construct a balanced immutable table in linear time. Entries must be strictly
# increasing by key (no duplicates); callers establish this before construction.
type Entry<-V: Data> is Data:
  Entry{key: U32,value: V}

type Built<-V: Data> is Data:
  Built{tree: Tree<V>,rest: List<&2,Entry<V>>,height: Nat}

def countEntries(-V: Data,entries: List<&2,Entry<V>>,count: Nat) -> Nat:
  match entries:
    case Nil{}: count
    case _ <> rest: countEntries(V,rest,Succ{count})

def remaining(-V: Data,built: Built<V>) -> List<&2,Entry<V>>:
  match built:
    case Built{_,rest,_}: rest

def branch(-V: Data,key: Maybe<&2,Entry<V>>,left: Built<V>,right: Built<V>) -> Built<V>:
  match key left right:
    case Some{Entry{index,value}} Built{left,_,leftHeight} Built{right,rest,rightHeight}: Built{Branch{index,value,left,right},rest,Succ{Nat.max(leftHeight,rightHeight)}}
    case None{} left _: left

def rootEntry(-V: Data,entries: List<&2,Entry<V>>) -> Maybe<&2,Entry<V>>:
  match entries:
    case head <> _: Some{head}
    case Nil{}: None{}

# The internal count always equals a prefix length, so rootEntry is total on
# every construction path. Each recursive call receives at most half the rows.
def buildSorted(-V: Data,fuel: Nat,count: Nat,entries: List<&2,Entry<V>>) -> Built<V>:
  match fuel count:
    case _ Zero{}: Built{Empty{},entries,Zero{}}
    case Zero{} _: Built{Empty{},entries,Zero{}}
    case Succ{+fuel} Succ{+rest}:
      +half = rest / 2n
      +left = buildSorted(V,fuel,half,entries)
      +tail = remaining(V,left)
      branch(V,rootEntry(V,tail),left,buildSorted(V,fuel,rest - half,List.drop(&2,Entry<V>,tail,1n)))

def builtTable(-V: Data,built: Built<V>) -> Table<V>:
  match built:
    case Built{tree,_,height}: Table{height,tree}

def fromSortedEntries(-V: Data,+entries: List<&2,Entry<V>>) -> Table<V>:
  +count = countEntries(V,entries,Zero{})
  builtTable(V,buildSorted(V,count,count,entries))

# Replace an existing value without changing keys, balance or height. Missing
# keys leave the table unchanged; construction owns the key-set invariant.
def replaceTree(-V: Data,fuel: Nat,tree: Tree<V>,+key: U32,+value: V) -> Tree<V>:
  match fuel tree:
    case _ Empty{}: Empty{}
    case Zero{} tree: tree
    case Succ{+fuel} Branch{+stored,+old,+left,+right}:
      Bool.pick(Unit -> Tree<V>,U32.is_lt(key,stored),
        _ => Branch{stored,old,replaceTree(V,fuel,left,key,value),right},
        _ => Bool.pick(Unit -> Tree<V>,U32.is_eq(key,stored),_ => Branch{stored,value,left,right},_ => Branch{stored,old,left,replaceTree(V,fuel,right,key,value)})(Unit{}))(Unit{})

def replace(-V: Data,table: Table<V>,key: U32,value: V) -> Table<V>:
  match table:
    case Table{+height,root}: Table{height,replaceTree(V,height,root,key,value)}
