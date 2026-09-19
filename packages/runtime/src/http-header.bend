import Base

# HTTP/Fetch header normalization at a typed string boundary. This is not a
# JavaScript object adapter. Each accepted value represents bytes 0..255.
type Header is Data:
  Header{name: String, value: String}

type HeaderError is Data:
  InvalidName{}
  InvalidValue{}
  NonByteValue{}

def between(+value: U32, minimum: U32, maximum: U32) -> Bool:
  U32.is_ge(value, minimum) && U32.is_le(value, maximum)

def punctuation(value: U32) -> Bool:
  match value:
    case 33: True{}
    case 35: True{}
    case 36: True{}
    case 37: True{}
    case 38: True{}
    case 39: True{}
    case 42: True{}
    case 43: True{}
    case 45: True{}
    case 46: True{}
    case 94: True{}
    case 95: True{}
    case 96: True{}
    case 124: True{}
    case 126: True{}
    case _: False{}

def token(+value: U32) -> Bool:
  between(value, 48, 57) || between(value, 65, 90) || between(value, 97, 122) || punctuation(value)

def validTokens(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: token(code) && validTokens(rest)

def validName(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code}, rest}: token(code) && validTokens(rest)

def lowercase(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, rest}:
      SCon{Chr{Bool.pick(U32, between(code, 65, 90), (code + 32 : U32), code)}, lowercase(rest)}

def checkedName(valid: Bool, name: String) -> Result<&2, &2, HeaderError, String>:
  match valid:
    case True{}: Done{lowercase(name)}
    case False{}: Fail{InvalidName{}}

def normalizeName(+name: String) -> Result<&2, &2, HeaderError, String>:
  checkedName(validName(name), name)

# HTTP whitespace includes CR/LF at the edges. Vertical tab, form feed and
# non-breaking space are not stripped. Interior NUL/CR/LF remain invalid.
def whitespace(value: U32) -> Bool:
  match value:
    case 9: True{}
    case 10: True{}
    case 13: True{}
    case 32: True{}
    case _: False{}

def trimLeading(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, +rest}:
      Bool.pick(String, whitespace(code), trimLeading(rest), SCon{Chr{code}, rest})

def trim(text: String) -> String:
  String.reverse(trimLeading(String.reverse(trimLeading(text))))

def byteValue(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: U32.is_le(code, 255) && byteValue(rest)

def validValue(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}:
      Bool.not(U32.is_eq(code, 0) || U32.is_eq(code, 10) || U32.is_eq(code, 13)) && validValue(rest)

def checkedValue(bytes: Bool, valid: Bool, value: String) -> Result<&2, &2, HeaderError, String>:
  match bytes valid:
    case False{} _: Fail{NonByteValue{}}
    case True{} False{}: Fail{InvalidValue{}}
    case True{} True{}: Done{value}

def normalizedValue(+value: String) -> Result<&2, &2, HeaderError, String>:
  checkedValue(byteValue(value), validValue(value), value)

def normalizeValue(value: String) -> Result<&2, &2, HeaderError, String>:
  normalizedValue(trim(value))

def combine(name: Result<&2, &2, HeaderError, String>, value: Result<&2, &2, HeaderError, String>) -> Result<&2, &2, HeaderError, Header>:
  match name value:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{key} Done{text}: Done{Header{key, text}}

def normalize(name: String, value: String) -> Result<&2, &2, HeaderError, Header>:
  combine(normalizeName(name), normalizeValue(value))
