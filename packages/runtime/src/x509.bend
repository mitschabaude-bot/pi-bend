import Base
import ./der.bend as DER
import ./rsa-sha256.bend as RSA
import ./calendar.bend as Calendar
import ./u64.bend as W
import ./big-nat.bend as Big

# Parsed wire evidence, not an authenticated identity. Trust, validity, names,
# constraints and extensions must be checked before a TLS connection is usable.
type Error is Data:
  Encoding{cause: DER.Error}
  InvalidCertificate{}
  UnsupportedAlgorithm{}
  Signature{cause: RSA.Error}
  InvalidTime{}
  NotYetValid{}
  Expired{}
  DuplicateExtension{oid: List<&2, U32>}

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
        Done{BasicConstraints{True{},Some{RSA.number(bytes,Big.zero())}}})
    case _: Fail{InvalidCertificate{}}

def basicConstraints(extension: Extension) -> Result<&2, &2, Error, BasicConstraints>:
  match extension:
    case Extension{85 <> 29 <> 19 <> Nil{},_,value}:
      Result.bind(&2, &2, Error, DER.Node, BasicConstraints, decoded(DER.Node,DER.one(value)), node =>
        Result.bind(&2, &2, Error, List<&2, DER.Node>, BasicConstraints, decoded(List<&2, DER.Node>,DER.sequence(node)), basicFields))
    case _: Fail{InvalidCertificate{}}
