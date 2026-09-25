import Base

# Native timing of the TLS client's secret-key crypto, without network or
# input parsing: `gcm N SIZE` seals and opens N records of SIZE bytes (each
# under a fresh key), `x25519 N` computes N public keys. Time with
# /usr/bin/time; see tests/parity/KNOWN.md for recorded numbers.
import ../packages/runtime/src/aes128.bend as AES
import ../packages/runtime/src/aes128-gcm.bend as GCM
import ../packages/runtime/src/x25519.bend as X

def bytes(count: Nat, +seed: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: bytes(rest, (seed * 1103515245 + 12345 : U32), U32.and(U32.shrn(seed, 16n), 255) <> tail)

def length(result: Result<&2, &2, GCM.Error, List<&2, U32>>) -> Nat:
  match result:
    case Done{text}: List.length(&2, U32, text)
    case Fail{_}: 0n

def roundTrip(key: GCM.GcmKey, sealed: Result<&2, &2, GCM.Error, GCM.Sealed>) -> Nat:
  match sealed:
    case Done{s}: length(GCM.open(key, GCM.Nonce{1, 2, 3}, 23 <> 3 <> 3 <> Nil{}, s))
    case Fail{_}: 0n

def gcm(count: Nat, +size: Nat, +seed: U32, total: Nat) -> Nat:
  match count:
    case 0n: total
    case 1n+rest:
      +key = GCM.key(AES.Block{seed, 2, 3, 4})
      gcm(rest, size, (seed + 1 : U32), Nat.add(total, roundTrip(key, GCM.seal(key, GCM.Nonce{1, 2, 3}, 23 <> 3 <> 3 <> Nil{}, bytes(size, seed, Nil{})))))

def first(result: Result<&2, &2, X.Error, List<&2, U32>>) -> U32:
  match result:
    case Done{b <> _}: b
    case _: 0

def x25519(count: Nat, +seed: U32, total: U32) -> U32:
  match count:
    case 0n: total
    case 1n+rest: x25519(rest, (seed + 1 : U32), (total + first(X.publicKey(bytes(32n, seed, Nil{}))) : U32))

def pickNat(value: Maybe<&2, Nat>) -> Nat:
  match value:
    case Some{n}: n
    case None{}: 0n

def readOr(text: String) -> Nat: pickNat(Nat.read(text))

def run(args: List<String>) -> String:
  match args:
    case "gcm" <> n <> size <> Nil{}: Nat.show(gcm(readOr(n), readOr(size), 1, 0n))
    case "x25519" <> n <> Nil{}: U32.show(x25519(readOr(n), 1, 0))
    case _: "usage"

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    IO.print(run(values))
