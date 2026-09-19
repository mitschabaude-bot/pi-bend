import Base
import ./http-header.bend as H

# Parse one HTTP field line after CRLF framing. HTTP header values are byte
# strings, unlike Fetch's UTF-8 statusText. Validate before trimming so invalid
# control bytes cannot disappear as whitespace during normalization.
type FieldLine is Data:
  EndOfHeaders{}
  Field{header: H.Header}

type FieldError is Data:
  MissingColon{}
  InvalidFieldName{}
  InvalidFieldValue{}

def valueByte(+byte: U32) -> Bool:
  U32.is_eq(byte, 9) || (U32.is_ge(byte, 32) && U32.is_le(byte, 126)) || (U32.is_ge(byte, 128) && U32.is_le(byte, 255))

def validValue(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: valueByte(byte) && validValue(rest)

def byteString(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: SNil{}
    case byte <> rest: SCon{Chr{byte}, byteString(rest)}

# Received fields use Node Fetch's wire behavior: skip leading OWS but retain
# trailing OWS. Public Headers append/set normalization is a different boundary.
def named(result: Result<&2, &2, H.HeaderError, String>, value: String) -> Result<&2, &2, FieldError, FieldLine>:
  match result:
    case Fail{_}: Fail{InvalidFieldName{}}
    case Done{name}: Done{Field{H.Header{name, H.trimLeading(value)}}}

def checkedValue(valid: Bool, name: String, bytes: List<&2, U32>) -> Result<&2, &2, FieldError, FieldLine>:
  match valid:
    case False{}: Fail{InvalidFieldValue{}}
    case True{}: named(H.normalizeName(name), byteString(bytes))

def scan(bytes: List<&2, U32>, reversedName: String) -> Result<&2, &2, FieldError, FieldLine>:
  match bytes:
    case Nil{}: Fail{MissingColon{}}
    case 58 <> +rest: checkedValue(validValue(rest), String.reverse(reversedName), rest)
    case byte <> rest: scan(rest, SCon{Chr{byte}, reversedName})

def parse(bytes: List<&2, U32>) -> Result<&2, &2, FieldError, FieldLine>:
  match bytes:
    case Nil{}: Done{EndOfHeaders{}}
    case first <> rest: scan(first <> rest, SNil{})
