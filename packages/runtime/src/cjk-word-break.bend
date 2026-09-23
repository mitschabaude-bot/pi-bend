import Base
import ./string.bend as Text
import ./cjk-dictionary.bend as Dictionary
import ./unicode.bend as Unicode
import ./unicode-17-compatibility.bend as Compatibility
import ./unicode-17-normalization.bend as Canonical
import ./unicode-17-cjk.bend as Properties

# ICU78.3 CjkBreakEngine's weighted word segmentation of a dictionary range.
# The caller owns ICU word-rule range selection; this is not a default Intl
# segmenter and does not implement the other dictionary/LSTM language engines.
type Context is Data: Context{dictionary: Dictionary.Trie,normalization: Unicode.Tables}
def create(dictionary: Dictionary.Trie) -> Context:
  Context{dictionary,Unicode.Tables{Compatibility.compatibilityProperties(),Canonical.compositions()}}
def handles(char: Char) -> Bool: U32.is_ge(Properties.properties(Char.to_u32(char)),2)
def boundaryBefore(char: Char) -> Bool: U32.is_eq((Properties.properties(Char.to_u32(char)) % 2: U32),1)

type Normalized is Data: Normalized{text: String,offsets: List<&2,Nat>}
type Output is Data: Output{reversed: String,offsets: List<&2,Nat>}
def append(text: String,+start: Nat,output: Output) -> Output:
  match text output:
    case SNil{} output: output
    case SCon{char,rest} Output{reversed,offsets}: append(rest,start,Output{SCon{char,reversed},start <> offsets})
def finish(output: Output,end: Nat) -> Normalized:
  match output:
    case Output{reversed,offsets}: Normalized{String.reverse(reversed),List.reverse(&2,Nat,end <> offsets)}
def chunks(text: String,+tables: Unicode.Tables,+position: Nat,+start: Nat,+fragment: String,+output: Output) -> Normalized:
  match text:
    case SNil{}: finish(append(Unicode.nfc(tables,String.reverse(fragment)),start,output),position)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Normalized,boundaryBefore(char),
        _ => chunks(rest,tables,Succ{position},position,SCon{char,""},append(Unicode.nfc(tables,String.reverse(fragment)),start,output)),
        _ => chunks(rest,tables,Succ{position},start,SCon{char,fragment},output))(Unit{})
def identity(text: String,+position: Nat,reversed: List<&2,Nat>) -> List<&2,Nat>:
  match text:
    case SNil{}: List.reverse(&2,Nat,position <> reversed)
    case SCon{_,rest}: identity(rest,Succ{position},position <> reversed)
def normalized(+tables: Unicode.Tables,+text: String) -> Normalized:
  Bool.pick(Unit -> Normalized,Text.equal(Unicode.nfc(tables,text),text),
    _ => Normalized{text,identity(text,0n,Nil{})},
    _ => chunks(text,tables,0n,0n,"",Output{"",Nil{}}))(Unit{})

def katakana(char: Char) -> Bool:
  +code = Char.to_u32(char)
  (U32.is_ge(code,12449) && U32.is_le(code,12542) && Bool.not(U32.is_eq(code,12539))) || (U32.is_ge(code,65382) && U32.is_le(code,65439))
def hangul(char: Char) -> Bool:
  +code = Char.to_u32(char)
  U32.is_ge(code,44032) && U32.is_le(code,55203)
def katakanaLength(fuel: Nat,text: String,+length: Nat) -> Nat:
  match fuel text:
    case Succ{left} SCon{char,+rest}: Bool.pick(Unit -> Nat,katakana(char),_ => katakanaLength(left,rest,Succ{length}),_ => length)(Unit{})
    case _ _: length
def katakanaCost(length: Nat) -> U32:
  match length:
    case 1n: 984
    case 2n: 408
    case 3n: 240
    case 4n: 204
    case 5n: 252
    case 6n: 300
    case 7n: 372
    case 8n: 480
    case _: 8192

type Path is Data: Path{cost: U32,ends: List<&2,Nat>}
def cheaper(cost: U32,current: Maybe<&2,Path>) -> Bool:
  match current:
    case None{}: U32.is_lt(cost,4294967295)
    case Some{Path{old,_}}: U32.is_lt(cost,old)
def relax(distance: Nat,+cost: U32,+ends: List<&2,Nat>,window: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match distance window:
    case Zero{} +current <> rest: Bool.pick(Maybe<&2,Path>,cheaper(cost,current),Some{Path{cost,ends}},current) <> rest
    case Succ{left} current <> rest: current <> relax(left,cost,ends,rest)
    case _ Nil{}: Nil{}
def candidates(matches: List<&2,Dictionary.Match>,+position: Nat,+best: Path,window: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match matches best:
    case Nil{} _: window
    case Dictionary.Match{+length,cost} <> rest Path{+total,+ends}:
      candidates(rest,position,Path{total,ends},relax(length,(total + cost: U32),(position + length) <> ends,window))
def single(matches: List<&2,Dictionary.Match>) -> Bool:
  match matches:
    case Dictionary.Match{1n,_} <> _: True{}
    case _: False{}
def fallback(char: Char,+matches: List<&2,Dictionary.Match>) -> List<&2,Dictionary.Match>:
  Bool.pick(List<&2,Dictionary.Match>,single(matches) || hangul(char),matches,List.append(&2,Dictionary.Match,matches,Dictionary.Match{1n,255} <> Nil{}))
def katakanaCandidate(enabled: Bool,+length: Nat,position: Nat,best: Path,+window: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match best:
    case Path{total,ends}:
      Bool.pick(Unit -> List<&2,Maybe<&2,Path>>,enabled && Nat.is_lt(length,20n),
        _ => relax(length,(total + katakanaCost(length): U32),(position + length) <> ends,window),_ => window)(Unit{})
def shift(window: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match window:
    case _ <> rest: List.append(&2,Maybe<&2,Path>,rest,None{} <> Nil{})
    case Nil{}: Nil{}
def solve(text: String,+dictionary: Dictionary.Trie,+position: Nat,+previousKatakana: Bool,+window: List<&2,Maybe<&2,Path>>) -> List<&2,Nat>:
  match text window:
    case SNil{} Some{Path{_,ends}} <> _: List.reverse(&2,Nat,ends)
    case SNil{} _: position <> Nil{}
    case SCon{+char,+rest} Some{+best} <> _:
      +isKatakana = katakana(char)
      solve(rest,dictionary,Succ{position},isKatakana,
        shift(katakanaCandidate(Bool.not(previousKatakana) && isKatakana,katakanaLength(20n,SCon{char,rest},0n),position,best,
          candidates(fallback(char,Dictionary.prefixes(dictionary,SCon{char,rest})),position,best,window))))
    case SCon{_,rest} _: solve(rest,dictionary,Succ{position},previousKatakana,shift(window))
def emptyWindow(count: Nat) -> List<&2,Maybe<&2,Path>>:
  match count:
    case Zero{}: Nil{}
    case Succ{left}: None{} <> emptyWindow(left)
def project(targets: List<&2,Nat>,offsets: List<&2,Nat>,+index: Nat,+previous: Nat,+reversed: List<&2,Nat>) -> List<&2,Nat>:
  match targets offsets:
    case +target <> +rest +offset <> +tail:
      Bool.pick(Unit -> List<&2,Nat>,Nat.is_eq(target,index),
        _ => project(rest,tail,Succ{index},offset,Bool.pick(List<&2,Nat>,Nat.is_gt(offset,previous),offset <> reversed,reversed)),
        _ => project(target <> rest,tail,Succ{index},previous,reversed))(Unit{})
    case _ _: List.reverse(&2,Nat,reversed)
def divided(dictionary: Dictionary.Trie,value: Normalized) -> List<&2,Nat>:
  match value:
    case Normalized{text,offsets}: project(solve(text,dictionary,0n,False{},Some{Path{0,Nil{}}} <> emptyWindow(20n)),offsets,0n,0n,Nil{})
def boundaries(context: Context,text: String) -> List<&2,Nat>:
  match context:
    case Context{dictionary,tables}: divided(dictionary,normalized(tables,text))
