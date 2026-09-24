import Base
import ../../runtime/src/text.bend as Text
import ../../runtime/src/word-segmenter.bend as Native

# A segmenter supplies lexical status; Unicode default word boundaries alone do
# not provide Intl's dictionary/LSTM segmentation. There is no implicit default.
type Segment is Data: Segment{text: String,isWordLike: Bool}
type Error is Data: InvalidCursor{} InvalidSegments{} MissingWordEngine{language: String} WordData{cause: Native.LoadError} WordDataPending{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
type Slice is Data: Slice{before: String,after: String}
type Direction is Data: Forward{} Backward{}
type Phase is Data: Seeking{} Punctuation{}

def slice(text: String,cursor: Nat,reversed: String) -> ResultOf(Slice):
  match text cursor:
    case text Zero{}: Done{Slice{String.reverse(reversed),text}}
    case SCon{char,rest} Succ{left}: slice(rest,left,SCon{char,reversed})
    case SNil{} Succ{_}: Fail{InvalidCursor{}}
def consume(expected: String,input: String) -> Maybe<&2,String>:
  match expected input:
    case SNil{} input: Some{input}
    case SCon{a,+left} SCon{b,+right}: Bool.pick(Unit -> Maybe<&2,String>,Char.is_eq(a,b),_ => consume(left,right),_ => None{})(Unit{})
    case _ _: None{}
def validate(parts: List<&2,Segment>,remaining: Maybe<&2,String>) -> Bool:
  match parts remaining:
    case Nil{} Some{SNil{}}: True{}
    case Segment{SNil{},_} <> _ _: False{}
    case Segment{value,_} <> rest Some{input}: validate(rest,consume(value,input))
    case _ _: False{}
def whitespace(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code},+rest}: Bool.pick(Unit -> Bool,Text.whitespace(code),_ => True{},_ => whitespace(rest))(Unit{})
def punctuation(char: Char) -> Bool:
  String.contains("(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`",SCon{char,""})
def leadingPunctuation(text: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{char,+rest}: Bool.pick(Unit -> Nat,punctuation(char),_ => leadingPunctuation(rest,Succ{count}),_ => count)(Unit{})
def forwardWord(text: String,+index: Nat) -> Nat:
  match text:
    case SNil{}: index
    case SCon{char,+rest}: Bool.pick(Unit -> Nat,punctuation(char),_ => index,_ => forwardWord(rest,Succ{index}))(Unit{})
def backwardWord(text: String,count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{char,rest}: backwardWord(rest,Bool.pick(Nat,punctuation(char),0n,Succ{count}))
def wordDistance(direction: Direction,+text: String) -> Nat:
  match direction:
    case Forward{}:
      +distance = forwardWord(text,0n)
      Bool.pick(Unit -> Nat,Nat.is_eq(distance,0n),_ => leadingPunctuation(text,0n),_ => distance)(Unit{})
    case Backward{}:
      +distance = backwardWord(text,0n)
      Bool.pick(Unit -> Nat,Nat.is_eq(distance,0n),_ => leadingPunctuation(String.reverse(text),0n),_ => distance)(Unit{})
def moved(direction: Direction,position: Nat,count: Nat) -> Nat:
  match direction:
    case Forward{}: position + count
    case Backward{}: position - count

# Whitespace first; then one lexical/atomic region, or a contiguous punctuation
# run. Atomic markers take priority even if their text contains whitespace.
def walk(~Context: Data,~isAtomic: Context -> String -> Bool,+context: Context,+direction: Direction,parts: List<&2,Segment>,+position: Nat,phase: Phase) -> Nat:
  match parts phase:
    case Nil{} _: position
    case Segment{+value,word} <> +rest Seeking{}:
      Bool.pick(Unit -> Nat,isAtomic(context,value),_ => moved(direction,position,String.length(value)),
        _ => Bool.pick(Unit -> Nat,whitespace(value),_ => walk(~Context,~isAtomic,context,direction,rest,moved(direction,position,String.length(value)),Seeking{}),
          _ => Bool.pick(Unit -> Nat,word,_ => moved(direction,position,wordDistance(direction,value)),
            _ => walk(~Context,~isAtomic,context,direction,rest,moved(direction,position,String.length(value)),Punctuation{}))(Unit{}))(Unit{}))(Unit{})
    case Segment{+value,word} <> rest Punctuation{}:
      Bool.pick(Unit -> Nat,isAtomic(context,value) || whitespace(value) || word,_ => position,
        _ => walk(~Context,~isAtomic,context,direction,rest,moved(direction,position,String.length(value)),Punctuation{}))(Unit{})
def isBackward(direction: Direction) -> Bool:
  match direction:
    case Backward{}: True{}
    case Forward{}: False{}
def navigate(~Context: Data,~isAtomic: Context -> String -> Bool,context: Context,+direction: Direction,+text: String,cursor: Nat,+parts: List<&2,Segment>) -> ResultOf(Nat):
  Bool.pick(Unit -> ResultOf(Nat),validate(parts,Some{text}),
    _ => Done{walk(~Context,~isAtomic,context,direction,Bool.pick(List<&2,Segment>,isBackward(direction),List.reverse(&2,Segment,parts),parts),cursor,Seeking{})},
    _ => Fail{InvalidSegments{}})(Unit{})
def find(~Context: Data,~segment: Context -> String -> List<&2,Segment>,~isAtomic: Context -> String -> Bool,+context: Context,+direction: Direction,cursor: Nat,result: ResultOf(Slice)) -> ResultOf(Nat):
  match result:
    case Fail{error}: Fail{error}
    case Done{Slice{before,after}}:
      +text = Bool.pick(String,isBackward(direction),before,after)
      navigate(~Context,~isAtomic,context,direction,text,cursor,segment(context,text))
def findWordBackward(~Context: Data,~segment: Context -> String -> List<&2,Segment>,~isAtomic: Context -> String -> Bool,context: Context,text: String,+cursor: Nat) -> ResultOf(Nat):
  find(~Context,~segment,~isAtomic,context,Backward{},cursor,slice(text,cursor,""))
def findWordForward(~Context: Data,~segment: Context -> String -> List<&2,Segment>,~isAtomic: Context -> String -> Bool,context: Context,text: String,+cursor: Nat) -> ResultOf(Nat):
  find(~Context,~segment,~isAtomic,context,Forward{},cursor,slice(text,cursor,""))

# A checked segmenter can report an unavailable dictionary/model explicitly.
# Keep the infallible callback entrypoints for fully supplied custom segmenters.
def segmented(~Context: Data,~isAtomic: Context -> String -> Bool,context: Context,direction: Direction,text: String,cursor: Nat,result: ResultOf(List<&2,Segment>)) -> ResultOf(Nat):
  match result:
    case Fail{error}: Fail{error}
    case Done{parts}: navigate(~Context,~isAtomic,context,direction,text,cursor,parts)
def findChecked(~Context: Data,~segment: Context -> String -> ResultOf(List<&2,Segment>),~isAtomic: Context -> String -> Bool,+context: Context,+direction: Direction,cursor: Nat,result: ResultOf(Slice)) -> ResultOf(Nat):
  match result:
    case Fail{error}: Fail{error}
    case Done{Slice{before,after}}:
      +text = Bool.pick(String,isBackward(direction),before,after)
      segmented(~Context,~isAtomic,context,direction,text,cursor,segment(context,text))
def findWordBackwardChecked(~Context: Data,~segment: Context -> String -> ResultOf(List<&2,Segment>),~isAtomic: Context -> String -> Bool,context: Context,text: String,+cursor: Nat) -> ResultOf(Nat):
  findChecked(~Context,~segment,~isAtomic,context,Backward{},cursor,slice(text,cursor,""))
def findWordForwardChecked(~Context: Data,~segment: Context -> String -> ResultOf(List<&2,Segment>),~isAtomic: Context -> String -> Bool,context: Context,text: String,+cursor: Nat) -> ResultOf(Nat):
  findChecked(~Context,~segment,~isAtomic,context,Forward{},cursor,slice(text,cursor,""))

# Adapt the explicitly loaded native runtime context for all TUI editors.
# Loading/assets remain caller-owned; custom checked segmenters remain valid.
def nativeParts(values: List<&2,Native.Segment>,reversed: List<&2,Segment>) -> List<&2,Segment>:
  match values:
    case Nil{}: List.reverse(&2,Segment,reversed)
    case Native.Segment{text,word,_} <> rest: nativeParts(rest,Segment{text,word} <> reversed)
def nativeResult(value: Native.ResultOf(List<&2,Native.Segment>)) -> ResultOf(List<&2,Segment>):
  match value:
    case Done{values}: Done{nativeParts(values,Nil{})}
    case Fail{Native.MissingEngine{language}}: Fail{MissingWordEngine{language}}
    case Fail{Native.InvalidState{}}: Fail{InvalidSegments{}}
def nativeSegments(context: Native.Context,text: String) -> ResultOf(List<&2,Segment>):
  nativeResult(Native.segments(context,text))
# Callers make the source ready before a word command.
def sourceSegments(source: Native.Source,text: String) -> ResultOf(List<&2,Segment>):
  match source:
    case Native.Ready{context}: nativeSegments(context,text)
    case Native.Unavailable{error}: Fail{WordData{error}}
    case Native.Pending{_}: Fail{WordDataPending{}}
