import Base

# RFC1950/1951 decompression. Input/output octets are U32 values in [0,255].
# The decoder is pure: its 32-KiB ring and decode tables are affine arrays.
# inflateRaw / inflateZlib decode exactly one complete stream, rejecting trailing
# bytes and any output larger than limit. Preset dictionaries are unsupported
# (DictionaryRequired); final-byte padding is ignored as RFC1951 permits.
type TreeKind is Data:
  CodeLengths{}
  Literals{}
  Distances{}

type Error is Data:
  InvalidByte{}
  UnexpectedEnd{}
  InvalidHeader{}
  HeaderCheck{}
  DictionaryRequired{}
  InvalidBlock{}
  StoredLength{}
  Oversubscribed{tree: TreeKind}
  IncompleteTree{tree: TreeKind}
  MissingEndCode{}
  InvalidCode{}
  InvalidRepeat{}
  ReservedSymbol{}
  InvalidDistance{distance: U32, available: U32}
  OutputLimit{}
  Checksum{expected: U32, actual: U32}
  TrailingData{}

type Bits is Data:
  Bits{bytes: List<&2,U32>, word: U32, available: U32}

type Read is Data:
  Read{value: U32, bits: Bits}

# At most two refill bytes are needed for the largest request (16 bits).
# Low reservoir bits are next on the wire; Huffman codes reverse this order.
def refill(fuel: Nat, +wanted: U32, bits: Bits) -> Bits:
  match fuel bits:
    case 0n bits: bits
    case _ Bits{Nil{},word,available}: Bits{Nil{},word,available}
    case 1n+n Bits{+byte <> +rest,+word,+available}:
      Bool.pick(Unit -> Bits,U32.is_ge(available,wanted),
        _ => Bits{byte <> rest,word,available},
        _ => refill(n,wanted,Bits{rest,U32.or(word,U32.shln(byte,U32.to_nat(available))),(available + 8 : U32)}))(Unit{})

def extracted(+wanted: U32, bits: Bits) -> Result<&2,&2,Error,Read>:
  match bits:
    case Bits{bytes,+word,+available}:
      Bool.pick(Result<&2,&2,Error,Read>,U32.is_ge(available,wanted),
        Done{Read{U32.and(word,(U32.shln(1,U32.to_nat(wanted)) - 1 : U32)),Bits{bytes,U32.shrn(word,U32.to_nat(wanted)),(available - wanted : U32)}}},Fail{UnexpectedEnd{}})

def take(+wanted: U32, bits: Bits) -> Result<&2,&2,Error,Read>: extracted(wanted,refill(2n,wanted,bits))

def align(bits: Bits) -> Bits:
  match bits:
    case Bits{bytes,word,+available}:
      +padding = U32.and(available,7)
      Bits{bytes,U32.shrn(word,U32.to_nat(padding)),(available - padding : U32)}

def atEnd(bits: Bits) -> Bool:
  match bits:
    case Bits{Nil{},_,0}: True{}
    case _: False{}

def validBytes(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case byte <> rest: Bool.pick(Unit -> Bool,U32.is_le(byte,255),_ => validBytes(rest),_ => False{})(Unit{})

type Output is Type:
  Output{ring: Array<U32>, position: U32, history: U32, remaining: Nat, reversed: List<&2,U32>, a: U32, b: U32, window: U32}

type Decoded is Type:
  Decoded{bits: Bits, output: Output}

# The ring holds the last min(total output,32768) bytes. Emitting one byte
# changes one indexed cell; match copying never traverses a distance-sized list.
# At span boundaries, remaining + emitted byte count equals the original limit.
# reserve checks the whole span before emission; copyMatch reads the updated ring
# on every step, so distance < length has the required overlapping-copy behavior.
def emit(+byte: U32, output: Output) -> Output:
  match output:
    case Output{ring,+position,+history,remaining,reversed,a,b,window}:
      +nextA = ((a + byte) % 65521 : U32)
      Output{Array.set(U32,ring,position,byte),U32.and((position + 1 : U32),32767),Bool.pick(U32,U32.is_lt(history,32768),(history + 1 : U32),history),remaining,byte <> reversed,nextA,((b + nextA) % 65521 : U32),window}

def reserve(+count: Nat, output: Output) -> Result<&2,&1,Error,Output>:
  match output:
    case Output{ring,position,history,+remaining,reversed,a,b,window}:
      Bool.pick(Unit -> Result<&2,&1,Error,Output>,Nat.is_le(count,remaining),
        _ => Done{Output{ring,position,history,remaining - count,reversed,a,b,window}},_ => Fail{OutputLimit{}})(Unit{})

def copiedByte(fetched: Array<U32> & U32, position: U32, history: U32, remaining: Nat, reversed: List<&2,U32>, a: U32, b: U32, window: U32) -> Output:
  match fetched:
    case (ring,byte): emit(byte,Output{ring,position,history,remaining,reversed,a,b,window})

def copyMatch(count: Nat, +distance: U32, output: Output) -> Output:
  match count output:
    case 0n output: output
    case 1n+n Output{ring,+position,history,remaining,reversed,a,b,window}:
      next = copiedByte(Array.get(U32,ring,U32.and((position - distance : U32),32767)),position,history,remaining,reversed,a,b,window)
      copyMatch(n,distance,next)

def matchDistance(+length: U32, +distance: U32, output: Output) -> Result<&2,&1,Error,Output>:
  match output:
    case Output{ring,position,+history,remaining,reversed,a,b,+window}:
      Bool.pick(Unit -> Result<&2,&1,Error,Output>,U32.is_gt(distance,0) && U32.is_le(distance,history) && U32.is_le(distance,window),
        _ => Result.map(&2,&1,Error,Output,Output,x => copyMatch(U32.to_nat(length),distance,x),reserve(U32.to_nat(length),Output{ring,position,history,remaining,reversed,a,b,window})),
        _ => Fail{InvalidDistance{distance,history}})(Unit{})

# Small bounded metadata lists are indexed only while constructing a tree or
# following a rare code longer than the nine-bit fast table.
def item(values: List<&2,U32>, +index: U32) -> U32:
  match values:
    case Nil{}: 0
    case head <> rest: Bool.pick(Unit -> U32,U32.is_eq(index,0),_ => head,_ => item(rest,(index - 1 : U32)))(Unit{})

def increment(values: List<&2,U32>, +index: U32) -> List<&2,U32>:
  match values:
    case Nil{}: Nil{}
    case +head <> +rest:
      Bool.pick(Unit -> List<&2,U32>,U32.is_eq(index,0),_ => (head + 1 : U32) <> rest,_ => head <> increment(rest,(index - 1 : U32)))(Unit{})

def zeros(count: Nat) -> List<&2,U32>:
  match count:
    case 0n: Nil{}
    case 1n+n: 0 <> zeros(n)

def histogram(lengths: List<&2,U32>, counts: List<&2,U32>) -> List<&2,U32>:
  match lengths:
    case Nil{}: counts
    case length <> rest: histogram(rest,increment(counts,length))

def reverseBits(count: Nat, +value: U32, accumulator: U32) -> U32:
  match count:
    case 0n: accumulator
    case 1n+n: reverseBits(n,U32.shr(value),U32.or(U32.shl(accumulator),U32.and(value,1)))

type Codes is Data:
  Codes{first: List<&2,U32>, offsets: List<&2,U32>, counts: List<&2,U32>, symbols: U32, unused: U32, maximum: U32}

def canonical(counts: List<&2,U32>, +code: U32, previous: U32, +offset: U32, +left: U32, +length: U32, maximum: U32, first: List<&2,U32>, offsets: List<&2,U32>, all: List<&2,U32>) -> Result<&2,&2,Error,Codes>:
  match counts:
    case Nil{}: Done{Codes{List.reverse(&2,U32,first),List.reverse(&2,U32,offsets),all,offset,left,maximum}}
    case +count <> rest:
      Bool.pick(Unit -> Result<&2,&2,Error,Codes>,U32.is_gt(count,U32.shl(left)),_ => Fail{Oversubscribed{Literals{}}},_ =>
        +nextCode = U32.shl((code + previous : U32))
        canonical(rest,nextCode,count,(offset + count : U32),(U32.shl(left) - count : U32),(length + 1 : U32),Bool.pick(U32,U32.is_gt(count,0),length,maximum),nextCode <> first,offset <> offsets,all))(Unit{})

def permitted(kind: TreeKind, codes: Codes) -> Bool:
  match kind codes:
    case CodeLengths{} Codes{_,_,_,_,unused,_}: U32.is_eq(unused,0)
    case Literals{} Codes{_,_,_,symbols,unused,maximum}: U32.is_eq(unused,0) || (U32.is_eq(symbols,1) && U32.is_eq(maximum,1))
    case Distances{} Codes{_,_,_,+symbols,unused,maximum}: U32.is_eq(symbols,0) || U32.is_eq(unused,0) || (U32.is_eq(symbols,1) && U32.is_eq(maximum,1))

type Huffman is Type:
  Huffman{fast: Array<U32>, symbols: Array<U32>, codes: Codes}

# An entry packs symbol+1 above five code-length bits; zero means slow path.
def fillFast(count: Nat, +index: U32, +stride: U32, +entry: U32, table: Array<U32>) -> Array<U32>:
  match count:
    case 0n: table
    case 1n+n: fillFast(n,(index + stride : U32),stride,entry,Array.set(U32,table,index,entry))

def shortCode(short: Bool, +length: U32, code: U32, symbol: U32, table: Array<U32>) -> Array<U32>:
  match short:
    case False{}: table
    case True{}: fillFast(U32.to_nat(U32.shln(1,U32.to_nat((9 - length : U32)))),reverseBits(U32.to_nat(length),code,0),U32.shln(1,U32.to_nat(length)),U32.or(U32.shln((symbol + 1 : U32),5n),length),table)

def installCode(nonzero: Bool, +length: U32, +symbol: U32, +used: List<&2,U32>, table: Huffman) -> Huffman:
  match nonzero table:
    case False{} table: table
    case True{} Huffman{fast,symbols,Codes{+first,+offsets,counts,total,unused,maximum}}:
      +ordinal = item(used,length)
      Huffman{shortCode(U32.is_le(length,9),length,(item(first,length) + ordinal : U32),symbol,fast),Array.set(U32,symbols,(item(offsets,length) + ordinal : U32),symbol),Codes{first,offsets,counts,total,unused,maximum}}

def install(lengths: List<&2,U32>, +symbol: U32, +used: List<&2,U32>, table: Huffman) -> Huffman:
  match lengths:
    case Nil{}: table
    case +length <> rest:
      next = installCode(U32.is_gt(length,0),length,symbol,used,table)
      install(rest,(symbol + 1 : U32),increment(used,length),next)

def makeChecked(+kind: TreeKind, +lengths: List<&2,U32>, result: Result<&2,&2,Error,Codes>) -> Result<&2,&1,Error,Huffman>:
  match result:
    case Fail{_}: Fail{Oversubscribed{kind}}
    case Done{+codes}:
      Bool.pick(Unit -> Result<&2,&1,Error,Huffman>,permitted(kind,codes),_ => Done{install(lengths,0,zeros(16n),Huffman{Array.new(U32,9n,0),Array.new(U32,9n,0),codes})},_ => Fail{IncompleteTree{kind}})(Unit{})

def make(kind: TreeKind, +lengths: List<&2,U32>) -> Result<&2,&1,Error,Huffman>:
  +counts = histogram(lengths,zeros(16n))
  makeChecked(kind,lengths,canonical(List.drop(&2,U32,counts,1n),0,0,0,1,1,0,0 <> Nil{},0 <> Nil{},counts))

type Symbol is Type:
  Symbol{table: Huffman, value: Read}

def foundValue(fast: Array<U32>, fetched: Array<U32> & U32, codes: Codes, bits: Bits) -> Symbol:
  match fetched:
    case (symbols,value): Symbol{Huffman{fast,symbols,codes},Read{value,bits}}

def foundSymbol(table: Huffman, bits: Bits, index: U32) -> Symbol:
  match table:
    case Huffman{fast,symbols,codes}:
      foundValue(fast,Array.get(U32,symbols,index),codes,bits)

# Long-code lookup extends a canonical prefix, at most fifteen bits total.
# Most symbols use one nine-bit array lookup and bypass this path entirely.
type Search is Data:
  NextBit{length: U32, code: U32, bits: Bits}
  Found{index: U32, bits: Bits}
  Broken{error: Error}

def searched(+length: U32, code: U32, codes: Codes, read: Result<&2,&2,Error,Read>) -> Search:
  match codes read:
    case _ Fail{error}: Broken{error}
    case Codes{first,offsets,counts,_,_,maximum} Done{Read{bit,+bits}}:
      +next = U32.or(U32.shl(code),bit)
      +base = item(first,length)
      Bool.pick(Search,U32.is_ge(next,base) && U32.is_lt((next - base : U32),item(counts,length)),
        Found{(item(offsets,length) + next - base : U32),bits},
        Bool.pick(Search,U32.is_ge(length,maximum),Broken{InvalidCode{}},NextBit{(length + 1 : U32),next,bits}))

@unsafe def slowSymbol(table: Huffman, search: Search) -> Result<&2,&1,Error,Symbol>:
  match table search:
    case _ Broken{error}: Fail{error}
    case table Found{index,bits}: Done{foundSymbol(table,bits,index)}
    case Huffman{fast,symbols,+codes} NextBit{length,code,bits}:
      slowSymbol(Huffman{fast,symbols,codes},searched(length,code,codes,take(1,bits)))

def fastChosen(valid: Bool, table: Huffman, bits: Bits, entry: U32, +length: U32) -> Result<&2,&1,Error,Symbol>:
  match valid bits:
    case True{} Bits{bytes,word,available}:
      Done{Symbol{table,Read{(U32.shrn(entry,5n) - 1 : U32),Bits{bytes,U32.shrn(word,U32.to_nat(length)),(available - length : U32)}}}}
    case False{} bits: slowSymbol(table,NextBit{1,0,bits})

def fastSymbol(table: Huffman, +bits: Bits, +entry: U32) -> Result<&2,&1,Error,Symbol>:
  match bits:
    case Bits{_,_,available}:
      +length = U32.and(entry,31)
      fastChosen(U32.is_gt(entry,0) && U32.is_le(length,available),table,bits,entry,length)

def fastValue(fetched: Array<U32> & U32, symbols: Array<U32>, codes: Codes, bits: Bits) -> Result<&2,&1,Error,Symbol>:
  match fetched:
    case (fast,entry): fastSymbol(Huffman{fast,symbols,codes},bits,entry)

def symbolReady(table: Huffman, +bits: Bits) -> Result<&2,&1,Error,Symbol>:
  match table:
    case Huffman{fast,symbols,codes}:
      match bits:
        case Bits{_,word,_}:
          fastValue(Array.get(U32,fast,U32.and(word,511)),symbols,codes,bits)

def symbol(table: Huffman, bits: Bits) -> Result<&2,&1,Error,Symbol>: symbolReady(table,refill(2n,9,bits))

def replace(values: List<&2,U32>, +index: U32, +value: U32) -> List<&2,U32>:
  match values:
    case Nil{}: Nil{}
    case head <> +rest:
      Bool.pick(Unit -> List<&2,U32>,U32.is_eq(index,0),_ => value <> rest,_ => head <> replace(rest,(index - 1 : U32),value))(Unit{})

type Header is Data:
  Header{bits: Bits, literalCount: Nat, distanceCount: Nat, lengths: List<&2,U32>, order: List<&2,U32>}

def readCodeLength(header: Header, read: Result<&2,&2,Error,Read>) -> Result<&2,&2,Error,Header>:
  match header read:
    case _ Fail{error}: Fail{error}
    case Header{_,lc,dc,lengths,index <> rest} Done{Read{value,bits}}: Done{Header{bits,lc,dc,replace(lengths,index,value),rest}}
    case _ _: Fail{InvalidRepeat{}}

def codeLengths(count: Nat, state: Result<&2,&2,Error,Header>) -> Result<&2,&2,Error,Header>:
  match count state:
    case _ Fail{error}: Fail{error}
    case 0n state: state
    case 1n+n Done{Header{+bits,lc,dc,lengths,order}}:
      codeLengths(n,readCodeLength(Header{bits,lc,dc,lengths,order},take(3,bits)))

def headerFields(read: Result<&2,&2,Error,Read>) -> Result<&2,&2,Error,Header>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{+value,bits}}:
      +literalCount = (U32.and(value,31) + 257 : U32)
      Bool.pick(Unit -> Result<&2,&2,Error,Header>,U32.is_gt(literalCount,286),_ => Fail{InvalidCode{}},_ =>
        codeLengths(U32.to_nat((U32.shrn(value,10n) + 4 : U32)),Done{Header{bits,U32.to_nat(literalCount),U32.to_nat((U32.and(U32.shrn(value,5n),31) + 1 : U32)),zeros(19n),16 <> 17 <> 18 <> 0 <> 8 <> 7 <> 9 <> 6 <> 10 <> 5 <> 11 <> 4 <> 12 <> 3 <> 13 <> 2 <> 14 <> 1 <> 15 <> Nil{}}}))(Unit{})

type Repetition is Data:
  Repetition{value: U32, base: U32, extra: U32}

def lengthCode(+code: U32, previous: List<&2,U32>) -> Result<&2,&2,Error,Repetition>:
  match previous:
    case Nil{}:
      Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,16),Fail{InvalidRepeat{}},
        Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,17),Done{Repetition{0,3,3}},
          Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,18),Done{Repetition{0,11,7}},Done{Repetition{code,1,0}})))
    case last <> _:
      Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,16),Done{Repetition{last,3,2}},
        Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,17),Done{Repetition{0,3,3}},
          Bool.pick(Result<&2,&2,Error,Repetition>,U32.is_eq(code,18),Done{Repetition{0,11,7}},Done{Repetition{code,1,0}})))

def repeated(count: Nat, +value: U32, values: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: values
    case 1n+n: repeated(n,value,value <> values)

type Expanded is Type:
  Expanded{table: Huffman, bits: Bits, remaining: Nat, reversed: List<&2,U32>}

def expandedRead(table: Huffman, +remaining: Nat, values: List<&2,U32>, value: U32, base: U32, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Expanded>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{extra,bits}}:
      +count = U32.to_nat((base + extra : U32))
      Bool.pick(Unit -> Result<&2,&1,Error,Expanded>,Nat.is_le(count,remaining),
        _ => Done{Expanded{table,bits,remaining - count,repeated(count,value,values)}},_ => Fail{InvalidRepeat{}})(Unit{})

def expandedCode(table: Huffman, bits: Bits, remaining: Nat, values: List<&2,U32>, spec: Result<&2,&2,Error,Repetition>) -> Result<&2,&1,Error,Expanded>:
  match spec:
    case Fail{error}: Fail{error}
    case Done{Repetition{value,base,extra}}: expandedRead(table,remaining,values,value,base,take(extra,bits))

def expandedSymbol(remaining: Nat, +values: List<&2,U32>, read: Result<&2,&1,Error,Symbol>) -> Result<&2,&1,Error,Expanded>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Symbol{table,Read{value,bits}}}: expandedCode(table,bits,remaining,values,lengthCode(value,values))

# Every expansion appends at least one code length, checked against the exact
# HLIT+HDIST total; repeats can cross that boundary but cannot exceed it.
@unsafe def expand(state: Result<&2,&1,Error,Expanded>) -> Result<&2,&1,Error,Expanded>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Expanded{table,bits,0n,values}}: Done{Expanded{table,bits,0n,values}}
    case Done{Expanded{table,bits,remaining,values}}: expand(expandedSymbol(remaining,values,symbol(table,bits)))

type Tables is Type:
  Tables{literal: Huffman, distance: Huffman}

type TableHeader is Type:
  TableHeader{tables: Tables, bits: Bits}

def distanceTable(literal: Huffman, bits: Bits, result: Result<&2,&1,Error,Huffman>) -> Result<&2,&1,Error,TableHeader>:
  match result:
    case Fail{error}: Fail{error}
    case Done{distance}: Done{TableHeader{Tables{literal,distance},bits}}

def literalTable(bits: Bits, distances: List<&2,U32>, result: Result<&2,&1,Error,Huffman>) -> Result<&2,&1,Error,TableHeader>:
  match result:
    case Fail{error}: Fail{error}
    case Done{literal}: distanceTable(literal,bits,make(Distances{},distances))

def buildTables(valid: Bool, bits: Bits, literals: List<&2,U32>, distances: List<&2,U32>) -> Result<&2,&1,Error,TableHeader>:
  match valid:
    case False{}: Fail{MissingEndCode{}}
    case True{}: literalTable(bits,distances,make(Literals{},literals))

def dynamicExpanded(+literalCount: Nat, state: Result<&2,&1,Error,Expanded>) -> Result<&2,&1,Error,TableHeader>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Expanded{_,bits,_,values}}:
      +all = List.reverse(&2,U32,values)
      buildTables(U32.is_gt(item(all,256),0),bits,List.take(&2,U32,all,literalCount),List.drop(&2,U32,all,literalCount))

def dynamicCodes(bits: Bits, +literalCount: Nat, distanceCount: Nat, result: Result<&2,&1,Error,Huffman>) -> Result<&2,&1,Error,TableHeader>:
  match result:
    case Fail{error}: Fail{error}
    case Done{table}: dynamicExpanded(literalCount,expand(Done{Expanded{table,bits,literalCount + distanceCount,Nil{}}}))

def dynamic(header: Result<&2,&2,Error,Header>) -> Result<&2,&1,Error,TableHeader>:
  match header:
    case Fail{error}: Fail{error}
    case Done{Header{bits,lc,dc,lengths,_}}: dynamicCodes(bits,lc,dc,make(CodeLengths{},lengths))

def fixedLengths(count: Nat, +index: U32, values: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: List.reverse(&2,U32,values)
    case 1n+n:
      length = Bool.pick(U32,U32.is_lt(index,144),8,Bool.pick(U32,U32.is_lt(index,256),9,Bool.pick(U32,U32.is_lt(index,280),7,8)))
      fixedLengths(n,(index + 1 : U32),length <> values)

def fixed(bits: Bits) -> Result<&2,&1,Error,TableHeader>:
  literalTable(bits,repeated(32n,5,Nil{}),make(Literals{},fixedLengths(288n,0,Nil{})))

type Compressed is Type:
  Compressed{tables: Tables, bits: Bits, output: Output, ended: Bool}

def literalOutput(tables: Tables, bits: Bits, byte: U32, result: Result<&2,&1,Error,Output>) -> Result<&2,&1,Error,Compressed>:
  match result:
    case Fail{error}: Fail{error}
    case Done{output}: Done{Compressed{tables,bits,emit(byte,output),False{}}}

def matchOutput(tables: Tables, bits: Bits, result: Result<&2,&1,Error,Output>) -> Result<&2,&1,Error,Compressed>:
  match result:
    case Fail{error}: Fail{error}
    case Done{output}: Done{Compressed{tables,bits,output,False{}}}

def distanceRead(tables: Tables, output: Output, length: U32, base: U32, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Compressed>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{extra,bits}}: matchOutput(tables,bits,matchDistance(length,(base + extra : U32),output))

def distanceValid(valid: Bool, literal: Huffman, distance: Huffman, bits: Bits, output: Output, length: U32, +code: U32) -> Result<&2,&1,Error,Compressed>:
  match valid:
    case False{}: Fail{ReservedSymbol{}}
    case True{}:
      +extra = Bool.pick(U32,U32.is_lt(code,4),0,(U32.shr(code) - 1 : U32))
      base = Bool.pick(U32,U32.is_lt(code,4),(code + 1 : U32),(U32.shln((2 + U32.and(code,1) : U32),U32.to_nat(extra)) + 1 : U32))
      distanceRead(Tables{literal,distance},output,length,base,take(extra,bits))

def distanceSymbol(literal: Huffman, output: Output, length: U32, read: Result<&2,&1,Error,Symbol>) -> Result<&2,&1,Error,Compressed>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Symbol{distance,Read{+code,bits}}}: distanceValid(U32.is_lt(code,30),literal,distance,bits,output,length,code)

def lengthRead(tables: Tables, output: Output, base: U32, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Compressed>:
  match tables read:
    case _ Fail{error}: Fail{error}
    case Tables{literal,distance} Done{Read{extra,bits}}: distanceSymbol(literal,output,(base + extra : U32),symbol(distance,bits))

def lengthValid(valid: Bool, tables: Tables, bits: Bits, output: Output, +index: U32) -> Result<&2,&1,Error,Compressed>:
  match valid:
    case False{}: Fail{ReservedSymbol{}}
    case True{}:
      +extra = Bool.pick(U32,U32.is_lt(index,8) || U32.is_eq(index,28),0,((index - 4) / 4 : U32))
      base = Bool.pick(U32,U32.is_lt(index,8),(index + 3 : U32),Bool.pick(U32,U32.is_eq(index,28),258,(U32.shln((4 + U32.and(index,3) : U32),U32.to_nat(extra)) + 3 : U32)))
      lengthRead(tables,output,base,take(extra,bits))

def literalCode(isByte: Bool, isEnd: Bool, +code: U32, tables: Tables, bits: Bits, output: Output) -> Result<&2,&1,Error,Compressed>:
  match isByte isEnd:
    case True{} _: literalOutput(tables,bits,code,reserve(1n,output))
    case False{} True{}: Done{Compressed{tables,bits,output,True{}}}
    case False{} False{}: lengthValid(U32.is_le(code,285),tables,bits,output,(code - 257 : U32))

def literalSymbol(distance: Huffman, output: Output, read: Result<&2,&1,Error,Symbol>) -> Result<&2,&1,Error,Compressed>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Symbol{literal,Read{+code,bits}}}: literalCode(U32.is_lt(code,256),U32.is_eq(code,256),code,Tables{literal,distance},bits,output)

# Each iteration consumes a nonempty Huffman code. Copying is separately
# bounded by the decoded length (at most 258), after one output-budget check.
@unsafe def compressed(state: Result<&2,&1,Error,Compressed>) -> Result<&2,&1,Error,Decoded>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Compressed{_,bits,output,True{}}}: Done{Decoded{bits,output}}
    case Done{Compressed{Tables{literal,distance},bits,output,False{}}}: compressed(literalSymbol(distance,output,symbol(literal,bits)))

def compressedTables(output: Output, result: Result<&2,&1,Error,TableHeader>) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{TableHeader{tables,bits}}: compressed(Done{Compressed{tables,bits,output,False{}}})

def storedByte(output: Output, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Decoded>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{byte,bits}}: Done{Decoded{bits,emit(byte,output)}}

def storedBytes(count: Nat, state: Result<&2,&1,Error,Decoded>) -> Result<&2,&1,Error,Decoded>:
  match count state:
    case _ Fail{error}: Fail{error}
    case 0n state: state
    case 1n+n Done{Decoded{bits,output}}: storedBytes(n,storedByte(output,take(8,bits)))

def storedReserved(count: Nat, bits: Bits, result: Result<&2,&1,Error,Output>) -> Result<&2,&1,Error,Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{output}: storedBytes(count,Done{Decoded{bits,output}})

def storedComplement(+length: U32, output: Output, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Decoded>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{other,bits}}:
      Bool.pick(Unit -> Result<&2,&1,Error,Decoded>,U32.is_eq(U32.xor(length,other),65535),
        _ => storedReserved(U32.to_nat(length),bits,reserve(U32.to_nat(length),output)),_ => Fail{StoredLength{}})(Unit{})

def storedHeader(output: Output, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,Decoded>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{length,bits}}: storedComplement(length,output,take(16,bits))

def block(kind: U32, bits: Bits, output: Output) -> Result<&2,&1,Error,Decoded>:
  match kind:
    case 0: storedHeader(output,take(16,align(bits)))
    case 1: compressedTables(output,fixed(bits))
    case 2: compressedTables(output,dynamic(headerFields(take(14,bits))))
    case _: Fail{InvalidBlock{}}

type BlockResult is Type:
  BlockResult{last: Bool, decoded: Decoded}

def blockRead(output: Output, read: Result<&2,&2,Error,Read>) -> Result<&2,&1,Error,BlockResult>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{+value,bits}}:
      Result.map(&2,&1,Error,Decoded,BlockResult,x => BlockResult{U32.is_eq(U32.and(value,1),1),x},block(U32.shr(value),bits,output))

# Each nonfinal block consumes a three-bit header, even an empty stored block.
# The finite input therefore bounds this loop independently of the output budget.
@unsafe def blocks(state: Result<&2,&1,Error,BlockResult>) -> Result<&2,&1,Error,Decoded>:
  match state:
    case Fail{error}: Fail{error}
    case Done{BlockResult{True{},decoded}}: Done{decoded}
    case Done{BlockResult{False{},Decoded{bits,output}}}: blocks(blockRead(output,take(3,bits)))

def start(bits: Bits, limit: Nat, window: U32) -> Result<&2,&1,Error,Decoded>:
  blocks(blockRead(Output{Array.new(U32,15n,0),0,0,limit,Nil{},1,0,window},take(3,bits)))

def rawFinish(result: Result<&2,&1,Error,Decoded>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoded{bits,Output{_,_,_,_,reversed,_,_,_}}}:
      Bool.pick(Result<&2,&2,Error,List<&2,U32>>,atEnd(align(bits)),Done{List.reverse(&2,U32,reversed)},Fail{TrailingData{}})

def rawValid(valid: Bool, bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: rawFinish(start(Bits{bytes,0,0},limit,32768))

def inflateRaw(+bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>: rawValid(validBytes(bytes),bytes,limit)

def adlerBytes(count: Nat, value: U32, read: Result<&2,&2,Error,Read>) -> Result<&2,&2,Error,Read>:
  match count read:
    case _ Fail{error}: Fail{error}
    case 0n read: read
    case 1n+rest Done{Read{byte,+bits}}:
      +n = rest
      +next = U32.or(U32.shln(value,8n),byte)
      Bool.pick(Unit -> Result<&2,&2,Error,Read>,Nat.is_eq(n,0n),_ => Done{Read{next,bits}},_ => adlerBytes(n,next,take(8,bits)))(Unit{})

def zlibChecksum(+actual: U32, bytes: List<&2,U32>, read: Result<&2,&2,Error,Read>) -> Result<&2,&2,Error,List<&2,U32>>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{+expected,bits}}:
      Bool.pick(Result<&2,&2,Error,List<&2,U32>>,U32.is_eq(actual,expected),
        Bool.pick(Result<&2,&2,Error,List<&2,U32>>,atEnd(bits),Done{List.reverse(&2,U32,bytes)},Fail{TrailingData{}}),Fail{Checksum{expected,actual}})

def zlibFinish(result: Result<&2,&1,Error,Decoded>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoded{bits,Output{_,_,_,_,reversed,a,b,_}}}:
      zlibChecksum(U32.or(U32.shln(b,16n),a),reversed,adlerBytes(4n,0,take(8,align(bits))))

def zlibFlags(valid: Bool, checked: Bool, dictionary: Bool, bits: Bits, limit: Nat, window: U32) -> Result<&2,&2,Error,List<&2,U32>>:
  match valid checked dictionary:
    case False{} _ _: Fail{InvalidHeader{}}
    case True{} False{} _: Fail{HeaderCheck{}}
    case True{} True{} True{}: Fail{DictionaryRequired{}}
    case True{} True{} False{}: zlibFinish(start(bits,limit,window))

def zlibHeader(limit: Nat, read: Result<&2,&2,Error,Read>) -> Result<&2,&2,Error,List<&2,U32>>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Read{+value,bits}}:
      +cmf = U32.and(value,255)
      +flg = U32.shrn(value,8n)
      zlibFlags(U32.is_eq(U32.and(cmf,15),8) && U32.is_le(U32.shrn(cmf,4n),7),U32.is_eq(((cmf * 256 + flg) % 31 : U32),0),U32.is_gt(U32.and(flg,32),0),bits,limit,U32.shln(1,U32.to_nat((U32.shrn(cmf,4n) + 8 : U32))))

def zlibValid(valid: Bool, bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: zlibHeader(limit,take(16,Bits{bytes,0,0}))

def inflateZlib(+bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>: zlibValid(validBytes(bytes),bytes,limit)
