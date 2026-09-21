import Base
import ./der.bend as DER
import ./rsa-sha256.bend as RSA

# Parsed wire evidence, not an authenticated identity. Trust, validity, names,
# constraints and extensions must be checked before a TLS connection is usable.
type Error is Data:
  Encoding{cause: DER.Error}
  InvalidCertificate{}
  UnsupportedAlgorithm{}
  Signature{cause: RSA.Error}

type Certificate is Data:
  Certificate{tbs: DER.Node, algorithm: DER.Node, signature: List<&2, U32>}

def decoded(-A: Data, result: Result<&2, &2, DER.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Fail{cause}: Fail{Encoding{cause}}
    case Done{value}: Done{value}

def rsaResult(-A: Data, result: Result<&2, &2, RSA.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Fail{cause}: Fail{Signature{cause}}
    case Done{value}: Done{value}

def signatureBytes(value: DER.Bits) -> Result<&2, &2, Error, List<&2, U32>>:
  match value:
    case DER.Bits{0, head <> rest}: Done{head <> rest}
    case _: Fail{InvalidCertificate{}}

def certificateFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, Certificate>:
  match nodes:
    case DER.Node{DER.Tag{0, True{}, 16}, header, body} <> DER.Node{DER.Tag{0, True{}, 16}, ah, ab} <> signature <> Nil{}:
      Result.bind(&2, &2, Error, DER.Bits, Certificate, decoded(DER.Bits, DER.bits(signature)), bitString =>
        Result.bind(&2, &2, Error, List<&2, U32>, Certificate, signatureBytes(bitString), bytes =>
          Done{Certificate{DER.Node{DER.Tag{0, True{}, 16}, header, body}, DER.Node{DER.Tag{0, True{}, 16}, ah, ab}, bytes}}))
    case _: Fail{InvalidCertificate{}}

def parse(bytes: List<&2, U32>) -> Result<&2, &2, Error, Certificate>:
  Result.bind(&2, &2, Error, DER.Node, Certificate, decoded(DER.Node, DER.one(bytes)), root =>
    Result.bind(&2, &2, Error, List<&2, DER.Node>, Certificate, decoded(List<&2, DER.Node>, DER.sequence(root)), certificateFields))

# Strip only canonical supported explicit versions. Version 1 (value zero) is
# DEFAULT and must be omitted in DER. Remaining schema checks are separate.
def tbsFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, List<&2, DER.Node>>:
  match nodes:
    case DER.Node{DER.Tag{2, True{}, 0}, _, 2 <> 1 <> +version <> Nil{}} <> rest:
      Bool.pick(Result<&2, &2, Error, List<&2, DER.Node>>, U32.is_eq(version, 1) || U32.is_eq(version, 2), Done{rest}, Fail{InvalidCertificate{}})
    case DER.Node{DER.Tag{2, _, 0}, _, _} <> _: Fail{InvalidCertificate{}}
    case nodes: Done{nodes}

def fields(tbs: DER.Node) -> Result<&2, &2, Error, List<&2, DER.Node>>:
  Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, DER.Node>, decoded(List<&2, DER.Node>, DER.sequence(tbs)), tbsFields)

def rsaIntegers(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, RSA.PublicKey>:
  match nodes:
    case modulus <> exponent <> Nil{}:
      Result.bind(&2, &2, Error, List<&2, U32>, RSA.PublicKey, decoded(List<&2, U32>, DER.unsigned(modulus)), n =>
        Result.bind(&2, &2, Error, List<&2, U32>, RSA.PublicKey, decoded(List<&2, U32>, DER.unsigned(exponent)), e => rsaResult(RSA.PublicKey, RSA.key(n, e))))
    case _: Fail{InvalidCertificate{}}

def rsaKeyBytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, RSA.PublicKey>:
  Result.bind(&2, &2, Error, DER.Node, RSA.PublicKey, decoded(DER.Node, DER.one(bytes)), root =>
    Result.bind(&2, &2, Error, List<&2, DER.Node>, RSA.PublicKey, decoded(List<&2, DER.Node>, DER.sequence(root)), rsaIntegers))

def rsaSubjectFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, RSA.PublicKey>:
  match nodes:
    case DER.Node{DER.Tag{0, True{}, 16}, _, 6 <> 9 <> 42 <> 134 <> 72 <> 134 <> 247 <> 13 <> 1 <> 1 <> 1 <> 5 <> 0 <> Nil{}} <> key <> Nil{}:
      Result.bind(&2, &2, Error, DER.Bits, RSA.PublicKey, decoded(DER.Bits, DER.bits(key)), bitString =>
        Result.bind(&2, &2, Error, List<&2, U32>, RSA.PublicKey, signatureBytes(bitString), rsaKeyBytes))
    case _: Fail{UnsupportedAlgorithm{}}

def rsaSubjectPublicKeyInfo(node: DER.Node) -> Result<&2, &2, Error, RSA.PublicKey>:
  Result.bind(&2, &2, Error, List<&2, DER.Node>, RSA.PublicKey, decoded(List<&2, DER.Node>, DER.sequence(node)), rsaSubjectFields)

def subjectKey(fields: List<&2, DER.Node>) -> Result<&2, &2, Error, RSA.PublicKey>:
  match fields:
    case _ <> _ <> _ <> _ <> _ <> key <> _: rsaSubjectPublicKeyInfo(key)
    case _: Fail{InvalidCertificate{}}

def rsaPublicKey(certificate: Certificate) -> Result<&2, &2, Error, RSA.PublicKey>:
  match certificate:
    case Certificate{tbs, _, _}: Result.bind(&2, &2, Error, List<&2, DER.Node>, RSA.PublicKey, fields(tbs), subjectKey)

def matchingAlgorithm(nodes: List<&2, DER.Node>, +algorithm: DER.Node) -> Result<&2, &2, Error, Unit>:
  match nodes:
    case _ <> inner <> _:
      Bool.pick(Result<&2, &2, Error, Unit>, RSA.equal(DER.encoded(inner), DER.encoded(algorithm), 0), Done{Unit{}}, Fail{InvalidCertificate{}})
    case _: Fail{InvalidCertificate{}}

# Cryptographic signature verification with an explicitly supplied issuer key.
# This does not establish that the issuer is trusted or allowed to issue a cert.
def verifyRsaSha256(issuer: RSA.PublicKey, certificate: Certificate) -> Result<&2, &2, Error, Unit>:
  match certificate:
    case Certificate{+tbs, DER.Node{DER.Tag{0, True{}, 16}, +header, +body}, signature}:
      algorithm = {DER.Node{DER.Tag{0, True{}, 16}, header, body} : DER.Node}
      allowed = Bool.pick(Result<&2, &2, Error, Unit>, RSA.equal(body, 6 <> 9 <> 42 <> 134 <> 72 <> 134 <> 247 <> 13 <> 1 <> 1 <> 11 <> 5 <> 0 <> Nil{}, 0), Done{Unit{}}, Fail{UnsupportedAlgorithm{}})
      Result.bind(&2, &2, Error, Unit, Unit, allowed, unused =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, Unit, fields(tbs), nodes =>
          Result.bind(&2, &2, Error, Unit, Unit, matchingAlgorithm(nodes, algorithm), unused =>
            rsaResult(Unit, RSA.verifyPkcs1(issuer, DER.encoded(tbs), signature)))))
    case _: Fail{UnsupportedAlgorithm{}}
