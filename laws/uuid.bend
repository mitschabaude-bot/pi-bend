import Base
import ../packages/ai/src/utils/uuid.bend as Uuid

# Ordering of the UUIDv7 generator's pure transition. A state covers a key
# when its recorded ordinary timestamp and sequence are at least the key's.
# Together the three laws give upstream's guarantee for any interleaving of
# ordinary and follower ids: after an ordinary id, every later step keeps it
# covered, and every later ordinary id's (timestamp, sequence) prefix is
# strictly greater, clock rollbacks included. Sequence exhaustion yields no id.
# The laws hold for every sequence limit; Uuid.advance is advanceWithin at
# upstream's 2^41-1. They are stated for the limit parameter because the
# checker cannot yet unfold a comparison with a large Nat constant (BEND-052).
def covers(state: Uuid.State, key: Uuid.Key) -> Bool:
  match state key:
    case Uuid.State{last, Some{sequence}} Uuid.Key{timestamp, issued}: Nat.is_le(timestamp, last) && Nat.is_le(issued, sequence)
    case Uuid.State{_, None{}} _: False{}

def before(earlier: Uuid.Key, later: Maybe<&2, Uuid.Key>) -> Bool:
  match earlier later:
    case _ None{}: True{}
    case Uuid.Key{+t1, s1} Some{Uuid.Key{+t2, s2}}: Nat.is_lt(t1, t2) || (Nat.is_eq(t1, t2) && Nat.is_lt(s1, s2))

def issuedCovered(result: Uuid.State & Maybe<&2, Uuid.Key>) -> Bool:
  match result:
    case Tuple{_, None{}}: True{}
    case Tuple{state, Some{key}}: covers(state, key)

def nextState(result: Uuid.State & Maybe<&2, Uuid.Key>) -> Uuid.State:
  match result:
    case Tuple{state, _}: state

def issued(result: Uuid.State & Maybe<&2, Uuid.Key>) -> Maybe<&2, Uuid.Key>:
  match result:
    case Tuple{_, key}: key

# An ordinary id is covered by the state it leaves, starting from any state.
law ordinary_key_covered:
  for +limit: Nat
  for +state: Uuid.State
  for +requested: Nat
  for +seed: Nat
  {issuedCovered(Uuid.advanceWithin(limit, state, requested, True{}, seed)) == True{} : Bool}

# No step, ordinary or follower, uncovers a key.
law advance_keeps_coverage:
  for +limit: Nat
  for +state: Uuid.State
  for +key: Uuid.Key
  for +covered: {covers(state, key) == True{} : Bool}
  for +requested: Nat
  for +ordinary: Bool
  for +seed: Nat
  {covers(nextState(Uuid.advanceWithin(limit, state, requested, ordinary, seed)), key) == True{} : Bool}

# An ordinary id sorts strictly after every covered key.
law ordinary_key_after_covered:
  for +limit: Nat
  for +state: Uuid.State
  for +key: Uuid.Key
  for +covered: {covers(state, key) == True{} : Bool}
  for +requested: Nat
  for +seed: Nat
  {before(key, issued(Uuid.advanceWithin(limit, state, requested, True{}, seed))) == True{} : Bool}
