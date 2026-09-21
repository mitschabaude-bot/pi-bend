import Base
import ./big-nat.bend as Big
import ./sha256.bend as SHA

# RFC 8017 sections 5.2.2, 9.1 and 9.2; SHA-256 for both hash and MGF1.
# RSA verification only. All arithmetic handles public values; no private-key
# operation or constant-time exponentiation is provided by this module.
type Error is Data:
  InvalidKey{}
  InvalidSignature{}
  HashFailure{cause: SHA.Error}

type PublicKey is Data:
  PublicKey{modulus: Big.BigNat, exponent: List<&2, U32>, bytes: Nat, bits: Nat}

def length(bytes: List<&2, U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: length(rest, 1n+count)

def valid(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: U32.is_le(byte, 255) && valid(rest)

def canonical(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case +head <> rest: U32.is_gt(head, 0) && U32.is_le(head, 255) && valid(rest)
    case Nil{}: False{}

def odd(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case byte <> Nil{}: U32.is_eq(U32.and(byte, 1), 1)
    case _ <> rest: odd(rest)
    case Nil{}: False{}

def number(bytes: List<&2, U32>, value: Big.BigNat) -> Big.BigNat:
  match bytes:
    case Nil{}: value
    case byte <> rest: number(rest, Big.add(Big.multiplyU32(value, 256), Big.fromU32(byte)))

def less(order: Cmp) -> Bool:
  match order:
    case LT{}: True{}
    case _: False{}

def leadingBits(fuel: Nat, byte: U32) -> Nat:
  match fuel byte:
    case _ 0: 0n
    case 1n+fuel byte: 1n+leadingBits(fuel, U32.shr(byte))
    case _ _: 0n

def bitLength(bytes: List<&2, U32>) -> Nat:
  match bytes:
    case head <> rest: leadingBits(8n, head) + length(rest, 0n) * 8n
    case Nil{}: 0n

def checkedKey(allowed: Bool, modulus: Big.BigNat, exponent: List<&2, U32>, size: Nat, bits: Nat) -> Result<&2, &2, Error, PublicKey>:
  match allowed:
    case False{}: Fail{InvalidKey{}}
    case True{}: Done{PublicKey{modulus, exponent, size, bits}}

def key(+modulus: List<&2, U32>, +exponent: List<&2, U32>) -> Result<&2, &2, Error, PublicKey>:
  +n = number(modulus, Big.zero())
  +e = number(exponent, Big.zero())
  checkedKey(canonical(modulus) && canonical(exponent) && odd(modulus) && odd(exponent) && less(Big.compare(Big.one(), e)) && less(Big.compare(e, n)), n, exponent, length(modulus, 0n), bitLength(modulus))

def remainder(division: Big.Division) -> Big.BigNat:
  match division:
    case Big.Division{_, value}: value

def reduce(value: Big.BigNat, modulus: Big.BigNat) -> Big.BigNat:
  match value:
    case Big.BigNat{limbs}: remainder(Big.divideLimbs(List.reverse(&2, U32, limbs), modulus, Big.Division{Big.zero(), Big.zero()}))

def multiplyBit(set: Bool, squared: Big.BigNat, base: Big.BigNat, modulus: Big.BigNat) -> Big.BigNat:
  match set:
    case False{}: squared
    case True{}: reduce(Big.multiply(squared, base), modulus)

def powerByte(fuel: Nat, +byte: U32, +base: Big.BigNat, +modulus: Big.BigNat, +value: Big.BigNat) -> Big.BigNat:
  match fuel:
    case 0n: value
    case 1n+fuel:
      powerByte(fuel, U32.and(U32.shl(byte), 255), base, modulus, multiplyBit(U32.is_eq(U32.and(byte, 128), 128), reduce(Big.multiply(value, value), modulus), base, modulus))

def power(exponent: List<&2, U32>, +base: Big.BigNat, +modulus: Big.BigNat, value: Big.BigNat) -> Big.BigNat:
  match exponent:
    case Nil{}: value
    case byte <> rest: power(rest, base, modulus, powerByte(8n, byte, base, modulus, value))

def output(count: Nat, step: Big.SmallDivision, bytes: List<&2, U32>) -> List<&2, U32>:
  match count step:
    case 0n _: bytes
    case 1n+count Big.SmallDivision{quotient, byte}: output(count, Big.divideSmallRaw(quotient, 256), byte <> bytes)

def recovered(allowed: Bool, modulus: Big.BigNat, exponent: List<&2, U32>, size: Nat, signature: Big.BigNat) -> Result<&2, &2, Error, List<&2, U32>>:
  match allowed:
    case False{}: Fail{InvalidSignature{}}
    case True{}: Done{output(size, Big.divideSmallRaw(power(exponent, signature, modulus, Big.one()), 256), Nil{})}

def recover(public: PublicKey, +signature: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match public:
    case PublicKey{+modulus, exponent, +size, _}:
      +value = number(signature, Big.zero())
      recovered(valid(signature) && Nat.is_eq(length(signature, 0n), size) && less(Big.compare(value, modulus)), modulus, exponent, size, value)

def append(left: List<&2, U32>, right: List<&2, U32>) -> List<&2, U32>:
  List.reverse.go(&2, U32, List.reverse(&2, U32, left), right)

def hashed(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{cause}: Fail{HashFailure{cause}}
    case Done{digest}: Done{SHA.toBytes(digest)}

def requireSignature(allowed: Bool) -> Result<&2, &2, Error, Unit>:
  match allowed:
    case False{}: Fail{InvalidSignature{}}
    case True{}: Done{Unit{}}

def equal(left: List<&2, U32>, right: List<&2, U32>, difference: U32) -> Bool:
  match left right:
    case Nil{} Nil{}: U32.is_eq(difference, 0)
    case a <> xs b <> ys: equal(xs, ys, U32.or(difference, U32.xor(a, b)))
    case _ _: False{}

# MGF1 uses a four-byte big-endian counter, beginning at zero.
def maskBlocks(blocks: Nat, +seed: List<&2, U32>, +counter: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match blocks:
    case 0n: Done{List.reverse(&2, U32, reversed)}
    case 1n+blocks:
      Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, hashed(SHA.digest(append(seed, SHA.wordBytes(counter)))), digest =>
        maskBlocks(blocks, seed, (counter + 1 : U32), List.reverse.go(&2, U32, digest, reversed)))

def xorBytes(left: List<&2, U32>, right: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match left right:
    case a <> xs b <> ys: xorBytes(xs, ys, U32.xor(a, b) <> reversed)
    case _ _: List.reverse(&2, U32, reversed)

def salt(padding: Nat, bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match padding bytes:
    case 0n 1 <> rest: Done{rest}
    case 1n+padding 0 <> rest: salt(padding, rest)
    case _ _: Fail{InvalidSignature{}}

def unmasked(unused: Nat, bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case first <> rest: U32.and(first, U32.shrn(255, unused)) <> rest
    case Nil{}: Nil{}

def pssHash(messageHash: List<&2, U32>, expected: List<&2, U32>, saltBytes: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  Result.bind(&2, &2, Error, List<&2, U32>, Unit, hashed(SHA.digest(0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> append(messageHash, saltBytes))), actual => requireSignature(equal(actual, expected, 0)))

def pssDatabase(+masked: List<&2, U32>, +hash: List<&2, U32>, messageHash: List<&2, U32>, +unused: Nat, +saltLength: Nat) -> Result<&2, &2, Error, Unit>:
  match masked:
    case +first <> +rest:
      +size = length(rest, 1n)
      Result.bind(&2, &2, Error, Unit, Unit, requireSignature(Nat.is_ge(size, 1n+saltLength) && U32.is_eq(U32.and(first, U32.xor(255, U32.shrn(255, unused))), 0)), unit =>
        Result.bind(&2, &2, Error, List<&2, U32>, Unit, maskBlocks(Nat.div(size + 31n, 32n), hash, 0, Nil{}), mask =>
          Result.bind(&2, &2, Error, List<&2, U32>, Unit, salt(Nat.sub(size, 1n+saltLength), unmasked(unused, xorBytes(first <> rest, mask, Nil{}))), saltBytes =>
            pssHash(messageHash, hash, saltBytes))))
    case Nil{}: Fail{InvalidSignature{}}

def pssTail(masked: List<&2, U32>, +tail: List<&2, U32>, messageHash: List<&2, U32>, unused: Nat, saltLength: Nat) -> Result<&2, &2, Error, Unit>:
  Result.bind(&2, &2, Error, Unit, Unit, requireSignature(equal(List.drop(&2, U32, tail, 32n), 188 <> Nil{}, 0)), unit =>
    pssDatabase(masked, List.take(&2, U32, tail, 32n), messageHash, unused, saltLength))

# emBits is modulusBits - 1; it may require one fewer byte than the signature.
def pssEncoded(+encoded: List<&2, U32>, messageHash: List<&2, U32>, +bits: Nat, saltLength: Nat) -> Result<&2, &2, Error, Unit>:
  +size = Nat.div(bits + 7n, 8n)
  Result.bind(&2, &2, Error, Unit, Unit, requireSignature(Nat.is_ge(size, 34n) && Nat.is_eq(length(encoded, 0n), size)), unit =>
    pssTail(List.take(&2, U32, encoded, Nat.sub(size, 33n)), List.drop(&2, U32, encoded, Nat.sub(size, 33n)), messageHash, Nat.sub(size * 8n, bits), saltLength))

def pssLeading(extra: Nat, encoded: List<&2, U32>, messageHash: List<&2, U32>, bits: Nat, saltLength: Nat) -> Result<&2, &2, Error, Unit>:
  match extra encoded:
    case 0n encoded: pssEncoded(encoded, messageHash, bits, saltLength)
    case 1n 0 <> rest: pssEncoded(rest, messageHash, bits, saltLength)
    case _ _: Fail{InvalidSignature{}}

def verifyPss(public: PublicKey, message: List<&2, U32>, signature: List<&2, U32>, saltLength: Nat) -> Result<&2, &2, Error, Unit>:
  match public:
    case PublicKey{modulus, exponent, +size, +bits}:
      +emBits = Nat.sub(bits, 1n)
      Result.bind(&2, &2, Error, List<&2, U32>, Unit, hashed(SHA.digest(message)), messageHash =>
        Result.bind(&2, &2, Error, List<&2, U32>, Unit, recover(PublicKey{modulus, exponent, size, bits}, signature), encoded =>
          pssLeading(Nat.sub(size, Nat.div(emBits + 7n, 8n)), encoded, messageHash, emBits, saltLength)))

# EMSA-PKCS1-v1_5 with the exact DER DigestInfo for SHA-256 (including NULL).
# This is needed for certificate-chain signatures, not TLS CertificateVerify.
def pkcsPadding(bytes: List<&2, U32>, minimum: Nat, expected: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  match bytes:
    case 255 <> rest: pkcsPadding(rest, Nat.sub(minimum, 1n), expected)
    case 0 <> rest: requireSignature(Nat.is_eq(minimum, 0n) && equal(rest, expected, 0))
    case _: Fail{InvalidSignature{}}

def pkcsEncoded(bytes: List<&2, U32>, hash: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  match bytes:
    case 0 <> 1 <> rest:
      pkcsPadding(rest, 8n, 48 <> 49 <> 48 <> 13 <> 6 <> 9 <> 96 <> 134 <> 72 <> 1 <> 101 <> 3 <> 4 <> 2 <> 1 <> 5 <> 0 <> 4 <> 32 <> hash)
    case _: Fail{InvalidSignature{}}

def verifyPkcs1(public: PublicKey, message: List<&2, U32>, signature: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  Result.bind(&2, &2, Error, List<&2, U32>, Unit, hashed(SHA.digest(message)), hash =>
    Result.bind(&2, &2, Error, List<&2, U32>, Unit, recover(public, signature), encoded => pkcsEncoded(encoded, hash)))
