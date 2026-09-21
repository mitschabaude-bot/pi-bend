import Base
import ./sha256.bend as SHA
import ./hmac-sha256.bend as HMAC

# RFC 5869. Empty salt is equivalent to the specified 32 zero bytes.
type Error is Data:
  Hash{error: SHA.Error}
  InvalidLength{length: U32}
  ShortKey{}

def hashResult(-A: Data, result: Result<&2, &2, SHA.Error, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{Hash{error}}

def extract(salt: List<&2, U32>, input: List<&2, U32>) -> Result<&2, &2, Error, SHA.Digest>:
  hashResult(SHA.Digest, HMAC.digest(salt, input))

def block(state: HMAC.State, previous: List<&2, U32>, info: List<&2, U32>, counter: U32) -> Result<&2, &2, Error, SHA.Digest>:
  hashResult(SHA.Digest,
    Result.bind(&2, &2, SHA.Error, HMAC.State, SHA.Digest, HMAC.update(previous, state), first =>
      Result.bind(&2, &2, SHA.Error, HMAC.State, SHA.Digest, HMAC.update(info, first), second =>
        Result.bind(&2, &2, SHA.Error, HMAC.State, SHA.Digest, HMAC.update(counter <> Nil{}, second), HMAC.finish))))

def blocks(count: Nat, +state: HMAC.State, +info: List<&2, U32>, previous: List<&2, U32>, +counter: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match count:
    case 0n: Done{List.reverse(&2, U32, reversed)}
    case 1n+rest:
      Result.bind(&2, &2, Error, SHA.Digest, List<&2, U32>, block(state, previous, info, counter), hash =>
        +bytes = SHA.toBytes(hash)
        blocks(rest, state, info, bytes, (counter + 1 : U32), List.append(&2, U32, List.reverse(&2, U32, bytes), reversed)))

def prefix(count: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match count bytes:
    case 0n _: List.reverse(&2, U32, reversed)
    case _ Nil{}: List.reverse(&2, U32, reversed)
    case 1n+rest head <> tail: prefix(rest, tail, head <> reversed)

def expanded(+length: U32, state: HMAC.State, info: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, blocks(U32.to_nat(((length + 31) / 32 : U32)), state, info, Nil{}, 1, Nil{}), bytes => Done{prefix(U32.to_nat(length), bytes, Nil{})})

def checked(validLength: Bool, validKey: Bool, key: List<&2, U32>, +info: List<&2, U32>, length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  match validLength validKey:
    case False{} _: Fail{InvalidLength{length}}
    case True{} False{}: Fail{ShortKey{}}
    case True{} True{}:
      Result.bind(&2, &2, Error, HMAC.State, List<&2, U32>, hashResult(HMAC.State, HMAC.create(key)), state =>
        Result.bind(&2, &2, Error, Unit, List<&2, U32>, hashResult(Unit, HMAC.validate(info)), unit => expanded(length, state, info)))

def expand(+key: List<&2, U32>, info: List<&2, U32>, +length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  checked(U32.is_le(length, 8160), HMAC.longer(key, 31n), key, info, length)

def derive(salt: List<&2, U32>, input: List<&2, U32>, info: List<&2, U32>, length: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, SHA.Digest, List<&2, U32>, extract(salt, input), key => expand(SHA.toBytes(key), info, length))
