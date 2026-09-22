import Base
import ./x509.bend as X509
import ./pem.bend as PEM
import ./bounded.bend as File
import ./utf8.bend as UTF8
import ./url.bend as URL
import ./string.bend as Split
import ./rsa-sha256.bend as RSA

# Configured certificates are distinct from peer evidence. This layer parses
# explicit configuration; certificate policy and path validity are checked at
# connection time. It does not silently choose an OS or bundled trust store.
type Error is Data:
  Read{cause: File.FileError<UTF8.Error>}
  Text{cause: PEM.Error}
  Certificate{cause: X509.Error}
  UnsupportedLabel{label: String}
  EmptyBundle{}

def certificate(result: Result<&2,&2,X509.Error,X509.Certificate>) -> Result<&2,&2,Error,X509.Certificate>:
  match result:
    case Fail{cause}: Fail{Certificate{cause}}
    case Done{value}: Done{value}

def labelled(allowed: Bool, label: String, bytes: List<&2,U32>) -> Result<&2,&2,Error,X509.Certificate>:
  match allowed:
    case False{}: Fail{UnsupportedLabel{label}}
    case True{}: certificate(X509.parse(bytes))

def blocks(values: List<&2,PEM.Block>, reversed: List<&2,X509.Certificate>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match values reversed:
    case Nil{} Nil{}: Fail{EmptyBundle{}}
    case Nil{} values: Done{List.reverse(&2,X509.Certificate,values)}
    case PEM.Block{+label,bytes} <> rest previous:
      Result.bind(&2,&2,Error,X509.Certificate,List<&2,X509.Certificate>,labelled(String.eq(label,"CERTIFICATE"),label,bytes), value => blocks(rest,value <> previous))

def parsed(result: Result<&2,&2,PEM.Error,List<&2,PEM.Block>>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match result:
    case Fail{cause}: Fail{Text{cause}}
    case Done{values}: blocks(values,Nil{})

def parse(text: String) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  parsed(PEM.decode(text))

def loaded(result: Result<&2,&2,File.FileError<UTF8.Error>,String>) -> Result<&2,&2,Error,List<&2,X509.Certificate>>:
  match result:
    case Fail{cause}: Fail{Read{cause}}
    case Done{text}: parse(text)

# Read limits apply to the entire source file, including comments and newlines.
# bounded-file closes the descriptor before invoking any certificate decoder.
def load(path: String, byteLimit: Nat) -> IO(Result<&2,&2,Error,List<&2,X509.Certificate>>):
  do IO<Result<&2,&2,Error,List<&2,X509.Certificate>>>:
    result : Result<&2,&2,File.FileError<UTF8.Error>,String> <- File.readWith(~UTF8.Error,~UTF8.decodeStrict,path,4096,byteLimit)
    return loaded(result)

# Explicit SAN-only HTTPS identity policy. It does not select a platform policy
# or validate the certificate chain. Reference DNS names must already be ASCII
# A-labels from URL normalization; an IP reference matches only an IP SAN.
type IdentityError is Data:
  InvalidReference{}
  InvalidIdentityCertificate{cause: X509.Error}
  MissingSubjectAltName{}
  IdentityMismatch{}

def asciiLower(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, rest}:
      SCon{Chr{Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 90), (code + 32 : U32), code)}, asciiLower(rest)}

def alphanumeric(+code: U32) -> Bool:
  (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57))

def labelTail(text: String, remaining: Nat, lastDash: Bool) -> Bool:
  match text remaining:
    case SNil{} _: Bool.not(lastDash)
    case _ 0n: False{}
    case SCon{Chr{+code}, rest} 1n+remaining:
      (alphanumeric(code) || U32.is_eq(code, 45)) && labelTail(rest, remaining, U32.is_eq(code, 45))

def validLabel(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code}, rest}: alphanumeric(code) && labelTail(rest, 62n, False{})

def validLabels(labels: List<&2, String>) -> Bool:
  match labels:
    case Nil{}: True{}
    case head <> rest: validLabel(head) && validLabels(rest)

def withoutRoot(reversed: List<&2, String>) -> List<&2, String>:
  match reversed:
    case SNil{} <> rest: List.reverse(&2, String, rest)
    case values: List.reverse(&2, String, values)

def dnsLabels(text: String) -> List<&2, String>:
  withoutRoot(List.reverse(&2, String, Split.split(asciiLower(text), '.')))

def sameLabels(left: List<&2, String>, right: List<&2, String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: String.eq(x, y) && sameLabels(xs, ys)
    case _ _: False{}

# The wildcard consumes exactly one reference label; suffix comparison has no
# wildcard rule. Partial wildcards and additional wildcard labels never match.
def matchLabels(reference: List<&2, String>, presented: List<&2, String>) -> Bool:
  match reference presented:
    case +first <> +rest +pattern <> +suffix:
      validLabel(first) && validLabels(rest) && validLabels(suffix) &&
      ((String.eq(pattern, "*") && Bool.not(List.is_empty(&2, String, suffix)) && sameLabels(rest, suffix)) ||
       (validLabel(pattern) && String.eq(first, pattern) && sameLabels(rest, suffix)))
    case _ _: False{}

def nameSize(labels: List<&2, String>, size: Nat) -> Nat:
  match labels:
    case Nil{}: size
    case head <> rest: nameSize(rest, (size + 1n + String.length(head) : Nat))

def boundedMatch(+reference: List<&2, String>, +presented: List<&2, String>) -> Bool:
  Nat.is_le(nameSize(reference, 0n), 254n) && Nat.is_le(nameSize(presented, 0n), 254n) && matchLabels(reference, presented)

def matchDNS(reference: String, presented: String) -> Bool:
  boundedMatch(dnsLabels(reference), dnsLabels(presented))

def wordBytes(+word: U32, rest: List<&2, U32>) -> List<&2, U32>:
  (word / 16777216 : U32) <> (word / 65536 % 256 : U32) <> (word / 256 % 256 : U32) <> (word % 256 : U32) <> rest

def matchName(host: URL.Host, name: X509.GeneralName) -> Bool:
  match host name:
    case URL.Domain{reference} X509.DnsName{presented}: matchDNS(reference, presented)
    case URL.IPv4{URL.Address{value}} X509.IpAddress{bytes}: RSA.equal(wordBytes(value, Nil{}), bytes, 0)
    case URL.IPv6{URL.Ipv6Address{a, b, c, d}} X509.IpAddress{bytes}:
      RSA.equal(wordBytes(a, wordBytes(b, wordBytes(c, wordBytes(d, Nil{})))), bytes, 0)
    case _ _: False{}

def matchNames(names: List<&2, X509.GeneralName>, +host: URL.Host) -> Bool:
  match names:
    case Nil{}: False{}
    case head <> rest: matchName(host, head) || matchNames(rest, host)

def validReference(host: URL.Host) -> Bool:
  match host:
    case URL.Domain{+name}: matchDNS(name, name)
    case URL.IPv4{_}: True{}
    case URL.IPv6{_}: True{}
    case _: False{}

def identityNames(host: URL.Host, result: Result<&2, &2, X509.Error, List<&2, X509.GeneralName>>) -> Result<&2, &2, IdentityError, Unit>:
  match result:
    case Fail{cause}: Fail{InvalidIdentityCertificate{cause}}
    case Done{names}: Bool.pick(Result<&2, &2, IdentityError, Unit>, matchNames(names, host), Done{Unit{}}, Fail{IdentityMismatch{}})

def identityExtension(values: List<&2, X509.Extension>, +host: URL.Host) -> Result<&2, &2, IdentityError, Unit>:
  match values:
    case Nil{}: Fail{MissingSubjectAltName{}}
    case X509.Extension{85 <> 29 <> 17 <> Nil{}, critical, bytes} <> _:
      identityNames(host, X509.subjectAltNames(X509.Extension{85 <> 29 <> 17 <> Nil{}, critical, bytes}))
    case _ <> rest: identityExtension(rest, host)

def identityExtensions(valid: Bool, host: URL.Host, result: Result<&2, &2, X509.Error, List<&2, X509.Extension>>) -> Result<&2, &2, IdentityError, Unit>:
  match valid result:
    case False{} _: Fail{InvalidReference{}}
    case True{} Fail{cause}: Fail{InvalidIdentityCertificate{cause}}
    case True{} Done{values}: identityExtension(values, host)

def checkSAN(+host: URL.Host, leaf: X509.Certificate) -> Result<&2, &2, IdentityError, Unit>:
  identityExtensions(validReference(host), host, X509.extensions(leaf))
