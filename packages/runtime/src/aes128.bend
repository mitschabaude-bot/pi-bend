import Base

# AES-128 encryption, FIPS 197. GCM uses the forward cipher for both directions.
# Four big-endian columns; no secret-indexed lookup tables.
type Block is Data:
  Block{a: U32, b: U32, c: U32, d: U32}

type ExpandedKey is Data:
  ExpandedKey{initial: Block, rounds: List<&2, Block>}

def xtime(+x: U32) -> U32:
  U32.xor(U32.and(U32.shln(x, 1n), 255), U32.and((0 - U32.shrn(x, 7n) : U32), 27))

def multiplyBits(count: Nat, +a: U32, +b: U32, product: U32) -> U32:
  match count:
    case 0n: product
    case 1n+rest: multiplyBits(rest, xtime(a), U32.shrn(b, 1n), U32.xor(product, U32.and(a, (0 - U32.and(b, 1) : U32))))

def multiply(a: U32, b: U32) -> U32: multiplyBits(8n, a, b, 0)

def rotateByte(+x: U32, left: Nat, right: Nat) -> U32:
  U32.and(U32.or(U32.shln(x, left), U32.shrn(x, right)), 255)

def substitute(+x: U32) -> U32:
  +x2 = multiply(x, x)
  +x4 = multiply(x2, x2)
  +x8 = multiply(x4, x4)
  +x16 = multiply(x8, x8)
  +x32 = multiply(x16, x16)
  +x64 = multiply(x32, x32)
  x128 = multiply(x64, x64)
  +inverse = multiply(multiply(multiply(x2, x4), multiply(x8, x16)), multiply(multiply(x32, x64), x128))
  U32.xor(99, U32.xor(inverse, U32.xor(rotateByte(inverse, 1n, 7n), U32.xor(rotateByte(inverse, 2n, 6n), U32.xor(rotateByte(inverse, 3n, 5n), rotateByte(inverse, 4n, 4n))))))

def pack(a: U32, b: U32, c: U32, d: U32) -> U32:
  (a * 16777216 + b * 65536 + c * 256 + d : U32)

def byte(word: U32, shift: Nat) -> U32: U32.and(U32.shrn(word, shift), 255)

def subWord(+word: U32) -> U32:
  pack(substitute(byte(word, 24n)), substitute(byte(word, 16n)), substitute(byte(word, 8n)), substitute(byte(word, 0n)))

def mixBytes(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  +sum = U32.xor(U32.xor(a, b), U32.xor(c, d))
  pack(U32.xor(U32.xor(a, sum), xtime(U32.xor(a, b))), U32.xor(U32.xor(b, sum), xtime(U32.xor(b, c))), U32.xor(U32.xor(c, sum), xtime(U32.xor(c, d))), U32.xor(U32.xor(d, sum), xtime(U32.xor(d, a))))

def mixWord(+word: U32) -> U32:
  mixBytes(byte(word, 24n), byte(word, 16n), byte(word, 8n), byte(word, 0n))

def shifted(a: U32, b: U32, c: U32, d: U32) -> U32:
  pack(substitute(byte(a, 24n)), substitute(byte(b, 16n)), substitute(byte(c, 8n)), substitute(byte(d, 0n)))

def subShift(state: Block) -> Block:
  match state:
    case Block{+a, +b, +c, +d}: Block{shifted(a, b, c, d), shifted(b, c, d, a), shifted(c, d, a, b), shifted(d, a, b, c)}

def mix(state: Block) -> Block:
  match state:
    case Block{a, b, c, d}: Block{mixWord(a), mixWord(b), mixWord(c), mixWord(d)}

def add(left: Block, right: Block) -> Block:
  match left right:
    case Block{a, b, c, d} Block{e, f, g, h}: Block{U32.xor(a, e), U32.xor(b, f), U32.xor(c, g), U32.xor(d, h)}

def nextKey(key: Block, constant: U32) -> Block:
  match key:
    case Block{a, b, c, +d}:
      rotated = U32.or(U32.shln(d, 8n), U32.shrn(d, 24n))
      +e = U32.xor(a, U32.xor(subWord(rotated), U32.shln(constant, 24n)))
      +f = U32.xor(b, e)
      +g = U32.xor(c, f)
      Block{e, f, g, U32.xor(d, g)}

def expandRounds(count: Nat, key: Block, +constant: U32) -> List<&2, Block>:
  match count:
    case 0n: Nil{}
    case 1n+rest:
      +next = nextKey(key, constant)
      next <> expandRounds(rest, next, xtime(constant))

def expand(+key: Block) -> ExpandedKey: ExpandedKey{key, expandRounds(10n, key, 1)}

def rounds(keys: List<&2, Block>, state: Block) -> Block:
  match keys:
    case Nil{}: state
    case key <> Nil{}: add(subShift(state), key)
    case key <> rest: rounds(rest, add(mix(subShift(state)), key))

def encrypt(key: ExpandedKey, plaintext: Block) -> Block:
  match key:
    case ExpandedKey{initial, keys}: rounds(keys, add(plaintext, initial))

def valid(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case head <> rest: U32.is_le(head, 255) && valid(rest)

def parsed(valid: Bool, block: Block) -> Maybe<&2, Block>:
  match valid:
    case True{}: Some{block}
    case False{}: None{}

def fromBytes(+bytes: List<&2, U32>) -> Maybe<&2, Block>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      parsed(valid(bytes), Block{pack(a, b, c, d), pack(e, f, g, h), pack(i, j, k, l), pack(m, n, o, p)})
    case _: None{}

def wordBytes(+word: U32) -> List<&2, U32>:
  byte(word, 24n) <> byte(word, 16n) <> byte(word, 8n) <> byte(word, 0n) <> Nil{}

def toBytes(block: Block) -> List<&2, U32>:
  match block:
    case Block{a, b, c, d}: List.append(&2, U32, wordBytes(a), List.append(&2, U32, wordBytes(b), List.append(&2, U32, wordBytes(c), wordBytes(d))))
