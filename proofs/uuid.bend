import Base
import ./absurd.bend as Absurd
import ../laws/uuid.bend as Laws
import ../packages/ai/src/utils/uuid.bend as Uuid

# Natural-number order lemmas, by induction on the Nat structure.
law le_refl:
  for +n: Nat
  {Nat.is_le(n, n) == True{} : Bool}

def le_refl(n):
  match n:
    case 0n: {==}
    case 1n+p: le_refl(p)

law le_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for ab: {Nat.is_le(a, b) == True{} : Bool}
  for bc: {Nat.is_le(b, c) == True{} : Bool}
  {Nat.is_le(a, c) == True{} : Bool}

def le_trans(a, b, c, ab, bc):
  match a b c:
    case 0n _ 0n: {==}
    case 0n _ 1n+_: {==}
    case 1n+_ 0n _: Empty.absurd({Nat.is_le(a, c) == True{} : Bool}, Absurd.false_is_not_true(ab))
    case 1n+_ 1n+_ 0n: Empty.absurd({Nat.is_le(a, c) == True{} : Bool}, Absurd.false_is_not_true(bc))
    case 1n+p 1n+q 1n+r: le_trans(p, q, r, ab, bc)

law le_succ:
  for +a: Nat
  for +b: Nat
  for ab: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_le(a, 1n+b) == True{} : Bool}

def le_succ(a, b, ab):
  match a b:
    case 0n _: {==}
    case 1n+_ 0n: Empty.absurd({Nat.is_le(a, 1n+b) == True{} : Bool}, Absurd.false_is_not_true(ab))
    case 1n+p 1n+q: le_succ(p, q, ab)

law le_lt_succ:
  for +a: Nat
  for +b: Nat
  for ab: {Nat.is_le(a, b) == True{} : Bool}
  {Nat.is_lt(a, 1n+b) == True{} : Bool}

def le_lt_succ(a, b, ab):
  match a b:
    case 0n _: {==}
    case 1n+_ 0n: Empty.absurd({Nat.is_lt(a, 1n+b) == True{} : Bool}, Absurd.false_is_not_true(ab))
    case 1n+p 1n+q: le_lt_succ(p, q, ab)

law pick_succ:
  for +c: Bool
  for +a: Nat
  for +b: Nat
  {1n+Bool.pick(Nat, c, a, b) == Bool.pick(Nat, c, 1n+a, 1n+b) : Nat}

def pick_succ(c, a, b):
  match c:
    case False{}: {==}
    case True{}: {==}

# The maximum bounds its second argument.
law max_upper:
  for +a: Nat
  for +b: Nat
  {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}

def max_upper(a, b):
  match a b:
    case 0n 0n: {==}
    case 0n 1n+q: le_refl(q)
    case 1n+_ 0n: {==}
    case 1n+p 1n+q:
      %pick_succ(Nat.is_lt(p, q), q, p) : {Nat.is_le(1n+q, _) == True{} : Bool}
      max_upper(p, q)

law and_left:
  for +x: Bool
  for +y: Bool
  for both: {x && y == True{} : Bool}
  {x == True{} : Bool}

def and_left(x, y, both):
  match x:
    case False{}: Empty.absurd({False{} == True{} : Bool}, Absurd.false_is_not_true(both))
    case True{}: {==}

law and_right:
  for +x: Bool
  for +y: Bool
  for both: {x && y == True{} : Bool}
  {y == True{} : Bool}

def and_right(x, y, both):
  match x:
    case False{}: Empty.absurd({y == True{} : Bool}, Absurd.false_is_not_true(both))
    case True{}: both

law both_true:
  for +x: Bool
  for +y: Bool
  for left: {x == True{} : Bool}
  for right: {y == True{} : Bool}
  {x && y == True{} : Bool}

def both_true(x, y, left, right):
  match x:
    case False{}: Empty.absurd({False{} && y == True{} : Bool}, Absurd.false_is_not_true(left))
    case True{}: right

# A key strictly precedes one with a later-or-equal timestamp and a larger sequence.
law precedes:
  for +t1: Nat
  for +s1: Nat
  for +t2: Nat
  for +s2: Nat
  for timestamps: {Nat.is_le(t1, t2) == True{} : Bool}
  for sequences: {Nat.is_lt(s1, s2) == True{} : Bool}
  {Laws.before(Uuid.Key{t1, s1}, Some{Uuid.Key{t2, s2}}) == True{} : Bool}

def precedes(t1, s1, t2, s2, timestamps, sequences):
  match t1 t2:
    case 0n 0n: sequences
    case 0n 1n+_: {==}
    case 1n+_ 0n: Empty.absurd({Laws.before(Uuid.Key{t1, s1}, Some{Uuid.Key{t2, s2}}) == True{} : Bool}, Absurd.false_is_not_true(timestamps))
    case 1n+p 1n+q: precedes(p, s1, q, s2, timestamps, sequences)

# The ordinary timestamp never falls below the recorded one.
law ordinary_timestamp_bound:
  for +t: Nat
  for +last: Nat
  for +requested: Nat
  for below: {Nat.is_le(t, last) == True{} : Bool}
  {Nat.is_le(t, Nat.max(requested, last)) == True{} : Bool}

def ordinary_timestamp_bound(t, last, requested, below):
  le_trans(t, last, Nat.max(requested, last), below, max_upper(requested, last))

# Case analysis on whether the sequence was exhausted.
law after_sequence:
  for +exhausted: Bool
  for +t: Nat
  for +s: Nat
  for +timestamp: Nat
  for +last: Nat
  for +sequence: Nat
  for timestamps: {Nat.is_le(t, timestamp) == True{} : Bool}
  for sequences: {Nat.is_le(s, sequence) == True{} : Bool}
  {Laws.before(Uuid.Key{t, s}, Laws.issued(Uuid.advanced(timestamp, last, Some{sequence}, Bool.pick(Maybe<&2, Nat>, exhausted, None{}, Some{1n+sequence})))) == True{} : Bool}

def after_sequence(exhausted, t, s, timestamp, last, sequence, timestamps, sequences):
  match exhausted:
    case True{}: {==}
    case False{}: precedes(t, s, timestamp, 1n+sequence, timestamps, le_lt_succ(s, sequence, sequences))

def Laws.ordinary_key_after_covered(limit, state, key, covered, requested, seed):
  match state key:
    case Uuid.State{_, None{}} _: Empty.absurd({Laws.before(key, Laws.issued(Uuid.advanceWithin(limit, state, requested, True{}, seed))) == True{} : Bool}, Absurd.false_is_not_true(covered))
    case Uuid.State{+last, Some{+sequence}} Uuid.Key{+t, +s}:
      after_sequence(Nat.is_eq(sequence, limit), t, s, Nat.max(requested, last), Nat.max(requested, last), sequence, ordinary_timestamp_bound(t, last, requested, and_left(Nat.is_le(t, last), Nat.is_le(s, sequence), covered)), and_right(Nat.is_le(t, last), Nat.is_le(s, sequence), covered))

# The state after any step, in both sequence outcomes.
law kept_after_sequence:
  for +exhausted: Bool
  for +t: Nat
  for +s: Nat
  for +recorded: Nat
  for +timestamp: Nat
  for +sequence: Nat
  for timestamps: {Nat.is_le(t, recorded) == True{} : Bool}
  for sequences: {Nat.is_le(s, sequence) == True{} : Bool}
  {Laws.covers(Laws.nextState(Uuid.advanced(timestamp, recorded, Some{sequence}, Bool.pick(Maybe<&2, Nat>, exhausted, None{}, Some{1n+sequence}))), Uuid.Key{t, s}) == True{} : Bool}

def kept_after_sequence(exhausted, t, s, recorded, timestamp, sequence, timestamps, sequences):
  match exhausted:
    case True{}: both_true(Nat.is_le(t, recorded), Nat.is_le(s, sequence), timestamps, sequences)
    case False{}: both_true(Nat.is_le(t, recorded), Nat.is_le(s, 1n+sequence), timestamps, le_succ(s, sequence, sequences))

law recorded_bound:
  for +ordinary: Bool
  for +t: Nat
  for +last: Nat
  for +requested: Nat
  for below: {Nat.is_le(t, last) == True{} : Bool}
  {Nat.is_le(t, Bool.pick(Nat, ordinary, Bool.pick(Nat, ordinary, Nat.max(requested, last), requested), last)) == True{} : Bool}

def recorded_bound(ordinary, t, last, requested, below):
  match ordinary:
    case True{}: ordinary_timestamp_bound(t, last, requested, below)
    case False{}: below

def Laws.advance_keeps_coverage(limit, state, key, covered, requested, ordinary, seed):
  match state key:
    case Uuid.State{_, None{}} _: Empty.absurd({Laws.covers(Laws.nextState(Uuid.advanceWithin(limit, state, requested, ordinary, seed)), key) == True{} : Bool}, Absurd.false_is_not_true(covered))
    case Uuid.State{+last, Some{+sequence}} Uuid.Key{+t, +s}:
      kept_after_sequence(Nat.is_eq(sequence, limit), t, s, Bool.pick(Nat, ordinary, Bool.pick(Nat, ordinary, Nat.max(requested, last), requested), last), Bool.pick(Nat, ordinary, Nat.max(requested, last), requested), sequence, recorded_bound(ordinary, t, last, requested, and_left(Nat.is_le(t, last), Nat.is_le(s, sequence), covered)), and_right(Nat.is_le(t, last), Nat.is_le(s, sequence), covered))

law covered_after_sequence:
  for +exhausted: Bool
  for +timestamp: Nat
  for +sequence: Nat
  {Laws.issuedCovered(Uuid.advanced(timestamp, timestamp, Some{sequence}, Bool.pick(Maybe<&2, Nat>, exhausted, None{}, Some{1n+sequence}))) == True{} : Bool}

def covered_after_sequence(exhausted, timestamp, sequence):
  match exhausted:
    case True{}: {==}
    case False{}: both_true(Nat.is_le(timestamp, timestamp), Nat.is_le(1n+sequence, 1n+sequence), le_refl(timestamp), le_refl(1n+sequence))

def Laws.ordinary_key_covered(limit, state, requested, seed):
  match state:
    case Uuid.State{+last, None{}}: both_true(Nat.is_le(Nat.max(requested, last), Nat.max(requested, last)), Nat.is_le(seed, seed), le_refl(Nat.max(requested, last)), le_refl(seed))
    case Uuid.State{+last, Some{+sequence}}: covered_after_sequence(Nat.is_eq(sequence, limit), Nat.max(requested, last), sequence)
