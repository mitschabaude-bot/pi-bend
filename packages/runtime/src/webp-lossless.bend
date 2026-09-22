import Base
import ./image.bend as Image

# VP8L entropy coding and reversible color/predictor transforms. Pixels inside
# the codec use packed ARGB; only the public raster conversion uses RGBA.
type Error is Data:
  InvalidByte{}
  Truncated{}
  Signature{}
  Version{}
  PixelLimit{}
  Dimensions{}
  Huffman{}
  Cache{}
  BackReference{}
  Transform{}
  PaletteIndex{}

type Bits is Data: Bits{bytes: List<&2,U32>, word: U32, available: U32}
type Read<-A: Data> is Data: Read{value: A, bits: Bits}
def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
def Parser(-A: Data) -> Data: Parsed(Read<A>)

def bind(-A: Data, -B: Data, result: Parser(A), next: A -> Bits -> Parser(B)) -> Parser(B):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{value,bits}}: next(value)(bits)

def validBytes(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> +rest: Bool.pick(Unit -> Bool,U32.is_le(byte,255),_ => validBytes(rest),_ => False{})(Unit{})

def refill(fuel: Nat, +wanted: U32, bits: Bits) -> Bits:
  match fuel bits:
    case 0n bits: bits
    case _ Bits{Nil{},word,available}: Bits{Nil{},word,available}
    case 1n+n Bits{+byte <> +rest,+word,+available}:
      Bool.pick(Unit -> Bits,U32.is_ge(available,wanted),_ => Bits{byte <> rest,word,available},
        _ => refill(n,wanted,Bits{rest,U32.or(word,U32.shln(byte,U32.to_nat(available))),(available + 8 : U32)}))(Unit{})

def extracted(+wanted: U32, bits: Bits) -> Parser(U32):
  match bits:
    case Bits{bytes,+word,+available}:
      Bool.pick(Parser(U32),U32.is_ge(available,wanted),Done{Read{U32.and(word,(U32.shln(1,U32.to_nat(wanted)) - 1 : U32)),Bits{bytes,U32.shrn(word,U32.to_nat(wanted)),(available - wanted : U32)}}},Fail{Truncated{}})

# All VP8L fields fit in 24 bits; three refill bytes cannot overflow a U32.
def take(+wanted: U32, bits: Bits) -> Parser(U32): extracted(wanted,refill(3n,wanted,bits))

def zeros(count: Nat) -> List<&2,U32>:
  match count:
    case 0n: Nil{}
    case 1n+n: 0 <> zeros(n)

def item(index: Nat, values: List<&2,U32>) -> U32:
  match index values:
    case 0n value <> _: value
    case 1n+n _ <> rest: item(n,rest)
    case _ _: 0

def replace(index: Nat, value: U32, values: List<&2,U32>) -> List<&2,U32>:
  match index values:
    case 0n _ <> rest: value <> rest
    case 1n+n head <> rest: head <> replace(n,value,rest)
    case _ Nil{}: Nil{}

type Tree is Data:
  Empty{}
  Leaf{symbol: U32}
  Branch{left: Tree, right: Tree}

def inserted(left: Tree, result: Parsed(Tree)) -> Parsed(Tree):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{right}: Done{Branch{left,right}}

def insertedLeft(right: Tree, result: Parsed(Tree)) -> Parsed(Tree):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{left}: Done{Branch{left,right}}

def insert(length: Nat, +code: U32, +symbol: U32, tree: Tree) -> Parsed(Tree):
  match length tree:
    case 0n Empty{}: Done{Leaf{symbol}}
    case 0n _: Fail{Huffman{}}
    case _ Leaf{_}: Fail{Huffman{}}
    case 1n+ +n Empty{}:
      Bool.pick(Unit -> Parsed(Tree),U32.is_eq(U32.and(U32.shrn(code,n),1),0),_ => insertedLeft(Empty{},insert(n,code,symbol,Empty{})),_ => inserted(Empty{},insert(n,code,symbol,Empty{})))(Unit{})
    case 1n+ +n Branch{+left,+right}:
      Bool.pick(Unit -> Parsed(Tree),U32.is_eq(U32.and(U32.shrn(code,n),1),0),_ => insertedLeft(right,insert(n,code,symbol,left)),_ => inserted(left,insert(n,code,symbol,right)))(Unit{})

type Histogram is Data: Histogram{counts: List<&2,U32>, count: U32, last: U32}

def histogram(lengths: List<&2,U32>, +counts: List<&2,U32>, +count: U32, last: U32, +index: U32) -> Parsed(Histogram):
  match lengths:
    case Nil{}: Done{Histogram{counts,count,last}}
    case +length <> +rest:
      Bool.pick(Unit -> Parsed(Histogram),U32.is_le(length,15),
        _ => Bool.pick(Unit -> Parsed(Histogram),U32.is_eq(length,0),_ => histogram(rest,counts,count,last,(index + 1 : U32)),
          _ => histogram(rest,replace(U32.to_nat(length),(item(U32.to_nat(length),counts) + 1 : U32),counts),(count + 1 : U32),index,(index + 1 : U32)))(Unit{}),_ => Fail{Huffman{}})(Unit{})

def complete(counts: List<&2,U32>, available: U32) -> Bool:
  match counts:
    case Nil{}: U32.is_eq(available,0)
    case +count <> +rest:
      +next = (available * 2 : U32)
      Bool.pick(Unit -> Bool,U32.is_le(count,next),_ => complete(rest,(next - count : U32)),_ => False{})(Unit{})

def firstCodes(counts: List<&2,U32>, +code: U32, previous: U32) -> List<&2,U32>:
  match counts:
    case Nil{}: Nil{}
    case count <> rest:
      +next = ((code + previous) * 2 : U32)
      next <> firstCodes(rest,next,count)

type Build is Data: Build{next: List<&2,U32>, tree: Tree}

def built(next: List<&2,U32>, value: Parsed(Tree)) -> Parsed(Build):
  match value:
    case Fail{cause}: Fail{cause}
    case Done{tree}: Done{Build{next,tree}}

def install(lengths: List<&2,U32>, +symbol: U32, state: Parsed(Build)) -> Parsed(Tree):
  match lengths state:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{Build{_,tree}}: Done{tree}
    case 0 <> rest state: install(rest,(symbol + 1 : U32),state)
    case +length <> rest Done{Build{+next,tree}}:
      +code = item(U32.to_nat(length),next)
      install(rest,(symbol + 1 : U32),built(replace(U32.to_nat(length),(code + 1 : U32),next),insert(U32.to_nat(length),code,symbol,tree)))

def treeCounts(lengths: List<&2,U32>, result: Parsed(Histogram)) -> Parsed(Tree):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Histogram{_,1,symbol}}: Done{Leaf{symbol}}
    case Done{Histogram{_ <> +counts,_,_}}:
      Bool.pick(Unit -> Parsed(Tree),complete(counts,1),_ => install(lengths,0,Done{Build{0 <> firstCodes(counts,0,0),Empty{}}}),_ => Fail{Huffman{}})(Unit{})
    case _: Fail{Huffman{}}

def buildTree(+lengths: List<&2,U32>) -> Parsed(Tree): treeCounts(lengths,histogram(lengths,zeros(16n),0,0,0))

type Walk is Data: Walk{tree: Tree, bits: Bits}

def branch(left: Tree, right: Tree, result: Parser(U32)) -> Parsed(Walk):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{bit,bits}}: Done{Walk{Bool.pick(Tree,U32.is_eq(bit,0),left,right),bits}}

def walk(fuel: Nat, state: Parsed(Walk)) -> Parser(U32):
  match fuel state:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Walk{Leaf{symbol},bits}}: Done{Read{symbol,bits}}
    case 1n+n Done{Walk{Branch{left,right},bits}}: walk(n,branch(left,right,take(1,bits)))
    case _ _: Fail{Huffman{}}

def readSymbol(tree: Tree, bits: Bits) -> Parser(U32): walk(15n,Done{Walk{tree,bits}})

# The code-length alphabet is ordered by frequency in the WebP specification.
def codeOrder() -> List<&2,U32>: 17 <> 18 <> 0 <> 1 <> 2 <> 3 <> 4 <> 5 <> 16 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> 12 <> 13 <> 14 <> 15 <> Nil{}

def codeLengths(count: Nat, order: List<&2,U32>, lengths: List<&2,U32>, bits: Bits) -> Parser(List<&2,U32>):
  match count order:
    case 0n _: Done{Read{lengths,bits}}
    case 1n+n index <> rest: bind(U32,List<&2,U32>,take(3,bits),value => bits => codeLengths(n,rest,replace(U32.to_nat(index),value,lengths),bits))
    case _ _: Fail{Huffman{}}

def repeated(count: Nat, +value: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: reversed
    case 1n+n: repeated(n,value,value <> reversed)

type LengthState is Data: LengthState{remaining: U32, previous: U32, reversed: List<&2,U32>, bits: Bits}

def repeatLength(+remaining: U32, +previous: U32, reversed: List<&2,U32>, usePrevious: Bool, offset: U32, result: Parser(U32)) -> Parsed(LengthState):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{extra,bits}}:
      +count = (extra + offset : U32)
      Bool.pick(Unit -> Parsed(LengthState),U32.is_le(count,remaining),_ => Done{LengthState{(remaining - count : U32),previous,repeated(U32.to_nat(count),Bool.pick(U32,usePrevious,previous,0),reversed),bits}},_ => Fail{Huffman{}})(Unit{})

def lengthSymbol(+remaining: U32, +previous: U32, +reversed: List<&2,U32>, result: Parser(U32)) -> Parsed(LengthState):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{+symbol,+bits}}:
      Bool.pick(Unit -> Parsed(LengthState),U32.is_lt(symbol,16),
        _ => Done{LengthState{(remaining - 1 : U32),Bool.pick(U32,U32.is_eq(symbol,0),previous,symbol),symbol <> reversed,bits}},
        _ => Bool.pick(Unit -> Parsed(LengthState),U32.is_le(symbol,18),
          _ => repeatLength(remaining,previous,reversed,U32.is_eq(symbol,16),Bool.pick(U32,U32.is_eq(symbol,18),11,3),take(Bool.pick(U32,U32.is_eq(symbol,16),2,Bool.pick(U32,U32.is_eq(symbol,17),3,7)),bits)),_ => Fail{Huffman{}})(Unit{}))(Unit{})

def readCodeLengths(tokens: Nat, +tree: Tree, state: Parsed(LengthState)) -> Parser(List<&2,U32>):
  match tokens state:
    case _ Fail{cause}: Fail{cause}
    case _ Done{LengthState{0,_,reversed,bits}}: Done{Read{List.reverse(&2,U32,reversed),bits}}
    case 0n Done{LengthState{remaining,_,reversed,bits}}: Done{Read{List.reverse(&2,U32,repeated(U32.to_nat(remaining),0,reversed)),bits}}
    case 1n+n Done{LengthState{remaining,previous,reversed,bits}}: readCodeLengths(n,tree,lengthSymbol(remaining,previous,reversed,readSymbol(tree,bits)))

def treeRead(bits: Bits, result: Parsed(Tree)) -> Parser(Tree):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{tree}: Done{Read{tree,bits}}

def boundedLengths(+alphabet: U32, tree: Tree, +maximum: U32, bits: Bits) -> Parser(Tree):
  Bool.pick(Unit -> Parser(Tree),U32.is_le(maximum,alphabet),
    _ => bind(List<&2,U32>,Tree,readCodeLengths(U32.to_nat(maximum),tree,Done{LengthState{alphabet,8,Nil{},bits}}),values => bits => treeRead(bits,buildTree(values))),_ => Fail{Huffman{}})(Unit{})

def readLengths(+alphabet: U32, +tree: Tree, bits: Bits) -> Parser(Tree):
  bind(U32,Tree,take(1,bits),limited => bits =>
    Bool.pick(Bits -> Parser(Tree),U32.is_eq(limited,0),bits => boundedLengths(alphabet,tree,alphabet,bits),
      bits => bind(U32,Tree,take(3,bits),width => bits => bind(U32,Tree,take((2 + 2 * width : U32),bits),maximum => bits => boundedLengths(alphabet,tree,(maximum + 2 : U32),bits))))(bits))

def complexTree(alphabet: U32, value: Parser(List<&2,U32>)) -> Parser(Tree):
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Read{values,bits}}:
      bind(Tree,Tree,treeRead(bits,buildTree(values)),tree => bits => readLengths(alphabet,tree,bits))

def secondSymbol(+alphabet: U32, +first: U32, result: Parser(U32)) -> Parser(Tree):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{+second,bits}}:
      Bool.pick(Parser(Tree),U32.is_lt(first,alphabet) && U32.is_lt(second,alphabet) && Bool.not(U32.is_eq(first,second)),Done{Read{Branch{Leaf{first},Leaf{second}},bits}},Fail{Huffman{}})

def simpleTree(+alphabet: U32, bits: Bits) -> Parser(Tree):
  bind(U32,Tree,take(1,bits),two => bits => bind(U32,Tree,take(1,bits),wide => bits => bind(U32,Tree,take((1 + 7 * wide : U32),bits),+first => bits =>
    Bool.pick(Bits -> Parser(Tree),U32.is_eq(two,0),bits => Bool.pick(Parser(Tree),U32.is_lt(first,alphabet),Done{Read{Leaf{first},bits}},Fail{Huffman{}}),bits => secondSymbol(alphabet,first,take(8,bits)))(bits))))

def readTree(+alphabet: U32, bits: Bits) -> Parser(Tree):
  bind(U32,Tree,take(1,bits),simple => bits => Bool.pick(Bits -> Parser(Tree),U32.is_eq(simple,1),bits => simpleTree(alphabet,bits),
    bits => bind(U32,Tree,take(4,bits),count => bits => complexTree(alphabet,codeLengths(U32.to_nat((count + 4 : U32)),codeOrder(),zeros(19n),bits))))(bits))

type Group is Data: Group{green: Tree, red: Tree, blue: Tree, alpha: Tree, distance: Tree}

def readGroup(+cacheBits: U32, bits: Bits) -> Parser(Group):
  bind(Tree,Group,readTree((280 + Bool.pick(U32,U32.is_eq(cacheBits,0),0,U32.shln(1,U32.to_nat(cacheBits))) : U32),bits),green => bits =>
    bind(Tree,Group,readTree(256,bits),red => bits => bind(Tree,Group,readTree(256,bits),blue => bits => bind(Tree,Group,readTree(256,bits),alpha => bits =>
      bind(Tree,Group,readTree(40,bits),distance => bits => Done{Read{Group{green,red,blue,alpha,distance},bits}})))))

def readCache(bits: Bits) -> Parser(U32):
  bind(U32,U32,take(1,bits),present => bits => Bool.pick(Bits -> Parser(U32),U32.is_eq(present,0),bits => Done{Read{0,bits}},
    bits => bind(U32,U32,take(4,bits),+size => bits => Bool.pick(Parser(U32),U32.is_ge(size,1) && U32.is_le(size,11),Done{Read{size,bits}},Fail{Cache{}})))(bits))

def prefixDistance(+code: U32, +bits: Bits) -> Parser(U32):
  +extra = ((code - 2) / 2 : U32)
  Bool.pick(Unit -> Parser(U32),U32.is_lt(code,4),_ => Done{Read{(code + 1 : U32),bits}},
    _ => bind(U32,U32,take(extra,bits),value => bits => Done{Read{(U32.shln((2 + U32.and(code,1) : U32),U32.to_nat(extra)) + value + 1 : U32),bits}}))(Unit{})

# Plane distances encode a near-neighbor position before linear distances.
def planeOffset(code: U32) -> U32:
  match code:
    case 1: 264
    case 2: 9
    case 3: 265
    case 4: 263
    case 5: 520
    case 6: 10
    case 7: 521
    case 8: 519
    case 9: 266
    case 10: 262
    case 11: 522
    case 12: 518
    case 13: 776
    case 14: 11
    case 15: 777
    case 16: 775
    case 17: 267
    case 18: 261
    case 19: 778
    case 20: 774
    case 21: 523
    case 22: 517
    case 23: 1032
    case 24: 12
    case 25: 1033
    case 26: 1031
    case 27: 268
    case 28: 260
    case 29: 779
    case 30: 773
    case 31: 1034
    case 32: 1030
    case 33: 524
    case 34: 516
    case 35: 1288
    case 36: 1035
    case 37: 1029
    case 38: 780
    case 39: 772
    case 40: 13
    case 41: 1289
    case 42: 1287
    case 43: 269
    case 44: 259
    case 45: 1290
    case 46: 1286
    case 47: 525
    case 48: 515
    case 49: 1036
    case 50: 1028
    case 51: 1291
    case 52: 1285
    case 53: 781
    case 54: 771
    case 55: 1544
    case 56: 14
    case 57: 1545
    case 58: 1543
    case 59: 270
    case 60: 258
    case 61: 1546
    case 62: 1542
    case 63: 526
    case 64: 514
    case 65: 1292
    case 66: 1284
    case 67: 1037
    case 68: 1027
    case 69: 1547
    case 70: 1541
    case 71: 782
    case 72: 770
    case 73: 1800
    case 74: 15
    case 75: 1801
    case 76: 1799
    case 77: 1293
    case 78: 1283
    case 79: 271
    case 80: 257
    case 81: 1548
    case 82: 1540
    case 83: 1038
    case 84: 1026
    case 85: 1802
    case 86: 1798
    case 87: 527
    case 88: 513
    case 89: 1803
    case 90: 1797
    case 91: 783
    case 92: 769
    case 93: 1549
    case 94: 1539
    case 95: 1294
    case 96: 1282
    case 97: 16
    case 98: 1804
    case 99: 1796
    case 100: 1039
    case 101: 1025
    case 102: 272
    case 103: 528
    case 104: 1550
    case 105: 1538
    case 106: 784
    case 107: 1805
    case 108: 1795
    case 109: 1295
    case 110: 1281
    case 111: 1040
    case 112: 1806
    case 113: 1794
    case 114: 1551
    case 115: 1537
    case 116: 1296
    case 117: 1807
    case 118: 1793
    case 119: 1552
    case 120: 1808
    case _: 0

def planeDistance(width: U32, +code: U32) -> U32:
  +offset = planeOffset(code)
  U32.from_nat(Bool.pick(Nat,U32.is_gt(code,120),U32.to_nat((code - 120 : U32)),Nat.max(1n,U32.to_nat(U32.shrn(offset,8n)) * U32.to_nat(width) + U32.to_nat(U32.and(offset,255)) - 8n)))

type Action is Data:
  Literal{pixel: U32, bits: Bits}
  Copy{length: U32, distance: U32, bits: Bits}
  Cached{key: U32, bits: Bits}

def outcome(-A: Data, -B: Data, result: Parser(A), next: A -> Bits -> Parsed(B)) -> Parsed(B):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{value,bits}}: next(value)(bits)

def takeColor(red: Tree, blue: Tree, alpha: Tree, green: U32, bits: Bits) -> Parser(U32):
  bind(U32,U32,readSymbol(red,bits),r => bits => bind(U32,U32,readSymbol(blue,bits),b => bits => bind(U32,U32,readSymbol(alpha,bits),a => bits => Done{Read{U32.or(U32.shln(a,24n),U32.or(U32.shln(r,16n),U32.or(U32.shln(green,8n),b))),bits}})))

def literalAction(green: U32, red: Tree, blue: Tree, alpha: Tree, bits: Bits) -> Parsed(Action):
  outcome(U32,Action,takeColor(red,blue,alpha,green,bits),pixel => bits => Done{Literal{pixel,bits}})

def copyAction(width: U32, code: U32, distance: Tree, bits: Bits) -> Parsed(Action):
  outcome(U32,Action,prefixDistance(code,bits),count => bits => outcome(U32,Action,readSymbol(distance,bits),code => bits => outcome(U32,Action,prefixDistance(code,bits),distance => bits => Done{Copy{count,planeDistance(width,distance),bits}})))

def action(width: U32, group: Group, result: Parser(U32)) -> Parsed(Action):
  match group result:
    case _ Fail{cause}: Fail{cause}
    case Group{_,red,blue,alpha,distance} Done{Read{+green,+bits}}:
      Bool.pick(Unit -> Parsed(Action),U32.is_lt(green,256),
        _ => literalAction(green,red,blue,alpha,bits),
        _ => Bool.pick(Unit -> Parsed(Action),U32.is_lt(green,280),_ => copyAction(width,(green - 256 : U32),distance,bits),_ => Done{Cached{(green - 280 : U32),bits}})(Unit{}))(Unit{})

type Config is Data:
  Config{width: U32, count: U32, cacheBits: U32, metaBits: U32, metaWidth: U32}
type Tables is Type: Tables{meta: Array<U32>, groups: Array<Group>}
type Store is Type: Store{pixels: Array<U32>, cache: Array<U32>, tables: Tables}
type Stream is Type: Stream{store: Store, bits: Bits, index: U32}
type Selected is Type: Selected{store: Store, bits: Bits, index: U32, group: Group}
type Decoded is Type: Decoded{pixels: Array<U32>, bits: Bits}

def selectedGroup(pixels: Array<U32>, cache: Array<U32>, meta: Array<U32>, bits: Bits, index: U32, fetched: Array<Group> & Group) -> Selected:
  match fetched:
    case (groups,group): Selected{Store{pixels,cache,Tables{meta,groups}},bits,index,group}

def selectedMeta(pixels: Array<U32>, cache: Array<U32>, groups: Array<Group>, bits: Bits, index: U32, fetched: Array<U32> & U32) -> Selected:
  match fetched:
    case (meta,key): selectedGroup(pixels,cache,meta,bits,index,Array.get(Group,groups,key))

def selectGroup(config: Config, state: Stream) -> Selected:
  match config state:
    case Config{+width,_,_,+shift,metaWidth} Stream{Store{pixels,cache,Tables{meta,groups}},bits,+index}:
      cell = Bool.pick(U32,U32.is_eq(shift,0),0,(U32.shrn((index / width : U32),U32.to_nat(shift)) * metaWidth + U32.shrn((index % width : U32),U32.to_nat(shift)) : U32))
      selectedMeta(pixels,cache,groups,bits,index,Array.get(U32,meta,cell))

def putCache(bits: U32, +pixel: U32, cache: Array<U32>) -> Array<U32>:
  match bits:
    case 0: cache
    case count: Array.set(U32,cache,U32.shrn((506832829 * pixel : U32),U32.to_nat((32 - count : U32))),pixel)

def emitPixel(index: U32, +pixel: U32, cacheBits: U32, store: Store) -> Store:
  match store:
    case Store{pixels,cache,tables}: Store{Array.set(U32,pixels,index,pixel),putCache(cacheBits,pixel,cache),tables}

def copiedPixel(index: U32, cacheBits: U32, cache: Array<U32>, tables: Tables, fetched: Array<U32> & U32) -> Store:
  match fetched:
    case (pixels,pixel): emitPixel(index,pixel,cacheBits,Store{pixels,cache,tables})

def copyPixels(count: Nat, +distance: U32, +index: U32, +cacheBits: U32, store: Store) -> Store:
  match count store:
    case 0n store: store
    case 1n+n Store{pixels,cache,tables}:
      copyPixels(n,distance,(index + 1 : U32),cacheBits,copiedPixel(index,cacheBits,cache,tables,Array.get(U32,pixels,(index - distance : U32))))

def cachedPixel(+index: U32, cacheBits: U32, pixels: Array<U32>, tables: Tables, bits: Bits, fetched: Array<U32> & U32) -> Result<&2,&1,Error,Stream>:
  match fetched:
    case (cache,pixel): Done{Stream{emitPixel(index,pixel,cacheBits,Store{pixels,cache,tables}),bits,(index + 1 : U32)}}

def cachePixel(valid: Bool, key: U32, index: U32, cacheBits: U32, store: Store, bits: Bits) -> Result<&2,&1,Error,Stream>:
  match valid store:
    case False{} _: Fail{Cache{}}
    case True{} Store{pixels,cache,tables}: cachedPixel(index,cacheBits,pixels,tables,bits,Array.get(U32,cache,key))

def perform(+index: U32, config: Config, store: Store, result: Parsed(Action)) -> Result<&2,&1,Error,Stream>:
  match config result:
    case _ Fail{cause}: Fail{cause}
    case Config{_,_,cacheBits,_,_} Done{Literal{pixel,bits}}: Done{Stream{emitPixel(index,pixel,cacheBits,store),bits,(index + 1 : U32)}}
    case Config{_,count,cacheBits,_,_} Done{Copy{+length,+distance,bits}}:
      Bool.pick(Unit -> Result<&2,&1,Error,Stream>,U32.is_gt(distance,0) && U32.is_le(distance,index) && U32.is_le(length,(count - index : U32)),
        _ => Done{Stream{copyPixels(U32.to_nat(length),distance,index,cacheBits,store),bits,(index + length : U32)}},_ => Fail{BackReference{}})(Unit{})
    case Config{_,_,+cacheBits,_,_} Done{Cached{+key,bits}}: cachePixel(U32.is_gt(cacheBits,0) && U32.is_lt(key,U32.shln(1,U32.to_nat(cacheBits))),key,index,cacheBits,store,bits)

def entropyStep(+config: Config, selected: Selected) -> Result<&2,&1,Error,Stream>:
  match config selected:
    case Config{+width,count,cacheBits,metaBits,metaWidth} Selected{store,bits,index,Group{green,red,blue,alpha,distance}}:
      perform(index,Config{width,count,cacheBits,metaBits,metaWidth},store,action(width,Group{Empty{},red,blue,alpha,distance},readSymbol(green,bits)))

def finished(state: Stream) -> Result<&2,&1,Error,Decoded>:
  match state:
    case Stream{Store{pixels,_,_},bits,_}: Done{Decoded{pixels,bits}}

def entropy(fuel: Nat, +config: Config, state: Result<&2,&1,Error,Stream>) -> Result<&2,&1,Error,Decoded>:
  match fuel config state:
    case _ _ Fail{cause}: Fail{cause}
    case 0n Config{_,count,_,_,_} Done{Stream{store,bits,+index}}:
      Bool.pick(Unit -> Result<&2,&1,Error,Decoded>,U32.is_eq(index,count),_ => finished(Stream{store,bits,index}),_ => Fail{BackReference{}})(Unit{})
    case 1n+n Config{+width,+count,+cacheBits,+metaBits,+metaWidth} Done{Stream{store,+bits,+index}}:
      Bool.pick(Store -> Result<&2,&1,Error,Decoded>,U32.is_eq(index,count),store => finished(Stream{store,bits,index}),
        store => entropy(n,Config{width,count,cacheBits,metaBits,metaWidth},entropyStep(Config{width,count,cacheBits,metaBits,metaWidth},selectGroup(Config{width,count,cacheBits,metaBits,metaWidth},Stream{store,bits,index}))))(store)

def beginEntropy(+width: U32, height: U32, +cacheBits: U32, metaBits: U32, metaWidth: U32, tables: Tables, bits: Bits) -> Result<&2,&1,Error,Decoded>:
  +count = (width * height : U32)
  entropy(U32.to_nat(count),Config{width,count,cacheBits,metaBits,metaWidth},Done{Stream{Store{Array.new(U32,Image.depth(31n,count,1,0n),0),Array.new(U32,U32.to_nat(cacheBits),0),tables},bits,0}})

def singleGroup(width: U32, height: U32, cacheBits: U32, result: Parser(Group)) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{group,bits}}: beginEntropy(width,height,cacheBits,0,1,Tables{Array.new(U32,0n,0),Array.new(Group,0n,group)},bits)

def singleCache(width: U32, height: U32, result: Parser(U32)) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{+cacheBits,bits}}: singleGroup(width,height,cacheBits,readGroup(cacheBits,bits))

# Auxiliary predictor/color/palette/entropy images have no transforms or nested
# entropy image, so their grammar has bounded nesting independent of input.
def decodeAuxiliary(width: U32, height: U32, bits: Bits) -> Result<&2,&1,Error,Decoded>:
  singleCache(width,height,readCache(bits))

type Mapped is Type: Mapped{meta: Array<U32>, used: Array<U32>, maximum: U32}

def mapPixel(index: U32, used: Array<U32>, maximum: U32, fetched: Array<U32> & U32) -> Mapped:
  match fetched:
    case (meta,pixel):
      +group = U32.and(U32.shrn(pixel,8n),65535)
      Mapped{Array.set(U32,meta,index,group),Array.set(U32,used,group,1),U32.max(maximum,(group + 1 : U32))}

def mapGroups(count: Nat, +index: U32, state: Mapped) -> Mapped:
  match count state:
    case 0n state: state
    case 1n+n Mapped{meta,used,maximum}: mapGroups(n,(index + 1 : U32),mapPixel(index,used,maximum,Array.get(U32,meta,index)))

type GroupState is Type: GroupState{used: Array<U32>, groups: Array<Group>, bits: Bits}

def keptGroup(index: U32, group: Group, groups: Array<Group>, bits: Bits, fetched: Array<U32> & U32) -> GroupState:
  match fetched:
    case (used,keep):
      GroupState{used,Bool.pick(Array<Group> -> Array<Group>,U32.is_eq(keep,0),groups => groups,groups => Array.set(Group,groups,index,group))(groups),bits}

def parsedGroup(+index: U32, used: Array<U32>, groups: Array<Group>, result: Parser(Group)) -> Result<&2,&1,Error,GroupState>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{group,bits}}: Done{keptGroup(index,group,groups,bits,Array.get(U32,used,index))}

def readGroups(count: Nat, +index: U32, +cacheBits: U32, state: Result<&2,&1,Error,GroupState>) -> Result<&2,&1,Error,GroupState>:
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n state: state
    case 1n+n Done{GroupState{used,groups,bits}}: readGroups(n,(index + 1 : U32),cacheBits,parsedGroup(index,used,groups,readGroup(cacheBits,bits)))

def grouped(width: U32, height: U32, cacheBits: U32, metaBits: U32, metaWidth: U32, meta: Array<U32>, result: Result<&2,&1,Error,GroupState>) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{GroupState{_,groups,bits}}: beginEntropy(width,height,cacheBits,metaBits,metaWidth,Tables{meta,groups},bits)

def mapped(width: U32, height: U32, +cacheBits: U32, metaBits: U32, metaWidth: U32, bits: Bits, value: Mapped) -> Result<&2,&1,Error,Decoded>:
  match value:
    case Mapped{meta,used,maximum}:
      grouped(width,height,cacheBits,metaBits,metaWidth,meta,readGroups(U32.to_nat(maximum),0,cacheBits,Done{GroupState{used,Array.new(Group,16n,Group{Empty{},Empty{},Empty{},Empty{},Empty{}}),bits}}))

def subsample(size: U32, +bits: U32) -> U32: U32.shrn((size + U32.shln(1,U32.to_nat(bits)) - 1 : U32),U32.to_nat(bits))

def metaImage(+width: U32, +height: U32, cacheBits: U32, +metaBits: U32, result: Result<&2,&1,Error,Decoded>) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Decoded{pixels,bits}}:
      +metaWidth = subsample(width,metaBits)
      mapped(width,height,cacheBits,metaBits,metaWidth,bits,mapGroups(U32.to_nat(metaWidth) * U32.to_nat(subsample(height,metaBits)),0,Mapped{pixels,Array.new(U32,16n,0),1}))

def metaSize(+width: U32, +height: U32, cacheBits: U32, result: Parser(U32)) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{value,bits}}:
      +metaBits = (value + 2 : U32)
      metaImage(width,height,cacheBits,metaBits,decodeAuxiliary(subsample(width,metaBits),subsample(height,metaBits),bits))

def metaFlag(+width: U32, +height: U32, +cacheBits: U32, result: Parser(U32)) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{flag,+bits}}:
      Bool.pick(Unit -> Result<&2,&1,Error,Decoded>,U32.is_eq(flag,0),_ => singleGroup(width,height,cacheBits,readGroup(cacheBits,bits)),_ => metaSize(width,height,cacheBits,take(3,bits)))(Unit{})

def entropyImage(width: U32, height: U32, result: Parser(U32)) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{cacheBits,bits}}: metaFlag(width,height,cacheBits,take(1,bits))

# Reversible channel arithmetic is modulo256, independently for all four bytes.
def addPixels(+a: U32, +b: U32) -> U32:
  U32.or(U32.and((U32.and(a,16711935) + U32.and(b,16711935) : U32),16711935),U32.shln(U32.and((U32.and(U32.shrn(a,8n),16711935) + U32.and(U32.shrn(b,8n),16711935) : U32),16711935),8n))

def average(+a: U32, +b: U32) -> U32: (U32.and(a,b) + U32.shr(U32.and(U32.xor(a,b),4278124286)) : U32)

def byteAt(value: U32, shift: Nat) -> U32: U32.and(U32.shrn(value,shift),255)

def absolute(+a: U32, +b: U32) -> U32: Bool.pick(U32,U32.is_ge(a,b),(a - b : U32),(b - a : U32))

def colorDistance(+a: U32, +b: U32) -> U32:
  (absolute(byteAt(a,0n),byteAt(b,0n)) + absolute(byteAt(a,8n),byteAt(b,8n)) + absolute(byteAt(a,16n),byteAt(b,16n)) + absolute(byteAt(a,24n),byteAt(b,24n)) : U32)

def clampFull(a: U32, b: U32, +c: U32) -> U32:
  +sum = (a + b : U32)
  Bool.pick(U32,U32.is_lt(sum,c),0,U32.min(255,(sum - c : U32)))

def clampHalf(+a: U32, +b: U32) -> U32:
  +delta = ((b - a) / 2 : U32)
  Bool.pick(U32,U32.is_ge(a,b),U32.min(255,(a + (a - b) / 2 : U32)),Bool.pick(U32,U32.is_ge(a,delta),(a - delta : U32),0))

def clampPixel(full: Bool, +a: U32, +b: U32, +c: U32) -> U32:
  match full:
    case True{}: U32.or(clampFull(byteAt(a,0n),byteAt(b,0n),byteAt(c,0n)),U32.or(U32.shln(clampFull(byteAt(a,8n),byteAt(b,8n),byteAt(c,8n)),8n),U32.or(U32.shln(clampFull(byteAt(a,16n),byteAt(b,16n),byteAt(c,16n)),16n),U32.shln(clampFull(byteAt(a,24n),byteAt(b,24n),byteAt(c,24n)),24n))))
    case False{}: U32.or(clampHalf(byteAt(a,0n),byteAt(c,0n)),U32.or(U32.shln(clampHalf(byteAt(a,8n),byteAt(c,8n)),8n),U32.or(U32.shln(clampHalf(byteAt(a,16n),byteAt(c,16n)),16n),U32.shln(clampHalf(byteAt(a,24n),byteAt(c,24n)),24n))))

def predict(mode: U32, +left: U32, +top: U32, +topLeft: U32, +topRight: U32) -> Parsed(U32):
  match mode:
    case 0: Done{4278190080}
    case 1: Done{left}
    case 2: Done{top}
    case 3: Done{topRight}
    case 4: Done{topLeft}
    case 5: Done{average(average(left,topRight),top)}
    case 6: Done{average(left,topLeft)}
    case 7: Done{average(left,top)}
    case 8: Done{average(topLeft,top)}
    case 9: Done{average(top,topRight)}
    case 10: Done{average(average(left,topLeft),average(top,topRight))}
    case 11: Done{Bool.pick(U32,U32.is_lt(colorDistance(top,topLeft),colorDistance(left,topLeft)),left,top)}
    case 12: Done{clampPixel(True{},left,top,topLeft)}
    case 13: Done{clampPixel(False{},average(left,top),0,topLeft)}
    case _: Fail{Transform{}}

def signedByte(+value: U32) -> U32: Bool.pick(U32,U32.is_lt(value,128),value,(value - 256 : U32))
def delta(coefficient: U32, value: U32) -> U32: U32.shrn((signedByte(coefficient) * signedByte(value) : U32),5n)

def restoreColor(+pixel: U32, +coefficients: U32) -> U32:
  +green = byteAt(pixel,8n)
  +red = U32.and((byteAt(pixel,16n) + delta(byteAt(coefficients,0n),green) : U32),255)
  blue = U32.and((byteAt(pixel,0n) + delta(byteAt(coefficients,8n),green) + delta(byteAt(coefficients,16n),red) : U32),255)
  U32.or(U32.and(pixel,4278255360),U32.or(U32.shln(red,16n),blue))

def restoreGreen(+pixel: U32) -> U32:
  +green = byteAt(pixel,8n)
  U32.or(U32.and(pixel,4278255360),U32.or(U32.shln(U32.and((byteAt(pixel,16n) + green : U32),255),16n),U32.and((byteAt(pixel,0n) + green : U32),255)))

type Buffers is Type: Buffers{pixels: Array<U32>, auxiliary: Array<U32>}

def colorCell(index: U32, pixel: U32, pixels: Array<U32>, fetched: Array<U32> & U32) -> Buffers:
  match fetched:
    case (auxiliary,coefficients): Buffers{Array.set(U32,pixels,index,restoreColor(pixel,coefficients)),auxiliary}

def colorPixel(index: U32, cell: U32, auxiliary: Array<U32>, fetched: Array<U32> & U32) -> Buffers:
  match fetched:
    case (pixels,pixel): colorCell(index,pixel,pixels,Array.get(U32,auxiliary,cell))

def colorMap(count: Nat, +index: U32, +width: U32, +sizeBits: U32, +gridWidth: U32, state: Buffers) -> Buffers:
  match count state:
    case 0n state: state
    case 1n+n Buffers{pixels,auxiliary}:
      cell = (U32.shrn((index / width : U32),U32.to_nat(sizeBits)) * gridWidth + U32.shrn((index % width : U32),U32.to_nat(sizeBits)) : U32)
      colorMap(n,(index + 1 : U32),width,sizeBits,gridWidth,colorPixel(index,cell,auxiliary,Array.get(U32,pixels,index)))

def greenPixel(index: U32, fetched: Array<U32> & U32) -> Array<U32>:
  match fetched:
    case (pixels,pixel): Array.set(U32,pixels,index,restoreGreen(pixel))

def greenMap(count: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match count:
    case 0n: pixels
    case 1n+n: greenMap(n,(index + 1 : U32),greenPixel(index,Array.get(U32,pixels,index)))

type Samples is Type: Samples{pixels: Array<U32>, values: List<&2,U32>}

def gather(indices: List<&2,U32>, reversed: List<&2,U32>, fetched: Array<U32> & U32) -> Samples:
  match indices fetched:
    case Nil{} Tuple{pixels,value}: Samples{pixels,value <> reversed}
    case index <> rest Tuple{pixels,value}: gather(rest,value <> reversed,Array.get(U32,pixels,index))

def predicted(index: U32, residual: U32, pixels: Array<U32>, auxiliary: Array<U32>, result: Parsed(U32)) -> Result<&2,&1,Error,Buffers>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{value}: Done{Buffers{Array.set(U32,pixels,index,addPixels(residual,value)),auxiliary}}

def prediction(+index: U32, +width: U32, samples: Samples, fetched: Array<U32> & U32) -> Result<&2,&1,Error,Buffers>:
  match samples fetched:
    case Samples{pixels,right <> aboveLeft <> above <> left <> residual <> Nil{}} Tuple{auxiliary,mode}:
      selected = Bool.pick(U32,U32.is_eq(index,0),0,Bool.pick(U32,U32.is_lt(index,width),1,Bool.pick(U32,U32.is_eq((index % width : U32),0),2,byteAt(mode,8n))))
      predicted(index,residual,pixels,auxiliary,predict(selected,left,above,aboveLeft,right))
    case _ _: Fail{Transform{}}

def predictorPixel(+index: U32, +width: U32, cell: U32, state: Buffers) -> Result<&2,&1,Error,Buffers>:
  match state:
    case Buffers{pixels,auxiliary}:
      left = Bool.pick(U32,U32.is_eq(index,0),0,(index - 1 : U32))
      +above = Bool.pick(U32,U32.is_lt(index,width),0,(index - width : U32))
      aboveLeft = Bool.pick(U32,U32.is_eq(above,0),0,(above - 1 : U32))
      right = Bool.pick(U32,U32.is_lt(index,width),0,(above + 1 : U32))
      prediction(index,width,gather(left <> above <> aboveLeft <> right <> Nil{},Nil{},Array.get(U32,pixels,index)),Array.get(U32,auxiliary,cell))

def predictorMap(count: Nat, +index: U32, +width: U32, +sizeBits: U32, +gridWidth: U32, state: Result<&2,&1,Error,Buffers>) -> Result<&2,&1,Error,Buffers>:
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n state: state
    case 1n+n Done{buffers}:
      cell = (U32.shrn((index / width : U32),U32.to_nat(sizeBits)) * gridWidth + U32.shrn((index % width : U32),U32.to_nat(sizeBits)) : U32)
      predictorMap(n,(index + 1 : U32),width,sizeBits,gridWidth,predictorPixel(index,width,cell,buffers))

type PaletteState is Type: PaletteState{source: Array<U32>, table: Array<U32>, previous: U32}

def paletteDelta(index: U32, table: Array<U32>, previous: U32, fetched: Array<U32> & U32) -> PaletteState:
  match fetched:
    case (source,value):
      +pixel = addPixels(previous,value)
      PaletteState{source,Array.set(U32,table,index,pixel),pixel}

def paletteDeltas(count: Nat, +index: U32, state: PaletteState) -> Array<U32>:
  match count state:
    case 0n PaletteState{_,table,_}: table
    case 1n+n PaletteState{source,table,previous}: paletteDeltas(n,(index + 1 : U32),paletteDelta(index,table,previous,Array.get(U32,source,index)))

def packingBits(+size: U32) -> U32:
  Bool.pick(U32,U32.is_le(size,2),3,Bool.pick(U32,U32.is_le(size,4),2,Bool.pick(U32,U32.is_le(size,16),1,0)))

type Indexed is Type: Indexed{input: Array<U32>, table: Array<U32>, output: Array<U32>, packed: U32}

def paletteValue(index: U32, packed: U32, input: Array<U32>, output: Array<U32>, fetched: Array<U32> & U32) -> Indexed:
  match fetched:
    case (table,pixel): Indexed{input,table,Array.set(U32,output,index,pixel),packed}

def unpackIndex(index: U32, +bits: U32, state: Indexed) -> Indexed:
  match state:
    case Indexed{input,table,output,+packed}:
      key = U32.and(packed,(U32.shln(1,U32.to_nat(bits)) - 1 : U32))
      paletteValue(index,U32.shrn(packed,U32.to_nat(bits)),input,output,Array.get(U32,table,key))

def indexedByte(table: Array<U32>, output: Array<U32>, fetched: Array<U32> & U32) -> Indexed:
  match fetched:
    case (input,pixel): Indexed{input,table,output,byteAt(pixel,8n)}

def paletteByte(needed: Bool, index: U32, state: Indexed) -> Indexed:
  match needed state:
    case False{} state: state
    case True{} Indexed{input,table,output,_}: indexedByte(table,output,Array.get(U32,input,index))

def paletteMap(count: Nat, +index: U32, +width: U32, +packedWidth: U32, +packing: U32, +size: U32, state: Indexed) -> Array<U32>:
  match count state:
    case 0n Indexed{_,_,output,_}: output
    case 1n+n state:
      +x = (index % width : U32)
      +perByte = U32.shln(1,U32.to_nat(packing))
      source = ((index / width) * packedWidth + x / perByte : U32)
      paletteMap(n,(index + 1 : U32),width,packedWidth,packing,size,unpackIndex(index,U32.shrn(8,U32.to_nat(packing)),paletteByte(U32.is_eq((x % perByte : U32),0),source,state)))

type TransformSpec is Type:
  Predictor{width: U32, bits: U32, data: Array<U32>}
  Color{width: U32, bits: U32, data: Array<U32>}
  SubtractGreen{width: U32}
  Indexing{width: U32, size: U32, data: Array<U32>}

def bufferPixels(value: Buffers) -> Array<U32>:
  match value:
    case Buffers{pixels,_}: pixels

def predictorPixels(result: Result<&2,&1,Error,Buffers>) -> Result<&2,&1,Error,Array<U32>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{buffers}: Done{bufferPixels(buffers)}

def applyTransform(+height: U32, transform: TransformSpec, pixels: Array<U32>) -> Result<&2,&1,Error,Array<U32>>:
  match transform:
    case Predictor{+width,+bits,data}: predictorPixels(predictorMap(U32.to_nat(width) * U32.to_nat(height),0,width,bits,subsample(width,bits),Done{Buffers{pixels,data}}))
    case Color{+width,+bits,data}: Done{bufferPixels(colorMap(U32.to_nat(width) * U32.to_nat(height),0,width,bits,subsample(width,bits),Buffers{pixels,data}))}
    case SubtractGreen{width}: Done{greenMap(U32.to_nat(width) * U32.to_nat(height),0,pixels)}
    case Indexing{+width,+size,data}:
      +packing = packingBits(size)
      Done{paletteMap(U32.to_nat(width) * U32.to_nat(height),0,width,subsample(width,packing),packing,size,Indexed{pixels,paletteDeltas(U32.to_nat(size),0,PaletteState{data,Array.new(U32,8n,0),0}),Array.new(U32,Image.depth(31n,(width * height : U32),1,0n),0),0})}

def applyTransforms(transforms: List<TransformSpec>, +height: U32, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Array<U32>>:
  match transforms result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} result: result
    case transform <> rest Done{pixels}: applyTransforms(rest,height,applyTransform(height,transform,pixels))

type TransformRead is Type: TransformRead{width: U32, transform: TransformSpec, bits: Bits}

def transformedData(+width: U32, kind: U32, +extra: U32, result: Result<&2,&1,Error,Decoded>) -> Result<&2,&1,Error,TransformRead>:
  match kind result:
    case _ Fail{cause}: Fail{cause}
    case 0 Done{Decoded{pixels,bits}}: Done{TransformRead{width,Predictor{width,extra,pixels},bits}}
    case 1 Done{Decoded{pixels,bits}}: Done{TransformRead{width,Color{width,extra,pixels},bits}}
    case 3 Done{Decoded{pixels,bits}}: Done{TransformRead{subsample(width,packingBits(extra)),Indexing{width,extra,pixels},bits}}
    case _ _: Fail{Transform{}}

def transformSize(+width: U32, height: U32, +kind: U32, result: Parser(U32)) -> Result<&2,&1,Error,TransformRead>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{value,+bits}}:
      +extra = (value + Bool.pick(U32,U32.is_eq(kind,3),1,2) : U32)
      Bool.pick(Unit -> Result<&2,&1,Error,TransformRead>,U32.is_eq(kind,3),_ => transformedData(width,kind,extra,decodeAuxiliary(extra,1,bits)),
        _ => transformedData(width,kind,extra,decodeAuxiliary(subsample(width,extra),subsample(height,extra),bits)))(Unit{})

def readTransform(+width: U32, height: U32, +kind: U32, +bits: Bits) -> Result<&2,&1,Error,TransformRead>:
  Bool.pick(Unit -> Result<&2,&1,Error,TransformRead>,U32.is_eq(kind,2),_ => Done{TransformRead{width,SubtractGreen{width},bits}},
    _ => transformSize(width,height,kind,take(Bool.pick(U32,U32.is_eq(kind,3),8,3),bits)))(Unit{})

type Pipeline is Type: Pipeline{width: U32, transforms: List<TransformSpec>, bits: Bits, seen: U32}
type PipelineStep is Type:
  More{pipeline: Pipeline}
  Ready{pipeline: Pipeline}

def transformed(transforms: List<TransformSpec>, seen: U32, result: Result<&2,&1,Error,TransformRead>) -> Result<&2,&1,Error,PipelineStep>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{TransformRead{width,transform,bits}}: Done{More{Pipeline{width,transform <> transforms,bits,seen}}}

def transformKind(width: U32, height: U32, transforms: List<TransformSpec>, +seen: U32, result: Parser(U32)) -> Result<&2,&1,Error,PipelineStep>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{+kind,bits}}:
      +flag = U32.shln(1,U32.to_nat(kind))
      Bool.pick(Unit -> Result<&2,&1,Error,PipelineStep>,U32.is_eq(U32.and(seen,flag),0),_ => transformed(transforms,U32.or(seen,flag),readTransform(width,height,kind,bits)),_ => Fail{Transform{}})(Unit{})

def transformFlag(+width: U32, height: U32, transforms: List<TransformSpec>, +seen: U32, result: Parser(U32)) -> Result<&2,&1,Error,PipelineStep>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Read{flag,+bits}}:
      Bool.pick(List<TransformSpec> -> Result<&2,&1,Error,PipelineStep>,U32.is_eq(flag,0),transforms => Done{Ready{Pipeline{width,transforms,bits,seen}}},transforms => transformKind(width,height,transforms,seen,take(2,bits)))(transforms)

def readTransforms(fuel: Nat, +height: U32, state: Result<&2,&1,Error,PipelineStep>) -> Result<&2,&1,Error,Pipeline>:
  match fuel state:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Ready{pipeline}}: Done{pipeline}
    case 0n _: Fail{Transform{}}
    case 1n+n Done{More{Pipeline{width,transforms,bits,seen}}}: readTransforms(n,height,transformFlag(width,height,transforms,seen,take(1,bits)))

def restored(height: U32, transforms: List<TransformSpec>, result: Result<&2,&1,Error,Decoded>) -> Result<&2,&1,Error,Array<U32>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Decoded{pixels,_}}: applyTransforms(transforms,height,Done{pixels})

def decodePipeline(+height: U32, result: Result<&2,&1,Error,Pipeline>) -> Result<&2,&1,Error,Array<U32>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Pipeline{width,transforms,bits,_}}: restored(height,transforms,entropyImage(width,height,readCache(bits)))

# Headerless VP8L is used by compressed ALPH payloads in extended WebP.
def decodeStream(+width: U32, +height: U32, bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Array<U32>>:
  Bool.pick(Unit -> Result<&2,&1,Error,Array<U32>>,Image.validDimensions(width,height) && Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit),
    _ => decodePipeline(height,readTransforms(5n,height,Done{More{Pipeline{width,Nil{},Bits{bytes,0,0},0}}})),_ => Fail{PixelLimit{}})(Unit{})

# ALPH callers may use the headerless stream directly; retain the same octet
# validation at this public boundary as the complete VP8L payload API.
def decodeImplicit(+width: U32, +height: U32, +bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Array<U32>>:
  Bool.pick(Unit -> Result<&2,&1,Error,Array<U32>>,validBytes(bytes),_ => decodeStream(width,height,bytes,limit),_ => Fail{InvalidByte{}})(Unit{})

def rgbaPixel(index: U32, fetched: Array<U32> & U32) -> Array<U32>:
  match fetched:
    case (pixels,+argb): Array.set(U32,pixels,index,U32.or(U32.shln(argb,8n),U32.shrn(argb,24n)))

def rgba(count: Nat, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match count:
    case 0n: pixels
    case 1n+n: rgba(n,(index + 1 : U32),rgbaPixel(index,Array.get(U32,pixels,index)))

def raster(+width: U32, +height: U32, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{pixels}: Done{Image.Raster{width,height,rgba(U32.to_nat(width) * U32.to_nat(height),0,pixels)}}

def header(limit: Nat, bytes: List<&2,U32>) -> Result<&2,&1,Error,Image.Raster>:
  match bytes:
    case 47 <> a <> b <> c <> d <> rest:
      +word = U32.or(a,U32.or(U32.shln(b,8n),U32.or(U32.shln(c,16n),U32.shln(d,24n))))
      +width = (U32.and(word,16383) + 1 : U32)
      +height = (U32.and(U32.shrn(word,14n),16383) + 1 : U32)
      Bool.pick(Unit -> Result<&2,&1,Error,Image.Raster>,U32.is_eq(U32.shrn(word,29n),0),_ => raster(width,height,decodeStream(width,height,rest,limit)),_ => Fail{Version{}})(Unit{})
    case 47 <> _: Fail{Truncated{}}
    case _: Fail{Signature{}}

def decode(+bytes: List<&2,U32>, pixelLimit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  Bool.pick(Unit -> Result<&2,&1,Error,Image.Raster>,validBytes(bytes),_ => header(pixelLimit,bytes),_ => Fail{InvalidByte{}})(Unit{})
