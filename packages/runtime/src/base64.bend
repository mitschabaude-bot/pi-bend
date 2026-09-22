import Base

# RFC 4648 standard Base64. Whitespace and URL-safe alphabets are not implicit;
# enclosing formats (such as PEM) must handle their own framing/whitespace.
type Error is Data:
  InvalidByte{}
  InvalidEncoding{}

type Symbol is Data:
  Digit{value: U32}
  Padding{}
  Invalid{}

type Decoder is Data:
  First{reversed: List<&2,U32>}
  Second{a: U32, reversed: List<&2,U32>}
  Third{a: U32, b: U32, reversed: List<&2,U32>}
  Fourth{a: U32, b: U32, c: U32, reversed: List<&2,U32>}
  LastPadding{reversed: List<&2,U32>}
  Finished{reversed: List<&2,U32>}

def between(+value: U32, low: U32, high: U32) -> Bool:
  U32.is_ge(value,low) && U32.is_le(value,high)

def symbol(+value: U32) -> Symbol:
  Bool.pick(Symbol,between(value,65,90),Digit{(value - 65 : U32)},
    Bool.pick(Symbol,between(value,97,122),Digit{(value - 71 : U32)},
      Bool.pick(Symbol,between(value,48,57),Digit{(value + 4 : U32)},
        Bool.pick(Symbol,U32.is_eq(value,43),Digit{62},
          Bool.pick(Symbol,U32.is_eq(value,47),Digit{63},
            Bool.pick(Symbol,U32.is_eq(value,61),Padding{},Invalid{}))))))

def canonical(valid: Bool, state: Decoder) -> Result<&2,&2,Error,Decoder>:
  match valid:
    case True{}: Done{state}
    case False{}: Fail{InvalidEncoding{}}

def advance(state: Decoder, next: Symbol) -> Result<&2,&2,Error,Decoder>:
  match state next:
    case First{bytes} Digit{a}: Done{Second{a,bytes}}
    case Second{a,bytes} Digit{b}: Done{Third{a,b,bytes}}
    case Third{a,b,bytes} Digit{c}: Done{Fourth{a,b,c,bytes}}
    case Fourth{a,+b,+c,bytes} Digit{d}:
      Done{First{(U32.and(c,3) * 64 + d : U32) <> (U32.and(b,15) * 16 + c / 4 : U32) <> (a * 4 + b / 16 : U32) <> bytes}}
    case Third{a,+b,bytes} Padding{}:
      canonical(U32.is_eq(U32.and(b,15),0),LastPadding{(a * 4 + b / 16 : U32) <> bytes})
    case Fourth{a,+b,+c,bytes} Padding{}:
      canonical(U32.is_eq(U32.and(c,3),0),Finished{(U32.and(b,15) * 16 + c / 4 : U32) <> (a * 4 + b / 16 : U32) <> bytes})
    case LastPadding{bytes} Padding{}: Done{Finished{bytes}}
    case _ _: Fail{InvalidEncoding{}}

def finish(state: Decoder) -> Result<&2,&2,Error,List<&2,U32>>:
  match state:
    case First{bytes}: Done{List.reverse(&2,U32,bytes)}
    case Finished{bytes}: Done{List.reverse(&2,U32,bytes)}
    case _: Fail{InvalidEncoding{}}

def scan(text: String, result: Result<&2,&2,Error,Decoder>) -> Result<&2,&2,Error,List<&2,U32>>:
  match text result:
    case _ Fail{cause}: Fail{cause}
    case SNil{} Done{state}: finish(state)
    case SCon{Chr{value},rest} Done{state}: scan(rest,advance(state,symbol(value)))

def decode(text: String) -> Result<&2,&2,Error,List<&2,U32>>:
  scan(text,Done{First{Nil{}}})

# The encoder supplies sextets only; all resulting characters are ASCII.
def alphabet(+value: U32) -> Char:
  Chr{Bool.pick(U32,U32.is_lt(value,26),(value + 65 : U32),
    Bool.pick(U32,U32.is_lt(value,52),(value + 71 : U32),
      Bool.pick(U32,U32.is_lt(value,62),(value - 4 : U32),
        Bool.pick(U32,U32.is_eq(value,62),43,47))))}

def octets(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: U32.is_le(byte,255) && octets(rest)

def encoded(bytes: List<&2,U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +a <> Nil{}:
      String.reverse(SCon{'=',SCon{'=',SCon{alphabet((U32.and(a,3) * 16 : U32)),SCon{alphabet((a / 4 : U32)),reversed}}}})
    case +a <> +b <> Nil{}:
      String.reverse(SCon{'=',SCon{alphabet((U32.and(b,15) * 4 : U32)),SCon{alphabet((U32.and(a,3) * 16 + b / 16 : U32)),SCon{alphabet((a / 4 : U32)),reversed}}}})
    case +a <> +b <> +c <> rest:
      encoded(rest,SCon{alphabet(U32.and(c,63)),SCon{alphabet((U32.and(b,15) * 4 + c / 64 : U32)),SCon{alphabet((U32.and(a,3) * 16 + b / 16 : U32)),SCon{alphabet((a / 4 : U32)),reversed}}}})

def encodeValid(valid: Bool, bytes: List<&2,U32>) -> Result<&2,&2,Error,String>:
  match valid:
    case True{}: Done{encoded(bytes,"")}
    case False{}: Fail{InvalidByte{}}

def encode(+bytes: List<&2,U32>) -> Result<&2,&2,Error,String>:
  encodeValid(octets(bytes),bytes)
