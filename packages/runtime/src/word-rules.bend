import Base
import ./u32-table.bend as Table

# Pinned ICU78 default word-rule automaton. Its 58 states have unconditional
# acceptance only: the source has no hard lookahead or synthetic BOF transition.
# The generator asserts those properties before emitting this versioned asset.
type State is Data: State{accept: Bool,status: U32,targets: Table.Table<U32>}
type Rules is Data: Rules{states: Table.Table<State>,properties: Table.Table<U32>}
type Error is Data: InvalidRules{}
def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
type Targets is Data: Targets{bytes: List<&2,U32>,entries: List<&2,Table.Entry<U32>>}
type States is Data: States{bytes: List<&2,U32>,entries: List<&2,Table.Entry<State>>}

def targets(count: Nat,+index: U32,bytes: List<&2,U32>,entries: List<&2,Table.Entry<U32>>) -> Parsed(Targets):
  match count bytes:
    case Zero{} bytes: Done{Targets{bytes,List.reverse(&2,Table.Entry<U32>,entries)}}
    case Succ{left} +value <> rest:
      Bool.pick(Unit -> Parsed(Targets),U32.is_lt(value,58),_ => targets(left,(index + 1: U32),rest,Table.Entry{index,value} <> entries),_ => Fail{InvalidRules{}})(Unit{})
    case _ _: Fail{InvalidRules{}}
def stateBuilt(index: U32,accept: U32,status: U32,entries: List<&2,Table.Entry<State>>,result: Parsed(Targets)) -> Parsed(States):
  match result:
    case Fail{error}: Fail{error}
    case Done{Targets{bytes,values}}: Done{States{bytes,Table.Entry{index,State{U32.is_eq(accept,1),status,Table.fromSortedEntries(U32,values)}} <> entries}}
def row(index: U32,value: States) -> Parsed(States):
  match value:
    case States{+accept <> +lo <> +hi <> bytes,entries}:
      +status = (lo + hi * 256: U32)
      Bool.pick(Unit -> Parsed(States),U32.is_le(accept,1) && U32.is_le(lo,255) && U32.is_le(hi,255) && (U32.is_eq(status,0) || U32.is_eq(status,100) || U32.is_eq(status,200) || U32.is_eq(status,400)),
        _ => stateBuilt(index,accept,status,entries,targets(31n,0,bytes,Nil{})),_ => Fail{InvalidRules{}})(Unit{})
    case _: Fail{InvalidRules{}}
def states(count: Nat,+index: U32,result: Parsed(States)) -> Parsed(States):
  match count result:
    case _ Fail{error}: Fail{error}
    case Zero{} Done{States{bytes,entries}}: Done{States{bytes,List.reverse(&2,Table.Entry<State>,entries)}}
    case Succ{left} Done{value}: states(left,(index + 1: U32),row(index,value))
def ordered(previous: Maybe<&2,U32>,code: U32) -> Bool:
  match previous:
    case None{}: U32.is_eq(code,0)
    case Some{old}: U32.is_lt(old,code)
def ranges(count: Nat,bytes: List<&2,U32>,previous: Maybe<&2,U32>,entries: List<&2,Table.Entry<U32>>) -> Parsed(Table.Table<U32>):
  match count bytes:
    case Zero{} Nil{}: Done{Table.fromSortedEntries(U32,List.reverse(&2,Table.Entry<U32>,entries))}
    case Succ{left} +a <> +b <> +c <> 0 <> +category <> +engine <> rest:
      +code = (a + b * 256 + c * 65536: U32)
      Bool.pick(Unit -> Parsed(Table.Table<U32>),U32.is_le(a,255) && U32.is_le(b,255) && U32.is_le(c,16) && U32.is_lt(category,31) && U32.is_lt(engine,8) && ordered(previous,code),
        _ => ranges(left,rest,Some{code},Table.Entry{code,(category + engine * 256: U32)} <> entries),_ => Fail{InvalidRules{}})(Unit{})
    case _ _: Fail{InvalidRules{}}
def combined(states: Table.Table<State>,result: Parsed(Table.Table<U32>)) -> Parsed(Rules):
  match result:
    case Fail{error}: Fail{error}
    case Done{properties}: Done{Rules{states,properties}}
def decoded(result: Parsed(States)) -> Parsed(Rules):
  match result:
    case Fail{error}: Fail{error}
    case Done{States{bytes,entries}}: combined(Table.fromSortedEntries(State,entries),ranges(2316n,bytes,None{},Nil{}))
def decode(bytes: List<&2,U32>) -> Parsed(Rules):
  match bytes:
    case 73 <> 67 <> 85 <> 87 <> 82 <> 68 <> 48 <> 49 <> 58 <> 0 <> 31 <> 0 <> 24 <> 0 <> 12 <> 9 <> rest:
      decoded(states(58n,0,Done{States{rest,Nil{}}}))
    case _: Fail{InvalidRules{}}

def properties(rules: Rules,char: Char) -> U32:
  match rules:
    case Rules{_,table}: Maybe.default(&2,U32,Table.floor(U32,table,Char.to_u32(char)),0)
def state(rules: Rules,index: U32) -> State:
  match rules:
    case Rules{table,_}: Maybe.default(&2,State,Table.get(State,table,index),State{False{},0,Table.Table{0n,Table.Empty{}}})
def target(value: State,category: U32) -> U32:
  match value:
    case State{_,_,transitions}: Maybe.default(&2,U32,Table.get(U32,transitions,category),0)

type Mark is Data: Mark{reversed: String,rest: String,length: Nat,status: U32,dictionary: Bool}
type Region is Data: Region{text: String,rest: String,length: Nat,status: U32,dictionary: Bool}
def accepted(value: State,reversed: String,rest: String,length: Nat,dictionary: Bool,best: Mark) -> Mark:
  match value:
    case State{accept,status,_}: Bool.pick(Mark,accept,Mark{reversed,rest,length,status,dictionary},best)
def region(value: Mark) -> Region:
  match value:
    case Mark{reversed,rest,length,status,dictionary}: Region{String.reverse(reversed),rest,length,status,dictionary}
def scan(text: String,+rules: Rules,+index: U32,+reversed: String,+length: Nat,+dictionary: Bool,best: Mark) -> Region:
  match text:
    case SNil{}: region(accepted(state(rules,target(state(rules,index),1)),reversed,"",length,dictionary,best))
    case SCon{+char,+rest}:
      +category = (properties(rules,char) % 256: U32)
      +next = target(state(rules,index),category)
      +best = accepted(state(rules,next),SCon{char,reversed},rest,Succ{length},dictionary || U32.is_ge(category,24),best)
      Bool.pick(Unit -> Region,U32.is_eq(next,0),_ => region(best),
        _ => scan(rest,rules,next,SCon{char,reversed},Succ{length},dictionary || U32.is_ge(category,24),best))(Unit{})
def next(rules: Rules,text: String) -> Maybe<&2,Region>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}: Some{scan(SCon{char,rest},rules,1,"",0n,False{},Mark{SCon{char,""},rest,1n,0,False{}})}
