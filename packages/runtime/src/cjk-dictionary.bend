import Base
import ./u32-table.bend as Table

# ICU78 weighted CJK dictionary. The compact postorder asset is decoded once;
# the resulting radix tree is immutable and shareable between segmentation calls.
type Trie is Data: Trie{tail: String,cost: U32,edges: Table.Table<Trie>}
type Error is Data: InvalidDictionary{}
def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
type Label is Data: Label{text: String,bytes: List<&2,U32>}
type Building is Data: Building{bytes: List<&2,U32>,stack: List<&2,Trie>}
type Children is Data: Children{bytes: List<&2,U32>,stack: List<&2,Trie>,entries: List<&2,Table.Entry<Trie>>}
type Match is Data: Match{length: Nat,cost: U32}

# Decoding matches on validity flags directly: a lazy `Bool.pick` would
# allocate two closures per character of a 2.2 MB asset at startup. `label`
# checks each character at the following step; an invalid one is stored as a
# placeholder and never returned.
def label(count: Nat,valid: Bool,bytes: List<&2,U32>,reversed: String) -> Parsed(Label):
  match count valid bytes:
    case _ False{} _: Fail{InvalidDictionary{}}
    case Zero{} True{} bytes: Done{Label{String.reverse(reversed),bytes}}
    case Succ{left} True{} +lo <> +hi <> rest:
      +code = (lo + 256 * hi: U32)
      +ok = U32.is_le(lo,255) && U32.is_le(hi,255) && Bool.not(U32.is_ge(code,55296) && U32.is_le(code,57343))
      label(left,ok,rest,SCon{Chr{Bool.pick(U32,ok,code,32)},reversed})
    case _ _ _: Fail{InvalidDictionary{}}
def attach(parsed: Parsed(Label),stack: List<&2,Trie>,+previous: U32,entries: List<&2,Table.Entry<Trie>>) -> Parsed(Children):
  match parsed stack:
    case Done{Label{SCon{Chr{+code},tail},bytes}} Trie{_,cost,edges} <> rest:
      Bool.pick(Parsed(Children),U32.is_lt(code,previous),Done{Children{bytes,rest,Table.Entry{code,Trie{tail,cost,edges}} <> entries}},Fail{InvalidDictionary{}})
    case _ _: Fail{InvalidDictionary{}}
def firstKey(entries: List<&2,Table.Entry<Trie>>) -> U32:
  match entries:
    case Nil{}: 65536
    case Table.Entry{key,_} <> _: key
def child(valid: Bool,length: U32,bytes: List<&2,U32>,stack: List<&2,Trie>,+entries: List<&2,Table.Entry<Trie>>) -> Parsed(Children):
  match valid:
    case True{}: attach(label(U32.to_nat(length),True{},bytes,""),stack,firstKey(entries),entries)
    case False{}: Fail{InvalidDictionary{}}
def children(count: Nat,result: Parsed(Children)) -> Parsed(Children):
  match count result:
    case _ Fail{error}: Fail{error}
    case Zero{} result: result
    case Succ{left} Done{Children{+length <> bytes,stack,entries}}:
      children(left,child(U32.is_ge(length,1) && U32.is_le(length,20),length,bytes,stack,entries))
    case _ _: Fail{InvalidDictionary{}}
def built(cost: U32,result: Parsed(Children)) -> Parsed(Building):
  match result:
    case Done{Children{bytes,stack,entries}}: Done{Building{bytes,Trie{"",cost,Table.fromSortedEntries(Trie,entries)} <> stack}}
    case Fail{error}: Fail{error}
def recordNode(valid: Bool,cost: U32,count: U32,bytes: List<&2,U32>,stack: List<&2,Trie>) -> Parsed(Building):
  match valid:
    case True{}: built(cost,children(U32.to_nat(count),Done{Children{bytes,stack,Nil{}}}))
    case False{}: Fail{InvalidDictionary{}}
def record(state: Building) -> Parsed(Building):
  match state:
    case Building{+cost <> +lo <> +hi <> bytes,stack}: recordNode(U32.is_le(cost,255) && U32.is_le(lo,255) && U32.is_le(hi,255),cost,(lo + hi * 256: U32),bytes,stack)
    case _: Fail{InvalidDictionary{}}
def records(count: Nat,result: Parsed(Building)) -> Parsed(Trie):
  match count result:
    case _ Fail{error}: Fail{error}
    case Zero{} Done{Building{Nil{},node <> Nil{}}}: Done{node}
    case Succ{left} Done{state}: records(left,record(state))
    case _ _: Fail{InvalidDictionary{}}
def decode(bytes: List<&2,U32>) -> Parsed(Trie):
  match bytes:
    case 73 <> 67 <> 85 <> 67 <> 74 <> 75 <> 48 <> 49 <> 207 <> 10 <> 5 <> 0 <> 60 <> 210 <> 4 <> 0 <> rest:
      records(330447n,Done{Building{rest,Nil{}}})
    case _: Fail{InvalidDictionary{}}

type Consumed is Data: Consumed{rest: String,length: Nat}
type Walk is Data: Walk{node: Trie,consumed: Consumed}
def consume(label: String,text: String,length: Nat) -> Maybe<&2,Consumed>:
  match label text:
    case SNil{} text: Some{Consumed{text,length}}
    case SCon{a,+left} SCon{b,+right}:
      Bool.pick(Unit -> Maybe<&2,Consumed>,Char.is_eq(a,b),_ => consume(left,right,Succ{length}),_ => None{})(Unit{})
    case _ _: None{}
def edge(text: String,edges: Table.Table<Trie>) -> Maybe<&2,Trie>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{code},_}: Table.get(Trie,edges,code)
def paired(node: Trie,result: Maybe<&2,Consumed>) -> Maybe<&2,Walk>:
  match result:
    case Some{consumed}: Some{Walk{node,consumed}}
    case None{}: None{}
def step(text: String,next: Maybe<&2,Trie>,length: Nat) -> Maybe<&2,Walk>:
  match text next:
    case SCon{_,rest} Some{Trie{tail,cost,edges}}: paired(Trie{"",cost,edges},consume(tail,rest,Succ{length}))
    case _ _: None{}
def matches(fuel: Nat,state: Maybe<&2,Walk>,+reversed: List<&2,Match>) -> List<&2,Match>:
  match fuel state:
    case Succ{left} Some{Walk{Trie{_,+cost,edges},Consumed{+text,+length}}}:
      +reversed = Bool.pick(List<&2,Match>,U32.is_lt(cost,255),Match{length,cost} <> reversed,reversed)
      Bool.pick(Unit -> List<&2,Match>,Nat.is_le(length,20n),
        _ => matches(left,step(text,edge(text,edges),length),reversed),_ => List.reverse(&2,Match,reversed))(Unit{})
    case _ _: List.reverse(&2,Match,reversed)
def prefixes(dictionary: Trie,text: String) -> List<&2,Match>:
  matches(21n,Some{Walk{dictionary,Consumed{text,0n}}},Nil{})
