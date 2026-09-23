import Base
import ./image.bend as Image

# Pure JPEG to straight-alpha RGBA8: sequential/progressive 8-bit DCT,
# Huffman lossless 8/16-bit samples, and AVI1 default Huffman tables.
# Input is one complete stream. Pixel and coefficient bounds are checked before
# image-sized allocation; EXIF orientation belongs to the calling image utility.
# See tests/jpeg.md for reference scope, strictness and lossless corrections.
type Error is Data:
  Signature{}
  InvalidByte{}
  Truncated{}
  FrameHeader{}
  ScanHeader{}
  Quantization{}
  InvalidHuffman{}
  Entropy{}
  Restart{}
  PixelLimit{}
  Unsupported{marker: U32}

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
def bind(-A: Data, -B: Data, result: Parsed(A), next: A -> Parsed(B)) -> Parsed(B):
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: next(value)

def byteCount(bytes: List<&2,U32>, count: Nat) -> Parsed(Nat):
  match bytes:
    case Nil{}: Done{count}
    case byte <> +rest: Bool.pick(Unit -> Parsed(Nat),U32.is_le(byte,255),_ => byteCount(rest,1n + count),_ => Fail{InvalidByte{}})(Unit{})

def item(index: Nat, bytes: List<&2,U32>) -> U32:
  match index bytes:
    case 0n byte <> _: byte
    case 1n+n _ <> rest: item(n,rest)
    case _ _: 0

def word16(a: U32, b: U32) -> U32: (a * 256 + b : U32)
def ceiling(a: U32, +b: U32) -> U32: ((a + b - 1) / b : U32)
def minimum(+a: U32, +b: U32) -> U32: Bool.pick(U32,U32.is_lt(a,b),a,b)
def maximum(+a: U32, +b: U32) -> U32: Bool.pick(U32,U32.is_gt(a,b),a,b)
def shiftedSigned(+value: U32, +bits: Nat) -> U32:
  U32.or(U32.shrn(value,bits),Bool.pick(U32,U32.is_ge(value,2147483648),U32.shln(4294967295,32n - bits),0))
def signed16(+value: U32) -> U32:
  +low = U32.and(value,65535)
  Bool.pick(U32,U32.is_ge(low,32768),U32.or(low,4294901760),low)

type Segment is Data: Segment{data: List<&2,U32>, rest: List<&2,U32>}
def segmentData(part: Segment) -> List<&2,U32>:
  match part:
    case Segment{data,_}: data
def segmentRest(part: Segment) -> List<&2,U32>:
  match part:
    case Segment{_,rest}: rest
def split(count: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(Segment):
  match count bytes:
    case 0n bytes: Done{Segment{List.reverse(&2,U32,reversed),bytes}}
    case 1n+n byte <> rest: split(n,rest,byte <> reversed)
    case _ Nil{}: Fail{Truncated{}}
def segment(bytes: List<&2,U32>) -> Parsed(Segment):
  match bytes:
    case a <> b <> +rest:
      +size = word16(a,b)
      Bool.pick(Unit -> Parsed(Segment),U32.is_ge(size,2),_ => split(U32.to_nat((size - 2 : U32)),rest,Nil{}),_ => Fail{Truncated{}})(Unit{})
    case _: Fail{Truncated{}}

type Component is Data:
  Component{id: U32, horizontal: U32, vertical: U32, quantizer: U32, width: U32, height: U32, columns: U32, rows: U32, offset: U32}
type Frame is Data:
  Frame{mode: U32, precision: U32, width: U32, height: U32, horizontal: U32, vertical: U32, columns: U32, rows: U32, components: List<&2,Component>, cells: U32}
def componentId(component: Component) -> U32:
  match component:
    case Component{id,_,_,_,_,_,_,_,_}: id

def componentExists(components: List<&2,Component>, +id: U32) -> Bool:
  match components:
    case Nil{}: False{}
    case component <> +rest: Bool.pick(Unit -> Bool,U32.is_eq(componentId(component),id),_ => True{},_ => componentExists(rest,id))(Unit{})

def frameComponents(count: Nat, bytes: List<&2,U32>, +reversed: List<&2,Component>) -> Parsed(List<&2,Component>):
  match count bytes:
    case 0n Nil{}: Done{List.reverse(&2,Component,reversed)}
    case 1n+n +id <> +sampling <> +quantizer <> +rest:
      +horizontal = U32.shrn(sampling,4n)
      +vertical = U32.and(sampling,15)
      Bool.pick(Unit -> Parsed(List<&2,Component>),U32.is_ge(horizontal,1) && U32.is_le(horizontal,4) && U32.is_ge(vertical,1) && U32.is_le(vertical,4) && U32.is_le(quantizer,3) && Bool.not(componentExists(reversed,id)),
        _ => frameComponents(n,rest,Component{id,horizontal,vertical,quantizer,0,0,0,0,0} <> reversed),_ => Fail{FrameHeader{}})(Unit{})
    case _ _: Fail{FrameHeader{}}

type Sampling is Data: Sampling{horizontal: U32, vertical: U32}
def sampling(components: List<&2,Component>, horizontal: U32, vertical: U32) -> Sampling:
  match components:
    case Nil{}: Sampling{horizontal,vertical}
    case Component{_,h,v,_,_,_,_,_,_} <> rest: sampling(rest,maximum(horizontal,h),maximum(vertical,v))

def layout(components: List<&2,Component>, +frame: Frame, +offset: U32, reversed: List<&2,Component>) -> Parsed(Frame):
  match components frame:
    case Nil{} Frame{mode,precision,width,height,h,v,columns,rows,_,_}: Done{Frame{mode,precision,width,height,h,v,columns,rows,List.reverse(&2,Component,reversed),offset}}
    case Component{id,+h,+v,+q,_,_,_,_,_} <> +rest Frame{+mode,+precision,+width,+height,+hm,+vm,+columns,+rows,_,_}:
      +cw = ceiling((width * h : U32),hm)
      +ch = ceiling((height * v : U32),vm)
      +bc = Bool.pick(U32,U32.is_eq(mode,195),width,(columns * h : U32))
      +br = Bool.pick(U32,U32.is_eq(mode,195),height,(rows * v : U32))
      +cells = U32.to_nat(bc) * U32.to_nat(br) * Bool.pick(Nat,U32.is_eq(mode,195),1n,64n)
      Bool.pick(Unit -> Parsed(Frame),Nat.is_le(U32.to_nat(offset) + cells,2147483648n) && U32.is_eq((hm % h : U32),0) && U32.is_eq((vm % v : U32),0) && (Bool.not(U32.is_eq(mode,195)) || U32.is_eq(q,0)),
        _ => layout(rest,Frame{mode,precision,width,height,hm,vm,columns,rows,Nil{},0},(offset + U32.from_nat(cells) : U32),Component{id,h,v,q,cw,ch,bc,br,offset} <> reversed),_ => Fail{PixelLimit{}})(Unit{})

def frameLayout(mode: U32, precision: U32, +width: U32, +height: U32, +components: List<&2,Component>, factors: Sampling) -> Parsed(Frame):
  match factors:
    case Sampling{+h,+v}: layout(components,Frame{mode,precision,width,height,h,v,ceiling(width,(8 * h : U32)),ceiling(height,(8 * v : U32)),Nil{},0},0,Nil{})

type Row is Data: Row{first: U32, count: U32, symbols: List<&2,U32>}
type Huffman is Data: Huffman{rows: List<&2,Row>}
def readFrame(+mode: U32, bytes: List<&2,U32>, +limit: Nat) -> Parsed(Frame):
  match bytes:
    case +precision <> ha <> hb <> wa <> wb <> +count <> +rest:
      +width = word16(wa,wb)
      +height = word16(ha,hb)
      Bool.pick(Unit -> Parsed(Frame),U32.is_gt(width,0) && U32.is_gt(height,0) && (U32.is_eq(count,1) || U32.is_eq(count,3) || U32.is_eq(count,4)) && (U32.is_eq(precision,8) || (U32.is_eq(mode,195) && U32.is_eq(precision,16))),
        _ => Bool.pick(Unit -> Parsed(Frame),Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit),
          _ => bind(List<&2,Component>,Frame,frameComponents(U32.to_nat(count),rest,Nil{}),+components => frameLayout(mode,precision,width,height,components,sampling(components,1,1))),_ => Fail{PixelLimit{}})(Unit{}),_ => Fail{FrameHeader{}})(Unit{})
    case _: Fail{FrameHeader{}}

# Canonical Huffman rows avoid allocating a 65536-entry table per alphabet.
# A row records the first code of a given bit length and its ordered symbols.
type CodeTable is Data: CodeTable{index: U32, tree: Huffman}
type Quantizer is Data: Quantizer{index: U32, values: List<&2,U32>}

def huffmanRows(counts: List<&2,U32>, +bits: Nat, +first: U32, symbols: List<&2,U32>, reversed: List<&2,Row>) -> Parsed(Huffman):
  match counts symbols:
    case Nil{} Nil{}: Done{Huffman{List.reverse(&2,Row,reversed)}}
    case +count <> +rest +symbols:
      Bool.pick(Unit -> Parsed(Huffman),U32.is_lt((first + count : U32),U32.shln(1,bits)),
        _ => bind(Segment,Huffman,split(U32.to_nat(count),symbols,Nil{}),+part => huffmanRows(rest,1n + bits,U32.shl((first + count : U32)),segmentRest(part),Row{first,count,segmentData(part)} <> reversed)),_ => Fail{InvalidHuffman{}})(Unit{})
    case _ _: Fail{InvalidHuffman{}}

def sum(bytes: List<&2,U32>, value: Nat) -> Nat:
  match bytes:
    case Nil{}: value
    case byte <> rest: sum(rest,value + U32.to_nat(byte))

def huffmanSymbols(+counts: Segment) -> Parsed(Segment):
  +count = sum(segmentData(counts),0n)
  Bool.pick(Unit -> Parsed(Segment),Nat.is_gt(count,0n) && Nat.is_le(count,256n),_ => split(count,segmentRest(counts),Nil{}),_ => Fail{InvalidHuffman{}})(Unit{})
def readHuffman(fuel: Nat, bytes: List<&2,U32>, tables: List<&2,CodeTable>) -> Parsed(List<&2,CodeTable>):
  match fuel bytes:
    case _ Nil{}: Done{tables}
    case 0n _: Fail{InvalidHuffman{}}
    case 1n+n +index <> +rest:
      Bool.pick(Unit -> Parsed(List<&2,CodeTable>),U32.is_le(U32.and(index,15),3) && U32.is_le(U32.shrn(index,4n),1),
        _ => bind(Segment,List<&2,CodeTable>,split(16n,rest,Nil{}),+counts => bind(Segment,List<&2,CodeTable>,huffmanSymbols(counts),+part => bind(Huffman,List<&2,CodeTable>,huffmanRows(segmentData(counts),1n,0,segmentData(part),Nil{}),tree => readHuffman(n,segmentRest(part),CodeTable{index,tree} <> tables)))),_ => Fail{InvalidHuffman{}})(Unit{})

def quantizerValues(count: Nat, +wide: Bool, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(Segment):
  match count wide bytes:
    case 0n _ bytes: Done{Segment{List.reverse(&2,U32,reversed),bytes}}
    case 1n+n False{} +byte <> +rest: Bool.pick(Unit -> Parsed(Segment),U32.is_gt(byte,0),_ => quantizerValues(n,wide,rest,byte <> reversed),_ => Fail{Quantization{}})(Unit{})
    case 1n+n True{} a <> b <> +rest:
      +value = word16(a,b)
      Bool.pick(Unit -> Parsed(Segment),U32.is_gt(value,0),_ => quantizerValues(n,wide,rest,value <> reversed),_ => Fail{Quantization{}})(Unit{})
    case _ _ _: Fail{Quantization{}}
def readQuantizers(fuel: Nat, bytes: List<&2,U32>, tables: List<&2,Quantizer>) -> Parsed(List<&2,Quantizer>):
  match fuel bytes:
    case _ Nil{}: Done{tables}
    case 0n _: Fail{Quantization{}}
    case 1n+n +index <> +rest:
      Bool.pick(Unit -> Parsed(List<&2,Quantizer>),U32.is_le(U32.and(index,15),3) && U32.is_le(U32.shrn(index,4n),1),
        _ => bind(Segment,List<&2,Quantizer>,quantizerValues(64n,U32.is_ge(index,16),rest,Nil{}),+part => readQuantizers(n,segmentRest(part),Quantizer{U32.and(index,15),segmentData(part)} <> tables)),_ => Fail{Quantization{}})(Unit{})

type Selection is Data: Selection{component: Component, dc: U32, ac: U32}
type EntropyChunk is Data: EntropyChunk{bytes: List<&2,U32>, restart: U32}
type Scan is Data:
  Scan{selected: List<&2,Selection>, start: U32, end: U32, high: U32, low: U32, interval: U32, codes: List<&2,CodeTable>, quantizers: List<&2,Quantizer>, chunks: List<&2,EntropyChunk>}
type EntropyData is Data: EntropyData{chunks: List<&2,EntropyChunk>, rest: List<&2,U32>}

def findComponent(components: List<&2,Component>, +id: U32) -> Parsed(Component):
  match components:
    case Nil{}: Fail{ScanHeader{}}
    case +component <> +rest: Bool.pick(Unit -> Parsed(Component),U32.is_eq(componentId(component),id),_ => Done{component},_ => findComponent(rest,id))(Unit{})
def selectedBefore(selections: List<&2,Selection>, +id: U32) -> Bool:
  match selections:
    case Nil{}: False{}
    case Selection{component,_,_} <> +rest: Bool.pick(Unit -> Bool,U32.is_eq(componentId(component),id),_ => True{},_ => selectedBefore(rest,id))(Unit{})
type Selected is Data: Selected{selected: List<&2,Selection>, rest: List<&2,U32>}
def scanSelections(count: Nat, bytes: List<&2,U32>, +components: List<&2,Component>, +reversed: List<&2,Selection>) -> Parsed(Selected):
  match count bytes:
    case 0n bytes: Done{Selected{List.reverse(&2,Selection,reversed),bytes}}
    case 1n+n +id <> +tables <> +rest:
      Bool.pick(Unit -> Parsed(Selected),U32.is_le(U32.shrn(tables,4n),3) && U32.is_le(U32.and(tables,15),3) && Bool.not(selectedBefore(reversed,id)),
        _ => bind(Component,Selected,findComponent(components,id),component => scanSelections(n,rest,components,Selection{component,U32.shrn(tables,4n),U32.and(tables,15)} <> reversed)),_ => Fail{ScanHeader{}})(Unit{})
    case _ _: Fail{ScanHeader{}}
def selectedBlocks(selections: List<&2,Selection>, total: U32) -> U32:
  match selections:
    case Nil{}: total
    case Selection{Component{_,h,v,_,_,_,_,_,_},_,_} <> rest: selectedBlocks(rest,(total + h * v : U32))

def finishScan(+mode: U32, +precision: U32, +count: U32, interval: U32, codes: List<&2,CodeTable>, quantizers: List<&2,Quantizer>, header: Selected) -> Parsed(Scan):
  match header:
    case Selected{+selected,+start <> +end <> +approximation <> Nil{}}:
      +high = U32.shrn(approximation,4n)
      +low = U32.and(approximation,15)
      +valid = Bool.pick(Bool,U32.is_eq(mode,194),U32.is_le(end,63) && U32.is_le(start,end) && (Bool.not(U32.is_eq(start,0)) || U32.is_eq(end,0)) && (U32.is_eq(start,0) || U32.is_eq(count,1)) && U32.is_le(high,13) && U32.is_le(low,13) && (U32.is_eq(high,0) || U32.is_eq(high,(low + 1 : U32))),Bool.pick(Bool,U32.is_eq(mode,195),U32.is_ge(start,1) && U32.is_le(start,7) && U32.is_eq(end,0) && U32.is_eq(high,0) && U32.is_lt(low,precision),U32.is_eq(start,0) && U32.is_eq(end,63) && U32.is_eq(approximation,0)))
      Bool.pick(Parsed(Scan),valid && (U32.is_eq(count,1) || U32.is_le(selectedBlocks(selected,0),10)),Done{Scan{selected,start,end,high,low,interval,codes,quantizers,Nil{}}},Fail{ScanHeader{}})
    case _: Fail{ScanHeader{}}
def readScan(bytes: List<&2,U32>, interval: U32, codes: List<&2,CodeTable>, quantizers: List<&2,Quantizer>, frame: Frame) -> Parsed(Scan):
  match bytes frame:
    case +count <> +rest Frame{mode,precision,_,_,_,_,_,_,components,_}:
      Bool.pick(Unit -> Parsed(Scan),U32.is_ge(count,1) && U32.is_le(count,4),_ => bind(Selected,Scan,scanSelections(U32.to_nat(count),rest,components,Nil{}),header => finishScan(mode,precision,count,interval,codes,quantizers,header)),_ => Fail{ScanHeader{}})(Unit{})
    case _ _: Fail{ScanHeader{}}

# Byte stuffing is removed once. Restart markers split the entropy stream so
# block decoding cannot consume marker bytes or cross a restart by accident.
def entropyBytes(bytes: List<&2,U32>, +reversed: List<&2,U32>, +chunks: List<&2,EntropyChunk>, escaped: Bool) -> Parsed(EntropyData):
  match bytes escaped:
    case Nil{} _: Fail{Truncated{}}
    case 255 <> rest _: entropyBytes(rest,reversed,chunks,True{})
    case 0 <> rest True{}: entropyBytes(rest,255 <> reversed,chunks,False{})
    case +marker <> +rest True{}:
      Bool.pick(Unit -> Parsed(EntropyData),U32.is_ge(marker,208) && U32.is_le(marker,215),
        _ => entropyBytes(rest,Nil{},EntropyChunk{List.reverse(&2,U32,reversed),marker} <> chunks,False{}),
        _ => Done{EntropyData{List.reverse(&2,EntropyChunk,EntropyChunk{List.reverse(&2,U32,reversed),0} <> chunks),255 <> marker <> rest}})(Unit{})
    case byte <> rest False{}: entropyBytes(rest,byte <> reversed,chunks,False{})

type Plan is Data: Plan{frame: Frame, scans: List<&2,Scan>, jfif: Bool, adobe: U32}
type Parsing is Data:
  Parsing{frame: Maybe<&2,Frame>, scans: List<&2,Scan>, codes: List<&2,CodeTable>, quantizers: List<&2,Quantizer>, interval: U32, jfif: Bool, adobe: U32}
type More is Data: More{state: Parsing, bytes: List<&2,U32>}
def withEntropy(scan: Scan, state: Parsing, entropy: EntropyData) -> More:
  match scan state entropy:
    case Scan{selected,start,end,high,low,interval,codes,quantizers,_} Parsing{frame,scans,allCodes,allQuantizers,intervalAll,jfif,adobe} EntropyData{chunks,rest}:
      More{Parsing{frame,Scan{selected,start,end,high,low,interval,codes,quantizers,chunks} <> scans,allCodes,allQuantizers,intervalAll,jfif,adobe},rest}
def scanFrame(data: List<&2,U32>, +rest: List<&2,U32>, +state: Parsing) -> Parsed(More):
  match state:
    case Parsing{None{},_,_,_,_,_,_}: Fail{ScanHeader{}}
    case Parsing{Some{+frame},+scans,+codes,+quantizers,+interval,+jfif,+adobe}:
      bind(Scan,More,readScan(data,interval,codes,quantizers,frame),scan => bind(EntropyData,More,entropyBytes(rest,Nil{},Nil{},False{}),entropy => Done{withEntropy(scan,Parsing{Some{frame},scans,codes,quantizers,interval,jfif,adobe},entropy)}))

def app(marker: U32, bytes: List<&2,U32>, jfif: Bool, adobe: U32) -> Sampling:
  match marker bytes:
    case 224 74 <> 70 <> 73 <> 70 <> 0 <> _: Sampling{1,adobe}
    case 238 65 <> 100 <> 111 <> 98 <> 101 <> _ <> _ <> _ <> _ <> _ <> _ <> value <> _: Sampling{Bool.pick(U32,jfif,1,0),value}
    case _ _: Sampling{Bool.pick(U32,jfif,1,0),adobe}
def appState(state: Parsing, flags: Sampling) -> Parsing:
  match state flags:
    case Parsing{frame,scans,codes,quantizers,interval,_,_} Sampling{jfif,adobe}: Parsing{frame,scans,codes,quantizers,interval,U32.is_eq(jfif,1),adobe}

def restartInterval(data: List<&2,U32>, rest: List<&2,U32>, frame: Maybe<&2,Frame>, scans: List<&2,Scan>, codes: List<&2,CodeTable>, quantizers: List<&2,Quantizer>, jfif: Bool, adobe: U32) -> Parsed(More):
  match data:
    case a <> b <> Nil{}: Done{More{Parsing{frame,scans,codes,quantizers,word16(a,b),jfif,adobe},rest}}
    case _: Fail{Restart{}}
def appFlags(marker: U32, data: List<&2,U32>, state: Parsing) -> Sampling:
  match state:
    case Parsing{_,_,_,_,_,jfif,adobe}: app(marker,data,jfif,adobe)

def avi(data: List<&2,U32>) -> Bool:
  match data:
    case 65 <> 86 <> 73 <> 49 <> 0 <> _: True{}
    case _: False{}
def defaultHuffman() -> List<&2,U32>:
  0 <> 0 <> 1 <> 5 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 2 <> 3 <> 4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> 16 <> 0 <> 2 <> 1 <> 3 <> 3 <> 2 <> 4 <> 3 <> 5 <> 5 <> 4 <> 4 <> 0 <> 0 <> 1 <> 125 <> 1 <> 2 <> 3 <> 0 <> 4 <> 17 <> 5 <> 18 <> 33 <> 49 <> 65 <> 6 <> 19 <> 81 <> 97 <> 7 <> 34 <> 113 <> 20 <> 50 <> 129 <> 145 <> 161 <> 8 <> 35 <> 66 <> 177 <> 193 <> 21 <> 82 <> 209 <> 240 <> 36 <> 51 <> 98 <> 114 <> 130 <> 9 <> 10 <> 22 <> 23 <> 24 <> 25 <> 26 <> 37 <> 38 <> 39 <> 40 <> 41 <> 42 <> 52 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 67 <> 68 <> 69 <> 70 <> 71 <> 72 <> 73 <> 74 <> 83 <> 84 <> 85 <> 86 <> 87 <> 88 <> 89 <> 90 <> 99 <> 100 <> 101 <> 102 <> 103 <> 104 <> 105 <> 106 <> 115 <> 116 <> 117 <> 118 <> 119 <> 120 <> 121 <> 122 <> 131 <> 132 <> 133 <> 134 <> 135 <> 136 <> 137 <> 138 <> 146 <> 147 <> 148 <> 149 <> 150 <> 151 <> 152 <> 153 <> 154 <> 162 <> 163 <> 164 <> 165 <> 166 <> 167 <> 168 <> 169 <> 170 <> 178 <> 179 <> 180 <> 181 <> 182 <> 183 <> 184 <> 185 <> 186 <> 194 <> 195 <> 196 <> 197 <> 198 <> 199 <> 200 <> 201 <> 202 <> 210 <> 211 <> 212 <> 213 <> 214 <> 215 <> 216 <> 217 <> 218 <> 225 <> 226 <> 227 <> 228 <> 229 <> 230 <> 231 <> 232 <> 233 <> 234 <> 241 <> 242 <> 243 <> 244 <> 245 <> 246 <> 247 <> 248 <> 249 <> 250 <> 1 <> 0 <> 3 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 2 <> 3 <> 4 <> 5 <> 6 <> 7 <> 8 <> 9 <> 10 <> 11 <> 17 <> 0 <> 2 <> 1 <> 2 <> 4 <> 4 <> 3 <> 4 <> 7 <> 5 <> 4 <> 4 <> 0 <> 1 <> 2 <> 119 <> 0 <> 1 <> 2 <> 3 <> 17 <> 4 <> 5 <> 33 <> 49 <> 6 <> 18 <> 65 <> 81 <> 7 <> 97 <> 113 <> 19 <> 34 <> 50 <> 129 <> 8 <> 20 <> 66 <> 145 <> 161 <> 177 <> 193 <> 9 <> 35 <> 51 <> 82 <> 240 <> 21 <> 98 <> 114 <> 209 <> 10 <> 22 <> 36 <> 52 <> 225 <> 37 <> 241 <> 23 <> 24 <> 25 <> 26 <> 38 <> 39 <> 40 <> 41 <> 42 <> 53 <> 54 <> 55 <> 56 <> 57 <> 58 <> 67 <> 68 <> 69 <> 70 <> 71 <> 72 <> 73 <> 74 <> 83 <> 84 <> 85 <> 86 <> 87 <> 88 <> 89 <> 90 <> 99 <> 100 <> 101 <> 102 <> 103 <> 104 <> 105 <> 106 <> 115 <> 116 <> 117 <> 118 <> 119 <> 120 <> 121 <> 122 <> 130 <> 131 <> 132 <> 133 <> 134 <> 135 <> 136 <> 137 <> 138 <> 146 <> 147 <> 148 <> 149 <> 150 <> 151 <> 152 <> 153 <> 154 <> 162 <> 163 <> 164 <> 165 <> 166 <> 167 <> 168 <> 169 <> 170 <> 178 <> 179 <> 180 <> 181 <> 182 <> 183 <> 184 <> 185 <> 186 <> 194 <> 195 <> 196 <> 197 <> 198 <> 199 <> 200 <> 201 <> 202 <> 210 <> 211 <> 212 <> 213 <> 214 <> 215 <> 216 <> 217 <> 218 <> 226 <> 227 <> 228 <> 229 <> 230 <> 231 <> 232 <> 233 <> 234 <> 242 <> 243 <> 244 <> 245 <> 246 <> 247 <> 248 <> 249 <> 250 <> Nil{}

def defaultTables(state: Parsing, defaults: List<&2,CodeTable>) -> Parsing:
  match state:
    case Parsing{frame,scans,codes,quantizers,interval,jfif,adobe}: Parsing{frame,scans,List.append(&2,CodeTable,codes,defaults),quantizers,interval,jfif,adobe}
def application(+marker: U32, +data: List<&2,U32>, +state: Parsing, +rest: List<&2,U32>) -> Parsed(More):
  +updated = appState(state,appFlags(marker,data,state))
  Bool.pick(Unit -> Parsed(More),U32.is_eq(marker,224) && avi(data),_ => bind(List<&2,CodeTable>,More,readHuffman(4n,defaultHuffman(),Nil{}),defaults => Done{More{defaultTables(updated,defaults),rest}}),_ => Done{More{updated,rest}})(Unit{})
def markerSegment(+marker: U32, data: List<&2,U32>, +rest: List<&2,U32>, +limit: Nat, +state: Parsing) -> Parsed(More):
  match marker state:
    case 192 Parsing{None{},scans,codes,quantizers,interval,jfif,adobe}: bind(Frame,More,readFrame(192,data,limit),frame => Done{More{Parsing{Some{frame},scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 193 Parsing{None{},scans,codes,quantizers,interval,jfif,adobe}: bind(Frame,More,readFrame(193,data,limit),frame => Done{More{Parsing{Some{frame},scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 194 Parsing{None{},scans,codes,quantizers,interval,jfif,adobe}: bind(Frame,More,readFrame(194,data,limit),frame => Done{More{Parsing{Some{frame},scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 195 Parsing{None{},scans,codes,quantizers,interval,jfif,adobe}: bind(Frame,More,readFrame(195,data,limit),frame => Done{More{Parsing{Some{frame},scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 196 Parsing{frame,scans,codes,quantizers,interval,jfif,adobe}: bind(List<&2,CodeTable>,More,readHuffman(4096n,data,codes),codes => Done{More{Parsing{frame,scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 219 Parsing{frame,scans,codes,quantizers,interval,jfif,adobe}: bind(List<&2,Quantizer>,More,readQuantizers(1024n,data,quantizers),quantizers => Done{More{Parsing{frame,scans,codes,quantizers,interval,jfif,adobe},rest}})
    case 221 Parsing{frame,scans,codes,quantizers,_,jfif,adobe}: restartInterval(data,rest,frame,scans,codes,quantizers,jfif,adobe)
    case 218 state: scanFrame(data,rest,state)
    case _ _:
      Bool.pick(Unit -> Parsed(More),(U32.is_ge(marker,224) && U32.is_le(marker,239)) || U32.is_eq(marker,254),_ => application(marker,data,state,rest),_ => Fail{Unsupported{marker}})(Unit{})
def finishPlan(bytes: List<&2,U32>, state: Parsing) -> Parsed(Plan):
  match bytes state:
    case Nil{} Parsing{Some{frame},+scan <> +scans,_,_,_,jfif,adobe}: Done{Plan{frame,List.reverse(&2,Scan,scan <> scans),jfif,adobe}}
    case _ _: Fail{FrameHeader{}}
def moreBytes(more: More) -> List<&2,U32>:
  match more:
    case More{_,bytes}: bytes
def moreState(more: More) -> Parsing:
  match more:
    case More{state,_}: state
def parseMarkers(fuel: Nat, bytes: List<&2,U32>, +limit: Nat, state: Parsing) -> Parsed(Plan):
  match fuel bytes:
    case 0n _: Fail{Truncated{}}
    case 1n+n 255 <> 255 <> rest: parseMarkers(n,255 <> rest,limit,state)
    case 1n+n 255 <> 217 <> rest: finishPlan(rest,state)
    case 1n+n 255 <> marker <> rest:
      bind(More,Plan,bind(Segment,More,segment(rest),+part => markerSegment(marker,segmentData(part),segmentRest(part),limit,state)),+more => parseMarkers(n,moreBytes(more),limit,moreState(more)))
    case _ _: Fail{Truncated{}}
def parseValid(bytes: List<&2,U32>, limit: Nat, size: Nat) -> Parsed(Plan):
  match bytes:
    case 255 <> 216 <> rest: parseMarkers(size,rest,limit,Parsing{None{},Nil{},Nil{},Nil{},0,False{},3})
    case _: Fail{Signature{}}
def parse(+bytes: List<&2,U32>, limit: Nat) -> Parsed(Plan): bind(Nat,Plan,byteCount(bytes,0n),size => parseValid(bytes,limit,size))

# Entropy reservoirs are MSB-first. Invalid reads remain invalid; a block driver
# checks the flag before advancing, so truncation never supplies valid zero bits.
type Bits is Data: Bits{bytes: List<&2,U32>, word: U32, count: U32, valid: Bool}
type Read is Data: Read{value: U32, bits: Bits}
def refill(fuel: Nat, +wanted: U32, bits: Bits) -> Bits:
  match fuel bits:
    case 0n bits: bits
    case _ Bits{Nil{},word,count,valid}: Bits{Nil{},word,count,valid}
    case 1n+n Bits{+byte <> +rest,+word,+count,+valid}:
      Bool.pick(Unit -> Bits,U32.is_ge(count,wanted),_ => Bits{byte <> rest,word,count,valid},_ => refill(n,wanted,Bits{rest,U32.or(U32.shln(word,8n),byte),(count + 8 : U32),valid}))(Unit{})
def readBits(+wanted: U32, bits: Bits) -> Read:
  match bits:
    case Bits{bytes,+word,+count,valid}:
      +remaining = Bool.pick(U32,U32.is_ge(count,wanted),(count - wanted : U32),0)
      Read{U32.and(U32.shrn(word,U32.to_nat(remaining)),(U32.shln(1,U32.to_nat(wanted)) - 1 : U32)),Bits{bytes,U32.and(word,(U32.shln(1,U32.to_nat(remaining)) - 1 : U32)),remaining,valid && U32.is_ge(count,wanted)}}
def take(+wanted: U32, bits: Bits) -> Read: readBits(wanted,refill(2n,wanted,bits))
def badBits(bits: Bits) -> Bits:
  match bits:
    case Bits{bytes,word,count,_}: Bits{bytes,word,count,False{}}
def readValue(read: Read) -> U32:
  match read:
    case Read{value,_}: value
def readRest(read: Read) -> Bits:
  match read:
    case Read{_,bits}: bits

def huffmanRead(rows: List<&2,Row>, code: U32, bits: Bits) -> Read:
  match rows:
    case Nil{}: Read{0,badBits(bits)}
    case Row{first,count,symbols} <> +rest:
      +read = take(1,bits)
      +next = (code * 2 + readValue(read) : U32)
      +index = (next - first : U32)
      Bool.pick(Unit -> Read,U32.is_lt(index,count),_ => Read{item(U32.to_nat(index),symbols),readRest(read)},_ => huffmanRead(rest,next,readRest(read)))(Unit{})
def symbol(tree: Huffman, bits: Bits) -> Read:
  match tree:
    case Huffman{rows}: huffmanRead(rows,0,bits)
def extend(+size: U32, +value: U32) -> U32:
  Bool.pick(U32,U32.is_eq(size,0) || U32.is_ge(value,U32.shln(1,U32.to_nat((size - 1 : U32)))),value,(value + 1 - U32.shln(1,U32.to_nat(size)) : U32))

type Block is Type: Block{bits: Bits, coefficients: Array<U32>, predictor: U32, eob: U32}
type Value is Type: Value{value: U32, block: Block}
def blockRead(read: Read, coefficients: Array<U32>, predictor: U32, eob: U32) -> Value:
  match read:
    case Read{value,bits}: Value{value,Block{bits,coefficients,predictor,eob}}
def blockBits(count: U32, block: Block) -> Value:
  match block:
    case Block{bits,coefficients,predictor,eob}: blockRead(take(count,bits),coefficients,predictor,eob)
def blockSymbol(tree: Huffman, block: Block) -> Value:
  match block:
    case Block{bits,coefficients,predictor,eob}: blockRead(symbol(tree,bits),coefficients,predictor,eob)
def invalidBlock(block: Block) -> Block:
  match block:
    case Block{bits,coefficients,predictor,eob}: Block{badBits(bits),coefficients,predictor,eob}
def blockSet(index: U32, value: U32, block: Block) -> Block:
  match block:
    case Block{bits,coefficients,predictor,eob}: Block{bits,Array.set(U32,coefficients,index,value),predictor,eob}
def blockFetched(bits: Bits, predictor: U32, eob: U32, fetched: Array<U32> & U32) -> Value:
  match fetched:
    case (coefficients,value): Value{value,Block{bits,coefficients,predictor,eob}}
def blockGet(index: U32, block: Block) -> Value:
  match block:
    case Block{bits,coefficients,predictor,eob}: blockFetched(bits,predictor,eob,Array.get(U32,coefficients,index))
def eobCount(count: U32, block: Block) -> Block:
  match block:
    case Block{bits,coefficients,predictor,_}: Block{bits,coefficients,predictor,count}
def dcValue(offset: U32, low: U32, size: U32, read: Value) -> Block:
  match read:
    case Value{value,Block{+bits,coefficients,predictor,eob}}:
      +next = (predictor + extend(size,value) : U32)
      +coefficient = U32.shln(next,U32.to_nat(low))
      Block{Bool.pick(Bits,U32.is_eq(signed16(next),next) && U32.is_eq(signed16(coefficient),coefficient),bits,badBits(bits)),Array.set(U32,coefficients,offset,coefficient),next,eob}
def dcSymbol(offset: U32, low: U32, read: Value) -> Block:
  match read:
    case Value{+size,block}:
      Bool.pick(Block -> Block,U32.is_le(size,11),block => dcValue(offset,low,size,blockBits(size,block)),block => invalidBlock(block))(block)

def checkedCoefficient(index: U32, +value: U32, block: Block) -> Block:
  Bool.pick(Block -> Block,U32.is_eq(value,signed16(value)),block => blockSet(index,value,block),block => invalidBlock(block))(block)
def acValue(index: U32, offset: U32, low: U32, size: U32, read: Value) -> Block:
  match read:
    case Value{value,block}: checkedCoefficient((offset + index : U32),U32.shln(extend(size,value),U32.to_nat(low)),block)
def eobValue(run: U32, read: Value) -> Block:
  match read:
    case Value{value,block}: eobCount((U32.shln(1,U32.to_nat(run)) + value - 1 : U32),block)

type AcStep is Type: AcStep{index: U32, block: Block}
def acSymbol(+index: U32, +end: U32, offset: U32, low: U32, read: Value) -> AcStep:
  match read:
    case Value{+code,block}:
      +run = U32.shrn(code,4n)
      +size = U32.and(code,15)
      +next = (index + run : U32)
      Bool.pick(Block -> AcStep,U32.is_eq(size,0),
        block => Bool.pick(Block -> AcStep,U32.is_eq(run,15),block => AcStep{(index + 16 : U32),Bool.pick(Block -> Block,U32.is_le((index + 16 : U32),(end + 1 : U32)),block => block,block => invalidBlock(block))(block)},block => AcStep{(end + 1 : U32),eobValue(run,blockBits(run,block))})(block),
        block => Bool.pick(Block -> AcStep,U32.is_le(next,end) && U32.is_le(size,10),block => AcStep{(next + 1 : U32),acValue(next,offset,low,size,blockBits(size,block))},block => AcStep{(end + 1 : U32),invalidBlock(block)})(block))(block)
def acLoop(fuel: Nat, +end: U32, +offset: U32, +low: U32, +tree: Huffman, step: AcStep) -> Block:
  match fuel step:
    case 0n AcStep{_,block}: block
    case 1n+n AcStep{+index,block}:
      Bool.pick(Block -> Block,U32.is_gt(index,end),block => block,block => acLoop(n,end,offset,low,tree,acSymbol(index,end,offset,low,blockSymbol(tree,block))))(block)
def firstAc(start: U32, +end: U32, offset: U32, low: U32, tree: Huffman, block: Block) -> Block:
  match block:
    case Block{bits,coefficients,predictor,+eob}:
      Bool.pick(Block -> Block,U32.is_gt(eob,0),block => eobCount((eob - 1 : U32),block),block => acLoop(65n,end,offset,low,tree,AcStep{maximum(start,1),block}))(Block{bits,coefficients,predictor,eob})

def refineValue(index: U32, +coefficient: U32, +bit: U32, read: Value) -> Block:
  match read:
    case Value{value,block}:
      +changed = Bool.pick(U32,U32.is_lt(coefficient,2147483648),(coefficient + bit : U32),(coefficient - bit : U32))
      +next = Bool.pick(U32,U32.is_eq(value,1) && U32.is_eq(U32.and(coefficient,bit),0),changed,coefficient)
      checkedCoefficient(index,next,block)
type Refining is Type: Refining{index: U32, zeros: U32, block: Block}
def refineStep(+index: U32, offset: U32, bit: U32, +zeros: U32, fetched: Value) -> Refining:
  match fetched:
    case Value{+coefficient,block}:
      Bool.pick(Block -> Refining,U32.is_eq(coefficient,0),block => Refining{(index + 1 : U32),(zeros - 1 : U32),block},block => Refining{(index + 1 : U32),zeros,refineValue((offset + index : U32),coefficient,bit,blockBits(1,block))})(block)
type Refinement is Type:
  Running{state: Refining}
  Stopped{state: Refining}
def refineWalkValue(+index: U32, +offset: U32, +bit: U32, +zeros: U32, fetched: Value) -> Refinement:
  match fetched:
    case Value{+coefficient,block}:
      Bool.pick(Block -> Refinement,U32.is_eq(coefficient,0) && U32.is_eq(zeros,0),block => Stopped{Refining{index,zeros,block}},block => Running{refineStep(index,offset,bit,zeros,Value{coefficient,block})})(block)
def refineWalk(fuel: Nat, +end: U32, +offset: U32, +bit: U32, state: Refinement) -> Refining:
  match fuel state:
    case _ Stopped{state}: state
    case 0n Running{state}: state
    case 1n+n Running{Refining{+index,+zeros,block}}:
      Bool.pick(Block -> Refining,U32.is_gt(index,end),block => Refining{index,zeros,block},block => refineWalk(n,end,offset,bit,refineWalkValue(index,offset,bit,zeros,blockGet((offset + index : U32),block))))(block)
def refinedEob(state: Refining) -> Block:
  match state:
    case Refining{_,_,block}: block

def refineDcFetched(offset: U32, bit: U32, fetched: Value) -> Block:
  match fetched:
    case Value{coefficient,block}: blockSet(offset,U32.or(coefficient,bit),block)
def refineDc(+offset: U32, low: U32, read: Value) -> Block:
  match read:
    case Value{bit,block}: refineDcFetched(offset,U32.shln(bit,U32.to_nat(low)),blockGet(offset,block))

def refineInserted(+end: U32, offset: U32, +value: U32, eob: Bool, refined: Refining) -> AcStep:
  match refined:
    case Refining{+index,zeros,block}:
      Bool.pick(Block -> AcStep,eob,block => AcStep{(end + 1 : U32),block},
        block => Bool.pick(Block -> AcStep,U32.is_le(index,end) && U32.is_eq(zeros,0),block => AcStep{(index + 1 : U32),blockSet((offset + index : U32),value,block)},block => AcStep{(end + 1 : U32),invalidBlock(block)})(block))(block)
def refineNewValue(index: U32, +end: U32, +offset: U32, +bit: U32, zeros: U32, read: Value) -> AcStep:
  match read:
    case Value{sign,block}:
      +value = Bool.pick(U32,U32.is_eq(sign,1),bit,(0 - bit : U32))
      refineInserted(end,offset,value,False{},refineWalk(64n,end,offset,bit,Running{Refining{index,zeros,block}}))
def refineSymbol(+index: U32, +end: U32, +offset: U32, +bit: U32, read: Value) -> AcStep:
  match read:
    case Value{+code,block}:
      +run = U32.shrn(code,4n)
      +size = U32.and(code,15)
      Bool.pick(Block -> AcStep,U32.is_eq(size,1),block => refineNewValue(index,end,offset,bit,run,blockBits(1,block)),
        block => Bool.pick(Block -> AcStep,U32.is_eq(size,0),
          block => Bool.pick(Block -> AcStep,U32.is_eq(run,15),
            block => refineInserted(end,offset,0,False{},refineWalk(64n,end,offset,bit,Running{Refining{index,15,block}})),
            block => refineInserted(end,offset,0,True{},refineWalk(64n,end,offset,bit,Running{Refining{index,64,eobValue(run,blockBits(run,block))}})))(block),
          block => AcStep{(end + 1 : U32),invalidBlock(block)})(block))(block)
def refineAcLoop(fuel: Nat, +end: U32, +offset: U32, +bit: U32, +tree: Huffman, step: AcStep) -> Block:
  match fuel step:
    case 0n AcStep{_,block}: block
    case 1n+n AcStep{+index,block}:
      Bool.pick(Block -> Block,U32.is_gt(index,end),block => block,block => refineAcLoop(n,end,offset,bit,tree,refineSymbol(index,end,offset,bit,blockSymbol(tree,block))))(block)
def refineAc(+start: U32, +end: U32, +offset: U32, +low: U32, tree: Huffman, block: Block) -> Block:
  match block:
    case Block{bits,coefficients,predictor,+eob}:
      Bool.pick(Block -> Block,U32.is_gt(eob,0),block => refinedEob(refineWalk(64n,end,offset,U32.shln(1,U32.to_nat(low)),Running{Refining{start,64,eobCount((eob - 1 : U32),block)}})),block => refineAcLoop(65n,end,offset,U32.shln(1,U32.to_nat(low)),tree,AcStep{start,block}))(Block{bits,coefficients,predictor,eob})

type Prepared is Data: Prepared{component: Component, dc: Huffman, ac: Huffman}
def findCode(tables: List<&2,CodeTable>, +index: U32) -> Parsed(Huffman):
  match tables:
    case Nil{}: Fail{InvalidHuffman{}}
    case CodeTable{id,+tree} <> +rest: Bool.pick(Unit -> Parsed(Huffman),U32.is_eq(id,index),_ => Done{tree},_ => findCode(rest,index))(Unit{})
def prepare(selected: List<&2,Selection>, +start: U32, +end: U32, +high: U32, +codes: List<&2,CodeTable>, reversed: List<&2,Prepared>) -> Parsed(List<&2,Prepared>):
  match selected:
    case Nil{}: Done{List.reverse(&2,Prepared,reversed)}
    case Selection{component,dc,ac} <> rest:
      bind(Huffman,List<&2,Prepared>,Bool.pick(Unit -> Parsed(Huffman),U32.is_eq(start,0) && U32.is_eq(high,0),_ => findCode(codes,dc),_ => Done{Huffman{Nil{}}})(Unit{}),dc =>
        bind(Huffman,List<&2,Prepared>,Bool.pick(Unit -> Parsed(Huffman),U32.is_gt(end,0),_ => findCode(codes,(16 + ac : U32)),_ => Done{Huffman{Nil{}}})(Unit{}),ac =>
          prepare(rest,start,end,high,codes,Prepared{component,dc,ac} <> reversed)))

def firstBlock(+offset: U32, +start: U32, end: U32, +low: U32, dc: Huffman, ac: Huffman, block: Block) -> Block:
  firstAc(start,end,offset,low,ac,Bool.pick(Block -> Block,U32.is_eq(start,0),block => dcSymbol(offset,low,blockSymbol(dc,block)),block => block)(block))
def decodeBlock(+offset: U32, +start: U32, +end: U32, high: U32, +low: U32, dc: Huffman, +ac: Huffman, block: Block) -> Block:
  Bool.pick(Block -> Block,U32.is_eq(high,0),block => firstBlock(offset,start,end,low,dc,ac,block),
    block => Bool.pick(Block -> Block,U32.is_eq(start,0),block => refineDc(offset,low,blockBits(1,block)),block => refineAc(start,end,offset,low,ac,block))(block))(block)

# DC predictors belong to components, while an AC end-of-band run belongs to
# the scan. Both reset at a restart; coefficient storage persists across scans.
type Predictors is Data: Predictors{a: U32, b: U32, c: U32, d: U32}
def predictor(index: U32, values: Predictors) -> U32:
  match index values:
    case 0 Predictors{a,_,_,_}: a
    case 1 Predictors{_,b,_,_}: b
    case 2 Predictors{_,_,c,_}: c
    case _ Predictors{_,_,_,d}: d
def updatePredictor(index: U32, value: U32, values: Predictors) -> Predictors:
  match index values:
    case 0 Predictors{_,b,c,d}: Predictors{value,b,c,d}
    case 1 Predictors{a,_,c,d}: Predictors{a,value,c,d}
    case 2 Predictors{a,b,_,d}: Predictors{a,b,value,d}
    case _ Predictors{a,b,c,_}: Predictors{a,b,c,value}
type Decoding is Type: Decoding{block: Block, predictors: Predictors}
def savePredictor(index: U32, values: Predictors, block: Block) -> Decoding:
  match block:
    case Block{bits,coefficients,+pred,eob}: Decoding{Block{bits,coefficients,pred,eob},updatePredictor(index,pred,values)}
def setPredictor(value: U32, block: Block) -> Block:
  match block:
    case Block{bits,coefficients,_,eob}: Block{bits,coefficients,value,eob}
def blockValid(block: Block) -> Result<&2,&1,Error,Block>:
  match block:
    case Block{Bits{bytes,word,count,True{}},coefficients,pred,eob}: Done{Block{Bits{bytes,word,count,True{}},coefficients,pred,eob}}
    case _: Fail{Entropy{}}

def blockGroup(count: Nat, +position: U32, +horizontal: U32, +columns: U32, +base: U32, +start: U32, +end: U32, +high: U32, +low: U32, +dc: Huffman, +ac: Huffman, result: Result<&2,&1,Error,Block>) -> Result<&2,&1,Error,Block>:
  match count result:
    case _ Fail{error}: Fail{error}
    case 0n result: result
    case 1n+n Done{block}:
      +offset = (base + ((position / horizontal) * columns + position % horizontal) * 64 : U32)
      blockGroup(n,(position + 1 : U32),horizontal,columns,base,start,end,high,low,dc,ac,blockValid(decodeBlock(offset,start,end,high,low,dc,ac,block)))
def groupResult(index: U32, values: Predictors, result: Result<&2,&1,Error,Block>) -> Result<&2,&1,Error,Decoding>:
  match result:
    case Fail{error}: Fail{error}
    case Done{block}: Done{savePredictor(index,values,block)}
def mcuComponents(components: List<&2,Prepared>, +interleaved: Bool, +x: U32, +y: U32, +index: U32, +start: U32, +end: U32, +high: U32, +low: U32, result: Result<&2,&1,Error,Decoding>) -> Result<&2,&1,Error,Decoding>:
  match components result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case Prepared{Component{_,+h,+v,_,_,_,+columns,_,offset},dc,ac} <> rest Done{Decoding{block,+values}}:
      +horizontal = Bool.pick(U32,interleaved,h,1)
      +vertical = Bool.pick(U32,interleaved,v,1)
      +base = (offset + (y * vertical * columns + x * horizontal) * 64 : U32)
      mcuComponents(rest,interleaved,x,y,(index + 1 : U32),start,end,high,low,
        groupResult(index,values,blockGroup(U32.to_nat((horizontal * vertical : U32)),0,horizontal,columns,base,start,end,high,low,dc,ac,Done{setPredictor(predictor(index,values),block)})))

type McuGrid is Data: McuGrid{columns: U32, rows: U32, interleaved: Bool}
def mcuGrid(frame: Frame, selected: List<&2,Selection>) -> McuGrid:
  match frame selected:
    case _ Selection{Component{_,_,_,_,width,height,_,_,_},_,_} <> Nil{}: McuGrid{ceiling(width,8),ceiling(height,8),False{}}
    case Frame{_,_,_,_,_,_,columns,rows,_,_} _: McuGrid{columns,rows,True{}}
type Eight is Data: Eight{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}
type Neighborhood is Type: Neighborhood{values: Eight, block: Block}
def prediction(mode: U32, +left: U32, +above: U32, +diagonal: U32) -> U32:
  match mode:
    case 0: 0
    case 1: left
    case 2: above
    case 3: diagonal
    case 4: (left + above - diagonal : U32)
    case 5: (left + shiftedSigned((above - diagonal : U32),1n) : U32)
    case 6: (above + shiftedSigned((left - diagonal : U32),1n) : U32)
    case _: ((left + above) / 2 : U32)
def losslessPredicted(+position: U32, +width: U32, offset: U32, predictorMode: U32, +precision: U32, +low: U32, +restart: U32, state: Neighborhood) -> Block:
  match state:
    case Neighborhood{Eight{_,_,_,_,_,left,above,diagonal},Block{bits,coefficients,difference,eob}}:
      +a = U32.shrn(left,U32.to_nat(low))
      +b = U32.shrn(above,U32.to_nat(low))
      +c = U32.shrn(diagonal,U32.to_nat(low))
      +initial = U32.shln(1,U32.to_nat((precision - low - 1 : U32)))
      +predicted = Bool.pick(U32,U32.is_eq(position,restart),initial,Bool.pick(U32,U32.is_lt((position - restart : U32),width),a,Bool.pick(U32,U32.is_eq((position % width : U32),0),b,prediction(predictorMode,a,b,c))))
      +mask = (U32.shln(1,U32.to_nat((precision - low : U32))) - 1 : U32)
      +value = U32.shln(U32.and((predicted + difference : U32),mask),U32.to_nat(low))
      Block{bits,Array.set(U32,coefficients,(offset + position : U32),value),0,eob}
def shiftEight(value: U32, values: Eight) -> Eight:
  match values:
    case Eight{_,b,c,d,e,f,g,h}: Eight{b,c,d,e,f,g,h,value}
def neighborFetched(values: Eight, fetched: Value) -> Neighborhood:
  match fetched:
    case Value{value,block}: Neighborhood{shiftEight(value,values),block}
def losslessNeighbors(count: Nat, +step: U32, +position: U32, +width: U32, +offset: U32, state: Neighborhood) -> Neighborhood:
  match count state:
    case 0n state: state
    case 1n+n Neighborhood{values,block}:
      +distance = Bool.pick(U32,U32.is_eq(step,0),1,Bool.pick(U32,U32.is_eq(step,1),width,(width + 1 : U32)))
      +index = (offset + Bool.pick(U32,U32.is_ge(position,distance),(position - distance : U32),0) : U32)
      losslessNeighbors(n,(step + 1 : U32),position,width,offset,neighborFetched(values,blockGet(index,block)))
def losslessDifference(+position: U32, +width: U32, +offset: U32, predictorMode: U32, precision: U32, low: U32, restart: U32, size: U32, read: Value) -> Block:
  match read:
    case Value{value,block}: losslessPredicted(position,width,offset,predictorMode,precision,low,restart,losslessNeighbors(3n,0,position,width,offset,Neighborhood{Eight{0,0,0,0,0,0,0,0},setPredictor(extend(size,value),block)}))
def losslessSymbol(+position: U32, +width: U32, +offset: U32, +predictorMode: U32, +precision: U32, +low: U32, +restart: U32, read: Value) -> Block:
  match read:
    case Value{+size,block}:
      Bool.pick(Block -> Block,U32.is_lt(size,16),block => losslessDifference(position,width,offset,predictorMode,precision,low,restart,size,blockBits(size,block)),
        block => Bool.pick(Block -> Block,U32.is_eq(size,16),block => losslessPredicted(position,width,offset,predictorMode,precision,low,restart,losslessNeighbors(3n,0,position,width,offset,Neighborhood{Eight{0,0,0,0,0,0,0,0},setPredictor(32768,block)})),block => invalidBlock(block))(block))(block)
def losslessComponents(components: List<&2,Prepared>, +position: U32, +width: U32, +predictorMode: U32, +precision: U32, +low: U32, +restart: U32, result: Result<&2,&1,Error,Decoding>) -> Result<&2,&1,Error,Decoding>:
  match components result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case Prepared{Component{_,_,_,_,_,_,_,_,offset},dc,_} <> rest Done{Decoding{block,values}}:
      losslessComponents(rest,position,width,predictorMode,precision,low,restart,groupResult(0,values,blockValid(losslessSymbol(position,width,offset,predictorMode,precision,low,restart,blockSymbol(dc,block)))))
def mcuLoop(count: Nat, +position: U32, +chunkStart: U32, +precision: U32, +columns: U32, +interleaved: Bool, +prepared: List<&2,Prepared>, +start: U32, +end: U32, +high: U32, +low: U32, result: Result<&2,&1,Error,Decoding>) -> Result<&2,&1,Error,Decoding>:
  match count result:
    case _ Fail{error}: Fail{error}
    case 0n result: result
    case 1n+n result: mcuLoop(n,(position + 1 : U32),chunkStart,precision,columns,interleaved,prepared,start,end,high,low,Bool.pick(Result<&2,&1,Error,Decoding> -> Result<&2,&1,Error,Decoding>,U32.is_eq(precision,0),result => mcuComponents(prepared,interleaved,(position % columns : U32),(position / columns : U32),0,start,end,high,low,result),result => losslessComponents(prepared,position,columns,start,precision,low,chunkStart,result))(result))
def finishEntropy(result: Result<&2,&1,Error,Decoding>) -> Result<&2,&1,Error,Array<U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoding{Block{Bits{Nil{},+word,+count,True{}},coefficients,_,0},_}}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Array<U32>>,U32.is_lt(count,8) && U32.is_eq(word,(U32.shln(1,U32.to_nat(count)) - 1 : U32)),coefficients => Done{coefficients},_ => Fail{Entropy{}})(coefficients)
    case _: Fail{Entropy{}}
def chunksLoop(chunks: List<&2,EntropyChunk>, +position: U32, +precision: U32, +total: U32, +columns: U32, +interleaved: Bool, +expected: U32, +interval: U32, +prepared: List<&2,Prepared>, +start: U32, +end: U32, +high: U32, +low: U32, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Array<U32>>:
  match chunks result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{coefficients}: Bool.pick(Array<U32> -> Result<&2,&1,Error,Array<U32>>,U32.is_eq(position,total),coefficients => Done{coefficients},_ => Fail{Restart{}})(coefficients)
    case EntropyChunk{bytes,+marker} <> +rest Done{coefficients}:
      +count = Bool.pick(U32,U32.is_eq(interval,0),(total - position : U32),minimum(interval,(total - position : U32)))
      +next = (position + count : U32)
      +valid = Bool.pick(Bool,U32.is_eq(marker,0),U32.is_eq(next,total),U32.is_gt(interval,0) && U32.is_lt(next,total) && U32.is_eq(marker,(208 + expected : U32)))
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Array<U32>>,valid && U32.is_lt(position,total),
        coefficients => chunksLoop(rest,next,precision,total,columns,interleaved,U32.and((expected + 1 : U32),7),interval,prepared,start,end,high,low,
          finishEntropy(mcuLoop(U32.to_nat(count),position,position,precision,columns,interleaved,prepared,start,end,high,low,Done{Decoding{Block{Bits{bytes,0,0,True{}},coefficients,0,0},Predictors{0,0,0,0}}}))),_ => Fail{Restart{}})(coefficients)
def decodePrepared(+precision: U32, grid: McuGrid, scan: Scan, prepared: Parsed(List<&2,Prepared>), coefficients: Array<U32>) -> Result<&2,&1,Error,Array<U32>>:
  match grid scan prepared:
    case _ _ Fail{error}: Fail{error}
    case McuGrid{+columns,rows,interleaved} Scan{_,start,end,high,low,+interval,_,_,chunks} Done{prepared}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Array<U32>>,U32.is_eq(precision,0) || U32.is_eq((interval % columns : U32),0),coefficients => chunksLoop(chunks,0,precision,(columns * rows : U32),columns,interleaved,0,interval,prepared,start,end,high,low,Done{coefficients}),_ => Fail{Restart{}})(coefficients)
def decodeScan(+frame: Frame, +scan: Scan, coefficients: Array<U32>) -> Result<&2,&1,Error,Array<U32>>:
  match frame scan:
    case Frame{+mode,+precision,+width,+height,+h,+v,+columns,+rows,+components,+cells} Scan{+selected,+start,+end,+high,+low,+interval,+codes,+quantizers,+chunks}:
      +lossless = U32.is_eq(mode,195)
      +grid = Bool.pick(McuGrid,lossless,McuGrid{width,height,True{}},mcuGrid(Frame{mode,precision,width,height,h,v,columns,rows,components,cells},selected))
      decodePrepared(Bool.pick(U32,lossless,precision,0),grid,Scan{selected,start,end,high,low,interval,codes,quantizers,chunks},prepare(selected,Bool.pick(U32,lossless,0,start),end,high,codes,Nil{}),coefficients)
def decodeScans(scans: List<&2,Scan>, +frame: Frame, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Array<U32>>:
  match scans result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case scan <> rest Done{coefficients}: decodeScans(rest,frame,decodeScan(frame,scan,coefficients))

# JPEG zigzag coefficient order to the spatial 8-by-8 matrix.
def zigzag(index: U32) -> U32:
  match index:
    case 0: 0
    case 1: 1
    case 2: 8
    case 3: 16
    case 4: 9
    case 5: 2
    case 6: 3
    case 7: 10
    case 8: 17
    case 9: 24
    case 10: 32
    case 11: 25
    case 12: 18
    case 13: 11
    case 14: 4
    case 15: 5
    case 16: 12
    case 17: 19
    case 18: 26
    case 19: 33
    case 20: 40
    case 21: 48
    case 22: 41
    case 23: 34
    case 24: 27
    case 25: 20
    case 26: 13
    case 27: 6
    case 28: 7
    case 29: 14
    case 30: 21
    case 31: 28
    case 32: 35
    case 33: 42
    case 34: 49
    case 35: 56
    case 36: 57
    case 37: 50
    case 38: 43
    case 39: 36
    case 40: 29
    case 41: 22
    case 42: 15
    case 43: 23
    case 44: 30
    case 45: 37
    case 46: 44
    case 47: 51
    case 48: 58
    case 49: 59
    case 50: 52
    case 51: 45
    case 52: 38
    case 53: 31
    case 54: 39
    case 55: 46
    case 56: 53
    case 57: 60
    case 58: 61
    case 59: 54
    case 60: 47
    case 61: 55
    case 62: 62
    case _: 63

def clamp(+value: U32) -> U32:
  Bool.pick(U32,U32.is_ge(value,2147483648),0,minimum(value,255))
def idctSample(value: U32, +shift: Nat) -> U32:
  +sample = shiftedSigned(value,shift)
  Bool.pick(U32,Nat.is_eq(shift,17n),clamp(sample),sample)

# Integer inverse kernel follows jpeg-decoder 0.3's portable implementation
# (itself based on stb_image), including its fixed-point rounding constants.
# First pass retains two fractional bits; the second adds the level shift.
def idctKernel(values: Eight, +bias: U32, +shift: Nat) -> Eight:
  match values:
    case Eight{+s0,+s1,+s2,+s3,+s4,+s5,+s6,+s7}:
      +even = ((s2 + s6) * 2217 : U32)
      +t2 = (even - s6 * 7567 : U32)
      +t3 = (even + s2 * 3135 : U32)
      +t0 = U32.shln((s0 + s4 : U32),12n)
      +t1 = U32.shln((s0 - s4 : U32),12n)
      +x0 = (t0 + t3 + bias : U32)
      +x3 = (t0 - t3 + bias : U32)
      +x1 = (t1 + t2 + bias : U32)
      +x2 = (t1 - t2 + bias : U32)
      +p3 = (s7 + s3 : U32)
      +p4 = (s5 + s1 : U32)
      +p5 = ((p3 + p4) * 4816 : U32)
      +p1 = (p5 - (s7 + s1) * 3685 : U32)
      +p2 = (p5 - (s5 + s3) * 10497 : U32)
      +q3 = (0 - p3 * 8034 : U32)
      +q4 = (0 - p4 * 1597 : U32)
      +a = (s7 * 1223 + p1 + q3 : U32)
      +b = (s5 * 8410 + p2 + q4 : U32)
      +c = (s3 * 12586 + p2 + q3 : U32)
      +d = (s1 * 6149 + p1 + q4 : U32)
      Eight{idctSample((x0 + d : U32),shift),idctSample((x1 + c : U32),shift),idctSample((x2 + b : U32),shift),idctSample((x3 + a : U32),shift),idctSample((x3 - a : U32),shift),idctSample((x2 - b : U32),shift),idctSample((x1 - c : U32),shift),idctSample((x0 - d : U32),shift)}

type Line is Type: Line{array: Array<U32>, values: Eight}
def gathered(values: Eight, fetched: Array<U32> & U32) -> Line:
  match fetched:
    case (array,value): Line{array,shiftEight(value,values)}
def gather(count: Nat, +index: U32, +stride: U32, line: Line) -> Line:
  match count line:
    case 0n line: line
    case 1n+n Line{array,values}: gather(n,(index + stride : U32),stride,gathered(values,Array.get(U32,array,index)))
def storeLine(+index: U32, +stride: U32, values: Eight, array: Array<U32>) -> Array<U32>:
  match values:
    case Eight{a,b,c,d,e,f,g,h}:
      array = Array.set(U32,array,index,a)
      array = Array.set(U32,array,(index + stride : U32),b)
      array = Array.set(U32,array,(index + stride * 2 : U32),c)
      array = Array.set(U32,array,(index + stride * 3 : U32),d)
      array = Array.set(U32,array,(index + stride * 4 : U32),e)
      array = Array.set(U32,array,(index + stride * 5 : U32),f)
      array = Array.set(U32,array,(index + stride * 6 : U32),g)
      Array.set(U32,array,(index + stride * 7 : U32),h)
def transformedLine(index: U32, stride: U32, bias: U32, shift: Nat, line: Line) -> Array<U32>:
  match line:
    case Line{array,values}: storeLine(index,stride,idctKernel(values,bias,shift),array)
def transformLines(count: Nat, +index: U32, +advance: U32, +stride: U32, +bias: U32, +shift: Nat, array: Array<U32>) -> Array<U32>:
  match count:
    case 0n: array
    case 1n+n: transformLines(n,(index + advance : U32),advance,stride,bias,shift,transformedLine(index,stride,bias,shift,gather(8n,index,stride,Line{array,Eight{0,0,0,0,0,0,0,0}})))

type Tile is Type: Tile{coefficients: Array<U32>, samples: Array<U32>}
def dequantized(index: U32, quantizer: U32, samples: Array<U32>, fetched: Array<U32> & U32) -> Tile:
  match fetched:
    case (coefficients,value): Tile{coefficients,Array.set(U32,samples,zigzag(index),(signed16(value) * quantizer : U32))}
def dequantize(quantizers: List<&2,U32>, +index: U32, +base: U32, tile: Tile) -> Tile:
  match quantizers tile:
    case Nil{} tile: tile
    case quantizer <> rest Tile{coefficients,samples}: dequantize(rest,(index + 1 : U32),base,dequantized(index,quantizer,samples,Array.get(U32,coefficients,(base + index : U32))))
def transformed(tile: Tile) -> Tile:
  match tile:
    case Tile{coefficients,samples}: Tile{coefficients,transformLines(8n,0,8,1,16842752,17n,transformLines(8n,0,1,8,512,10n,samples))}
def sampleStored(index: U32, coefficients: Array<U32>, fetched: Array<U32> & U32) -> Tile:
  match fetched:
    case (samples,value): Tile{Array.set(U32,coefficients,index,value),samples}
def storeTile(count: Nat, +index: U32, +base: U32, tile: Tile) -> Array<U32>:
  match count tile:
    case 0n Tile{coefficients,_}: coefficients
    case 1n+n Tile{coefficients,samples}: storeTile(n,(index + 1 : U32),base,sampleStored((base + index : U32),coefficients,Array.get(U32,samples,index)))
def transformBlocks(count: Nat, +base: U32, +quantizers: List<&2,U32>, coefficients: Array<U32>) -> Array<U32>:
  match count:
    case 0n: coefficients
    case 1n+n: transformBlocks(n,(base + 64 : U32),quantizers,storeTile(64n,0,base,transformed(dequantize(quantizers,0,base,Tile{coefficients,Array.new(U32,6n,0)}))))
def findQuantizer(tables: List<&2,Quantizer>, +index: U32) -> Parsed(List<&2,U32>):
  match tables:
    case Nil{}: Fail{Quantization{}}
    case Quantizer{id,+values} <> +rest: Bool.pick(Unit -> Parsed(List<&2,U32>),U32.is_eq(id,index),_ => Done{values},_ => findQuantizer(rest,index))(Unit{})
def scanQuantizer(scans: List<&2,Scan>, +id: U32, +index: U32) -> Parsed(List<&2,U32>):
  match scans:
    case Nil{}: Fail{ScanHeader{}}
    case Scan{selected,_,_,_,_,_,_,quantizers,_} <> +rest: Bool.pick(Unit -> Parsed(List<&2,U32>),selectedBefore(selected,id),_ => findQuantizer(quantizers,index),_ => scanQuantizer(rest,id,index))(Unit{})
def transformComponent(component: Component, quantizers: Parsed(List<&2,U32>), coefficients: Array<U32>) -> Result<&2,&1,Error,Array<U32>>:
  match component quantizers:
    case _ Fail{error}: Fail{error}
    case Component{_,_,_,_,_,_,columns,rows,offset} Done{values}: Done{transformBlocks(U32.to_nat(columns) * U32.to_nat(rows),offset,values,coefficients)}
def transformComponents(components: List<&2,Component>, +scans: List<&2,Scan>, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Array<U32>>:
  match components result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case Component{+id,+h,+v,+q,+w,+height,+columns,+rows,+offset} <> rest Done{coefficients}:
      transformComponents(rest,scans,transformComponent(Component{id,h,v,q,w,height,columns,rows,offset},scanQuantizer(scans,id,q),coefficients))

type Sampler is Data:
  Sampler{width: U32, height: U32, columns: U32, offset: U32, horizontal: U32, vertical: U32, interpolation: U32}
def samplers(components: List<&2,Component>, +width: U32, +height: U32, +h: U32, +v: U32, reversed: List<&2,Sampler>) -> List<&2,Sampler>:
  match components:
    case Nil{}: List.reverse(&2,Sampler,reversed)
    case Component{_,+ch,+cv,_,cw,heightC,columns,_,offset} <> rest:
      +horizontal = Bool.pick(U32,U32.is_eq(width,1),1,(h / ch : U32))
      +vertical = Bool.pick(U32,U32.is_eq(height,1),1,(v / cv : U32))
      +mode = Bool.pick(U32,U32.is_le(horizontal,2) && U32.is_le(vertical,2),((horizontal - 1) + 2 * (vertical - 1) : U32),0)
      samplers(rest,width,height,h,v,Sampler{cw,heightC,columns,offset,horizontal,vertical,mode} <> reversed)
def neighbor(+coordinate: U32, +size: U32, position: U32) -> U32:
  Bool.pick(U32,U32.is_eq(U32.and(position,1),0),Bool.pick(U32,U32.is_gt(coordinate,0),(coordinate - 1 : U32),0),minimum((coordinate + 1 : U32),(size - 1 : U32)))
def sampleIndex(+x: U32, +y: U32, columns: U32, offset: U32) -> U32:
  (offset + ((y / 8) * columns + x / 8) * 64 + (y % 8) * 8 + x % 8 : U32)
type Tap is Data: Tap{index: U32, weight: U32}
type Filter is Data: Filter{taps: List<&2,Tap>, shift: Nat, bias: U32}
def filter(+x: U32, +y: U32, sampler: Sampler) -> Filter:
  match sampler:
    case Sampler{width,height,+columns,+offset,+h,+v,+mode}:
      +nearX = (x / h : U32)
      +nearY = (y / v : U32)
      +farX = neighbor(nearX,width,x)
      +farY = neighbor(nearY,height,y)
      +near = Bool.pick(U32,U32.is_eq(mode,4),(offset + nearY * columns + nearX : U32),sampleIndex(nearX,nearY,columns,offset))
      +horizontal = sampleIndex(farX,nearY,columns,offset)
      +vertical = sampleIndex(nearX,farY,columns,offset)
      +diagonal = sampleIndex(farX,farY,columns,offset)
      Bool.pick(Filter,U32.is_eq(mode,3),Filter{Tap{near,9} <> Tap{horizontal,3} <> Tap{vertical,3} <> Tap{diagonal,1} <> Nil{},4n,8},
        Bool.pick(Filter,U32.is_eq(mode,1),Filter{Tap{near,3} <> Tap{horizontal,1} <> Nil{},2n,2},
          Bool.pick(Filter,U32.is_eq(mode,2),Filter{Tap{near,3} <> Tap{vertical,1} <> Nil{},2n,2},Filter{Tap{near,1} <> Nil{},0n,0})))
type Sample is Type: Sample{array: Array<U32>, value: U32}
def sampleAdded(weight: U32, total: U32, fetched: Array<U32> & U32) -> Sample:
  match fetched:
    case (array,value): Sample{array,(total + weight * value : U32)}
def sampleTaps(taps: List<&2,Tap>, sample: Sample) -> Sample:
  match taps sample:
    case Nil{} sample: sample
    case Tap{index,weight} <> rest Sample{array,value}: sampleTaps(rest,sampleAdded(weight,value,Array.get(U32,array,index)))
def sampleRounded(shift: Nat, bias: U32, sample: Sample) -> Sample:
  match sample:
    case Sample{array,value}: Sample{array,U32.shrn((value + bias : U32),shift)}
def sampleFiltered(filter: Filter, array: Array<U32>) -> Sample:
  match filter:
    case Filter{taps,shift,bias}: sampleRounded(shift,bias,sampleTaps(taps,Sample{array,0}))
def pixelSampled(values: Eight, sample: Sample) -> Line:
  match sample:
    case Sample{array,value}: Line{array,shiftEight(value,values)}
def pixelSamples(samplers: List<&2,Sampler>, +x: U32, +y: U32, line: Line) -> Line:
  match samplers line:
    case Nil{} line: line
    case sampler <> rest Line{array,values}: pixelSamples(rest,x,y,pixelSampled(values,sampleFiltered(filter(x,y,sampler),array)))

type Color is Data:
  Gray{}
  Gray16{}
  InvertedCmyk{}
  Rgb{}
  Ycbcr{}
  Cmyk{}
  Ycck{}
def colorSpace(components: List<&2,Component>, +jfif: Bool, +adobe: U32) -> Parsed(Color):
  match components:
    case _ <> Nil{}: Done{Gray{}}
    case a <> b <> c <> Nil{}:
      +first = componentId(a)
      +second = componentId(b)
      +third = componentId(c)
      Bool.pick(Parsed(Color),U32.is_eq(first,1) && U32.is_eq(second,2) && U32.is_eq(third,3),Done{Ycbcr{}},
        Bool.pick(Parsed(Color),U32.is_eq(first,82) && U32.is_eq(second,71) && U32.is_eq(third,66),Done{Rgb{}},
          Bool.pick(Parsed(Color),(U32.is_eq(first,1) && U32.is_eq(second,34) && U32.is_eq(third,35)) || (U32.is_eq(first,114) && U32.is_eq(second,103) && U32.is_eq(third,98)),Fail{Unsupported{238}},
            Bool.pick(Parsed(Color),jfif || U32.is_eq(adobe,1) || U32.is_eq(adobe,3),Done{Ycbcr{}},Bool.pick(Parsed(Color),U32.is_eq(adobe,0),Done{Rgb{}},Fail{FrameHeader{}})))))
    case _ <> _ <> _ <> _ <> Nil{}: Bool.pick(Parsed(Color),U32.is_eq(adobe,0) || U32.is_eq(adobe,3),Done{Cmyk{}},Bool.pick(Parsed(Color),U32.is_eq(adobe,2),Done{Ycck{}},Fail{FrameHeader{}}))
    case _: Fail{FrameHeader{}}
def rgba(r: U32, g: U32, b: U32) -> U32: U32.or(U32.shln(r,24n),U32.or(U32.shln(g,16n),U32.or(U32.shln(b,8n),255)))
def rgb(y: U32, cb: U32, cr: U32) -> Eight:
  +luma = (y * 1048576 + 524288 : U32)
  +blue = (cb - 128 : U32)
  +red = (cr - 128 : U32)
  Eight{0,0,0,0,0,clamp(shiftedSigned((luma + red * 1470104 : U32),20n)),clamp(shiftedSigned((luma - blue * 360857 - red * 748830 : U32),20n)),clamp(shiftedSigned((luma + blue * 1858077 : U32),20n))}
def ycckRgb(+k: U32, values: Eight) -> U32:
  match values:
    case Eight{_,_,_,_,_,r,g,b}: rgba(((255 - r) * k / 255 : U32),((255 - g) * k / 255 : U32),((255 - b) * k / 255 : U32))
def packedRgb(values: Eight) -> U32:
  match values:
    case Eight{_,_,_,_,_,r,g,b}: rgba(r,g,b)
def colorPixel(color: Color, values: Eight) -> U32:
  match color values:
    case Gray{} Eight{_,_,_,_,_,_,_,+gray}: rgba(gray,gray,gray)
    case Gray16{} Eight{_,_,_,_,_,_,_,+gray}:
      +byte = ((gray * 255 + 32767) / 65535 : U32)
      rgba(byte,byte,byte)
    case InvertedCmyk{} Eight{_,_,_,_,c,m,y,+k}: rgba(((255 - c) * (255 - k) / 255 : U32),((255 - m) * (255 - k) / 255 : U32),((255 - y) * (255 - k) / 255 : U32))
    case Rgb{} Eight{_,_,_,_,_,r,g,b}: rgba(r,g,b)
    case Ycbcr{} Eight{_,_,_,_,_,y,cb,cr}: packedRgb(rgb(y,cb,cr))
    case Cmyk{} Eight{_,_,_,_,c,m,y,+k}: rgba((c * k / 255 : U32),(m * k / 255 : U32),(y * k / 255 : U32))
    case Ycck{} Eight{_,_,_,_,y,cb,cr,k}: ycckRgb(k,rgb(y,cb,cr))
type Pixels is Type: Pixels{samples: Array<U32>, output: Array<U32>}
def pixelStored(index: U32, color: Color, output: Array<U32>, sampled: Line) -> Pixels:
  match sampled:
    case Line{samples,values}: Pixels{samples,Array.set(U32,output,index,colorPixel(color,values))}
def renderPixels(count: Nat, +index: U32, +width: U32, +color: Color, +samplers: List<&2,Sampler>, pixels: Pixels) -> Array<U32>:
  match count pixels:
    case 0n Pixels{_,output}: output
    case 1n+n Pixels{samples,output}: renderPixels(n,(index + 1 : U32),width,color,samplers,pixelStored(index,color,output,pixelSamples(samplers,(index % width : U32),(index / width : U32),Line{samples,Eight{0,0,0,0,0,0,0,0}})))
def losslessSamplers(components: List<&2,Component>, reversed: List<&2,Sampler>) -> List<&2,Sampler>:
  match components:
    case Nil{}: List.reverse(&2,Sampler,reversed)
    case Component{_,_,_,_,width,height,columns,_,offset} <> rest: losslessSamplers(rest,Sampler{width,height,columns,offset,1,1,4} <> reversed)
def render(frame: Frame, color: Color, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Image.Raster>:
  match frame result:
    case _ Fail{error}: Fail{error}
    case Frame{mode,_,+width,+height,h,v,_,_,+components,_} Done{samples}:
      +count = (width * height : U32)
      Done{Image.Raster{width,height,renderPixels(U32.to_nat(count),0,width,color,Bool.pick(List<&2,Sampler>,U32.is_eq(mode,195),losslessSamplers(components,Nil{}),samplers(components,width,height,h,v,Nil{})),Pixels{samples,Array.new(U32,Image.depth(31n,count,1,0n),0)})}}
def decodeColor(+frame: Frame, +scans: List<&2,Scan>, choice: Parsed(Color)) -> Result<&2,&1,Error,Image.Raster>:
  match frame choice:
    case _ Fail{error}: Fail{error}
    case Frame{+mode,+precision,+width,+height,+h,+v,+columns,+rows,+components,+cells} Done{color}:
      +layout = {Frame{mode,precision,width,height,h,v,columns,rows,components,cells} : Frame}
      render(layout,color,Bool.pick(Result<&2,&1,Error,Array<U32>> -> Result<&2,&1,Error,Array<U32>>,U32.is_eq(mode,195),result => result,result => transformComponents(components,scans,result))(decodeScans(scans,layout,Done{Array.new(U32,Image.depth(31n,cells,1,0n),0)})))
def losslessColor(components: List<&2,Component>, precision: U32) -> Parsed(Color):
  match components precision:
    case _ <> Nil{} 8: Done{Gray{}}
    case _ <> Nil{} 16: Done{Gray16{}}
    case _ <> _ <> _ <> Nil{} 8: Done{Rgb{}}
    case _ <> _ <> _ <> _ <> Nil{} 8: Done{InvertedCmyk{}}
    case _ _: Fail{Unsupported{195}}
def frameColor(frame: Frame, jfif: Bool, adobe: U32) -> Parsed(Color):
  match frame:
    case Frame{mode,precision,_,_,_,_,_,_,+components,_}: Bool.pick(Parsed(Color),U32.is_eq(mode,195),losslessColor(components,precision),colorSpace(components,jfif,adobe))
def decodePlan(plan: Parsed(Plan)) -> Result<&2,&1,Error,Image.Raster>:
  match plan:
    case Fail{error}: Fail{error}
    case Done{Plan{+frame,scans,jfif,adobe}}: decodeColor(frame,scans,frameColor(frame,jfif,adobe))
def planChecked(plan: Plan, result: Parsed(Unit)) -> Parsed(Plan):
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{plan}
type Band is Data: Band{id: U32, levels: List<&2,U32>}
def emptyLevels(count: Nat, values: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: values
    case 1n+n: emptyLevels(n,255 <> values)
def emptyBands(components: List<&2,Component>) -> List<&2,Band>:
  match components:
    case Nil{}: Nil{}
    case component <> rest: Band{componentId(component),emptyLevels(64n,Nil{})} <> emptyBands(rest)
def completeBands(bands: List<&2,Band>) -> Parsed(Unit):
  match bands:
    case Nil{}: Done{Unit{}}
    case Band{_,first <> _} <> +rest: Bool.pick(Unit -> Parsed(Unit),Bool.not(U32.is_eq(first,255)),_ => completeBands(rest),_ => Fail{ScanHeader{}})(Unit{})
    case _: Fail{ScanHeader{}}
def updateLevels(levels: List<&2,U32>, +index: U32, +start: U32, +end: U32, +high: U32, +low: U32, reversed: List<&2,U32>) -> Parsed(List<&2,U32>):
  match levels:
    case Nil{}: Done{List.reverse(&2,U32,reversed)}
    case +previous <> +rest:
      +included = U32.is_ge(index,start) && U32.is_le(index,end)
      +valid = Bool.not(included) || ((U32.is_eq(high,0) && U32.is_eq(previous,255)) || (U32.is_gt(high,0) && U32.is_eq(previous,high)))
      Bool.pick(Unit -> Parsed(List<&2,U32>),valid,_ => updateLevels(rest,(index + 1 : U32),start,end,high,low,Bool.pick(U32,included,low,previous) <> reversed),_ => Fail{ScanHeader{}})(Unit{})
def updateBands(bands: List<&2,Band>, +id: U32, +start: U32, +end: U32, +high: U32, +low: U32, +reversed: List<&2,Band>) -> Parsed(List<&2,Band>):
  match bands:
    case Nil{}: Fail{ScanHeader{}}
    case Band{+found,+levels} <> +rest:
      Bool.pick(Unit -> Parsed(List<&2,Band>),U32.is_eq(found,id),
        _ => Bool.pick(Unit -> Parsed(List<&2,Band>),U32.is_eq(start,0) || Bool.not(U32.is_eq(item(0n,levels),255)),
          _ => bind(List<&2,U32>,List<&2,Band>,updateLevels(levels,0,start,end,high,low,Nil{}),levels => Done{List.reverse.go(&2,Band,reversed,Band{found,levels} <> rest)}),_ => Fail{ScanHeader{}})(Unit{}),
        _ => updateBands(rest,id,start,end,high,low,Band{found,levels} <> reversed))(Unit{})
def selectionsBands(selected: List<&2,Selection>, +start: U32, +end: U32, +high: U32, +low: U32, result: Parsed(List<&2,Band>)) -> Parsed(List<&2,Band>):
  match selected result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case Selection{component,_,_} <> rest Done{bands}: selectionsBands(rest,start,end,high,low,updateBands(bands,componentId(component),start,end,high,low,Nil{}))
def checkScans(scans: List<&2,Scan>, +lossless: Bool, result: Parsed(List<&2,Band>)) -> Parsed(Unit):
  match scans result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{bands}: completeBands(bands)
    case Scan{selected,start,end,high,low,_,_,_,_} <> rest result:
      checkScans(rest,lossless,selectionsBands(selected,Bool.pick(U32,lossless,0,start),end,high,low,result))
def validatePlan(plan: Parsed(Plan)) -> Parsed(Plan):
  match plan:
    case Fail{error}: Fail{error}
    case Done{Plan{Frame{+mode,+precision,+width,+height,+h,+v,+columns,+rows,+components,+cells},+scans,+jfif,+adobe}}:
      planChecked(Plan{Frame{mode,precision,width,height,h,v,columns,rows,components,cells},scans,jfif,adobe},checkScans(scans,U32.is_eq(mode,195),Done{emptyBands(components)}))

def decode(bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Image.Raster>: decodePlan(validatePlan(parse(bytes,limit)))

# Lossless predictions operate on point-transformed samples. The buffer stores
# restored samples, so neighbors are shifted back before prediction; restarts
# reset the initial sample and first-line predictor as specified by T.81 H.1.2.1.

# Each progressive coefficient is introduced once and then refined one bit at
# a time. This map is checked before allocating image-sized coefficient buffers.

# Annex K standard tables for AVI1/MJPEG streams with omitted DHT segments.
