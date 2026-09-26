import Base
import ./big-nat.bend as Big
import ./der.bend as Der
import ./pem.bend as Pem
import ./sha256.bend as SHA

# RSA private keys and RSASSA-PKCS1-v1_5 signing with SHA-256 (RFC 8017
# sections 8.2.1 and 9.2, the JWS "RS256" algorithm). Keys are read from PEM:
# PKCS#8 "PRIVATE KEY" wrapping an rsaEncryption key, or PKCS#1 "RSA PRIVATE
# KEY". Signing uses the CRT form. The exponentiation is Big.powerMod's
# Montgomery ladder, which is not constant-time: suitable for signing
# requests from a client, not for a service exposed to timing measurements.

type Error is Data:
  InvalidPem{}
  InvalidDer{cause: Der.Error}
  UnsupportedKey{}
  KeyTooSmall{}
  HashFailure{cause: SHA.Error}

# RSAPrivateKey: n, the modulus width in bytes, and the CRT values.
type PrivateKey is Data:
  PrivateKey{modulus: Big.BigNat, bytes: Nat, p: Big.BigNat, q: Big.BigNat, dP: List<&2, U32>, dQ: List<&2, U32>, qInv: Big.BigNat}

def derResult(-A: Data, value: Result<&2, &2, Der.Error, A>) -> Result<&2, &2, Error, A>:
  match value:
    case Fail{cause}: Fail{InvalidDer{cause}}
    case Done{item}: Done{item}

def consInteger(head: Result<&2, &2, Error, List<&2, U32>>, tail: Result<&2, &2, Error, List<&2, List<&2, U32>>>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match head tail:
    case Fail{cause} _: Fail{cause}
    case _ Fail{cause}: Fail{cause}
    case Done{value} Done{rest}: Done{value <> rest}

def integers(nodes: List<&2, Der.Node>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match nodes:
    case Nil{}: Done{Nil{}}
    case node <> rest: consInteger(derResult(List<&2, U32>, Der.unsigned(node)), integers(rest))

def width(bytes: List<&2, U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: width(rest, 1n + count)

# RSAPrivateKey ::= SEQUENCE { version 0, n, e, d, p, q, dP, dQ, qInv }
def fromValues(values: List<&2, List<&2, U32>>) -> Result<&2, &2, Error, PrivateKey>:
  match values:
    case [0] <> +n <> _ <> _ <> p <> q <> dP <> dQ <> qInv <> Nil{}: Done{PrivateKey{Big.fromBigEndian(n), width(n, 0n), Big.fromBigEndian(p), Big.fromBigEndian(q), dP, dQ, Big.fromBigEndian(qInv)}}
    case _: Fail{UnsupportedKey{}}

def pkcs1Nodes(nodes: Result<&2, &2, Error, List<&2, Der.Node>>) -> Result<&2, &2, Error, PrivateKey>:
  match nodes:
    case Fail{cause}: Fail{cause}
    case Done{items}: Result.bind(&2, &2, Error, List<&2, List<&2, U32>>, PrivateKey, integers(items), fromValues)

def pkcs1(bytes: List<&2, U32>) -> Result<&2, &2, Error, PrivateKey>:
  pkcs1Nodes(derResult(List<&2, Der.Node>, Result.bind(&2, &2, Der.Error, Der.Node, List<&2, Der.Node>, Der.one(bytes), Der.sequence)))

# 1.2.840.113549.1.1.1 with NULL parameters.
def rsaAlgorithm(node: Der.Node) -> Bool:
  match node:
    case Der.Node{Der.Tag{0, True{}, 16}, _, [6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 1, 5, 0]}: True{}
    case _: False{}

# PrivateKeyInfo ::= SEQUENCE { version 0, AlgorithmIdentifier, OCTET STRING }
def pkcs8Nodes(nodes: Result<&2, &2, Error, List<&2, Der.Node>>) -> Result<&2, &2, Error, PrivateKey>:
  match nodes:
    case Done{Der.Node{Der.Tag{0, False{}, 2}, _, [0]} <> +algorithm <> Der.Node{Der.Tag{0, False{}, 4}, _, key} <> _}: Bool.pick(Result<&2, &2, Error, PrivateKey>, rsaAlgorithm(algorithm), pkcs1(key), Fail{UnsupportedKey{}})
    case Done{_}: Fail{UnsupportedKey{}}
    case Fail{cause}: Fail{cause}

def pkcs8(bytes: List<&2, U32>) -> Result<&2, &2, Error, PrivateKey>:
  pkcs8Nodes(derResult(List<&2, Der.Node>, Result.bind(&2, &2, Der.Error, Der.Node, List<&2, Der.Node>, Der.one(bytes), Der.sequence)))

def fromBlocks(blocks: Result<&2, &2, Pem.Error, List<&2, Pem.Block>>) -> Result<&2, &2, Error, PrivateKey>:
  match blocks:
    case Done{Pem.Block{"PRIVATE KEY", bytes} <> _}: pkcs8(bytes)
    case Done{Pem.Block{"RSA PRIVATE KEY", bytes} <> _}: pkcs1(bytes)
    case Done{_}: Fail{UnsupportedKey{}}
    case Fail{_}: Fail{InvalidPem{}}

# The first PEM block's RSA private key.
def parsePrivateKeyPem(text: String) -> Result<&2, &2, Error, PrivateKey>: fromBlocks(Pem.decode(text))

# Signing
# -------

def digestInfo(hash: List<&2, U32>) -> List<&2, U32>:
  48 <> 49 <> 48 <> 13 <> 6 <> 9 <> 96 <> 134 <> 72 <> 1 <> 101 <> 3 <> 4 <> 2 <> 1 <> 5 <> 0 <> 4 <> 32 <> hash

def padding(count: Nat, rest: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: rest
    case 1n+left: 255 <> padding(left, rest)

# EMSA-PKCS1-v1_5: 0x00 0x01 PS 0x00 T, with at least eight 0xff octets.
def encoded(+size: Nat, hash: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  Bool.pick(Result<&2, &2, Error, List<&2, U32>>, Nat.is_lt(size, 62n), Fail{KeyTooSmall{}}, Done{0 <> 1 <> padding(Nat.sub(size, 54n), 0 <> digestInfo(hash))})

# m mod p - m2 mod p, lifted into [0, p).
def difference(+p: Big.BigNat, +m1: Big.BigNat, +m2: Big.BigNat) -> Big.BigNat:
  Big.reduce(Maybe.default(&2, Big.BigNat, Big.subtract(Big.add(m1, p), Big.reduce(m2, p)), Big.zero()), p)

# RSASP1 with the CRT: s = m2 + q * (qInv * (m1 - m2) mod p).
def exponentiate(key: PrivateKey, +message: Big.BigNat) -> Big.BigNat:
  match key:
    case PrivateKey{_, _, +p, +q, dP, dQ, qInv}:
      +m1 = Big.powerMod(dP, Big.reduce(message, p), p)
      +m2 = Big.powerMod(dQ, Big.reduce(message, q), q)
      Big.add(m2, Big.multiply(q, Big.reduce(Big.multiply(qInv, difference(p, m1, m2)), p)))

def keyBytes(key: PrivateKey) -> Nat:
  match key:
    case PrivateKey{_, bytes, _, _, _, _, _}: bytes

def signEncoded(+key: PrivateKey, message: Result<&2, &2, Error, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match message:
    case Fail{cause}: Fail{cause}
    case Done{bytes}: Done{Big.toBigEndian(keyBytes(key), exponentiate(key, Big.fromBigEndian(bytes)))}

def hashed(+key: PrivateKey, result: Result<&2, &2, SHA.Error, SHA.Digest>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{cause}: Fail{HashFailure{cause}}
    case Done{digest}: signEncoded(key, encoded(keyBytes(key), SHA.toBytes(digest)))

# RSASSA-PKCS1-v1_5-SIGN with SHA-256.
def signPkcs1Sha256(key: PrivateKey, message: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  hashed(key, SHA.digest(message))
