import Base
import ../packages/runtime/src/rsa-sha256.bend as RSA
import ../packages/runtime/src/string-split.bend as Split
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/test/utf8-runner.bend as Decimal

def error(cause: RSA.Error) -> String:
  match cause:
    case RSA.InvalidKey{}: "key"
    case RSA.InvalidSignature{}: "signature"
    case RSA.HashFailure{_}: "hash"

def recovered(result: Result<&2, &2, RSA.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{value}: Bytes.show(value)

def verified(result: Result<&2, &2, RSA.Error, Unit>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{Unit{}}: "ok"

def run(parts: List<&2, String>) -> String:
  match parts:
    case "v" <> modulus <> exponent <> message <> signature <> Nil{}:
      verified(Result.bind(&2, &2, RSA.Error, RSA.PublicKey, Unit, RSA.key(Bytes.bytes(modulus), Bytes.bytes(exponent)), public => RSA.verifyPkcs1(public, Bytes.bytes(message), Bytes.bytes(signature))))
    case "p" <> modulus <> exponent <> message <> signature <> saltLength <> Nil{}:
      verified(Result.bind(&2, &2, RSA.Error, RSA.PublicKey, Unit, RSA.key(Bytes.bytes(modulus), Bytes.bytes(exponent)), public => RSA.verifyPss(public, Bytes.bytes(message), Bytes.bytes(signature), U32.to_nat(Decimal.decimal(saltLength, 0)))))
    case "r" <> modulus <> exponent <> signature <> Nil{}:
      recovered(Result.bind(&2, &2, RSA.Error, RSA.PublicKey, List<&2, U32>, RSA.key(Bytes.bytes(modulus), Bytes.bytes(exponent)), public => RSA.recover(public, Bytes.bytes(signature))))
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
