import Base
import ../packages/runtime/src/tls-trust.bend as Trust
import ../packages/runtime/src/x509.bend as X
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/string.bend as Split
import ./aes128-gcm.bend as Bytes

def show(result: Result<&2, &2, Trust.IdentityError, Unit>) -> String:
  match result:
    case Done{_}: "ok"
    case Fail{Trust.InvalidReference{}}: "reference"
    case Fail{Trust.InvalidIdentityCertificate{_}}: "certificate"
    case Fail{Trust.MissingSubjectAltName{}}: "missing"
    case Fail{Trust.IdentityMismatch{}}: "mismatch"

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

def run(parts: List<&2, String>) -> String:
  match parts:
    case "dns" <> reference <> presented <> Nil{}: Bool.pick(String, Trust.matchDNS(reference, presented), "ok", "mismatch")
    case "cert" <> reference <> certificate <> Nil{}: checked(URL.Domain{reference}, X.parse(Bytes.bytes(certificate)))
    case "v4" <> reference <> certificate <> Nil{}: ipv4(certificate, URL.parseIpv4(reference))
    case "v6" <> reference <> certificate <> Nil{}: ipv6(certificate, URL.parseIpv6(reference))
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
