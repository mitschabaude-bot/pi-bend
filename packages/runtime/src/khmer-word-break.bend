import Base
import ./cjk-dictionary.bend as Dictionary
import ./u32-table.bend as Table
import ./khmer-word-data.bend as Data

# ICU78 Khmer dictionary engine, with immutable three-word lookahead.
# Trie records share the native CJK radix representation, but Khmer matching
# has no CJK length/cost restriction and retains ICU's attempted-prefix count.
type Candidate is Data: Candidate{length: Nat,rest: String}
type Matches is Data: Matches{prefix: Nat,words: List<&2,Candidate>}
type Scan is Data:
  Finished{result: Matches}
  Walking{node: Dictionary.Trie,text: String,length: Nat,words: List<&2,Candidate>}
type Consumed is Data: Consumed{complete: Bool,text: String,length: Nat}
def consume(tail: String,text: String,length: Nat) -> Consumed:
  match tail text:
    case SNil{} text: Consumed{True{},text,length}
    case _ SNil{}: Consumed{False{},"",length}
    case SCon{a,+tail} SCon{b,+rest}:
      +length = {Succ{length}: Nat}
      Bool.pick(Unit -> Consumed,Char.is_eq(a,b),_ => consume(tail,rest,length),_ => Consumed{False{},rest,length})(Unit{})
def matched(node: Maybe<&2,Dictionary.Trie>,text: String,length: Nat,words: List<&2,Candidate>) -> Scan:
  match node:
    case None{}: Finished{Matches{length,words}}
    case Some{node}: Walking{node,text,length,words}
def edge(edges: Table.Table<Dictionary.Trie>,text: String,length: Nat,words: List<&2,Candidate>) -> Scan:
  match edges text:
    case Table.Table{_,Table.Empty{}} _: Finished{Matches{length,words}}
    case _ SNil{}: Finished{Matches{length,words}}
    case edges SCon{Chr{code},rest}: matched(Table.get(Dictionary.Trie,edges,code),rest,Succ{length},words)
def consumed(value: Consumed,+cost: U32,edges: Table.Table<Dictionary.Trie>,+words: List<&2,Candidate>) -> Scan:
  match value:
    case Consumed{False{},_,length}: Finished{Matches{length,words}}
    case Consumed{True{},+text,+length}:
      edge(edges,text,length,Bool.pick(List<&2,Candidate>,U32.is_eq(cost,0),Candidate{length,text} <> words,words))
def step(node: Dictionary.Trie,text: String,length: Nat,words: List<&2,Candidate>) -> Scan:
  match node:
    case Dictionary.Trie{tail,cost,edges}: consumed(consume(tail,text,length),cost,edges,words)
def scan(fuel: Nat,value: Scan) -> Matches:
  match fuel value:
    case _ Finished{result}: result
    case Zero{} Walking{_,_,length,words}: Matches{length,words}
    case Succ{left} Walking{node,text,length,words}: scan(left,step(node,text,length,words))
def matches(dictionary: Dictionary.Trie,text: String) -> Matches:
  scan(Data.maxWordLength() + 2n,Walking{dictionary,text,0n,Nil{}})
def any(result: Matches) -> Bool:
  match result:
    case Matches{_,Nil{}}: False{}
    case _: True{}
def third(+dictionary: Dictionary.Trie,candidates: List<&2,Candidate>) -> Bool:
  match candidates:
    case Nil{}: False{}
    case Candidate{_,SNil{}} <> _: True{}
    case Candidate{_,rest} <> +remaining:
      Bool.pick(Unit -> Bool,any(matches(dictionary,rest)),_ => True{},_ => third(dictionary,remaining))(Unit{})
type Choice is Data: Choice{finished: Bool,best: Candidate}
def second(dictionary: Dictionary.Trie,result: Matches,+current: Candidate,marked: Candidate) -> Choice:
  match result:
    case Matches{_,Nil{}}: Choice{False{},marked}
    case Matches{_,words}: Choice{third(dictionary,words),current}
def candidate(+dictionary: Dictionary.Trie,current: Candidate,marked: Candidate) -> Choice:
  match current:
    case Candidate{length,SNil{}}: Choice{True{},Candidate{length,""}}
    case Candidate{+length,+rest}: second(dictionary,matches(dictionary,rest),Candidate{length,rest},marked)
def lookahead(+dictionary: Dictionary.Trie,candidates: List<&2,Candidate>,choice: Choice) -> Candidate:
  match candidates choice:
    case _ Choice{True{},best}: best
    case Nil{} Choice{_,best}: best
    case current <> remaining Choice{_,best}: lookahead(dictionary,remaining,candidate(dictionary,current,best))
def choose(+dictionary: Dictionary.Trie,result: Matches,+text: String) -> Candidate:
  match result:
    case Matches{_,Nil{}}: Candidate{0n,text}
    case Matches{_,single <> Nil{}}: single
    case Matches{_,+first <> remaining}: lookahead(dictionary,first <> remaining,Choice{False{},first})
def endWord(+char: Char) -> Bool: Data.handles(char) && Bool.not(Char.is_eq(char,Chr{6098}))
def beginWord(char: Char) -> Bool:
  match char:
    case Chr{+code}: U32.is_ge(code,6016) && U32.is_le(code,6067)
def resync(+dictionary: Dictionary.Trie,text: String,length: Nat) -> Candidate:
  match text:
    case SNil{}: Candidate{length,""}
    case SCon{_,SNil{}}: Candidate{Succ{length},""}
    case SCon{previous,SCon{+next,+tail}}:
      +length = {Succ{length}: Nat}
      +rest = {SCon{next,tail}: String}
      Bool.pick(Unit -> Candidate,endWord(previous) && beginWord(next) && any(matches(dictionary,rest)),
        _ => Candidate{length,rest},_ => resync(dictionary,rest,length))(Unit{})
def unknown(dictionary: Dictionary.Trie,result: Matches,+text: String,+length: Nat) -> Candidate:
  match result:
    case Matches{prefix,Nil{}}:
      Bool.pick(Unit -> Candidate,Nat.is_eq(length,0n) || Nat.is_lt(prefix,3n),
        _ => resync(dictionary,text,length),_ => Candidate{length,text})(Unit{})
    case _: Candidate{length,text}
def combine(+dictionary: Dictionary.Trie,value: Candidate) -> Candidate:
  match value:
    case Candidate{+length,+rest}:
      Bool.pick(Unit -> Candidate,Nat.is_lt(length,3n),
        _ => unknown(dictionary,matches(dictionary,rest),rest,length),_ => Candidate{length,rest})(Unit{})
def marks(text: String,+length: Nat) -> Candidate:
  match text:
    case SNil{}: Candidate{length,""}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Candidate,Data.mark(char),_ => marks(rest,Succ{length}),_ => Candidate{length,SCon{char,rest}})(Unit{})
def attachMarks(value: Candidate) -> Candidate:
  match value:
    case Candidate{length,text}: marks(text,length)
type Work is Data: Work{text: String,position: Nat,reversed: List<&2,Nat>}
def accepted(value: Candidate,position: Nat,reversed: List<&2,Nat>) -> Work:
  match value:
    case Candidate{length,rest}:
      +position = position + length
      Work{rest,position,position <> reversed}
def advance(+dictionary: Dictionary.Trie,+text: String,position: Nat,reversed: List<&2,Nat>) -> Work:
  accepted(attachMarks(combine(dictionary,choose(dictionary,matches(dictionary,text),text))),position,reversed)
def loop(fuel: Nat,+dictionary: Dictionary.Trie,value: Work) -> List<&2,Nat>:
  match fuel value:
    case _ Work{SNil{},_,reversed}: List.reverse(&2,Nat,reversed)
    case Zero{} Work{_,_,reversed}: List.reverse(&2,Nat,reversed)
    case Succ{left} Work{text,position,reversed}: loop(left,dictionary,advance(dictionary,text,position,reversed))
def boundaries(+dictionary: Dictionary.Trie,+text: String) -> List<&2,Nat>:
  +length = String.length(text)
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_lt(length,4n),
    _ => Bool.pick(List<&2,Nat>,Nat.is_eq(length,0n),Nil{},length <> Nil{}),_ => loop(length,dictionary,Work{text,0n,Nil{}}))(Unit{})
