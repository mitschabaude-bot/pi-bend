import Base



# RFC 3492 parameters and generalized integers. Match the 31-bit arithmetic
# bound used by the reference Punycode implementation; report overflow instead
# of returning a wrapped result.
# Scalar validation is separate from IDNA mapping and label restrictions.
def scalar(+code: U32) -> Bool:
  U32.is_le(code, 1114111) && Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343))

type Error is Data:
  InvalidInput{}
  Overflow{}

def checked(fits: Bool, value: U32) -> Result<&2, &2, Error, U32>:
  match fits:
    case True{}: Done{value}
    case False{}: Fail{Overflow{}}

def add(+left: U32, +right: U32) -> Result<&2, &2, Error, U32>:
  checked(U32.is_le(left, 2147483647) && U32.is_le(right, (2147483647 - left : U32)), (left + right : U32))

def multiply(+left: U32, +right: U32) -> Result<&2, &2, Error, U32>:
  match right:
    case 0: Done{0}
    case other: checked(U32.is_le(left, (2147483647 / other : U32)), (left * right : U32))

def threshold(+k: U32, +bias: U32) -> U32:
  Bool.pick(U32, U32.is_le(k, bias), 1, Bool.pick(U32, U32.is_ge(k, (bias + 26 : U32)), 26, (k - bias : U32)))

def adapted(fuel: Nat, +delta: U32, k: U32, small: Bool) -> U32:
  match fuel small:
    case _ True{}: (k + 36 * delta / (delta + 38) : U32)
    case Succ{rest} False{}:
      +next = (delta / 35 : U32)
      adapted(rest, next, (k + 36 : U32), U32.is_le(next, 455))
    case Zero{} False{}: k

def adaptValue(+delta: U32, points: U32) -> U32:
  +value = (delta + delta / points : U32)
  adapted(32n, value, 0, U32.is_le(value, 455))

def adapt(+delta: U32, points: U32, first: Bool) -> U32:
  adaptValue(Bool.pick(U32, first, (delta / 700 : U32), (delta / 2 : U32)), points)

def digitCore(+value: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(value, 26), (97 + value : U32), (22 + value : U32))}

def digitValue(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), Some{(code - 22 : U32)},
    Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 65) && U32.is_le(code, 90), Some{(code - 65 : U32)},
      Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 97) && U32.is_le(code, 122), Some{(code - 97 : U32)}, None{})))

def writeLoop(fuel: Nat, +q: U32, +bias: U32, +k: U32, reversed: String, +t: U32, stop: Bool) -> Result<&2, &2, Error, String>:
  match fuel stop:
    case _ True{}: Done{SCon{digitCore(q), reversed}}
    case Zero{} False{}: Fail{Overflow{}}
    case Succ{rest} False{}:
      +next = ((q - t) / (36 - t) : U32)
      +step = (k + 36 : U32)
      +limit = threshold(step, bias)
      writeLoop(rest, next, bias, step, SCon{digitCore((t + (q - t) % (36 - t) : U32)), reversed}, limit, U32.is_lt(next, limit))

# Append the encoded integer to an already reversed output accumulator.
def write(+q: U32, +bias: U32, reversed: String) -> Result<&2, &2, Error, String>:
  +t = threshold(36, bias)
  writeLoop(32n, q, bias, 36, reversed, t, U32.is_lt(q, t))

type IntegerState is Data:
  Reading{value: U32, weight: U32, k: U32}
  Complete{value: U32}

type Read is Data:
  Read{value: U32, rest: String}

def weighted(value: U32, weight: Result<&2, &2, Error, U32>, k: U32) -> Result<&2, &2, Error, IntegerState>:
  match weight:
    case Fail{error}: Fail{error}
    case Done{weight}: Done{Reading{value, weight, (k + 36 : U32)}}

def integerStep(stop: Bool, value: Result<&2, &2, Error, U32>, weight: U32, k: U32, t: U32) -> Result<&2, &2, Error, IntegerState>:
  match stop value:
    case _ Fail{error}: Fail{error}
    case True{} Done{value}: Done{Complete{value}}
    case False{} Done{value}: weighted(value, multiply(weight, (36 - t : U32)), k)

def digitProduct(value: U32, product: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, U32>:
  match product:
    case Fail{error}: Fail{error}
    case Done{product}: add(value, product)

def readDigit(digitCore: Maybe<&2, U32>, value: U32, +weight: U32, k: U32, +t: U32) -> Result<&2, &2, Error, IntegerState>:
  match digitCore:
    case None{}: Fail{InvalidInput{}}
    case Some{+digitCore}: integerStep(U32.is_lt(digitCore, t), digitProduct(value, multiply(digitCore, weight)), weight, k, t)

def readLoop(text: String, +bias: U32, state: Result<&2, &2, Error, IntegerState>) -> Result<&2, &2, Error, Read>:
  match text state:
    case _ Fail{error}: Fail{error}
    case text Done{Complete{value}}: Done{Read{value, text}}
    case SNil{} _: Fail{InvalidInput{}}
    case SCon{Chr{code}, rest} Done{Reading{value, weight, +k}}: readLoop(rest, bias, readDigit(digitValue(code), value, weight, k, threshold(k, bias)))

def read(text: String, bias: U32, initial: U32) -> Result<&2, &2, Error, Read>:
  readLoop(text, bias, Done{Reading{initial, 1, 36}})


type Basics is Data:
  Basics{count: U32, total: U32, reversed: String}

def basicEncode(valid: Bool, ascii: Bool, code: U32, state: Basics) -> Result<&2, &2, Error, Basics>:
  match valid ascii state:
    case False{} _ _: Fail{InvalidInput{}}
    case True{} True{} Basics{count, total, reversed}: Done{Basics{(count + 1 : U32), (total + 1 : U32), SCon{Chr{code}, reversed}}}
    case True{} False{} Basics{count, total, reversed}: Done{Basics{count, (total + 1 : U32), reversed}}

def basicsEncode(text: String, state: Result<&2, &2, Error, Basics>) -> Result<&2, &2, Error, Basics>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} Done{state}: basicsEncode(rest, basicEncode(scalar(code), U32.is_lt(code, 128), code, state))

type EncodeState is Data:
  EncodeState{next: U32, delta: U32, bias: U32, handled: U32, reversed: String}

def nextCode(text: String, +floor: U32, +best: U32) -> U32:
  match text:
    case SNil{}: best
    case SCon{Chr{+code}, rest}: nextCode(rest, floor, Bool.pick(U32, U32.is_ge(code, floor), U32.min(code, best), best))

def withDelta(result: Result<&2, &2, Error, U32>, next: U32, bias: U32, handled: U32, reversed: String) -> Result<&2, &2, Error, EncodeState>:
  match result:
    case Fail{error}: Fail{error}
    case Done{delta}: Done{EncodeState{next, delta, bias, handled, reversed}}

def advanced(product: Result<&2, &2, Error, U32>, delta: U32, next: U32, bias: U32, handled: U32, reversed: String) -> Result<&2, &2, Error, EncodeState>:
  match product:
    case Fail{error}: Fail{error}
    case Done{product}: withDelta(add(delta, product), next, bias, handled, reversed)

def advance(+next: U32, state: EncodeState) -> Result<&2, &2, Error, EncodeState>:
  match state:
    case EncodeState{previous, delta, bias, +handled, reversed}: advanced(multiply((next - previous : U32), (handled + 1 : U32)), delta, next, bias, handled, reversed)

def emitted(result: Result<&2, &2, Error, String>, next: U32, delta: U32, +handled: U32, basicsEncode: U32) -> Result<&2, &2, Error, EncodeState>:
  match result:
    case Fail{error}: Fail{error}
    case Done{reversed}: Done{EncodeState{next, 0, adapt(delta, (handled + 1 : U32), U32.is_eq(handled, basicsEncode)), (handled + 1 : U32), reversed}}

def pointEncode(less: Bool, equal: Bool, state: EncodeState, basicsEncode: U32) -> Result<&2, &2, Error, EncodeState>:
  match less equal state:
    case True{} _ EncodeState{next, delta, bias, handled, reversed}: withDelta(add(delta, 1), next, bias, handled, reversed)
    case False{} True{} EncodeState{next, +delta, bias, handled, reversed}: emitted(write(delta, bias, reversed), next, delta, handled, basicsEncode)
    case False{} False{} state: Done{state}

def scan(text: String, +basicsEncode: U32, state: Result<&2, &2, Error, EncodeState>) -> Result<&2, &2, Error, EncodeState>:
  match text state:
    case _ Fail{error}: Fail{error}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} Done{EncodeState{+next, delta, bias, handled, reversed}}: scan(rest, basicsEncode, pointEncode(U32.is_lt(code, next), U32.is_eq(code, next), EncodeState{next, delta, bias, handled, reversed}, basicsEncode))

type Progress is Data:
  Active{state: EncodeState}
  EncodeComplete{output: String}

def continued(result: Result<&2, &2, Error, EncodeState>) -> Result<&2, &2, Error, Progress>:
  match result:
    case Fail{error}: Fail{error}
    case Done{state}: Done{Active{state}}

def checkedPass(done: Bool, state: EncodeState) -> Result<&2, &2, Error, Progress>:
  match done state:
    case True{} EncodeState{_, _, _, _, reversed}: Done{EncodeComplete{String.reverse(reversed)}}
    case False{} EncodeState{next, delta, bias, handled, reversed}: continued(withDelta(add(delta, 1), (next + 1 : U32), bias, handled, reversed))

def passResult(total: U32, result: Result<&2, &2, Error, EncodeState>) -> Result<&2, &2, Error, Progress>:
  match result:
    case Fail{error}: Fail{error}
    case Done{EncodeState{next, delta, bias, +handled, reversed}}: checkedPass(U32.is_eq(handled, total), EncodeState{next, delta, bias, handled, reversed})

def pass(+text: String, basicsEncode: U32, total: U32, state: EncodeState) -> Result<&2, &2, Error, Progress>:
  match state:
    case EncodeState{+next, delta, bias, handled, reversed}: passResult(total, scan(text, basicsEncode, advance(nextCode(text, next, 1114111), EncodeState{next, delta, bias, handled, reversed})))

# Each pass emits at least one previously unhandled scalar; input length is
# therefore a structural upper bound on the number of passes.
def loopEncode(fuel: String, +text: String, +basicsEncode: U32, +total: U32, progress: Result<&2, &2, Error, Progress>) -> Result<&2, &2, Error, String>:
  match fuel progress:
    case _ Fail{error}: Fail{error}
    case _ Done{EncodeComplete{output}}: Done{output}
    case SNil{} _: Fail{Overflow{}}
    case SCon{_, rest} Done{Active{state}}: loopEncode(rest, text, basicsEncode, total, pass(text, basicsEncode, total, state))

def initial(done: Bool, count: U32, reversed: String) -> Progress:
  match done:
    case True{}: EncodeComplete{String.reverse(reversed)}
    case False{}: Active{EncodeState{128, 0, 72, count, reversed}}

def preparedEncode(+text: String, result: Result<&2, &2, Error, Basics>) -> Result<&2, &2, Error, String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Basics{+count, +total, +reversed}}:
      loopEncode(text, text, count, total, Done{initial(U32.is_eq(count, total), count, Bool.pick(String, U32.is_eq(count, 0), reversed, SCon{'-', reversed}))})

def encode(+text: String) -> Result<&2, &2, Error, String>:
  preparedEncode(text, basicsEncode(text, Done{Basics{0, 0, ""}}))


type Input is Data:
  Input{basic: String, encoded: String}

# Split at the final delimiter, retaining ASCII case. A leading delimiter alone
# is not a basic prefix, matching the reference decoder's invalid-input path.
def divide(reversed: String, suffix: String) -> Input:
  match reversed:
    case SNil{}: Input{"", suffix}
    case SCon{'-', SNil{}}: Input{"", SCon{'-', suffix}}
    case SCon{'-', rest}: Input{String.reverse(rest), suffix}
    case SCon{char, rest}: divide(rest, SCon{char, suffix})

type State is Data:
  State{output: List<&2, U32>, count: U32, next: U32, index: U32, bias: U32, rest: String}

def basics(text: String, reversed: List<&2, U32>, count: U32, encoded: String, valid: Bool) -> Result<&2, &2, Error, State>:
  match text valid:
    case _ False{}: Fail{InvalidInput{}}
    case SNil{} True{}: Done{State{List.reverse(&2, U32, reversed), count, 128, 0, 72, encoded}}
    case SCon{Chr{+code}, rest} True{}: basics(rest, code <> reversed, (count + 1 : U32), encoded, U32.is_lt(code, 128))

def prepend(reversed: List<&2, U32>, suffix: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: suffix
    case head <> rest: prepend(rest, head <> suffix)

def insert(parts: List<&2, U32>, index: U32, value: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match parts index:
    case parts 0: Done{prepend(reversed, value <> parts)}
    case head <> rest remaining: insert(rest, (remaining - 1 : U32), value, head <> reversed)
    case Nil{} _: Fail{InvalidInput{}}

def inserted(output: Result<&2, &2, Error, List<&2, U32>>, count: U32, next: U32, index: U32, bias: U32, rest: String) -> Result<&2, &2, Error, State>:
  match output:
    case Fail{error}: Fail{error}
    case Done{output}: Done{State{output, count, next, (index + 1 : U32), bias, rest}}

def incremented(value: Result<&2, &2, Error, U32>, output: List<&2, U32>, count: U32, +index: U32, bias: U32, rest: String) -> Result<&2, &2, Error, State>:
  match value:
    case Fail{error}: Fail{error}
    case Done{+next}: inserted(insert(output, index, next, Nil{}), count, next, index, bias, rest)

def decoded(result: Result<&2, &2, Error, Read>, output: List<&2, U32>, +count: U32, next: U32, +previous: U32) -> Result<&2, &2, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Read{+value, rest}}:
      incremented(add(next, (value / count : U32)), output, count, (value % count : U32), adapt((value - previous : U32), count, U32.is_eq(previous, 0)), rest)

def stepDecode(state: State) -> Result<&2, &2, Error, State>:
  match state:
    case State{output, count, next, +index, bias, rest}: decoded(read(rest, bias, index), output, (count + 1 : U32), next, index)

# Keep decoded points numeric until parsing finishes. This preserves overflow
# precedence while ensuring no invalid native Char can be constructed.
def scalarText(valid: Bool, point: U32, reversed: String) -> Result<&2, &2, Error, String>:
  match valid:
    case False{}: Fail{InvalidInput{}}
    case True{}: Done{SCon{Chr{point}, reversed}}

def text(points: List<&2, U32>, state: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, String>:
  match points state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{reversed}: Done{String.reverse(reversed)}
    case +point <> rest Done{reversed}: text(rest, scalarText(scalar(point), point, reversed))

# One iteration consumes at least one encoded ASCII character.
def loop(fuel: String, state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, String>:
  match fuel state:
    case _ Fail{error}: Fail{error}
    case _ Done{State{output, _, _, _, _, SNil{}}}: text(output, Done{""})
    case SNil{} _: Fail{InvalidInput{}}
    case SCon{_, fuel} Done{state}: loop(fuel, stepDecode(state))

def prepared(input: Input) -> Result<&2, &2, Error, String>:
  match input:
    case Input{basic, +encoded}: loop(encoded, basics(basic, Nil{}, 0, encoded, True{}))

def decode(input: String) -> Result<&2, &2, Error, String>:
  prepared(divide(String.reverse(input), ""))


# Unicode-scalar Punycode, without the xn-- prefix. IDNA mapping, NFC, label
# validity, case folding and DNS length policy belong to the hostname layer.
