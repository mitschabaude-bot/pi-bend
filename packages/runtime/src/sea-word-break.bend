import Base
import ./cjk-dictionary.bend as Dictionary
import ./u32-table.bend as Table
import ./sea-word-data.bend as Data

# ICU78 Khmer/Lao dictionary engine, with immutable three-word lookahead.
# Trie records share the native CJK radix representation, but Khmer matching
# has language-specific length bounds and retains ICU's attempted-prefix count.
type Context is Data: Context{language: Data.Language,dictionary: Dictionary.Trie}
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
def matches(context: Context,text: String) -> Matches:
  match context:
    case Context{language,dictionary}: scan(Data.maxWordLength(language) + 2n,Walking{dictionary,text,0n,Nil{}})
def any(result: Matches) -> Bool:
  match result:
    case Matches{_,Nil{}}: False{}
    case _: True{}
def third(+context: Context,candidates: List<&2,Candidate>) -> Bool:
  match candidates:
    case Nil{}: False{}
    case Candidate{_,SNil{}} <> _: True{}
    case Candidate{_,rest} <> +remaining:
      Bool.pick(Unit -> Bool,any(matches(context,rest)),_ => True{},_ => third(context,remaining))(Unit{})
type Choice is Data: Choice{finished: Bool,best: Candidate}
def second(context: Context,result: Matches,+current: Candidate,marked: Candidate) -> Choice:
  match result:
    case Matches{_,Nil{}}: Choice{False{},marked}
    case Matches{_,words}: Choice{third(context,words),current}
def candidate(+context: Context,current: Candidate,marked: Candidate) -> Choice:
  match current:
    case Candidate{length,SNil{}}: Choice{True{},Candidate{length,""}}
    case Candidate{+length,+rest}: second(context,matches(context,rest),Candidate{length,rest},marked)
def lookahead(+context: Context,candidates: List<&2,Candidate>,choice: Choice) -> Candidate:
  match candidates choice:
    case _ Choice{True{},best}: best
    case Nil{} Choice{_,best}: best
    case current <> remaining Choice{_,best}: lookahead(context,remaining,candidate(context,current,best))
def choose(+context: Context,result: Matches,+text: String) -> Candidate:
  match result:
    case Matches{_,Nil{}}: Candidate{0n,text}
    case Matches{_,single <> Nil{}}: single
    case Matches{_,+first <> remaining}: lookahead(context,first <> remaining,Choice{False{},first})
def endWord(context: Context,char: Char) -> Bool:
  match context:
    case Context{language,_}: Data.endWord(language,char)
def beginWord(context: Context,char: Char) -> Bool:
  match context:
    case Context{language,_}: Data.beginWord(language,char)
def mark(context: Context,char: Char) -> Bool:
  match context:
    case Context{language,_}: Data.mark(language,char)
def resync(+context: Context,text: String,length: Nat) -> Candidate:
  match text:
    case SNil{}: Candidate{length,""}
    case SCon{_,SNil{}}: Candidate{Succ{length},""}
    case SCon{previous,SCon{+next,+tail}}:
      +length = {Succ{length}: Nat}
      +rest = {SCon{next,tail}: String}
      Bool.pick(Unit -> Candidate,endWord(context,previous) && beginWord(context,next) && any(matches(context,rest)),
        _ => Candidate{length,rest},_ => resync(context,rest,length))(Unit{})
def unknown(context: Context,result: Matches,+text: String,+length: Nat) -> Candidate:
  match result:
    case Matches{prefix,Nil{}}:
      Bool.pick(Unit -> Candidate,Nat.is_eq(length,0n) || Nat.is_lt(prefix,3n),
        _ => resync(context,text,length),_ => Candidate{length,text})(Unit{})
    case _: Candidate{length,text}
def combine(+context: Context,value: Candidate) -> Candidate:
  match value:
    case Candidate{+length,+rest}:
      Bool.pick(Unit -> Candidate,Nat.is_lt(length,3n),
        _ => unknown(context,matches(context,rest),rest,length),_ => Candidate{length,rest})(Unit{})
def marks(text: String,+context: Context,+length: Nat) -> Candidate:
  match text:
    case SNil{}: Candidate{length,""}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Candidate,mark(context,char),_ => marks(rest,context,Succ{length}),_ => Candidate{length,SCon{char,rest}})(Unit{})
def attachMarks(context: Context,value: Candidate) -> Candidate:
  match value:
    case Candidate{length,text}: marks(text,context,length)
type Work is Data: Work{text: String,position: Nat,reversed: List<&2,Nat>}
def accepted(value: Candidate,position: Nat,reversed: List<&2,Nat>) -> Work:
  match value:
    case Candidate{length,rest}:
      +position = position + length
      Work{rest,position,position <> reversed}
def advance(+context: Context,+text: String,position: Nat,reversed: List<&2,Nat>) -> Work:
  accepted(attachMarks(context,combine(context,choose(context,matches(context,text),text))),position,reversed)
def loop(fuel: Nat,+context: Context,value: Work) -> List<&2,Nat>:
  match fuel value:
    case _ Work{SNil{},_,reversed}: List.reverse(&2,Nat,reversed)
    case Zero{} Work{_,_,reversed}: List.reverse(&2,Nat,reversed)
    case Succ{left} Work{text,position,reversed}: loop(left,context,advance(context,text,position,reversed))
def boundaries(+context: Context,+text: String) -> List<&2,Nat>:
  +length = String.length(text)
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_lt(length,4n),
    _ => Bool.pick(List<&2,Nat>,Nat.is_eq(length,0n),Nil{},length <> Nil{}),_ => loop(length,context,Work{text,0n,Nil{}}))(Unit{})
