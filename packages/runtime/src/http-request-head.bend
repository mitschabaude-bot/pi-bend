import Base
import ./http-header.bend as H
import ./http-field.bend as Field
import ./http-request-method.bend as Method

# Origin-form request heads for ordinary HTTP/1.1 Fetch connections. URL
# parsing/percent encoding and body framing are separate preparation steps.
type HeadError is Data:
  MethodError{error: Method.MethodError}
  InvalidTarget{}
  InvalidField{name: String}

type Head is Data:
  Head{method: String, bytes: List<&2, U32>}

def targetBytes(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: H.between(code, 33, 126) && Bool.not(U32.is_eq(code, 35)) && targetBytes(rest)

def validTarget(target: String) -> Bool:
  match target:
    case SCon{Chr{47}, rest}: targetBytes(rest)
    case _: False{}

# Header values are Latin-1 bytes on the wire, not UTF-8 encoded strings.
def prepend(text: String, rest: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SNil{}: rest
    case SCon{Chr{byte}, tail}: byte <> prepend(tail, rest)

def validFieldValue(value: String) -> Bool:
  match value:
    case SNil{}: True{}
    case SCon{Chr{byte}, rest}: Field.valueByte(byte) && validFieldValue(rest)

def fieldsChecked(valid: Bool, name: String, value: String, tail: Result<&2, &2, HeadError, List<&2, U32>>) -> Result<&2, &2, HeadError, List<&2, U32>>:
  match valid tail:
    case False{} _: Fail{InvalidField{name}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{bytes}: Done{prepend(name, 58 <> 32 <> prepend(value, 13 <> 10 <> bytes))}

def fields(values: List<&2, H.Header>) -> Result<&2, &2, HeadError, List<&2, U32>>:
  match values:
    case Nil{}: Done{13 <> 10 <> Nil{}}
    case H.Header{+name, +value} <> rest:
      fieldsChecked(H.validName(name) && validFieldValue(value), name, value, fields(rest))

def headed(+method: String, target: String, tail: Result<&2, &2, HeadError, List<&2, U32>>) -> Result<&2, &2, HeadError, Head>:
  match tail:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{Head{method, prepend(method, 32 <> prepend(target, prepend(" HTTP/1.1\r\n", bytes)))}}

def targeted(method: String, target: String, headers: List<&2, H.Header>, valid: Bool) -> Result<&2, &2, HeadError, Head>:
  match valid:
    case False{}: Fail{InvalidTarget{}}
    case True{}: headed(method, target, fields(headers))

def requested(method: Result<&2, &2, Method.MethodError, String>, +target: String, headers: List<&2, H.Header>) -> Result<&2, &2, HeadError, Head>:
  match method:
    case Fail{error}: Fail{MethodError{error}}
    case Done{normalized}: targeted(normalized, target, headers, validTarget(target))

# Serialize validated bytes without adding, sorting or coalescing fields.
# The request builder supplies Host and consistent framing headers.
def encode(method: String, target: String, headers: List<&2, H.Header>) -> Result<&2, &2, HeadError, Head>:
  requested(Method.normalize(method), target, headers)
