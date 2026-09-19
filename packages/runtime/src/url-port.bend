import Base

# Parse a delimited port token, not a URL.port setter's numeric prefix. The
# authority parser handles delimiters and prohibits ports on file URLs.
type Error is Data:
  InvalidDigit{}
  OutOfRange{}

def bounded(fits: Bool, value: U32) -> Result<&2, &2, Error, U32>:
  match fits:
    case True{}: Done{value}
    case False{}: Fail{OutOfRange{}}

def addDigit(valid: Bool, +digit: U32, state: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, U32>:
  match valid state:
    case False{} _: Fail{InvalidDigit{}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{+value}: bounded(U32.is_le((value * 10 + digit : U32), 65535), (value * 10 + digit : U32))

def digits(text: String, state: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, U32>:
  match text state:
    case _ Fail{InvalidDigit{}}: Fail{InvalidDigit{}}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} result: digits(rest, addDigit(U32.is_ge(code, 48) && U32.is_le(code, 57), (code - 48 : U32), result))

def retained(isDefault: Bool, value: U32) -> Maybe<&2, U32>:
  match isDefault:
    case True{}: None{}
    case False{}: Some{value}

def normalize(default: Maybe<&2, U32>, result: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, Maybe<&2, U32>>:
  match default result:
    case _ Fail{error}: Fail{error}
    case None{} Done{value}: Done{Some{value}}
    case Some{expected} Done{+value}: Done{retained(U32.is_eq(value, expected), value)}

def parse(default: Maybe<&2, U32>, text: String) -> Result<&2, &2, Error, Maybe<&2, U32>>:
  match text:
    case SNil{}: Done{None{}}
    case other: normalize(default, digits(other, Done{0}))
