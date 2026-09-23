import Base
import ../../runtime/src/string.bend as Strings

# Keyboard state belongs to its terminal owner, never to process globals.
type Context is Data:
  Context{kittyProtocolActive: Bool,windowsTerminalSession: Bool}
type Modifiers is Data:
  Modifiers{shift: Bool,alt: Bool,ctrl: Bool,superKey: Bool}
type FunctionKey is Data:
  F1{}
  F2{}
  F3{}
  F4{}
  F5{}
  F6{}
  F7{}
  F8{}
  F9{}
  F10{}
  F11{}
  F12{}
type BaseKey is Data:
  Printable{char: Char}
  Function{key: FunctionKey}
  Escape{}
  Enter{}
  Tab{}
  Space{}
  Backspace{}
  Delete{}
  Insert{}
  Clear{}
  Home{}
  End{}
  PageUp{}
  PageDown{}
  Up{}
  Down{}
  Left{}
  Right{}
type KeyId is Data:
  KeyId{key: BaseKey,modifiers: Modifiers}
type KeyEventType is Data:
  Press{}
  Repeat{}
  Release{}
type Code is Data:
  RawCode{point: U32}
  NamedCode{key: BaseKey}
type ParsedSequence is Data:
  ParsedSequence{code: Code,shifted: Maybe<&2,U32>,baseLayout: Maybe<&2,U32>,modifiers: U32,event: KeyEventType}

def defaults() -> Context: Context{False{},False{}}
def setKittyProtocolActive(active: Bool,context: Context) -> Context:
  match context:
    case Context{_,windows}: Context{active,windows}
def isKittyProtocolActive(context: Context) -> Bool:
  match context:
    case Context{active,_}: active
def isWindowsTerminalSession(context: Context) -> Bool:
  match context:
    case Context{_,windows}: windows
def modifierBits(value: Modifiers) -> U32:
  match value:
    case Modifiers{shiftHeld,altHeld,ctrlHeld,superHeld}: (Bool.pick(U32,shiftHeld,1,0) + Bool.pick(U32,altHeld,2,0) + Bool.pick(U32,ctrlHeld,4,0) + Bool.pick(U32,superHeld,8,0) : U32)
def has(+mask: U32,bit: U32) -> Bool: U32.is_ne(U32.and(mask,bit),0)
def modifiers(+mask: U32) -> Modifiers: Modifiers{has(mask,1),has(mask,2),has(mask,4),has(mask,8)}
def plain(key: BaseKey) -> KeyId: KeyId{key,modifiers(0)}
def ctrl(key: BaseKey) -> KeyId: KeyId{key,modifiers(4)}
def shift(key: BaseKey) -> KeyId: KeyId{key,modifiers(1)}
def alt(key: BaseKey) -> KeyId: KeyId{key,modifiers(2)}
def super(key: BaseKey) -> KeyId: KeyId{key,modifiers(8)}
def ctrlShift(key: BaseKey) -> KeyId: KeyId{key,modifiers(5)}
def shiftCtrl(key: BaseKey) -> KeyId: KeyId{key,modifiers(5)}
def ctrlAlt(key: BaseKey) -> KeyId: KeyId{key,modifiers(6)}
def altCtrl(key: BaseKey) -> KeyId: KeyId{key,modifiers(6)}
def shiftAlt(key: BaseKey) -> KeyId: KeyId{key,modifiers(3)}
def altShift(key: BaseKey) -> KeyId: KeyId{key,modifiers(3)}
def ctrlSuper(key: BaseKey) -> KeyId: KeyId{key,modifiers(12)}
def superCtrl(key: BaseKey) -> KeyId: KeyId{key,modifiers(12)}
def shiftSuper(key: BaseKey) -> KeyId: KeyId{key,modifiers(9)}
def superShift(key: BaseKey) -> KeyId: KeyId{key,modifiers(9)}
def altSuper(key: BaseKey) -> KeyId: KeyId{key,modifiers(10)}
def superAlt(key: BaseKey) -> KeyId: KeyId{key,modifiers(10)}
def ctrlShiftAlt(key: BaseKey) -> KeyId: KeyId{key,modifiers(7)}
def ctrlShiftSuper(key: BaseKey) -> KeyId: KeyId{key,modifiers(13)}

def functionName(value: FunctionKey) -> String:
  match value:
    case F1{}: "f1"
    case F2{}: "f2"
    case F3{}: "f3"
    case F4{}: "f4"
    case F5{}: "f5"
    case F6{}: "f6"
    case F7{}: "f7"
    case F8{}: "f8"
    case F9{}: "f9"
    case F10{}: "f10"
    case F11{}: "f11"
    case F12{}: "f12"
def baseName(value: BaseKey) -> String:
  match value:
    case Printable{char}: SCon{char,SNil{}}
    case Function{key}: functionName(key)
    case Escape{}: "escape"
    case Enter{}: "enter"
    case Tab{}: "tab"
    case Space{}: "space"
    case Backspace{}: "backspace"
    case Delete{}: "delete"
    case Insert{}: "insert"
    case Clear{}: "clear"
    case Home{}: "home"
    case End{}: "end"
    case PageUp{}: "pageUp"
    case PageDown{}: "pageDown"
    case Up{}: "up"
    case Down{}: "down"
    case Left{}: "left"
    case Right{}: "right"
def formatKeyId(value: KeyId) -> String:
  match value:
    case KeyId{key,Modifiers{shiftHeld,altHeld,ctrlHeld,superHeld}}: Bool.pick(String,shiftHeld,"shift+","") ++ Bool.pick(String,ctrlHeld,"ctrl+","") ++ Bool.pick(String,altHeld,"alt+","") ++ Bool.pick(String,superHeld,"super+","") ++ baseName(key)
def between(+value: U32,minimum: U32,maximum: U32) -> Bool: U32.is_ge(value,minimum) && U32.is_le(value,maximum)
def letter(value: U32) -> Bool: between(value,97,122)
def digit(value: U32) -> Bool: between(value,48,57)
def symbol(value: U32) -> Bool:
  match value:
    case 96: True{}
    case 45: True{}
    case 61: True{}
    case 91: True{}
    case 93: True{}
    case 92: True{}
    case 59: True{}
    case 39: True{}
    case 44: True{}
    case 46: True{}
    case 47: True{}
    case 33: True{}
    case 64: True{}
    case 35: True{}
    case 36: True{}
    case 37: True{}
    case 94: True{}
    case 38: True{}
    case 42: True{}
    case 40: True{}
    case 41: True{}
    case 95: True{}
    case 43: True{}
    case 124: True{}
    case 126: True{}
    case 123: True{}
    case 125: True{}
    case 58: True{}
    case 60: True{}
    case 62: True{}
    case 63: True{}
    case _: False{}
def bindingCharacter(+point: U32) -> Bool: letter(point) || digit(point) || symbol(point)
def lower(+point: U32) -> U32: Bool.pick(U32,between(point,65,90),U32.add(point,32),point)
def lowercase(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{point},rest}: lowercase(rest,SCon{Chr{lower(point)},reversed})
def sameBase(left: BaseKey,right: BaseKey) -> Bool: Strings.equal(baseName(left),baseName(right))
def sameCode(left: Code,right: Code) -> Bool:
  match left right:
    case RawCode{a} RawCode{b}: U32.is_eq(a,b)
    case NamedCode{a} NamedCode{b}: sameBase(a,b)
    case _ _: False{}
def normalizedCode(point: U32) -> Code:
  match point:
    case 57399: RawCode{48}
    case 57400: RawCode{49}
    case 57401: RawCode{50}
    case 57402: RawCode{51}
    case 57403: RawCode{52}
    case 57404: RawCode{53}
    case 57405: RawCode{54}
    case 57406: RawCode{55}
    case 57407: RawCode{56}
    case 57408: RawCode{57}
    case 57409: RawCode{46}
    case 57410: RawCode{47}
    case 57411: RawCode{42}
    case 57412: RawCode{45}
    case 57413: RawCode{43}
    case 57415: RawCode{61}
    case 57416: RawCode{44}
    case 57417: NamedCode{Left{}}
    case 57418: NamedCode{Right{}}
    case 57419: NamedCode{Up{}}
    case 57420: NamedCode{Down{}}
    case 57421: NamedCode{PageUp{}}
    case 57422: NamedCode{PageDown{}}
    case 57423: NamedCode{Home{}}
    case 57424: NamedCode{End{}}
    case 57425: NamedCode{Insert{}}
    case 57426: NamedCode{Delete{}}
    case point: RawCode{point}
def shiftedIdentity(code: Code,mask: U32) -> Code:
  match code:
    case RawCode{+point}: RawCode{Bool.pick(U32,has(mask,1) && between(point,65,90),U32.add(point,32),point)}
    case named: named
def identity(point: U32,mask: U32) -> Code: shiftedIdentity(normalizedCode(point),mask)
def recognizedCode(code: Code,includeDigits: Bool) -> Bool:
  match code:
    case RawCode{+point}: letter(point) || symbol(point) || (includeDigits && digit(point))
    case _: False{}
def codeKey(code: Code) -> Maybe<&2,BaseKey>:
  match code:
    case NamedCode{key}: Some{key}
    case RawCode{27}: Some{Escape{}}
    case RawCode{9}: Some{Tab{}}
    case RawCode{13}: Some{Enter{}}
    case RawCode{57414}: Some{Enter{}}
    case RawCode{32}: Some{Space{}}
    case RawCode{127}: Some{Backspace{}}
    case RawCode{+point}: Bool.pick(Maybe<&2,BaseKey>,bindingCharacter(point),Some{Printable{Chr{point}}},None{})
def expectedCode(key: BaseKey) -> Code:
  match key:
    case Printable{Chr{point}}: RawCode{lower(point)}
    case Escape{}: RawCode{27}
    case Tab{}: RawCode{9}
    case Enter{}: RawCode{13}
    case Space{}: RawCode{32}
    case Backspace{}: RawCode{127}
    case key: NamedCode{key}

def legacyBinding(data: String) -> Maybe<&2,KeyId>:
  match data:
    case "\u{1b}[A": Some{KeyId{Up{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OA": Some{KeyId{Up{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[B": Some{KeyId{Down{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OB": Some{KeyId{Down{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[C": Some{KeyId{Right{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OC": Some{KeyId{Right{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[D": Some{KeyId{Left{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OD": Some{KeyId{Left{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[H": Some{KeyId{Home{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OH": Some{KeyId{Home{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[1~": Some{KeyId{Home{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[7~": Some{KeyId{Home{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[F": Some{KeyId{End{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OF": Some{KeyId{End{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[4~": Some{KeyId{End{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[8~": Some{KeyId{End{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[2~": Some{KeyId{Insert{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[3~": Some{KeyId{Delete{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[5~": Some{KeyId{PageUp{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[5~": Some{KeyId{PageUp{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[6~": Some{KeyId{PageDown{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[6~": Some{KeyId{PageDown{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[E": Some{KeyId{Clear{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OE": Some{KeyId{Clear{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OP": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[11~": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[A": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OQ": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[12~": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[B": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OR": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[13~": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[C": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OS": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[14~": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[D": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[15~": Some{KeyId{Function{F5{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[E": Some{KeyId{Function{F5{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[17~": Some{KeyId{Function{F6{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[18~": Some{KeyId{Function{F7{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[19~": Some{KeyId{Function{F8{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[20~": Some{KeyId{Function{F9{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[21~": Some{KeyId{Function{F10{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[23~": Some{KeyId{Function{F11{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[24~": Some{KeyId{Function{F12{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[a": Some{KeyId{Up{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[b": Some{KeyId{Down{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[c": Some{KeyId{Right{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[d": Some{KeyId{Left{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[e": Some{KeyId{Clear{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[2$": Some{KeyId{Insert{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[3$": Some{KeyId{Delete{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[5$": Some{KeyId{PageUp{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[6$": Some{KeyId{PageDown{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[7$": Some{KeyId{Home{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[8$": Some{KeyId{End{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}Oa": Some{KeyId{Up{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Ob": Some{KeyId{Down{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Oc": Some{KeyId{Right{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Od": Some{KeyId{Left{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Oe": Some{KeyId{Clear{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[2^": Some{KeyId{Insert{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[3^": Some{KeyId{Delete{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[5^": Some{KeyId{PageUp{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[6^": Some{KeyId{PageDown{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[7^": Some{KeyId{Home{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[8^": Some{KeyId{End{},Modifiers{False{},False{},True{},False{}}}}
    case _: None{}

def legacyParsed(data: String) -> Maybe<&2,KeyId>:
  match data:
    case "\u{1b}OA": Some{KeyId{Up{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OB": Some{KeyId{Down{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OC": Some{KeyId{Right{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OD": Some{KeyId{Left{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OH": Some{KeyId{Home{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OF": Some{KeyId{End{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[E": Some{KeyId{Clear{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OE": Some{KeyId{Clear{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}Oe": Some{KeyId{Clear{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[e": Some{KeyId{Clear{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[2~": Some{KeyId{Insert{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[2$": Some{KeyId{Insert{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[2^": Some{KeyId{Insert{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[3$": Some{KeyId{Delete{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[3^": Some{KeyId{Delete{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[[5~": Some{KeyId{PageUp{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[6~": Some{KeyId{PageDown{},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[a": Some{KeyId{Up{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[b": Some{KeyId{Down{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[c": Some{KeyId{Right{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[d": Some{KeyId{Left{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}Oa": Some{KeyId{Up{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Ob": Some{KeyId{Down{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Oc": Some{KeyId{Right{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}Od": Some{KeyId{Left{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[5$": Some{KeyId{PageUp{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[6$": Some{KeyId{PageDown{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[7$": Some{KeyId{Home{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[8$": Some{KeyId{End{},Modifiers{True{},False{},False{},False{}}}}
    case "\u{1b}[5^": Some{KeyId{PageUp{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[6^": Some{KeyId{PageDown{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[7^": Some{KeyId{Home{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}[8^": Some{KeyId{End{},Modifiers{False{},False{},True{},False{}}}}
    case "\u{1b}OP": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OQ": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OR": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}OS": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[11~": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[12~": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[13~": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[14~": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[A": Some{KeyId{Function{F1{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[B": Some{KeyId{Function{F2{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[C": Some{KeyId{Function{F3{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[D": Some{KeyId{Function{F4{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[[E": Some{KeyId{Function{F5{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[15~": Some{KeyId{Function{F5{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[17~": Some{KeyId{Function{F6{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[18~": Some{KeyId{Function{F7{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[19~": Some{KeyId{Function{F8{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[20~": Some{KeyId{Function{F9{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[21~": Some{KeyId{Function{F10{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[23~": Some{KeyId{Function{F11{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}[24~": Some{KeyId{Function{F12{}},Modifiers{False{},False{},False{},False{}}}}
    case "\u{1b}b": Some{KeyId{Left{},Modifiers{False{},True{},False{},False{}}}}
    case "\u{1b}f": Some{KeyId{Right{},Modifiers{False{},True{},False{},False{}}}}
    case "\u{1b}p": Some{KeyId{Up{},Modifiers{False{},True{},False{},False{}}}}
    case "\u{1b}n": Some{KeyId{Down{},Modifiers{False{},True{},False{},False{}}}}
    case _: None{}

# Bounded decimal parsing consumes the whole field and rejects overflow.
def decimalDigits(text: String,+current: U32,seen: Bool) -> Maybe<&2,U32>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,U32>,seen,Some{current},None{})
    case SCon{Chr{+point},rest}: Bool.pick(Unit -> Maybe<&2,U32>,digit(point) && (U32.is_lt(current,429496729) || (U32.is_eq(current,429496729) && U32.is_le(point,53))),_ => decimalDigits(rest,U32.add(U32.mul(current,10),U32.sub(point,48)),True{}),_ => None{})(Unit{})
def decimal(text: String) -> Maybe<&2,U32>: decimalDigits(text,0,False{})
def scalar(+point: U32) -> Bool: U32.is_le(point,1114111) && Bool.not(between(point,55296,57343))
def unicodeNumber(text: String) -> Maybe<&2,U32>:
  do Maybe<&2,U32>:
    +point : U32 <- decimal(text)
    Bool.pick(Maybe<&2,U32>,scalar(point),Some{point},None{})
def optionalNumber(text: String) -> Maybe<&2,Maybe<&2,U32>>:
  match text:
    case "": Some{None{}}
    case value: Maybe.map(&2,U32,Maybe<&2,U32>,point => Some{point},unicodeNumber(value))
def eventType(value: U32) -> KeyEventType:
  match value:
    case 2: Repeat{}
    case 3: Release{}
    case _: Press{}
type Identity is Data:
  Identity{point: U32,shifted: Maybe<&2,U32>,baseLayout: Maybe<&2,U32>,event: KeyEventType}
def identityFields(parts: List<&2,String>,allowEvent: Bool) -> Maybe<&2,Identity>:
  match parts:
    case code <> Nil{}:
      do Maybe<&2,Identity>:
        point : U32 <- unicodeNumber(code)
        return Identity{point,None{},None{},Press{}}
    case code <> shifted <> Nil{}:
      do Maybe<&2,Identity>:
        point : U32 <- unicodeNumber(code)
        alternate : Maybe<&2,U32> <- optionalNumber(shifted)
        return Identity{point,alternate,None{},Press{}}
    case code <> shifted <> base <> Nil{}:
      do Maybe<&2,Identity>:
        point : U32 <- unicodeNumber(code)
        alternate : Maybe<&2,U32> <- optionalNumber(shifted)
        layout : U32 <- unicodeNumber(base)
        return Identity{point,alternate,Some{layout},Press{}}
    case code <> shifted <> base <> event <> Nil{}:
      do Maybe<&2,Identity>:
        point : U32 <- unicodeNumber(code)
        alternate : Maybe<&2,U32> <- optionalNumber(shifted)
        layout : U32 <- unicodeNumber(base)
        kind : U32 <- decimal(event)
        Bool.pick(Maybe<&2,Identity>,allowEvent,Some{Identity{point,alternate,Some{layout},eventType(kind)}},None{})
    case _: None{}
type SequenceModifier is Data:
  SequenceModifier{mask: U32,event: KeyEventType}
def modifierValue(value: U32) -> Maybe<&2,U32>:
  match value:
    case 0: None{}
    case value: Some{U32.sub(value,1)}
def modifierFields(parts: List<&2,String>) -> Maybe<&2,SequenceModifier>:
  match parts:
    case text <> Nil{}:
      do Maybe<&2,SequenceModifier>:
        number : U32 <- decimal(text)
        mask : U32 <- modifierValue(number)
        return SequenceModifier{mask,Press{}}
    case text <> event <> Nil{}:
      do Maybe<&2,SequenceModifier>:
        number : U32 <- decimal(text)
        mask : U32 <- modifierValue(number)
        kind : U32 <- decimal(event)
        return SequenceModifier{mask,eventType(kind)}
    case _: None{}
def csiIdentity(value: Identity) -> ParsedSequence:
  match value:
    case Identity{point,shifted,base,kind}: ParsedSequence{normalizedCode(point),shifted,base,0,kind}
def csiModified(value: Identity,modifier: SequenceModifier) -> ParsedSequence:
  match value modifier:
    case Identity{point,shifted,base,_} SequenceModifier{mask,kind}: ParsedSequence{normalizedCode(point),shifted,base,mask,kind}
def csiUFields(parts: List<&2,String>) -> Maybe<&2,ParsedSequence>:
  match parts:
    case text <> Nil{}: Maybe.map(&2,Identity,ParsedSequence,csiIdentity,identityFields(Strings.split(text,':'),True{}))
    case text <> modifier <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        identity : Identity <- identityFields(Strings.split(text,':'),False{})
        flags : SequenceModifier <- modifierFields(Strings.split(modifier,':'))
        return csiModified(identity,flags)
    case _: None{}
def navigation(final: Char) -> Maybe<&2,BaseKey>:
  match final:
    case 'A': Some{Up{}}
    case 'B': Some{Down{}}
    case 'C': Some{Right{}}
    case 'D': Some{Left{}}
    case 'H': Some{Home{}}
    case 'F': Some{End{}}
    case _: None{}
def navigationModified(key: BaseKey,value: SequenceModifier) -> ParsedSequence:
  match value:
    case SequenceModifier{mask,kind}: ParsedSequence{NamedCode{key},None{},None{},mask,kind}
def navigationFields(parts: List<&2,String>,final: Char) -> Maybe<&2,ParsedSequence>:
  match parts:
    case "1" <> modifier <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        key : BaseKey <- navigation(final)
        flags : SequenceModifier <- modifierFields(Strings.split(modifier,':'))
        return navigationModified(key,flags)
    case _: None{}
def functional(number: U32) -> Maybe<&2,BaseKey>:
  match number:
    case 2: Some{Insert{}}
    case 3: Some{Delete{}}
    case 5: Some{PageUp{}}
    case 6: Some{PageDown{}}
    case 7: Some{Home{}}
    case 8: Some{End{}}
    case _: None{}
def functionalBare(parts: List<&2,String>) -> Maybe<&2,ParsedSequence>:
  match parts:
    case text <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        number : U32 <- decimal(text)
        key : BaseKey <- functional(number)
        return ParsedSequence{NamedCode{key},None{},None{},0,Press{}}
    case text <> event <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        number : U32 <- decimal(text)
        key : BaseKey <- functional(number)
        kind : U32 <- decimal(event)
        return ParsedSequence{NamedCode{key},None{},None{},0,eventType(kind)}
    case _: None{}
def functionalFields(parts: List<&2,String>) -> Maybe<&2,ParsedSequence>:
  match parts:
    case text <> Nil{}: functionalBare(Strings.split(text,':'))
    case text <> modifier <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        number : U32 <- decimal(text)
        key : BaseKey <- functional(number)
        flags : SequenceModifier <- modifierFields(Strings.split(modifier,':'))
        return navigationModified(key,flags)
    case _: None{}
def kittyBody(final: Char,body: String) -> Maybe<&2,ParsedSequence>:
  match final:
    case 'u': csiUFields(Strings.split(body,';'))
    case '~': functionalFields(Strings.split(body,';'))
    case final: navigationFields(Strings.split(body,';'),final)
def kittyReversed(text: String) -> Maybe<&2,ParsedSequence>:
  match text:
    case SCon{final,body}: kittyBody(final,String.reverse(body))
    case _: None{}
def parseKittySequence(data: String) -> Maybe<&2,ParsedSequence>:
  match data:
    case SCon{'\u{1b}',SCon{'[',rest}}: kittyReversed(String.reverse(rest))
    case _: None{}
def modifyFields(parts: List<&2,String>) -> Maybe<&2,ParsedSequence>:
  match parts:
    case "27" <> modifier <> code <> Nil{}:
      do Maybe<&2,ParsedSequence>:
        number : U32 <- decimal(modifier)
        mask : U32 <- modifierValue(number)
        point : U32 <- unicodeNumber(code)
        return ParsedSequence{RawCode{point},None{},None{},mask,Press{}}
    case _: None{}
def modifyReversed(text: String) -> Maybe<&2,ParsedSequence>:
  match text:
    case SCon{'~',body}: modifyFields(Strings.split(String.reverse(body),';'))
    case _: None{}
def parseModifyOtherKeysSequence(data: String) -> Maybe<&2,ParsedSequence>:
  match data:
    case SCon{'\u{1b}',SCon{'[',rest}}: modifyReversed(String.reverse(rest))
    case _: None{}

# Matching uses the requested identity, not parseKey's preferred spelling.
def baseMatches(value: Maybe<&2,U32>,expected: Code) -> Bool:
  match value expected:
    case Some{point} RawCode{wanted}: U32.is_eq(point,wanted)
    case _ _: False{}
def kittyMatches(value: Maybe<&2,ParsedSequence>,+expected: Code,+wanted: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{ParsedSequence{code,_,base,+mask,_}}:
      +actual = shiftedIdentity(code,mask)
      U32.is_eq(U32.and(mask,4294967103),wanted) && (sameCode(actual,shiftedIdentity(expected,wanted)) || (Bool.not(recognizedCode(actual,False{})) && baseMatches(base,expected)))
def modifyMatches(value: Maybe<&2,ParsedSequence>,+expected: Code,+wanted: U32,printable: Bool) -> Bool:
  match value:
    case None{}: False{}
    case Some{ParsedSequence{+code,_,_,+mask,_}}: U32.is_eq(mask,wanted) && Bool.pick(Bool,printable,Bool.not(U32.is_eq(wanted,0)) && sameCode(shiftedIdentity(code,mask),shiftedIdentity(expected,wanted)),sameCode(code,expected))
def legacyMatches(value: Maybe<&2,KeyId>,key: BaseKey,mask: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{KeyId{actual,flags}}: sameBase(actual,key) && U32.is_eq(modifierBits(flags),mask)
def rawBackspace(context: Context,data: String,mask: U32) -> Bool:
  match data:
    case "\u{7f}": U32.is_eq(mask,0)
    case "\u{8}": U32.is_eq(mask,Bool.pick(U32,isWindowsTerminalSession(context),4,0))
    case _: False{}
def rawControl(+point: U32) -> Maybe<&2,U32>:
  match point:
    case 45: Some{31}
    case 91: Some{27}
    case 92: Some{28}
    case 93: Some{29}
    case 95: Some{31}
    case point: Bool.pick(Maybe<&2,U32>,letter(point),Some{U32.and(point,31)},None{})
def controlMatches(value: Maybe<&2,U32>,data: String,prefix: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{point}: Strings.equal(data,prefix ++ SCon{Chr{point},SNil{}})
def printableLegacy(+context: Context,+data: String,+point: U32,mask: U32) -> Bool:
  match mask:
    case 0: Strings.equal(data,SCon{Chr{point},SNil{}})
    case 1: letter(point) && Strings.equal(data,SCon{Chr{U32.sub(point,32)},SNil{}})
    case 2: Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\u{1b}" ++ SCon{Chr{point},SNil{}})
    case 4: controlMatches(rawControl(point),data,"")
    case 6: Bool.not(isKittyProtocolActive(context)) && controlMatches(rawControl(point),data,"\u{1b}")
    case _: False{}
def enterLegacy(+context: Context,+data: String,mask: U32) -> Bool:
  match mask:
    case 0: Strings.equal(data,"\r") || (Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\n")) || Strings.equal(data,"\u{1b}OM")
    case 1: isKittyProtocolActive(context) && (Strings.equal(data,"\u{1b}\r") || Strings.equal(data,"\n"))
    case 2: Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\u{1b}\r")
    case _: False{}
def arrowAlt(context: Context,+data: String,key: BaseKey) -> Bool:
  match key:
    case Up{}: Strings.equal(data,"\u{1b}p")
    case Down{}: Strings.equal(data,"\u{1b}n")
    case Left{}: Strings.equal(data,"\u{1b}b") || (Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\u{1b}B"))
    case Right{}: Strings.equal(data,"\u{1b}f") || (Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\u{1b}F"))
    case _: False{}
def otherLegacy(context: Context,+data: String,+key: BaseKey,+mask: U32) -> Bool:
  legacyMatches(legacyBinding(data),key,mask) || (U32.is_eq(mask,2) && arrowAlt(context,data,key))
def specialLegacy(context: Context,+data: String,key: BaseKey,mask: U32) -> Bool:
  match key mask:
    case Escape{} 0: Strings.equal(data,"\u{1b}")
    case Tab{} 0: Strings.equal(data,"\t")
    case Tab{} 1: Strings.equal(data,"\u{1b}[Z")
    case Space{} 0: Strings.equal(data," ")
    case Space{} 4: Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\0")
    case Space{} 2: Bool.not(isKittyProtocolActive(context)) && Strings.equal(data,"\u{1b} ")
    case Enter{} mask: enterLegacy(context,data,mask)
    case Backspace{} 2: Strings.equal(data,"\u{1b}\u{7f}") || Strings.equal(data,"\u{1b}\u{8}")
    case Backspace{} mask: rawBackspace(context,data,mask)
    case key mask: otherLegacy(context,data,key,mask)
def inputMatches(context: Context,+data: String,+key: BaseKey,+mask: U32,+kitty: Maybe<&2,ParsedSequence>,+modify: Maybe<&2,ParsedSequence>) -> Bool:
  match key:
    case Printable{Chr{point}}:
      +point = lower(point)
      bindingCharacter(point) && (printableLegacy(context,data,point,mask) || kittyMatches(kitty,RawCode{point},mask) || modifyMatches(modify,RawCode{point},mask,True{}))
    case Escape{}: U32.is_eq(mask,0) && (specialLegacy(context,data,key,mask) || kittyMatches(kitty,RawCode{27},mask) || modifyMatches(modify,RawCode{27},mask,False{}))
    case Tab{}: specialLegacy(context,data,key,mask) || kittyMatches(kitty,RawCode{9},mask) || (U32.is_ne(mask,0) && modifyMatches(modify,RawCode{9},mask,False{}))
    case Enter{}: specialLegacy(context,data,key,mask) || kittyMatches(kitty,RawCode{13},mask) || kittyMatches(kitty,RawCode{57414},mask) || (U32.is_ne(mask,0) && modifyMatches(modify,RawCode{13},mask,False{}))
    case Space{}: specialLegacy(context,data,key,mask) || kittyMatches(kitty,RawCode{32},mask) || modifyMatches(modify,RawCode{32},mask,False{})
    case Backspace{}: specialLegacy(context,data,key,mask) || kittyMatches(kitty,RawCode{127},mask) || modifyMatches(modify,RawCode{127},mask,False{})
    case Clear{}: legacyMatches(legacyBinding(data),key,mask)
    case Function{_}: U32.is_eq(mask,0) && legacyMatches(legacyBinding(data),key,mask)
    case key: specialLegacy(context,data,key,mask) || kittyMatches(kitty,expectedCode(key),mask)
def matchesKey(context: Context,+data: String,value: KeyId) -> Bool:
  match value:
    case KeyId{key,flags}: inputMatches(context,data,key,modifierBits(flags),parseKittySequence(data),parseModifyOtherKeysSequence(data))

# parseKey chooses a single display identity; that is intentionally not the set
# of every binding that matches the input (Ctrl+H / Backspace is one example).
def formattedIdentity(key: Maybe<&2,BaseKey>,+mask: U32) -> Maybe<&2,KeyId>:
  match key:
    case None{}: None{}
    case Some{key}: Bool.pick(Maybe<&2,KeyId>,U32.is_eq(U32.and(mask,4294967088),0),Some{KeyId{key,modifiers(mask)}},None{})
def preferredCode(+code: Code,base: Maybe<&2,U32>) -> Code:
  Bool.pick(Code,recognizedCode(code,True{}),code,Maybe.default(&2,Code,Maybe.map(&2,U32,Code,point => RawCode{point},base),code))
def normalizedParsed(code: Code) -> Code:
  match code:
    case RawCode{point}: normalizedCode(point)
    case code: code
def parsedIdentity(value: ParsedSequence) -> Maybe<&2,KeyId>:
  match value:
    case ParsedSequence{code,_,base,+mask,_}: formattedIdentity(codeKey(preferredCode(shiftedIdentity(normalizedParsed(code),mask),base)),mask)
def legacyCharacter(data: String) -> Maybe<&2,KeyId>:
  match data:
    case SCon{Chr{+point},SNil{}}:
      Bool.pick(Maybe<&2,KeyId>,between(point,1,26),Some{ctrl(Printable{Chr{U32.add(point,96)}})},Bool.pick(Maybe<&2,KeyId>,between(point,32,126),Some{plain(Printable{Chr{point}})},None{}))
    case _: None{}
def legacyAlt(data: String) -> Maybe<&2,KeyId>:
  match data:
    case "\u{1b}\r": Some{alt(Enter{})}
    case "\u{1b} ": Some{alt(Space{})}
    case "\u{1b}B": Some{alt(Left{})}
    case "\u{1b}F": Some{alt(Right{})}
    case SCon{'\u{1b}',SCon{Chr{+point},SNil{}}}: Bool.pick(Maybe<&2,KeyId>,between(point,1,26),Some{ctrlAlt(Printable{Chr{U32.add(point,96)}})},Bool.pick(Maybe<&2,KeyId>,bindingCharacter(point),Some{alt(Printable{Chr{point}})},None{}))
    case _: None{}
def legacyRaw(context: Context,+data: String) -> Maybe<&2,KeyId>:
  match data:
    case "\u{1b}": Some{plain(Escape{})}
    case "\u{1c}": Some{ctrl(Printable{'\\'})}
    case "\u{1d}": Some{ctrl(Printable{']'})}
    case "\u{1f}": Some{ctrl(Printable{'-'})}
    case "\u{1b}\u{1b}": Some{ctrlAlt(Printable{'['})}
    case "\u{1b}\u{1c}": Some{ctrlAlt(Printable{'\\'})}
    case "\u{1b}\u{1d}": Some{ctrlAlt(Printable{']'})}
    case "\u{1b}\u{1f}": Some{ctrlAlt(Printable{'-'})}
    case "\t": Some{plain(Tab{})}
    case "\r": Some{plain(Enter{})}
    case "\n": Some{plain(Enter{})}
    case "\u{1b}OM": Some{plain(Enter{})}
    case "\0": Some{ctrl(Space{})}
    case " ": Some{plain(Space{})}
    case "\u{7f}": Some{plain(Backspace{})}
    case "\u{8}": Some{KeyId{Backspace{},modifiers(Bool.pick(U32,isWindowsTerminalSession(context),4,0))}}
    case "\u{1b}[Z": Some{shift(Tab{})}
    case "\u{1b}\u{7f}": Some{alt(Backspace{})}
    case "\u{1b}\u{8}": Some{alt(Backspace{})}
    case "\u{1b}[A": Some{plain(Up{})}
    case "\u{1b}[B": Some{plain(Down{})}
    case "\u{1b}[C": Some{plain(Right{})}
    case "\u{1b}[D": Some{plain(Left{})}
    case "\u{1b}[H": Some{plain(Home{})}
    case "\u{1b}[F": Some{plain(End{})}
    case _: Maybe.or(&2,KeyId,Bool.pick(Maybe<&2,KeyId>,isKittyProtocolActive(context),None{},legacyAlt(data)),legacyCharacter(data))
def parseLegacy(+context: Context,+data: String) -> Maybe<&2,KeyId>:
  Bool.pick(Maybe<&2,KeyId>,isKittyProtocolActive(context) && (Strings.equal(data,"\u{1b}\r") || Strings.equal(data,"\n")),Some{shift(Enter{})},Maybe.or(&2,KeyId,legacyParsed(data),legacyRaw(context,data)))
def parseAfterKitty(value: Maybe<&2,ParsedSequence>,context: Context,data: String) -> Maybe<&2,KeyId>:
  match value:
    case Some{value}: parsedIdentity(value)
    case None{}: parseLegacy(context,data)
def parseProtocol(value: Maybe<&2,ParsedSequence>,context: Context,+data: String) -> Maybe<&2,KeyId>:
  match value:
    case Some{value}: parsedIdentity(value)
    case None{}: parseAfterKitty(parseModifyOtherKeysSequence(data),context,data)
def parseKey(context: Context,+data: String) -> Maybe<&2,KeyId>: parseProtocol(parseKittySequence(data),context,data)

# Configuration names are parsed strictly; aliases normalize to one identity.
def baseCharacter(text: String) -> Maybe<&2,BaseKey>:
  match text:
    case SCon{Chr{+point},SNil{}}: Bool.pick(Maybe<&2,BaseKey>,bindingCharacter(point),Some{Printable{Chr{point}}},None{})
    case _: None{}
def baseIdentifier(text: String) -> Maybe<&2,BaseKey>:
  match text:
    case "escape": Some{Escape{}}
    case "enter": Some{Enter{}}
    case "tab": Some{Tab{}}
    case "space": Some{Space{}}
    case "backspace": Some{Backspace{}}
    case "delete": Some{Delete{}}
    case "insert": Some{Insert{}}
    case "clear": Some{Clear{}}
    case "home": Some{Home{}}
    case "end": Some{End{}}
    case "pageup": Some{PageUp{}}
    case "pagedown": Some{PageDown{}}
    case "up": Some{Up{}}
    case "down": Some{Down{}}
    case "left": Some{Left{}}
    case "right": Some{Right{}}
    case "f1": Some{Function{F1{}}}
    case "f2": Some{Function{F2{}}}
    case "f3": Some{Function{F3{}}}
    case "f4": Some{Function{F4{}}}
    case "f5": Some{Function{F5{}}}
    case "f6": Some{Function{F6{}}}
    case "f7": Some{Function{F7{}}}
    case "f8": Some{Function{F8{}}}
    case "f9": Some{Function{F9{}}}
    case "f10": Some{Function{F10{}}}
    case "f11": Some{Function{F11{}}}
    case "f12": Some{Function{F12{}}}
    case "esc": Some{Escape{}}
    case "return": Some{Enter{}}
    case other: baseCharacter(other)
def identifierModifier(text: String) -> Maybe<&2,U32>:
  match text:
    case "shift": Some{1}
    case "alt": Some{2}
    case "ctrl": Some{4}
    case "super": Some{8}
    case _: None{}
def identifierParts(parts: List<&2,String>,+mask: U32) -> Maybe<&2,KeyId>:
  match parts:
    case text <> Nil{}: Maybe.map(&2,BaseKey,KeyId,key => KeyId{key,modifiers(mask)},baseIdentifier(text))
    case "" <> "" <> Nil{}: Some{KeyId{Printable{'+'},modifiers(mask)}}
    case text <> rest:
      do Maybe<&2,KeyId>:
        +bit : U32 <- identifierModifier(text)
        Bool.pick(Unit -> Maybe<&2,KeyId>,has(mask,bit),_ => None{},_ => identifierParts(rest,U32.or(mask,bit)))(Unit{})
    case _: None{}
def parseKeyId(text: String) -> Maybe<&2,KeyId>: identifierParts(Strings.split(lowercase(text,""),'+'),0)

# Printable decoding is independent of binding identity and event filtering.
def printableCode(code: Code) -> Maybe<&2,String>:
  match code:
    case RawCode{+point}: Bool.pick(Maybe<&2,String>,scalar(point) && U32.is_ge(point,32),Some{SCon{Chr{point},SNil{}}},None{})
    case _: None{}
def kittyPrintableCode(+code: Code,shifted: Maybe<&2,U32>,+mask: U32) -> Maybe<&2,String>:
  Bool.pick(Maybe<&2,String>,U32.is_eq(U32.and(mask,4294967102),0),printableCode(Bool.pick(Code,has(mask,1),Maybe.default(&2,Code,Maybe.map(&2,U32,Code,normalizedCode,shifted),code),code)),None{})
def kittyPrintable(value: Maybe<&2,ParsedSequence>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{ParsedSequence{code,shifted,_,mask,_}}: kittyPrintableCode(code,shifted,mask)
def csiOnlyReversed(text: String) -> Maybe<&2,ParsedSequence>:
  match text:
    case SCon{'u',body}: csiUFields(Strings.split(String.reverse(body),';'))
    case _: None{}
def decodeKittyPrintable(data: String) -> Maybe<&2,String>:
  match data:
    case SCon{'\u{1b}',SCon{'[',rest}}: kittyPrintable(csiOnlyReversed(String.reverse(rest)))
    case _: None{}
def modifyPrintable(value: Maybe<&2,ParsedSequence>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{ParsedSequence{code,_,_,mask,_}}: Bool.pick(Maybe<&2,String>,U32.is_eq(U32.and(mask,4294967102),0),printableCode(code),None{})
def decodePrintableKey(+data: String) -> Maybe<&2,String>: Maybe.or(&2,String,decodeKittyPrintable(data),modifyPrintable(parseModifyOtherKeysSequence(data)))

# These helpers intentionally inspect the raw framing text. Bracketed paste
# suppresses event-like substrings, including ordinary pasted MAC addresses.
def prefix(text: String,needle: String) -> Bool:
  match text needle:
    case _ SNil{}: True{}
    case SCon{Chr{a},rest} SCon{Chr{b},tail}: U32.is_eq(a,b) && prefix(rest,tail)
    case _ _: False{}
def contains(+text: String,+needle: String) -> Bool:
  match text:
    case SNil{}: String.is_empty(needle)
    case SCon{_,rest}: Bool.pick(Unit -> Bool,prefix(text,needle),_ => True{},_ => contains(rest,needle))(Unit{})
def eventSuffix(value: Char) -> Bool:
  match value:
    case 'u': True{}
    case '~': True{}
    case 'A': True{}
    case 'B': True{}
    case 'C': True{}
    case 'D': True{}
    case 'H': True{}
    case 'F': True{}
    case _: False{}
def markerEnd(text: String) -> Bool:
  match text:
    case SCon{next,_}: eventSuffix(next)
    case _: False{}
def markerKind(text: String,kind: U32) -> Bool:
  match text:
    case SCon{Chr{actual},rest}: U32.is_eq(actual,kind) && markerEnd(rest)
    case _: False{}
def eventMarker(text: String,+kind: U32) -> Bool:
  match text:
    case SCon{':',+rest}: Bool.pick(Unit -> Bool,markerKind(rest,kind),_ => True{},_ => eventMarker(rest,kind))(Unit{})
    case SCon{_,rest}: eventMarker(rest,kind)
    case _: False{}
def isKeyRelease(+data: String) -> Bool: Bool.not(contains(data,"\u{1b}[200~")) && eventMarker(data,51)
def isKeyRepeat(+data: String) -> Bool: Bool.not(contains(data,"\u{1b}[200~")) && eventMarker(data,50)
