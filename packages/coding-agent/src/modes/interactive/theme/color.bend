import Base

type Rgb is Data: Rgb{red: Nat,green: Nat,blue: Nat}
type Color is Data: Default{} Indexed{index: Nat} RgbColor{rgb: Rgb}
type Mode is Data: TrueColor{} Palette256{}
# upstream theme.ts: truecolor when the terminal supports it, else 256 colours.
def modeFor(trueColor: Bool) -> Mode:
  match trueColor:
    case True{}: TrueColor{}
    case False{}: Palette256{}
type Error is Data: InvalidHex{value: String} InvalidIndex{value: Nat}

def digit(char: Char) -> Maybe<&2,Nat>:
  +value = U32.to_nat(Char.to_u32(char))
  Bool.pick(Maybe<&2,Nat>,Nat.is_ge(value,48n) && Nat.is_le(value,57n),Some{value - 48n},
    Bool.pick(Maybe<&2,Nat>,Nat.is_ge(value,65n) && Nat.is_le(value,70n),Some{value - 55n},
      Bool.pick(Maybe<&2,Nat>,Nat.is_ge(value,97n) && Nat.is_le(value,102n),Some{value - 87n},None{})))
def hexDigits(text: String,+count: Nat,+acc: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,Nat>,Nat.is_eq(count,6n),Some{acc},None{})
    case SCon{char,rest}:
      Bool.pick(Unit -> Maybe<&2,Nat>,Nat.is_lt(count,6n),
        _ => Maybe.bind(&2,Nat,Nat,digit(char),value => hexDigits(rest,count + 1n,acc * 16n + value)),_ => None{})(Unit{})
def packed(value: Maybe<&2,Nat>,source: String) -> Result<&2,&2,Error,Rgb>:
  match value:
    case None{}: Fail{InvalidHex{source}}
    case Some{+bits}: Done{Rgb{bits / 65536n,(bits / 256n) % 256n,bits % 256n}}
def parseHex(+text: String) -> Result<&2,&2,Error,Rgb>:
  match text:
    case SCon{'#',rest}: packed(hexDigits(rest,0n,0n),text)
    case _: Fail{InvalidHex{text}}
def indexed(+value: Nat) -> Result<&2,&2,Error,Color>:
  Bool.pick(Result<&2,&2,Error,Color>,Nat.is_le(value,255n),Done{Indexed{value}},Fail{InvalidIndex{value}})

def cubeIndex(+value: Nat) -> Nat:
  Bool.pick(Nat,Nat.is_le(value,47n),0n,
    Bool.pick(Nat,Nat.is_le(value,115n),1n,
      Bool.pick(Nat,Nat.is_le(value,155n),2n,
        Bool.pick(Nat,Nat.is_le(value,195n),3n,
          Bool.pick(Nat,Nat.is_le(value,235n),4n,5n)))))
def cubeLevel(index: Nat) -> Nat:
  match index:
    case 0n: 0n
    case 1n: 95n
    case 2n: 135n
    case 3n: 175n
    case 4n: 215n
    case _: 255n
def distance(+r: Nat,+g: Nat,+b: Nat,+x: Nat,+y: Nat,+z: Nat) -> Nat:
  +dr = Nat.max(r,x) - Nat.min(r,x)
  +dg = Nat.max(g,y) - Nat.min(g,y)
  +db = Nat.max(b,z) - Nat.min(b,z)
  299n * dr * dr + 587n * dg * dg + 114n * db * db
def grayIndex(gray: Nat) -> Nat:
  Nat.min(23n,(Nat.max(gray,8n) - 8n + 4n) / 10n)
def rgbTo256(value: Rgb) -> Nat:
  match value:
    case Rgb{+r,+g,+b}:
      +ri = cubeIndex(r)
      +gi = cubeIndex(g)
      +bi = cubeIndex(b)
      +gray = (299n * r + 587n * g + 114n * b + 500n) / 1000n
      +level = 8n + grayIndex(gray) * 10n
      +cube = 16n + 36n * ri + 6n * gi + bi
      +spread = Nat.max(r,Nat.max(g,b)) - Nat.min(r,Nat.min(g,b))
      Bool.pick(Nat,Nat.is_lt(spread,10n) && Nat.is_lt(distance(r,g,b,level,level,level),distance(r,g,b,cubeLevel(ri),cubeLevel(gi),cubeLevel(bi))),232n + grayIndex(gray),cube)

def ansi(prefix: String,reset: String,color: Color,mode: Mode) -> String:
  match color mode:
    case Default{} _: "\u{1b}[" ++ reset ++ "m"
    case Indexed{index} _: "\u{1b}[" ++ prefix ++ ";5;" ++ Nat.show(index) ++ "m"
    case RgbColor{Rgb{r,g,b}} TrueColor{}:
      "\u{1b}[" ++ prefix ++ ";2;" ++ Nat.show(r) ++ ";" ++ Nat.show(g) ++ ";" ++ Nat.show(b) ++ "m"
    case RgbColor{rgb} Palette256{}:
      "\u{1b}[" ++ prefix ++ ";5;" ++ Nat.show(rgbTo256(rgb)) ++ "m"
def foreground(color: Color,mode: Mode) -> String: ansi("38","39",color,mode)
def background(color: Color,mode: Mode) -> String: ansi("48","49",color,mode)
