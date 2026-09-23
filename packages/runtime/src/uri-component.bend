import Base

# Percent decoding is strict about encoded UTF-8. Literal characters pass
# through unchanged; incomplete escapes and invalid byte sequences fail.
type State is Data:
  Ready{}
  Pending{remaining: U32, scalar: U32, minimum: U32}

type Step is Data:
  Step{state: State, emitted: String}

def hex(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), Some{(code - 48 : U32)},
    Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 65) && U32.is_le(code, 70), Some{(code - 55 : U32)},
      Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 97) && U32.is_le(code, 102), Some{(code - 87 : U32)}, None{})))

def octet(high: Maybe<&2, U32>, low: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match high low:
    case Some{high} Some{low}: Some{(high * 16 + low : U32)}
    case _ _: None{}

def begin(+byte: U32) -> Maybe<&2, Step>:
  Bool.pick(Maybe<&2, Step>, U32.is_lt(byte, 128), Some{Step{Ready{}, SCon{Chr{byte}, ""}}},
    Bool.pick(Maybe<&2, Step>, U32.is_ge(byte, 194) && U32.is_le(byte, 223), Some{Step{Pending{1, (byte - 192 : U32), 128}, ""}},
      Bool.pick(Maybe<&2, Step>, U32.is_ge(byte, 224) && U32.is_le(byte, 239), Some{Step{Pending{2, (byte - 224 : U32), 2048}, ""}},
        Bool.pick(Maybe<&2, Step>, U32.is_ge(byte, 240) && U32.is_le(byte, 244), Some{Step{Pending{3, (byte - 240 : U32), 65536}, ""}}, None{}))))

def finishScalar(complete: Bool, remaining: U32, +scalar: U32, +minimum: U32) -> Maybe<&2, Step>:
  match complete:
    case False{}: Some{Step{Pending{remaining, scalar, minimum}, ""}}
    case True{}: Bool.pick(Unit -> Maybe<&2, Step>, U32.is_ge(scalar, minimum) && U32.is_le(scalar, 1114111) && Bool.not(U32.is_ge(scalar, 55296) && U32.is_le(scalar, 57343)), _ => Some{Step{Ready{}, SCon{Chr{scalar}, ""}}}, _ => None{})(Unit{})

def continuation(valid: Bool, +remaining: U32, scalar: U32, minimum: U32, byte: U32) -> Maybe<&2, Step>:
  match valid:
    case False{}: None{}
    case True{}: finishScalar(U32.is_eq(remaining, 1), (remaining - 1 : U32), (scalar * 64 + byte - 128 : U32), minimum)

def consume(state: State, value: Maybe<&2, U32>) -> Maybe<&2, Step>:
  match state value:
    case _ None{}: None{}
    case Ready{} Some{byte}: begin(byte)
    case Pending{remaining, scalar, minimum} Some{+byte}: continuation(U32.is_ge(byte, 128) && U32.is_le(byte, 191), remaining, scalar, minimum, byte)

def literal(state: State, char: Char) -> Maybe<&2, Step>:
  match state:
    case Ready{}: Some{Step{Ready{}, SCon{char, ""}}}
    case Pending{_, _, _}: None{}

def finished(state: State, fragments: List<&2, String>) -> Maybe<&2, String>:
  match state:
    case Ready{}: Some{String.join(List.reverse(&2, String, fragments), "")}
    case Pending{_, _, _}: None{}

def scan(text: String, step: Maybe<&2, Step>, fragments: List<&2, String>) -> Maybe<&2, String>:
  match text step:
    case _ None{}: None{}
    case SNil{} Some{Step{state, emitted}}: finished(state, emitted <> fragments)
    case SCon{Chr{37}, SCon{Chr{a}, SCon{Chr{b}, rest}}} Some{Step{state, emitted}}: scan(rest, consume(state, octet(hex(a), hex(b))), emitted <> fragments)
    case SCon{Chr{37}, _} _: None{}
    case SCon{char, rest} Some{Step{state, emitted}}: scan(rest, literal(state, char), emitted <> fragments)

def decode(text: String) -> Maybe<&2, String>:
  scan(text, Some{Step{Ready{}, ""}}, Nil{})
