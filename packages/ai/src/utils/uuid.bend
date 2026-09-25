import Base
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/date.bend as Date
import ../../../runtime/src/ref.bend as R

# Time-ordered UUIDv7 (upstream utils/uuid.ts): a 48-bit millisecond
# timestamp, a 41-bit monotonic sequence and fresh random bits. Upstream's
# module variables are the explicit State below; `advance` is its pure
# transition and a Generator owns it in a Ref, so the ids of every caller that
# shares the process generator are strictly ordered even when they race.

# Nat literals stop at 2^32-1 and Nat itself at 2^48-1, exactly the largest
# UUIDv7 timestamp; larger constants are built from 2^32.
def word() -> Nat: Nat.mul(65536n, 65536n)
def MAX_UUID_V7_TIMESTAMP() -> Nat: Nat.add(Nat.mul(65535n, word()), 4294967295n)
def MAX_SEQUENCE() -> Nat: Nat.sub(Nat.mul(word(), 512n), 1n)

type Error is Data:
  InvalidTimestamp{}
  SequenceExhausted{}
  EntropyUnavailable{message: String}

# Upstream throws a RangeError with these messages.
def errorMessage(error: Error) -> String:
  match error:
    case InvalidTimestamp{}: "UUIDv7 timestamp must be an integer between 0 and 281474976710655"
    case SequenceExhausted{}: "UUIDv7 generator sequence exhausted"
    case EntropyUnavailable{message}: "Could not obtain entropy for a UUID: " ++ message

# lastOrdinaryTimestamp starts at 0 instead of upstream's -1: every accepted
# timestamp is a natural number t, and max(t, -1) = max(t, 0) = t.
type State is Data:
  State{lastOrdinaryTimestamp: Nat, sequence: Maybe<&2, Nat>}

def initial() -> State: State{0n, None{}}

# The ordering-relevant prefix of an id: 48 timestamp bits, then 41 sequence bits.
type Key is Data:
  Key{timestamp: Nat, sequence: Nat}

def nextSequence(+limit: Nat, sequence: Maybe<&2, Nat>, seed: Nat) -> Maybe<&2, Nat>:
  match sequence:
    case None{}: Some{seed}
    case Some{+value}: Bool.pick(Maybe<&2, Nat>, Nat.is_eq(value, limit), None{}, Some{1n+value})

def advanced(+timestamp: Nat, +last: Nat, sequence: Maybe<&2, Nat>, next: Maybe<&2, Nat>) -> State & Maybe<&2, Key>:
  match next:
    case None{}: (State{last, sequence}, None{})
    case Some{+value}: (State{last, Some{value}}, Some{Key{timestamp, value}})

# An ordinary id clamps a clock rollback to the last ordinary timestamp and
# records its timestamp; a follower keeps the requested one. Both advance the
# shared sequence, which a process seeds once from 40 random bits, up to the
# limit. Exhaustion fails after the timestamp was recorded, as upstream.
def advanceWithin(+limit: Nat, state: State, +requested: Nat, +ordinary: Bool, seed: Nat) -> State & Maybe<&2, Key>:
  match state:
    case State{+last, +sequence}:
      +timestamp = Bool.pick(Nat, ordinary, Nat.max(requested, last), requested)
      advanced(timestamp, Bool.pick(Nat, ordinary, timestamp, last), sequence, nextSequence(limit, sequence, seed))

def advance(state: State, +requested: Nat, +ordinary: Bool, seed: Nat) -> State & Maybe<&2, Key>:
  advanceWithin(MAX_SEQUENCE(), state, requested, ordinary, seed)

# The 16 random bytes upstream draws per id: bytes 1..5 seed a fresh
# sequence, the low bit of byte 11 and bytes 12..15 stay random.
type Random is Data:
  Random{seed: Nat, bit: U32, tail: List<&2, U32>}

def draw(bytes: List<&2, U32>) -> Maybe<&2, Random>:
  match bytes:
    case _ <> r1 <> r2 <> r3 <> r4 <> r5 <> _ <> _ <> _ <> _ <> _ <> r11 <> r12 <> r13 <> r14 <> r15 <> Nil{}:
      Some{Random{Nat.add(Nat.mul(U32.to_nat(r1), word()), U32.to_nat(U32.or(U32.shln(r2, 24n), U32.or(U32.shln(r3, 16n), U32.or(U32.shln(r4, 8n), r5))))), U32.and(r11, 1), [r12, r13, r14, r15]}}
    case _: None{}

# Bits [divisor, divisor * modulus) of a natural, as a byte-sized word.
def bits(value: Nat, divisor: Nat, modulus: Nat) -> U32: U32.from_nat(Nat.mod(Nat.div(value, divisor), modulus))

def keyBytes(key: Key, bit: U32) -> List<&2, U32>:
  match key:
    case Key{+t, +s}:
      [bits(t, Nat.mul(word(), 256n), 256n), bits(t, word(), 256n), bits(t, 16777216n, 256n), bits(t, 65536n, 256n), bits(t, 256n, 256n), bits(t, 1n, 256n), U32.or(112, bits(s, Nat.mul(word(), 32n), 16n)), bits(s, 536870912n, 256n), U32.or(128, bits(s, 8388608n, 64n)), bits(s, 32768n, 256n), bits(s, 128n, 256n), U32.or(U32.shln(bits(s, 1n, 128n), 1n), bit)]

def hexDigit(+value: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(value, 10), (48 + value : U32), (87 + value : U32)))

def hex(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{hexDigit(U32.shrn(byte, 4n)), SCon{hexDigit(U32.and(byte, 15)), hex(rest)}}

# 8-4-4-4-12 hexadecimal groups of 16 bytes.
def formatted(+bytes: List<&2, U32>) -> String:
  hex(List.take(&2, U32, bytes, 4n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 4n), 2n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 6n), 2n)) ++ "-" ++ hex(List.take(&2, U32, List.drop(&2, U32, bytes, 8n), 2n)) ++ "-" ++ hex(List.drop(&2, U32, bytes, 10n))

def identifier(key: Key, random: Random) -> String:
  match random:
    case Random{_, bit, tail}: formatted(List.append(&2, U32, keyBytes(key, bit), tail))

# Integers 0..2^48-1; -0 reads as 0. Negative, fractional, larger and
# non-finite numbers are rejected.
def timestampOf(converted: Result<&2, &2, F.Error, Nat>) -> Maybe<&2, Nat>:
  match converted:
    case Done{timestamp}: Some{timestamp}
    case Fail{_}: None{}

def validTimestamp(+value: F64) -> Maybe<&2, Nat>: timestampOf(F.convert(value))

def generated(result: State & Maybe<&2, Key>, random: Random) -> State & Result<&2, &2, Error, String>:
  match result:
    case Tuple{state, None{}}: (state, Fail{SequenceExhausted{}})
    case Tuple{state, Some{key}}: (state, Done{identifier(key, random)})

def validated(state: State, timestamp: Maybe<&2, Nat>, ordinary: Bool, random: Random) -> State & Result<&2, &2, Error, String>:
  match timestamp random:
    case None{} _: (state, Fail{InvalidTimestamp{}})
    case Some{timestamp} Random{+seed, bit, tail}: generated(advance(state, timestamp, ordinary, seed), Random{seed, bit, tail})

# upstream uuidv7(timestampMs?) as a pure step: the clock reading and random
# bytes are inputs, the next generator state an output. An invalid timestamp
# leaves the state unchanged.
def next(state: State, +timestampMs: Maybe<&2, F64>, now: F64, random: Random) -> State & Result<&2, &2, Error, String>:
  validated(state, validTimestamp(Maybe.default(&2, F64, timestampMs, now)), Maybe.is_none(&2, F64, timestampMs), random)

# The process generator: one per process, shared by every id-creating caller.
type Generator is Data:
  Generator{state: R.Ref<State>}

def generator() -> IO(Generator):
  do IO<Generator>:
    +state : R.Ref<State> <- R.new(State, initial())
    return Generator{state}

def drawn(bytes: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, Error, Random>:
  match bytes:
    case Fail{(_, message)}: Fail{EntropyUnavailable{message}}
    case Done{bytes}: Maybe.default(&2, Result<&2, &2, Error, Random>, Maybe.map(&2, Random, Result<&2, &2, Error, Random>, random => Done{random}, draw(bytes)), Fail{EntropyUnavailable{"too few bytes"}})

def stepped(generator: Generator, timestampMs: Maybe<&2, F64>, now: F64, random: Result<&2, &2, Error, Random>) -> IO(Result<&2, &2, Error, String>):
  match generator random:
    case _ Fail{error}: IO.pure(Result<&2, &2, Error, String>, Fail{error})
    case Generator{state} Done{random}: R.modify(State, Result<&2, &2, Error, String>, state, current => next(current, timestampMs, now, random))

# Generate a time-ordered UUIDv7. A supplied timestamp is preserved for follower ids.
def uuidv7(generator: Generator, timestampMs: Maybe<&2, F64>) -> IO(Result<&2, &2, Error, String>):
  do IO<Result<&2, &2, Error, String>>:
    now : F64 <- Date.now()
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(16)
    stepped(generator, timestampMs, now, drawn(bytes))

# node:crypto randomUUID (version 4), used where upstream calls it rather than uuidv7.
def v4(bytes: List<&2, U32>) -> Maybe<&2, String>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      Some{formatted([a, b, c, d, e, f, U32.or(64, U32.and(g, 15)), h, U32.or(128, U32.and(i, 63)), j, k, l, m, n, o, p])}
    case _: None{}

def randomDrawn(bytes: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&2, &2, Error, String>:
  match bytes:
    case Fail{(_, message)}: Fail{EntropyUnavailable{message}}
    case Done{bytes}: Maybe.default(&2, Result<&2, &2, Error, String>, Maybe.map(&2, String, Result<&2, &2, Error, String>, id => Done{id}, v4(bytes)), Fail{EntropyUnavailable{"too few bytes"}})

def randomUUID() -> IO(Result<&2, &2, Error, String>):
  do IO<Result<&2, &2, Error, String>>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(16)
    return randomDrawn(bytes)
