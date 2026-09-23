import Base
import ./unicode-17-word-break.bend as Unicode

# Unicode17 default word boundaries, UAX29 revision47 (WB1..WB999).
# This defines regions, not lexical words or Intl.Segmenter isWordLike status.
# Dictionary segmentation and locale tailoring belong above this algorithm.
type Class is Data:
  Other{} CR{} LF{} Newline{} Extend{} Format{} ZWJ{} WSegSpace{}
  ALetter{} HebrewLetter{} Numeric{} Katakana{} ExtendNumLet{}
  MidLetter{} MidNum{} MidNumLet{} SingleQuote{} DoubleQuote{} RegionalIndicator{}
type Properties is Data: Properties{word: Class,pictographic: Bool}
type Context is Data:
  Context{previous: Class,left: Class,beforeLeft: Class,regionalOdd: Bool}
def classOf(value: U32) -> Class:
  match value:
    case 1: CR{}
    case 2: LF{}
    case 3: Newline{}
    case 4: Extend{}
    case 5: Format{}
    case 6: ZWJ{}
    case 7: WSegSpace{}
    case 8: ALetter{}
    case 9: HebrewLetter{}
    case 10: Numeric{}
    case 11: Katakana{}
    case 12: ExtendNumLet{}
    case 13: MidLetter{}
    case 14: MidNum{}
    case 15: MidNumLet{}
    case 16: SingleQuote{}
    case 17: DoubleQuote{}
    case 18: RegionalIndicator{}
    case _: Other{}
def decoded(+packed: U32) -> Properties:
  Properties{classOf((packed % 32: U32)),U32.is_ge(packed,32)}
def properties(char: Char) -> Properties: decoded(Unicode.properties(Char.to_u32(char)))
def wordClass(char: Char) -> Class: classOf((Unicode.properties(Char.to_u32(char)) % 32: U32))
def ignored(value: Class) -> Bool:
  match value:
    case Extend{}: True{}
    case Format{}: True{}
    case ZWJ{}: True{}
    case _: False{}
def newline(value: Class) -> Bool:
  match value:
    case CR{}: True{}
    case LF{}: True{}
    case Newline{}: True{}
    case _: False{}
def letter(value: Class) -> Bool:
  match value:
    case ALetter{}: True{}
    case HebrewLetter{}: True{}
    case _: False{}
def number(value: Class) -> Bool:
  match value:
    case Numeric{}: True{}
    case _: False{}
def wordBase(value: Class) -> Bool:
  match value:
    case ALetter{}: True{}
    case HebrewLetter{}: True{}
    case Numeric{}: True{}
    case Katakana{}: True{}
    case _: False{}
def letterPunctuation(value: Class) -> Bool:
  match value:
    case MidLetter{}: True{}
    case MidNumLet{}: True{}
    case SingleQuote{}: True{}
    case _: False{}
def numberPunctuation(value: Class) -> Bool:
  match value:
    case MidNum{}: True{}
    case MidNumLet{}: True{}
    case SingleQuote{}: True{}
    case _: False{}
def lookahead(text: String) -> Class:
  match text:
    case SNil{}: Other{}
    case SCon{char,rest}:
      +value = wordClass(char)
      Bool.pick(Unit -> Class,ignored(value),_ => lookahead(rest),_ => value)(Unit{})
def adjacent(left: Class,right: Class) -> Bool:
  match left right:
    case ZWJ{} _: False{}
    case Katakana{} Katakana{}: True{}
    case ExtendNumLet{} ExtendNumLet{}: True{}
    case ExtendNumLet{} right: wordBase(right)
    case left ExtendNumLet{}: wordBase(left)
    case HebrewLetter{} SingleQuote{}: True{}
    case left right:
      +left = {left: Class}
      +right = {right: Class}
      (letter(left) && (letter(right) || number(right))) || (number(left) && (number(right) || letter(right)))
def trailingPunctuation(+before: Class,+middle: Class,+current: Class) -> Bool:
  match before middle current:
    case HebrewLetter{} DoubleQuote{} HebrewLetter{}: True{}
    case _ _ _:
      (letter(before) && letterPunctuation(middle) && letter(current)) || (number(before) && numberPunctuation(middle) && number(current))
def possibleBridge(+left: Class,+middle: Class) -> Bool:
  match left middle:
    case HebrewLetter{} DoubleQuote{}: True{}
    case _ _: (letter(left) && letterPunctuation(middle)) || (number(left) && numberPunctuation(middle))
def leadingPunctuation(+left: Class,+middle: Class,rest: String) -> Bool:
  Bool.pick(Unit -> Bool,possibleBridge(left,middle),_ => trailingPunctuation(left,middle,lookahead(rest)),_ => False{})(Unit{})
def regional(odd: Bool,current: Class) -> Bool:
  match current:
    case RegionalIndicator{}: odd
    case _: False{}
def early(previous: Class,current: Class,pictographic: Bool) -> Bool:
  match previous current:
    case ZWJ{} _: pictographic
    case WSegSpace{} WSegSpace{}: True{}
    case _ _: False{}
def continues(context: Context,value: Properties,rest: String) -> Bool:
  match context value:
    case Context{CR{},_,_,_} Properties{LF{},_}: True{}
    case Context{previous,+left,before,odd} Properties{current,pictographic}:
      +previous = {previous: Class}
      +current = {current: Class}
      Bool.pick(Unit -> Bool,newline(previous) || newline(current),_ => False{},
        _ => Bool.pick(Unit -> Bool,early(previous,current,pictographic) || ignored(current) || adjacent(left,current) || trailingPunctuation(before,left,current) || regional(odd,current),
          _ => True{},_ => leadingPunctuation(left,current,rest))(Unit{}))(Unit{})
def nextOdd(odd: Bool,current: Class) -> Bool:
  match current:
    case RegionalIndicator{}: Bool.not(odd)
    case _: False{}
def advance(context: Context,value: Properties) -> Context:
  match context value:
    case Context{_,+left,+before,+odd} Properties{+current,_}:
      Bool.pick(Context,ignored(current),Context{current,left,before,odd},Context{current,current,left,nextOdd(odd,current)})
def initial(current: Properties) -> Context: advance(Context{Other{},Other{},Other{},False{}},current)

# Lookahead is needed only at a possible internal punctuation boundary. Ignored
# runs are scanned at most once there and once during consumption. No suffix
# lengths or reversals: repeated next calls remain linear in consumed text.
def takeRegion(text: String,+context: Context,+reversed: String) -> String & String:
  match text:
    case SNil{}: (String.reverse(reversed),"")
    case SCon{+char,+rest}:
      +value = properties(char)
      Bool.pick(Unit -> String & String,continues(context,value,rest),
        _ => takeRegion(rest,advance(context,value),SCon{char,reversed}),
        _ => (String.reverse(reversed),SCon{char,rest}))(Unit{})
def next(text: String) -> Maybe<&1,String & String>:
  match text:
    case SNil{}: None{}
    case SCon{+char,rest}: Some{takeRegion(rest,initial(properties(char)),SCon{char,""})}
def split(text: String,+context: Context,+region: String,+reversed: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(region) <> reversed)
    case SCon{+char,+rest}:
      +value = properties(char)
      Bool.pick(Unit -> List<&2,String>,continues(context,value,rest),
        _ => split(rest,advance(context,value),SCon{char,region},reversed),
        _ => split(rest,advance(context,value),SCon{char,""},String.reverse(region) <> reversed))(Unit{})
def segments(text: String) -> List<&2,String>:
  match text:
    case SNil{}: Nil{}
    case SCon{+char,rest}: split(rest,initial(properties(char)),SCon{char,""},Nil{})
