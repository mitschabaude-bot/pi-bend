import Base
import ./x25519.bend as X
import ./tls13-record.bend as Record
import ./sha256.bend as SHA
import ./hkdf-sha256.bend as HKDF
import ./tls13-kdf.bend as KDF
import ./aes128.bend as AES
import ./aes128-gcm.bend as GCM
import ./x509.bend as X509
import ./rsa-sha256.bend as RSA
import ./ecdsa.bend as EC

# TLS 1.3 handshake framing and negotiation. Affine states retain key epochs
# and exact transcripts; none yet represents an authenticated connection.
type Error is Data:
  EntropyFailure{code: U32, message: String}
  InvalidRandomness{}
  InvalidServerName{}
  KeyExchange{cause: X.Error}
  MalformedServerHello{}
  RejectedParameters{}
  HelloRetryRequest{}
  Derivation{cause: KDF.Error}
  InvalidKeyMaterial{}
  MalformedHandshake{}
  RejectedExtension{kind: U32}
  DuplicateExtension{kind: U32}
  CertificateFailure{cause: X509.Error}
  FinishedMismatch{}

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
  # PKCS1/SHA256 is permitted for certificates, never TLS1.3 CertificateVerify.
  signatures = extension(13, vector(4 <> 3 <> 5 <> 3 <> 8 <> 4 <> 4 <> 1 <> Nil{}))
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

# Only the two cryptographic extensions we offered may occur in ServerHello.
# Both orders are accepted; extra, duplicate and truncated extensions fail.
def equal(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x, y) && equal(xs, ys)
    case _ _: False{}

def selected(valid: Bool, key: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid:
    case False{}: Fail{RejectedParameters{}}
    case True{}: Done{key}

def serverExtensions(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case 0 <> 43 <> 0 <> 2 <> 3 <> 4 <> 0 <> 51 <> 0 <> 36 <> 0 <> 29 <> 0 <> 32 <> +key:
      selected(Nat.is_eq(Record.length(key, 0n), 32n), key)
    case 0 <> 51 <> 0 <> 36 <> 0 <> 29 <> 0 <> 32 <> +rest:
      selected(equal(List.drop(&2, U32, rest, 32n), 0 <> 43 <> 0 <> 2 <> 3 <> 4 <> Nil{}), List.take(&2, U32, rest, 32n))
    case _: Fail{RejectedParameters{}}

def serverParameters(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case 19 <> 1 <> 0 <> high <> low <> +rest:
      Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, selected(U32.is_eq((high * 256 + low : U32), U32.from_nat(Record.length(rest, 0n))), rest), serverExtensions)
    case _: Fail{RejectedParameters{}}

def serverSession(session: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case +size <> +rest:
      Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, selected(U32.is_le(size, 32) && equal(session, List.take(&2, U32, rest, U32.to_nat(size))), List.drop(&2, U32, rest, U32.to_nat(size))), serverParameters)
    case _: Fail{MalformedServerHello{}}

def serverRandom(retry: Bool, session: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match retry:
    case True{}: Fail{HelloRetryRequest{}}
    case False{}: serverSession(session, bytes)

def serverBody(session: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case 3 <> 3 <> +rest:
      retryRandom = {207 <> 33 <> 173 <> 116 <> 229 <> 154 <> 97 <> 17 <> 190 <> 29 <> 140 <> 2 <> 30 <> 101 <> 184 <> 145 <> 194 <> 162 <> 17 <> 22 <> 122 <> 187 <> 140 <> 94 <> 7 <> 158 <> 9 <> 226 <> 200 <> 168 <> 51 <> 156 <> Nil{} : List<&2, U32>}
      serverRandom(equal(List.take(&2, U32, rest, 32n), retryRandom), session, List.drop(&2, U32, rest, 32n))
    case _: Fail{RejectedParameters{}}

def serverMessage(session: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match bytes:
    case 2 <> high <> middle <> low <> +body:
      checked = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_eq((high * 65536 + middle * 256 + low : U32), U32.from_nat(Record.length(body, 0n))) && Nat.is_ge(Record.length(body, 0n), 38n), Done{Unit{}}, Fail{MalformedServerHello{}})
      Result.bind(&2, &2, Error, Unit, List<&2, U32>, checked, unused => serverBody(session, body))
    case _: Fail{MalformedServerHello{}}

def parseServerHello(session: List<&2, U32>, +bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  checked = Bool.pick(Result<&2, &2, Error, Unit>, X.valid(bytes), Done{Unit{}}, Fail{MalformedServerHello{}})
  Result.bind(&2, &2, Error, Unit, List<&2, U32>, checked, unused => serverMessage(session, bytes))

# A handshake state permits protected handshake records, not application IO.
# Server authentication must still verify CertificateVerify and Finished.
type Handshake is Type:
  Handshake{serverName: Maybe<&2, String>, transcript: SHA.State, secret: SHA.Digest, clientSecret: List<&2, U32>, serverSecret: List<&2, U32>, write: Record.Traffic, read: Record.Traffic}

type TrafficKey is Data:
  TrafficKey{key: AES.Block, iv: GCM.Nonce}

def trafficKey(key: Maybe<&2, AES.Block>, iv: List<&2, U32>) -> Result<&2, &2, Error, TrafficKey>:
  match key iv:
    case Some{key} a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> Nil{}:
      Done{TrafficKey{key, GCM.Nonce{AES.pack(a, b, c, d), AES.pack(e, f, g, h), AES.pack(i, j, k, l)}}}
    case _ _: Fail{InvalidKeyMaterial{}}

def derivation(-A: Data, result: Result<&2, &2, KDF.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Fail{cause}: Fail{Derivation{cause}}
    case Done{value}: Done{value}

def hashResult(-A: Data, result: Result<&2, &2, SHA.Error, A>) -> Result<&2, &2, Error, A>:
  derivation(A, KDF.kdfResult(A, HKDF.hashResult(A, result)))

def deriveKey(+secret: List<&2, U32>) -> Result<&2, &2, Error, TrafficKey>:
  Result.bind(&2, &2, Error, List<&2, U32>, TrafficKey, derivation(List<&2, U32>, KDF.expandLabel(secret, "key", Nil{}, 16)), key =>
    Result.bind(&2, &2, Error, List<&2, U32>, TrafficKey, derivation(List<&2, U32>, KDF.expandLabel(secret, "iv", Nil{}, 12)), iv => trafficKey(AES.fromBytes(key), iv)))

type Secrets is Data:
  Secrets{transcript: SHA.State, secret: SHA.Digest, client: List<&2, U32>, server: List<&2, U32>, write: TrafficKey, read: TrafficKey}

def secrets(shared: List<&2, U32>, hello: List<&2, U32>, serverHello: List<&2, U32>) -> Result<&2, &2, Error, Secrets>:
  Result.bind(&2, &2, Error, SHA.State, Secrets, hashResult(SHA.State, SHA.update(Record.append(hello, serverHello), SHA.create())), +transcript =>
    Result.bind(&2, &2, Error, SHA.Digest, Secrets, hashResult(SHA.Digest, SHA.finish(transcript)), +hash =>
      Result.bind(&2, &2, Error, SHA.Digest, Secrets, derivation(SHA.Digest, KDF.kdfResult(SHA.Digest, HKDF.extract(Nil{}, X.small(0)))), early =>
        Result.bind(&2, &2, Error, SHA.Digest, Secrets, derivation(SHA.Digest, KDF.advance(SHA.toBytes(early), shared)), +secret =>
          Result.bind(&2, &2, Error, List<&2, U32>, Secrets, derivation(List<&2, U32>, KDF.deriveSecret(SHA.toBytes(secret), "c hs traffic", hash)), +client =>
            Result.bind(&2, &2, Error, List<&2, U32>, Secrets, derivation(List<&2, U32>, KDF.deriveSecret(SHA.toBytes(secret), "s hs traffic", hash)), +server =>
              Result.bind(&2, &2, Error, TrafficKey, Secrets, deriveKey(client), write =>
                Result.bind(&2, &2, Error, TrafficKey, Secrets, deriveKey(server), read =>
                  Done{Secrets{transcript, secret, client, server, write, read}}))))))))

def exchanged(result: Result<&2, &2, X.Error, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{cause}: Fail{KeyExchange{cause}}
    case Done{shared}: Done{shared}

def negotiated(name: Maybe<&2, String>, result: Result<&2, &2, Error, Secrets>) -> Result<&2, &1, Error, Handshake>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Secrets{transcript, secret, client, server, TrafficKey{wk, wi}, TrafficKey{rk, ri}}}:
      Done{Handshake{name, transcript, secret, client, server, Record.create(wk, wi), Record.create(rk, ri)}}

def acceptServerHello(pending: Pending, +serverHello: List<&2, U32>) -> Result<&2, &1, Error, Handshake>:
  match pending:
    case Pending{name, privateKey, session, hello}:
      negotiated(name,
        Result.bind(&2, &2, Error, List<&2, U32>, Secrets, parseServerHello(session, serverHello), point =>
          Result.bind(&2, &2, Error, List<&2, U32>, Secrets, exchanged(X.sharedSecret(privateKey, point)), shared =>
            secrets(shared, hello, serverHello))))

# Record boundaries do not delimit handshake messages. Retain each byte once
# in reverse order until its uint24-sized body is complete; emit exact wire
# messages for transcript hashing. The caller sets a body-size resource limit.
type Buffer is Data:
  Header{reverse: List<&2, U32>, needed: U32, length: U32}
  Body{reverse: List<&2, U32>, remaining: U32}

type FramingError is Data:
  InvalidByte{}
  MessageTooLarge{length: U32, limit: U32}

type Batch is Data:
  Batch{buffer: Buffer, messages: List<&2, List<&2, U32>>}

def emptyBuffer() -> Buffer:
  Header{Nil{}, 4, 0}

def atBoundary(buffer: Buffer) -> Bool:
  match buffer:
    case Header{Nil{}, 4, 0}: True{}
    case _: False{}

def headerComplete(allowed: Bool, +size: U32, limit: U32, reverse: List<&2, U32>, messages: List<&2, List<&2, U32>>) -> Result<&2, &2, FramingError, Batch>:
  match allowed size:
    case False{} _: Fail{MessageTooLarge{size, limit}}
    case True{} 0: Done{Batch{emptyBuffer(), List.reverse(&2, U32, reverse) <> messages}}
    case True{} _: Done{Batch{Body{reverse, size}, messages}}

def bufferByte(+byte: U32, +limit: U32, buffer: Buffer, messages: List<&2, List<&2, U32>>) -> Result<&2, &2, FramingError, Batch>:
  match buffer:
    case Header{reverse, 4, _}: Done{Batch{Header{byte <> reverse, 3, 0}, messages}}
    case Header{reverse, 1, length}:
      +size = (length * 256 + byte : U32)
      headerComplete(U32.is_le(size, limit), size, limit, byte <> reverse, messages)
    case Header{reverse, needed, length}: Done{Batch{Header{byte <> reverse, (needed - 1 : U32), (length * 256 + byte : U32)}, messages}}
    case Body{reverse, 1}: Done{Batch{emptyBuffer(), List.reverse(&2, U32, byte <> reverse) <> messages}}
    case Body{reverse, remaining}: Done{Batch{Body{byte <> reverse, (remaining - 1 : U32)}, messages}}

def checkedByte(valid: Bool, byte: U32, limit: U32, buffer: Buffer, messages: List<&2, List<&2, U32>>) -> Result<&2, &2, FramingError, Batch>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: bufferByte(byte, limit, buffer, messages)

def feedBytes(bytes: List<&2, U32>, +limit: U32, result: Result<&2, &2, FramingError, Batch>) -> Result<&2, &2, FramingError, Batch>:
  match bytes result:
    case Nil{} result: result
    case _ Fail{cause}: Fail{cause}
    case +byte <> rest Done{Batch{buffer, messages}}:
      feedBytes(rest, limit, checkedByte(U32.is_le(byte, 255), byte, limit, buffer, messages))

def orderedBatch(result: Result<&2, &2, FramingError, Batch>) -> Result<&2, &2, FramingError, Batch>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Batch{buffer, messages}}: Done{Batch{buffer, List.reverse(&2, List<&2, U32>, messages)}}

def feed(limit: U32, buffer: Buffer, bytes: List<&2, U32>) -> Result<&2, &2, FramingError, Batch>:
  orderedBatch(feedBytes(bytes, limit, Done{Batch{buffer, Nil{}}}))

# Complete handshake messages arrive from feed. Extension parsing is shared
# by server parameters and, later, certificate entries; placement is checked
# separately against the extensions actually offered by this client.
type ServerExtension is Data:
  ServerExtension{kind: U32, bytes: List<&2, U32>}

def require(valid: Bool) -> Result<&2, &2, Error, Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{MalformedHandshake{}}

def messageBody(expected: U32, wire: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match wire:
    case kind <> +a <> +b <> +c <> +body:
      Result.bind(&2, &2, Error, Unit, List<&2, U32>, require(U32.is_eq(kind, expected) && X.valid(body) && U32.is_le(a, 255) && U32.is_le(b, 255) && U32.is_le(c, 255) && Nat.is_eq(Record.length(body, 0n), U32.to_nat((a * 65536 + b * 256 + c : U32)))), unused => Done{body})
    case _: Fail{MalformedHandshake{}}

def extensionBytes(count: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match count bytes:
    case 1n+count head <> tail: extensionBytes(count, tail, head <> reversed)
    case _ _: List.reverse(&2, U32, reversed)

def parseExtensions(fuel: Nat, bytes: List<&2, U32>, reversed: List<&2, ServerExtension>) -> Result<&2, &2, Error, List<&2, ServerExtension>>:
  match fuel bytes:
    case _ Nil{}: Done{List.reverse(&2, ServerExtension, reversed)}
    case 1n+fuel a <> b <> c <> d <> +rest:
      +size = U32.to_nat((c * 256 + d : U32))
      +data = extensionBytes(size, rest, Nil{})
      Result.bind(&2, &2, Error, Unit, List<&2, ServerExtension>, require(Nat.is_eq(size, Record.length(data, 0n))), unused =>
        parseExtensions(fuel, List.drop(&2, U32, rest, size), ServerExtension{(a * 256 + b : U32), data} <> reversed))
    case _ _: Fail{MalformedHandshake{}}

def extensionVector(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, ServerExtension>>:
  match bytes:
    case a <> b <> +rest:
      +size = Record.length(rest, 0n)
      Result.bind(&2, &2, Error, Unit, List<&2, ServerExtension>, require(Nat.is_eq(size, U32.to_nat((a * 256 + b : U32)))), unused => parseExtensions(size, rest, Nil{}))
    case _: Fail{MalformedHandshake{}}

type Parameters is Data:
  Parameters{serverNameAcknowledged: Bool, applicationProtocol: Maybe<&2, String>}

def validGroups(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case a <> b <> +rest:
      +size = (a * 256 + b : U32)
      U32.is_ge(size, 2) && U32.is_eq(U32.and(size, 1), 0) && Nat.is_eq(Record.length(rest, 0n), U32.to_nat(size))
    case _: False{}

def selectExtension(offeredName: Bool, extension: ServerExtension, parameters: Parameters) -> Result<&2, &2, Error, Parameters>:
  match extension parameters:
    case ServerExtension{0, Nil{}} Parameters{_, protocol}:
      Bool.pick(Result<&2, &2, Error, Parameters>, offeredName, Done{Parameters{True{}, protocol}}, Fail{RejectedExtension{0}})
    case ServerExtension{16, 0 <> 9 <> 8 <> 104 <> 116 <> 116 <> 112 <> 47 <> 49 <> 46 <> 49 <> Nil{}} Parameters{acknowledged, _}:
      Done{Parameters{acknowledged, Some{"http/1.1"}}}
    case ServerExtension{10, bytes} parameters:
      Result.bind(&2, &2, Error, Unit, Parameters, require(validGroups(bytes)), unused => Done{parameters})
    case ServerExtension{kind, _} _: Fail{RejectedExtension{kind}}

def containsKind(kinds: List<&2, U32>, +kind: U32) -> Bool:
  match kinds:
    case Nil{}: False{}
    case head <> rest: U32.is_eq(head, kind) || containsKind(rest, kind)

def selectExtensions(extensions: List<&2, ServerExtension>, +offeredName: Bool, +seen: List<&2, U32>, parameters: Parameters) -> Result<&2, &2, Error, Parameters>:
  match extensions:
    case Nil{}: Done{parameters}
    case ServerExtension{+kind, bytes} <> rest:
      unique = Bool.pick(Result<&2, &2, Error, Unit>, containsKind(seen, kind), Fail{DuplicateExtension{kind}}, Done{Unit{}})
      Result.bind(&2, &2, Error, Unit, Parameters, unique, unused =>
        Result.bind(&2, &2, Error, Parameters, Parameters, selectExtension(offeredName, ServerExtension{kind, bytes}, parameters), chosen =>
          selectExtensions(rest, offeredName, kind <> seen, chosen)))

def encryptedExtensions(offeredName: Bool, wire: List<&2, U32>) -> Result<&2, &2, Error, Parameters>:
  Result.bind(&2, &2, Error, List<&2, U32>, Parameters, messageBody(8, wire), body =>
    Result.bind(&2, &2, Error, List<&2, ServerExtension>, Parameters, extensionVector(body), parsed =>
      selectExtensions(parsed, offeredName, Nil{}, Parameters{False{}, None{}})))

type ServerParameters is Type:
  ServerParameters{handshake: Handshake, parameters: Parameters}

def offeredServerName(name: Maybe<&2, String>) -> Bool:
  match name:
    case None{}: False{}
    case Some{_}: True{}

def updatedParameters(state: ServerParameters, result: Result<&2, &2, Error, SHA.State>) -> Result<&2, &1, Error, ServerParameters>:
  match state result:
    case _ Fail{cause}: Fail{cause}
    case ServerParameters{Handshake{name, _, secret, client, server, write, read}, parameters} Done{transcript}:
      Done{ServerParameters{Handshake{name, transcript, secret, client, server, write, read}, parameters}}

def parameterState(handshake: Handshake, wire: List<&2, U32>, result: Result<&2, &2, Error, Parameters>) -> Result<&2, &1, Error, ServerParameters>:
  match handshake result:
    case _ Fail{cause}: Fail{cause}
    case Handshake{name, +transcript, secret, client, server, write, read} Done{parameters}:
      updatedParameters(ServerParameters{Handshake{name, transcript, secret, client, server, write, read}, parameters}, hashResult(SHA.State, SHA.update(wire, transcript)))

def acceptEncryptedExtensions(handshake: Handshake, +wire: List<&2, U32>) -> Result<&2, &1, Error, ServerParameters>:
  match handshake:
    case Handshake{+name, transcript, secret, client, server, write, read}:
      parameterState(Handshake{name, transcript, secret, client, server, write, read}, wire, encryptedExtensions(offeredServerName(name), wire))

# Wire evidence only: certificates must still undergo DER, chain, identity and
# signature verification. Our ClientHello requests no certificate extensions.
type CertificateEntry is Data:
  CertificateEntry{bytes: List<&2, U32>, rest: List<&2, U32>}

def certificateFragment(result: Result<&2, &2, Record.Error, Record.Fragment>) -> Result<&2, &2, Error, CertificateEntry>:
  match result:
    case Done{Record.Fragment{head <> tail, 0 <> 0 <> rest}}: Done{CertificateEntry{head <> tail, rest}}
    case _: Fail{MalformedHandshake{}}

def certificateEntry(bytes: List<&2, U32>) -> Result<&2, &2, Error, CertificateEntry>:
  match bytes:
    case a <> b <> c <> rest:
      certificateFragment(Record.take(U32.to_nat((a * 65536 + b * 256 + c : U32)), rest, Nil{}))
    case _: Fail{MalformedHandshake{}}

def certificateEntries(fuel: Nat, result: Result<&2, &2, Error, CertificateEntry>, reversed: List<&2, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match fuel result:
    case _ Fail{cause}: Fail{cause}
    case _ Done{CertificateEntry{bytes, Nil{}}}: Done{List.reverse(&2, List<&2, U32>, bytes <> reversed)}
    case 1n+fuel Done{CertificateEntry{bytes, rest}}: certificateEntries(fuel, certificateEntry(rest), bytes <> reversed)
    case _ _: Fail{MalformedHandshake{}}

def certificateBody(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match bytes:
    case 0 <> a <> b <> c <> +rest:
      +size = Record.length(rest, 0n)
      Result.bind(&2, &2, Error, Unit, List<&2, List<&2, U32>>, require(Nat.is_eq(size, U32.to_nat((a * 65536 + b * 256 + c : U32)))), unused =>
        certificateEntries(size, certificateEntry(rest), Nil{}))
    case _: Fail{MalformedHandshake{}}

def certificates(wire: List<&2, U32>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  Result.bind(&2, &2, Error, List<&2, U32>, List<&2, List<&2, U32>>, messageBody(11, wire), certificateBody)

type SignatureScheme is Data:
  EcdsaP256Sha256{}
  EcdsaP384Sha384{}
  RsaPssRsaeSha256{}

type CertificateSignature is Data:
  CertificateSignature{scheme: SignatureScheme, signature: List<&2, U32>, signedBytes: List<&2, U32>}

def signatureBytes(scheme: SignatureScheme, signedBytes: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, CertificateSignature>:
  match bytes:
    case +a <> +b <> +signature:
      Result.bind(&2, &2, Error, Unit, CertificateSignature, require(Nat.is_eq(Record.length(signature, 0n), U32.to_nat((a * 256 + b : U32))) && U32.is_gt((a * 256 + b : U32), 0)), unused =>
        Done{CertificateSignature{scheme, signature, signedBytes}})
    case _: Fail{MalformedHandshake{}}

def certificateVerifyBody(signedBytes: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, Error, CertificateSignature>:
  match bytes:
    case 4 <> 3 <> rest: signatureBytes(EcdsaP256Sha256{}, signedBytes, rest)
    case 5 <> 3 <> rest: signatureBytes(EcdsaP384Sha384{}, signedBytes, rest)
    case 8 <> 4 <> rest: signatureBytes(RsaPssRsaeSha256{}, signedBytes, rest)
    case _: Fail{RejectedParameters{}}

def certificateSignature(transcript: SHA.State, wire: List<&2, U32>) -> Result<&2, &2, Error, CertificateSignature>:
  Result.bind(&2, &2, Error, List<&2, U32>, CertificateSignature, messageBody(15, wire), body =>
    Result.bind(&2, &2, Error, SHA.Digest, CertificateSignature, hashResult(SHA.Digest, SHA.finish(transcript)), hash =>
      certificateVerifyBody(X.repeat(64n, 32, Record.append(ascii("TLS 1.3, server CertificateVerify"), 0 <> SHA.toBytes(hash))), body)))

# These checks authenticate handshake bytes relative to a supplied certificate
# key and traffic secret. Certificate path/identity authorization is separate.
def certificateResult(-A: Data, result: Result<&2, &2, X509.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Fail{cause}: Fail{CertificateFailure{cause}}
    case Done{value}: Done{value}

def verifyEvidence(key: X509.PublicKey, evidence: CertificateSignature) -> Result<&2, &2, Error, Unit>:
  match key evidence:
    case X509.Rsa{key} CertificateSignature{RsaPssRsaeSha256{}, signature, input}:
      certificateResult(Unit, X509.rsaResult(Unit, RSA.verifyPss(key, input, signature, 32n)))
    case X509.Ec{EC.P256{},key} CertificateSignature{EcdsaP256Sha256{}, signature, input}:
      certificateResult(Unit, X509.curveResult(Unit, EC.verify(EC.P256{}, EC.Sha256{}, key, input, signature)))
    case X509.Ec{EC.P384{},key} CertificateSignature{EcdsaP384Sha384{}, signature, input}:
      certificateResult(Unit, X509.curveResult(Unit, EC.verify(EC.P384{}, EC.Sha384{}, key, input, signature)))
    case _ _: Fail{RejectedParameters{}}

def verifyCertificateSignature(key: X509.PublicKey, +transcript: SHA.State, +wire: List<&2, U32>) -> Result<&2, &2, Error, SHA.State>:
  Result.bind(&2, &2, Error, CertificateSignature, SHA.State, certificateSignature(transcript, wire), evidence =>
    Result.bind(&2, &2, Error, Unit, SHA.State, verifyEvidence(key, evidence), unused =>
      hashResult(SHA.State, SHA.update(wire, transcript))))

def finishedMatch(valid: Bool) -> Result<&2, &2, Error, Unit>:
  match valid:
    case False{}: Fail{FinishedMismatch{}}
    case True{}: Done{Unit{}}

# The transcript excludes this Finished until its exact verify_data matches.
# For SHA-256 both the traffic secret and verify_data are exactly 32 bytes.
def verifyFinished(+secret: List<&2, U32>, +transcript: SHA.State, +wire: List<&2, U32>) -> Result<&2, &2, Error, SHA.State>:
  Result.bind(&2, &2, Error, List<&2, U32>, SHA.State, messageBody(20, wire), +body =>
    Result.bind(&2, &2, Error, Unit, SHA.State, require(Nat.is_eq(Record.length(body,0n),32n) && Nat.is_eq(Record.length(secret,0n),32n)), unused =>
      Result.bind(&2, &2, Error, SHA.Digest, SHA.State, hashResult(SHA.Digest, SHA.finish(transcript)), hash =>
        Result.bind(&2, &2, Error, SHA.Digest, SHA.State, derivation(SHA.Digest, KDF.finished(secret, hash)), expected =>
          Result.bind(&2, &2, Error, Unit, SHA.State, finishedMatch(RSA.equal(body, SHA.toBytes(expected), 0)), unused =>
            hashResult(SHA.State, SHA.update(wire, transcript)))))))

# Application traffic uses the transcript through server Finished. The returned
# Secrets are key-schedule material, not proof of a trusted peer. The connection
# layer must authorize the certificate and verify the server flight first.
def applicationSecrets(+handshakeSecret: List<&2, U32>, +transcript: SHA.State) -> Result<&2, &2, Error, Secrets>:
  Result.bind(&2, &2, Error, Unit, Secrets, require(Nat.is_eq(Record.length(handshakeSecret,0n),32n)), unused =>
    Result.bind(&2, &2, Error, SHA.Digest, Secrets, derivation(SHA.Digest, KDF.advance(handshakeSecret, X.small(0))), +master =>
      Result.bind(&2, &2, Error, SHA.Digest, Secrets, hashResult(SHA.Digest, SHA.finish(transcript)), +hash =>
        Result.bind(&2, &2, Error, List<&2, U32>, Secrets, derivation(List<&2, U32>, KDF.deriveSecret(SHA.toBytes(master), "c ap traffic", hash)), +client =>
          Result.bind(&2, &2, Error, List<&2, U32>, Secrets, derivation(List<&2, U32>, KDF.deriveSecret(SHA.toBytes(master), "s ap traffic", hash)), +server =>
            Result.bind(&2, &2, Error, TrafficKey, Secrets, deriveKey(client), write =>
              Result.bind(&2, &2, Error, TrafficKey, Secrets, deriveKey(server), read =>
                Done{Secrets{transcript,master,client,server,write,read}})))))))

# No client certificate was requested in this flow. Encrypt this message with
# the client handshake traffic key before switching the writer to application
# traffic. Application secrets exclude it; the resumption transcript includes it.
def clientFinished(+clientHandshakeSecret: List<&2, U32>, transcript: SHA.State) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, Unit, List<&2, U32>, require(Nat.is_eq(Record.length(clientHandshakeSecret,0n),32n)), unused =>
    Result.bind(&2, &2, Error, SHA.Digest, List<&2, U32>, hashResult(SHA.Digest, SHA.finish(transcript)), hash =>
      Result.bind(&2, &2, Error, SHA.Digest, List<&2, U32>, derivation(SHA.Digest, KDF.finished(clientHandshakeSecret,hash)), mac =>
        Done{20 <> 0 <> 0 <> 32 <> SHA.toBytes(mac)})))
