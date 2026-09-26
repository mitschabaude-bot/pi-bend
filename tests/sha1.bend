import Base
import ../packages/runtime/src/sha1.bend as Sha1

# tests/sha1_check.py: each argument is a message in hex; each output line is
# its SHA-1 digest in hex.

def nibble(c: Char) -> U32:
  +code = Char.to_u32(c)
  Bool.pick(U32, U32.is_lt(code, 58), (code - 48 : U32), (code - 87 : U32))

def unhex(text: String) -> List<&2, U32>:
  match text:
    case SCon{a, SCon{b, rest}}: ((nibble(a) * 16 + nibble(b) : U32)) <> unhex(rest)
    case _: Nil{}

def digests(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case message <> rest:
      do IO<Unit>:
        IO.print(Sha1.hex(unhex(message)))
        digests(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    digests(arguments)
