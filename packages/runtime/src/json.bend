import Base
import ./schema-value.bend as V
import ./record.bend as R
import ./utf16.bend as Utf16
import ./number-string.bend as Number
import ./f64.bend as F


# Strict JSON decoding into the canonical immutable value tree. Parser errors
# are language-independent values, not JavaScript engine exception messages.
type ParseError is Data:
  ParseInvalidValue{}
  InvalidEscape{}
  UnescapedControl{}
  UnterminatedString{}
  UnexpectedToken{}
  UnexpectedEnd{}
  TrailingInput{}
  InputLimit{}

type Token is Data:
  Atom{value: V.Value}
  Punctuation{char: Char}
  End{}
  Invalid{error: ParseError}

type Lexeme is Data:
  Lexeme{token: Token, remaining: String}

def skipSpace(text: String) -> String:
  match text:
    case SCon{' ', rest}: skipSpace(rest)
    case SCon{'\t', rest}: skipSpace(rest)
    case SCon{'\r', rest}: skipSpace(rest)
    case SCon{'\n', rest}: skipSpace(rest)
    case other: other

def hexDigit(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(code,48) && U32.is_le(code,57), Some{(code - 48 : U32)}, Bool.pick(Maybe<&2,U32>,U32.is_ge(code,65) && U32.is_le(code,70),Some{(code - 55 : U32)},Bool.pick(Maybe<&2,U32>,U32.is_ge(code,97) && U32.is_le(code,102),Some{(code - 87 : U32)},None{})))

type StringState is Data:
  Plain{}
  Escape{}
  Hex{remaining: Nat, code: U32}

type StringStep is Data:
  More{state: StringState, reversed: String}
  Complete{reversed: String}
  StringError{error: ParseError}

def hexStep(value: Maybe<&2,U32>, remaining: Nat, code: U32, reversed: String) -> StringStep:
  match value remaining:
    case None{} _: StringError{InvalidEscape{}}
    case Some{digit} 0n: More{Plain{}, SCon{Chr{(code * 16 + digit : U32)}, reversed}}
    case Some{digit} 1n+n: More{Hex{n,(code * 16 + digit : U32)}, reversed}

def stringStep(state: StringState, +code: U32, reversed: String) -> StringStep:
  match state code:
    case Plain{} 34: Complete{reversed}
    case Plain{} 92: More{Escape{}, reversed}
    case Plain{} _: Bool.pick(StringStep,U32.is_lt(code,32),StringError{UnescapedControl{}},More{Plain{},SCon{Chr{code},reversed}})
    case Escape{} 34: More{Plain{}, SCon{'"',reversed}}
    case Escape{} 92: More{Plain{}, SCon{'\\',reversed}}
    case Escape{} 47: More{Plain{}, SCon{'/',reversed}}
    case Escape{} 98: More{Plain{}, SCon{Chr{8},reversed}}
    case Escape{} 102: More{Plain{}, SCon{Chr{12},reversed}}
    case Escape{} 110: More{Plain{}, SCon{'\n',reversed}}
    case Escape{} 114: More{Plain{}, SCon{'\r',reversed}}
    case Escape{} 116: More{Plain{}, SCon{'\t',reversed}}
    case Escape{} 117: More{Hex{3n,0},reversed}
    case Escape{} _: StringError{InvalidEscape{}}
    case Hex{remaining,value} _: hexStep(hexDigit(code),remaining,value,reversed)

def scanString(text: String, step: StringStep) -> Lexeme:
  match text step:
    case remaining Complete{reversed}: Lexeme{Atom{V.Text{Utf16.normalize(String.reverse(reversed))}},remaining}
    case remaining StringError{error}: Lexeme{Invalid{error},remaining}
    case SNil{} More{_,_}: Lexeme{Invalid{UnterminatedString{}},""}
    case SCon{Chr{code},rest} More{state,reversed}: scanString(rest,stringStep(state,code,reversed))

type NumberState is Data:
  NumberStart{}
  NumberSign{}
  NumberZero{}
  NumberInteger{}
  NumberDecimalPoint{}
  NumberFraction{}
  NumberExponent{}
  NumberExponentSign{}
  NumberExponentDigits{}
  BadNumber{}

def decimalDigit(+code: U32) -> Bool: U32.is_ge(code,48) && U32.is_le(code,57)

def integerStart(+code: U32) -> NumberState:
  match code:
    case 48: NumberZero{}
    case _: Bool.pick(NumberState,U32.is_ge(code,49) && U32.is_le(code,57),NumberInteger{},BadNumber{})

def afterInteger(code: U32) -> NumberState:
  match code:
    case 46: NumberDecimalPoint{}
    case 101: NumberExponent{}
    case 69: NumberExponent{}
    case _: BadNumber{}

def numberStep(state: NumberState, +code: U32) -> NumberState:
  match state code:
    case NumberStart{} 45: NumberSign{}
    case NumberStart{} _: integerStart(code)
    case NumberSign{} _: integerStart(code)
    case NumberZero{} _: afterInteger(code)
    case NumberInteger{} _: Bool.pick(NumberState,decimalDigit(code),NumberInteger{},afterInteger(code))
    case NumberDecimalPoint{} _: Bool.pick(NumberState,decimalDigit(code),NumberFraction{},BadNumber{})
    case NumberFraction{} 101: NumberExponent{}
    case NumberFraction{} 69: NumberExponent{}
    case NumberFraction{} _: Bool.pick(NumberState,decimalDigit(code),NumberFraction{},BadNumber{})
    case NumberExponent{} 43: NumberExponentSign{}
    case NumberExponent{} 45: NumberExponentSign{}
    case NumberExponent{} _: Bool.pick(NumberState,decimalDigit(code),NumberExponentDigits{},BadNumber{})
    case NumberExponentSign{} _: Bool.pick(NumberState,decimalDigit(code),NumberExponentDigits{},BadNumber{})
    case NumberExponentDigits{} _: Bool.pick(NumberState,decimalDigit(code),NumberExponentDigits{},BadNumber{})
    case BadNumber{} _: BadNumber{}

def numberComplete(state: NumberState) -> Bool:
  match state:
    case NumberZero{}: True{}
    case NumberInteger{}: True{}
    case NumberFraction{}: True{}
    case NumberExponentDigits{}: True{}
    case _: False{}

def validNumber(text: String, state: NumberState) -> Bool:
  match text:
    case SNil{}: numberComplete(state)
    case SCon{Chr{code},rest}: validNumber(rest,numberStep(state,code))

def numberToken(valid: Bool, text: String) -> Token:
  match valid:
    case True{}: Atom{V.Number{Number.toNumber(text)}}
    case False{}: Invalid{ParseInvalidValue{}}

def atom(+text: String) -> Token:
  match text:
    case "null": Atom{V.Null{}}
    case "true": Atom{V.Boolean{True{}}}
    case "false": Atom{V.Boolean{False{}}}
    case other: numberToken(validNumber(other,NumberStart{}),other)

def wordEnd(reversed: String, remaining: String) -> Lexeme:
  Lexeme{atom(String.reverse(reversed)),remaining}

def scanWord(text: String, reversed: String) -> Lexeme:
  match text:
    case SNil{}: wordEnd(reversed,"")
    case SCon{' ',rest}: wordEnd(reversed,SCon{' ',rest})
    case SCon{'\t',rest}: wordEnd(reversed,SCon{'\t',rest})
    case SCon{'\n',rest}: wordEnd(reversed,SCon{'\n',rest})
    case SCon{'\r',rest}: wordEnd(reversed,SCon{'\r',rest})
    case SCon{',',rest}: wordEnd(reversed,SCon{',',rest})
    case SCon{']',rest}: wordEnd(reversed,SCon{']',rest})
    case SCon{'}',rest}: wordEnd(reversed,SCon{'}',rest})
    case SCon{':',rest}: wordEnd(reversed,SCon{':',rest})
    case SCon{char,rest}: scanWord(rest,SCon{char,reversed})

def lexClean(text: String) -> Lexeme:
  match text:
    case SNil{}: Lexeme{End{},""}
    case SCon{'"',rest}: scanString(rest,More{Plain{},""})
    case SCon{'[',rest}: Lexeme{Punctuation{'['},rest}
    case SCon{']',rest}: Lexeme{Punctuation{']'},rest}
    case SCon{'{',rest}: Lexeme{Punctuation{'{'},rest}
    case SCon{'}',rest}: Lexeme{Punctuation{'}'},rest}
    case SCon{',',rest}: Lexeme{Punctuation{','},rest}
    case SCon{':',rest}: Lexeme{Punctuation{':'},rest}
    case other: scanWord(other,"")

def lex(text: String) -> Lexeme: lexClean(skipSpace(text))

type Frame is Data:
  ArrayFrame{reversed: List<&2,V.Value>}
  ObjectFrame{key: String, fields: R.Record<V.Value>}

type Mode is Data:
  Value{}
  ArrayFirst{}
  ArrayNext{reversed: List<&2,V.Value>}
  ArrayAfter{reversed: List<&2,V.Value>}
  ObjectFirst{}
  ObjectNext{fields: R.Record<V.Value>}
  ObjectAfter{fields: R.Record<V.Value>}
  Colon{key: String, fields: R.Record<V.Value>}
  Finished{value: V.Value}
  Broken{error: ParseError}

type Parser is Data:
  Parser{mode: Mode, stack: List<&2,Frame>}

def accepted(stack: List<&2,Frame>, value: V.Value) -> Parser:
  match stack:
    case Nil{}: Parser{Finished{value},Nil{}}
    case ArrayFrame{reversed} <> rest: Parser{ArrayAfter{value <> reversed},rest}
    case ObjectFrame{key,fields} <> rest: Parser{ObjectAfter{R.set(V.Value,fields,key,value)},rest}

def valueToken(token: Token, stack: List<&2,Frame>) -> Parser:
  match token:
    case Atom{value}: accepted(stack,value)
    case Punctuation{'['}: Parser{ArrayFirst{},stack}
    case Punctuation{'{'}: Parser{ObjectFirst{},stack}
    case Invalid{error}: Parser{Broken{error},Nil{}}
    case End{}: Parser{Broken{UnexpectedEnd{}},Nil{}}
    case _: Parser{Broken{UnexpectedToken{}},Nil{}}

def parserStep(parser: Parser, token: Token) -> Parser:
  match parser token:
    case Parser{Value{},stack} token: valueToken(token,stack)
    case Parser{ArrayFirst{},stack} Punctuation{']'}: accepted(stack,V.ArrayValue{Nil{}})
    case Parser{ArrayFirst{},stack} token: valueToken(token,ArrayFrame{Nil{}} <> stack)
    case Parser{ArrayNext{reversed},stack} token: valueToken(token,ArrayFrame{reversed} <> stack)
    case Parser{ArrayAfter{reversed},stack} Punctuation{','}: Parser{ArrayNext{reversed},stack}
    case Parser{ArrayAfter{reversed},stack} Punctuation{']'}: accepted(stack,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case Parser{ObjectFirst{},stack} Punctuation{'}'}: accepted(stack,V.ObjectValue{R.new(V.Value)})
    case Parser{ObjectFirst{},stack} Atom{V.Text{key}}: Parser{Colon{key,R.new(V.Value)},stack}
    case Parser{ObjectNext{fields},stack} Atom{V.Text{key}}: Parser{Colon{key,fields},stack}
    case Parser{Colon{key,fields},stack} Punctuation{':'}: Parser{Value{},ObjectFrame{key,fields} <> stack}
    case Parser{ObjectAfter{fields},stack} Punctuation{','}: Parser{ObjectNext{fields},stack}
    case Parser{ObjectAfter{fields},stack} Punctuation{'}'}: accepted(stack,V.ObjectValue{fields})
    case Parser{Broken{error},_} _: Parser{Broken{error},Nil{}}
    case _ Invalid{error}: Parser{Broken{error},Nil{}}
    case _ End{}: Parser{Broken{UnexpectedEnd{}},Nil{}}
    case _ _: Parser{Broken{UnexpectedToken{}},Nil{}}

# Each token consumes at least one input character. The input length bounds the
# transition count, while explicit frames permit arbitrarily nested containers.
def parseLoop(fuel: Nat, +parser: Parser, input: Lexeme) -> Result<&2,&2,ParseError,V.Value>:
  match fuel parser input:
    case 0n _ _: Fail{InputLimit{}}
    case _ Parser{Broken{error},_} _: Fail{error}
    case _ Parser{Finished{value},_} Lexeme{End{},_}: Done{value}
    case _ Parser{Finished{_},_} _: Fail{TrailingInput{}}
    case 1n+n _ Lexeme{token,rest}: parseLoop(n,parserStep(parser,token),lex(rest))

def parse(+text: String) -> Result<&2,&2,ParseError,V.Value>:
  parseLoop(2n+String.length(text),Parser{Value{},Nil{}},lex(text))


# Paths carry literal field names, not dot-separated strings or JS properties.
type Segment is Data:
  Field{name: String}
  Index{index: Nat}

type Error is Data:
  MissingField{path: List<&2, Segment>}
  WrongType{path: List<&2, Segment>, expected: String}
  InvalidValue{path: List<&2, Segment>, expected: String}

def at(error: Error, segment: Segment) -> Error:
  match error:
    case MissingField{path}: MissingField{segment <> path}
    case WrongType{path, expected}: WrongType{segment <> path, expected}
    case InvalidValue{path, expected}: InvalidValue{segment <> path, expected}

def located(-A: Data, result: Result<&2, &2, Error, A>, segment: Segment) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{at(error, segment)}

def object(value: V.Value) -> Result<&2, &2, Error, R.Record<V.Value>>:
  match value:
    case V.ObjectValue{fields}: Done{fields}
    case _: Fail{WrongType{Nil{}, "object"}}

def string(value: V.Value) -> Result<&2, &2, Error, String>:
  match value:
    case V.Text{text}: Done{text}
    case _: Fail{WrongType{Nil{}, "string"}}

def number(value: V.Value) -> Result<&2, &2, Error, F64>:
  match value:
    case V.Number{scalar}: Done{scalar}
    case _: Fail{WrongType{Nil{}, "number"}}

def array(value: V.Value) -> Result<&2, &2, Error, List<&2, V.Value>>:
  match value:
    case V.ArrayValue{values}: Done{values}
    case _: Fail{WrongType{Nil{}, "array"}}

def requiredValue(value: Maybe<&2, V.Value>) -> Result<&2, &2, Error, V.Value>:
  match value:
    case None{}: Fail{MissingField{Nil{}}}
    case Some{value}: Done{value}

def required(-A: Data, fields: R.Record<V.Value>, +key: String, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, A>:
  located(A, Result.bind(&2, &2, Error, V.Value, A, requiredValue(R.get(V.Value, fields, key)), decode), Field{key})

# Nullable protocol fields use Maybe; a wrong non-null type remains an error.
def optionalValue(-A: Data, value: Maybe<&2, V.Value>, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, Maybe<&2, A>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Null{}}: Done{None{}}
    case Some{value}: Result.map(&2, &2, Error, A, Maybe<&2, A>, item => Some{item}, decode(value))

def optional(-A: Data, fields: R.Record<V.Value>, +key: String, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, Maybe<&2, A>>:
  located(Maybe<&2, A>, optionalValue(A, R.get(V.Value, fields, key), decode), Field{key})

def items(~A: Data, ~decode: V.Value -> Result<&2, &2, Error, A>, values: List<&2, V.Value>, +index: Nat) -> Result<&2, &2, Error, List<&2, A>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, Error, List<&2, A>>:
        value : A <- located(A, decode(head), Index{index})
        rest : List<&2, A> <- items(~A, ~decode, tail, index + 1n)
        return value <> rest

def list(~A: Data, ~decode: V.Value -> Result<&2, &2, Error, A>, value: V.Value) -> Result<&2, &2, Error, List<&2, A>>:
  do Result<&2, &2, Error, List<&2, A>>:
    values : List<&2, V.Value> <- array(value)
    items(~A, ~decode, values, 0n)


# Quote a JavaScript-compatible string. Bend may contain Unicode scalars or
# individual UTF-16 surrogate units. Valid adjacent pairs emit their scalar;
# unpaired units emit lowercase Unicode escapes, as JSON.stringify does.
def hex(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def unicodeEscape(+code: U32) -> String:
  "\\u" ++ SCon{hex((code / 4096 : U32)), SCon{hex(((code / 256) % 16 : U32)), SCon{hex(((code / 16) % 16 : U32)), SCon{hex((code % 16 : U32)), SNil{}}}}}

def escapeOther(needed: Bool, code: U32) -> String:
  match needed:
    case True{}: unicodeEscape(code)
    case False{}: SCon{Chr{code}, SNil{}}

def escapeCode(+code: U32) -> String:
  match code:
    case 34: "\\\""
    case 92: "\\\\"
    case 8: "\\b"
    case 9: "\\t"
    case 10: "\\n"
    case 12: "\\f"
    case 13: "\\r"
    case _: escapeOther(U32.is_lt(code, 32) || Utf16.highSurrogate(code) || Utf16.lowSurrogate(code), code)

# Accumulate backwards so large prompt/tool strings do not retain one hosted
# machine-stack frame per scalar. Each escape fragment has at most six scalars.
def escapeInto(chars: String, reversed: String) -> String:
  match chars:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{code}, rest}: escapeInto(rest, String.reverse.go(escapeCode(code), reversed))

def escaped(chars: String) -> String:
  escapeInto(chars, "")

def quote(text: String) -> String:
  "\"" ++ escaped(Utf16.normalize(text)) ++ "\""
