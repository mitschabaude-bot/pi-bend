import Base
import ./x25519.bend as X
import ./tls13-record.bend as Record

# Initial TLS 1.3 client flight. The affine Pending state retains the private
# key and exact transcript bytes; it is not an authenticated connection.
type Error is Data:
  EntropyFailure{code: U32, message: String}
  InvalidRandomness{}
  InvalidServerName{}
  KeyExchange{cause: X.Error}

type Pending is Type:
  Pending{serverName: Maybe<&2, String>, privateKey: List<&2, U32>, sessionId: List<&2, U32>, clientHello: List<&2, U32>}

type Started is Type:
  Started{pending: Pending, record: List<&2, U32>}

def u16(+value: U32) -> List<&2, U32>:
  U32.and(U32.shrn(value, 8n), 255) <> U32.and(value, 255) <> Nil{}

def vector(+bytes: List<&2, U32>) -> List<&2, U32>:
  Record.append(u16(U32.from_nat(Record.length(bytes, 0n))), bytes)

def extension(kind: U32, bytes: List<&2, U32>) -> List<&2, U32>:
  Record.append(u16(kind), vector(bytes))

def ascii(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{byte}, rest}: byte <> ascii(rest)

# The URL layer supplies an ASCII DNS name (IDNA A-labels), without a root dot.
# Numeric addresses omit SNI. Enforce label boundaries before encoding lengths.
def alphanumeric(+byte: U32) -> Bool:
  (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122))

def nameBytes(bytes: List<&2, U32>, +label: U32, +total: U32, endAlphanumeric: Bool, valid: Bool) -> Bool:
  match bytes:
    case Nil{}: valid && U32.is_gt(label, 0) && endAlphanumeric
    case +byte <> rest:
      +dot = U32.is_eq(byte, 46)
      +letter = alphanumeric(byte)
      allowed = Bool.pick(Bool, dot, U32.is_gt(label, 0) && endAlphanumeric,
        U32.is_lt(label, 63) && (letter || (U32.is_eq(byte, 45) && U32.is_gt(label, 0))))
      nameBytes(rest, Bool.pick(U32, dot, 0, (label + 1 : U32)), (total + 1 : U32), letter, valid && U32.is_lt(total, 253) && allowed)

def validName(name: Maybe<&2, String>) -> Bool:
  match name:
    case None{}: True{}
    case Some{text}: nameBytes(ascii(text), 0, 0, False{}, True{})

def serverName(name: Maybe<&2, String>) -> List<&2, U32>:
  match name:
    case None{}: Nil{}
    case Some{text}: extension(0, vector(0 <> vector(ascii(text))))

def extensions(name: Maybe<&2, String>, publicKey: List<&2, U32>) -> List<&2, U32>:
  groups = extension(10, vector(u16(29)))
  signatures = extension(13, vector(4 <> 3 <> 8 <> 4 <> Nil{}))
  versions = extension(43, 2 <> 3 <> 4 <> Nil{})
  share = extension(51, vector(0 <> 29 <> vector(publicKey)))
  alpn = extension(16, vector(8 <> ascii("http/1.1")))
  Record.append(serverName(name), Record.append(groups, Record.append(signatures, Record.append(versions, Record.append(share, alpn)))))

def clientHelloMessage(+body: List<&2, U32>) -> List<&2, U32>:
  +size = U32.from_nat(Record.length(body, 0n))
  1 <> U32.shrn(size, 16n) <> U32.and(U32.shrn(size, 8n), 255) <> U32.and(size, 255) <> body

def encoded(+name: Maybe<&2, String>, random: List<&2, U32>, privateKey: List<&2, U32>, +sessionId: List<&2, U32>, result: Result<&2, &2, X.Error, List<&2, U32>>) -> Result<&2, &1, Error, Started>:
  match result:
    case Fail{cause}: Fail{KeyExchange{cause}}
    case Done{publicKey}:
      tail = Record.append(0 <> 2 <> 19 <> 1 <> 1 <> 0 <> Nil{}, vector(extensions(name, publicKey)))
      +hello = clientHelloMessage(3 <> 3 <> Record.append(random, 32 <> Record.append(sessionId, tail)))
      # Initial record uses the compatibility version; ClientHello itself uses 0x0303.
      wire = {22 <> 3 <> 1 <> vector(hello) : List<&2, U32>}
      Done{Started{Pending{name, privateKey, sessionId, hello}, wire}}

# A deterministic constructor makes the wire format testable. Production start
# supplies 96 OS bytes: independent random, private scalar and session ID slices.
def initialized(valid: Bool, name: Maybe<&2, String>, +entropy: List<&2, U32>) -> Result<&2, &1, Error, Started>:
  match valid:
    case False{}: Fail{InvalidRandomness{}}
    case True{}:
      +random = List.take(&2, U32, entropy, 32n)
      +privateKey = List.take(&2, U32, List.drop(&2, U32, entropy, 32n), 32n)
      sessionId = List.drop(&2, U32, entropy, 64n)
      encoded(name, random, privateKey, sessionId, X.publicKey(privateKey))

def named(valid: Bool, name: Maybe<&2, String>, +entropy: List<&2, U32>) -> Result<&2, &1, Error, Started>:
  match valid:
    case False{}: Fail{InvalidServerName{}}
    case True{}: initialized(Nat.is_eq(Record.length(entropy, 0n), 96n) && X.valid(entropy), name, entropy)

def initialize(+name: Maybe<&2, String>, entropy: List<&2, U32>) -> Result<&2, &1, Error, Started>:
  named(validName(name), name, entropy)

def fromEntropy(name: Maybe<&2, String>, result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &1, Error, Started>:
  match result:
    case Fail{Tuple{code, message}}: Fail{EntropyFailure{code, message}}
    case Done{bytes}: initialize(name, bytes)

def startValid(valid: Bool, name: Maybe<&2, String>) -> IO(Result<&2, &1, Error, Started>):
  match valid:
    case False{}: IO.pure(Result<&2, &1, Error, Started>, Fail{InvalidServerName{}})
    case True{}:
      do IO<Result<&2, &1, Error, Started>>:
        entropy : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(96)
        return fromEntropy(name, entropy)

def start(+name: Maybe<&2, String>) -> IO(Result<&2, &1, Error, Started>):
  startValid(validName(name), name)
