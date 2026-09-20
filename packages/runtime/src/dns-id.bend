import Base

# ID generation is separate from matching and pending-request ownership.
# Two uniformly random octets cover the full DNS ID range without modulo bias.
type Error is Data:
  SourceFailure{code: U32, message: String}
  InvalidBytes{}

def octets(high: U32, low: U32, valid: Bool) -> Result<&2, &2, Error, U32>:
  match valid:
    case True{}: Done{U32.or(U32.shln(high, 8n), low)}
    case False{}: Fail{InvalidBytes{}}

def decoded(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{Tuple{code, message}}: Fail{SourceFailure{code, message}}
    case Done{+high <> +low <> Nil{}}: octets(high, low, U32.is_le(high, 255) && U32.is_le(low, 255))
    case Done{_}: Fail{InvalidBytes{}}

def random(unused: Unit) -> IO(Result<&2, &2, Error, U32>):
  do IO<Result<&2, &2, Error, U32>>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(2)
    return decoded(bytes)

def fixed(value: U32) -> IO(Result<&2, &2, Error, U32>):
  IO.pure(Result<&2, &2, Error, U32>, Done{value})
