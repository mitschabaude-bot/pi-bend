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

def increment(block: AES.Block) -> AES.Block:
  match block:
    case AES.Block{a, b, c, d}: AES.Block{a, b, c, (d + 1 : U32)}

# GHASH's bit order is most significant first; reduction uses x^128+x^7+x^2+x+1.
# Selection uses masks, without secret-indexed tables or data-dependent branches.
def reduce(block: AES.Block) -> AES.Block:
  match block:
    case AES.Block{+a, +b, +c, +d}:
      mask = (0 - U32.and(d, 1) : U32)
      AES.Block{U32.xor(U32.shr(a), U32.and(mask, 3774873600)), U32.or(U32.shr(b), U32.shln(a, 31n)), U32.or(U32.shr(c), U32.shln(b, 31n)), U32.or(U32.shr(d), U32.shln(c, 31n))}

def select(+mask: U32, value: AES.Block) -> AES.Block:
  match value:
    case AES.Block{a, b, c, d}: AES.Block{U32.and(mask, a), U32.and(mask, b), U32.and(mask, c), U32.and(mask, d)}

def productBits(count: Nat, bits: AES.Block, +factor: AES.Block, result: AES.Block) -> AES.Block:
  match count:
    case 0n: result
    case 1n+rest:
      match bits:
        case AES.Block{+a, +b, +c, +d}:
          next = {AES.Block{U32.or(U32.shl(a), U32.shrn(b, 31n)), U32.or(U32.shl(b), U32.shrn(c, 31n)), U32.or(U32.shl(c), U32.shrn(d, 31n)), U32.shl(d)} : AES.Block}
          productBits(rest, next, reduce(factor), AES.add(result, select((0 - U32.shrn(a, 31n) : U32), factor)))

def multiply(left: AES.Block, right: AES.Block) -> AES.Block:
  productBits(128n, left, right, AES.Block{0, 0, 0, 0})

def appendByte(block: AES.Block, byte: U32) -> AES.Block:
  match block:
    case AES.Block{a, +b, +c, +d}: AES.Block{U32.or(U32.shln(a, 8n), U32.shrn(b, 24n)), U32.or(U32.shln(b, 8n), U32.shrn(c, 24n)), U32.or(U32.shln(c, 8n), U32.shrn(d, 24n)), U32.or(U32.shln(d, 8n), byte)}

type HashState is Data:
  HashState{digest: AES.Block, partial: AES.Block, remaining: Nat}

def pad(count: Nat, block: AES.Block) -> AES.Block:
  match count:
    case 0n: block
    case 1n+rest: pad(rest, appendByte(block, 0))

def absorb(h: AES.Block, byte: U32, state: HashState) -> HashState:
  match state:
    case HashState{digest, partial, 0n}: HashState{multiply(AES.add(digest, appendByte(partial, byte)), h), AES.Block{0, 0, 0, 0}, 15n}
    case HashState{digest, partial, 1n+rest}: HashState{digest, appendByte(partial, byte), rest}

def finishHash(h: AES.Block, state: HashState) -> AES.Block:
  match state:
    case HashState{digest, _, 15n}: digest
    case HashState{digest, partial, remaining}: multiply(AES.add(digest, pad(1n+remaining, partial)), h)

def hashBytes(bytes: List<&2, U32>, +h: AES.Block, state: HashState) -> AES.Block:
  match bytes:
    case Nil{}: finishHash(h, state)
    case head <> rest: hashBytes(rest, h, absorb(h, head, state))

def hash(h: AES.Block, state: AES.Block, bytes: List<&2, U32>) -> AES.Block:
  hashBytes(bytes, h, HashState{state, AES.Block{0, 0, 0, 0}, 15n})

type Lengths is Data:
  Lengths{aad: Word.U64, text: Word.U64}

def lengthBlock(sizes: Lengths) -> AES.Block:
  match sizes:
    case Lengths{Word.U64{ah, +al}, Word.U64{ch, +cl}}:
      AES.Block{U32.or(U32.shln(ah, 3n), U32.shrn(al, 29n)), U32.shln(al, 3n), U32.or(U32.shln(ch, 3n), U32.shrn(cl, 29n)), U32.shln(cl, 3n)}

def tag(cipher: AES.ExpandedKey, +h: AES.Block, nonce: Nonce, aad: List<&2, U32>, text: List<&2, U32>, sizes: Lengths) -> AES.Block:
  authenticated = hash(h, hash(h, AES.Block{0, 0, 0, 0}, aad), text)
  final = multiply(AES.add(authenticated, lengthBlock(sizes)), h)
  AES.add(final, AES.encrypt(cipher, initial(nonce)))

type Counter is Data:
  Counter{next: AES.Block, stream: AES.Block, remaining: Nat, reversed: List<&2, U32>}

def cryptByte(byte: U32, next: AES.Block, block: AES.Block, remaining: Nat, reversed: List<&2, U32>) -> Counter:
  match block:
    case AES.Block{+a, b, c, d}:
      Counter{next, appendByte(AES.Block{a, b, c, d}, 0), remaining, U32.xor(byte, AES.byte(a, 24n)) <> reversed}

def feedCounter(cipher: AES.ExpandedKey, byte: U32, state: Counter) -> Counter:
  match state:
    case Counter{+next, _, 0n, reversed}: cryptByte(byte, increment(next), AES.encrypt(cipher, next), 15n, reversed)
    case Counter{next, stream, 1n+rest, reversed}: cryptByte(byte, next, stream, rest, reversed)

def finishCounter(state: Counter) -> List<&2, U32>:
  match state:
    case Counter{_, _, _, reversed}: List.reverse(&2, U32, reversed)

def cryptBytes(bytes: List<&2, U32>, +cipher: AES.ExpandedKey, state: Counter) -> List<&2, U32>:
  match bytes:
    case Nil{}: finishCounter(state)
    case head <> rest: cryptBytes(rest, cipher, feedCounter(cipher, head, state))

def crypt(cipher: AES.ExpandedKey, nonce: Nonce, bytes: List<&2, U32>) -> List<&2, U32>:
  cryptBytes(bytes, cipher, Counter{increment(initial(nonce)), AES.Block{0, 0, 0, 0}, 0n, Nil{}})

def measure(bytes: List<&2, U32>, result: Result<&2, &2, Error, Word.U64>, +limit: Word.U64) -> Result<&2, &2, Error, Word.U64>:
  match bytes result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} result: result
    case head <> rest Done{+count}:
      checked = Bool.pick(Result<&2, &2, Error, Word.U64>, U32.is_le(head, 255),
        Bool.pick(Result<&2, &2, Error, Word.U64>, Word.equal(count, limit), Fail{MessageTooLong{}}, Done{Word.add(count, Word.one())}), Fail{InvalidByte{}})
      measure(rest, checked, limit)

def validate(aad: List<&2, U32>, text: List<&2, U32>) -> Result<&2, &2, Error, Lengths>:
  Result.bind(&2, &2, Error, Word.U64, Lengths, measure(aad, Done{Word.zero()}, Word.U64{536870911, 4294967295}), a =>
    Result.bind(&2, &2, Error, Word.U64, Lengths, measure(text, Done{Word.zero()}, Word.U64{15, 4294967264}), c =>
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
