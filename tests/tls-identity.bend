import Base
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/x509.bend as X
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes
import ./x509.bend as CertTest
import ../packages/runtime/src/u64.bend as W

def show(result: Result<&2, &2, X.Error, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{X.InvalidReferenceIdentity{}}: "reference"
    case Fail{X.MissingSubjectAltName{}}: "missing"
    case Fail{X.IdentityMismatch{}}: "mismatch"
    case Fail{X.NoTrustedPath{}}: "untrusted"
    case Fail{X.Expired{}}: "expired"
    case Fail{cause}: CertTest.error(cause)

def checked(host: URL.Host, result: Result<&2, &2, X.Error, X.Certificate>) -> String:
  match result:
    case Fail{_}: "parse"
    case Done{leaf}: show(Trust.checkSAN(host, leaf))

def ipv4(certificate: String, result: Result<&2, &2, URL.AddressError, URL.Address>) -> String:
  match result:
    case Fail{_}: "address"
    case Done{address}: checked(URL.IPv4{address}, X.parse(Bytes.bytes(certificate)))

def ipv6(certificate: String, result: Result<&2, &2, URL.Ipv6AddressError, URL.Ipv6Address>) -> String:
  match result:
    case Fail{_}: "address"
    case Done{address}: checked(URL.IPv6{address}, X.parse(Bytes.bytes(certificate)))

def trusted(reference: String, anchor: String, leaf: String) -> String:
  show(Result.bind(&2, &2, X.Error, List<&2, X.Certificate>, Unit, CertTest.pathCertificates(anchor <> Nil{}, Nil{}), anchors =>
    Result.bind(&2, &2, X.Error, List<&2, X.Certificate>, Unit, CertTest.pathCertificates(leaf <> Nil{}, Nil{}), chain =>
      Result.map(&2, &2, X.Error, X.PublicKey, Unit, key => Unit{}, Trust.verifySAN(64n, W.multiply(W.fromU32(1700000000), W.fromU32(1000)), URL.Domain{reference}, chain, anchors)))))

def run(parts: List<&2, String>) -> String:
  match parts:
    case "dns" <> reference <> presented <> Nil{}: Bool.pick(String, Trust.matchDNS(reference, presented), "ok", "mismatch")
    case "cert" <> reference <> certificate <> Nil{}: checked(URL.Domain{reference}, X.parse(Bytes.bytes(certificate)))
    case "v4" <> reference <> certificate <> Nil{}: ipv4(certificate, URL.parseIpv4(reference))
    case "v6" <> reference <> certificate <> Nil{}: ipv6(certificate, URL.parseIpv6(reference))
    case "trust" <> reference <> anchor <> leaf <> Nil{}: trusted(reference, anchor, leaf)
    case _: "invalid"

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(value, '|')))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
