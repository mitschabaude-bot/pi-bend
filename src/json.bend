import Base

# Numbers preserve their exact decimal spelling; no lossy F32 conversion.
type Json is Data:
  Null{}
  Boolean{value: Bool}
  Number{text: String}
  Text{text: String}
  Array{items: Json}
  Object{fields: Json}
  End{}
  Item{value: Json, rest: Json}
  Field{key: String, value: Json, rest: Json}

def comma(rest: String) -> String:
  match rest:
    case SNil{}: ""
    case SCon{h, t}: "," ++ SCon{h, t}

def hex(+n: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(n, 10), (48 + n : U32), (87 + n : U32)))

def escape_code(+c: U32) -> String:
  match c:
    case 34: "\\\""
    case 92: "\\\\"
    case 8: "\\b"
    case 9: "\\t"
    case 10: "\\n"
    case 12: "\\f"
    case 13: "\\r"
    case _: Bool.pick(String, U32.is_lt(c, 32), "\\u00" ++ SCon{hex((c / 16 : U32)), SCon{hex((c % 16 : U32)), SNil{}}}, SCon{Char.from_u32(c), SNil{}})

def escape(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{c, t}: escape_code(Char.to_u32(c)) ++ escape(t)

def quote(s: String) -> String:
  "\"" ++ escape(s) ++ "\""

def encode(j: Json) -> String:
  match j:
    case Null{}: "null"
    case Boolean{b}: Bool.pick(String, b, "true", "false")
    case Number{s}: s
    case Text{s}: quote(s)
    case Array{xs}: "[" ++ encode(xs) ++ "]"
    case Object{xs}: "{" ++ encode(xs) ++ "}"
    case End{}: ""
    case Item{v, t}: encode(v) ++ comma(encode(t))
    case Field{k, v, t}: quote(k) ++ ":" ++ encode(v) ++ comma(encode(t))

def reverse(xs: Json, acc: Json) -> Json:
  match xs:
    case Item{v, t}: reverse(t, Item{v, acc})
    case Field{k, v, t}: reverse(t, Field{k, v, acc})
    case _: acc

def get_fields(xs: Json, +key: String) -> Json:
  match xs:
    case Field{k, v, t}: Bool.pick(Json, String.eq(k, key), v, get_fields(t, key))
    case _: Null{}

def get(j: Json, key: String) -> Json:
  match j:
    case Object{xs}: get_fields(xs, key)
    case _: Null{}

def text(j: Json) -> String:
  match j:
    case Text{s}: s
    case _: ""

def number(j: Json, fallback: Nat) -> Nat:
  match j:
    case Number{s}: Maybe.default(&2, Nat, Nat.read(s), fallback)
    case _: fallback

def array(j: Json) -> Json:
  match j:
    case Array{xs}: xs
    case _: End{}

def append(xs: Json, ys: Json) -> Json:
  match xs:
    case Item{v, t}: Item{v, append(t, ys)}
    case Field{k, v, t}: Field{k, v, append(t, ys)}
    case _: ys

def str_field(key: String, value: String, rest: Json) -> Json:
  Field{key, Text{value}, rest}

type Token is Data:
  Atom{value: Json}
  Punct{c: Char}
  Eof{}
  Bad{message: String}

def space(+c: Char) -> Bool:
  +n = Char.to_u32(c)
  U32.is_eq(n, 32) || U32.is_eq(n, 9) || U32.is_eq(n, 10) || U32.is_eq(n, 13)

def skip(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+c, +t}: Bool.pick(String, space(c), skip(t), SCon{c, t})

def unhex(+c: U32) -> U32:
  Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), (c - 48 : U32), Bool.pick(U32, U32.is_ge(c, 65) && U32.is_le(c, 70), (c - 55 : U32), Bool.pick(U32, U32.is_ge(c, 97) && U32.is_le(c, 102), (c - 87 : U32), 255)))

type StrState is Data:
  Plain{}
  Esc{}
  Hex{left: Nat, code: U32}
  SurSlash{high: U32}
  SurU{high: U32}
  SurHex{left: Nat, high: U32, code: U32}

type StrStep is Data:
  More{state: StrState, out: String}
  Stop{out: String}
  Invalid{}

def finish_hex(+code: U32, +out: String) -> StrStep:
  Bool.pick(StrStep, U32.is_ge(code, 55296) && U32.is_le(code, 56319), More{SurSlash{code}, out}, Bool.pick(StrStep, U32.is_ge(code, 56320) && U32.is_le(code, 57343), Invalid{}, More{Plain{}, SCon{Chr{code}, out}}))

def string_step(st: StrState, +c: U32, out: String) -> StrStep:
  match st c:
    case Plain{} 34: Stop{out}
    case Plain{} 92: More{Esc{}, out}
    case Plain{} _: Bool.pick(StrStep, U32.is_lt(c, 32), Invalid{}, More{Plain{}, SCon{Chr{c}, out}})
    case Esc{} 34: More{Plain{}, SCon{'"', out}}
    case Esc{} 92: More{Plain{}, SCon{'\\', out}}
    case Esc{} 47: More{Plain{}, SCon{'/', out}}
    case Esc{} 98: More{Plain{}, SCon{Chr{8}, out}}
    case Esc{} 102: More{Plain{}, SCon{Chr{12}, out}}
    case Esc{} 110: More{Plain{}, SCon{'\n', out}}
    case Esc{} 114: More{Plain{}, SCon{'\r', out}}
    case Esc{} 116: More{Plain{}, SCon{'\t', out}}
    case Esc{} 117: More{Hex{3n, 0}, out}
    case Hex{0n, code} _:
      +h = unhex(c)
      Bool.pick(StrStep, U32.is_eq(h, 255), Invalid{}, finish_hex((code * 16 + h : U32), out))
    case Hex{1n+n, code} _:
      +h = unhex(c)
      Bool.pick(StrStep, U32.is_eq(h, 255), Invalid{}, More{Hex{n, (code * 16 + h : U32)}, out})
    case SurSlash{h} 92: More{SurU{h}, out}
    case SurU{h} 117: More{SurHex{3n, h, 0}, out}
    case SurHex{0n, h, code} _:
      +v = unhex(c)
      +low = (code * 16 + v : U32)
      Bool.pick(StrStep, U32.is_eq(v, 255) || U32.is_lt(low, 56320) || U32.is_gt(low, 57343), Invalid{}, More{Plain{}, SCon{Chr{(65536 + (h - 55296) * 1024 + low - 56320 : U32)}, out}})
    case SurHex{1n+n, h, code} _:
      +v = unhex(c)
      Bool.pick(StrStep, U32.is_eq(v, 255), Invalid{}, More{SurHex{n, h, (code * 16 + v : U32)}, out})
    case _ _: Invalid{}

def scan_string(fuel: Nat, step: StrStep, s: String) -> Token & String:
  match fuel step s:
    case 0n _ _: (Bad{"Unterminated JSON string"}, "")
    case 1n+n Stop{out} s: (Atom{Text{String.reverse(out)}}, s)
    case 1n+n Invalid{} s: (Bad{"Invalid JSON string escape"}, s)
    case 1n+n More{state, out} SNil{}: (Bad{"Unterminated JSON string"}, "")
    case 1n+n More{state, out} SCon{c, t}: scan_string(n, string_step(state, Char.to_u32(c), out), t)

def read_string(+s: String) -> Token & String:
  scan_string(1n+String.length(s), More{Plain{}, ""}, s)

def delimiter(+c: Char) -> Bool:
  +n = Char.to_u32(c)
  space(c) || U32.is_eq(n, 44) || U32.is_eq(n, 93) || U32.is_eq(n, 125) || U32.is_eq(n, 58)

def scan_word(fuel: Nat, running: Bool, s: String, +acc: String) -> String & String:
  match fuel running s:
    case 0n _ s: (String.reverse(acc), s)
    case 1n+n False{} s: (String.reverse(acc), s)
    case 1n+n True{} SNil{}: (String.reverse(acc), "")
    case 1n+n True{} SCon{+c, +t}:
      +stop = delimiter(c)
      scan_word(n, Bool.not(stop), Bool.pick(String, stop, SCon{c, t}, t), Bool.pick(String, stop, acc, SCon{c, acc}))

# JSON number grammar: sign, integer, fraction, exponent.
def num_step(state: U32, +c: U32) -> U32:
  match state:
    case 0: Bool.pick(U32, U32.is_eq(c, 45), 1, Bool.pick(U32, U32.is_eq(c, 48), 2, Bool.pick(U32, U32.is_ge(c, 49) && U32.is_le(c, 57), 3, 99)))
    case 1: Bool.pick(U32, U32.is_eq(c, 48), 2, Bool.pick(U32, U32.is_ge(c, 49) && U32.is_le(c, 57), 3, 99))
    case 2: Bool.pick(U32, U32.is_eq(c, 46), 4, Bool.pick(U32, U32.is_eq(c, 101) || U32.is_eq(c, 69), 6, 99))
    case 3: Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 3, Bool.pick(U32, U32.is_eq(c, 46), 4, Bool.pick(U32, U32.is_eq(c, 101) || U32.is_eq(c, 69), 6, 99)))
    case 4: Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 5, 99)
    case 5: Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 5, Bool.pick(U32, U32.is_eq(c, 101) || U32.is_eq(c, 69), 6, 99))
    case 6: Bool.pick(U32, U32.is_eq(c, 43) || U32.is_eq(c, 45), 7, Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 8, 99))
    case 7: Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 8, 99)
    case 8: Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), 8, 99)
    case _: 99

def valid_number(s: String, +state: U32) -> Bool:
  match s:
    case SNil{}: U32.is_eq(state, 2) || U32.is_eq(state, 3) || U32.is_eq(state, 5) || U32.is_eq(state, 8)
    case SCon{c, t}: valid_number(t, num_step(state, Char.to_u32(c)))

def atom(+s: String) -> Token:
  Bool.pick(Token, String.eq(s, "null"), Atom{Null{}}, Bool.pick(Token, String.eq(s, "true"), Atom{Boolean{True{}}}, Bool.pick(Token, String.eq(s, "false"), Atom{Boolean{False{}}}, Bool.pick(Token, valid_number(s, 0), Atom{Number{s}}, Bad{"Invalid JSON value"}))))

def word_token(pair: String & String) -> Token & String:
  (word, rest) = pair
  (atom(word), rest)

def lex_char(+c: U32, +rest: String) -> Token & String:
  match c:
    case 34: read_string(rest)
    case 91: (Punct{'['}, rest)
    case 93: (Punct{']'}, rest)
    case 123: (Punct{'{'}, rest)
    case 125: (Punct{'}'}, rest)
    case 44: (Punct{','}, rest)
    case 58: (Punct{':'}, rest)
    case _: word_token(scan_word(2n+String.length(rest), True{}, SCon{Chr{c}, rest}, ""))

def lex_clean(s: String) -> Token & String:
  match s:
    case SNil{}: (Eof{}, "")
    case SCon{c, t}: lex_char(Char.to_u32(c), t)

def lex(s: String) -> Token & String:
  lex_clean(skip(s))

type Frame is Data:
  InArray{acc: Json}
  InObject{key: String, acc: Json}

type Mode is Data:
  Want{}
  ArrFirst{}
  ArrNext{}
  ArrAfter{}
  ObjFirst{}
  ObjNext{}
  ObjAfter{}
  Colon{key: String}
  Finished{}
  Broken{message: String}

type Parser is Data:
  Parser{mode: Mode, stack: List<&2, Frame>, value: Json}

def accepted(stack: List<&2, Frame>, v: Json) -> Parser:
  match stack:
    case Nil{}: Parser{Finished{}, Nil{}, v}
    case InArray{acc} <> t: Parser{ArrAfter{}, t, Item{v, acc}}
    case InObject{k, acc} <> t: Parser{ObjAfter{}, t, Field{k, v, acc}}

def value_token(tok: Token, stack: List<&2, Frame>) -> Parser:
  match tok:
    case Atom{v}: accepted(stack, v)
    case Punct{'['}: Parser{ArrFirst{}, stack, End{}}
    case Punct{'{'}: Parser{ObjFirst{}, stack, End{}}
    case Bad{s}: Parser{Broken{s}, Nil{}, Null{}}
    case _: Parser{Broken{"Expected JSON value"}, Nil{}, Null{}}

def parser_step(p: Parser, tok: Token) -> Parser:
  match p tok:
    case Parser{Want{}, stack, _} tok: value_token(tok, stack)
    case Parser{ArrFirst{}, stack, acc} Punct{']'}: accepted(stack, Array{reverse(acc, End{})})
    case Parser{ArrFirst{}, stack, acc} tok: value_token(tok, InArray{acc} <> stack)
    case Parser{ArrNext{}, stack, acc} tok: value_token(tok, InArray{acc} <> stack)
    case Parser{ArrAfter{}, stack, acc} Punct{','}: Parser{ArrNext{}, stack, acc}
    case Parser{ArrAfter{}, stack, acc} Punct{']'}: accepted(stack, Array{reverse(acc, End{})})
    case Parser{ObjFirst{}, stack, acc} Punct{'}'}: accepted(stack, Object{reverse(acc, End{})})
    case Parser{ObjFirst{}, stack, acc} Atom{Text{k}}: Parser{Colon{k}, stack, acc}
    case Parser{ObjNext{}, stack, acc} Atom{Text{k}}: Parser{Colon{k}, stack, acc}
    case Parser{Colon{k}, stack, acc} Punct{':'}: Parser{Want{}, InObject{k, acc} <> stack, Null{}}
    case Parser{ObjAfter{}, stack, acc} Punct{','}: Parser{ObjNext{}, stack, acc}
    case Parser{ObjAfter{}, stack, acc} Punct{'}'}: accepted(stack, Object{reverse(acc, End{})})
    case Parser{Finished{}, stack, acc} Eof{}: Parser{Finished{}, stack, acc}
    case Parser{Broken{s}, _, _} _: Parser{Broken{s}, Nil{}, Null{}}
    case _ Bad{s}: Parser{Broken{s}, Nil{}, Null{}}
    case _ _: Parser{Broken{"Unexpected JSON token"}, Nil{}, Null{}}

def parse_loop(fuel: Nat, +p: Parser, input: Token & String) -> Result<&2, &2, String, Json>:
  match fuel p input:
    case 0n _ _: Fail{"JSON input too large"}
    case 1n+n Parser{Broken{msg}, _, _} _: Fail{msg}
    case 1n+n Parser{Finished{}, _, v} Tuple{Eof{}, _}: Done{v}
    case 1n+n Parser{Finished{}, _, v} _: Fail{"Trailing JSON input"}
    case 1n+n _ Tuple{tok, rest}: parse_loop(n, parser_step(p, tok), lex(rest))

def parse(+s: String) -> Result<&2, &2, String, Json>:
  parse_loop(2n+String.length(s), Parser{Want{}, Nil{}, Null{}}, lex(s))

def or_null(r: Result<&2, &2, String, Json>) -> Json:
  match r:
    case Done{j}: j
    case Fail{e}: Null{}
