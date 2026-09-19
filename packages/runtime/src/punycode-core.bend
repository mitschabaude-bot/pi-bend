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

def digit(+value: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(value, 26), (97 + value : U32), (22 + value : U32))}

def digitValue(+code: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 48) && U32.is_le(code, 57), Some{(code - 22 : U32)},
    Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 65) && U32.is_le(code, 90), Some{(code - 65 : U32)},
      Bool.pick(Maybe<&2, U32>, U32.is_ge(code, 97) && U32.is_le(code, 122), Some{(code - 97 : U32)}, None{})))

def writeLoop(fuel: Nat, +q: U32, +bias: U32, +k: U32, reversed: String, +t: U32, stop: Bool) -> Result<&2, &2, Error, String>:
  match fuel stop:
    case _ True{}: Done{SCon{digit(q), reversed}}
    case Zero{} False{}: Fail{Overflow{}}
    case Succ{rest} False{}:
      +next = ((q - t) / (36 - t) : U32)
      +step = (k + 36 : U32)
      +limit = threshold(step, bias)
      writeLoop(rest, next, bias, step, SCon{digit((t + (q - t) % (36 - t) : U32)), reversed}, limit, U32.is_lt(next, limit))

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

def readDigit(digit: Maybe<&2, U32>, value: U32, +weight: U32, k: U32, +t: U32) -> Result<&2, &2, Error, IntegerState>:
  match digit:
    case None{}: Fail{InvalidInput{}}
    case Some{+digit}: integerStep(U32.is_lt(digit, t), digitProduct(value, multiply(digit, weight)), weight, k, t)

def readLoop(text: String, +bias: U32, state: Result<&2, &2, Error, IntegerState>) -> Result<&2, &2, Error, Read>:
  match text state:
    case _ Fail{error}: Fail{error}
    case text Done{Complete{value}}: Done{Read{value, text}}
    case SNil{} _: Fail{InvalidInput{}}
    case SCon{Chr{code}, rest} Done{Reading{value, weight, +k}}: readLoop(rest, bias, readDigit(digitValue(code), value, weight, k, threshold(k, bias)))

def read(text: String, bias: U32, initial: U32) -> Result<&2, &2, Error, Read>:
  readLoop(text, bias, Done{Reading{initial, 1, 36}})
