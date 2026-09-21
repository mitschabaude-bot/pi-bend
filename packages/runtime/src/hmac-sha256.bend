import Base
import ./sha256.bend as SHA

# RFC 2104: immutable, reusable inner/outer prefix states.
type State is Data:
  State{inner: SHA.State, outer: SHA.State}

def longer(bytes: List<&2, U32>, remaining: Nat) -> Bool:
  match bytes remaining:
    case Nil{} _: False{}
    case _ <> _ 0n: True{}
    case _ <> rest 1n+left: longer(rest, left)

def pad(bytes: List<&2, U32>, count: Nat, +mask: U32) -> List<&2, U32>:
  match bytes count:
    case _ 0n: Nil{}
    case Nil{} 1n+left: mask <> pad(Nil{}, left, mask)
    case value <> rest 1n+left: U32.xor(value, mask) <> pad(rest, left, mask)

def validByte(valid: Bool, value: U32) -> Result<&2, &2, SHA.Error, Unit>:
  match valid:
    case False{}: Fail{SHA.InvalidByte{value}}
    case True{}: Done{Unit{}}

def validate(bytes: List<&2, U32>) -> Result<&2, &2, SHA.Error, Unit>:
  match bytes:
    case Nil{}: Done{Unit{}}
    case +head <> rest:
      Result.bind(&2, &2, SHA.Error, Unit, Unit, validByte(U32.is_le(head, 255), head), unit => validate(rest))

def prefixes(+key: List<&2, U32>) -> Result<&2, &2, SHA.Error, State>:
  Result.bind(&2, &2, SHA.Error, SHA.State, State, SHA.update(pad(key, 64n, 54), SHA.create()), inner =>
    Result.bind(&2, &2, SHA.Error, SHA.State, State, SHA.update(pad(key, 64n, 92), SHA.create()), outer => Done{State{inner, outer}}))

def prepare(isLong: Bool, +key: List<&2, U32>) -> Result<&2, &2, SHA.Error, State>:
  match isLong:
    case False{}: Result.bind(&2, &2, SHA.Error, Unit, State, validate(key), unit => prefixes(key))
    case True{}: Result.bind(&2, &2, SHA.Error, SHA.Digest, State, SHA.digest(key), hash => prefixes(SHA.toBytes(hash)))

def create(+key: List<&2, U32>) -> Result<&2, &2, SHA.Error, State>:
  prepare(longer(key, 64n), key)

def update(bytes: List<&2, U32>, state: State) -> Result<&2, &2, SHA.Error, State>:
  match state:
    case State{inner, outer}:
      Result.bind(&2, &2, SHA.Error, SHA.State, State, SHA.update(bytes, inner), next => Done{State{next, outer}})

def finish(state: State) -> Result<&2, &2, SHA.Error, SHA.Digest>:
  match state:
    case State{inner, outer}:
      Result.bind(&2, &2, SHA.Error, SHA.Digest, SHA.Digest, SHA.finish(inner), hash =>
        Result.bind(&2, &2, SHA.Error, SHA.State, SHA.Digest, SHA.update(SHA.toBytes(hash), outer), SHA.finish))

def digest(key: List<&2, U32>, bytes: List<&2, U32>) -> Result<&2, &2, SHA.Error, SHA.Digest>:
  Result.bind(&2, &2, SHA.Error, State, SHA.Digest, create(key), state =>
    Result.bind(&2, &2, SHA.Error, State, SHA.Digest, update(bytes, state), finish))
