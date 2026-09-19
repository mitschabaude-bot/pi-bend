import Base

# Scheme tokens exclude the colon. Input preprocessing and relative-URL fallback
# belong to the enclosing URL parser.
type Scheme is Data:
  Ftp{}
  File{}
  Http{}
  Https{}
  Ws{}
  Wss{}
  Other{name: String}

def alpha(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))

def lower(upper: Bool, code: U32) -> Char:
  match upper:
    case True{}: Chr{(code + 32 : U32)}
    case False{}: Chr{code}

def normalized(+code: U32) -> Char:
  lower(U32.is_ge(code, 65) && U32.is_le(code, 90), code)

def continuation(+code: U32) -> Bool:
  alpha(code) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 43) || U32.is_eq(code, 45) || U32.is_eq(code, 46)

def classify(text: String) -> Scheme:
  match text:
    case "ftp": Ftp{}
    case "file": File{}
    case "http": Http{}
    case "https": Https{}
    case "ws": Ws{}
    case "wss": Wss{}
    case other: Other{other}

def scan(text: String, valid: Bool, reversed: String) -> Maybe<&2, Scheme>:
  match text valid:
    case _ False{}: None{}
    case SNil{} True{}: Some{classify(String.reverse(reversed))}
    case SCon{Chr{+code}, rest} True{}: scan(rest, continuation(code), SCon{normalized(code), reversed})

def parse(text: String) -> Maybe<&2, Scheme>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: scan(rest, alpha(code), SCon{normalized(code), ""})

def serialize(scheme: Scheme) -> String:
  match scheme:
    case Ftp{}: "ftp"
    case File{}: "file"
    case Http{}: "http"
    case Https{}: "https"
    case Ws{}: "ws"
    case Wss{}: "wss"
    case Other{name}: name

def isSpecial(scheme: Scheme) -> Bool:
  match scheme:
    case Other{_}: False{}
    case _: True{}

def defaultPort(scheme: Scheme) -> Maybe<&2, U32>:
  match scheme:
    case Ftp{}: Some{21}
    case Http{}: Some{80}
    case Https{}: Some{443}
    case Ws{}: Some{80}
    case Wss{}: Some{443}
    case _: None{}
