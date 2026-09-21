import Base
import ../packages/runtime/src/x509.bend as X509
import ../packages/runtime/src/der.bend as DER
import ../packages/runtime/src/rsa-sha256.bend as RSA
import ../packages/runtime/src/big-nat.bend as Big
import ../packages/runtime/src/string-split.bend as Split
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/test/utf8-runner.bend as Decimal

def error(cause: X509.Error) -> String:
  match cause:
    case X509.Encoding{_}: "encoding"
    case X509.InvalidCertificate{}: "certificate"
    case X509.UnsupportedAlgorithm{}: "algorithm"
    case X509.Signature{_}: "signature"
    case X509.InvalidTime{}: "time"
    case X509.NotYetValid{}: "early"
    case X509.Expired{}: "expired"

def parsed(result: Result<&2, &2, X509.Error, X509.Certificate>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{X509.Certificate{tbs, algorithm, signature}}:
      Bytes.show(DER.encoded(tbs)) ++ "|" ++ Bytes.show(DER.encoded(algorithm)) ++ "|" ++ Bytes.show(signature)

def publicKey(result: Result<&2, &2, X509.Error, RSA.PublicKey>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{RSA.PublicKey{modulus, exponent, bytes, bits}}:
      Big.toDecimal(modulus) ++ "|" ++ Bytes.show(exponent) ++ "|" ++ Nat.show(bytes) ++ "|" ++ Nat.show(bits)

def verified(result: Result<&2, &2, X509.Error, Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def verify(issuer: List<&2, U32>, certificate: List<&2, U32>) -> Result<&2, &2, X509.Error, Unit>:
  Result.bind(&2, &2, X509.Error, X509.Certificate, Unit, X509.parse(issuer), issuerCertificate =>
    Result.bind(&2, &2, X509.Error, RSA.PublicKey, Unit, X509.rsaPublicKey(issuerCertificate), key =>
      Result.bind(&2, &2, X509.Error, X509.Certificate, Unit, X509.parse(certificate), subject => X509.verifyRsaSha256(key, subject))))

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

def run(parts: List<&2, String>) -> String:
  match parts:
    case "t" <> bytes <> Nil{}: instant(Result.bind(&2, &2, X509.Error, DER.Node, W.U64, X509.decoded(DER.Node, DER.one(Bytes.bytes(bytes))), X509.time))
    case "range" <> bytes <> Nil{}:
      period(Result.bind(&2, &2, X509.Error, DER.Node, X509.Validity, X509.decoded(DER.Node, DER.one(Bytes.bytes(bytes))), root =>
        Result.bind(&2, &2, X509.Error, List<&2, DER.Node>, X509.Validity, X509.decoded(List<&2, DER.Node>, DER.sequence(root)), X509.validityTimes)))
    case "a" <> bytes <> high <> low <> Nil{}: verified(at(high,low,Bytes.bytes(bytes)))
    case "p" <> bytes <> Nil{}: parsed(X509.parse(Bytes.bytes(bytes)))
    case "k" <> bytes <> Nil{}: publicKey(Result.bind(&2, &2, X509.Error, X509.Certificate, RSA.PublicKey, X509.parse(Bytes.bytes(bytes)), X509.rsaPublicKey))
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
