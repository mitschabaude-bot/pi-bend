import Base
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/text.bend as Text

type RgbColor is Data: RgbColor{r: U32,g: U32,b: U32}
type TerminalColorScheme is Data:
  Dark{}
  Light{}

# Framing is separate from color parsing: even an unrecognized, but complete,
# OSC 11 reply is consumed by the TUI rather than delivered as keyboard input.
def payload(text: String,reversed: String) -> Maybe<&2,String>:
  match text:
    case SCon{'\u{7}',SNil{}}: Some{String.reverse(reversed)}
    case SCon{'\u{1b}',SCon{'\\',SNil{}}}: Some{String.reverse(reversed)}
    case SCon{'\u{7}',_}: None{}
    case SCon{'\u{1b}',_}: None{}
    case SCon{char,rest}: payload(rest,SCon{char,reversed})
    case SNil{}: None{}
def oscPayload(data: String) -> Maybe<&2,String>:
  match data:
    case SCon{'\u{1b}',SCon{']',SCon{'1',SCon{'1',SCon{';',rest}}}}}: payload(rest,"")
    case _: None{}
def isOsc11BackgroundColorResponse(data: String) -> Bool:
  Bool.not(Maybe.is_none(&2,String,oscPayload(data)))

def trimStart(text: String) -> String:
  match text:
    case SCon{+char,+rest}: Bool.pick(Unit -> String,Text.whitespace(Char.to_u32(char)),_ => trimStart(rest),_ => SCon{char,rest})(Unit{})
    case SNil{}: ""
def trim(text: String) -> String: String.reverse(trimStart(String.reverse(trimStart(text))))

# X11 RGB channels have one to four hex digits. Scale with integer arithmetic
# so rounding is exact and malformed/oversized values cannot produce NaN.
def channelDigits(text: String,+value: U32,+maximum: U32,count: U32) -> Maybe<&2,U32>:
  match text count:
    case SNil{} 0: None{}
    case SNil{} _: Some{((value * 255 + maximum / 2) / maximum : U32)}
    case _ 4: None{}
    case SCon{char,rest} count:
      +code = Char.to_u32(Char.to_lower(char))
      +decimal = U32.is_ge(code,48) && U32.is_le(code,57)
      Bool.pick(Unit -> Maybe<&2,U32>,decimal || (U32.is_ge(code,97) && U32.is_le(code,102)),
        _ => channelDigits(rest,(value * 16 + code - Bool.pick(U32,decimal,48,87) : U32),(maximum * 16 + 15 : U32),(count + 1 : U32)),_ => None{})(Unit{})
def color(red: Maybe<&2,U32>,green: Maybe<&2,U32>,blue: Maybe<&2,U32>) -> Maybe<&2,RgbColor>:
  match red green blue:
    case Some{r} Some{g} Some{b}: Some{RgbColor{r,g,b}}
    case _ _ _: None{}
def channels(red: String,green: String,blue: String) -> Maybe<&2,RgbColor>:
  color(channelDigits(red,0,0,0),channelDigits(green,0,0,0),channelDigits(blue,0,0,0))
def hashColor(+hex: String,+width: Nat) -> Maybe<&2,RgbColor>:
  channels(String.take(hex,width),String.take(String.drop(hex,width),width),String.drop(hex,width * 2n))
def parts(values: List<&2,String>,alphaAllowed: Bool) -> Maybe<&2,RgbColor>:
  match values:
    case red <> green <> blue <> Nil{}: channels(red,green,blue)
    case red <> green <> blue <> alpha <> Nil{}:
      Bool.pick(Unit -> Maybe<&2,RgbColor>,alphaAllowed && Bool.not(Maybe.is_none(&2,U32,channelDigits(alpha,0,0,0))),_ => channels(red,green,blue),_ => None{})(Unit{})
    case _: None{}
def namedColor(+value: String) -> Maybe<&2,RgbColor>:
  +lower = String.to_lower(String.take(value,5n))
  Bool.pick(Unit -> Maybe<&2,RgbColor>,String.starts_with(lower,"rgba:"),_ => parts(Strings.split(String.drop(value,5n),'/'),True{}),
    _ => parts(Strings.split(Bool.pick(String,String.starts_with(lower,"rgb:"),String.drop(value,4n),value),'/'),False{}))(Unit{})
def colorValue(value: String) -> Maybe<&2,RgbColor>:
  match value:
    case SCon{'#',+hex}:
      +length = String.length(hex)
      Bool.pick(Unit -> Maybe<&2,RgbColor>,Nat.is_eq(length,6n),_ => hashColor(hex,2n),
        _ => Bool.pick(Unit -> Maybe<&2,RgbColor>,Nat.is_eq(length,12n),_ => hashColor(hex,4n),_ => None{})(Unit{}))(Unit{})
    case value: namedColor(value)
def parsePayload(value: Maybe<&2,String>) -> Maybe<&2,RgbColor>:
  match value:
    case None{}: None{}
    case Some{text}: colorValue(trim(text))
def parseOsc11BackgroundColor(data: String) -> Maybe<&2,RgbColor>:
  parsePayload(oscPayload(data))

def scheme(data: String,last: Maybe<&2,TerminalColorScheme>) -> Maybe<&2,TerminalColorScheme>:
  match data:
    case SNil{}: last
    case SCon{'\u{1b}',SCon{'[',SCon{'?',SCon{'9',SCon{'9',SCon{'7',SCon{';',SCon{'1',SCon{'n',rest}}}}}}}}}: scheme(rest,Some{Dark{}})
    case SCon{'\u{1b}',SCon{'[',SCon{'?',SCon{'9',SCon{'9',SCon{'7',SCon{';',SCon{'2',SCon{'n',rest}}}}}}}}}: scheme(rest,Some{Light{}})
    case _: None{}
def parseTerminalColorSchemeReport(data: String) -> Maybe<&2,TerminalColorScheme>: scheme(data,None{})
