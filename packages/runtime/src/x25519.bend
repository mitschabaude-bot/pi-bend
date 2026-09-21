import Base

# X25519, RFC 7748. Internal field elements are 32 little-endian byte limbs.
# Folding at 2^256 = 38 (mod p) keeps every product accumulator below 2^27:
# 32 * 38 * 255^2. No wide integer or foreign cryptographic primitive is used.
# Field operations preserve a canonical representative in [0, 2^255-19).
type Error is Data:
  InvalidLength{}
  InvalidByte{}
  LowOrderPoint{}

def repeat(count: Nat, +byte: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: repeat(rest, byte, byte <> tail)

def small(+value: U32) -> List<&2, U32>:
  U32.and(value, 255) <> U32.and(U32.shrn(value, 8n), 255) <> U32.and(U32.shrn(value, 16n), 255) <> U32.shrn(value, 24n) <> repeat(28n, 0, Nil{})

def prime() -> List<&2, U32>: 237 <> repeat(30n, 255, 127 <> Nil{})

# bit is 0 or 1. Selection never branches on a secret field value.
def select(a: List<&2, U32>, b: List<&2, U32>, +bit: U32) -> List<&2, U32>:
  match a b:
    case x <> xs +y <> ys: U32.xor(y, U32.and((0 - bit : U32), U32.xor(x, y))) <> select(xs, ys, bit)
    case _ _: Nil{}

type Carried is Data:
  Carried{bytes: List<&2, U32>, carry: U32}

def carry(bytes: List<&2, U32>, value: U32, reversed: List<&2, U32>) -> Carried:
  match bytes:
    case Nil{}: Carried{List.reverse(&2, U32, reversed), value}
    case head <> rest:
      +sum = (head + value : U32)
      carry(rest, U32.shrn(sum, 8n), U32.and(sum, 255) <> reversed)

def fold(result: Carried) -> Carried:
  match result:
    case Carried{bytes, high}: carry(bytes, (high * 38 : U32), Nil{})

type Difference is Data:
  Difference{bytes: List<&2, U32>, borrow: U32}

def subtractPrime(bytes: List<&2, U32>, modulus: List<&2, U32>, borrow: U32, reversed: List<&2, U32>) -> Difference:
  match bytes modulus:
    case head <> rest p <> ps:
      +difference = (head - p - borrow : U32)
      subtractPrime(rest, ps, U32.shrn(difference, 31n), U32.and(difference, 255) <> reversed)
    case _ _: Difference{List.reverse(&2, U32, reversed), borrow}

def reduced(original: List<&2, U32>, result: Difference) -> List<&2, U32>:
  match result:
    case Difference{bytes, borrow}: select(bytes, original, (1 - borrow : U32))

def canonical(+bytes: List<&2, U32>) -> List<&2, U32>:
  reduced(bytes, subtractPrime(bytes, prime(), 0, Nil{}))

def normalized(result: Carried) -> List<&2, U32>:
  match result:
    case Carried{bytes, _}: canonical(canonical(bytes))

# After the first fold, an overflow leaves fewer than 2^24 in the low limbs;
# a second fold therefore cannot overflow. Two subtractions cover all 256 bits.
def normalize(coefficients: List<&2, U32>) -> List<&2, U32>:
  normalized(fold(fold(carry(coefficients, 0, Nil{}))))

def scaleAdd(a: List<&2, U32>, b: List<&2, U32>, +scale: U32) -> List<&2, U32>:
  match a b:
    case x <> xs y <> ys: (x * scale + y : U32) <> scaleAdd(xs, ys, scale)
    case _ _: Nil{}

def add(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  normalize(scaleAdd(a, b, 1))

def subtractCoefficients(a: List<&2, U32>, b: List<&2, U32>, modulus: List<&2, U32>) -> List<&2, U32>:
  match a b modulus:
    case x <> xs y <> ys p <> ps: (x + 2 * p - y : U32) <> subtractCoefficients(xs, ys, ps)
    case _ _ _: Nil{}

def subtract(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  normalize(subtractCoefficients(a, b, prime()))

def rotate(reversed: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: Nil{}
    case head <> rest: (head * 38 : U32) <> List.reverse(&2, U32, rest)

def product(a: List<&2, U32>, +b: List<&2, U32>, accumulated: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}: accumulated
    case head <> rest: product(rest, rotate(List.reverse(&2, U32, b)), scaleAdd(b, accumulated, head))

def multiply(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  normalize(product(a, b, small(0)))

def square(+a: List<&2, U32>) -> List<&2, U32>: multiply(a, a)

# Bit lists are most significant first. Their length and access schedule are
# fixed for valid inputs; neither scalar bits nor field values index a table.
def byteBits(count: Nat, +byte: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: byteBits(rest, U32.shr(byte), U32.and(byte, 1) <> tail)

def bits(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case head <> rest: bits(rest, byteBits(8n, head, reversed))

def power(exponent: List<&2, U32>, +base: List<&2, U32>, result: List<&2, U32>) -> List<&2, U32>:
  match exponent:
    case Nil{}: result
    case bit <> rest:
      +squared = square(result)
      power(rest, base, select(multiply(squared, base), squared, bit))

def inverse(value: List<&2, U32>) -> List<&2, U32>:
  power(bits(235 <> repeat(30n, 255, 127 <> Nil{}), Nil{}), value, small(1))

type Ladder is Data:
  Ladder{x2: List<&2, U32>, z2: List<&2, U32>, x3: List<&2, U32>, z3: List<&2, U32>, previous: U32}

def swap(state: Ladder, +bit: U32) -> Ladder:
  match state:
    case Ladder{+x2, +z2, +x3, +z3, previous}:
      +change = U32.xor(bit, previous)
      Ladder{select(x3, x2, change), select(z3, z2, change), select(x2, x3, change), select(z2, z3, change), bit}

def step(base: List<&2, U32>, state: Ladder) -> Ladder:
  match state:
    case Ladder{+x2, +z2, +x3, +z3, bit}:
      +a = add(x2, z2)
      +aa = square(a)
      +b = subtract(x2, z2)
      +bb = square(b)
      +e = subtract(aa, bb)
      +da = multiply(subtract(x3, z3), a)
      +cb = multiply(add(x3, z3), b)
      Ladder{multiply(aa, bb), multiply(e, add(aa, multiply(small(121665), e))), square(add(da, cb)), multiply(base, square(subtract(da, cb))), bit}

def finish(state: Ladder) -> List<&2, U32>:
  match state:
    case Ladder{+x2, +z2, x3, z3, +previous}:
      multiply(select(x3, x2, previous), inverse(select(z3, z2, previous)))

def ladder(scalarBits: List<&2, U32>, +base: List<&2, U32>, state: Ladder) -> List<&2, U32>:
  match scalarBits:
    case Nil{}: finish(state)
    case bit <> rest: ladder(rest, base, step(base, swap(state, bit)))

def highByte(bytes: List<&2, U32>, +set: U32) -> List<&2, U32>:
  match bytes:
    case Nil{}: Nil{}
    case byte <> Nil{}: U32.or(U32.and(byte, 127), set) <> Nil{}
    case head <> rest: head <> highByte(rest, set)

def clamp(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: Nil{}
    case head <> rest: U32.and(head, 248) <> highByte(rest, 64)

def valid(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case head <> rest: U32.is_le(head, 255) && valid(rest)

def checked(length: Bool, bytesValid: Bool, scalar: List<&2, U32>, point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match length bytesValid:
    case False{} _: Fail{InvalidLength{}}
    case True{} False{}: Fail{InvalidByte{}}
    case True{} True{}:
      +base = canonical(highByte(point, 0))
      Done{ladder(List.drop(&2, U32, bits(clamp(scalar), Nil{}), 1n), base, Ladder{small(1), small(0), base, small(1), 0})}

# RFC 7748 requires masking the point's top bit and accepting noncanonical
# encodings modulo p. Raw multiplication can return zero; TLS must reject it.
def scalarMult(+scalar: List<&2, U32>, +point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  checked(Nat.is_eq(List.length(&2, U32, scalar), 32n) && Nat.is_eq(List.length(&2, U32, point), 32n), valid(scalar) && valid(point), scalar, point)

def publicKey(scalar: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  scalarMult(scalar, small(9))

def nonzero(bytes: List<&2, U32>, accumulated: U32) -> Bool:
  match bytes:
    case Nil{}: U32.is_ne(accumulated, 0)
    case head <> rest: nonzero(rest, U32.or(head, accumulated))

def sharedSecret(scalar: List<&2, U32>, point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, scalarMult(scalar, point), +value =>
    Bool.pick(Result<&2, &2, Error, List<&2, U32>>, nonzero(value, 0), Done{value}, Fail{LowOrderPoint{}}))
