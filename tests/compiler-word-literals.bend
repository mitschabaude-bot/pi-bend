import Base

# Compiler representation regression: literal words, generic containers,
# reconstructed words and values received only at runtime.
type Box<-A: Data> is Data:
  Box{value: A}

def unbox(-A: Data, value: Box<A>) -> A:
  match value:
    case Box{item}: item

def rebuild(value: U32) -> U32:
  match value:
    case U32{bits}: U32{bits}

def floatBits(value: F32) -> U32:
  match value:
    case F32{bits}: U32{bits}

def firstBit(value: Bool) -> U32:
  U32{WCon{value, Word.zero(31n)}}

def integer(+value: U32) -> IO(Unit):
  IO.print(U32.show(unbox(U32, Box{value})) ++ ":" ++ U32.show(rebuild(value)) ++ ":" ++ U32.show(firstBit(U32.is_ne(value, 0))))

def float(value: F32) -> IO(Unit):
  IO.print(U32.show(floatBits(unbox(F32, Box{value}))))

def parsed(value: Maybe<&2, U32>) -> IO(Unit):
  match value:
    case Some{number}: integer(number)
    case None{}: IO.die(Unit, 1, "expected a decimal word")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case text <> rest:
      do IO<Unit>:
        parsed(U32.read(text))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    integer(0)
    integer(1)
    integer(2147483648)
    integer(4294967295)
    float(0.0)
    float(F32.neg(0.0))
    float(1.0)
    float(0.1)
    float(1.17549435e-38)
    float(1.40129846e-45)
    float(3.40282347e38)
    values : List<String> <- IO.args()
    arguments(values)
