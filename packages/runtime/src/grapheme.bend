import Base
import ./unicode-17-grapheme.bend as Unicode

# Unicode17 default extended grapheme clusters (UAX29 revision47).
# These properties belong to segmentation; display cell width is independent.
type Class is Data:
  Other{} CR{} LF{} Control{} Extend{} ZWJ{} RegionalIndicator{}
  Prepend{} SpacingMark{} L{} V{} T{} LV{} LVT{}
type IndicProperty is Data: NoIndic{} Consonant{} IndicExtend{} Linker{}
type Properties is Data:
  Properties{grapheme: Class, pictographic: Bool, indic: IndicProperty}
type EmojiState is Data: NoEmoji{} EmojiBase{} EmojiJoiner{}
type IndicState is Data: NoConjunct{} ConsonantSeen{} LinkerSeen{}
type Context is Data:
  Context{previous: Class, regionalOdd: Bool, emoji: EmojiState, indic: IndicState}

def classOf(value: U32) -> Class:
  match value:
    case 1: CR{}
    case 2: LF{}
    case 3: Control{}
    case 4: Extend{}
    case 5: ZWJ{}
    case 6: RegionalIndicator{}
    case 7: Prepend{}
    case 8: SpacingMark{}
    case 9: L{}
    case 10: V{}
    case 11: T{}
    case 12: LV{}
    case 13: LVT{}
    case _: Other{}
def indicOf(value: U32) -> IndicProperty:
  match value:
    case 1: Consonant{}
    case 2: IndicExtend{}
    case 3: Linker{}
    case _: NoIndic{}
def packedHangul(syllable: Bool,+code: U32) -> U32:
  match syllable:
    case True{}: Bool.pick(U32,U32.is_eq(((code - 44032 : U32) % 28 : U32),0),12,13)
    case False{}: Unicode.lookup(code)
def packedFrom(ascii: Bool,+code: U32) -> U32:
  match ascii:
    case True{}: Bool.pick(U32,U32.is_lt(code,32) || U32.is_eq(code,127),3,0)
    case False{}: packedHangul(U32.is_ge(code,44032) && U32.is_lt(code,55204),code)
def packed(+code: U32) -> U32:
  match code:
    case 10: 2
    case 13: 1
    case +code: packedFrom(U32.is_lt(code,128),code)
def propertiesFrom(+value: U32) -> Properties:
  Properties{classOf((value % 16 : U32)),U32.is_eq(((value / 16 : U32) % 2 : U32),1),indicOf((value / 32 : U32))}
def properties(char: Char) -> Properties: propertiesFrom(packed(Char.to_u32(char)))

def control(value: Class) -> Bool:
  match value:
    case CR{}: True{}
    case LF{}: True{}
    case Control{}: True{}
    case _: False{}
def hangul(left: Class,right: Class) -> Bool:
  match left right:
    case L{} L{}: True{}
    case L{} V{}: True{}
    case L{} LV{}: True{}
    case L{} LVT{}: True{}
    case LV{} V{}: True{}
    case LV{} T{}: True{}
    case V{} V{}: True{}
    case V{} T{}: True{}
    case LVT{} T{}: True{}
    case T{} T{}: True{}
    case _ _: False{}
def attached(previous: Class,current: Class) -> Bool:
  match previous current:
    case _ Extend{}: True{}
    case _ ZWJ{}: True{}
    case _ SpacingMark{}: True{}
    case Prepend{} _: True{}
    case _ _: False{}
def indicJoin(before: IndicState,after: IndicProperty) -> Bool:
  match before after:
    case LinkerSeen{} Consonant{}: True{}
    case _ _: False{}
def emojiJoin(before: EmojiState,pictographic: Bool) -> Bool:
  match before:
    case EmojiJoiner{}: pictographic
    case _: False{}
def regionalJoin(odd: Bool,current: Class) -> Bool:
  match current:
    case RegionalIndicator{}: odd
    case _: False{}

# Ordered GB3, GB4/5, GB6–9b, GB9c, GB11, GB12/13; otherwise GB999.
def continues(context: Context,value: Properties) -> Bool:
  match context value:
    case Context{CR{},_,_,_} Properties{LF{},_,_}: True{}
    case Context{previous,odd,emoji,indic} Properties{current,pictographic,conjunct}:
      +previous = {previous: Class}
      +current = {current: Class}
      Bool.not(control(previous) || control(current)) &&
        (hangul(previous,current) || attached(previous,current) || indicJoin(indic,conjunct) || emojiJoin(emoji,pictographic) || regionalJoin(odd,current))

def emojiAfter(previous: EmojiState,current: Class,pictographic: Bool) -> EmojiState:
  match previous current pictographic:
    case _ _ True{}: EmojiBase{}
    case EmojiBase{} Extend{} False{}: EmojiBase{}
    case EmojiBase{} ZWJ{} False{}: EmojiJoiner{}
    case _ _ _: NoEmoji{}
def indicAfter(previous: IndicState,current: IndicProperty) -> IndicState:
  match previous current:
    case _ Consonant{}: ConsonantSeen{}
    case previous IndicExtend{}: previous
    case ConsonantSeen{} Linker{}: LinkerSeen{}
    case LinkerSeen{} Linker{}: LinkerSeen{}
    case _ _: NoConjunct{}
def regionalAfter(odd: Bool,current: Class) -> Bool:
  match current:
    case RegionalIndicator{}: Bool.not(odd)
    case _: False{}
def advance(context: Context,value: Properties) -> Context:
  match context value:
    case Context{_,odd,emoji,indic} Properties{+current,pictographic,conjunct}:
      Context{current,regionalAfter(odd,current),emojiAfter(emoji,current,pictographic),indicAfter(indic,conjunct)}
def initial(value: Properties) -> Context: advance(Context{Other{},False{},NoEmoji{},NoConjunct{}},value)

# Only the current cluster is reversed. The remaining suffix is shared, never
# measured or copied, so repeated next calls traverse the string in linear time.
# The properties of the next character and whether it joins the cluster arrive
# as parameters, so the scan branches without allocating closures.
def headProperties(text: String) -> Properties:
  match text:
    case SNil{}: Properties{Other{},False{},NoIndic{}}
    case SCon{char,_}: properties(char)
def takeCluster(text: String,joins: Bool,+value: Properties,+context: Context,+reversed: String) -> String & String:
  match text joins:
    case SCon{+char,+rest} True{}:
      +after = advance(context,value)
      +following = headProperties(rest)
      takeCluster(rest,continues(after,following),following,after,SCon{char,reversed})
    case text _: (String.reverse(reversed),text)
def clusterAt(+text: String,+context: Context,reversed: String) -> String & String:
  +value = headProperties(text)
  takeCluster(text,continues(context,value),value,context,reversed)
def next(text: String) -> Maybe<&1,String & String>:
  match text:
    case SNil{}: None{}
    case SCon{+char,rest}: Some{clusterAt(rest,initial(properties(char)),SCon{char,""})}
type Split is Data: Split{cluster: String,reversed: List<&2,String>}
def grown(joins: Bool,char: Char,cluster: String,reversed: List<&2,String>) -> Split:
  match joins:
    case True{}: Split{SCon{char,cluster},reversed}
    case False{}: Split{SCon{char,""},String.reverse(cluster) <> reversed}
def split(text: String,+context: Context,state: Split) -> List<&2,String>:
  match text state:
    case SNil{} Split{cluster,reversed}: List.reverse(&2,String,String.reverse(cluster) <> reversed)
    case SCon{+char,rest} Split{cluster,reversed}:
      +value = properties(char)
      split(rest,advance(context,value),grown(continues(context,value),char,cluster,reversed))
def segments(text: String) -> List<&2,String>:
  match text:
    case SNil{}: Nil{}
    case SCon{+char,rest}: split(rest,initial(properties(char)),Split{SCon{char,""},Nil{}})
