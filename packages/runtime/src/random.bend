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
