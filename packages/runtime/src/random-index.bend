import Base

# OS-backed uniform indices. Policy and rejection sampling are pure Bend;
# the entropy primitive supplies only four bytes per attempt.
type Error is Data:
  InvalidBound{}
  SourceFailure{code: U32, message: String}
  InvalidBytes{}

type Range is Data:
  Range{bound: Nat, ceiling: Nat}

def width() -> Nat: 1n+4294967295n

def checked(+bound: Nat, valid: Bool) -> Result<&2, &2, Error, Range>:
  match valid:
    case False{}: Fail{InvalidBound{}}
    case True{}: Done{Range{bound, Nat.sub(width(), Nat.mod(width(), bound))}}

def prepare(+bound: Nat) -> Result<&2, &2, Error, Range>:
  checked(bound, Nat.is_gt(bound, 0n) && Nat.is_le(bound, width()))

def accepted(bound: Nat, word: Nat, valid: Bool) -> Maybe<&2, Nat>:
  match valid:
    case False{}: None{}
    case True{}: Some{Nat.mod(word, bound)}

# Discard the incomplete final bucket; every accepted index has exactly the
# same number of preimages. A source word is unsigned and at most 2^32-1.
def select(range: Range, +word: U32) -> Maybe<&2, Nat>:
  match range:
    case Range{bound, ceiling}: accepted(bound, U32.to_nat(word), Nat.is_lt(U32.to_nat(word), ceiling))

def octets(a: U32, b: U32, c: U32, d: U32, valid: Bool) -> Result<&2, &2, Error, U32>:
  match valid:
    case False{}: Fail{InvalidBytes{}}
    case True{}: Done{U32.or(U32.shln(a, 24n), U32.or(U32.shln(b, 16n), U32.or(U32.shln(c, 8n), d)))}

def decoded(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{(code, message)}: Fail{SourceFailure{code, message}}
    case Done{+a <> +b <> +c <> +d <> Nil{}}: octets(a, b, c, d, U32.is_le(a, 255) && U32.is_le(b, 255) && U32.is_le(c, 255) && U32.is_le(d, 255))
    case Done{_}: Fail{InvalidBytes{}}

def word(unused: Unit) -> IO(Result<&2, &2, Error, U32>):
  do IO<Result<&2, &2, Error, U32>>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(4)
    return decoded(bytes)

def sampled(range: Range, result: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, Maybe<&2, Nat>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{select(range, value)}

# The injected source remains caller-owned and must return promptly. Rejected
# words draw again; source failures return intact, with no fallback randomness.
@unsafe def retry(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Error, U32>), +environment: Environment, +range: Range, result: Result<&2, &2, Error, Maybe<&2, Nat>>) -> IO(Result<&2, &2, Error, Nat>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Nat>, Fail{error})
    case Done{Some{index}}: IO.pure(Result<&2, &2, Error, Nat>, Done{index})
    case Done{None{}}:
      do IO<Result<&2, &2, Error, Nat>>:
        next : Result<&2, &2, Error, U32> <- draw(environment)
        retry(~Environment, ~draw, environment, range, sampled(range, next))

def started(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Error, U32>), environment: Environment, range: Result<&2, &2, Error, Range>) -> IO(Result<&2, &2, Error, Nat>):
  match range:
    case Fail{error}: IO.pure(Result<&2, &2, Error, Nat>, Fail{error})
    case Done{Range{1n, _}}: IO.pure(Result<&2, &2, Error, Nat>, Done{0n})
    case Done{valid}: retry(~Environment, ~draw, environment, valid, Done{None{}})

def sampleWith(~Environment: Data, ~draw: Environment -> IO(Result<&2, &2, Error, U32>), environment: Environment, bound: Nat) -> IO(Result<&2, &2, Error, Nat>):
  started(~Environment, ~draw, environment, prepare(bound))

def random(bound: Nat) -> IO(Result<&2, &2, Error, Nat>):
  sampleWith(~Unit, ~word, Unit{}, bound)
