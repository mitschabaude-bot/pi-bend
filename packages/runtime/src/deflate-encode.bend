import Base

# RFC1951 encoder: bounded LZ77 hash chains, fixed canonical Huffman codes,
# and stored blocks only when they are smaller. Production code is pure Bend.
# Complete-stream APIs bound serialized output; zlib framing counts toward it.
# Input uses indexed arrays and is limited to 2^31 bytes (InputLimit otherwise).
type Error is Data:
  InvalidByte{}
  InputLimit{}
  OutputLimit{}

type Token is Data:
  Literal{byte: U32}
  Copy{length: U32, distance: U32}

type Code is Data:
  Code{symbol: U32, extra: U32, value: U32}

def logarithm(fuel: Nat, +value: U32, +bits: U32) -> U32:
  match fuel:
    case 0n: bits
    case 1n+n: Bool.pick(Unit -> U32,U32.is_lt(value,2),_ => bits,_ => logarithm(n,U32.shr(value),(bits + 1 : U32)))(Unit{})

def lengthCode(+length: U32) -> Code:
  +adjusted = (length - 3 : U32)
  +extra = (logarithm(8n,adjusted,0) - 2 : U32)
  Bool.pick(Unit -> Code,U32.is_eq(length,258),_ => Code{285,0,0},_ =>
    Bool.pick(Unit -> Code,U32.is_le(length,10),_ => Code{(length + 254 : U32),0,0},_ =>
      Code{(257 + extra * 4 + U32.shrn(adjusted,U32.to_nat(extra)) : U32),extra,U32.and(adjusted,(U32.shln(1,U32.to_nat(extra)) - 1 : U32))})(Unit{}))(Unit{})

def distanceCode(+distance: U32) -> Code:
  +adjusted = (distance - 1 : U32)
  +extra = (logarithm(15n,adjusted,0) - 1 : U32)
  Bool.pick(Unit -> Code,U32.is_le(distance,4),_ => Code{adjusted,0,0},_ =>
    Code{(extra * 2 + U32.shrn(adjusted,U32.to_nat(extra)) : U32),extra,U32.and(adjusted,(U32.shln(1,U32.to_nat(extra)) - 1 : U32))})(Unit{})

def symbolBits(+symbol: U32) -> U32:
  Bool.pick(U32,U32.is_le(symbol,143),8,Bool.pick(U32,U32.is_le(symbol,255),9,Bool.pick(U32,U32.is_le(symbol,279),7,8)))

def copyBits(length: Code, distance: Code) -> Nat:
  match length distance:
    case Code{symbol,extra,_} Code{_,more,_}: U32.to_nat((symbolBits(symbol) + extra + 5 + more : U32))

def tokenBits(token: Token) -> Nat:
  match token:
    case Literal{byte}: U32.to_nat(symbolBits(byte))
    case Copy{length,distance}: copyBits(lengthCode(length),distanceCode(distance))

type Output is Data:
  Output{word: U32, bits: U32, reversed: List<&2,U32>}

def flushBytes(fuel: Nat, state: Output) -> Output:
  match fuel state:
    case 0n state: state
    case 1n+n Output{+word,+bits,+reversed}:
      Bool.pick(Unit -> Output,U32.is_lt(bits,8),_ => Output{word,bits,reversed},_ => flushBytes(n,Output{U32.shrn(word,8n),(bits - 8 : U32),U32.and(word,255) <> reversed}))(Unit{})

def put(value: U32, count: U32, state: Output) -> Output:
  match state:
    case Output{word,+bits,reversed}: flushBytes(3n,Output{U32.or(word,U32.shln(value,U32.to_nat(bits))),(bits + count : U32),reversed})

def reversedBits(count: Nat, +value: U32, accumulator: U32) -> U32:
  match count:
    case 0n: accumulator
    case 1n+n: reversedBits(n,U32.shr(value),U32.or(U32.shl(accumulator),U32.and(value,1)))

def fixedSymbol(+symbol: U32, state: Output) -> Output:
  +bits = symbolBits(symbol)
  +code = Bool.pick(U32,U32.is_le(symbol,143),(symbol + 48 : U32),Bool.pick(U32,U32.is_le(symbol,255),(symbol + 256 : U32),Bool.pick(U32,U32.is_le(symbol,279),(symbol - 256 : U32),(symbol - 88 : U32))))
  put(reversedBits(U32.to_nat(bits),code,0),bits,state)

def copyOutput(length: Code, distance: Code, state: Output) -> Output:
  match length distance:
    case Code{symbol,extra,value} Code{code,more,bits}:
      put(bits,more,put(reversedBits(5n,code,0),5,put(value,extra,fixedSymbol(symbol,state))))

def tokensOutput(tokens: List<&2,Token>, state: Output) -> Output:
  match tokens:
    case Nil{}: fixedSymbol(256,state)
    case Literal{byte} <> rest: tokensOutput(rest,fixedSymbol(byte,state))
    case Copy{length,distance} <> rest: tokensOutput(rest,copyOutput(lengthCode(length),distanceCode(distance),state))

def outputBytes(state: Output) -> List<&2,U32>:
  match state:
    case Output{_,0,reversed}: List.reverse(&2,U32,reversed)
    case Output{word,_,reversed}: List.reverse(&2,U32,word <> reversed)

def inputSize(bytes: List<&2,U32>, +count: U32) -> Result<&2,&2,Error,U32>:
  match bytes:
    case Nil{}: Done{count}
    case byte <> rest:
      Bool.pick(Unit -> Result<&2,&2,Error,U32>,U32.is_gt(byte,255),_ => Fail{InvalidByte{}},_ =>
        Bool.pick(Unit -> Result<&2,&2,Error,U32>,U32.is_eq(count,2147483648),_ => Fail{InputLimit{}},_ => inputSize(rest,(count + 1 : U32)))(Unit{}))(Unit{})

type Loaded is Type:
  Loaded{bytes: Array<U32>, size: U32, checksum: U32}

def load(bytes: List<&2,U32>, +position: U32, a: U32, b: U32, data: Array<U32>) -> Loaded:
  match bytes:
    case Nil{}: Loaded{data,position,U32.or(U32.shln(b,16n),a)}
    case +byte <> rest:
      +nextA = ((a + byte) % 65521 : U32)
      load(rest,(position + 1 : U32),nextA,((b + nextA) % 65521 : U32),Array.set(U32,data,position,byte))

type Store is Type:
  Store{bytes: Array<U32>, heads: Array<U32>, previous: Array<U32>}

type Hashed is Type:
  Hashed{store: Store, hash: U32}

def hashThird(a: U32, b: U32, heads: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Hashed:
  match fetched:
    case (bytes,c): Hashed{Store{bytes,heads,previous},U32.and(((a * 251 + b) * 251 + c : U32),32767)}

def hashSecond(+position: U32, a: U32, heads: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Hashed:
  match fetched:
    case (bytes,b): hashThird(a,b,heads,previous,Array.get(U32,bytes,(position + 2 : U32)))

def hashFirst(+position: U32, heads: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Hashed:
  match fetched:
    case (bytes,a): hashSecond(position,a,heads,previous,Array.get(U32,bytes,(position + 1 : U32)))

def hashAt(+position: U32, store: Store) -> Hashed:
  match store:
    case Store{bytes,heads,previous}: hashFirst(position,heads,previous,Array.get(U32,bytes,position))

def inserted(+position: U32, hash: U32, bytes: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Store:
  match fetched:
    case (heads,old): Store{bytes,Array.set(U32,heads,hash,(position + 1 : U32)),Array.set(U32,previous,U32.and(position,32767),old)}

def insertHash(position: U32, state: Hashed) -> Store:
  match state:
    case Hashed{Store{bytes,heads,previous},+hash}: inserted(position,hash,bytes,previous,Array.get(U32,heads,hash))

def insert(count: Nat, +position: U32, +size: U32, store: Store) -> Store:
  match count:
    case 0n: store
    case 1n+n:
      Bool.pick(Store -> Store,U32.is_le((position + 3 : U32),size),s => insert(n,(position + 1 : U32),size,insertHash(position,hashAt(position,s))),s => s)(store)

type Compared is Type:
  Compared{bytes: Array<U32>, length: U32, equal: Bool}

def comparedByte(+length: U32, first: U32, fetched: Array<U32> & U32) -> Compared:
  match fetched:
    case (bytes,second):
      +equal = U32.is_eq(first,second)
      Compared{bytes,Bool.pick(U32,equal,(length + 1 : U32),length),equal}

def comparedFirst(candidate: U32, +length: U32, fetched: Array<U32> & U32) -> Compared:
  match fetched:
    case (bytes,first): comparedByte(length,first,Array.get(U32,bytes,(candidate + length : U32)))

def compareBytes(count: Nat, +position: U32, +candidate: U32, state: Compared) -> Compared:
  match count state:
    case 0n state: state
    case _ Compared{bytes,length,False{}}: Compared{bytes,length,False{}}
    case 1n+n Compared{bytes,+length,True{}}: compareBytes(n,position,candidate,comparedFirst(candidate,length,Array.get(U32,bytes,(position + length : U32))))

type Search is Type:
  Search{store: Store, candidate: U32, length: U32, distance: U32}

def searchedNext(position: U32, +candidate: U32, +length: U32, +best: U32, distance: U32, bytes: Array<U32>, heads: Array<U32>, fetched: Array<U32> & U32) -> Search:
  match fetched:
    case (previous,next):
      +better = U32.is_gt(length,best)
      Search{Store{bytes,heads,previous},next,Bool.pick(U32,better,length,best),Bool.pick(U32,better,(position - candidate : U32),distance)}

def searchedLength(position: U32, +candidate: U32, best: U32, distance: U32, heads: Array<U32>, previous: Array<U32>, compared: Compared) -> Search:
  match compared:
    case Compared{bytes,length,_}: searchedNext(position,candidate,length,best,distance,bytes,heads,Array.get(U32,previous,U32.and(candidate,32767)))

def searchStep(+position: U32, +candidate: U32, maximum: U32, best: U32, distance: U32, store: Store) -> Search:
  match store:
    case Store{bytes,heads,previous}: searchedLength(position,candidate,best,distance,heads,previous,compareBytes(U32.to_nat(maximum),position,candidate,Compared{bytes,0,True{}}))

# Heads store position+1. Candidate links strictly decrease; a reused slot is
# never followed once its position falls outside the 32768-byte history window.
# The 32-candidate budget bounds search even for adversarial hash collisions.
def search(fuel: Nat, +position: U32, +maximum: U32, state: Search) -> Search:
  match fuel state:
    case 0n state: state
    case 1n+n Search{store,+candidate,+best,+distance}:
      Bool.pick(Store -> Search,U32.is_eq(candidate,0) || U32.is_gt((position + 1 - candidate : U32),32768) || U32.is_eq(best,maximum),
        s => Search{s,candidate,best,distance},s => search(n,position,maximum,searchStep(position,(candidate - 1 : U32),maximum,best,distance,s)))(store)

def searchHead(position: U32, maximum: U32, bytes: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Search:
  match fetched:
    case (heads,candidate): search(32n,position,maximum,Search{Store{bytes,heads,previous},candidate,2,0})

def searchHash(position: U32, maximum: U32, hashed: Hashed) -> Search:
  match hashed:
    case Hashed{Store{bytes,heads,previous},hash}: searchHead(position,maximum,bytes,previous,Array.get(U32,heads,hash))

type Encoded is Type:
  Encoded{store: Store, position: U32, tokens: List<&2,Token>, bits: Nat}

def literalToken(+position: U32, tokens: List<&2,Token>, bits: Nat, heads: Array<U32>, previous: Array<U32>, fetched: Array<U32> & U32) -> Encoded:
  match fetched:
    case (bytes,+byte): Encoded{Store{bytes,heads,previous},(position + 1 : U32),Literal{byte} <> tokens,bits + U32.to_nat(symbolBits(byte))}

def emitLiteral(+position: U32, tokens: List<&2,Token>, bits: Nat, store: Store) -> Encoded:
  match store:
    case Store{bytes,heads,previous}: literalToken(position,tokens,bits,heads,previous,Array.get(U32,bytes,position))

def chosen(found: Bool, +position: U32, size: U32, +length: U32, distance: U32, tokens: List<&2,Token>, bits: Nat, store: Store) -> Encoded:
  match found:
    case False{}: emitLiteral(position,tokens,bits,insert(1n,position,size,store))
    case True{}:
      +token = {Copy{length,distance} : Token}
      Encoded{insert(U32.to_nat(length),position,size,store),(position + length : U32),token <> tokens,bits + tokenBits(token)}

def selected(position: U32, size: U32, tokens: List<&2,Token>, bits: Nat, state: Search) -> Encoded:
  match state:
    case Search{store,_,+length,distance}: chosen(U32.is_ge(length,3),position,size,length,distance,tokens,bits,store)

def encodeStep(long: Bool, +position: U32, +size: U32, tokens: List<&2,Token>, bits: Nat, store: Store) -> Encoded:
  match long:
    case False{}: emitLiteral(position,tokens,bits,store)
    case True{}: selected(position,size,tokens,bits,searchHash(position,Bool.pick(U32,U32.is_gt((size - position : U32),258),258,(size - position : U32)),hashAt(position,store)))

type Progress is Type:
  Continue{encoded: Encoded}
  Complete{encoded: Encoded}

def advance(done: Bool, +size: U32, state: Encoded) -> Progress:
  match done state:
    case True{} state: Complete{state}
    case False{} Encoded{store,+position,tokens,bits}: Continue{encodeStep(U32.is_le((position + 3 : U32),size),position,size,tokens,bits,store)}

# Every token consumes at least one byte. Match length never exceeds remaining
# input, and insertion advances every consumed position, including overlap.
@unsafe def tokenize(+size: U32, state: Progress) -> Encoded:
  match state:
    case Complete{encoded}: encoded
    case Continue{Encoded{store,+position,tokens,bits}}: tokenize(size,advance(U32.is_eq(position,size),size,Encoded{store,position,tokens,bits}))

type Stored is Type:
  Stored{bytes: Array<U32>, position: U32, output: Output}

def storedByte(position: U32, output: Output, fetched: Array<U32> & U32) -> Stored:
  match fetched:
    case (bytes,value): Stored{bytes,(position + 1 : U32),put(value,8,output)}

def storedData(count: Nat, state: Stored) -> Stored:
  match count state:
    case 0n state: state
    case 1n+n Stored{bytes,+position,output}: storedData(n,storedByte(position,output,Array.get(U32,bytes,position)))

def storedBlock(+size: U32, +count: U32, state: Stored) -> Stored:
  match state:
    case Stored{bytes,+position,output}:
      +last = Bool.pick(U32,U32.is_eq((position + count : U32),size),1,0)
      storedData(U32.to_nat(count),Stored{bytes,position,put(U32.xor(count,65535),16,put(count,16,put(last,8,output)))})

def storedBlocks(count: Nat, +size: U32, state: Stored) -> List<&2,U32>:
  match count state:
    case 0n Stored{_,_,output}: outputBytes(output)
    case 1n+n Stored{bytes,+position,output}:
      storedBlocks(n,size,storedBlock(size,Bool.pick(U32,U32.is_gt((size - position : U32),65535),65535,(size - position : U32)),Stored{bytes,position,output}))

def finishBlock(fixed: Bool, size: U32, blocks: Nat, state: Encoded) -> List<&2,U32>:
  match fixed state:
    case True{} Encoded{_,_,tokens,_}: outputBytes(tokensOutput(List.reverse(&2,Token,tokens),put(3,3,Output{0,0,Nil{}})))
    case False{} Encoded{Store{bytes,_,_},_,_,_}: storedBlocks(blocks,size,Stored{bytes,0,Output{0,0,Nil{}}})

def finished(+size: U32, +limit: Nat, state: Encoded) -> Result<&2,&2,Error,List<&2,U32>>:
  match state:
    case Encoded{store,position,tokens,+bits}:
      +blocks = Bool.pick(Nat,U32.is_eq(size,0),1n,(U32.to_nat(size) + 65534n) / 65535n)
      +stored = U32.to_nat(size) + blocks * 5n
      +fixed = (bits + 7n) / 8n
      +useFixed = Nat.is_le(fixed,stored)
      Bool.pick(Encoded -> Result<&2,&2,Error,List<&2,U32>>,Nat.is_le(Bool.pick(Nat,useFixed,fixed,stored),limit),
        value => Done{finishBlock(useFixed,size,blocks,value)},_ => Fail{OutputLimit{}})(Encoded{store,position,tokens,bits})

def wrapped(zlib: Bool, checksum: U32, result: Result<&2,&2,Error,List<&2,U32>>) -> Result<&2,&2,Error,List<&2,U32>>:
  match zlib result:
    case _ Fail{error}: Fail{error}
    case False{} result: result
    case True{} Done{bytes}:
      +sum = checksum
      trailer = {U32.shrn(sum,24n) <> U32.and(U32.shrn(sum,16n),255) <> U32.and(U32.shrn(sum,8n),255) <> U32.and(sum,255) <> Nil{} : List<&2,U32>}
      Done{120 <> 1 <> List.reverse.go(&2,U32,List.reverse(&2,U32,bytes),trailer)}

def loaded(zlib: Bool, limit: Nat, state: Loaded) -> Result<&2,&2,Error,List<&2,U32>>:
  match state:
    case Loaded{bytes,+size,checksum}:
      wrapped(zlib,checksum,finished(size,limit,tokenize(size,Continue{Encoded{Store{bytes,Array.new(U32,15n,0),Array.new(U32,15n,0)},0,Nil{},10n}})))

def capacityDepth(fuel: Nat, +size: U32, +capacity: U32, +depth: Nat) -> Nat:
  match fuel:
    case 0n: depth
    case 1n+n: Bool.pick(Unit -> Nat,U32.is_ge(capacity,size),_ => depth,_ => capacityDepth(n,size,U32.shl(capacity),1n + depth))(Unit{})

def sized(zlib: Bool, bytes: List<&2,U32>, limit: Nat, result: Result<&2,&2,Error,U32>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{size}: loaded(zlib,limit,load(bytes,0,1,0,Array.new(U32,capacityDepth(31n,size,1,0n),0)))

def compressRaw(+bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  sized(False{},bytes,limit,inputSize(bytes,0))

def compressZlib(+bytes: List<&2,U32>, +limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  Bool.pick(Unit -> Result<&2,&2,Error,List<&2,U32>>,Nat.is_ge(limit,6n),_ => sized(True{},bytes,limit - 6n,inputSize(bytes,0)),_ => Fail{OutputLimit{}})(Unit{})
