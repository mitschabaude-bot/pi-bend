import Base
import ./u64.bend as W
import ./big-nat.bend as N
import ./utf8.bend as Utf8
import ./text.bend as Text
import ./url.bend as URL
import ./url.bend as Host
import ./calendar.bend as Calendar
import ./record.bend as R
import ./url.bend as Scheme
import ./url.bend as Serialize
import ./url.bend as Params

# HTTP/Fetch header normalization at a typed string boundary. This is not a
# JavaScript object adapter. Each accepted value represents bytes 0..255.
type Header is Data:
  Header{name: String, value: String}

type HeaderSyntaxError is Data:
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

def isTokenByte(+value: U32) -> Bool:
  between(value, 48, 57) || between(value, 65, 90) || between(value, 97, 122) || punctuation(value)

def validTokens(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: isTokenByte(code) && validTokens(rest)

def validName(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code}, rest}: isTokenByte(code) && validTokens(rest)

def checkedName(valid: Bool, name: String) -> Result<&2, &2, HeaderSyntaxError, String>:
  match valid:
    case True{}: Done{Text.asciiLower(name)}
    case False{}: Fail{InvalidName{}}

def normalizeName(+name: String) -> Result<&2, &2, HeaderSyntaxError, String>:
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

def trimHeader(text: String) -> String:
  String.reverse(trimLeading(String.reverse(trimLeading(text))))

def byteValue(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code}, rest}: U32.is_le(code, 255) && byteValue(rest)

def validValueHeader(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}:
      Bool.not(U32.is_eq(code, 0) || U32.is_eq(code, 10) || U32.is_eq(code, 13)) && validValueHeader(rest)

def checkedValueHeader(bytes: Bool, valid: Bool, value: String) -> Result<&2, &2, HeaderSyntaxError, String>:
  match bytes valid:
    case False{} _: Fail{NonByteValue{}}
    case True{} False{}: Fail{InvalidValue{}}
    case True{} True{}: Done{value}

def normalizedValue(+value: String) -> Result<&2, &2, HeaderSyntaxError, String>:
  checkedValueHeader(byteValue(value), validValueHeader(value), value)

def normalizeValue(value: String) -> Result<&2, &2, HeaderSyntaxError, String>:
  normalizedValue(trimHeader(value))

def combine(name: Result<&2, &2, HeaderSyntaxError, String>, value: Result<&2, &2, HeaderSyntaxError, String>) -> Result<&2, &2, HeaderSyntaxError, Header>:
  match name value:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{key} Done{text}: Done{Header{key, text}}

def normalize(name: String, value: String) -> Result<&2, &2, HeaderSyntaxError, Header>:
  combine(normalizeName(name), normalizeValue(value))

# Persistent server-side HTTP headers. Values retain append order; public
# iteration sorts names and coalesces values except for Set-Cookie.
type Headers is Data:
  Headers{fields: R.Record<List<&2, String>>}

def new() -> Headers: Headers{R.new(List<&2, String>)}

def extended(previous: Maybe<&2, List<&2, String>>, value: String) -> List<&2, String>:
  match previous:
    case None{}: value <> Nil{}
    case Some{values}: List.append(&2, String, values, value <> Nil{})

# Import an already validated field without caller-input normalization. Received
# HTTP fields can retain trailing whitespace that append(name, value) strips.
def appendField(headers: Headers, field: Header) -> Headers:
  match headers field:
    case Headers{+fields} Header{+name, value}:
      Headers{R.set(List<&2, String>, fields, name, extended(R.get(List<&2, String>, fields, name), value))}

def appendChecked(headers: Headers, field: Result<&2, &2, HeaderSyntaxError, Header>) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  match field:
    case Done{value}: Done{appendField(headers, value)}
    case Fail{error}: Fail{error}

def append(headers: Headers, name: String, value: String) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  appendChecked(headers, normalize(name, value))

def setChecked(headers: Headers, field: Result<&2, &2, HeaderSyntaxError, Header>) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  match headers field:
    case Headers{fields} Done{Header{name, value}}:
      Done{Headers{R.set(List<&2, String>, fields, name, value <> Nil{})}}
    case _ Fail{error}: Fail{error}

def set(headers: Headers, name: String, value: String) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  setChecked(headers, normalize(name, value))

def deleteChecked(headers: Headers, name: Result<&2, &2, HeaderSyntaxError, String>) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  match headers name:
    case Headers{fields} Done{key}: Done{Headers{R.remove(List<&2, String>, fields, key)}}
    case _ Fail{error}: Fail{error}

def delete(headers: Headers, name: String) -> Result<&2, &2, HeaderSyntaxError, Headers>:
  deleteChecked(headers, normalizeName(name))

def separator(name: String) -> String:
  match name:
    case "cookie": "; "
    case _: ", "

def joined(name: String, values: Maybe<&2, List<&2, String>>) -> Maybe<&2, String>:
  match values:
    case None{}: None{}
    case Some{items}: Some{String.join(items, separator(name))}

def getChecked(headers: Headers, name: Result<&2, &2, HeaderSyntaxError, String>) -> Result<&2, &2, HeaderSyntaxError, Maybe<&2, String>>:
  match headers name:
    case Headers{fields} Done{+key}: Done{joined(key, R.get(List<&2, String>, fields, key))}
    case _ Fail{error}: Fail{error}

def get(headers: Headers, name: String) -> Result<&2, &2, HeaderSyntaxError, Maybe<&2, String>>:
  getChecked(headers, normalizeName(name))

def found(result: Result<&2, &2, HeaderSyntaxError, Maybe<&2, String>>) -> Result<&2, &2, HeaderSyntaxError, Bool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{False{}}
    case Done{Some{_}}: Done{True{}}

def has(headers: Headers, name: String) -> Result<&2, &2, HeaderSyntaxError, Bool>:
  found(get(headers, name))

def valuesOrEmpty(values: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match values:
    case None{}: Nil{}
    case Some{items}: items

def getSetCookie(headers: Headers) -> List<&2, String>:
  match headers:
    case Headers{fields}: valuesOrEmpty(R.get(List<&2, String>, fields, "set-cookie"))

def ordered(result: (String & String) & Cmp) -> Bool:
  match result:
    case (_, order): Bool.not(Cmp.is_gt(order))

def nameOrder(left: R.Property<List<&2, String>>, right: R.Property<List<&2, String>>) -> Bool:
  match left right:
    case R.Property{a, _} R.Property{b, _}:
      ordered(String.cmp(a, b))

def cookieEntries(values: List<&2, String>) -> List<&2, Header>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Header{"set-cookie", value} <> cookieEntries(rest)

def fieldEntries(cookie: Bool, +name: String, values: List<&2, String>) -> List<&2, Header>:
  match cookie:
    case True{}: cookieEntries(values)
    case False{}: Header{name, String.join(values, separator(name))} <> Nil{}

def combined(fields: List<&2, R.Property<List<&2, String>>>) -> List<&2, Header>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+name, values} <> rest:
      List.append(&2, Header, fieldEntries(String.eq(name, "set-cookie"), name, values), combined(rest))

def entries(headers: Headers) -> List<&2, Header>:
  match headers:
    case Headers{fields}: combined(List.sort(~R.Property<List<&2, String>>, ~nameOrder, R.entries(List<&2, String>, fields)))

# Parse one HTTP field line after CRLF framing. HTTP header values are byte
# strings, unlike Fetch's UTF-8 statusText. Validate before trimming so invalid
# control bytes cannot disappear as whitespace during normalization.
type FieldLine is Data:
  EndOfHeaders{}
  Field{header: Header}

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
def named(result: Result<&2, &2, HeaderSyntaxError, String>, value: String) -> Result<&2, &2, FieldError, FieldLine>:
  match result:
    case Fail{_}: Fail{InvalidFieldName{}}
    case Done{name}: Done{Field{Header{name, trimLeading(value)}}}

def checkedValue(valid: Bool, name: String, bytes: List<&2, U32>) -> Result<&2, &2, FieldError, FieldLine>:
  match valid:
    case False{}: Fail{InvalidFieldValue{}}
    case True{}: named(normalizeName(name), byteString(bytes))

def scanField(bytes: List<&2, U32>, reversedName: String) -> Result<&2, &2, FieldError, FieldLine>:
  match bytes:
    case Nil{}: Fail{MissingColon{}}
    case 58 <> +rest: checkedValue(validValue(rest), String.reverse(reversedName), rest)
    case byte <> rest: scanField(rest, SCon{Chr{byte}, reversedName})

def parseField(bytes: List<&2, U32>) -> Result<&2, &2, FieldError, FieldLine>:
  match bytes:
    case Nil{}: Done{EndOfHeaders{}}
    case first <> rest: scanField(first <> rest, SNil{})

# Incremental octet-level CRLF framing. HTTP syntax validation belongs to the
# status/header parsers; this reader neither decodes UTF-8 nor folds lines.
# The bound counts payload bytes, excluding the terminating CRLF.
type LineReader is Data:
  LineReader{reversed: List<&2, U32>, remaining: Nat, carriageReturn: Bool}

type LineReadError is Data:
  LineTooLong{}
  LineInvalidByte{value: U32}
  IncompleteLine{}

type LineReadResult is Data:
  LineMore{reader: LineReader}
  Line{bytes: List<&2, U32>, rest: List<&2, U32>}
  LineFailed{error: LineReadError}

def newLine(limit: Nat) -> LineReader: LineReader{Nil{}, limit, False{}}

def bufferedLine(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> LineReadResult:
  match remaining:
    case Zero{}: LineFailed{LineTooLong{}}
    case Succ{capacity}: LineMore{LineReader{byte <> reversed, capacity, False{}}}

def ordinary(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> LineReadResult:
  match byte:
    case 13: LineMore{LineReader{reversed, remaining, True{}}}
    case other: bufferedLine(reversed, remaining, other)

# A pending CR is payload only once the following byte is known not to be LF.
# This lets an exactly-full line terminate across two separate chunks.
def afterCarriageReturn(reversed: List<&2, U32>, remaining: Nat, byte: U32) -> LineReadResult:
  match remaining:
    case Zero{}: LineFailed{LineTooLong{}}
    case Succ{capacity}: ordinary(13 <> reversed, capacity, byte)

def acceptedLine(reader: LineReader, byte: U32) -> LineReadResult:
  match reader byte:
    case LineReader{reversed, _, True{}} 10: Line{List.reverse(&2, U32, reversed), Nil{}}
    case LineReader{reversed, remaining, True{}} other: afterCarriageReturn(reversed, remaining, other)
    case LineReader{reversed, remaining, False{}} other: ordinary(reversed, remaining, other)

def checkedLine(valid: Bool, reader: LineReader, byte: U32) -> LineReadResult:
  match valid:
    case False{}: LineFailed{LineInvalidByte{byte}}
    case True{}: acceptedLine(reader, byte)

def consumeLine(reader: LineReader, +byte: U32) -> LineReadResult:
  checkedLine(U32.is_le(byte, 255), reader, byte)

def feedLine(bytes: List<&2, U32>, result: LineReadResult) -> LineReadResult:
  match bytes result:
    case rest Line{line, _}: Line{line, rest}
    case _ LineFailed{error}: LineFailed{error}
    case Nil{} LineMore{reader}: LineMore{reader}
    case head <> tail LineMore{reader}: feedLine(tail, consumeLine(reader, head))

def readLine(reader: LineReader, bytes: List<&2, U32>) -> LineReadResult:
  feedLine(bytes, LineMore{reader})

def finishLine(reader: LineReader) -> LineReadResult: LineFailed{IncompleteLine{}}

# Byte-preserving HTTP/1.x status-line syntax. The transport decides supported
# versions, informational handling and which status codes can become responses.
type StatusLine is Data:
  StatusLine{major: U32, minor: U32, status: U32, reasonBytes: List<&2, U32>}

type SyntaxError is Data:
  InvalidVersion{}
  InvalidStatus{}
  InvalidReason{}

def isAsciiDigit(+byte: U32) -> Bool: U32.is_ge(byte, 48) && U32.is_le(byte, 57)

def validReason(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: valueByte(byte) && validReason(rest)

# Node Fetch exposes UTF-8 decoded statusText; keep wire octets separately.
def statusText(line: StatusLine) -> String:
  match line:
    case StatusLine{_, _, _, bytes}: Utf8.decodeBytes(bytes)

def finishReason(valid: Bool, major: U32, minor: U32, status: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case True{}: Done{StatusLine{major, minor, status, bytes}}
    case False{}: Fail{InvalidReason{}}

def reason(major: U32, minor: U32, status: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    # Node Fetch also accepts an absent separator when the reason is empty.
    case Nil{}: Done{StatusLine{major, minor, status, Nil{}}}
    case 32 <> +rest: finishReason(validReason(rest), major, minor, status, rest)
    case _: Fail{InvalidStatus{}}

def checkedCode(valid: Bool, major: U32, minor: U32, code: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidStatus{}}
    case True{}: reason(major, minor, code, bytes)

def statusLine(major: U32, minor: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    case +a <> +b <> +c <> rest:
      checkedCode(isAsciiDigit(a) && isAsciiDigit(b) && isAsciiDigit(c), major, minor, ((a - 48) * 100 + (b - 48) * 10 + c - 48 : U32), rest)
    case _: Fail{InvalidStatus{}}

def checkedVersion(valid: Bool, major: U32, minor: U32, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidVersion{}}
    case True{}: statusLine((major - 48 : U32), (minor - 48 : U32), bytes)

def version(bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match bytes:
    case +major <> 46 <> +minor <> 32 <> rest:
      checkedVersion(isAsciiDigit(major) && isAsciiDigit(minor), major, minor, rest)
    case _: Fail{InvalidVersion{}}

def prefix(expected: List<&2, U32>, bytes: List<&2, U32>) -> Bool:
  match expected bytes:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case first <> tail head <> rest: U32.is_eq(first, head) && prefix(tail, rest)

def checkedPrefix(valid: Bool, bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  match valid:
    case False{}: Fail{InvalidVersion{}}
    case True{}: version(List.drop(&2, U32, bytes, 5n))

def parseStatus(+bytes: List<&2, U32>) -> Result<&2, &2, SyntaxError, StatusLine>:
  checkedPrefix(prefix(72 <> 84 <> 84 <> 80 <> 47 <> Nil{}, bytes), bytes)

type StatusReadError is Data:
  StatusFramingError{error: LineReadError}
  StatusSyntaxError{error: SyntaxError}

type StatusReadResult is Data:
  StatusMore{reader: LineReader}
  StatusComplete{status: StatusLine, rest: List<&2, U32>}
  StatusFailed{error: StatusReadError}

def statusParsed(result: Result<&2, &2, SyntaxError, StatusLine>, rest: List<&2, U32>) -> StatusReadResult:
  match result:
    case Fail{error}: StatusFailed{StatusSyntaxError{error}}
    case Done{status}: StatusComplete{status, rest}

def framedStatus(result: LineReadResult) -> StatusReadResult:
  match result:
    case LineMore{reader}: StatusMore{reader}
    case LineFailed{error}: StatusFailed{StatusFramingError{error}}
    case Line{bytes, rest}: statusParsed(parseStatus(bytes), rest)

def readStatus(reader: LineReader, bytes: List<&2, U32>) -> StatusReadResult:
  framedStatus(readLine(reader, bytes))

# Preserve ordered individual fields for later body-framing validation. A
# coalesced Headers view alone would erase duplicate framing declarations.
type ResponseHead is Data:
  ResponseHead{status: StatusLine, fields: List<&2, Header>}

type HeadPhase is Data:
  ReadingStatus{}
  ReadingFields{status: StatusLine, reversed: List<&2, Header>}

type Budget is Data:
  Budget{lineLimit: Nat, remainingBytes: Nat, remainingFields: Nat}

type HeadReader is Data:
  HeadReader{line: LineReader, phase: HeadPhase, budget: Budget}

type ReadError is Data:
  HeadFramingError{error: LineReadError}
  StatusError{error: SyntaxError}
  HeadFieldError{error: FieldError}
  HeadTooLong{}
  TooManyFields{}
  IncompleteHead{}

type HeadReadResult is Data:
  HeadMore{reader: HeadReader}
  HeadComplete{head: ResponseHead, rest: List<&2, U32>}
  HeadFailed{error: ReadError}

# Header-byte limits include status line, all delimiters and the empty line.
# Line limits exclude CRLF. Field limits count individual occurrences.
def newHead(+lineLimit: Nat, headLimit: Nat, fieldLimit: Nat) -> HeadReader:
  HeadReader{newLine(lineLimit), ReadingStatus{}, Budget{lineLimit, headLimit, fieldLimit}}

def nextLine(phase: HeadPhase, budget: Budget) -> HeadReadResult:
  match budget:
    case Budget{+lineLimit, bytes, fields}:
      HeadMore{HeadReader{newLine(lineLimit), phase, Budget{lineLimit, bytes, fields}}}

def parsedStatus(result: Result<&2, &2, SyntaxError, StatusLine>, budget: Budget) -> HeadReadResult:
  match result:
    case Fail{error}: HeadFailed{StatusError{error}}
    case Done{status}: nextLine(ReadingFields{status, Nil{}}, budget)

def addField(status: StatusLine, reversed: List<&2, Header>, field: Header, budget: Budget) -> HeadReadResult:
  match budget:
    case Budget{_, _, Zero{}}: HeadFailed{TooManyFields{}}
    case Budget{limit, bytes, Succ{fields}}:
      nextLine(ReadingFields{status, field <> reversed}, Budget{limit, bytes, fields})

def parsedField(result: Result<&2, &2, FieldError, FieldLine>, status: StatusLine, reversed: List<&2, Header>, budget: Budget) -> HeadReadResult:
  match result:
    case Fail{error}: HeadFailed{HeadFieldError{error}}
    case Done{EndOfHeaders{}}: HeadComplete{ResponseHead{status, List.reverse(&2, Header, reversed)}, Nil{}}
    case Done{Field{field}}: addField(status, reversed, field, budget)

def completedLine(bytes: List<&2, U32>, phase: HeadPhase, budget: Budget) -> HeadReadResult:
  match phase:
    case ReadingStatus{}: parsedStatus(parseStatus(bytes), budget)
    case ReadingFields{status, reversed}: parsedField(parseField(bytes), status, reversed, budget)

def framedHead(result: LineReadResult, phase: HeadPhase, budget: Budget) -> HeadReadResult:
  match result:
    case LineFailed{error}: HeadFailed{HeadFramingError{error}}
    case LineMore{reader}: HeadMore{HeadReader{reader, phase, budget}}
    case Line{bytes, _}: completedLine(bytes, phase, budget)

def consumeHead(reader: HeadReader, byte: U32) -> HeadReadResult:
  match reader:
    case HeadReader{_, _, Budget{_, Zero{}, _}}: HeadFailed{HeadTooLong{}}
    case HeadReader{line, phase, Budget{limit, Succ{remaining}, fields}}:
      framedHead(consumeLine(line, byte), phase, Budget{limit, remaining, fields})

def feed(bytes: List<&2, U32>, result: HeadReadResult) -> HeadReadResult:
  match bytes result:
    case rest HeadComplete{head, _}: HeadComplete{head, rest}
    case _ HeadFailed{error}: HeadFailed{error}
    case Nil{} HeadMore{reader}: HeadMore{reader}
    case byte <> rest HeadMore{reader}: feed(rest, consumeHead(reader, byte))

def readHead(reader: HeadReader, bytes: List<&2, U32>) -> HeadReadResult:
  feed(bytes, HeadMore{reader})

def finishHead(reader: HeadReader) -> HeadReadResult: HeadFailed{IncompleteHead{}}

def collectHead(fields: List<&2, Header>, headers: Headers) -> Headers:
  match fields:
    case Nil{}: headers
    case field <> rest: collectHead(rest, appendField(headers, field))

def headHeaders(head: ResponseHead) -> Headers:
  match head:
    case ResponseHead{_, fields}: collectHead(fields, new())

type RequestMethodError is Data:
  InvalidMethod{}
  ForbiddenMethod{}

# Fetch normalizes six common methods, preserving other token spellings.
def normalizedRequestMethod(lower: String, original: String) -> Result<&2, &2, RequestMethodError, String>:
  match lower:
    case "connect": Fail{ForbiddenMethod{}}
    case "trace": Fail{ForbiddenMethod{}}
    case "track": Fail{ForbiddenMethod{}}
    case "delete": Done{"DELETE"}
    case "get": Done{"GET"}
    case "head": Done{"HEAD"}
    case "options": Done{"OPTIONS"}
    case "post": Done{"POST"}
    case "put": Done{"PUT"}
    case _: Done{original}

def checkedRequestMethod(valid: Bool, +method: String) -> Result<&2, &2, RequestMethodError, String>:
  match valid:
    case False{}: Fail{InvalidMethod{}}
    case True{}: normalizedRequestMethod(Text.asciiLower(method), method)

def normalizeRequestMethod(+method: String) -> Result<&2, &2, RequestMethodError, String>:
  checkedRequestMethod(validName(method), method)

# Origin-form request heads for ordinary HTTP/1.1 Fetch connections. URL
# parsing/percent encoding and body framing are separate preparation steps.
type RequestHeadError is Data:
  RequestHeadMethodError{error: RequestMethodError}
  InvalidTarget{}
  InvalidField{name: String}

type Head is Data:
  Head{method: String, bytes: List<&2, U32>}

def targetBytes(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: between(code, 33, 126) && Bool.not(U32.is_eq(code, 35)) && targetBytes(rest)

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
    case SCon{Chr{byte}, rest}: valueByte(byte) && validFieldValue(rest)

def fieldsChecked(valid: Bool, name: String, value: String, tail: Result<&2, &2, RequestHeadError, List<&2, U32>>) -> Result<&2, &2, RequestHeadError, List<&2, U32>>:
  match valid tail:
    case False{} _: Fail{InvalidField{name}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{bytes}: Done{prepend(name, 58 <> 32 <> prepend(value, 13 <> 10 <> bytes))}

def requestHeadFields(values: List<&2, Header>) -> Result<&2, &2, RequestHeadError, List<&2, U32>>:
  match values:
    case Nil{}: Done{13 <> 10 <> Nil{}}
    case Header{+name, +value} <> rest:
      fieldsChecked(validName(name) && validFieldValue(value), name, value, requestHeadFields(rest))

def headedRequestHead(+method: String, target: String, tail: Result<&2, &2, RequestHeadError, List<&2, U32>>) -> Result<&2, &2, RequestHeadError, Head>:
  match tail:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{Head{method, prepend(method, 32 <> prepend(target, prepend(" HTTP/1.1\r\n", bytes)))}}

def targeted(method: String, target: String, headers: List<&2, Header>, valid: Bool) -> Result<&2, &2, RequestHeadError, Head>:
  match valid:
    case False{}: Fail{InvalidTarget{}}
    case True{}: headedRequestHead(method, target, requestHeadFields(headers))

def requested(method: Result<&2, &2, RequestMethodError, String>, +target: String, headers: List<&2, Header>) -> Result<&2, &2, RequestHeadError, Head>:
  match method:
    case Fail{error}: Fail{RequestHeadMethodError{error}}
    case Done{normalized}: targeted(normalized, target, headers, validTarget(target))

# Serialize validated bytes without adding, sorting or coalescing fields.
# The request builder supplies Host and consistent framing headers.
def encodeRequestHead(method: String, target: String, headers: List<&2, Header>) -> Result<&2, &2, RequestHeadError, Head>:
  requested(normalizeRequestMethod(method), target, headers)

type LengthError is Data:
  ContentLengthInvalidLength{}
  LengthOverflow{}
  DuplicateLength{}

type ContentLengthState is Data:
  Leading{}
  Digits{value: W.U64}
  Trailing{value: W.U64}

# floor((2^64 - 1) / 10), remainder 5. Check before modular arithmetic.
def fits(+value: W.U64, +digit: U32) -> Bool:
  Cmp.is_lt(W.compare(value, W.U64{429496729, 2576980377})) || (W.equal(value, W.U64{429496729, 2576980377}) && U32.is_le(digit, 5))

def accumulatedContentLength(valid: Bool, value: W.U64, digit: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  match valid:
    case False{}: Fail{LengthOverflow{}}
    case True{}: Done{Digits{W.add(W.multiply(value, W.fromU32(10)), W.fromU32(digit))}}

def addDigitContentLength(+value: W.U64, +digit: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  accumulatedContentLength(fits(value, digit), value, digit)

def digitStep(state: ContentLengthState, digit: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  match state:
    case Leading{}: Done{Digits{W.fromU32(digit)}}
    case Digits{value}: addDigitContentLength(value, digit)
    case Trailing{_}: Fail{ContentLengthInvalidLength{}}

# Node's received Content-Length parser permits SP after digits, but not HTAB.
# Leading OWS is accepted by its field parser before numeric interpretation.
def whitespaceStep(state: ContentLengthState, byte: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  match state byte:
    case Leading{} 32: Done{Leading{}}
    case Leading{} 9: Done{Leading{}}
    case Digits{value} 32: Done{Trailing{value}}
    case Trailing{value} 32: Done{Trailing{value}}
    case _ _: Fail{ContentLengthInvalidLength{}}

def stepContentLength(isDigit: Bool, state: ContentLengthState, byte: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  match isDigit:
    case True{}: digitStep(state, (byte - 48 : U32))
    case False{}: whitespaceStep(state, byte)

def consume(state: ContentLengthState, +byte: U32) -> Result<&2, &2, LengthError, ContentLengthState>:
  stepContentLength(U32.is_ge(byte, 48) && U32.is_le(byte, 57), state, byte)

def scanContentLength(text: String, result: Result<&2, &2, LengthError, ContentLengthState>) -> Result<&2, &2, LengthError, W.U64>:
  match text result:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{Leading{}}: Fail{ContentLengthInvalidLength{}}
    case SNil{} Done{Digits{value}}: Done{value}
    case SNil{} Done{Trailing{value}}: Done{value}
    case SCon{Chr{byte}, rest} Done{state}: scanContentLength(rest, consume(state, byte))

def parseContentLength(value: String) -> Result<&2, &2, LengthError, W.U64>:
  scanContentLength(value, Done{Leading{}})

def optional(result: Result<&2, &2, LengthError, W.U64>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Some{value}}

def observed(previous: Maybe<&2, W.U64>, value: String) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match previous:
    case None{}: optional(parseContentLength(value))
    case Some{_}: Fail{DuplicateLength{}}

def contentLengthField(matches: Bool, previous: Maybe<&2, W.U64>, value: String) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match matches:
    case False{}: Done{previous}
    case True{}: observed(previous, value)

def collectContentLength(fields: List<&2, Header>, result: Result<&2, &2, LengthError, Maybe<&2, W.U64>>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match fields result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: Done{value}
    case Header{name, value} <> rest Done{previous}:
      collectContentLength(rest, contentLengthField(String.eq(Text.asciiLower(name), "content-length"), previous, value))

def fromFields(fields: List<&2, Header>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  collectContentLength(fields, Done{None{}})

# A CRLF-framed chunk-size line. Extensions are validated and ignored, as in
# Fetch; no extension metadata or body-sized buffers are retained.
type Phase is Data:
  FirstDigit{}
  SizeDigits{}
  ExtensionStart{}
  ExtensionName{}
  ExtensionValue{}
  QuotedValue{}
  EscapedValue{}
  AfterQuote{}

type SizeError is Data:
  InvalidSize{}
  SizeOverflow{}
  InvalidExtension{}

type State is Data:
  State{phase: Phase, size: W.U64}

def hex(+byte: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 48) && U32.is_le(byte, 57), Some{(byte - 48 : U32)},
    Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 65) && U32.is_le(byte, 70), Some{(byte - 55 : U32)},
      Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 97) && U32.is_le(byte, 102), Some{(byte - 87 : U32)}, None{})))

def accumulated(fits: Bool, size: W.U64, digit: U32) -> Result<&2, &2, SizeError, State>:
  match fits:
    case False{}: Fail{SizeOverflow{}}
    case True{}: Done{State{SizeDigits{}, W.add(W.shiftLeft(size, 4n), W.fromU32(digit))}}

def addDigit(+size: W.U64, digit: U32) -> Result<&2, &2, SizeError, State>:
  accumulated(Bool.not(Cmp.is_gt(W.compare(size, W.U64{268435455, 4294967295}))), size, digit)

def tokenStep(valid: Bool, phase: Phase, size: W.U64) -> Result<&2, &2, SizeError, State>:
  match valid:
    case True{}: Done{State{phase, size}}
    case False{}: Fail{InvalidExtension{}}

def nameStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 61: Done{State{ExtensionValue{}, size}}
    case 59: Done{State{ExtensionStart{}, size}}
    case other: tokenStep(isTokenByte(other), ExtensionName{}, size)

def valueStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 34: Done{State{QuotedValue{}, size}}
    case 59: Done{State{ExtensionStart{}, size}}
    case other: tokenStep(isTokenByte(other), ExtensionValue{}, size)

# The installed Fetch parser accepts DEL inside an unescaped quoted value;
# its escaped-pair and header-field character classes are stricter.
def quotedByte(+byte: U32) -> Bool: valueByte(byte) || U32.is_eq(byte, 127)

def quotedStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 34: Done{State{AfterQuote{}, size}}
    case 92: Done{State{EscapedValue{}, size}}
    case other: tokenStep(quotedByte(other), QuotedValue{}, size)

def sizeStep(digit: Maybe<&2, U32>, first: Bool, size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match digit first byte:
    case Some{value} _ _: addDigit(size, value)
    case None{} False{} 59: Done{State{ExtensionStart{}, size}}
    case _ _ _: Fail{InvalidSize{}}

def step(state: State, +byte: U32) -> Result<&2, &2, SizeError, State>:
  match state:
    case State{FirstDigit{}, size}: sizeStep(hex(byte), True{}, size, byte)
    case State{SizeDigits{}, size}: sizeStep(hex(byte), False{}, size, byte)
    case State{ExtensionStart{}, size}: nameStep(size, byte)
    case State{ExtensionName{}, size}: nameStep(size, byte)
    case State{ExtensionValue{}, size}: valueStep(size, byte)
    case State{QuotedValue{}, size}: quotedStep(size, byte)
    case State{EscapedValue{}, size}: tokenStep(valueByte(byte), QuotedValue{}, size)
    case State{AfterQuote{}, size}:
      tokenStep(U32.is_eq(byte, 59), ExtensionStart{}, size)

def finishChunkSize(state: State) -> Result<&2, &2, SizeError, W.U64>:
  match state:
    case State{FirstDigit{}, _}: Fail{InvalidSize{}}
    case State{ExtensionStart{}, _}: Fail{InvalidExtension{}}
    case State{QuotedValue{}, _}: Fail{InvalidExtension{}}
    case State{EscapedValue{}, _}: Fail{InvalidExtension{}}
    case State{_, size}: Done{size}

def scan(bytes: List<&2, U32>, result: Result<&2, &2, SizeError, State>) -> Result<&2, &2, SizeError, W.U64>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{state}: finishChunkSize(state)
    case byte <> rest Done{state}: scan(rest, step(state, byte))

def parse(bytes: List<&2, U32>) -> Result<&2, &2, SizeError, W.U64>:
  scan(bytes, Done{State{FirstDigit{}, W.zero()}})

# Pure chunk transform for a body whose framing policy selected Content-Length.
# The retained state is only a counter; previously emitted bytes are not kept.
type FixedBodyReader is Data:
  FixedBodyReader{remaining: W.U64}

type FixedBodyError is Data:
  FixedBodyInvalidByte{value: U32}
  FixedBodyIncompleteBody{remaining: W.U64}

type FixedBodyReadResult is Data:
  FixedBodyMore{reader: FixedBodyReader, bytes: List<&2, U32>}
  FixedBodyComplete{bytes: List<&2, U32>, rest: List<&2, U32>}
  FixedBodyFailed{error: FixedBodyError}

type Buffer is Data:
  Buffer{remaining: W.U64, reversed: List<&2, U32>}

def newFixedBody(length: W.U64) -> FixedBodyReader: FixedBodyReader{length}

def isComplete(reader: FixedBodyReader) -> Bool:
  match reader:
    case FixedBodyReader{remaining}: W.equal(remaining, W.zero())

def accepted(valid: Bool, remaining: W.U64, reversed: List<&2, U32>, byte: U32) -> Result<&2, &2, FixedBodyError, Buffer>:
  match valid:
    case False{}: Fail{FixedBodyInvalidByte{byte}}
    case True{}: Done{Buffer{W.subtract(remaining, W.one()), byte <> reversed}}

def collectFixedBody(bytes: List<&2, U32>, result: Result<&2, &2, FixedBodyError, Buffer>) -> FixedBodyReadResult:
  match bytes result:
    case _ Fail{error}: FixedBodyFailed{error}
    case rest Done{Buffer{W.U64{0, 0}, reversed}}: FixedBodyComplete{List.reverse(&2, U32, reversed), rest}
    case Nil{} Done{Buffer{remaining, reversed}}: FixedBodyMore{FixedBodyReader{remaining}, List.reverse(&2, U32, reversed)}
    case +byte <> rest Done{Buffer{remaining, reversed}}:
      collectFixedBody(rest, accepted(U32.is_le(byte, 255), remaining, reversed, byte))

def readFixedBody(reader: FixedBodyReader, bytes: List<&2, U32>) -> FixedBodyReadResult:
  match reader:
    case FixedBodyReader{remaining}: collectFixedBody(bytes, Done{Buffer{remaining, Nil{}}})

def finishFixedBody(reader: FixedBodyReader) -> Result<&2, &2, FixedBodyError, Unit>:
  match reader:
    case FixedBodyReader{W.U64{0, 0}}: Done{Unit{}}
    case FixedBodyReader{remaining}: Fail{FixedBodyIncompleteBody{remaining}}

type Limits is Data:
  Limits{sizeLineBytes: Nat, trailerLineBytes: Nat, trailerBytes: Nat, trailerFields: Nat}

type ChunkedBodyPhase is Data:
  SizeLine{line: LineReader}
  Payload{remaining: W.U64}
  PayloadCR{}
  PayloadLF{}
  Trailers{line: LineReader, remainingBytes: Nat, remainingFields: Nat, reversed: List<&2, Header>}
  Ended{trailers: List<&2, Header>}

type ChunkedBodyReader is Data:
  ChunkedBodyReader{phase: ChunkedBodyPhase, limits: Limits}

type ChunkedBodyError is Data:
  ChunkedBodyInvalidByte{value: U32}
  LineError{error: LineReadError}
  ChunkedBodySizeError{error: SizeError}
  TrailerError{error: FieldError}
  InvalidDelimiter{}
  TrailerTooLong{}
  TooManyTrailers{}
  IncompleteBody{}

type ChunkedBodyReadResult is Data:
  ChunkedBodyMore{reader: ChunkedBodyReader, bytes: List<&2, U32>}
  ChunkedBodyComplete{bytes: List<&2, U32>, trailers: List<&2, Header>, rest: List<&2, U32>}
  ChunkedBodyFailed{error: ChunkedBodyError, bytes: List<&2, U32>}

# A single-byte state transition, separate from per-call output accumulation.
type Emission is Data:
  Emission{reader: ChunkedBodyReader, byte: Maybe<&2, U32>}

def sizeReader(limits: Limits) -> LineReader:
  match limits:
    case Limits{size, _, _, _}: newLine(size)

def newChunkedBody(+limits: Limits) -> ChunkedBodyReader: ChunkedBodyReader{SizeLine{sizeReader(limits)}, limits}

def silent(phase: ChunkedBodyPhase, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  Done{Emission{ChunkedBodyReader{phase, limits}, None{}}}

def startTrailers(+limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match limits:
    case Limits{_, line, bytes, fields}: silent(Trailers{newLine(line), bytes, fields, Nil{}}, limits)

def parsedSize(result: Result<&2, &2, SizeError, W.U64>, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match result:
    case Fail{error}: Fail{ChunkedBodySizeError{error}}
    case Done{W.U64{0, 0}}: startTrailers(limits)
    case Done{size}: silent(Payload{size}, limits)

def sizeLine(result: LineReadResult, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match result:
    case LineFailed{error}: Fail{LineError{error}}
    case LineMore{line}: silent(SizeLine{line}, limits)
    case Line{bytes, _}: parsedSize(parse(bytes), limits)

def afterPayload(remaining: W.U64) -> ChunkedBodyPhase:
  match remaining:
    case W.U64{0, 0}: PayloadCR{}
    case other: Payload{other}

def delimiter(valid: Bool, next: ChunkedBodyPhase, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match valid:
    case False{}: Fail{InvalidDelimiter{}}
    case True{}: silent(next, limits)

def trailerReader(limits: Limits) -> LineReader:
  match limits:
    case Limits{_, line, _, _}: newLine(line)

def addTrailer(field: Header, bytes: Nat, fields: Nat, reversed: List<&2, Header>, +limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match fields:
    case Zero{}: Fail{TooManyTrailers{}}
    case Succ{remaining}: silent(Trailers{trailerReader(limits), bytes, remaining, field <> reversed}, limits)

def parsedTrailer(result: Result<&2, &2, FieldError, FieldLine>, bytes: Nat, fields: Nat, reversed: List<&2, Header>, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match result:
    case Fail{error}: Fail{TrailerError{error}}
    case Done{EndOfHeaders{}}: silent(Ended{List.reverse(&2, Header, reversed)}, limits)
    case Done{Field{field}}: addTrailer(field, bytes, fields, reversed, limits)

def trailerLine(result: LineReadResult, bytes: Nat, fields: Nat, reversed: List<&2, Header>, limits: Limits) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match result:
    case LineFailed{error}: Fail{LineError{error}}
    case LineMore{line}: silent(Trailers{line, bytes, fields, reversed}, limits)
    case Line{line, _}: parsedTrailer(parseField(line), bytes, fields, reversed, limits)

def stepChunkedBody(reader: ChunkedBodyReader, byte: U32) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match reader:
    case ChunkedBodyReader{SizeLine{line}, limits}: sizeLine(consumeLine(line, byte), limits)
    case ChunkedBodyReader{Payload{remaining}, limits}:
      Done{Emission{ChunkedBodyReader{afterPayload(W.subtract(remaining, W.one())), limits}, Some{byte}}}
    case ChunkedBodyReader{PayloadCR{}, limits}: delimiter(U32.is_eq(byte, 13), PayloadLF{}, limits)
    case ChunkedBodyReader{PayloadLF{}, +limits}: delimiter(U32.is_eq(byte, 10), SizeLine{sizeReader(limits)}, limits)
    case ChunkedBodyReader{Trailers{_, Zero{}, _, _}, _}: Fail{TrailerTooLong{}}
    case ChunkedBodyReader{Trailers{line, Succ{bytes}, fields, reversed}, limits}: trailerLine(consumeLine(line, byte), bytes, fields, reversed, limits)
    case ChunkedBodyReader{Ended{trailers}, limits}: silent(Ended{trailers}, limits)

def checked(valid: Bool, reader: ChunkedBodyReader, byte: U32) -> Result<&2, &2, ChunkedBodyError, Emission>:
  match valid:
    case False{}: Fail{ChunkedBodyInvalidByte{byte}}
    case True{}: stepChunkedBody(reader, byte)

type ScanState is Data:
  Running{reader: ChunkedBodyReader, reversed: List<&2, U32>}
  Broken{error: ChunkedBodyError, reversed: List<&2, U32>}

def emitted(result: Result<&2, &2, ChunkedBodyError, Emission>, reversed: List<&2, U32>) -> ScanState:
  match result:
    case Fail{error}: Broken{error, reversed}
    case Done{Emission{reader, None{}}}: Running{reader, reversed}
    case Done{Emission{reader, Some{byte}}}: Running{reader, byte <> reversed}

def collect(bytes: List<&2, U32>, state: ScanState) -> ChunkedBodyReadResult:
  match bytes state:
    case _ Broken{error, reversed}: ChunkedBodyFailed{error, List.reverse(&2, U32, reversed)}
    case rest Running{ChunkedBodyReader{Ended{trailers}, _}, reversed}: ChunkedBodyComplete{List.reverse(&2, U32, reversed), trailers, rest}
    case Nil{} Running{reader, reversed}: ChunkedBodyMore{reader, List.reverse(&2, U32, reversed)}
    case +byte <> rest Running{reader, reversed}: collect(rest, emitted(checked(U32.is_le(byte, 255), reader, byte), reversed))

def readChunkedBody(reader: ChunkedBodyReader, bytes: List<&2, U32>) -> ChunkedBodyReadResult:
  collect(bytes, Running{reader, Nil{}})

def finishChunkedBody(reader: ChunkedBodyReader) -> Result<&2, &2, ChunkedBodyError, Unit>:
  match reader:
    case ChunkedBodyReader{Ended{_}, _}: Done{Unit{}}
    case _: Fail{IncompleteBody{}}

# Framing selection belongs to the response policy, not the decoder. Explicit
# an approved end-of-input ends UntilClose; transport policy must distinguish
# clean EOF, framing-compatible reset and failures before calling finish.
type Framing is Data:
  NoBody{}
  ContentLength{length: W.U64}
  ChunkedEncoding{}
  UntilClose{}

type Reader is Data:
  Empty{}
  FixedReader{reader: FixedBodyReader}
  ChunkedReader{reader: ChunkedBodyReader}
  CloseReader{}

type BodyError is Data:
  FixedError{error: FixedBodyError}
  ChunkedError{error: ChunkedBodyError}
  InvalidByte{value: U32}

type ReadResult is Data:
  More{reader: Reader, bytes: List<&2, U32>}
  Complete{bytes: List<&2, U32>, trailers: List<&2, Header>, rest: List<&2, U32>}
  Failed{error: BodyError, bytes: List<&2, U32>}

def newBody(framing: Framing, limits: Limits) -> Reader:
  match framing:
    case NoBody{}: Empty{}
    case ContentLength{length}: FixedReader{newFixedBody(length)}
    case ChunkedEncoding{}: ChunkedReader{newChunkedBody(limits)}
    case UntilClose{}: CloseReader{}

def fixed(result: FixedBodyReadResult) -> ReadResult:
  match result:
    case FixedBodyMore{reader, bytes}: More{FixedReader{reader}, bytes}
    case FixedBodyComplete{bytes, rest}: Complete{bytes, Nil{}, rest}
    case FixedBodyFailed{error}: Failed{FixedError{error}, Nil{}}

def chunked(result: ChunkedBodyReadResult) -> ReadResult:
  match result:
    case ChunkedBodyMore{reader, bytes}: More{ChunkedReader{reader}, bytes}
    case ChunkedBodyComplete{bytes, trailers, rest}: Complete{bytes, trailers, rest}
    case ChunkedBodyFailed{error, bytes}: Failed{ChunkedError{error}, bytes}

def invalidByte(bytes: List<&2, U32>) -> Maybe<&2, U32>:
  match bytes:
    case Nil{}: None{}
    case +byte <> rest: Bool.pick(Maybe<&2, U32>, U32.is_le(byte, 255), invalidByte(rest), Some{byte})

def closeBytes(invalid: Maybe<&2, U32>, bytes: List<&2, U32>) -> ReadResult:
  match invalid:
    case None{}: More{CloseReader{}, bytes}
    case Some{byte}: Failed{InvalidByte{byte}, Nil{}}

def read(reader: Reader, +bytes: List<&2, U32>) -> ReadResult:
  match reader:
    case Empty{}: Complete{Nil{}, Nil{}, bytes}
    case FixedReader{state}: fixed(readFixedBody(state, bytes))
    case ChunkedReader{state}: chunked(readChunkedBody(state, bytes))
    case CloseReader{}: closeBytes(invalidByte(bytes), bytes)

def fixedEOF(result: Result<&2, &2, FixedBodyError, Unit>) -> Result<&2, &2, BodyError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{FixedError{error}}

def chunkedEOF(result: Result<&2, &2, ChunkedBodyError, Unit>) -> Result<&2, &2, BodyError, Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{ChunkedError{error}}

def finish(reader: Reader) -> Result<&2, &2, BodyError, Unit>:
  match reader:
    case Empty{}: Done{Unit{}}
    case CloseReader{}: Done{Unit{}}
    case FixedReader{state}: fixedEOF(finishFixedBody(state))
    case ChunkedReader{state}: chunkedEOF(finishChunkedBody(state))

type Transfer is Data:
  NoTransferEncoding{}
  ChunkedTransfer{}
  OtherTransfer{}

type Fields is Data:
  Fields{length: Maybe<&2, W.U64>, transfer: Transfer}

type FramingFieldsFieldError is Data:
  FramingFieldsLengthError{error: LengthError}
  ConflictingFraming{}

def last(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case value <> Nil{}: value
    case _ <> rest: last(rest)

def spaces(text: String) -> String:
  match text:
    case SCon{' ', rest}: spaces(rest)
    case other: other

# This classifies the installed Fetch parser's wire framing. It is not a
# generic transfer-coding grammar or a compression decoder.
def classify(value: String) -> Transfer:
  token = Text.asciiLower(String.reverse(spaces(String.reverse(trimLeading(last(String.split(value, ',')))))))
  Bool.pick(Transfer, String.eq(token, "chunked"), ChunkedTransfer{}, OtherTransfer{})

def transferValue(previous: Transfer, value: String) -> Transfer:
  match value:
    case SNil{}: previous
    case other: classify(other)

def receivedTransfer(state: Fields, value: String) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  match state:
    case Fields{Some{_}, _}: Fail{ConflictingFraming{}}
    case Fields{None{}, previous}: Done{Fields{None{}, transferValue(previous, trimLeading(value))}}

def parsedLength(result: Result<&2, &2, LengthError, Maybe<&2, W.U64>>) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  match result:
    case Fail{error}: Fail{FramingFieldsLengthError{error}}
    case Done{value}: Done{Fields{value, NoTransferEncoding{}}}

def receivedLength(state: Fields, value: String) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  match state:
    case Fields{previous, NoTransferEncoding{}}: parsedLength(observed(previous, value))
    case _: Fail{ConflictingFraming{}}

def framingField(name: String, value: String, state: Fields) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  match name:
    case "content-length": receivedLength(state, value)
    case "transfer-encoding": receivedTransfer(state, value)
    case _: Done{state}

def collectFramingFields(fields: List<&2, Header>, state: Result<&2, &2, FramingFieldsFieldError, Fields>) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  match fields state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{result}: Done{result}
    case Header{name, value} <> rest Done{result}: collectFramingFields(rest, framingField(Text.asciiLower(name), value, result))

# Consume validated received fields, before they are coalesced for public use.
def analyze(fields: List<&2, Header>) -> Result<&2, &2, FramingFieldsFieldError, Fields>:
  collectFramingFields(fields, Done{Fields{None{}, NoTransferEncoding{}}})

# Use only after method/status policy determines that this response carries a
# payload. HEAD, informational, upgrade and null-body decisions are separate.
def bodyFraming(fields: Fields) -> Framing:
  match fields:
    case Fields{_, ChunkedTransfer{}}: ChunkedEncoding{}
    case Fields{Some{size}, NoTransferEncoding{}}: ContentLength{size}
    case _: UntilClose{}

type Transport is Data:
  Plaintext{}
  TLS{}

type Endpoint is Data:
  Endpoint{transport: Transport, host: Host.Host, port: U32, authority: String, target: String}

type EndpointError is Data:
  UnsupportedScheme{}
  Credentials{}
  InvalidHost{}
  InvalidPath{}

def urlPort(value: Maybe<&2, U32>, default: U32) -> U32:
  match value:
    case None{}: default
    case Some{number}: number

# A present empty query contributes '?'. URL.search alone cannot preserve this
# distinction. Fragments never belong to an HTTP request target.
def urlTarget(parts: List<&2, String>, query: Maybe<&2, String>) -> String:
  String.reverse(Serialize.component(query, '?', Serialize.serializeSegments(parts, "")))

def withPath(transport: Transport, +host: Host.Host, +number: Maybe<&2, U32>, default: U32, urlPath: URL.RecordPath, query: Maybe<&2, String>) -> Result<&2, &2, EndpointError, Endpoint>:
  match urlPath:
    case URL.Hierarchical{first <> rest}: Done{Endpoint{transport, host, urlPort(number, default), String.reverse(Serialize.serializePort(number, Serialize.appendSerialize(Host.serializeHost(host), ""))), urlTarget(first <> rest, query)}}
    case _: Fail{InvalidPath{}}

def withHost(transport: Transport, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, default: U32, urlPath: URL.RecordPath, query: Maybe<&2, String>) -> Result<&2, &2, EndpointError, Endpoint>:
  match host:
    case None{}: Fail{InvalidHost{}}
    case Some{Host.Empty{}}: Fail{InvalidHost{}}
    case Some{Host.Opaque{_}}: Fail{InvalidHost{}}
    case Some{Host.Domain{SNil{}}}: Fail{InvalidHost{}}
    case Some{value}: withPath(transport, value, number, default, urlPath, query)

def withCredentials(transport: Transport, username: String, password: String, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, default: U32, urlPath: URL.RecordPath, query: Maybe<&2, String>) -> Result<&2, &2, EndpointError, Endpoint>:
  match username password:
    case SNil{} SNil{}: withHost(transport, host, number, default, urlPath, query)
    case _ _: Fail{Credentials{}}

def withScheme(scheme: Scheme.Scheme, username: String, password: String, host: Maybe<&2, Host.Host>, number: Maybe<&2, U32>, urlPath: URL.RecordPath, query: Maybe<&2, String>) -> Result<&2, &2, EndpointError, Endpoint>:
  match scheme:
    case Scheme.Http{}: withCredentials(Plaintext{}, username, password, host, number, 80, urlPath, query)
    case Scheme.Https{}: withCredentials(TLS{}, username, password, host, number, 443, urlPath, query)
    case _: Fail{UnsupportedScheme{}}

# Input is a normalized URL record produced by the URL parsers. Keep the host
# typed for later DNS/socket selection; authority includes IPv6 brackets and
# only a non-default port. This projection does not open sockets, apply Fetch's
# blocked-port policy, choose proxy routing, or replace caller-supplied headers.
def urlPrepare(value: URL.URL) -> Result<&2, &2, EndpointError, Endpoint>:
  match value:
    case URL.URL{scheme, username, password, host, number, urlPath, query, _}: withScheme(scheme, username, password, host, number, urlPath, query)

type ExchangePlanError is Data:
  TLSRequired{}
  InvalidReadSize{}

type Plan<-Request: Data> is Data:
  Rejected{error: ExchangePlanError}
  Start{host: Host.Host, port: U32, request: Request, maximum: U32}

# This cleartext adapter must never send HTTP bytes on a TLS endpoint. Request
# preparation has already supplied its authority/target; dialing uses host/port.
def prepareExchangePlan(-Request: Data, endpoint: Endpoint, request: Request, maximum: U32) -> Plan<Request>:
  match endpoint maximum:
    case Endpoint{TLS{}, _, _, _, _} _: Rejected{TLSRequired{}}
    case Endpoint{Plaintext{}, _, _, _, _} 0: Rejected{InvalidReadSize{}}
    case Endpoint{Plaintext{}, host, port, _, _} size: Start{host, port, request, size}

# Syntax recognition only. Calendar validity, timezone policy and resolution
# of two-digit years remain explicit responsibilities of the date interpreter.
type Format is Data:
  ImfFixdate{}
  Rfc850{}
  Asctime{}

type ClockFields is Data:
  ClockFields{hour: U32, minute: U32, second: U32}

type DateFields is Data:
  DateFields{format: Format, weekdayValue: U32, year: U32, month: U32, day: U32, clockValue: ClockFields}

def digits(count: Nat, text: String, value: U32) -> Maybe<&2, U32>:
  match count text:
    case Zero{} SNil{}: Some{value}
    case Succ{rest} SCon{Chr{+code}, tail}:
      Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), digits(rest, tail, (value * 10 + code - 48 : U32)), None{})
    case _ _: None{}

def find(+text: String, names: List<&2, String>, +index: U32) -> Maybe<&2, U32>:
  match names:
    case Nil{}: None{}
    case name <> rest: Bool.pick(Maybe<&2, U32>, String.eq(text, name), Some{index}, find(text, rest, (index + 1 : U32)))

def parseMonth(text: String) -> Maybe<&2, U32>:
  find(text, "Jan" <> "Feb" <> "Mar" <> "Apr" <> "May" <> "Jun" <> "Jul" <> "Aug" <> "Sep" <> "Oct" <> "Nov" <> "Dec" <> Nil{}, 1)

def parseWeekday(text: String) -> Maybe<&2, U32>:
  find(text, "Mon" <> "Tue" <> "Wed" <> "Thu" <> "Fri" <> "Sat" <> "Sun" <> Nil{}, 1)

def longWeekday(text: String) -> Maybe<&2, U32>:
  find(text, "Monday" <> "Tuesday" <> "Wednesday" <> "Thursday" <> "Friday" <> "Saturday" <> "Sunday" <> Nil{}, 1)

def commaReversed(text: String) -> String:
  match text:
    case SCon{Chr{44}, rest}: String.reverse(rest)
    case _: ""

def withoutComma(text: String) -> String: commaReversed(String.reverse(text))

def clockFields(hour: Maybe<&2, U32>, minute: Maybe<&2, U32>, second: Maybe<&2, U32>) -> Maybe<&2, ClockFields>:
  match hour minute second:
    case Some{h} Some{m} Some{s}: Some{ClockFields{h, m, s}}
    case _ _ _: None{}

def clockParts(parts: List<&2, String>) -> Maybe<&2, ClockFields>:
  match parts:
    case hour <> minute <> second <> Nil{}: clockFields(digits(2n, hour, 0), digits(2n, minute, 0), digits(2n, second, 0))
    case _: None{}

def parseClock(text: String) -> Maybe<&2, ClockFields>: clockParts(String.split(text, ':'))

def dateFields(format: Format, weekdayValue: Maybe<&2, U32>, year: Maybe<&2, U32>, month: Maybe<&2, U32>, day: Maybe<&2, U32>, clockValue: Maybe<&2, ClockFields>) -> Maybe<&2, DateFields>:
  match weekdayValue year month day clockValue:
    case Some{w} Some{y} Some{m} Some{d} Some{t}: Some{DateFields{format, w, y, m, d, t}}
    case _ _ _ _ _: None{}

def rfc850(weekdayValue: String, date: List<&2, String>, time: String) -> Maybe<&2, DateFields>:
  match date:
    case day <> mon <> year <> Nil{}: dateFields(Rfc850{}, longWeekday(withoutComma(weekdayValue)), digits(2n, year, 0), parseMonth(mon), digits(2n, day, 0), parseClock(time))
    case _: None{}

def shortDay(+text: String) -> Maybe<&2, U32>:
  match text:
    case SCon{_, SNil{}}: digits(1n, text, 0)
    case _: digits(2n, text, 0)

def gmt(zone: String, value: Maybe<&2, DateFields>) -> Maybe<&2, DateFields>:
  Bool.pick(Maybe<&2, DateFields>, String.eq(zone, "GMT"), value, None{})

def words(parts: List<&2, String>) -> Maybe<&2, DateFields>:
  match parts:
    case week <> day <> mon <> year <> time <> zone <> Nil{}:
      gmt(zone, dateFields(ImfFixdate{}, parseWeekday(withoutComma(week)), digits(4n, year, 0), parseMonth(mon), digits(2n, day, 0), parseClock(time)))
    case week <> date <> time <> zone <> Nil{}: gmt(zone, rfc850(week, String.split(date, '-'), time))
    case week <> mon <> day <> time <> year <> Nil{}:
      dateFields(Asctime{}, parseWeekday(week), digits(4n, year, 0), parseMonth(mon), shortDay(day), parseClock(time))
    case _: None{}

# Accept surrounding/repeated spaces without changing recognized field tokens.
def nonempty(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case SNil{} <> rest: nonempty(rest)
    case head <> rest: head <> nonempty(rest)

def parseDateSyntax(text: String) -> Maybe<&2, DateFields>: words(nonempty(String.split(text, ' ')))

# RFC 9110's obsolete two-digit year is relative to the current UTC date.
# Calendar/weekday validation of the resolved input belongs to the interpreter.
type DateYearError is Data:
  InvalidShortYear{}
  InvalidReference{cause: Calendar.CalendarError}
  OutsideCalendar{}

def bounded(+year: U32) -> Result<&2, &2, DateYearError, U32>:
  Bool.pick(Result<&2, &2, DateYearError, U32>, U32.is_le(year, 9999), Done{year}, Fail{OutsideCalendar{}})

def afterField(+left: U32, +right: U32, suffix: Bool) -> Bool:
  U32.is_gt(left, right) || (U32.is_eq(left, right) && suffix)

# Compare the anniversary's remaining fields rather than treating a year as
# a fixed number of days. The parsed date has whole-second precision.
def laterInYear(date: DateFields, reference: Calendar.CivilTime) -> Bool:
  match date reference:
    case DateFields{_, _, _, month, day, ClockFields{hour, minute, second}} Calendar.CivilTime{_, rmonth, rday, rhour, rminute, rsecond, _}:
      afterField(month, rmonth, afterField(day, rday, afterField(hour, rhour, afterField(minute, rminute, U32.is_gt(second, rsecond)))))

def previousYear(+candidate: U32, valid: Bool) -> Result<&2, &2, DateYearError, U32>:
  match valid:
    case False{}: Fail{OutsideCalendar{}}
    case True{}: bounded((candidate - 100 : U32))

def select(+candidate: U32, rollback: Bool) -> Result<&2, &2, DateYearError, U32>:
  match rollback:
    case False{}: bounded(candidate)
    case True{}: previousYear(candidate, U32.is_ge(candidate, 100))

def candidate(+upper: U32, +year: U32, later: Bool) -> Result<&2, &2, DateYearError, U32>:
  +value = ((upper / 100) * 100 + year : U32)
  select(value, afterField(value, upper, later))

def window(reference: Calendar.CivilTime, +date: DateFields) -> Result<&2, &2, DateYearError, U32>:
  match reference date:
    case Calendar.CivilTime{+year, month, day, hour, minute, second, millis} DateFields{_, _, shortYearValue, _, _, _}:
      candidate((year + 50 : U32), shortYearValue, laterInYear(date, Calendar.CivilTime{year, month, day, hour, minute, second, millis}))

def checkedReference(reference: Calendar.CivilTime, date: DateFields, valid: Result<&2, &2, Calendar.CalendarError, W.U64>) -> Result<&2, &2, DateYearError, U32>:
  match valid:
    case Fail{cause}: Fail{InvalidReference{cause}}
    case Done{_}: window(reference, date)

def shortYear(+reference: Calendar.CivilTime, date: DateFields, valid: Bool) -> Result<&2, &2, DateYearError, U32>:
  match valid:
    case False{}: Fail{InvalidShortYear{}}
    case True{}: checkedReference(reference, date, Calendar.toEpochMilliseconds(reference))

def resolve(reference: Calendar.CivilTime, +date: DateFields) -> Result<&2, &2, DateYearError, U32>:
  match date:
    case DateFields{Rfc850{}, _, year, _, _, _}: shortYear(reference, date, U32.is_lt(year, 100))
    case DateFields{_, _, year, _, _, _}: bounded(year)

# Unix timestamps cannot identify a leap second uniquely. Preserve that case
# explicitly rather than silently shifting it into the following day.
type Instant is Data:
  Ordinary{milliseconds: W.U64}
  LeapSecond{precedingMilliseconds: W.U64}

type Error is Data:
  InvalidSyntax{}
  YearFailure{cause: DateYearError}
  CalendarFailure{cause: Calendar.CalendarError}
  WeekdayMismatch{}
  InvalidLeapPosition{}

type UnixError is Data:
  LeapSecondNotRepresentable{}

def unixMilliseconds(instant: Instant) -> Result<&2, &2, UnixError, W.U64>:
  match instant:
    case Ordinary{value}: Done{value}
    case LeapSecond{_}: Fail{LeapSecondNotRepresentable{}}

def tagged(leap: Bool, milliseconds: W.U64) -> Instant:
  match leap:
    case False{}: Ordinary{milliseconds}
    case True{}: LeapSecond{milliseconds}

def checkedWeekday(valid: Bool, leap: Bool, milliseconds: W.U64) -> Result<&2, &2, Error, Instant>:
  match valid:
    case False{}: Fail{WeekdayMismatch{}}
    case True{}: Done{tagged(leap, milliseconds)}

# Calendar day zero (0000-01-01) is Saturday; syntax numbers Monday as one.
def weekday(year: U32, month: U32, day: U32) -> U32:
  ((Calendar.dayIndex(year, month, day) + 5) % 7 + 1 : U32)

def checkedCalendar(year: U32, month: U32, day: U32, claimedWeekday: U32, leap: Bool, result: Result<&2, &2, Calendar.CalendarError, W.U64>) -> Result<&2, &2, Error, Instant>:
  match result:
    case Fail{cause}: Fail{CalendarFailure{cause}}
    case Done{milliseconds}: checkedWeekday(U32.is_eq(weekday(year, month, day), claimedWeekday), leap, milliseconds)

def clock(validLeap: Bool, +year: U32, date: DateFields, +leap: Bool) -> Result<&2, &2, Error, Instant>:
  match validLeap date:
    case False{} _: Fail{InvalidLeapPosition{}}
    case True{} DateFields{_, claimed, _, +month, +day, ClockFields{hour, minute, second}}:
      checkedCalendar(year, month, day, claimed, leap, Calendar.toEpochMilliseconds(Calendar.CivilTime{year, month, day, hour, minute, Bool.pick(U32, leap, 59, second), 0}))

def resolvedYear(+date: DateFields, result: Result<&2, &2, DateYearError, U32>) -> Result<&2, &2, Error, Instant>:
  match date result:
    case _ Fail{cause}: Fail{YearFailure{cause}}
    case DateFields{_, _, _, _, _, ClockFields{hour, minute, +second}} Done{year}:
      +leap = U32.is_eq(second, 60)
      clock(Bool.not(leap) || (U32.is_eq(hour, 23) && U32.is_eq(minute, 59)), year, date, leap)

def interpret(reference: Calendar.CivilTime, +date: DateFields) -> Result<&2, &2, Error, Instant>:
  resolvedYear(date, resolve(reference, date))

def parsedDate(reference: Calendar.CivilTime, fields: Maybe<&2, DateFields>) -> Result<&2, &2, Error, Instant>:
  match fields:
    case None{}: Fail{InvalidSyntax{}}
    case Some{date}: interpret(reference, date)

def parseAt(reference: Calendar.CivilTime, text: String) -> Result<&2, &2, Error, Instant>:
  parsedDate(reference, parseDateSyntax(text))

# Buffered request inputs. Streaming uploads, multipart forms and blob ownership
# have different lifetimes and are not represented by this value type.
type Input is Data:
  Absent{}
  Text{text: String}
  Bytes{bytes: List<&2, U32>}
  SearchParams{params: Params.URLSearchParams}

type Content is Data:
  Content{bytes: List<&2, U32>, length: N.BigNat}

type Prepared is Data:
  Prepared{method: String, headers: Headers, content: Maybe<&2, Content>}

type BufferedBodyError is Data:
  MethodError{error: RequestMethodError}
  BodyNotAllowed{}
  BufferedBodyInvalidByte{value: U32}
  HeaderError{error: HeaderSyntaxError}

def countedByte(valid: Bool, byte: U32, length: N.BigNat) -> Result<&2, &2, BufferedBodyError, N.BigNat>:
  match valid:
    case False{}: Fail{BufferedBodyInvalidByte{byte}}
    case True{}: Done{N.add(length, N.one())}

def counted(bytes: List<&2, U32>, result: Result<&2, &2, BufferedBodyError, N.BigNat>) -> Result<&2, &2, BufferedBodyError, N.BigNat>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{length}: Done{length}
    case +byte <> rest Done{length}: counted(rest, countedByte(U32.is_le(byte, 255), byte, length))

def withLength(method: String, headers: Headers, bytes: List<&2, U32>, length: Result<&2, &2, BufferedBodyError, N.BigNat>) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match length:
    case Fail{error}: Fail{error}
    case Done{size}: Done{Prepared{method, headers, Some{Content{bytes, size}}}}

def buffered(method: String, headers: Headers, +bytes: List<&2, U32>) -> Result<&2, &2, BufferedBodyError, Prepared>:
  withLength(method, headers, bytes, counted(bytes, Done{N.zero()}))

def textHeaders(method: String, headers: Result<&2, &2, HeaderSyntaxError, Headers>, text: String) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match headers:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{fields}: buffered(method, fields, Utf8.encode(text))

def textType(method: String, headers: Headers, text: String, contentType: String, existing: Result<&2, &2, HeaderSyntaxError, Bool>) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match existing:
    case Fail{error}: Fail{HeaderError{error}}
    case Done{True{}}: buffered(method, headers, Utf8.encode(text))
    case Done{False{}}: textHeaders(method, set(headers, "content-type", contentType), text)

def bufferedBody(method: String, +headers: Headers, input: Input) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match input:
    case Absent{}: Done{Prepared{method, headers, None{}}}
    case Bytes{bytes}: buffered(method, headers, bytes)
    case SearchParams{params}: textType(method, headers, Params.toString(params), "application/x-www-form-urlencoded;charset=UTF-8", has(headers, "content-type"))
    case Text{text}: textType(method, headers, text, "text/plain;charset=UTF-8", has(headers, "content-type"))

def permitted(method: String, headers: Headers, input: Input, disallowed: Bool) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match input disallowed:
    case Absent{} _: Done{Prepared{method, headers, None{}}}
    case _ True{}: Fail{BodyNotAllowed{}}
    case value False{}: bufferedBody(method, headers, value)

def normalizedBufferedBody(method: Result<&2, &2, RequestMethodError, String>, headers: Headers, input: Input) -> Result<&2, &2, BufferedBodyError, Prepared>:
  match method:
    case Fail{error}: Fail{MethodError{error}}
    case Done{+name}: permitted(name, headers, input, String.eq(name, "GET") || String.eq(name, "HEAD"))

# Empty text/bytes are present bodies, so GET/HEAD reject them too. Keep absent
# content distinct from a zero-length body; wire framing is a later step.
def prepare(method: String, headers: Headers, input: Input) -> Result<&2, &2, BufferedBodyError, Prepared>:
  normalizedBufferedBody(normalizeRequestMethod(method), headers, input)

# Buffered bodies can use a single chunk. Chunk size counts payload bytes;
# framing delimiters are separate, and an empty body is only the terminator.
def digit(+value: U32) -> U32:
  Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32))

def limb(+value: U32, tail: List<&2, U32>) -> List<&2, U32>:
  digit(U32.and(U32.shrn(value, 12n), 15)) <> digit(U32.and(U32.shrn(value, 8n), 15)) <> digit(U32.and(U32.shrn(value, 4n), 15)) <> digit(U32.and(value, 15)) <> tail

def hexLimbs(values: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match values:
    case Nil{}: tail
    case value <> rest: hexLimbs(rest, limb(value, tail))

def trim(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: 48 <> Nil{}
    case 48 <> rest: trim(rest)
    case byte <> rest: byte <> rest

def hexadecimal(length: N.BigNat) -> List<&2, U32>:
  match length:
    case N.BigNat{limbs}: trim(hexLimbs(limbs, Nil{}))

def end() -> List<&2, U32>: 48 <> 13 <> 10 <> 13 <> 10 <> Nil{}

def payload(empty: Bool, bytes: List<&2, U32>, length: N.BigNat) -> List<&2, U32>:
  match empty:
    case True{}: end()
    case False{}: List.append(&2, U32, hexadecimal(length), 13 <> 10 <> List.append(&2, U32, bytes, 13 <> 10 <> end()))

# Content comes from buffered-body preparation, which validates each byte and
# computes its immutable length. The result materializes the framed wire bytes;
# the request plan retains the entity content separately for retries.
def encode(content: Content) -> List<&2, U32>:
  match content:
    case Content{bytes, +length}: payload(N.isZero(length), bytes, length)

type Encoding is Data:
  Plain{}
  Chunked{}

type BufferedFramingPrepared is Data:
  BufferedFramingPrepared{request: Prepared, encoding: Encoding}

type Selection is Data:
  Selection{length: Maybe<&2, N.BigNat>, encoding: Encoding}

type FramingError is Data:
  InvalidLength{}
  LengthMismatch{actual: N.BigNat, declared: N.BigNat}
  UnsupportedTransferEncoding{}
  BufferedFramingHeaderError{error: HeaderSyntaxError}

# These method spellings have payload semantics in the installed transport.
# Common methods were already normalized by buffered-body preparation.
def expectsPayload(method: String) -> Bool:
  match method:
    case "POST": True{}
    case "PUT": True{}
    case "PATCH": True{}
    case "QUERY": True{}
    case "PROPFIND": True{}
    case "PROPPATCH": True{}
    case _: False{}

def parsed(value: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>:
  match value:
    case None{}: Fail{InvalidLength{}}
    case Some{length}: Done{Some{length}}

def declared(value: Result<&2, &2, HeaderSyntaxError, Maybe<&2, String>>) -> Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>:
  match value:
    case Fail{error}: Fail{BufferedFramingHeaderError{error}}
    case Done{None{}}: Done{None{}}
    case Done{Some{text}}: parsed(N.fromDecimal(text))

def zeroLength(payload: Bool) -> Selection:
  match payload:
    case True{}: Selection{Some{N.zero()}, Plain{}}
    case False{}: Selection{None{}, Plain{}}

def wireLength(method: String, +length: N.BigNat) -> Selection:
  Bool.pick(Selection, N.isZero(length), zeroLength(expectsPayload(method)), Selection{Some{length}, Plain{}})

def matching(matches: Bool, fallbackChunked: Bool, method: String, actual: N.BigNat, supplied: N.BigNat) -> Result<&2, &2, FramingError, Selection>:
  match matches fallbackChunked:
    case True{} _: Done{wireLength(method, actual)}
    case False{} True{}: Done{Selection{None{}, Chunked{}}}
    case False{} False{}: Fail{LengthMismatch{actual, supplied}}

def present(+method: String, +length: N.BigNat, supplied: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Selection>:
  match supplied:
    case None{}: Done{wireLength(method, length)}
    case Some{+value}: matching(N.equal(length, value), N.isZero(value) && Bool.not(expectsPayload(method)), method, length, value)

def selected(method: String, content: Maybe<&2, Content>, supplied: Maybe<&2, N.BigNat>) -> Result<&2, &2, FramingError, Selection>:
  match content:
    case None{}: Done{zeroLength(expectsPayload(method))}
    case Some{Content{_, length}}: present(method, length, supplied)

def updated(method: String, content: Maybe<&2, Content>, encoding: Encoding, headers: Result<&2, &2, HeaderSyntaxError, Headers>) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match headers:
    case Fail{error}: Fail{BufferedFramingHeaderError{error}}
    case Done{fields}: Done{BufferedFramingPrepared{Prepared{method, fields, content}, encoding}}

def chunkedBufferedFraming(method: String, content: Maybe<&2, Content>, result: Result<&2, &2, HeaderSyntaxError, Headers>) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match result:
    case Fail{error}: Fail{BufferedFramingHeaderError{error}}
    case Done{headers}: updated(method, content, Chunked{}, set(headers, "transfer-encoding", "chunked"))

def canonical(method: String, headers: Headers, content: Maybe<&2, Content>, length: Result<&2, &2, FramingError, Selection>) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match length:
    case Fail{error}: Fail{error}
    case Done{Selection{_, Chunked{}}}: chunkedBufferedFraming(method, content, delete(headers, "content-length"))
    case Done{Selection{None{}, Plain{}}}: updated(method, content, Plain{}, delete(headers, "content-length"))
    case Done{Selection{Some{value}, Plain{}}}: updated(method, content, Plain{}, set(headers, "content-length", N.toDecimal(value)))

def lengths(request: Prepared, value: Result<&2, &2, FramingError, Maybe<&2, N.BigNat>>) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match request value:
    case _ Fail{error}: Fail{error}
    case Prepared{+method, headers, +content} Done{supplied}: canonical(method, headers, content, selected(method, content, supplied))

def transfer(request: Prepared, provided: Result<&2, &2, HeaderSyntaxError, Bool>) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match request provided:
    case _ Fail{error}: Fail{BufferedFramingHeaderError{error}}
    case _ Done{True{}}: Fail{UnsupportedTransferEncoding{}}
    case Prepared{method, +headers, content} Done{False{}}: lengths(Prepared{method, headers, content}, declared(get(headers, "content-length")))

# A supplied zero length can select chunked framing for methods without
# payload semantics, matching the transport. The encoding is explicit so the
# sender cannot mistake entity bytes for an already framed chunked body.
# Validate a supplied length even with absent content; the transport then
# canonicalizes absent-body framing independently of its numeric value.
def prepareBufferedFraming(request: Prepared) -> Result<&2, &2, FramingError, BufferedFramingPrepared>:
  match request:
    case Prepared{method, +headers, content}: transfer(Prepared{method, headers, content}, has(headers, "transfer-encoding"))

# Produce the selected wire representation. Entity content and length remain
# available in BufferedFramingPrepared for retries and request metadata.
def wireContent(content: Maybe<&2, Content>, encoding: Encoding) -> List<&2, U32>:
  match content encoding:
    case None{} _: Nil{}
    case Some{Content{bytes, _}} Plain{}: bytes
    case Some{value} Chunked{}: encode(value)

def wireBody(prepared: BufferedFramingPrepared) -> List<&2, U32>:
  match prepared:
    case BufferedFramingPrepared{Prepared{_, _, content}, encoding}: wireContent(content, encoding)

type BufferedRequestPrepared is Data:
  BufferedRequestPrepared{head: Head, body: BufferedFramingPrepared}

type RequestError is Data:
  BufferedRequestBodyError{error: BufferedBodyError}
  BufferedRequestFramingError{error: FramingError}
  HeadError{error: RequestHeadError}

def headed(body: BufferedFramingPrepared, value: Result<&2, &2, RequestHeadError, Head>) -> Result<&2, &2, RequestError, BufferedRequestPrepared>:
  match value:
    case Fail{error}: Fail{HeadError{error}}
    case Done{head}: Done{BufferedRequestPrepared{head, body}}

def framed(target: String, value: Result<&2, &2, FramingError, BufferedFramingPrepared>) -> Result<&2, &2, RequestError, BufferedRequestPrepared>:
  match value:
    case Fail{error}: Fail{BufferedRequestFramingError{error}}
    case Done{BufferedFramingPrepared{Prepared{+method, +headers, +content}, +encoding}}:
      headed(BufferedFramingPrepared{Prepared{method, headers, content}, encoding}, encodeRequestHead(method, target, entries(headers)))

def prepared(target: String, value: Result<&2, &2, BufferedBodyError, Prepared>) -> Result<&2, &2, RequestError, BufferedRequestPrepared>:
  match value:
    case Fail{error}: Fail{BufferedRequestBodyError{error}}
    case Done{body}: framed(target, prepareBufferedFraming(body))

# Pure preparation can run before opening a connection. The caller supplies
# an encoded origin-form target and endpoint/default headers, including Host.
def prepareBufferedRequest(method: String, target: String, headers: Headers, body: Input) -> Result<&2, &2, RequestError, BufferedRequestPrepared>:
  prepared(target, prepare(method, headers, body))


# Retain the typed connection endpoint alongside the fully framed request.
# Fetch derives Host from the URL, overriding any caller-supplied Host field.
type URLPrepared is Data:
  URLPrepared{endpoint: Endpoint, request: BufferedRequestPrepared}

type URLRequestError is Data:
  URLError{error: EndpointError}
  BufferedRequestHeaderError{error: HeaderSyntaxError}
  PreparationError{error: RequestError}

def urlPrepared(endpoint: Endpoint, result: Result<&2, &2, RequestError, BufferedRequestPrepared>) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{PreparationError{error}}
    case Done{request}: Done{URLPrepared{endpoint, request}}

def urlHeaders(endpoint: Endpoint, method: String, target: String, body: Input, result: Result<&2, &2, HeaderSyntaxError, Headers>) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{BufferedRequestHeaderError{error}}
    case Done{headers}: urlPrepared(endpoint, prepareBufferedRequest(method, target, headers, body))

def urlEndpoint(result: Result<&2, &2, EndpointError, Endpoint>, method: String, headers: Headers, body: Input) -> Result<&2, &2, URLRequestError, URLPrepared>:
  match result:
    case Fail{error}: Fail{URLError{error}}
    case Done{Endpoint{transport, host, port, +authority, +target}}: urlHeaders(Endpoint{transport, host, port, authority, target}, method, target, body, set(headers, "host", authority))

def prepareURL(value: URL.URL, method: String, headers: Headers, body: Input) -> Result<&2, &2, URLRequestError, URLPrepared>:
  urlEndpoint(urlPrepare(value), method, headers, body)
