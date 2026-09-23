import Base
import ./color.bend as Color
import ../../../../../runtime/src/f64.bend as F
import ../../../../../runtime/src/text.bend as Text

type TerminalTheme is Data: Dark{} Light{}
type AutoSetting is Data: AutoSetting{light: String,dark: String}
type Source is Data: TerminalBackground{} ColorFgBg{} Fallback{}
type Confidence is Data: High{} Low{}
type Detection is Data: Detection{theme: TerminalTheme,source: Source,detail: String,confidence: Confidence}

def autoParts(parts: List<&2,String>) -> Maybe<&2,AutoSetting>:
  match parts:
    case light <> dark <> Nil{}:
      +light = Text.trim(light)
      +dark = Text.trim(dark)
      Bool.pick(Maybe<&2,AutoSetting>,String.is_empty(light) || String.is_empty(dark),None{},Some{AutoSetting{light,dark}})
    case _: None{}
def parseAutoThemeSetting(setting: Maybe<&2,String>) -> Maybe<&2,AutoSetting>:
  match setting:
    case None{}: None{}
    case Some{text}: autoParts(String.split(text,'/'))
def autoName(setting: Maybe<&2,AutoSetting>,original: Maybe<&2,String>,terminal: TerminalTheme) -> Maybe<&2,String>:
  match setting original terminal:
    case Some{AutoSetting{light,_}} _ Light{}: Some{light}
    case Some{AutoSetting{_,dark}} _ Dark{}: Some{dark}
    case None{} Some{+text} _:
      Bool.pick(Maybe<&2,String>,String.contains(text,"/"),None{},Some{text})
    case None{} None{} _: None{}
def resolveThemeSetting(+setting: Maybe<&2,String>,terminal: TerminalTheme) -> Maybe<&2,String>:
  autoName(parseAutoThemeSetting(setting),setting,terminal)

def ratio(numerator: U32,denominator: U32) -> F64:
  F.divide(F.fromU32(numerator),F.fromU32(denominator))
def linear(channel: Nat) -> F64:
  +value = F.divide(F.fromNat(channel),F.fromU32(255))
  Bool.pick(Unit -> F64,F.isAtMost(F.compare(value,ratio(3928,100000))),
    _ => F.divide(value,ratio(1292,100)),
    _ => F64.pow(F.divide(F.add(value,ratio(55,1000)),ratio(1055,1000)),ratio(24,10)))(Unit{})
def luminance(rgb: Color.Rgb) -> F64:
  match rgb:
    case Color.Rgb{red,green,blue}:
      F.add(F.add(F.multiply(ratio(2126,10000),linear(red)),F.multiply(ratio(7152,10000),linear(green))),F.multiply(ratio(722,10000),linear(blue)))
def getThemeForRgbColor(rgb: Color.Rgb) -> TerminalTheme:
  Bool.pick(TerminalTheme,F.isAtLeast(F.compare(luminance(rgb),ratio(1,2))),Light{},Dark{})

def basicColors() -> List<&2,Color.Rgb>:
  Color.Rgb{0n,0n,0n} <> Color.Rgb{128n,0n,0n} <> Color.Rgb{0n,128n,0n} <> Color.Rgb{128n,128n,0n} <>
  Color.Rgb{0n,0n,128n} <> Color.Rgb{128n,0n,128n} <> Color.Rgb{0n,128n,128n} <> Color.Rgb{192n,192n,192n} <>
  Color.Rgb{128n,128n,128n} <> Color.Rgb{255n,0n,0n} <> Color.Rgb{0n,255n,0n} <> Color.Rgb{255n,255n,0n} <>
  Color.Rgb{0n,0n,255n} <> Color.Rgb{255n,0n,255n} <> Color.Rgb{0n,255n,255n} <> Color.Rgb{255n,255n,255n} <> Nil{}
def cubeChannel(+index: Nat) -> Nat:
  Bool.pick(Nat,Nat.is_eq(index,0n),0n,55n + 40n * index)
def ansiRgb(+index: Nat) -> Color.Rgb:
  Bool.pick(Unit -> Color.Rgb,Nat.is_lt(index,16n),_ => Maybe.default(&2,Color.Rgb,List.get(&2,Color.Rgb,basicColors(),index),Color.Rgb{0n,0n,0n}),
    _ => Bool.pick(Unit -> Color.Rgb,Nat.is_lt(index,232n),
      _ => Color.Rgb{cubeChannel((index - 16n) / 36n),cubeChannel(((index - 16n) % 36n) / 6n),cubeChannel((index - 16n) % 6n)},
      _ => Color.Rgb{8n + 10n * (index - 232n),8n + 10n * (index - 232n),8n + 10n * (index - 232n)})(Unit{}))(Unit{})

def decimal(text: String,+acc: Nat,seen: Bool) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,Nat>,seen && Nat.is_le(acc,255n),Some{acc},None{})
    case SCon{char,rest}:
      +digit = U32.to_nat(Char.to_u32(char))
      Bool.pick(Unit -> Maybe<&2,Nat>,Nat.is_ge(digit,48n) && Nat.is_le(digit,57n) && Nat.is_le(acc,255n),
        _ => decimal(rest,acc * 10n + digit - 48n,True{}),_ => None{})(Unit{})
def lastIndex(parts: List<&2,String>,last: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match parts:
    case Nil{}: last
    case part <> rest:
      +parsed = decimal(Text.trim(part),0n,False{})
      lastIndex(rest,Maybe.default(&2,Maybe<&2,Nat>,Maybe.map(&2,Nat,Maybe<&2,Nat>,value => Some{value},parsed),last))
def colorFgBgIndex(value: String) -> Maybe<&2,Nat>:
  lastIndex(String.split(value,';'),None{})
def detectedIndex(value: Maybe<&2,Nat>) -> Detection:
  match value:
    case Some{+index}:
      Detection{getThemeForRgbColor(ansiRgb(index)),ColorFgBg{},"background color index " ++ Nat.show(index),High{}}
    case None{}: Detection{Dark{},Fallback{},"no terminal background hint found",Low{}}
def detectTerminalBackgroundFromEnv(value: Maybe<&2,String>) -> Detection:
  match value:
    case None{}: detectedIndex(None{})
    case Some{text}: detectedIndex(colorFgBgIndex(text))
def detectTerminalBackgroundColor(color: Maybe<&2,Color.Rgb>,env: Maybe<&2,String>) -> Detection:
  match color:
    case None{}: detectTerminalBackgroundFromEnv(env)
    case Some{Color.Rgb{+red,+green,+blue}}:
      Detection{getThemeForRgbColor(Color.Rgb{red,green,blue}),TerminalBackground{},"OSC 11 background rgb(" ++ Nat.show(red) ++ ", " ++ Nat.show(green) ++ ", " ++ Nat.show(blue) ++ ")",High{}}
def detectionTheme(detection: Detection) -> TerminalTheme:
  match detection:
    case Detection{theme,_,_,_}: theme
def detectTerminalThemeForAuto(scheme: Maybe<&2,TerminalTheme>,background: Maybe<&2,Color.Rgb>,env: Maybe<&2,String>) -> TerminalTheme:
  match scheme:
    case Some{theme}: theme
    case None{}: detectionTheme(detectTerminalBackgroundColor(background,env))
