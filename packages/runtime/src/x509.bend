import Base
import ./der.bend as DER
import ./rsa-sha256.bend as RSA
import ./ecdsa.bend as EC
import ./calendar.bend as Calendar
import ./u64.bend as W
import ./big-nat.bend as Big
import ./utf8.bend as UTF8

# Parsed wire evidence, not an authenticated identity. Trust, validity, names,
# constraints and extensions must be checked before a TLS connection is usable.
type Error is Data:
  Encoding{cause: DER.Error}
  InvalidCertificate{}
  UnsupportedAlgorithm{}
  Signature{cause: RSA.Error}
  Curve{cause: EC.Error}
  InvalidTime{}
  NotYetValid{}
  Expired{}
  DuplicateExtension{oid: List<&2, U32>}
  UnsupportedCriticalExtension{oid: List<&2, U32>}
  NotCertificateAuthority{}
  InvalidKeyUsage{}
  InvalidPurpose{}
  PathLengthExceeded{}
  UnsupportedNameEncoding{tag: U32}
  UnsupportedConstraint{oid: List<&2,U32>}
  IssuerMismatch{}
  NoTrustedPath{}
  PathSearchLimit{}

type PublicKey is Data:
  Rsa{key: RSA.PublicKey}
  Ec{curve: EC.Curve, point: EC.Point}

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

def curveResult(-A: Data, result: Result<&2, &2, EC.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Fail{cause}: Fail{Curve{cause}}
    case Done{value}: Done{value}

def ecSubject(+selected: EC.Curve, key: DER.Node) -> Result<&2,&2,Error,PublicKey>:
  Result.bind(&2,&2,Error,DER.Bits,PublicKey,decoded(DER.Bits,DER.bits(key)), bitString =>
    Result.bind(&2,&2,Error,List<&2,U32>,PublicKey,signatureBytes(bitString), bytes =>
      Result.bind(&2,&2,Error,EC.Point,PublicKey,curveResult(EC.Point,EC.publicKey(selected,bytes)), value => Done{Ec{selected,value}})))

def subjectFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, PublicKey>:
  match nodes:
    case DER.Node{DER.Tag{0, True{}, 16}, _, 6 <> 9 <> 42 <> 134 <> 72 <> 134 <> 247 <> 13 <> 1 <> 1 <> 1 <> 5 <> 0 <> Nil{}} <> key <> Nil{}:
      Result.bind(&2, &2, Error, DER.Bits, PublicKey, decoded(DER.Bits, DER.bits(key)), bitString =>
        Result.bind(&2, &2, Error, List<&2, U32>, PublicKey, signatureBytes(bitString), bytes =>
          Result.bind(&2, &2, Error, RSA.PublicKey, PublicKey, rsaKeyBytes(bytes), value => Done{Rsa{value}})))
    case DER.Node{DER.Tag{0, True{}, 16}, _, 6 <> 7 <> 42 <> 134 <> 72 <> 206 <> 61 <> 2 <> 1 <> 6 <> 8 <> 42 <> 134 <> 72 <> 206 <> 61 <> 3 <> 1 <> 7 <> Nil{}} <> key <> Nil{}:
      ecSubject(EC.P256{},key)
    case DER.Node{DER.Tag{0, True{}, 16}, _, 6 <> 7 <> 42 <> 134 <> 72 <> 206 <> 61 <> 2 <> 1 <> 6 <> 5 <> 43 <> 129 <> 4 <> 0 <> 34 <> Nil{}} <> key <> Nil{}:
      ecSubject(EC.P384{},key)
    case _: Fail{UnsupportedAlgorithm{}}

def subjectKey(fields: List<&2, DER.Node>) -> Result<&2, &2, Error, PublicKey>:
  match fields:
    case _ <> _ <> _ <> _ <> _ <> key <> _:
      Result.bind(&2, &2, Error, List<&2, DER.Node>, PublicKey, decoded(List<&2, DER.Node>, DER.sequence(key)), subjectFields)
    case _: Fail{InvalidCertificate{}}

def publicKey(certificate: Certificate) -> Result<&2, &2, Error, PublicKey>:
  match certificate:
    case Certificate{tbs, _, _}: Result.bind(&2, &2, Error, List<&2, DER.Node>, PublicKey, fields(tbs), subjectKey)

def matchingAlgorithm(nodes: List<&2, DER.Node>, +algorithm: DER.Node) -> Result<&2, &2, Error, Unit>:
  match nodes:
    case _ <> inner <> _:
      Bool.pick(Result<&2, &2, Error, Unit>, RSA.equal(DER.encoded(inner), DER.encoded(algorithm), 0), Done{Unit{}}, Fail{InvalidCertificate{}})
    case _: Fail{InvalidCertificate{}}

# The key type and exact AlgorithmIdentifier jointly select verification.
# ECDSA parameters must be absent; rsaEncryption/SHA256 use explicit NULL.
def signatureAlgorithm(issuer: PublicKey, body: List<&2, U32>, message: List<&2, U32>, signature: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  match issuer body:
    case Rsa{key} 6 <> 9 <> 42 <> 134 <> 72 <> 134 <> 247 <> 13 <> 1 <> 1 <> 11 <> 5 <> 0 <> Nil{}:
      rsaResult(Unit, RSA.verifyPkcs1(key, message, signature))
    case Ec{selected,key} 6 <> 8 <> 42 <> 134 <> 72 <> 206 <> 61 <> 4 <> 3 <> 2 <> Nil{}:
      curveResult(Unit,EC.verify(selected,EC.Sha256{},key,message,signature))
    case Ec{selected,key} 6 <> 8 <> 42 <> 134 <> 72 <> 206 <> 61 <> 4 <> 3 <> 3 <> Nil{}:
      curveResult(Unit,EC.verify(selected,EC.Sha384{},key,message,signature))
    case _ _: Fail{UnsupportedAlgorithm{}}

# An explicitly supplied issuer key proves a signature, not trust or authority.
def verifySignature(issuer: PublicKey, certificate: Certificate) -> Result<&2, &2, Error, Unit>:
  match certificate:
    case Certificate{+tbs, DER.Node{DER.Tag{0, True{}, 16}, +header, +body}, signature}:
      algorithm = {DER.Node{DER.Tag{0, True{}, 16}, header, body} : DER.Node}
      Result.bind(&2, &2, Error, List<&2, DER.Node>, Unit, fields(tbs), nodes =>
        Result.bind(&2, &2, Error, Unit, Unit, matchingAlgorithm(nodes, algorithm), unused =>
          signatureAlgorithm(issuer, body, DER.encoded(tbs), signature)))
    case _: Fail{UnsupportedAlgorithm{}}

# RFC 5280 times require seconds and a literal Z, without offsets/fractions.
# The calendar primitive validates civil fields and supplies exact signed epochs.
type Validity is Data:
  Validity{notBefore: W.U64, notAfter: W.U64}

def digits(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case +byte <> rest: U32.is_ge(byte, 48) && U32.is_le(byte, 57) && digits(rest)

def pair(a: U32, b: U32) -> U32:
  ((a - 48) * 10 + b - 48 : U32)

def epoch(result: Result<&2, &2, Calendar.CalendarError, W.U64>) -> Result<&2, &2, Error, W.U64>:
  match result:
    case Fail{_}: Fail{InvalidTime{}}
    case Done{value}: Done{value}

def timeParts(year: U32, bytes: List<&2, U32>) -> Result<&2, &2, Error, W.U64>:
  match bytes:
    case +a <> +b <> +c <> +d <> +e <> +f <> +g <> +h <> +i <> +j <> 90 <> Nil{}:
      checked = Bool.pick(Result<&2, &2, Error, Unit>, digits(a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> Nil{}), Done{Unit{}}, Fail{InvalidTime{}})
      Result.bind(&2, &2, Error, Unit, W.U64, checked, unused => epoch(Calendar.toEpochMilliseconds(Calendar.CivilTime{year, pair(a,b), pair(c,d), pair(e,f), pair(g,h), pair(i,j), 0})))
    case _: Fail{InvalidTime{}}

def timeYear(valid: Bool, year: U32, rest: List<&2, U32>) -> Result<&2, &2, Error, W.U64>:
  match valid:
    case False{}: Fail{InvalidTime{}}
    case True{}: timeParts(year, rest)

def time(node: DER.Node) -> Result<&2, &2, Error, W.U64>:
  match node:
    case DER.Node{DER.Tag{0, False{}, 23}, _, +a <> +b <> rest}:
      +year = pair(a,b)
      timeYear(digits(a <> b <> Nil{}), (Bool.pick(U32, U32.is_ge(year, 50), 1900, 2000) + year : U32), rest)
    case DER.Node{DER.Tag{0, False{}, 24}, _, +a <> +b <> +c <> +d <> rest}:
      timeYear(digits(a <> b <> c <> d <> Nil{}), (pair(a,b) * 100 + pair(c,d) : U32), rest)
    case _: Fail{InvalidTime{}}

def signedCompare(left: W.U64, right: W.U64) -> Cmp:
  match left right:
    case W.U64{a,b} W.U64{c,d}: W.compare(W.U64{U32.xor(a,2147483648),b}, W.U64{U32.xor(c,2147483648),d})

def interval(+start: W.U64, +end: W.U64) -> Result<&2, &2, Error, Validity>:
  Bool.pick(Result<&2, &2, Error, Validity>, W.atLeast(signedCompare(end,start)), Done{Validity{start,end}}, Fail{InvalidTime{}})

def validityTimes(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, Validity>:
  match nodes:
    case start <> end <> Nil{}:
      Result.bind(&2, &2, Error, W.U64, Validity, time(start), a =>
        Result.bind(&2, &2, Error, W.U64, Validity, time(end), b => interval(a,b)))
    case _: Fail{InvalidTime{}}

def validityFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, Validity>:
  match nodes:
    case _ <> _ <> _ <> value <> _:
      Result.bind(&2, &2, Error, List<&2, DER.Node>, Validity, decoded(List<&2, DER.Node>, DER.sequence(value)), validityTimes)
    case _: Fail{InvalidCertificate{}}

def validity(certificate: Certificate) -> Result<&2, &2, Error, Validity>:
  match certificate:
    case Certificate{tbs, _, _}: Result.bind(&2, &2, Error, List<&2, DER.Node>, Validity, fields(tbs), validityFields)

def checkedValidity(before: Cmp, after: Cmp) -> Result<&2, &2, Error, Unit>:
  match before after:
    case LT{} _: Fail{NotYetValid{}}
    case _ GT{}: Fail{Expired{}}
    case _ _: Done{Unit{}}

def validAt(+now: W.U64, validity: Validity) -> Result<&2, &2, Error, Unit>:
  match validity:
    case Validity{start,end}: checkedValidity(signedCompare(now,start), signedCompare(now,end))

# Unknown extensions remain explicit values. A path validator must reject
# critical extensions it cannot process; parsing alone does not authorize them.
type Extension is Data:
  Extension{oid: List<&2, U32>, critical: Bool, value: List<&2, U32>}

def oidGroups(bytes: List<&2, U32>, +start: Bool) -> Bool:
  match bytes:
    case Nil{}: start
    case +byte <> rest:
      Bool.not(start && U32.is_eq(byte,128)) && oidGroups(rest,U32.is_lt(byte,128))

def extensionValue(oid: List<&2, U32>, critical: Bool, value: List<&2, U32>) -> Result<&2, &2, Error, Extension>:
  match oid:
    case +head <> +tail:
      Bool.pick(Result<&2, &2, Error, Extension>, oidGroups(head <> tail,True{}), Done{Extension{head <> tail,critical,value}}, Fail{InvalidCertificate{}})
    case Nil{}: Fail{InvalidCertificate{}}

def extensionFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, Extension>:
  match nodes:
    case DER.Node{DER.Tag{0,False{},6},_,oid} <> DER.Node{DER.Tag{0,False{},4},_,value} <> Nil{}:
      extensionValue(oid,False{},value)
    case DER.Node{DER.Tag{0,False{},6},_,oid} <> DER.Node{DER.Tag{0,False{},1},_,255 <> Nil{}} <> DER.Node{DER.Tag{0,False{},4},_,value} <> Nil{}:
      extensionValue(oid,True{},value)
    case _: Fail{InvalidCertificate{}}

def hasExtension(values: List<&2, Extension>, +oid: List<&2, U32>) -> Bool:
  match values:
    case Nil{}: False{}
    case Extension{other,_,_} <> rest: RSA.equal(oid,other,0) || hasExtension(rest,oid)

def insertExtension(value: Extension, +seen: List<&2, Extension>) -> Result<&2, &2, Error, List<&2, Extension>>:
  match value:
    case Extension{+oid,critical,bytes}:
      Bool.pick(Result<&2, &2, Error, List<&2, Extension>>, hasExtension(seen,oid), Fail{DuplicateExtension{oid}}, Done{Extension{oid,critical,bytes} <> seen})

def orderedExtensions(result: Result<&2, &2, Error, List<&2, Extension>>) -> Result<&2, &2, Error, List<&2, Extension>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{values}: Done{List.reverse(&2,Extension,values)}

def decodeExtensions(nodes: List<&2, DER.Node>, result: Result<&2, &2, Error, List<&2, Extension>>) -> Result<&2, &2, Error, List<&2, Extension>>:
  match nodes result:
    case Nil{} result: orderedExtensions(result)
    case _ Fail{cause}: Fail{cause}
    case node <> rest Done{seen}:
      decodeExtensions(rest,
        Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, Extension>, decoded(List<&2, DER.Node>,DER.sequence(node)), parts =>
          Result.bind(&2, &2, Error, Extension, List<&2, Extension>, extensionFields(parts), value => insertExtension(value,seen))))

def nonemptyExtensions(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, List<&2, Extension>>:
  match nodes:
    case Nil{}: Fail{InvalidCertificate{}}
    case head <> rest: decodeExtensions(head <> rest,Done{Nil{}})

def extensionSequence(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, Extension>>:
  Result.bind(&2, &2, Error, DER.Node, List<&2, Extension>, decoded(DER.Node,DER.one(bytes)), root =>
    Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, Extension>, decoded(List<&2, DER.Node>,DER.sequence(root)), nonemptyExtensions))

def optionalFields(nodes: List<&2, DER.Node>, +version: U32, stage: U32) -> Result<&2, &2, Error, List<&2, Extension>>:
  match nodes:
    case Nil{}: Done{Nil{}}
    case DER.Node{DER.Tag{2,False{},+kind},header,bytes} <> rest:
      allowed = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_ge(version,1) && U32.is_gt(kind,stage) && U32.is_le(kind,2), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, List<&2, Extension>, allowed, unused =>
        Result.bind(&2, &2, Error, DER.Bits, List<&2, Extension>, decoded(DER.Bits,DER.bits(DER.Node{DER.Tag{0,False{},3},header,bytes})), unused => optionalFields(rest,version,kind)))
    case DER.Node{DER.Tag{2,True{},3},_,bytes} <> Nil{}:
      allowed = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_eq(version,2), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, List<&2, Extension>, allowed, unused => extensionSequence(bytes))
    case _: Fail{InvalidCertificate{}}

def afterSubject(nodes: List<&2, DER.Node>, version: U32) -> Result<&2, &2, Error, List<&2, Extension>>:
  match nodes:
    case _ <> _ <> _ <> _ <> _ <> _ <> rest: optionalFields(rest,version,0)
    case _: Fail{InvalidCertificate{}}

def extensionsFromTbs(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, List<&2, Extension>>:
  match nodes:
    case DER.Node{DER.Tag{2,True{},0},_,2 <> 1 <> +version <> Nil{}} <> rest:
      allowed = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_eq(version,1) || U32.is_eq(version,2), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, List<&2, Extension>, allowed, unused => afterSubject(rest,version))
    case DER.Node{DER.Tag{2,_,0},_,_} <> _: Fail{InvalidCertificate{}}
    case nodes: afterSubject(nodes,0)

def extensions(certificate: Certificate) -> Result<&2, &2, Error, List<&2, Extension>>:
  match certificate:
    case Certificate{tbs,_,_}:
      Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, Extension>, decoded(List<&2, DER.Node>,DER.sequence(tbs)), extensionsFromTbs)

type BasicConstraints is Data:
  BasicConstraints{ca: Bool, pathLength: Maybe<&2, Big.BigNat>}

def basicFields(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, BasicConstraints>:
  match nodes:
    case Nil{}: Done{BasicConstraints{False{},None{}}}
    case DER.Node{DER.Tag{0,False{},1},_,255 <> Nil{}} <> Nil{}: Done{BasicConstraints{True{},None{}}}
    case DER.Node{DER.Tag{0,False{},1},_,255 <> Nil{}} <> path <> Nil{}:
      Result.bind(&2, &2, Error, List<&2, U32>, BasicConstraints, decoded(List<&2, U32>,DER.unsigned(path)), bytes =>
        Done{BasicConstraints{True{},Some{Big.fromBigEndian(bytes)}}})
    case _: Fail{InvalidCertificate{}}

def basicConstraints(extension: Extension) -> Result<&2, &2, Error, BasicConstraints>:
  match extension:
    case Extension{85 <> 29 <> 19 <> Nil{},_,value}:
      Result.bind(&2, &2, Error, DER.Node, BasicConstraints, decoded(DER.Node,DER.one(value)), node =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, BasicConstraints, decoded(List<&2, DER.Node>,DER.sequence(node)), basicFields))
    case _: Fail{InvalidCertificate{}}

type KeyUsage is Data:
  KeyUsage{digitalSignature: Bool, contentCommitment: Bool, keyEncipherment: Bool, dataEncipherment: Bool, keyAgreement: Bool, keyCertSign: Bool, crlSign: Bool, encipherOnly: Bool, decipherOnly: Bool}

def flag(byte: U32, mask: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(byte,mask),0))

def usageFlags(+first: U32, last: Bool) -> KeyUsage:
  KeyUsage{flag(first,128),flag(first,64),flag(first,32),flag(first,16),flag(first,8),flag(first,4),flag(first,2),flag(first,1),last}

def zeroBits(fuel: Nat, +byte: U32) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+fuel: Bool.pick(Nat,flag(byte,1),0n,1n+zeroBits(fuel,U32.shr(byte)))

# KeyUsage is a named-bit list: DER omits every trailing zero bit, and RFC5280
# requires at least one usage bit. The nine bits are preserved without imposing
# algorithm-specific authorization here.
def usageBits(bits: DER.Bits) -> Result<&2, &2, Error, KeyUsage>:
  match bits:
    case DER.Bits{unused,+first <> Nil{}}:
      Bool.pick(Result<&2, &2, Error, KeyUsage>, U32.is_gt(first,0) && Nat.is_eq(U32.to_nat(unused),zeroBits(8n,first)), Done{usageFlags(first,False{})}, Fail{InvalidCertificate{}})
    case DER.Bits{7,first <> 128 <> Nil{}}: Done{usageFlags(first,True{})}
    case _: Fail{InvalidCertificate{}}

def keyUsage(extension: Extension) -> Result<&2, &2, Error, KeyUsage>:
  match extension:
    case Extension{85 <> 29 <> 15 <> Nil{},_,value}:
      Result.bind(&2, &2, Error, DER.Node, KeyUsage, decoded(DER.Node,DER.one(value)), node =>
        Result.bind(&2, &2, Error, DER.Bits, KeyUsage, decoded(DER.Bits,DER.bits(node)), usageBits))
    case _: Fail{InvalidCertificate{}}

def purposeList(nodes: List<&2, DER.Node>, reversed: List<&2, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match nodes:
    case Nil{}: Done{List.reverse(&2,List<&2,U32>,reversed)}
    case DER.Node{DER.Tag{0,False{},6},_,+head <> +tail} <> rest:
      checked = Bool.pick(Result<&2, &2, Error, Unit>, oidGroups(head <> tail,True{}), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, List<&2, List<&2, U32>>, checked, unused => purposeList(rest,(head <> tail) <> reversed))
    case _: Fail{InvalidCertificate{}}

def purposes(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match nodes:
    case Nil{}: Fail{InvalidCertificate{}}
    case head <> rest: purposeList(head <> rest,Nil{})

def extendedKeyUsage(extension: Extension) -> Result<&2, &2, Error, List<&2, List<&2, U32>>>:
  match extension:
    case Extension{85 <> 29 <> 37 <> Nil{},_,value}:
      Result.bind(&2, &2, Error, DER.Node, List<&2, List<&2, U32>>, decoded(DER.Node,DER.one(value)), node =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, List<&2, U32>>, decoded(List<&2, DER.Node>,DER.sequence(node)), purposes))
    case _: Fail{InvalidCertificate{}}

type GeneralName is Data:
  DnsName{value: String}
  IpAddress{bytes: List<&2, U32>}
  Mailbox{value: String}
  Uri{value: String}
  RegisteredId{oid: List<&2, U32>}
  StructuredName{node: DER.Node}

def ia5(bytes: List<&2, U32>, reverse: String) -> Result<&2, &2, Error, String>:
  match bytes:
    case Nil{}: Done{String.reverse(reverse)}
    case +byte <> rest:
      checked = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_lt(byte,128), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, String, checked, unused => ia5(rest,SCon{Chr{byte},reverse}))

# Decode identifiers without normalizing or matching them. Other ASN.1 name
# forms are retained explicitly for later name-constraint and schema handling.
def generalName(node: DER.Node) -> Result<&2, &2, Error, GeneralName>:
  match node:
    case DER.Node{DER.Tag{2,False{},2},_,head <> tail}:
      Result.bind(&2, &2, Error, String, GeneralName, ia5(head <> tail,""), text => Done{DnsName{text}})
    case DER.Node{DER.Tag{2,False{},1},_,head <> tail}:
      Result.bind(&2, &2, Error, String, GeneralName, ia5(head <> tail,""), text => Done{Mailbox{text}})
    case DER.Node{DER.Tag{2,False{},6},_,head <> tail}:
      Result.bind(&2, &2, Error, String, GeneralName, ia5(head <> tail,""), text => Done{Uri{text}})
    case DER.Node{DER.Tag{2,False{},7},_,+bytes}:
      +size = DER.length(bytes,0n)
      Bool.pick(Result<&2, &2, Error, GeneralName>, Nat.is_eq(size,4n) || Nat.is_eq(size,16n), Done{IpAddress{bytes}}, Fail{InvalidCertificate{}})
    case DER.Node{DER.Tag{2,False{},8},_,+head <> +tail}:
      Bool.pick(Result<&2, &2, Error, GeneralName>, oidGroups(head <> tail,True{}), Done{RegisteredId{head <> tail}}, Fail{InvalidCertificate{}})
    case DER.Node{DER.Tag{2,True{},+kind},header,+body}:
      allowed = Bool.pick(Result<&2, &2, Error, Unit>, U32.is_eq(kind,0) || U32.is_eq(kind,3) || U32.is_eq(kind,4) || U32.is_eq(kind,5), Done{Unit{}}, Fail{InvalidCertificate{}})
      Result.bind(&2, &2, Error, Unit, GeneralName, allowed, unused =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, GeneralName, decoded(List<&2, DER.Node>,DER.all(body)), unused =>
          Done{StructuredName{DER.Node{DER.Tag{2,True{},kind},header,body}}}))
    case _: Fail{InvalidCertificate{}}

def generalNames(nodes: List<&2, DER.Node>, result: Result<&2, &2, Error, List<&2, GeneralName>>) -> Result<&2, &2, Error, List<&2, GeneralName>>:
  match nodes result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{reversed}: Done{List.reverse(&2,GeneralName,reversed)}
    case head <> tail Done{reversed}:
      generalNames(tail,Result.bind(&2, &2, Error, GeneralName, List<&2, GeneralName>, generalName(head), name => Done{name <> reversed}))

def nonemptyNames(nodes: List<&2, DER.Node>) -> Result<&2, &2, Error, List<&2, GeneralName>>:
  match nodes:
    case Nil{}: Fail{InvalidCertificate{}}
    case head <> tail: generalNames(head <> tail,Done{Nil{}})

def subjectAltNames(extension: Extension) -> Result<&2, &2, Error, List<&2, GeneralName>>:
  match extension:
    case Extension{85 <> 29 <> 17 <> Nil{},_,value}:
      Result.bind(&2, &2, Error, DER.Node, List<&2, GeneralName>, decoded(DER.Node,DER.one(value)), node =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, List<&2, GeneralName>, decoded(List<&2, DER.Node>,DER.sequence(node)), nonemptyNames))
    case _: Fail{InvalidCertificate{}}

# Policy is decoded evidence. Signature/path/name/time checks remain separate.
# An absent usage extension imposes no restriction; an absent CA constraint
# never grants authority to an intermediate certificate.
type Policy is Data:
  Policy{constraints: BasicConstraints, usage: Maybe<&2, KeyUsage>, eku: Maybe<&2, List<&2, List<&2, U32>>>}

def unsupportedConstraint(oid: List<&2,U32>) -> Bool:
  match oid:
    case 85 <> 29 <> +kind <> Nil{}: U32.is_eq(kind,30) || U32.is_eq(kind,33) || U32.is_eq(kind,36) || U32.is_eq(kind,54)
    case _: False{}

def unhandledExtension(extension: Extension, state: Policy) -> Result<&2,&2,Error,Policy>:
  match extension:
    case Extension{oid,True{},_}: Fail{UnsupportedCriticalExtension{oid}}
    case Extension{+oid,False{},_}: Bool.pick(Result<&2,&2,Error,Policy>,unsupportedConstraint(oid),Fail{UnsupportedConstraint{oid}},Done{state})

def policyExtension(+extension: Extension, state: Policy) -> Result<&2, &2, Error, Policy>:
  match extension state:
    case Extension{85 <> 29 <> 19 <> Nil{},_,_} Policy{_,usage,eku}:
      Result.bind(&2,&2,Error,BasicConstraints,Policy,basicConstraints(extension), basic => Done{Policy{basic,usage,eku}})
    case Extension{85 <> 29 <> 15 <> Nil{},_,_} Policy{basic,_,eku}:
      Result.bind(&2,&2,Error,KeyUsage,Policy,keyUsage(extension), usage => Done{Policy{basic,Some{usage},eku}})
    case Extension{85 <> 29 <> 37 <> Nil{},_,_} Policy{basic,usage,_}:
      Result.bind(&2,&2,Error,List<&2,List<&2,U32>>,Policy,extendedKeyUsage(extension), eku => Done{Policy{basic,usage,Some{eku}}})
    case Extension{85 <> 29 <> 17 <> Nil{},_,_} state:
      Result.bind(&2,&2,Error,List<&2,GeneralName>,Policy,subjectAltNames(extension), unused => Done{state})
    case _ state: unhandledExtension(extension,state)

def policyExtensions(extensions: List<&2, Extension>, state: Policy) -> Result<&2,&2,Error,Policy>:
  match extensions:
    case Nil{}: Done{state}
    case head <> rest:
      Result.bind(&2,&2,Error,Policy,Policy,policyExtension(head,state), next => policyExtensions(rest,next))

def certificatePolicy(certificate: Certificate) -> Result<&2,&2,Error,Policy>:
  Result.bind(&2,&2,Error,List<&2,Extension>,Policy,extensions(certificate), values =>
    policyExtensions(values,Policy{BasicConstraints{False{},None{}},None{},None{}}))

def hasServerPurpose(values: List<&2,List<&2,U32>>) -> Bool:
  match values:
    case Nil{}: False{}
    case (43 <> 6 <> 1 <> 5 <> 5 <> 7 <> 3 <> 1 <> Nil{}) <> _: True{}
    case _ <> rest: hasServerPurpose(rest)

# Like OpenSSL's sslserver purpose, an EKU extension must explicitly contain
# serverAuth; anyExtendedKeyUsage alone does not grant this purpose.
def serverPurpose(eku: Maybe<&2,List<&2,List<&2,U32>>>) -> Result<&2,&2,Error,Unit>:
  match eku:
    case None{}: Done{Unit{}}
    case Some{values}: Bool.pick(Result<&2,&2,Error,Unit>,hasServerPurpose(values),Done{Unit{}},Fail{InvalidPurpose{}})

def signingUsage(usage: Maybe<&2,KeyUsage>) -> Result<&2,&2,Error,Unit>:
  match usage:
    case None{}: Done{Unit{}}
    case Some{KeyUsage{True{},_,_,_,_,_,_,_,_}}: Done{Unit{}}
    case _: Fail{InvalidKeyUsage{}}

def issuingUsage(usage: Maybe<&2,KeyUsage>) -> Result<&2,&2,Error,Unit>:
  match usage:
    case None{}: Done{Unit{}}
    case Some{KeyUsage{_,_,_,_,_,True{},_,_,_}}: Done{Unit{}}
    case _: Fail{InvalidKeyUsage{}}

# TLS1.3 signs CertificateVerify; keyEncipherment alone is insufficient.
def checkServerPolicy(policy: Policy) -> Result<&2,&2,Error,Unit>:
  match policy:
    case Policy{_,usage,eku}:
      Result.bind(&2,&2,Error,Unit,Unit,serverPurpose(eku), unused => signingUsage(usage))

def withinPathLimit(order: Cmp) -> Result<&2,&2,Error,Unit>:
  match order:
    case GT{}: Fail{PathLengthExceeded{}}
    case _: Done{Unit{}}

def pathLimit(limit: Maybe<&2,Big.BigNat>, count: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  match limit:
    case None{}: Done{Unit{}}
    case Some{maximum}: withinPathLimit(Big.compare(count,maximum))

# For intermediate CAs, not trust anchors. Count only non-self-issued
# intermediate certificates below this issuer, excluding the target leaf.
def checkIssuerPolicy(policy: Policy, intermediatesBelow: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  match policy:
    case Policy{BasicConstraints{False{},_},_,_}: Fail{NotCertificateAuthority{}}
    case Policy{BasicConstraints{True{},limit},usage,eku}:
      Result.bind(&2,&2,Error,Unit,Unit,issuingUsage(usage), unused =>
        Result.bind(&2,&2,Error,Unit,Unit,serverPurpose(eku), unused => pathLimit(limit,intermediatesBelow)))

# Ordered RDNs contain unordered multisets of attributes. Values use the
# OpenSSL comparison form: common string encodings compare as text, with ASCII
# case/space folding; non-ASCII code points remain exact (no Unicode folding).
type NameValue is Data:
  TextNameValue{text: String}
  EncodedNameValue{node: DER.Node}

type NameAttribute is Data:
  NameAttribute{oid: List<&2,U32>, value: NameValue}

type DistinguishedName is Data:
  DistinguishedName{rdns: List<&2,List<&2,NameAttribute>>}

type CertificateNames is Data:
  CertificateNames{issuer: DistinguishedName, subject: DistinguishedName}

def nameScalar(+code: U32, reversed: String) -> Result<&2,&2,Error,String>:
  Bool.pick(Unit -> Result<&2,&2,Error,String>,U32.is_le(code,1114111) && Bool.not(U32.is_ge(code,55296) && U32.is_le(code,57343)),unused => Done{SCon{Char.from_u32(code),reversed}},unused => Fail{InvalidCertificate{}})(Unit{})

def wideName(bytes: List<&2,U32>, +width: U32, reversed: String) -> Result<&2,&2,Error,String>:
  match bytes width:
    case Nil{} _: Done{String.reverse(reversed)}
    case a <> b <> rest 2:
      Result.bind(&2,&2,Error,String,String,nameScalar((a * 256 + b : U32),reversed), next => wideName(rest,width,next))
    case a <> b <> c <> d <> rest 4:
      Result.bind(&2,&2,Error,String,String,nameScalar((a * 16777216 + b * 65536 + c * 256 + d : U32),reversed), next => wideName(rest,width,next))
    case _ _: Fail{InvalidCertificate{}}

def printable(+code: U32) -> Bool:
  (U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122)) || (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,32) || U32.is_eq(code,39) || (U32.is_ge(code,40) && U32.is_le(code,41)) || (U32.is_ge(code,43) && U32.is_le(code,47)) || U32.is_eq(code,58) || U32.is_eq(code,61) || U32.is_eq(code,63)

def nameByteAllowed(tag: U32, +code: U32) -> Bool:
  match tag:
    case 19: printable(code)
    case 20: U32.is_le(code,255)
    case 22: U32.is_le(code,127)
    case _: False{}

def narrowName(bytes: List<&2,U32>, +tag: U32, reversed: String) -> Result<&2,&2,Error,String>:
  match bytes:
    case Nil{}: Done{String.reverse(reversed)}
    case +byte <> rest:
      checked = Bool.pick(Result<&2,&2,Error,Unit>,nameByteAllowed(tag,byte),Done{Unit{}},Fail{InvalidCertificate{}})
      Result.bind(&2,&2,Error,Unit,String,checked, unused => narrowName(rest,tag,SCon{Char.from_u32(byte),reversed}))

def nameUtf8(result: Result<&2,&2,UTF8.Error,String>) -> Result<&2,&2,Error,String>:
  match result:
    case Fail{_}: Fail{InvalidCertificate{}}
    case Done{value}: Done{value}

def encodedNameString(+tag: U32, bytes: List<&2,U32>) -> Result<&2,&2,Error,String>:
  match tag:
    case 12: nameUtf8(UTF8.decodeWith(UTF8.Preserve{},bytes))
    case 30: wideName(bytes,2,"")
    case 28: wideName(bytes,4,"")
    case _:
      checked = Bool.pick(Result<&2,&2,Error,Unit>,U32.is_eq(tag,19) || U32.is_eq(tag,20) || U32.is_eq(tag,22),Done{Unit{}},Fail{UnsupportedNameEncoding{tag}})
      Result.bind(&2,&2,Error,Unit,String,checked,unused => narrowName(bytes,tag,""))

def nameString(node: DER.Node) -> Result<&2,&2,Error,String>:
  match node:
    case DER.Node{DER.Tag{0,False{},tag},_,bytes}: encodedNameString(tag,bytes)
    case _: Fail{InvalidCertificate{}}

def nameSpace(+code: U32) -> Bool:
  U32.is_eq(code,32) || (U32.is_ge(code,9) && U32.is_le(code,13))

def nameLower(+code: U32) -> U32:
  Bool.pick(U32,U32.is_ge(code,65) && U32.is_le(code,90),(code + 32 : U32),code)

def pendingSpace(pending: Bool, reversed: String) -> String:
  match pending reversed:
    case _ SNil{}: ""
    case True{} reversed: SCon{Chr{32},reversed}
    case False{} reversed: reversed

def canonicalNameText(text: String, pending: Bool, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code},rest}:
      +space = nameSpace(code)
      canonicalNameText(rest,space,Bool.pick(String,space,reversed,SCon{Char.from_u32(nameLower(code)),pendingSpace(pending,reversed)}))

def numericName(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case +head <> rest: (U32.is_eq(head,32) || (U32.is_ge(head,48) && U32.is_le(head,57))) && numericName(rest)

def typedNameValue(+node: DER.Node, tag: U32, bytes: List<&2,U32>) -> Result<&2,&2,Error,NameValue>:
  match tag:
    case 18: Bool.pick(Result<&2,&2,Error,NameValue>,numericName(bytes),Done{EncodedNameValue{node}},Fail{InvalidCertificate{}})
    case 3: Result.bind(&2,&2,Error,DER.Bits,NameValue,decoded(DER.Bits,DER.bits(node)),unused => Done{EncodedNameValue{node}})
    case _: Result.bind(&2,&2,Error,String,NameValue,nameString(node), text => Done{TextNameValue{canonicalNameText(text,False{},"")}})

def nameValue(+node: DER.Node) -> Result<&2,&2,Error,NameValue>:
  match node:
    case DER.Node{DER.Tag{0,False{},tag},_,bytes}: typedNameValue(node,tag,bytes)
    case DER.Node{DER.Tag{0,True{},16},_,bytes}:
      Result.bind(&2,&2,Error,List<&2,DER.Node>,NameValue,decoded(List<&2,DER.Node>,DER.all(bytes)),unused => Done{EncodedNameValue{node}})
    case _: Fail{InvalidCertificate{}}

def nameAttribute(nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,NameAttribute>:
  match nodes:
    case DER.Node{DER.Tag{0,False{},6},_,+oid} <> value <> Nil{}:
      checked = Bool.pick(Result<&2,&2,Error,Unit>,oidGroups(oid,True{}) && Nat.is_gt(DER.length(oid,0n),0n),Done{Unit{}},Fail{InvalidCertificate{}})
      Result.bind(&2,&2,Error,Unit,NameAttribute,checked,unused =>
        Result.bind(&2,&2,Error,NameValue,NameAttribute,nameValue(value), text => Done{NameAttribute{oid,text}}))
    case _: Fail{InvalidCertificate{}}

def firstOrder(head: Cmp, tail: Cmp) -> Cmp:
  match head:
    case EQ{}: tail
    case order: order

def nameByteOrder(left: List<&2,U32>, right: List<&2,U32>) -> Cmp:
  match left right:
    case Nil{} Nil{}: EQ{}
    case Nil{} _ <> _: LT{}
    case _ <> _ Nil{}: GT{}
    case a <> xs b <> ys: firstOrder(U32.cmp(a,b),nameByteOrder(xs,ys))

def setOrder(order: Cmp) -> Result<&2,&2,Error,Unit>:
  match order:
    case GT{}: Fail{InvalidCertificate{}}
    case _: Done{Unit{}}

def nameAttributes(nodes: List<&2,DER.Node>, previous: List<&2,U32>, reversed: List<&2,NameAttribute>) -> Result<&2,&2,Error,List<&2,NameAttribute>>:
  match nodes:
    case Nil{}: Done{List.reverse(&2,NameAttribute,reversed)}
    case +head <> rest:
      +wire = DER.encoded(head)
      Result.bind(&2,&2,Error,Unit,List<&2,NameAttribute>,setOrder(nameByteOrder(previous,wire)),unused =>
        Result.bind(&2,&2,Error,List<&2,DER.Node>,List<&2,NameAttribute>,decoded(List<&2,DER.Node>,DER.sequence(head)), nodes =>
          Result.bind(&2,&2,Error,NameAttribute,List<&2,NameAttribute>,nameAttribute(nodes), attr => nameAttributes(rest,wire,attr <> reversed))))

def nonemptyRdn(nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,List<&2,NameAttribute>>:
  match nodes:
    case Nil{}: Fail{InvalidCertificate{}}
    case head <> rest: nameAttributes(head <> rest,Nil{},Nil{})

def relativeName(node: DER.Node) -> Result<&2,&2,Error,List<&2,NameAttribute>>:
  match node:
    case DER.Node{DER.Tag{0,True{},17},_,bytes}:
      Result.bind(&2,&2,Error,List<&2,DER.Node>,List<&2,NameAttribute>,decoded(List<&2,DER.Node>,DER.all(bytes)),nonemptyRdn)
    case _: Fail{InvalidCertificate{}}

def relativeNames(nodes: List<&2,DER.Node>, reversed: List<&2,List<&2,NameAttribute>>) -> Result<&2,&2,Error,DistinguishedName>:
  match nodes:
    case Nil{}: Done{DistinguishedName{List.reverse(&2,List<&2,NameAttribute>,reversed)}}
    case head <> rest:
      Result.bind(&2,&2,Error,List<&2,NameAttribute>,DistinguishedName,relativeName(head), value => relativeNames(rest,value <> reversed))

def distinguishedName(node: DER.Node) -> Result<&2,&2,Error,DistinguishedName>:
  Result.bind(&2,&2,Error,List<&2,DER.Node>,DistinguishedName,decoded(List<&2,DER.Node>,DER.sequence(node)), nodes => relativeNames(nodes,Nil{}))

def sameNameValue(left: NameValue, right: NameValue) -> Bool:
  match left right:
    case TextNameValue{x} TextNameValue{y}: String.eq(x,y)
    case EncodedNameValue{x} EncodedNameValue{y}: RSA.equal(DER.encoded(x),DER.encoded(y),0)
    case _ _: False{}

def sameAttribute(left: NameAttribute, right: NameAttribute) -> Bool:
  match left right:
    case NameAttribute{a,x} NameAttribute{b,y}: RSA.equal(a,b,0) && sameNameValue(x,y)

def removeAttribute(values: List<&2,NameAttribute>, +wanted: NameAttribute, +reversed: List<&2,NameAttribute>) -> Maybe<&2,List<&2,NameAttribute>>:
  match values:
    case Nil{}: None{}
    case +head <> +rest:
      Bool.pick(Unit -> Maybe<&2,List<&2,NameAttribute>>,sameAttribute(head,wanted),unused => Some{List.append(&2,NameAttribute,List.reverse(&2,NameAttribute,reversed),rest)},unused => removeAttribute(rest,wanted,head <> reversed))(Unit{})

def sameRdn(left: List<&2,NameAttribute>, right: Maybe<&2,List<&2,NameAttribute>>) -> Bool:
  match left right:
    case Nil{} Some{Nil{}}: True{}
    case head <> rest Some{values}: sameRdn(rest,removeAttribute(values,head,Nil{}))
    case _ _: False{}

def sameRdns(left: List<&2,List<&2,NameAttribute>>, right: List<&2,List<&2,NameAttribute>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: sameRdn(a,Some{b}) && sameRdns(xs,ys)
    case _ _: False{}

def sameName(left: DistinguishedName, right: DistinguishedName) -> Bool:
  match left right:
    case DistinguishedName{xs} DistinguishedName{ys}: sameRdns(xs,ys)

def certificateNameFields(nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,CertificateNames>:
  match nodes:
    case _ <> _ <> issuer <> _ <> subject <> _:
      Result.bind(&2,&2,Error,DistinguishedName,CertificateNames,distinguishedName(issuer), issuerName =>
        Result.bind(&2,&2,Error,DistinguishedName,CertificateNames,distinguishedName(subject), subjectName => Done{CertificateNames{issuerName,subjectName}}))
    case _: Fail{InvalidCertificate{}}

def certificateNames(certificate: Certificate) -> Result<&2,&2,Error,CertificateNames>:
  match certificate:
    case Certificate{tbs,_,_}: Result.bind(&2,&2,Error,List<&2,DER.Node>,CertificateNames,fields(tbs),certificateNameFields)

# A decoded path member carries the evidence reused at adjacent links. It is
# not an authenticated identity: hostname checks and path discovery are separate.
type PathCertificate is Data:
  PathCertificate{certificate: Certificate, issuer: DistinguishedName, subject: DistinguishedName, key: PublicKey, policy: Policy}

def pathSerial(nodes: List<&2,DER.Node>) -> Result<&2,&2,Error,Unit>:
  match nodes:
    case serial <> _ <> _ <> _ <> _ <> _ <> _:
      Result.bind(&2,&2,Error,List<&2,U32>,Unit,decoded(List<&2,U32>,DER.unsigned(serial)), bytes =>
        Bool.pick(Result<&2,&2,Error,Unit>,Bool.not(Big.isZero(Big.fromBigEndian(bytes))),Done{Unit{}},Fail{InvalidCertificate{}}))
    case _: Fail{InvalidCertificate{}}

def criticalSubjectName(values: List<&2,Extension>) -> Bool:
  match values:
    case Nil{}: False{}
    case Extension{85 <> 29 <> 17 <> Nil{},True{},_} <> _: True{}
    case _ <> rest: criticalSubjectName(rest)

def nameProfile(names: CertificateNames, values: List<&2,Extension>) -> Result<&2,&2,Error,Unit>:
  match names:
    case CertificateNames{DistinguishedName{Nil{}},_}: Fail{InvalidCertificate{}}
    case CertificateNames{_,DistinguishedName{Nil{}}}:
      Bool.pick(Result<&2,&2,Error,Unit>,criticalSubjectName(values),Done{Unit{}},Fail{InvalidCertificate{}})
    case _: Done{Unit{}}

def usageProfile(policy: Policy) -> Result<&2,&2,Error,Unit>:
  match policy:
    case Policy{BasicConstraints{False{},_},Some{KeyUsage{_,_,_,_,_,True{},_,_,_}},_}: Fail{InvalidKeyUsage{}}
    case _: Done{Unit{}}

def pathMember(+certificate: Certificate, names: CertificateNames, key: PublicKey, policy: Policy) -> PathCertificate:
  match names:
    case CertificateNames{issuer,subject}: PathCertificate{certificate,issuer,subject,key,policy}

def preparePathCertificate(+now: W.U64, +certificate: Certificate) -> Result<&2,&2,Error,PathCertificate>:
  match certificate:
    case Certificate{+tbs,algorithm,signature}:
      Result.bind(&2,&2,Error,List<&2,DER.Node>,PathCertificate,fields(tbs), nodes =>
        Result.bind(&2,&2,Error,Unit,PathCertificate,pathSerial(nodes),unused =>
          Result.bind(&2,&2,Error,Validity,PathCertificate,validity(certificate), period =>
            Result.bind(&2,&2,Error,Unit,PathCertificate,validAt(now,period),unused =>
              Result.bind(&2,&2,Error,List<&2,Extension>,PathCertificate,extensions(certificate), +values =>
                Result.bind(&2,&2,Error,Policy,PathCertificate,policyExtensions(values,Policy{BasicConstraints{False{},None{}},None{},None{}}), +policy =>
                  Result.bind(&2,&2,Error,Unit,PathCertificate,usageProfile(policy),unused =>
                    Result.bind(&2,&2,Error,CertificateNames,PathCertificate,certificateNames(certificate), +names =>
                      Result.bind(&2,&2,Error,Unit,PathCertificate,nameProfile(names,values),unused =>
                        Result.bind(&2,&2,Error,PublicKey,PathCertificate,publicKey(certificate), key =>
                          Done{pathMember(certificate,names,key,policy)}))))))))))

def sameCertificate(left: Certificate, right: Certificate) -> Bool:
  match left right:
    case Certificate{a,b,c} Certificate{d,e,f}:
      RSA.equal(DER.encoded(a),DER.encoded(d),0) && RSA.equal(DER.encoded(b),DER.encoded(e),0) && RSA.equal(c,f,0)

def issuerLink(child: PathCertificate, parent: PathCertificate, intermediatesBelow: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  match child parent:
    case PathCertificate{certificate,issuer,_,_,_} PathCertificate{_,_,subject,key,policy}:
      Result.bind(&2,&2,Error,Unit,Unit,checkIssuerPolicy(policy,intermediatesBelow),unused =>
        Result.bind(&2,&2,Error,Unit,Unit,Bool.pick(Result<&2,&2,Error,Unit>,sameName(issuer,subject),Done{Unit{}},Fail{IssuerMismatch{}}),unused =>
          verifySignature(key,certificate)))

def belowParent(parent: PathCertificate, +count: Big.BigNat) -> Big.BigNat:
  match parent:
    case PathCertificate{_,issuer,subject,_,_}: Bool.pick(Big.BigNat,sameName(issuer,subject),count,Big.add(count,Big.one()))

# The separately supplied anchor is trusted configuration, never a certificate
# accepted merely because the peer sent it. Exact direct trust skips self-signing
# and CA requirements, but still checks the target's time/purpose/encoding.
def pathToAnchor(remaining: List<&2,Certificate>, +now: W.U64, +child: PathCertificate, +anchor: PathCertificate, +count: Big.BigNat) -> Result<&2,&2,Error,Unit>:
  match remaining:
    case Nil{}:
      match child anchor:
        case PathCertificate{+certificate,issuer,subject,key,policy} PathCertificate{+trusted,ai,as,ak,ap}:
          Bool.pick(Unit -> Result<&2,&2,Error,Unit>,sameCertificate(certificate,trusted),unused => Done{Unit{}},unused => issuerLink(PathCertificate{certificate,issuer,subject,key,policy},PathCertificate{trusted,ai,as,ak,ap},count))(Unit{})
    case head <> rest:
      Result.bind(&2,&2,Error,PathCertificate,Unit,preparePathCertificate(now,head), +parent =>
        Result.bind(&2,&2,Error,Unit,Unit,issuerLink(child,parent,count),unused =>
          pathToAnchor(rest,now,parent,anchor,belowParent(parent,count))))

def serverPath(+now: W.U64, intermediates: List<&2,Certificate>, anchor: PathCertificate, leaf: PathCertificate) -> Result<&2,&2,Error,PublicKey>:
  match leaf:
    case PathCertificate{certificate,issuer,subject,+key,+policy}:
      Result.bind(&2,&2,Error,Unit,PublicKey,checkServerPolicy(policy),unused =>
        Result.bind(&2,&2,Error,Unit,PublicKey,pathToAnchor(intermediates,now,PathCertificate{certificate,issuer,subject,key,policy},anchor,Big.zero()),unused => Done{key}))

# Validate one candidate path ordered leaf -> intermediates -> configured anchor.
# This is not path discovery, hostname authorization, revocation or a complete
# policy/name-constraint implementation; unsupported constraints fail closed.
def verifyPath(+now: W.U64, leaf: Certificate, intermediates: List<&2,Certificate>, trusted: Certificate) -> Result<&2,&2,Error,PublicKey>:
  Result.bind(&2,&2,Error,PathCertificate,PublicKey,preparePathCertificate(now,trusted), anchor =>
    Result.bind(&2,&2,Error,PathCertificate,PublicKey,preparePathCertificate(now,leaf), target => serverPath(now,intermediates,anchor,target)))

# Discovery ignores unusable *candidates*, not failures on the selected path.
# The target is checked separately and its validation errors are preserved.
def retainPrepared(result: Result<&2,&2,Error,PathCertificate>, reversed: List<&2,PathCertificate>) -> List<&2,PathCertificate>:
  match result:
    case Fail{_}: reversed
    case Done{value}: value <> reversed

def prepareCandidates(values: List<&2,Certificate>, +now: W.U64, reversed: List<&2,PathCertificate>) -> List<&2,PathCertificate>:
  match values:
    case Nil{}: List.reverse(&2,PathCertificate,reversed)
    case head <> rest: prepareCandidates(rest,now,retainPrepared(preparePathCertificate(now,head),reversed))

def linkAccepted(result: Result<&2,&2,Error,Unit>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{Unit{}}: True{}

def reachesAnchor(+child: PathCertificate, +anchor: PathCertificate, count: Big.BigNat) -> Bool:
  match child anchor:
    case PathCertificate{certificate,_,_,_,_} PathCertificate{trusted,_,_,_,_}:
      Bool.pick(Unit -> Bool,sameCertificate(certificate,trusted),unit => True{},unit => linkAccepted(issuerLink(child,anchor,count)))(Unit{})

def memberCertificate(member: PathCertificate) -> Certificate:
  match member:
    case PathCertificate{certificate,_,_,_,_}: certificate

def alreadyVisited(values: List<&2,Certificate>, +certificate: Certificate) -> Bool:
  match values:
    case Nil{}: False{}
    case head <> rest: sameCertificate(head,certificate) || alreadyVisited(rest,certificate)

type PathSearch is Data:
  PathSearch{child: PathCertificate, count: Big.BigNat, visited: List<&2,Certificate>}

def trustedCandidate(anchors: List<&2,PathCertificate>, +child: PathCertificate, +count: Big.BigNat) -> Bool:
  match anchors:
    case Nil{}: False{}
    case anchor <> rest:
      Bool.pick(Unit -> Bool,reachesAnchor(child,anchor,count),unit => True{},unit => trustedCandidate(rest,child,count))(Unit{})

# New branches precede deferred siblings, so the search is depth-first without
# retaining an exponentially growing breadth-first frontier. Every branch is a
# simple path: a peer certificate cannot occur twice in its visited list.
def extendPeers(peers: List<&2,PathCertificate>, +child: PathCertificate, +count: Big.BigNat, +visited: List<&2,Certificate>, pending: List<&2,PathSearch>) -> List<&2,PathSearch>:
  match peers:
    case Nil{}: pending
    case +parent <> rest:
      +tail = extendPeers(rest,child,count,visited,pending)
      Bool.pick(Unit -> List<&2,PathSearch>,alreadyVisited(visited,memberCertificate(parent)),unit => tail,unit =>
        Bool.pick(Unit -> List<&2,PathSearch>,linkAccepted(issuerLink(child,parent,count)),unit =>
          PathSearch{parent,belowParent(parent,count),memberCertificate(parent) <> visited} <> tail,unit => tail)(Unit{}))(Unit{})

# The caller supplies a work bound for ambiguous/untrusted peer graphs. Limit
# exhaustion is explicit and never turns an incomplete search into acceptance.
def searchPath(steps: Nat, pending: List<&2,PathSearch>, +peers: List<&2,PathCertificate>, +anchors: List<&2,PathCertificate>) -> Result<&2,&2,Error,Unit>:
  match steps pending:
    case _ Nil{}: Fail{NoTrustedPath{}}
    case 0n _ <> _: Fail{PathSearchLimit{}}
    case 1n+rest PathSearch{+child,+count,visited} <> deferred:
      Bool.pick(Unit -> Result<&2,&2,Error,Unit>,trustedCandidate(anchors,child,count),unit => Done{Unit{}},unit =>
        searchPath(rest,extendPeers(peers,child,count,visited,deferred),peers,anchors))(Unit{})

def discoverServer(steps: Nat, anchors: List<&2,PathCertificate>, peers: List<&2,PathCertificate>, +leaf: PathCertificate) -> Result<&2,&2,Error,PublicKey>:
  match leaf:
    case PathCertificate{certificate,_,_,+key,policy}:
      Result.bind(&2,&2,Error,Unit,PublicKey,checkServerPolicy(policy),unit =>
        Result.bind(&2,&2,Error,Unit,PublicKey,searchPath(steps,PathSearch{leaf,Big.zero(),certificate <> Nil{}} <> Nil{},peers,anchors),unit => Done{key}))

# Configured anchors are explicit trust. Peer certificates only supply possible
# intermediate links; even a self-signed peer root cannot grant itself trust.
# Hostname authorization remains a separate requirement for TLS connections.
def verifyChain(steps: Nat, +now: W.U64, leaf: Certificate, peers: List<&2,Certificate>, anchors: List<&2,Certificate>) -> Result<&2,&2,Error,PublicKey>:
  match anchors:
    case Nil{}: Fail{NoTrustedPath{}}
    case head <> rest:
      Result.bind(&2,&2,Error,PathCertificate,PublicKey,preparePathCertificate(now,leaf), target =>
        discoverServer(steps,prepareCandidates(head <> rest,now,Nil{}),prepareCandidates(peers,now,Nil{}),target))
