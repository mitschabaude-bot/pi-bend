import Base

# SHA-1 (FIPS 180-4 sections 5.1.1, 6.1) over a byte list. SHA-1 is broken
# for collision resistance; it is provided for identifiers that other tools
# derive with it (the AWS SSO token cache file name), not for security.

type Digest is Data:
  Digest{a: U32, b: U32, c: U32, d: U32, e: U32}

def initial() -> Digest: Digest{1732584193, 4023233417, 2562383102, 271733878, 3285377520}

def rotl(+x: U32, +n: Nat) -> U32: U32.or(U32.shln(x, n), U32.shrn(x, Nat.sub(32n, n)))

def byteLength(bytes: List<&2, U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: byteLength(rest, 1n + count)

def zeros(count: Nat, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+left: 0 <> zeros(left, tail)

def lengthBytes(count: Nat, +bits: Nat, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+left: lengthBytes(left, Nat.div(bits, 256n), U32.from_nat(Nat.mod(bits, 256n)) <> tail)

# The message, 0x80, zeros to 56 mod 64, and the 64-bit bit length.
def padded(+bytes: List<&2, U32>) -> List<&2, U32>:
  +length = byteLength(bytes, 0n)
  List.append(&2, U32, bytes, 128 <> zeros(Nat.mod(Nat.sub(Nat.add(64n, 55n), Nat.mod(length, 64n)), 64n), lengthBytes(8n, Nat.mul(length, 8n), Nil{})))

def word(+a: U32, +b: U32, +c: U32, +d: U32) -> U32: U32.or(U32.or(U32.shln(a, 24n), U32.shln(b, 16n)), U32.or(U32.shln(c, 8n), d))

def prepend(+w: U32, pair: List<&2, U32> & List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match pair:
    case (list, rest): (w <> list, rest)

def words(count: Nat, bytes: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match count bytes:
    case 0n rest: (Nil{}, rest)
    case 1n+left a <> b <> c <> d <> rest: prepend(word(a, b, c, d), words(left, rest))
    case _ rest: (Nil{}, rest)

def at(values: List<&2, U32>, index: Nat) -> U32:
  match values index:
    case Nil{} _: 0
    case value <> _ 0n: value
    case _ <> rest 1n+left: at(rest, left)

# The 80-word schedule, built forward: w[t] = rotl1(w[t-3] ^ w[t-8] ^ w[t-14] ^ w[t-16]).
def extend(remaining: Nat, +schedule: List<&2, U32>, +t: Nat) -> List<&2, U32>:
  match remaining:
    case 0n: schedule
    case 1n+left:
      +next = rotl(U32.xor(U32.xor(at(schedule, Nat.sub(t, 3n)), at(schedule, Nat.sub(t, 8n))), U32.xor(at(schedule, Nat.sub(t, 14n)), at(schedule, Nat.sub(t, 16n)))), 1n)
      extend(left, List.append(&2, U32, schedule, [next]), 1n + t)

type Mixed is Data:
  Mixed{f: U32, k: U32}

def mix(+t: Nat, +b: U32, +c: U32, +d: U32) -> Mixed:
  Bool.pick(Mixed, Nat.is_lt(t, 20n), Mixed{U32.or(U32.and(b, c), U32.and(U32.not(b), d)), 1518500249}, Bool.pick(Mixed, Nat.is_lt(t, 40n), Mixed{U32.xor(U32.xor(b, c), d), 1859775393}, Bool.pick(Mixed, Nat.is_lt(t, 60n), Mixed{U32.or(U32.or(U32.and(b, c), U32.and(b, d)), U32.and(c, d)), 2400959708}, Mixed{U32.xor(U32.xor(b, c), d), 3395469782})))

def stepWith(work: Digest, +w: U32, mixed: Mixed) -> Digest:
  match work mixed:
    case Digest{+a, +b, c, d, e} Mixed{f, k}: Digest{(rotl(a, 5n) + f + e + k + w : U32), a, rotl(b, 30n), c, d}

def mixOf(work: Digest, +t: Nat) -> Mixed:
  match work:
    case Digest{_, b, c, d, _}: mix(t, b, c, d)

def step(+work: Digest, +t: Nat, +w: U32) -> Digest: stepWith(work, w, mixOf(work, t))

def rounds(schedule: List<&2, U32>, +t: Nat, work: Digest) -> Digest:
  match schedule:
    case Nil{}: work
    case w <> rest: rounds(rest, 1n + t, step(work, t, w))

def added(left: Digest, right: Digest) -> Digest:
  match left right:
    case Digest{a, b, c, d, e} Digest{f, g, h, i, j}: Digest{(a + f : U32), (b + g : U32), (c + h : U32), (d + i : U32), (e + j : U32)}

@unsafe def blocks(+hash: Digest, pair: List<&2, U32> & List<&2, U32>) -> Digest:
  match pair:
    case (Nil{}, _): hash
    case (+block, rest): blocks(added(hash, rounds(extend(64n, block, 16n), 0n, hash)), words(16n, rest))

def digest(bytes: List<&2, U32>) -> Digest: blocks(initial(), words(16n, padded(bytes)))

def wordBytes(+value: U32) -> List<&2, U32>:
  [U32.and(U32.shrn(value, 24n), 255), U32.and(U32.shrn(value, 16n), 255), U32.and(U32.shrn(value, 8n), 255), U32.and(value, 255)]

def toBytes(value: Digest) -> List<&2, U32>:
  match value:
    case Digest{a, b, c, d, e}: List.concat(&2, U32, [wordBytes(a), wordBytes(b), wordBytes(c), wordBytes(d), wordBytes(e)])

def hexDigit(+value: U32) -> Char: Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hexBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +b <> rest: SCon{hexDigit(U32.shrn(b, 4n)), SCon{hexDigit(U32.and(b, 15)), hexBytes(rest)}}

# The lowercase hexadecimal digest.
def hex(bytes: List<&2, U32>) -> String: hexBytes(toBytes(digest(bytes)))
