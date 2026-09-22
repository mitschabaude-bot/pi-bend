import Base
import ./u64.bend as W
import ./f64.bend as F
import ./ref.bend as R


# SplitMix64, following Sebastiano Vigna's public-domain reference:
# https://prng.di.unimi.it/splitmix64.c
# Non-cryptographic randomness for jitter/sampling, never authentication.
type Generator is Data:
  Generator{state: R.Ref<W.U64>}

def mix(+value: W.U64) -> W.U64:
  +first = W.multiply(W.bitXor(value, W.shiftRight(value, 30n)), W.U64{3210233709, 484763065})
  +second = W.multiply(W.bitXor(first, W.shiftRight(first, 27n)), W.U64{2496678331, 321982955})
  W.bitXor(second, W.shiftRight(second, 31n))

def step(seed: W.U64) -> W.U64 & W.U64:
  +next = W.add(seed, W.U64{2654435769, 2135587861})
  (next, mix(next))

# Exactly 53 random bits, scaled by 2^-53. All intermediate integers are
# representable; the result is in [0,1), including zero and excluding one.
def unit(value: W.U64) -> F.F64:
  F.multiply(F.fromU64(W.shiftRight(value, 11n)), F.fromBits(1017118720, 0))

def seeded(seed: W.U64) -> IO(Generator):
  do IO<Generator>:
    state : R.Ref<W.U64> <- R.new(W.U64, seed)
    return Generator{state}

def nextWord(generator: Generator) -> IO(W.U64):
  match generator:
    case Generator{state}: R.modify(W.U64, W.U64, state, value => step(value))

def random(generator: Generator) -> IO(F.F64):
  do IO<F.F64>:
    word : W.U64 <- nextWord(generator)
    return unit(word)

# Retire the generator after all borrowed handles/callbacks have finished.
def dispose(generator: Generator) -> IO(Unit):
  match generator:
    case Generator{state}:
      do IO<Unit>:
        last : W.U64 <- R.dispose(W.U64, state)
        return Unit{}


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

def randomWord(unused: Unit) -> IO(Result<&2, &2, Error, U32>):
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

def randomIndex(bound: Nat) -> IO(Result<&2, &2, Error, Nat>):
  sampleWith(~Unit, ~randomWord, Unit{}, bound)


# Linux entropy boundary using existing native binary-file primitives. Source
# failures remain typed; never substitute timestamps or a fixed fallback seed.
type SeedError is Data:
  SeedSourceFailure{code: U32, message: String}
  ShortSeed{bytes: Nat}

def sourceFailure(error: U32 & String) -> SeedError:
  match error:
    case Tuple{code, message}: SeedSourceFailure{code, message}

def seedWord(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.shln(a, 24n), U32.or(U32.shln(b, 16n), U32.or(U32.shln(c, 8n), d)))

def decode(+bytes: List<&2, U32>) -> Result<&2, &2, SeedError, W.U64>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}: Done{W.U64{seedWord(a, b, c, d), seedWord(e, f, g, h)}}
    case _: Fail{ShortSeed{List.length(&2, U32, bytes)}}

def decodedSeed(result: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, SeedError, W.U64>:
  match result:
    case Fail{error}: Fail{sourceFailure(error)}
    case Done{bytes}: decode(bytes)

def closeRead(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, SeedError, W.U64>):
  match pair:
    case Tuple{file, result}:
      do IO<Result<&2, &2, SeedError, W.U64>>:
        File.close(file)
        return decodedSeed(result)

def readOpened(result: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, SeedError, W.U64>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, SeedError, W.U64>, Fail{sourceFailure(error)})
    case Done{file}:
      do IO<Result<&2, &2, SeedError, W.U64>>:
        bytes : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 8)
        closeRead(bytes)

# The source path is injectable for deterministic success/error tests. A short
# read is an explicit initialization failure, never a partially padded seed.
def read(path: String) -> IO(Result<&2, &2, SeedError, W.U64>):
  do IO<Result<&2, &2, SeedError, W.U64>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    readOpened(opened)

def initialize(result: Result<&2, &2, SeedError, W.U64>) -> IO(Result<&2, &2, SeedError, Generator>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, SeedError, Generator>, Fail{error})
    case Done{seed}:
      do IO<Result<&2, &2, SeedError, Generator>>:
        generator : Generator <- seeded(seed)
        return Done{generator}

def new() -> IO(Result<&2, &2, SeedError, Generator>):
  do IO<Result<&2, &2, SeedError, Generator>>:
    seed : Result<&2, &2, SeedError, W.U64> <- read("/dev/urandom")
    initialize(seed)
