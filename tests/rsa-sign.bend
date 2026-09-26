import Base
import ../packages/runtime/src/rsa-sign.bend as Sign
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# tests/rsa_sign_check.py: each argument pair is a PEM file and a message in
# hex; each output line is the RS256 signature in hex or the error kind.

def hexDigit(+n: U32) -> String:
  Bool.pick(String, U32.is_lt(n, 10), String.from_list([Char.from_u32((48 + n : U32))]), String.from_list([Char.from_u32((87 + n : U32))]))

def hex(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +b <> rest: hexDigit(U32.div(b, 16)) ++ hexDigit(U32.mod(b, 16)) ++ hex(rest)

def nibble(c: Char) -> U32:
  +code = Char.to_u32(c)
  Bool.pick(U32, U32.is_lt(code, 58), (code - 48 : U32), (code - 87 : U32))

def unhex(text: String) -> List<&2, U32>:
  match text:
    case SCon{a, SCon{b, rest}}: ((nibble(a) * 16 + nibble(b) : U32)) <> unhex(rest)
    case _: Nil{}

def errorName(error: Sign.Error) -> String:
  match error:
    case Sign.InvalidPem{}: "error:pem"
    case Sign.InvalidDer{_}: "error:der"
    case Sign.UnsupportedKey{}: "error:unsupported"
    case Sign.KeyTooSmall{}: "error:small"
    case Sign.HashFailure{_}: "error:hash"

def shown(result: Result<&2, &2, Sign.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: hex(bytes)
    case Fail{error}: errorName(error)

def signed(key: Result<&2, &2, Sign.Error, Sign.PrivateKey>, message: List<&2, U32>) -> String:
  match key:
    case Done{k}: shown(Sign.signPkcs1Sha256(k, message))
    case Fail{error}: errorName(error)

def text(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, bytes))
    case Fail{_}: ""

def cases(args: List<String>) -> IO(Unit):
  match args:
    case path <> message <> rest:
      do IO<Unit>:
        content : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        IO.print(signed(Sign.parsePrivateKeyPem(text(content)), unhex(message)))
        cases(rest)
    case _: IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args)
