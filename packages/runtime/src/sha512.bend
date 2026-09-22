import Base
import ./u64.bend as W

# SHA-384 and SHA-512 share the FIPS180-4 64-bit compression function.
# https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# Byte counts use two U64 words; accepted messages are shorter than 2^128 bits.
type Variant is Data:
  Sha384{}
  Sha512{}

type Hash is Data:
  Hash{a: W.U64, b: W.U64, c: W.U64, d: W.U64, e: W.U64, f: W.U64, g: W.U64, h: W.U64}

type State is Data:
  State{variant: Variant, hash: Hash, reversed: List<&2,U32>, used: U32, high: W.U64, low: W.U64}

type Error is Data:
  InvalidByte{value: U32}
  MessageTooLong{}
  InvalidState{}

type Words is Data:
  Words{w0: W.U64, w1: W.U64, w2: W.U64, w3: W.U64, w4: W.U64, w5: W.U64, w6: W.U64, w7: W.U64, w8: W.U64, w9: W.U64, w10: W.U64, w11: W.U64, w12: W.U64, w13: W.U64, w14: W.U64, w15: W.U64}

type Loaded is Data:
  Loaded{words: Words, rest: List<&2,U32>}

# Initial words are the fractional square roots of primes1..8 (SHA512)
# and9..16 (SHA384). Round constants are fractional cube roots of primes1..80.
def initial(variant: Variant) -> Hash:
  match variant:
    case Sha384{}: Hash{W.U64{3418070365,3238371032},W.U64{1654270250,914150663},W.U64{2438529370,812702999},W.U64{355462360,4144912697},W.U64{1731405415,4290775857},W.U64{2394180231,1750603025},W.U64{3675008525,1694076839},W.U64{1203062813,3204075428}}
    case Sha512{}: Hash{W.U64{1779033703,4089235720},W.U64{3144134277,2227873595},W.U64{1013904242,4271175723},W.U64{2773480762,1595750129},W.U64{1359893119,2917565137},W.U64{2600822924,725511199},W.U64{528734635,4215389547},W.U64{1541459225,327033209}}

def create(+variant: Variant) -> State:
  State{variant,initial(variant),Nil{},0,W.zero(),W.zero()}

def constants() -> List<&2,W.U64>:
  W.U64{1116352408,3609767458} <>
  W.U64{1899447441,602891725} <>
  W.U64{3049323471,3964484399} <>
  W.U64{3921009573,2173295548} <>
  W.U64{961987163,4081628472} <>
  W.U64{1508970993,3053834265} <>
  W.U64{2453635748,2937671579} <>
  W.U64{2870763221,3664609560} <>
  W.U64{3624381080,2734883394} <>
  W.U64{310598401,1164996542} <>
  W.U64{607225278,1323610764} <>
  W.U64{1426881987,3590304994} <>
  W.U64{1925078388,4068182383} <>
  W.U64{2162078206,991336113} <>
  W.U64{2614888103,633803317} <>
  W.U64{3248222580,3479774868} <>
  W.U64{3835390401,2666613458} <>
  W.U64{4022224774,944711139} <>
  W.U64{264347078,2341262773} <>
  W.U64{604807628,2007800933} <>
  W.U64{770255983,1495990901} <>
  W.U64{1249150122,1856431235} <>
  W.U64{1555081692,3175218132} <>
  W.U64{1996064986,2198950837} <>
  W.U64{2554220882,3999719339} <>
  W.U64{2821834349,766784016} <>
  W.U64{2952996808,2566594879} <>
  W.U64{3210313671,3203337956} <>
  W.U64{3336571891,1034457026} <>
  W.U64{3584528711,2466948901} <>
  W.U64{113926993,3758326383} <>
  W.U64{338241895,168717936} <>
  W.U64{666307205,1188179964} <>
  W.U64{773529912,1546045734} <>
  W.U64{1294757372,1522805485} <>
  W.U64{1396182291,2643833823} <>
  W.U64{1695183700,2343527390} <>
  W.U64{1986661051,1014477480} <>
  W.U64{2177026350,1206759142} <>
  W.U64{2456956037,344077627} <>
  W.U64{2730485921,1290863460} <>
  W.U64{2820302411,3158454273} <>
  W.U64{3259730800,3505952657} <>
  W.U64{3345764771,106217008} <>
  W.U64{3516065817,3606008344} <>
  W.U64{3600352804,1432725776} <>
  W.U64{4094571909,1467031594} <>
  W.U64{275423344,851169720} <>
  W.U64{430227734,3100823752} <>
  W.U64{506948616,1363258195} <>
  W.U64{659060556,3750685593} <>
  W.U64{883997877,3785050280} <>
  W.U64{958139571,3318307427} <>
  W.U64{1322822218,3812723403} <>
  W.U64{1537002063,2003034995} <>
  W.U64{1747873779,3602036899} <>
  W.U64{1955562222,1575990012} <>
  W.U64{2024104815,1125592928} <>
  W.U64{2227730452,2716904306} <>
  W.U64{2361852424,442776044} <>
  W.U64{2428436474,593698344} <>
  W.U64{2756734187,3733110249} <>
  W.U64{3204031479,2999351573} <>
  W.U64{3329325298,3815920427} <>
  W.U64{3391569614,3928383900} <>
  W.U64{3515267271,566280711} <>
  W.U64{3940187606,3454069534} <>
  W.U64{4118630271,4000239992} <>
  W.U64{116418474,1914138554} <>
  W.U64{174292421,2731055270} <>
  W.U64{289380356,3203993006} <>
  W.U64{460393269,320620315} <>
  W.U64{685471733,587496836} <>
  W.U64{852142971,1086792851} <>
  W.U64{1017036298,365543100} <>
  W.U64{1126000580,2618297676} <>
  W.U64{1288033470,3409855158} <>
  W.U64{1501505948,4234509866} <>
  W.U64{1607167915,987167468} <>
  W.U64{1816402316,1246189591} <> Nil{}

# Compression rotates by fixed counts in1..63, never0/32. Split-word shifts
# avoid a per-bit loop while leaving the general U64 implementation unchanged.
def rotateSmall(value: W.U64, +right: Nat) -> W.U64:
  match value:
    case W.U64{+hi,+lo}:
      +left = Nat.sub(32n,right)
      W.U64{U32.or(U32.shrn(hi,right),U32.shln(lo,left)),U32.or(U32.shrn(lo,right),U32.shln(hi,left))}

def rotateWide(wide: Bool, value: W.U64, count: Nat) -> W.U64:
  match wide value:
    case True{} W.U64{hi,lo}: rotateSmall(W.U64{lo,hi},Nat.sub(count,32n))
    case False{} value: rotateSmall(value,count)

def rotate(value: W.U64, +count: Nat) -> W.U64:
  rotateWide(Nat.is_ge(count,32n),value,count)

# Used only for the compression function's logical shifts by6/7.
def shiftRight(value: W.U64, +count: Nat) -> W.U64:
  match value:
    case W.U64{+hi,lo}: W.U64{U32.shrn(hi,count),U32.or(U32.shrn(lo,count),U32.shln(hi,Nat.sub(32n,count)))}

def small0(+x: W.U64) -> W.U64: W.bitXor(W.bitXor(rotate(x,1n),rotate(x,8n)),shiftRight(x,7n))
def small1(+x: W.U64) -> W.U64: W.bitXor(W.bitXor(rotate(x,19n),rotate(x,61n)),shiftRight(x,6n))
def big0(+x: W.U64) -> W.U64: W.bitXor(W.bitXor(rotate(x,28n),rotate(x,34n)),rotate(x,39n))
def big1(+x: W.U64) -> W.U64: W.bitXor(W.bitXor(rotate(x,14n),rotate(x,18n)),rotate(x,41n))
def choose(+x: W.U64, y: W.U64, z: W.U64) -> W.U64: W.bitXor(W.bitAnd(x,y),W.bitAnd(W.bitNot(x),z))
def majority(+x: W.U64, +y: W.U64, +z: W.U64) -> W.U64: W.bitXor(W.bitXor(W.bitAnd(x,y),W.bitAnd(x,z)),W.bitAnd(y,z))

# A rolling window holds the next sixteen words. Advancing computes one
# schedule word directly from offsets 0, 1, 9 and 14, without indexed lists.
def shift(words: Words, value: W.U64) -> Words:
  match words:
    case Words{_,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,w15}:
      Words{w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,w15,value}

def scheduled(words: Words) -> W.U64:
  match words:
    case Words{w0,w1,_,_,_,_,_,_,_,w9,_,_,_,_,w14,_}:
      W.add(W.add(small1(w14),w9),W.add(small0(w1),w0))

def first(words: Words) -> W.U64:
  match words:
    case Words{w0,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: w0

def round(work: Hash, k: W.U64, w: W.U64) -> Hash:
  match work:
    case Hash{+a,+b,+c,d,+e,+f,+g,h}:
      +t1 = W.add(W.add(W.add(h,big1(e)),choose(e,f,g)),W.add(k,w))
      t2 = W.add(big0(a),majority(a,b,c))
      Hash{W.add(t1,t2),a,b,c,W.add(d,t1),e,f,g}

# After 64 extensions, the last sixteen words are already in the window.
def finalRounds(keys: List<&2,W.U64>, +words: Words, work: Hash) -> Hash:
  match keys:
    case Nil{}: work
    case k <> rest: finalRounds(rest,shift(words,W.zero()),round(work,k,first(words)))

def rounds(count: Nat, keys: List<&2,W.U64>, +words: Words, work: Hash) -> Hash:
  match count keys:
    case 0n keys: finalRounds(keys,words,work)
    case 1n+n k <> rest: rounds(n,rest,shift(words,scheduled(words)),round(work,k,first(words)))
    case _ Nil{}: work

def add(left: Hash, right: Hash) -> Hash:
  match left right:
    case Hash{a,b,c,d,e,f,g,h} Hash{i,j,k,l,m,n,o,p}: Hash{W.add(a,i),W.add(b,j),W.add(c,k),W.add(d,l),W.add(e,m),W.add(f,n),W.add(g,o),W.add(h,p)}

def compress(+hash: Hash, words: Words) -> Hash:
  add(hash,rounds(64n,constants(),words,hash))

def emptyWords() -> Words:
  Words{W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero(),W.zero()}

def pack(a: U32,b: U32,c: U32,d: U32) -> U32: (a * 16777216 + b * 65536 + c * 256 + d : U32)

def load(bytes: List<&2,U32>, count: Nat, words: Words) -> Result<&2,&2,Error,Loaded>:
  match bytes count:
    case rest 0n: Done{Loaded{words,rest}}
    case a <> b <> c <> d <> e <> f <> g <> h <> rest 1n+left:
      load(rest,left,shift(words,W.U64{pack(a,b,c,d),pack(e,f,g,h)}))
    case _ _: Fail{InvalidState{}}

def loadedBlock(hash: Hash, loaded: Loaded) -> Result<&2,&2,Error,Hash>:
  match loaded:
    case Loaded{words,Nil{}}: Done{compress(hash,words)}
    case _: Fail{InvalidState{}}

def block(hash: Hash, bytes: List<&2,U32>) -> Result<&2,&2,Error,Hash>:
  Result.bind(&2,&2,Error,Loaded,Hash,load(bytes,16n,emptyWords()), loaded => loadedBlock(hash,loaded))

def buffered(variant: Variant, hash: Hash, reversed: List<&2,U32>, used: U32, high: W.U64, low: W.U64) -> Result<&2,&2,Error,State>:
  match used:
    case 128:
      Result.bind(&2,&2,Error,Hash,State,block(hash,List.reverse(&2,U32,reversed)), next => Done{State{variant,next,Nil{},0,high,low}})
    case amount: Done{State{variant,hash,reversed,amount,high,low}}

def validLength(high: W.U64) -> Bool:
  match high:
    case W.U64{hi,_}: U32.is_lt(hi,536870912)

def accepted(valid: Bool, variant: Variant, hash: Hash, reversed: List<&2,U32>, used: U32, high: W.U64, low: W.U64) -> Result<&2,&2,Error,State>:
  match valid:
    case False{}: Fail{MessageTooLong{}}
    case True{}: buffered(variant,hash,reversed,used,high,low)

def byte(valid: Bool, state: State, value: U32) -> Result<&2,&2,Error,State>:
  match valid state:
    case False{} _: Fail{InvalidByte{value}}
    case True{} State{variant,hash,reversed,used,high,low}:
      +nextLow = W.add(low,W.one())
      +nextHigh = W.add(high,W.fromU32(Bool.pick(U32,W.equal(nextLow,W.zero()),1,0)))
      accepted(validLength(nextHigh),variant,hash,value <> reversed,(used + 1 : U32),nextHigh,nextLow)

def feed(bytes: List<&2,U32>, result: Result<&2,&2,Error,State>) -> Result<&2,&2,Error,State>:
  match bytes result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} result: result
    case +head <> rest Done{state}: feed(rest,byte(U32.is_le(head,255),state,head))

def update(bytes: List<&2,U32>, state: State) -> Result<&2,&2,Error,State>: feed(bytes,Done{state})

def bytes32(+value: U32) -> List<&2,U32>:
  U32.shrn(value,24n) <> U32.and(U32.shrn(value,16n),255) <> U32.and(U32.shrn(value,8n),255) <> U32.and(value,255) <> Nil{}

def bytes64(value: W.U64) -> List<&2,U32>:
  match value:
    case W.U64{hi,lo}: List.append(&2,U32,bytes32(hi),bytes32(lo))

def is384(variant: Variant) -> Bool:
  match variant:
    case Sha384{}: True{}
    case Sha512{}: False{}

def output(variant: Variant, hash: Hash) -> List<&2,U32>:
  match hash:
    case Hash{a,b,c,d,e,f,g,h}:
      tail = Bool.pick(List<&2,U32>,is384(variant),Nil{},List.append(&2,U32,bytes64(g),bytes64(h)))
      List.append(&2,U32,bytes64(a),List.append(&2,U32,bytes64(b),List.append(&2,U32,bytes64(c),List.append(&2,U32,bytes64(d),List.append(&2,U32,bytes64(e),List.append(&2,U32,bytes64(f),tail))))))

def zeros(count: Nat, tail: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: tail
    case 1n+rest: 0 <> zeros(rest,tail)

def finalBlock(hash: Hash, loaded: Loaded) -> Result<&2,&2,Error,Hash>:
  match loaded:
    case Loaded{words,Nil{}}: Done{compress(hash,words)}
    case Loaded{words,rest}: block(compress(hash,words),rest)

def finishValid(valid: Bool, variant: Variant, hash: Hash, reversed: List<&2,U32>, +used: U32, high: W.U64, +low: W.U64) -> Result<&2,&2,Error,List<&2,U32>>:
  match valid:
    case False{}: Fail{InvalidState{}}
    case True{}:
      pad = (Bool.pick(U32,U32.is_lt(used,112),111,239) - used : U32)
      length = List.append(&2,U32,bytes64(W.bitOr(W.shiftLeft(high,3n),W.shiftRight(low,61n))),bytes64(W.shiftLeft(low,3n)))
      bytes = List.append(&2,U32,List.reverse(&2,U32,reversed),128 <> zeros(U32.to_nat(pad),length))
      Result.bind(&2,&2,Error,Loaded,List<&2,U32>,load(bytes,16n,emptyWords()), loaded =>
        Result.bind(&2,&2,Error,Hash,List<&2,U32>,finalBlock(hash,loaded), final => Done{output(variant,final)}))

def finish(state: State) -> Result<&2,&2,Error,List<&2,U32>>:
  match state:
    case State{variant,hash,reversed,+used,+high,low}: finishValid(U32.is_lt(used,128) && validLength(high),variant,hash,reversed,used,high,low)

def digest(variant: Variant, bytes: List<&2,U32>) -> Result<&2,&2,Error,List<&2,U32>>:
  Result.bind(&2,&2,Error,State,List<&2,U32>,update(bytes,create(variant)),finish)
