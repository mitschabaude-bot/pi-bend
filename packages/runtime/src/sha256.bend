import Base

# Byte-oriented SHA-256, FIPS 180-4 sections 4.1.2, 4.2.2, 5 and 6.2.
# https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# State is immutable; update accepts only bytes and rejects length overflow.
type Digest is Data:
  Digest{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

type Words is Data:
  Words{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32, w8: U32, w9: U32, w10: U32, w11: U32, w12: U32, w13: U32, w14: U32, w15: U32}

type State is Data:
  State{hash: Digest, reversed: List<&2, U32>, used: U32, high: U32, low: U32}

type Error is Data:
  InvalidByte{value: U32}
  MessageTooLong{}
  InvalidState{}

type Loaded is Data:
  Loaded{words: Words, rest: List<&2, U32>}

def initial() -> Digest:
  Digest{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def create() -> State: State{initial(), Nil{}, 0, 0, 0}

def constants() -> List<&2, U32>:
  1116352408 <> 1899447441 <> 3049323471 <> 3921009573 <> 961987163 <> 1508970993 <> 2453635748 <> 2870763221 <> 3624381080 <> 310598401 <> 607225278 <> 1426881987 <> 1925078388 <> 2162078206 <> 2614888103 <> 3248222580 <> 3835390401 <> 4022224774 <> 264347078 <> 604807628 <> 770255983 <> 1249150122 <> 1555081692 <> 1996064986 <> 2554220882 <> 2821834349 <> 2952996808 <> 3210313671 <> 3336571891 <> 3584528711 <> 113926993 <> 338241895 <> 666307205 <> 773529912 <> 1294757372 <> 1396182291 <> 1695183700 <> 1986661051 <> 2177026350 <> 2456956037 <> 2730485921 <> 2820302411 <> 3259730800 <> 3345764771 <> 3516065817 <> 3600352804 <> 4094571909 <> 275423344 <> 430227734 <> 506948616 <> 659060556 <> 883997877 <> 958139571 <> 1322822218 <> 1537002063 <> 1747873779 <> 1955562222 <> 2024104815 <> 2227730452 <> 2361852424 <> 2428436474 <> 2756734187 <> 3204031479 <> 3329325298 <> Nil{}

def rotate(+x: U32, right: Nat, left: Nat) -> U32:
  U32.or(U32.shrn(x, right), U32.shln(x, left))

def small0(+x: U32) -> U32:
  U32.xor(U32.xor(rotate(x, 7n, 25n), rotate(x, 18n, 14n)), U32.shrn(x, 3n))

def small1(+x: U32) -> U32:
  U32.xor(U32.xor(rotate(x, 17n, 15n), rotate(x, 19n, 13n)), U32.shrn(x, 10n))

def big0(+x: U32) -> U32:
  U32.xor(U32.xor(rotate(x, 2n, 30n), rotate(x, 13n, 19n)), rotate(x, 22n, 10n))

def big1(+x: U32) -> U32:
  U32.xor(U32.xor(rotate(x, 6n, 26n), rotate(x, 11n, 21n)), rotate(x, 25n, 7n))

def choose(+x: U32, y: U32, z: U32) -> U32:
  U32.xor(U32.and(x, y), U32.and(U32.not(x), z))

def majority(+x: U32, +y: U32, +z: U32) -> U32:
  U32.xor(U32.xor(U32.and(x, y), U32.and(x, z)), U32.and(y, z))

def shift(words: Words, value: U32) -> Words:
  match words:
    case Words{_, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15}: Words{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, value}

def scheduled(words: Words) -> U32:
  match words:
    case Words{+w0, +w1, w2, w3, w4, w5, w6, w7, w8, +w9, w10, w11, w12, w13, +w14, w15}:
      (small1(w14) + w9 + small0(w1) + w0 : U32)

def first(words: Words) -> U32:
  match words:
    case Words{w0, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: w0

def round(work: Digest, k: U32, w: U32) -> Digest:
  match work:
    case Digest{+a, +b, +c, d, +e, +f, +g, h}:
      +t1 = (h + big1(e) + choose(e, f, g) + k + w : U32)
      t2 = (big0(a) + majority(a, b, c) : U32)
      Digest{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}

def rounds(keys: List<&2, U32>, +words: Words, work: Digest) -> Digest:
  match keys:
    case Nil{}: work
    case k <> rest: rounds(rest, shift(words, scheduled(words)), round(work, k, first(words)))

def add(left: Digest, right: Digest) -> Digest:
  match left right:
    case Digest{a, b, c, d, e, f, g, h} Digest{i, j, k, l, m, n, o, p}:
      Digest{(a + i : U32), (b + j : U32), (c + k : U32), (d + l : U32), (e + m : U32), (f + n : U32), (g + o : U32), (h + p : U32)}

def compress(+hash: Digest, words: Words) -> Digest:
  add(hash, rounds(constants(), words, hash))

def emptyWords() -> Words: Words{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

def load(bytes: List<&2, U32>, count: Nat, words: Words) -> Result<&2, &2, Error, Loaded>:
  match bytes count:
    case rest 0n: Done{Loaded{words, rest}}
    case a <> b <> c <> d <> rest 1n+left:
      load(rest, left, shift(words, (a * 16777216 + b * 65536 + c * 256 + d : U32)))
    case _ _: Fail{InvalidState{}}

def loadedBlock(hash: Digest, result: Loaded) -> Result<&2, &2, Error, Digest>:
  match result:
    case Loaded{words, Nil{}}: Done{compress(hash, words)}
    case _: Fail{InvalidState{}}

def block(hash: Digest, bytes: List<&2, U32>) -> Result<&2, &2, Error, Digest>:
  Result.bind(&2, &2, Error, Loaded, Digest, load(bytes, 16n, emptyWords()), loaded => loadedBlock(hash, loaded))

def buffered(hash: Digest, reversed: List<&2, U32>, used: U32, high: U32, low: U32) -> Result<&2, &2, Error, State>:
  match used:
    case 64:
      Result.bind(&2, &2, Error, Digest, State, block(hash, List.reverse(&2, U32, reversed)), next => Done{State{next, Nil{}, 0, high, low}})
    case amount: Done{State{hash, reversed, amount, high, low}}

def accepted(valid: Bool, hash: Digest, reversed: List<&2, U32>, used: U32, high: U32, low: U32) -> Result<&2, &2, Error, State>:
  match valid:
    case False{}: Fail{MessageTooLong{}}
    case True{}: buffered(hash, reversed, used, high, low)

def byte(valid: Bool, state: State, value: U32) -> Result<&2, &2, Error, State>:
  match valid state:
    case False{} _: Fail{InvalidByte{value}}
    case True{} State{hash, reversed, used, high, low}:
      +nextLow = (low + 1 : U32)
      +nextHigh = (high + Bool.pick(U32, U32.is_eq(nextLow, 0), 1, 0) : U32)
      accepted(U32.is_lt(nextHigh, 536870912), hash, value <> reversed, (used + 1 : U32), nextHigh, nextLow)

def feed(bytes: List<&2, U32>, result: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, State>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case +head <> tail Done{state}: feed(tail, byte(U32.is_le(head, 255), state, head))

def update(bytes: List<&2, U32>, state: State) -> Result<&2, &2, Error, State>:
  feed(bytes, Done{state})

def wordBytes(+value: U32) -> List<&2, U32>:
  U32.shrn(value, 24n) <> U32.and(U32.shrn(value, 16n), 255) <> U32.and(U32.shrn(value, 8n), 255) <> U32.and(value, 255) <> Nil{}

def zeros(count: Nat, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: 0 <> zeros(rest, tail)

def finalBlock(hash: Digest, loaded: Loaded) -> Result<&2, &2, Error, Digest>:
  match loaded:
    case Loaded{words, Nil{}}: Done{compress(hash, words)}
    case Loaded{words, rest}: block(compress(hash, words), rest)

def finishValid(valid: Bool, hash: Digest, reversed: List<&2, U32>, +used: U32, +high: U32, +low: U32) -> Result<&2, &2, Error, Digest>:
  match valid:
    case False{}: Fail{InvalidState{}}
    case True{}:
      pad = (Bool.pick(U32, U32.is_lt(used, 56), 55, 119) - used : U32)
      length = List.append(&2, U32, wordBytes(U32.or(U32.shln(high, 3n), U32.shrn(low, 29n))), wordBytes(U32.shln(low, 3n)))
      bytes = List.append(&2, U32, List.reverse(&2, U32, reversed), 128 <> zeros(U32.to_nat(pad), length))
      Result.bind(&2, &2, Error, Loaded, Digest, load(bytes, 16n, emptyWords()), loaded => finalBlock(hash, loaded))

def finish(state: State) -> Result<&2, &2, Error, Digest>:
  match state:
    case State{hash, reversed, +used, +high, low}:
      finishValid(U32.is_lt(used, 64) && U32.is_lt(high, 536870912), hash, reversed, used, high, low)

def digest(bytes: List<&2, U32>) -> Result<&2, &2, Error, Digest>:
  Result.bind(&2, &2, Error, State, Digest, update(bytes, create()), finish)

def toBytes(hash: Digest) -> List<&2, U32>:
  match hash:
    case Digest{a, b, c, d, e, f, g, h}:
      List.append(&2, U32, wordBytes(a), List.append(&2, U32, wordBytes(b), List.append(&2, U32, wordBytes(c), List.append(&2, U32, wordBytes(d), List.append(&2, U32, wordBytes(e), List.append(&2, U32, wordBytes(f), List.append(&2, U32, wordBytes(g), wordBytes(h))))))))
