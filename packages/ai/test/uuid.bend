import Base
import ../src/utils/uuid.bend as Uuid
import ../../runtime/src/f64.bend as F

# upstream uuid.test.ts. The module-level generator state is an explicit
# Uuid.State threaded through the cases in file order, and vi's fake clock
# and stubbed getRandomValues become the `now` and random-byte inputs of the
# pure Uuid.next. Supplements check sequence exhaustion and the process
# Generator's ordering under concurrent callers.

type Outcome is Data:
  Outcome{state: Uuid.State, ids: List<&2, String>, valid: Bool}

def TIMESTAMP() -> Nat: Nat.add(Nat.mul(291n, Nat.mul(65536n, 65536n)), 1164413355n)

def number(+value: Nat) -> F64: F.fromNat(value)

# /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
def hexChar(+code: U32) -> Bool:
  (U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 97) && U32.is_le(code, 102))

def shaped(chars: List<&2, Char>, +index: Nat) -> Bool:
  match chars:
    case Nil{}: Nat.is_eq(index, 36n)
    case Chr{+code} <> rest:
      +here = Bool.pick(Bool, Nat.is_eq(index, 8n) || Nat.is_eq(index, 13n) || Nat.is_eq(index, 18n) || Nat.is_eq(index, 23n), U32.is_eq(code, 45), Bool.pick(Bool, Nat.is_eq(index, 14n), U32.is_eq(code, 55), Bool.pick(Bool, Nat.is_eq(index, 19n), U32.is_eq(code, 56) || U32.is_eq(code, 57) || U32.is_eq(code, 97) || U32.is_eq(code, 98), hexChar(code))))
      here && shaped(rest, 1n+index)

def isUuidV7(id: String) -> Bool: shaped(String.to_list(id), 0n)

def hexValue(+code: U32) -> Nat: U32.to_nat(Bool.pick(U32, U32.is_le(code, 57), (code - 48 : U32), (code - 87 : U32)))

def parseHex(chars: List<&2, Char>, value: Nat) -> Nat:
  match chars:
    case Nil{}: value
    case Chr{code} <> rest: parseHex(rest, Nat.add(Nat.mul(value, 16n), hexValue(code)))

# Number.parseInt(uuid.replaceAll("-", "").slice(0, 12), 16)
def parseTimestamp(+id: String) -> Nat: parseHex(String.to_list(String.take(id, 8n) ++ String.take(String.drop(id, 9n), 4n)), 0n)

def ascending(ids: List<&2, String>) -> Bool:
  match ids:
    case first <> +second <> rest: String.is_lt(first, second) && ascending(second <> rest)
    case _: True{}

def member(+id: String, ids: List<&2, String>) -> Bool:
  match ids:
    case Nil{}: False{}
    case other <> rest: String.eq(id, other) || member(id, rest)

def distinct(ids: List<&2, String>) -> Bool:
  match ids:
    case Nil{}: True{}
    case +id <> +rest: Bool.not(member(id, rest)) && distinct(rest)

def timestamps(ids: List<&2, String>) -> List<&2, Nat>:
  match ids:
    case Nil{}: Nil{}
    case id <> rest: parseTimestamp(id) <> timestamps(rest)

def sameNats(left: List<&2, Nat>, right: List<&2, Nat>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: Nat.is_eq(a, b) && sameNats(as, bs)
    case _ _: False{}

def drawnRandom(random: Maybe<&2, Uuid.Random>) -> IO(Uuid.Random):
  match random:
    case Some{random}: IO.pure(Uuid.Random, random)
    case None{}: IO.die(Uuid.Random, 1, "short entropy")

def randomOf(bytes: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Uuid.Random):
  match bytes:
    case Done{bytes}: drawnRandom(Uuid.draw(bytes))
    case Fail{_}: IO.die(Uuid.Random, 1, "no entropy")

def fresh() -> IO(Uuid.Random):
  do IO<Uuid.Random>:
    bytes : Result<&1, &1, U32 & String, List<&2, U32>> <- Entropy.bytes(16)
    randomOf(bytes)

def called(result: Uuid.State & Result<&2, &2, Uuid.Error, String>, ids: List<&2, String>, valid: Bool) -> Outcome:
  match result:
    case Tuple{state, Done{+id}}: Outcome{state, List.append(&2, String, ids, id <> Nil{}), valid && isUuidV7(id)}
    case Tuple{state, Fail{_}}: Outcome{state, ids, False{}}

# One call with a fresh random draw, like upstream's getRandomValues.
def step(outcome: Outcome, timestampMs: Maybe<&2, F64>, now: F64) -> IO(Outcome):
  match outcome:
    case Outcome{state, ids, valid}:
      do IO<Outcome>:
        random : Uuid.Random <- fresh()
        return called(Uuid.next(state, timestampMs, now, random), ids, valid)

def report(+name: String, passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), passed, IO.print("PASS " ++ name), IO.die(Unit, 1, "FAIL " ++ name))

def idsOf(outcome: Outcome) -> List<&2, String>:
  match outcome:
    case Outcome{_, ids, _}: ids

def stateOf(outcome: Outcome) -> Uuid.State:
  match outcome:
    case Outcome{state, _, _}: state

def validOf(outcome: Outcome) -> Bool:
  match outcome:
    case Outcome{_, _, valid}: valid

def orderedCase(+ordinary: Outcome, +followers: Outcome, +followerTimestamp: Nat) -> IO(Uuid.State):
  +ordinaryIds = idsOf(ordinary)
  +followerIds = idsOf(followers)
  +passed = validOf(ordinary) && validOf(followers) && ascending(ordinaryIds) && distinct(ordinaryIds) && sameNats(timestamps(ordinaryIds), [TIMESTAMP(), TIMESTAMP(), TIMESTAMP(), 1n+TIMESTAMP()]) && sameNats(timestamps(followerIds), [followerTimestamp, followerTimestamp]) && distinct(followerIds)
  do IO<Uuid.State>:
    report("generates ordered UUIDv7s while preserving follower timestamps", passed)
    return stateOf(followers)

def begin(state: Uuid.State) -> Outcome: Outcome{state, Nil{}, True{}}

def generatesOrdered(state: Uuid.State) -> IO(Uuid.State):
  +followerTimestamp = Nat.sub(TIMESTAMP(), 1000n)
  do IO<Uuid.State>:
    first : Outcome <- step(begin(state), None{}, number(TIMESTAMP()))
    second : Outcome <- step(first, None{}, number(TIMESTAMP()))
    afterRollback : Outcome <- step(second, None{}, number(Nat.sub(TIMESTAMP(), 1n)))
    +afterAdvance : Outcome <- step(afterRollback, None{}, number(1n+TIMESTAMP()))
    follower : Outcome <- step(begin(stateOf(afterAdvance)), Some{number(followerTimestamp)}, number(1n+TIMESTAMP()))
    followers : Outcome <- step(follower, Some{number(followerTimestamp)}, number(1n+TIMESTAMP()))
    orderedCase(afterAdvance, followers, followerTimestamp)

def filled(+byte: U32) -> Uuid.Random:
  Maybe.default(&2, Uuid.Random, Uuid.draw(List.replicate(U32, 16n, byte)), Uuid.Random{0n, 0, Nil{}})

def tail(result: Result<&2, &2, Uuid.Error, String>) -> String:
  match result:
    case Done{id}: String.drop(id, 28n)
    case Fail{error}: Uuid.errorMessage(error)

def secondTail(+first: String, second: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Uuid.State):
  match second:
    case Tuple{state, result}:
      do IO<Uuid.State>:
        report("uses fresh randomness for every UUID tail", String.eq(first, "01010101") && String.eq(tail(result), "02020202"))
        return state

def firstTail(first: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Uuid.State):
  match first:
    case Tuple{state, result}: secondTail(tail(result), Uuid.next(state, Some{number(TIMESTAMP())}, number(TIMESTAMP()), filled(2)))

def freshRandomness(state: Uuid.State) -> IO(Uuid.State):
  firstTail(Uuid.next(state, Some{number(TIMESTAMP())}, number(TIMESTAMP()), filled(1)))

def parsedTimestamp(result: Result<&2, &2, Uuid.Error, String>) -> Maybe<&2, Nat>:
  match result:
    case Done{id}: Some{parseTimestamp(id)}
    case Fail{_}: None{}

def accepted(+label: String, +timestamp: Nat, generated: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Uuid.State):
  match generated:
    case Tuple{state, result}:
      do IO<Uuid.State>:
        report("accepts timestamp boundary " ++ label, Maybe.default(&2, Bool, Maybe.map(&2, Nat, Bool, parsed => Nat.is_eq(parsed, timestamp), parsedTimestamp(result)), False{}))
        return state

def accepts(state: Uuid.State, +label: String, +timestamp: Nat) -> IO(Uuid.State):
  accepted(label, timestamp, Uuid.next(state, Some{number(timestamp)}, number(TIMESTAMP()), filled(3)))

def invalid(result: Result<&2, &2, Uuid.Error, String>) -> Bool:
  match result:
    case Fail{Uuid.InvalidTimestamp{}}: True{}
    case _: False{}

def rejected(+label: String, generated: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Uuid.State):
  match generated:
    case Tuple{state, result}:
      do IO<Uuid.State>:
        report("rejects invalid timestamp " ++ label, invalid(result))
        return state

def rejects(state: Uuid.State, +label: String, timestamp: F64) -> IO(Uuid.State):
  rejected(label, Uuid.next(state, Some{timestamp}, number(TIMESTAMP()), filled(4)))

# Supplement: the 2^41-th sequence value fails after recording the ordinary
# timestamp, as upstream's increment check follows the timestamp update.
def exhaustedCase(result: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> Bool:
  match result:
    case Tuple{Uuid.State{last, Some{sequence}}, Fail{Uuid.SequenceExhausted{}}}: Nat.is_eq(last, 1n+TIMESTAMP()) && Nat.is_eq(sequence, Uuid.MAX_SEQUENCE())
    case _: False{}

def exhaustion() -> IO(Unit):
  report("supplement: sequence exhaustion records the timestamp and fails", exhaustedCase(Uuid.next(Uuid.State{TIMESTAMP(), Some{Uuid.MAX_SEQUENCE()}}, None{}, number(1n+TIMESTAMP()), filled(5))))

# Supplement: exact ids from pinned upstream uuidv7 with getRandomValues
# stubbed to byte i of draw n = (17i + 101n + 3) mod 256: the seeded
# sequence, its increments and every bit position.
def patternBytes(count: Nat, +draw: U32, +index: U32) -> List<&2, U32>:
  match count:
    case 0n: Nil{}
    case 1n+remaining: U32.and(((17 * index) + ((101 * draw) + 3) : U32), 255) <> patternBytes(remaining, draw, (index + 1 : U32))

def pattern(+draw: U32) -> Uuid.Random:
  Maybe.default(&2, Uuid.Random, Uuid.draw(patternBytes(16n, draw, 0)), Uuid.Random{0n, 0, Nil{}})

def idOf(result: Result<&2, &2, Uuid.Error, String>) -> String:
  match result:
    case Done{id}: id
    case Fail{error}: Uuid.errorMessage(error)

def layoutThird(+first: String, +second: String, third: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Unit):
  match third:
    case Tuple{_, result}: report("supplement: ids match upstream for fixed random bytes", String.eq(first, "01234567-89ab-70a1-8a6c-8eb0cfe0f102") && String.eq(second, "01234567-89ab-70a1-8a6c-8eb334455667") && String.eq(idOf(result), "00000000-0005-70a1-8a6c-8eb499aabbcc"))

def layoutSecond(+first: String, second: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Unit):
  match second:
    case Tuple{state, result}: layoutThird(first, idOf(result), Uuid.next(state, Some{number(5n)}, number(TIMESTAMP()), pattern(2)))

def layoutFirst(first: Uuid.State & Result<&2, &2, Uuid.Error, String>) -> IO(Unit):
  match first:
    case Tuple{state, result}: layoutSecond(idOf(result), Uuid.next(state, Some{number(TIMESTAMP())}, number(TIMESTAMP()), pattern(1)))

def layout() -> IO(Unit):
  layoutFirst(Uuid.next(Uuid.initial(), Some{number(TIMESTAMP())}, number(TIMESTAMP()), pattern(0)))

# Supplement: callers sharing one process Generator race; each caller's own
# ids are strictly ordered and no id repeats.
def generatedIds(+generator: Uuid.Generator, count: Nat, +ids: List<&2, String>) -> IO(List<&2, String>):
  match count:
    case 0n: IO.pure(List<&2, String>, List.reverse(&2, String, ids))
    case 1n+remaining:
      do IO<List<&2, String>>:
        result : Result<&2, &2, Uuid.Error, String> <- Uuid.uuidv7(generator, None{})
        generatedIds(generator, remaining, Result.default(&2, &2, Uuid.Error, String, result, "error") <> ids)

def concurrent() -> IO(Unit):
  do IO<Unit>:
    +generator : Uuid.Generator <- Uuid.generator()
    +a : Chan(List<&2, String>) <- IO.fork(List<&2, String>, generatedIds(generator, 50n, Nil{}))
    +b : Chan(List<&2, String>) <- IO.fork(List<&2, String>, generatedIds(generator, 50n, Nil{}))
    +c : Chan(List<&2, String>) <- IO.fork(List<&2, String>, generatedIds(generator, 50n, Nil{}))
    +d : List<&2, String> <- generatedIds(generator, 50n, Nil{})
    +ra : List<&2, String> <- IO.join(List<&2, String>, a)
    +rb : List<&2, String> <- IO.join(List<&2, String>, b)
    +rc : List<&2, String> <- IO.join(List<&2, String>, c)
    report("supplement: concurrent callers of one generator get ordered, distinct ids", ascending(ra) && ascending(rb) && ascending(rc) && ascending(d) && distinct(List.concat(&2, String, [ra, rb, rc, d])) && List.all(~&2, ~String, ~isUuidV7, List.concat(&2, String, [ra, rb, rc, d])))

def main() -> IO(Unit):
  do IO<Unit>:
    ordered : Uuid.State <- generatesOrdered(Uuid.initial())
    stubbed : Uuid.State <- freshRandomness(ordered)
    zero : Uuid.State <- accepts(stubbed, "0", 0n)
    maximum : Uuid.State <- accepts(zero, "281474976710655", Uuid.MAX_UUID_V7_TIMESTAMP())
    negative : Uuid.State <- rejects(maximum, "-1", F.negate(number(1n)))
    large : Uuid.State <- rejects(negative, "281474976710656", F.add(number(Uuid.MAX_UUID_V7_TIMESTAMP()), number(1n)))
    fractional : Uuid.State <- rejects(large, "1.5", F.divide(number(3n), number(2n)))
    nan : Uuid.State <- rejects(fractional, "NaN", F.nan())
    infinite : Uuid.State <- rejects(nan, "Infinity", F.infinity(False{}))
    exhaustion()
    layout()
    concurrent()
