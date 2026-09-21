import Base
import ./sha256.bend as SHA
import ./hmac-sha256.bend as HMAC
import ./hkdf-sha256.bend as HKDF

# TLS 1.3 SHA-256 key derivation (RFC 8446 sections 4.4.4 and 7).
type Error is Data:
  Kdf{error: HKDF.Error}
  InvalidLabel{}
  InvalidContext{}
  InvalidLength{length: U32}

def kdfResult(-A: Data, result: Result<&2, &2, HKDF.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{Kdf{error}}

def characters(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{code}, rest}: code <> characters(rest)

def ascii(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case head <> rest: U32.is_lt(head, 128) && ascii(rest)

def encoded(validLabel: Bool, validContext: Bool, validLength: Bool, +label: List<&2, U32>, +context: List<&2, U32>, +length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  match validLabel validContext validLength:
    case False{} _ _: Fail{InvalidLabel{}}
    case True{} False{} _: Fail{InvalidContext{}}
    case True{} True{} False{}: Fail{InvalidLength{length}}
    case True{} True{} True{}:
      Result.bind(&2, &2, Error, Unit, List<&2, U32>, kdfResult(Unit, HKDF.hashResult(Unit, HMAC.validate(context))), unit =>
        Done{U32.shrn(length, 8n) <> U32.and(length, 255) <> (U32.from_nat(List.length(&2, U32, label)) + 6 : U32) <>
          List.append(&2, U32, characters("tls13 "), List.append(&2, U32, label, U32.from_nat(List.length(&2, U32, context)) <> context))})

def encodeLabel(label: String, +context: List<&2, U32>, +length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  +bytes = characters(label)
  encoded(HMAC.longer(bytes, 0n) && Bool.not(HMAC.longer(bytes, 249n)) && ascii(bytes), Bool.not(HMAC.longer(context, 255n)), U32.is_le(length, 65535), bytes, context, length)

def expandLabel(secret: List<&2, U32>, label: String, context: List<&2, U32>, +length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, encodeLabel(label, context, length), info => kdfResult(List<&2, U32>, HKDF.expand(secret, info, length)))

# The caller supplies the digest of precisely the handshake transcript required
# at this stage; record headers are not included in that transcript.
def deriveSecret(secret: List<&2, U32>, label: String, transcript: SHA.Digest) -> Result<&2, &2, Error, List<&2, U32>>:
  expandLabel(secret, label, SHA.toBytes(transcript), 32)

# Early -> handshake and handshake -> master use the same extract transition.
# For the master transition, input is 32 zero bytes, not an empty byte string.
def advance(secret: List<&2, U32>, input: List<&2, U32>) -> Result<&2, &2, Error, SHA.Digest>:
  Result.bind(&2, &2, Error, SHA.Digest, SHA.Digest, kdfResult(SHA.Digest, HKDF.hashResult(SHA.Digest, SHA.digest(Nil{}))), empty =>
    Result.bind(&2, &2, Error, List<&2, U32>, SHA.Digest, deriveSecret(secret, "derived", empty), salt => kdfResult(SHA.Digest, HKDF.extract(salt, input))))

def finished(secret: List<&2, U32>, transcript: SHA.Digest) -> Result<&2, &2, Error, SHA.Digest>:
  Result.bind(&2, &2, Error, List<&2, U32>, SHA.Digest, expandLabel(secret, "finished", Nil{}, 32), key => kdfResult(SHA.Digest, HKDF.hashResult(SHA.Digest, HMAC.digest(key, SHA.toBytes(transcript)))))
