import Base
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/der.bend as DER
import ../packages/runtime/src/rsa-sha256.bend as RSA
import ../packages/runtime/src/ecdsa.bend as EC
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/prime-field.bend as Field
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/test/utf8-runner.bend as Decimal

def error(cause: X509.Error) -> String:
  match cause:
    case X509.Encoding{_}: "encoding"
    case X509.InvalidCertificate{}: "certificate"
    case X509.UnsupportedAlgorithm{}: "algorithm"
    case X509.Signature{_}: "signature"
    case X509.Curve{_}: "curve"
    case X509.InvalidTime{}: "time"
    case X509.NotYetValid{}: "early"
    case X509.Expired{}: "expired"
    case X509.DuplicateExtension{_}: "duplicate"
    case X509.UnsupportedCriticalExtension{_}: "critical"
    case X509.NotCertificateAuthority{}: "ca"
    case X509.InvalidKeyUsage{}: "usage"
    case X509.InvalidPurpose{}: "purpose"
    case X509.PathLengthExceeded{}: "path"
    case X509.UnsupportedNameEncoding{_}: "name-encoding"
    case X509.UnsupportedConstraint{_}: "constraint"
    case X509.IssuerMismatch{}: "issuer"
    case X509.NoTrustedPath{}: "untrusted"
    case X509.PathSearchLimit{}: "search-limit"
    case X509.InvalidReferenceIdentity{}: "reference"
    case X509.MissingSubjectAltName{}: "missing-san"
    case X509.IdentityMismatch{}: "identity"

def parsed(result: Result<&2, &2, X509.Error, X509.Certificate>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.Certificate{tbs, algorithm, signature}}:
      Bytes.show(DER.encoded(tbs)) ++ "|" ++ Bytes.show(DER.encoded(algorithm)) ++ "|" ++ Bytes.show(signature)

def publicKey(result: Result<&2, &2, X509.Error, X509.PublicKey>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.Rsa{RSA.PublicKey{modulus, exponent, bytes, bits}}}:
      Big.toDecimal(modulus) ++ "|" ++ Bytes.show(exponent) ++ "|" ++ Nat.show(bytes) ++ "|" ++ Nat.show(bits)

    case Done{X509.Ec{EC.P256{},EC.Point{x,y}}}: "p256:" ++ Bytes.show(DER.append(Big.toBigEndian(32n,Field.toBig(x)),Big.toBigEndian(32n,Field.toBig(y))))
    case Done{X509.Ec{EC.P384{},EC.Point{x,y}}}: "p384:" ++ Bytes.show(DER.append(Big.toBigEndian(48n,Field.toBig(x)),Big.toBigEndian(48n,Field.toBig(y))))

def verified(result: Result<&2, &2, X509.Error, Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def verify(issuer: List<&2, U32>, certificate: List<&2, U32>) -> Result<&2, &2, X509.Error, Unit>:
  Result.bind(&2, &2, X509.Error, X509.Certificate, Unit, X509.parse(issuer), issuerCertificate =>
    Result.bind(&2, &2, X509.Error, X509.PublicKey, Unit, X509.publicKey(issuerCertificate), key =>
      Result.bind(&2, &2, X509.Error, X509.Certificate, Unit, X509.parse(certificate), subject => X509.verifySignature(key, subject))))

def words(value: W.U64) -> String:
  match value:
    case W.U64{high,low}: U32.show(high) ++ "," ++ U32.show(low)

def instant(result: Result<&2, &2, X509.Error, W.U64>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: words(value)

def period(result: Result<&2, &2, X509.Error, X509.Validity>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.Validity{start,end}}: words(start) ++ "|" ++ words(end)

def at(high: String, low: String, certificate: List<&2, U32>) -> Result<&2, &2, X509.Error, Unit>:
  Result.bind(&2, &2, X509.Error, X509.Certificate, Unit, X509.parse(certificate), parsedCertificate =>
    Result.bind(&2, &2, X509.Error, X509.Validity, Unit, X509.validity(parsedCertificate), value => X509.validAt(W.U64{Decimal.decimal(high,0),Decimal.decimal(low,0)},value)))

def extensionList(values: List<&2, X509.Extension>, reverse: String) -> String:
  match values:
    case Nil{}: String.reverse(reverse)
    case X509.Extension{oid,critical,value} <> rest:
      text = "|" ++ Bytes.show(oid) ++ ":" ++ Bool.pick(String,critical,"1","0") ++ ":" ++ Bytes.show(value)
      extensionList(rest,String.reverse(text) ++ reverse)

def extensionResult(result: Result<&2, &2, X509.Error, List<&2, X509.Extension>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{values}: "extensions" ++ extensionList(values,"")

def pathLength(value: Maybe<&2, Big.BigNat>) -> String:
  match value:
    case None{}: "none"
    case Some{value}: Big.toDecimal(value)

def basic(result: Result<&2, &2, X509.Error, X509.BasicConstraints>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.BasicConstraints{ca,path}}: Bool.pick(String,ca,"ca:","leaf:") ++ pathLength(path)

def usage(result: Result<&2, &2, X509.Error, X509.KeyUsage>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.KeyUsage{a,b,c,d,e,f,g,h,i}}:
      U32.show((Bool.to_u32(a) + Bool.to_u32(b)*2 + Bool.to_u32(c)*4 + Bool.to_u32(d)*8 + Bool.to_u32(e)*16 + Bool.to_u32(f)*32 + Bool.to_u32(g)*64 + Bool.to_u32(h)*128 + Bool.to_u32(i)*256 : U32))

def purposeBytes(values: List<&2, List<&2, U32>>, reverse: String) -> String:
  match values:
    case Nil{}: String.reverse(reverse)
    case value <> rest: purposeBytes(rest,String.reverse(Bytes.show(value)) ++ "|" ++ reverse)

def purposeResult(result: Result<&2, &2, X509.Error, List<&2, List<&2, U32>>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{values}: "purposes" ++ purposeBytes(values,"")

def textBytes(text: String, reverse: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SNil{}: List.reverse(&2,U32,reverse)
    case SCon{Chr{byte},rest}: textBytes(rest,byte <> reverse)

def generalName(value: X509.GeneralName) -> String:
  match value:
    case X509.DnsName{text}: "dns:" ++ Bytes.show(textBytes(text,Nil{}))
    case X509.IpAddress{bytes}: "ip:" ++ Bytes.show(bytes)
    case X509.Mailbox{text}: "mail:" ++ Bytes.show(textBytes(text,Nil{}))
    case X509.Uri{text}: "uri:" ++ Bytes.show(textBytes(text,Nil{}))
    case X509.RegisteredId{oid}: "oid:" ++ Bytes.show(oid)
    case X509.StructuredName{node}: "structured:" ++ Bytes.show(DER.encoded(node))

def nameList(values: List<&2,X509.GeneralName>, reverse: String) -> String:
  match values:
    case Nil{}: String.reverse(reverse)
    case head <> tail: nameList(tail,String.reverse(generalName(head)) ++ "|" ++ reverse)

def names(result: Result<&2,&2,X509.Error,List<&2,X509.GeneralName>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{values}: "names" ++ nameList(values,"")

def policy(bytes: List<&2,U32>) -> Result<&2,&2,X509.Error,X509.Policy>:
  Result.bind(&2,&2,X509.Error,X509.Certificate,X509.Policy,X509.parse(bytes),X509.certificatePolicy)

def issuerPolicy(count: Maybe<&2,Big.BigNat>, result: Result<&2,&2,X509.Error,X509.Policy>) -> String:
  match count result:
    case None{} _: "count"
    case _ Fail{cause}: error(cause)
    case Some{value} Done{state}: verified(X509.checkIssuerPolicy(state,value))

def nameValue(bytes: List<&2,U32>) -> Result<&2,&2,X509.Error,X509.DistinguishedName>:
  Result.bind(&2,&2,X509.Error,DER.Node,X509.DistinguishedName,X509.decoded(DER.Node,DER.one(bytes)),X509.distinguishedName)

def compared(result: Result<&2,&2,X509.Error,Bool>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{equal}: Bool.pick(String,equal,"same","different")

def compareNames(left: List<&2,U32>, right: List<&2,U32>) -> Result<&2,&2,X509.Error,Bool>:
  Result.bind(&2,&2,X509.Error,X509.DistinguishedName,Bool,nameValue(left), a =>
    Result.bind(&2,&2,X509.Error,X509.DistinguishedName,Bool,nameValue(right), b => Done{X509.sameName(a,b)}))

def selfIssued(result: Result<&2,&2,X509.Error,X509.CertificateNames>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.CertificateNames{issuer,subject}}: Bool.pick(String,X509.sameName(issuer,subject),"same","different")

def pathCertificates(values: List<&2,String>, reversed: List<&2,X509.Certificate>) -> Result<&2,&2,X509.Error,List<&2,X509.Certificate>>:
  match values:
    case Nil{}: Done{List.reverse(&2,X509.Certificate,reversed)}
    case SNil{} <> rest: pathCertificates(rest,reversed)
    case head <> rest:
      Result.bind(&2,&2,X509.Error,X509.Certificate,List<&2,X509.Certificate>,X509.parse(Bytes.bytes(head)), parsedCert => pathCertificates(rest,parsedCert <> reversed))

def candidatePath(now: W.U64, trusted: List<&2,U32>, leaf: List<&2,U32>, intermediates: List<&2,String>) -> Result<&2,&2,X509.Error,Unit>:
  Result.bind(&2,&2,X509.Error,X509.Certificate,Unit,X509.parse(trusted), anchor =>
    Result.bind(&2,&2,X509.Error,X509.Certificate,Unit,X509.parse(leaf), target =>
      Result.bind(&2,&2,X509.Error,List<&2,X509.Certificate>,Unit,pathCertificates(intermediates,Nil{}), chain =>
        Result.bind(&2,&2,X509.Error,X509.PublicKey,Unit,X509.verifyPath(now,target,chain,anchor),unused => Done{Unit{}}))))

def discoverPath(steps: Nat, now: W.U64, leaf: List<&2,U32>, peers: List<&2,String>, anchors: List<&2,String>) -> Result<&2,&2,X509.Error,Unit>:
  Result.bind(&2,&2,X509.Error,X509.Certificate,Unit,X509.parse(leaf), target =>
    Result.bind(&2,&2,X509.Error,List<&2,X509.Certificate>,Unit,pathCertificates(peers,Nil{}), chain =>
      Result.bind(&2,&2,X509.Error,List<&2,X509.Certificate>,Unit,pathCertificates(anchors,Nil{}), trusted =>
        Result.bind(&2,&2,X509.Error,X509.PublicKey,Unit,X509.verifyChain(steps,now,target,chain,trusted),unused => Done{Unit{}}))))

def run(parts: List<&2, String>) -> String:
  match parts:
    case "discover" <> high <> low <> leaf <> peers <> anchors <> Nil{}: verified(discoverPath(1024n,W.U64{Decimal.decimal(high,0),Decimal.decimal(low,0)},Bytes.bytes(leaf),Split.split(peers,'|'),Split.split(anchors,'|')))
    case "limited" <> steps <> high <> low <> leaf <> peers <> anchors <> Nil{}: verified(discoverPath(U32.to_nat(Decimal.decimal(steps,0)),W.U64{Decimal.decimal(high,0),Decimal.decimal(low,0)},Bytes.bytes(leaf),Split.split(peers,'|'),Split.split(anchors,'|')))
    case "chain" <> high <> low <> trusted <> leaf <> intermediates: verified(candidatePath(W.U64{Decimal.decimal(high,0),Decimal.decimal(low,0)},Bytes.bytes(trusted),Bytes.bytes(leaf),intermediates))
    case "dn" <> left <> right <> Nil{}: compared(compareNames(Bytes.bytes(left),Bytes.bytes(right)))
    case "self" <> cert <> Nil{}: selfIssued(Result.bind(&2,&2,X509.Error,X509.Certificate,X509.CertificateNames,X509.parse(Bytes.bytes(cert)),X509.certificateNames))
    case "server" <> bytes <> Nil{}: verified(Result.bind(&2,&2,X509.Error,X509.Policy,Unit,policy(Bytes.bytes(bytes)),X509.checkServerPolicy))
    case "issuer" <> count <> bytes <> Nil{}: issuerPolicy(Big.fromDecimal(count),policy(Bytes.bytes(bytes)))
    case "san" <> bytes <> Nil{}: names(X509.subjectAltNames(X509.Extension{85 <> 29 <> 17 <> Nil{},False{},Bytes.bytes(bytes)}))
    case "ku" <> bytes <> Nil{}: usage(X509.keyUsage(X509.Extension{85 <> 29 <> 15 <> Nil{},False{},Bytes.bytes(bytes)}))
    case "eku" <> bytes <> Nil{}: purposeResult(X509.extendedKeyUsage(X509.Extension{85 <> 29 <> 37 <> Nil{},False{},Bytes.bytes(bytes)}))
    case "ex" <> bytes <> Nil{}: extensionResult(Result.bind(&2, &2, X509.Error, X509.Certificate, List<&2, X509.Extension>, X509.parse(Bytes.bytes(bytes)), X509.extensions))
    case "basic" <> bytes <> Nil{}: basic(X509.basicConstraints(X509.Extension{85 <> 29 <> 19 <> Nil{},False{},Bytes.bytes(bytes)}))
    case "t" <> bytes <> Nil{}: instant(Result.bind(&2, &2, X509.Error, DER.Node, W.U64, X509.decoded(DER.Node, DER.one(Bytes.bytes(bytes))), X509.time))
    case "range" <> bytes <> Nil{}:
      period(Result.bind(&2, &2, X509.Error, DER.Node, X509.Validity, X509.decoded(DER.Node, DER.one(Bytes.bytes(bytes))), root =>
        Result.bind(&2, &2, X509.Error, List<&2, DER.Node>, X509.Validity, X509.decoded(List<&2, DER.Node>, DER.sequence(root)), X509.validityTimes)))
    case "a" <> bytes <> high <> low <> Nil{}: verified(at(high,low,Bytes.bytes(bytes)))
    case "p" <> bytes <> Nil{}: parsed(X509.parse(Bytes.bytes(bytes)))
    case "k" <> bytes <> Nil{}: publicKey(Result.bind(&2, &2, X509.Error, X509.Certificate, X509.PublicKey, X509.parse(Bytes.bytes(bytes)), X509.publicKey))
    case "v" <> issuer <> certificate <> Nil{}: verified(verify(Bytes.bytes(issuer), Bytes.bytes(certificate)))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head, ':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
