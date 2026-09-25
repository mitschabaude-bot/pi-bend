import Base
import ./aes128.bend as AES
import ./u64.bend as Word

# AES-128-GCM for TLS: 96-bit nonces and full 128-bit tags (SP 800-38D).
# Each key/nonce pair must be used for encryption at most once. The TLS record
# owner supplies that uniqueness through its sequence number.
type Nonce is Data:
  Nonce{a: U32, b: U32, c: U32}

type GcmKey is Data:
  GcmKey{cipher: AES.ExpandedKey, hash: AES.Block}

type Sealed is Data:
  Sealed{ciphertext: List<&2, U32>, tag: AES.Block}

type Error is Data:
  InvalidByte{}
  MessageTooLong{}
  AuthenticationFailed{}

def key(value: AES.Block) -> GcmKey:
  +cipher = AES.expand(value)
  GcmKey{cipher, AES.encrypt(cipher, AES.Block{0, 0, 0, 0})}

def initial(nonce: Nonce) -> AES.Block:
  match nonce:
    case Nonce{a, b, c}: AES.Block{a, b, c, 1}

# GHASH multiplies in GF(2^128) with x^128 + x^7 + x^2 + x + 1, bits most
# significant first. Carryless 32-bit products use integer multiplication on
# every fourth bit (BearSSL's ctmul): at most eight terms meet in one
# position, so sums stay below the next bit of the same class. No table or
# branch depends on the hash key or data.
type Wide is Data:
  Wide{high: U32, low: U32}

def spread(+x: U32, +y0: U32, +y1: U32, +y2: U32, +y3: U32) -> U32:
  U32.xor(U32.xor((x * y0 : U32), (x * y1 : U32)), U32.xor((x * y2 : U32), (x * y3 : U32)))

def carryless(+x: U32, +y: U32) -> Wide:
  +x0 = U32.and(x, 286331153)
  +x1 = U32.and(x, 572662306)
  +x2 = U32.and(x, 1145324612)
  +x3 = U32.and(x, 2290649224)
  +y0 = U32.and(y, 286331153)
  +y1 = U32.and(y, 572662306)
  +y2 = U32.and(y, 1145324612)
  +y3 = U32.and(y, 2290649224)
  l0 = U32.xor(U32.xor((x0 * y0 : U32), (x1 * y3 : U32)), U32.xor((x2 * y2 : U32), (x3 * y1 : U32)))
  l1 = U32.xor(U32.xor((x0 * y1 : U32), (x1 * y0 : U32)), U32.xor((x2 * y3 : U32), (x3 * y2 : U32)))
  l2 = U32.xor(U32.xor((x0 * y2 : U32), (x1 * y1 : U32)), U32.xor((x2 * y0 : U32), (x3 * y3 : U32)))
  l3 = U32.xor(U32.xor((x0 * y3 : U32), (x1 * y2 : U32)), U32.xor((x2 * y1 : U32), (x3 * y0 : U32)))
  h0 = U32.xor(U32.xor(U32.mul_hi(x0, y0), U32.mul_hi(x1, y3)), U32.xor(U32.mul_hi(x2, y2), U32.mul_hi(x3, y1)))
  h1 = U32.xor(U32.xor(U32.mul_hi(x0, y1), U32.mul_hi(x1, y0)), U32.xor(U32.mul_hi(x2, y3), U32.mul_hi(x3, y2)))
  h2 = U32.xor(U32.xor(U32.mul_hi(x0, y2), U32.mul_hi(x1, y1)), U32.xor(U32.mul_hi(x2, y0), U32.mul_hi(x3, y3)))
  h3 = U32.xor(U32.xor(U32.mul_hi(x0, y3), U32.mul_hi(x1, y2)), U32.xor(U32.mul_hi(x2, y1), U32.mul_hi(x3, y0)))
  Wide{U32.or(U32.or(U32.and(h0, 286331153), U32.and(h1, 572662306)), U32.or(U32.and(h2, 1145324612), U32.and(h3, 2290649224))), U32.or(U32.or(U32.and(l0, 286331153), U32.and(l1, 572662306)), U32.or(U32.and(l2, 1145324612), U32.and(l3, 2290649224)))}

# Karatsuba: a 64-bit carryless product from three 32-bit ones, as big-endian words.
def karatsuba(high: Wide, low: Wide, middle: Wide) -> AES.Block:
  match high low middle:
    case Wide{+h1, +h0} Wide{+l1, +l0} Wide{m1, m0}:
      AES.Block{h1, U32.xor(h0, U32.xor(m1, U32.xor(h1, l1))), U32.xor(l1, U32.xor(m0, U32.xor(h0, l0))), l0}

def product64(+a1: U32, +a0: U32, +b1: U32, +b0: U32) -> AES.Block:
  karatsuba(carryless(a1, b1), carryless(a0, b0), carryless(U32.xor(a1, a0), U32.xor(b1, b0)))

# The 256-bit product shifted left once (GHASH's bit reflection), then reduced:
# each low word folds into the words above it, the last fold feeding the first.
def fold(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32) -> AES.Block:
  +z0 = U32.shln(w0, 1n)
  +z1 = U32.or(U32.shln(w1, 1n), U32.shrn(w0, 31n))
  +z2 = U32.or(U32.shln(w2, 1n), U32.shrn(w1, 31n))
  z3 = U32.or(U32.shln(w3, 1n), U32.shrn(w2, 31n))
  z4 = U32.or(U32.shln(w4, 1n), U32.shrn(w3, 31n))
  z5 = U32.or(U32.shln(w5, 1n), U32.shrn(w4, 31n))
  z6 = U32.or(U32.shln(w6, 1n), U32.shrn(w5, 31n))
  z7 = U32.or(U32.shln(w7, 1n), U32.shrn(w6, 31n))
  +f3 = U32.xor(z3, U32.xor(U32.xor(U32.shln(z0, 31n), U32.shln(z0, 30n)), U32.shln(z0, 25n)))
  +f4 = U32.xor(z4, U32.xor(U32.xor(U32.shln(z1, 31n), U32.shln(z1, 30n)), U32.shln(z1, 25n)))
  +f5 = U32.xor(z5, U32.xor(U32.xor(U32.shln(z2, 31n), U32.shln(z2, 30n)), U32.shln(z2, 25n)))
  +f6 = U32.xor(z6, U32.xor(U32.xor(U32.shln(f3, 31n), U32.shln(f3, 30n)), U32.shln(f3, 25n)))
  AES.Block{U32.xor(z7, U32.xor(U32.xor(f3, U32.shrn(f3, 1n)), U32.xor(U32.shrn(f3, 2n), U32.shrn(f3, 7n)))), U32.xor(f6, U32.xor(U32.xor(z2, U32.shrn(z2, 1n)), U32.xor(U32.shrn(z2, 2n), U32.shrn(z2, 7n)))), U32.xor(f5, U32.xor(U32.xor(z1, U32.shrn(z1, 1n)), U32.xor(U32.shrn(z1, 2n), U32.shrn(z1, 7n)))), U32.xor(f4, U32.xor(U32.xor(z0, U32.shrn(z0, 1n)), U32.xor(U32.shrn(z0, 2n), U32.shrn(z0, 7n))))}

def combine(high: AES.Block, low: AES.Block, middle: AES.Block) -> AES.Block:
  match high low middle:
    case AES.Block{+h3, +h2, +h1, +h0} AES.Block{+l3, +l2, +l1, +l0} AES.Block{m3, m2, m1, m0}:
      fold(l0, l1, U32.xor(l2, U32.xor(m0, U32.xor(h0, l0))), U32.xor(l3, U32.xor(m1, U32.xor(h1, l1))), U32.xor(h0, U32.xor(m2, U32.xor(h2, l2))), U32.xor(h1, U32.xor(m3, U32.xor(h3, l3))), h2, h3)

def multiply(left: AES.Block, right: AES.Block) -> AES.Block:
  match left right:
    case AES.Block{+a3, +a2, +a1, +a0} AES.Block{+b3, +b2, +b1, +b0}:
      combine(product64(a3, a2, b3, b2), product64(a1, a0, b1, b0), product64(U32.xor(a3, a1), U32.xor(a2, a0), U32.xor(b3, b1), U32.xor(b2, b0)))

def padded(bytes: List<&2, U32>, count: Nat) -> List<&2, U32>:
  match bytes count:
    case _ 0n: Nil{}
    case Nil{} 1n+rest: 0 <> padded(Nil{}, rest)
    case head <> tail 1n+rest: head <> padded(tail, rest)

def absorbPartial(+h: AES.Block, state: AES.Block, block: Maybe<&2, AES.Block>) -> AES.Block:
  match block:
    case None{}: state
    case Some{value}: multiply(AES.add(state, value), h)

def hashRest(+h: AES.Block, state: AES.Block, bytes: List<&2, U32>) -> AES.Block:
  match bytes:
    case Nil{}: state
    case _: absorbPartial(h, state, AES.fromBytes(padded(bytes, 16n)))

# Sixteen bytes at a time; a short last block is padded with zeros.
def hash(bytes: List<&2, U32>, +h: AES.Block, state: AES.Block) -> AES.Block:
  match bytes:
    case x0 <> x1 <> x2 <> x3 <> x4 <> x5 <> x6 <> x7 <> x8 <> x9 <> x10 <> x11 <> x12 <> x13 <> x14 <> x15 <> rest:
      hash(rest, h, multiply(AES.add(state, AES.Block{AES.pack(x0, x1, x2, x3), AES.pack(x4, x5, x6, x7), AES.pack(x8, x9, x10, x11), AES.pack(x12, x13, x14, x15)}), h))
    case rest: hashRest(h, state, rest)

type Lengths is Data:
  Lengths{aad: Word.U64, text: Word.U64}

def lengthBlock(sizes: Lengths) -> AES.Block:
  match sizes:
    case Lengths{Word.U64{ah, +al}, Word.U64{ch, +cl}}:
      AES.Block{U32.or(U32.shln(ah, 3n), U32.shrn(al, 29n)), U32.shln(al, 3n), U32.or(U32.shln(ch, 3n), U32.shrn(cl, 29n)), U32.shln(cl, 3n)}

def tag(cipher: AES.ExpandedKey, +h: AES.Block, nonce: Nonce, aad: List<&2, U32>, text: List<&2, U32>, sizes: Lengths) -> AES.Block:
  authenticated = hash(text, h, hash(aad, h, AES.Block{0, 0, 0, 0}))
  final = multiply(AES.add(authenticated, lengthBlock(sizes)), h)
  AES.add(final, AES.encrypt(cipher, initial(nonce)))

def streamBytes(pair: AES.Pair) -> List<&2, U32>:
  match pair:
    case AES.Pair{first, second}: List.append(&2, U32, AES.toBytes(first), AES.toBytes(second))

def xorTail(bytes: List<&2, U32>, stream: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes stream:
    case x <> xs k <> ks: xorTail(xs, ks, U32.xor(x, k) <> reversed)
    case _ _: List.reverse(&2, U32, reversed)

def counterBlock(nonce: Nonce, counter: U32) -> AES.Block:
  match nonce:
    case Nonce{a, b, c}: AES.Block{a, b, c, counter}

def stream(cipher: AES.ExpandedKey, +nonce: Nonce, +counter: U32) -> AES.Pair:
  AES.encryptPair(cipher, counterBlock(nonce, counter), counterBlock(nonce, (counter + 1 : U32)))

# Thirty-two bytes xored with two keystream blocks, pushed in reverse.
def push(pair: AES.Pair, x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32, x8: U32, x9: U32, x10: U32, x11: U32, x12: U32, x13: U32, x14: U32, x15: U32, x16: U32, x17: U32, x18: U32, x19: U32, x20: U32, x21: U32, x22: U32, x23: U32, x24: U32, x25: U32, x26: U32, x27: U32, x28: U32, x29: U32, x30: U32, x31: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match pair:
    case AES.Pair{AES.Block{+k0, +k1, +k2, +k3}, AES.Block{+k4, +k5, +k6, +k7}}:
      U32.xor(x31, AES.byte(k7, 0n)) <> U32.xor(x30, AES.byte(k7, 8n)) <> U32.xor(x29, AES.byte(k7, 16n)) <> U32.xor(x28, AES.byte(k7, 24n)) <> U32.xor(x27, AES.byte(k6, 0n)) <> U32.xor(x26, AES.byte(k6, 8n)) <> U32.xor(x25, AES.byte(k6, 16n)) <> U32.xor(x24, AES.byte(k6, 24n)) <> U32.xor(x23, AES.byte(k5, 0n)) <> U32.xor(x22, AES.byte(k5, 8n)) <> U32.xor(x21, AES.byte(k5, 16n)) <> U32.xor(x20, AES.byte(k5, 24n)) <> U32.xor(x19, AES.byte(k4, 0n)) <> U32.xor(x18, AES.byte(k4, 8n)) <> U32.xor(x17, AES.byte(k4, 16n)) <> U32.xor(x16, AES.byte(k4, 24n)) <> U32.xor(x15, AES.byte(k3, 0n)) <> U32.xor(x14, AES.byte(k3, 8n)) <> U32.xor(x13, AES.byte(k3, 16n)) <> U32.xor(x12, AES.byte(k3, 24n)) <> U32.xor(x11, AES.byte(k2, 0n)) <> U32.xor(x10, AES.byte(k2, 8n)) <> U32.xor(x9, AES.byte(k2, 16n)) <> U32.xor(x8, AES.byte(k2, 24n)) <> U32.xor(x7, AES.byte(k1, 0n)) <> U32.xor(x6, AES.byte(k1, 8n)) <> U32.xor(x5, AES.byte(k1, 16n)) <> U32.xor(x4, AES.byte(k1, 24n)) <> U32.xor(x3, AES.byte(k0, 0n)) <> U32.xor(x2, AES.byte(k0, 8n)) <> U32.xor(x1, AES.byte(k0, 16n)) <> U32.xor(x0, AES.byte(k0, 24n)) <> reversed

# Counter mode, two blocks per cipher call; the counter is the last word.
def cryptBlocks(bytes: List<&2, U32>, +cipher: AES.ExpandedKey, +nonce: Nonce, +counter: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: List.reverse(&2, U32, reversed)
    case x0 <> x1 <> x2 <> x3 <> x4 <> x5 <> x6 <> x7 <> x8 <> x9 <> x10 <> x11 <> x12 <> x13 <> x14 <> x15 <> x16 <> x17 <> x18 <> x19 <> x20 <> x21 <> x22 <> x23 <> x24 <> x25 <> x26 <> x27 <> x28 <> x29 <> x30 <> x31 <> rest:
      cryptBlocks(rest, cipher, nonce, (counter + 2 : U32), push(stream(cipher, nonce, counter), x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19, x20, x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31, reversed))
    case rest: xorTail(rest, streamBytes(stream(cipher, nonce, counter)), reversed)

def crypt(cipher: AES.ExpandedKey, nonce: Nonce, bytes: List<&2, U32>) -> List<&2, U32>:
  cryptBlocks(bytes, cipher, nonce, 2, Nil{})

type Scan is Data:
  Scan{high: U32, length: Word.U64}

# Ors every byte's bits above the low eight and counts, in one pass.
def scan(bytes: List<&2, U32>, +high: U32, +countHigh: U32, +countLow: U32) -> Scan:
  match bytes:
    case Nil{}: Scan{high, Word.U64{countHigh, countLow}}
    case head <> rest:
      +next = (countLow + 1 : U32)
      scan(rest, U32.or(high, U32.shrn(head, 8n)), (countHigh + Bool.pick(U32, U32.is_eq(next, 0), 1, 0) : U32), next)

def measured(result: Scan, limit: Word.U64) -> Result<&2, &2, Error, Word.U64>:
  match result:
    case Scan{high, +length}:
      Bool.pick(Result<&2, &2, Error, Word.U64>, U32.is_eq(high, 0),
        Bool.pick(Result<&2, &2, Error, Word.U64>, Word.atLeast(Word.compare(limit, length)), Done{length}, Fail{MessageTooLong{}}), Fail{InvalidByte{}})

# AAD is limited to 2^61 - 1 bytes and text to 2^36 - 32 bytes.
def validate(aad: List<&2, U32>, text: List<&2, U32>) -> Result<&2, &2, Error, Lengths>:
  Result.bind(&2, &2, Error, Word.U64, Lengths, measured(scan(aad, 0, 0, 0), Word.U64{536870911, 4294967295}), a =>
    Result.bind(&2, &2, Error, Word.U64, Lengths, measured(scan(text, 0, 0, 0), Word.U64{15, 4294967264}), c =>
      Done{Lengths{a, c}}))

def seal(key: GcmKey, +nonce: Nonce, +aad: List<&2, U32>, +plaintext: List<&2, U32>) -> Result<&2, &2, Error, Sealed>:
  match key:
    case GcmKey{+cipher, h}:
      Result.bind(&2, &2, Error, Lengths, Sealed, validate(aad, plaintext), sizes =>
        +ciphertext = crypt(cipher, nonce, plaintext)
        Done{Sealed{ciphertext, tag(cipher, h, nonce, aad, ciphertext, sizes)}})

def sameTag(left: AES.Block, right: AES.Block) -> Bool:
  match left right:
    case AES.Block{a, b, c, d} AES.Block{e, f, g, h}:
      U32.is_eq(U32.or(U32.or(U32.xor(a, e), U32.xor(b, f)), U32.or(U32.xor(c, g), U32.xor(d, h))), 0)

# No plaintext is produced until the complete tag has been authenticated.
def authenticated(valid: Bool, cipher: AES.ExpandedKey, nonce: Nonce, ciphertext: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid:
    case False{}: Fail{AuthenticationFailed{}}
    case True{}: Done{crypt(cipher, nonce, ciphertext)}

def open(key: GcmKey, +nonce: Nonce, +aad: List<&2, U32>, sealed: Sealed) -> Result<&2, &2, Error, List<&2, U32>>:
  match key sealed:
    case GcmKey{+cipher, h} Sealed{+ciphertext, received}:
      Result.bind(&2, &2, Error, Lengths, List<&2, U32>, validate(aad, ciphertext), sizes =>
        authenticated(sameTag(received, tag(cipher, h, nonce, aad, ciphertext, sizes)), cipher, nonce, ciphertext))
