import Base
import ./word-rules.bend as Rules
import ./cjk-dictionary.bend as Dictionary
import ./cjk-word-break.bend as Cjk
import ./sea-word-break.bend as Sea
import ./sea-word-data.bend as SeaData

# ICU78 word rules with preloaded CJK and Southeast Asian dictionaries.
# The pinned reference runtime has no Thai/Myanmar LSTM model resources.
type Context is Data: Context{rules: Rules.Rules,cjk: Cjk.Context,khmer: Sea.Context,lao: Sea.Context,thai: Sea.Context,myanmar: Sea.Context}
type Segment is Data: Segment{text: String,isWordLike: Bool,status: U32}
type Error is Data: MissingEngine{language: String} InvalidState{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def create(rules: Rules.Rules,dictionary: Dictionary.Trie,khmer: Dictionary.Trie,lao: Dictionary.Trie,thai: Dictionary.Trie,myanmar: Dictionary.Trie) -> Context:
  Context{rules,Cjk.create(dictionary),Sea.Context{SeaData.Khmer{},khmer},Sea.Context{SeaData.Lao{},lao},Sea.Context{SeaData.Thai{},thai},Sea.Context{SeaData.Myanmar{},myanmar}}

type Mode is Data: Outside{} CjkRange{} KoreanRange{} KhmerRange{} LaoRange{} ThaiRange{} MyanmarRange{}
type DictionaryScan is Data:
  Active{position: Nat,start: Nat,mode: Mode,reversed: String,breaks: List<&2,Nat>}
  Failed{error: Error}
def internalBreaks(ends: List<&2,Nat>,+start: Nat,reversed: List<&2,Nat>) -> List<&2,Nat>:
  match ends:
    case Nil{}: reversed
    case _ <> Nil{}: reversed
    case endpoint <> rest: internalBreaks(rest,start,(start + endpoint) <> reversed)
def rangeEnds(context: Context,mode: Mode,text: String) -> List<&2,Nat>:
  match context mode:
    case Context{_,_,khmer,_,_,_} KhmerRange{}: Sea.boundaries(khmer,text)
    case Context{_,_,_,lao,_,_} LaoRange{}: Sea.boundaries(lao,text)
    case Context{_,_,_,_,thai,_} ThaiRange{}: Sea.boundaries(thai,text)
    case Context{_,_,_,_,_,myanmar} MyanmarRange{}: Sea.boundaries(myanmar,text)
    case Context{_,cjk,_,_,_,_} _: Cjk.boundaries(cjk,text)
def flush(context: Context,mode: Mode,start: Nat,reversed: String,breaks: List<&2,Nat>) -> List<&2,Nat>:
  match reversed:
    case SNil{}: breaks
    case SCon{char,rest}: internalBreaks(rangeEnds(context,mode,String.reverse(SCon{char,rest})),start,breaks)
def continues(mode: Mode,char: Char) -> Bool:
  match mode:
    case Outside{}: False{}
    case CjkRange{}: Cjk.handles(char)
    case KoreanRange{}: Cjk.hangul(char)
    case KhmerRange{}: SeaData.handles(SeaData.Khmer{},char)
    case LaoRange{}: SeaData.handles(SeaData.Lao{},char)
    case ThaiRange{}: SeaData.handles(SeaData.Thai{},char)
    case MyanmarRange{}: SeaData.handles(SeaData.Myanmar{},char)
def engine(kind: U32,char: Char,+position: Nat,breaks: List<&2,Nat>) -> DictionaryScan:
  match kind:
    case 1: Active{Succ{position},position,CjkRange{},SCon{char,""},breaks}
    case 2: Active{Succ{position},position,KoreanRange{},SCon{char,""},breaks}
    case 3: Active{Succ{position},position,ThaiRange{},SCon{char,""},breaks}
    case 4: Active{Succ{position},position,LaoRange{},SCon{char,""},breaks}
    case 5: Active{Succ{position},position,MyanmarRange{},SCon{char,""},breaks}
    case 6: Active{Succ{position},position,KhmerRange{},SCon{char,""},breaks}
    case 7: Active{Succ{position},position,CjkRange{},SCon{char,""},breaks}
    case _: Active{Succ{position},Succ{position},Outside{},"",breaks}
def begin(+properties: U32,+char: Char,+position: Nat,+breaks: List<&2,Nat>) -> DictionaryScan:
  Bool.pick(Unit -> DictionaryScan,U32.is_ge((properties % 256: U32),24),
    _ => engine((properties / 256: U32),char,position,breaks),
    _ => Active{Succ{position},Succ{position},Outside{},"",breaks})(Unit{})
def properties(context: Context,char: Char) -> U32:
  match context:
    case Context{rules,_,_,_,_,_}: Rules.properties(rules,char)
def feed(+context: Context,+char: Char,value: DictionaryScan) -> DictionaryScan:
  match value:
    case Failed{error}: Failed{error}
    case Active{+position,+start,+mode,+reversed,+breaks}:
      Bool.pick(Unit -> DictionaryScan,continues(mode,char),
        _ => Active{Succ{position},start,mode,SCon{char,reversed},breaks},
        _ => begin(properties(context,char),char,position,flush(context,mode,start,reversed,breaks)))(Unit{})
def finish(+context: Context,value: DictionaryScan) -> ResultOf(List<&2,Nat>):
  match value:
    case Failed{error}: Fail{error}
    case Active{position,start,mode,reversed,breaks}:
      Done{List.reverse(&2,Nat,position <> flush(context,mode,start,reversed,breaks))}
def dictionaryBreaks(text: String,+context: Context,value: DictionaryScan) -> ResultOf(List<&2,Nat>):
  match text value:
    case _ Failed{error}: Fail{error}
    case SNil{} value: finish(context,value)
    case SCon{char,rest} value: dictionaryBreaks(rest,context,feed(context,char,value))

type Cut is Data: Cut{text: String,rest: String}
type Pieces is Data: Pieces{rest: String,reversed: List<&2,Segment>}
def cut(count: Nat,text: String,reversed: String) -> Cut:
  match count text:
    case Zero{} text: Cut{String.reverse(reversed),text}
    case Succ{left} SCon{char,rest}: cut(left,rest,SCon{char,reversed})
    case _ SNil{}: Cut{String.reverse(reversed),""}
def piece(value: Cut,+status: U32,reversed: List<&2,Segment>) -> Pieces:
  match value:
    case Cut{text,rest}: Pieces{rest,Segment{text,U32.is_ge(status,100) && U32.is_lt(status,500),status} <> reversed}
def take(endpoint: Nat,previous: Nat,status: U32,value: Pieces) -> Pieces:
  match value:
    case Pieces{text,reversed}: piece(cut(endpoint - previous,text,""),status,reversed)
def split(ends: List<&2,Nat>,previous: Nat,+status: U32,value: Pieces) -> Pieces:
  match ends:
    case Nil{}: value
    case +endpoint <> rest: split(rest,endpoint,status,take(endpoint,previous,status,value))

type Work is Data: Work{rest: String,reversed: List<&2,Segment>}
def rejoined(value: Pieces,rest: String) -> ResultOf(Work):
  match value:
    case Pieces{SNil{},reversed}: Done{Work{rest,reversed}}
    case _: Fail{InvalidState{}}
def subdivided(result: ResultOf(List<&2,Nat>),text: String,rest: String,status: U32,reversed: List<&2,Segment>) -> ResultOf(Work):
  match result:
    case Fail{error}: Fail{error}
    case Done{ends}: rejoined(split(ends,0n,status,Pieces{text,reversed}),rest)
def region(context: Context,value: Maybe<&2,Rules.Region>,reversed: List<&2,Segment>) -> ResultOf(Work):
  match value:
    case None{}: Done{Work{"",reversed}}
    case Some{Rules.Region{+text,+rest,+length,+status,dictionary}}:
      +reversed = {reversed: List<&2,Segment>}
      Bool.pick(Unit -> ResultOf(Work),dictionary && Nat.is_gt(length,1n),
        _ => subdivided(dictionaryBreaks(text,context,Active{0n,0n,Outside{},"",Nil{}}),text,rest,status,reversed),
        _ => Done{Work{rest,Segment{text,U32.is_ge(status,100) && U32.is_lt(status,500),status} <> reversed}})(Unit{})
def next(+context: Context,value: Work) -> ResultOf(Work):
  match context value:
    case Context{rules,_,_,_,_,_} Work{text,reversed}: region(context,Rules.next(rules,text),reversed)
def segmentsLoop(fuel: Nat,+context: Context,result: ResultOf(Work)) -> ResultOf(List<&2,Segment>):
  match fuel result:
    case _ Fail{error}: Fail{error}
    case _ Done{Work{SNil{},reversed}}: Done{List.reverse(&2,Segment,reversed)}
    case Succ{left} Done{work}: segmentsLoop(left,context,next(context,work))
    case Zero{} _: Fail{InvalidState{}}
def segments(+context: Context,+text: String) -> ResultOf(List<&2,Segment>):
  segmentsLoop(String.length(text),context,Done{Work{text,Nil{}}})
