import Base
import ./image.bend as Image

# Decode GIF's first image into its logical screen. Animation disposal and the
# background-color hint do not affect the still-image RGBA result.
type Error is Data:
  Signature{}
  InvalidByte{}
  Truncated{}
  Dimensions{}
  PixelLimit{}
  FrameBounds{}
  Block{}
  PaletteIndex{}
  CodeSize{}
  InvalidCode{}
  OutputLength{}
  MissingEnd{}

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>

def bind(-A: Data, -B: Data, result: Parsed(A), next: A -> Parsed(B)) -> Parsed(B):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{value}: next(value)

def length(bytes: List<&2,U32>, count: Nat) -> Parsed(Nat):
  match bytes:
    case Nil{}: Done{count}
    case byte <> +rest:
      Bool.pick(Unit -> Parsed(Nat),U32.is_le(byte,255),_ => length(rest,1n + count),_ => Fail{InvalidByte{}})(Unit{})

def u16(a: U32, b: U32) -> U32: (a + b * 256 : U32)

type Slice is Data: Slice{bytes: List<&2,U32>, rest: List<&2,U32>}

def take(count: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(Slice):
  match count bytes:
    case 0n rest: Done{Slice{List.reverse(&2,U32,reversed),rest}}
    case 1n+n byte <> rest: take(n,rest,byte <> reversed)
    case _ Nil{}: Fail{Truncated{}}

# Data subblocks can split a compressed code at any byte; the bit reader sees
# their concatenation, after all subblock bounds and the terminator are checked.
def subblocks(fuel: Nat, remaining: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(Slice):
  match fuel remaining bytes:
    case _ 0n 0 <> rest: Done{Slice{List.reverse(&2,U32,reversed),rest}}
    case 1n+n 0n count <> rest: subblocks(n,U32.to_nat(count),rest,reversed)
    case 1n+n 1n+left byte <> rest: subblocks(n,left,rest,byte <> reversed)
    case _ _ _: Fail{Truncated{}}

type Frame is Data:
  Frame{screenWidth: U32, screenHeight: U32, left: U32, top: U32, width: U32, height: U32, interlaced: Bool, palette: List<&2,U32>, transparent: Maybe<&2,U32>, minimum: U32, compressed: List<&2,U32>}

def assembledFrame(width: U32, height: U32, left: U32, top: U32, frameWidth: U32, frameHeight: U32, interlaced: Bool, palette: List<&2,U32>, transparent: Maybe<&2,U32>, minimum: U32, value: Slice) -> Parsed(Frame):
  match value:
    case Slice{bytes,_}: Done{Frame{width,height,left,top,frameWidth,frameHeight,interlaced,palette,transparent,minimum,bytes}}

def imageData(fuel: Nat, width: U32, height: U32, left: U32, top: U32, frameWidth: U32, frameHeight: U32, interlaced: Bool, palette: List<&2,U32>, transparent: Maybe<&2,U32>, bytes: List<&2,U32>) -> Parsed(Frame):
  match bytes:
    case +minimum <> rest:
      Bool.pick(Unit -> Parsed(Frame),U32.is_ge(minimum,2) && U32.is_le(minimum,8),
        _ => bind(Slice,Frame,subblocks(fuel,0n,rest,Nil{}),value => assembledFrame(width,height,left,top,frameWidth,frameHeight,interlaced,palette,transparent,minimum,value)),_ => Fail{CodeSize{}})(Unit{})
    case _: Fail{Truncated{}}

def localPalette(fuel: Nat, width: U32, height: U32, left: U32, top: U32, frameWidth: U32, frameHeight: U32, interlaced: Bool, transparent: Maybe<&2,U32>, value: Slice) -> Parsed(Frame):
  match value:
    case Slice{palette,rest}: imageData(fuel,width,height,left,top,frameWidth,frameHeight,interlaced,palette,transparent,rest)

def descriptor(+fuel: Nat, +width: U32, +height: U32, palette: List<&2,U32>, +transparent: Maybe<&2,U32>, bytes: List<&2,U32>) -> Parsed(Frame):
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> +flags <> +rest:
      +left = u16(a,b)
      +top = u16(c,d)
      +frameWidth = u16(e,f)
      +frameHeight = u16(g,h)
      +interlaced = U32.is_gt(U32.and(flags,64),0)
      Bool.pick(Unit -> Parsed(Frame),U32.is_gt(frameWidth,0) && U32.is_gt(frameHeight,0) && U32.is_le((left + frameWidth : U32),width) && U32.is_le((top + frameHeight : U32),height) && U32.is_eq(U32.and(flags,24),0),
        _ => Bool.pick(Unit -> Parsed(Frame),U32.is_gt(U32.and(flags,128),0),
          _ => bind(Slice,Frame,take(3n * U32.to_nat(U32.shln(2,U32.to_nat(U32.and(flags,7)))),rest,Nil{}),value => localPalette(fuel,width,height,left,top,frameWidth,frameHeight,interlaced,transparent,value)),
          _ => imageData(fuel,width,height,left,top,frameWidth,frameHeight,interlaced,palette,transparent,rest))(Unit{}),_ => Fail{FrameBounds{}})(Unit{})
    case _: Fail{Truncated{}}

type Metadata is Data: Metadata{bytes: List<&2,U32>, transparent: Maybe<&2,U32>}

def skippedExtension(transparent: Maybe<&2,U32>, value: Slice) -> Parsed(Metadata):
  match value:
    case Slice{_,rest}: Done{Metadata{rest,transparent}}

def extension(fuel: Nat, transparent: Maybe<&2,U32>, bytes: List<&2,U32>) -> Parsed(Metadata):
  match bytes:
    case 249 <> 4 <> +flags <> _ <> _ <> index <> 0 <> rest:
      Bool.pick(Parsed(Metadata),U32.is_eq(U32.and(flags,224),0),Done{Metadata{rest,Bool.pick(Maybe<&2,U32>,U32.is_eq(U32.and(flags,1),1),Some{index},None{})}},Fail{Block{}})
    case 249 <> _: Fail{Block{}}
    case _ <> rest: bind(Slice,Metadata,subblocks(fuel,0n,rest,Nil{}),value => skippedExtension(transparent,value))
    case _: Fail{Truncated{}}

def blocks(fuel: Nat, +width: U32, +height: U32, +palette: List<&2,U32>, state: Parsed(Metadata)) -> Parsed(Frame):
  match fuel state:
    case _ Fail{cause}: Fail{cause}
    case 1n+n Done{Metadata{44 <> rest,transparent}}: descriptor(n,width,height,palette,transparent,rest)
    case 1n+ +n Done{Metadata{33 <> rest,transparent}}: blocks(n,width,height,palette,extension(n,transparent,rest))
    case _ Done{Metadata{Nil{},_}}: Fail{Truncated{}}
    case _ _: Fail{Block{}}

def globalPalette(fuel: Nat, width: U32, height: U32, value: Slice) -> Parsed(Frame):
  match value:
    case Slice{palette,rest}: blocks(fuel,width,height,palette,Done{Metadata{rest,None{}}})

def logical(fuel: Nat, limit: Nat, bytes: List<&2,U32>) -> Parsed(Frame):
  match bytes:
    case a <> b <> c <> d <> +flags <> _ <> _ <> +rest:
      +width = u16(a,b)
      +height = u16(c,d)
      Bool.pick(Unit -> Parsed(Frame),Image.validDimensions(width,height),
        _ => Bool.pick(Unit -> Parsed(Frame),Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit),
          _ => bind(Slice,Frame,take(Bool.pick(Nat,U32.is_gt(U32.and(flags,128),0),3n * U32.to_nat(U32.shln(2,U32.to_nat(U32.and(flags,7)))),0n),rest,Nil{}),value => globalPalette(fuel,width,height,value)),_ => Fail{PixelLimit{}})(Unit{}),_ => Fail{Dimensions{}})(Unit{})
    case _: Fail{Truncated{}}

def signature(fuel: Nat, limit: Nat, bytes: List<&2,U32>) -> Parsed(Frame):
  match bytes:
    case 71 <> 73 <> 70 <> 56 <> +version <> 97 <> rest:
      Bool.pick(Unit -> Parsed(Frame),U32.is_eq(version,55) || U32.is_eq(version,57),_ => logical(fuel,limit,rest),_ => Fail{Signature{}})(Unit{})
    case _: Fail{Signature{}}

type Bits is Data: Bits{bytes: List<&2,U32>, word: U32, count: Nat}
type Code is Data: Code{value: U32, bits: Bits}

def refill(word: U32, +count: Nat, bytes: List<&2,U32>) -> Parsed(Bits):
  match bytes:
    case byte <> rest: Done{Bits{rest,U32.or(word,U32.shln(byte,count)),count + 8n}}
    case _: Fail{MissingEnd{}}

def readCode(fuel: Nat, +width: Nat, state: Parsed(Bits)) -> Parsed(Code):
  match fuel state:
    case _ Fail{cause}: Fail{cause}
    case 0n _: Fail{MissingEnd{}}
    case 1n+n Done{Bits{+bytes,+word,+count}}:
      Bool.pick(Unit -> Parsed(Code),Nat.is_ge(count,width),
        _ => Done{Code{U32.and(word,(U32.shln(1,width) - 1 : U32)),Bits{bytes,U32.shrn(word,width),count - width}}},
        _ => readCode(n,width,refill(word,count,bytes)))(Unit{})

# Dictionary entries pack a preceding 12-bit code and one appended byte. Every
# installed prefix precedes its entry, bounding expansion to 4096 symbols.
type Expanded is Type: Expanded{dictionary: Array<U32>, symbols: List<&2,U32>}

def expand(fuel: Nat, +clear: U32, +code: U32, +symbols: List<&2,U32>, fetched: Array<U32> & U32) -> Result<&2,&1,Error,Expanded>:
  match fuel fetched:
    case 0n _: Fail{OutputLength{}}
    case 1n+n Tuple{dictionary,+entry}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Expanded>,U32.is_lt(code,clear),
        dictionary => Done{Expanded{dictionary,code <> symbols}},
        dictionary => expand(n,clear,U32.shrn(entry,8n),U32.and(entry,255) <> symbols,Array.get(U32,dictionary,U32.shrn(entry,8n))))(dictionary)

type Output is Data: Output{remaining: Nat, reversed: List<&2,U32>}

def emit(symbols: List<&2,U32>, remaining: Nat, reversed: List<&2,U32>) -> Parsed(Output):
  match symbols remaining:
    case Nil{} left: Done{Output{left,reversed}}
    case _ 0n: Fail{OutputLength{}}
    case symbol <> rest 1n+n: emit(rest,n,symbol <> reversed)

type Decoder is Type:
  Decoder{dictionary: Array<U32>, bits: Bits, width: Nat, next: U32, previous: Maybe<&2,U32>, output: Output}
type Progress is Type:
  Continue{decoder: Decoder}
  Finished{symbols: List<&2,U32>}

# GIF increases the width after adding the entry that reaches its old limit.
def installed(dictionary: Array<U32>, bits: Bits, +width: Nat, +next: U32, code: U32, output: Parsed(Output)) -> Result<&2,&1,Error,Progress>:
  match output:
    case Fail{cause}: Fail{cause}
    case Done{value}:
      Done{Continue{Decoder{dictionary,bits,Bool.pick(Nat,Nat.is_lt(width,12n) && U32.is_eq(next,U32.shln(1,width)),width + 1n,width),next,Some{code},value}}}

def outputWord(dictionary: Array<U32>, +bits: Bits, +width: Nat, +next: U32, +code: U32, previous: Maybe<&2,U32>, first: U32, +output: Parsed(Output)) -> Result<&2,&1,Error,Progress>:
  match previous:
    case None{}: installed(dictionary,bits,width,next,code,output)
    case Some{old}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Progress>,U32.is_lt(next,4096),
        dictionary => installed(Array.set(U32,dictionary,next,U32.or(U32.shln(old,8n),first)),bits,width,(next + 1 : U32),code,output),
        dictionary => installed(dictionary,bits,width,next,code,output) )(dictionary)

def appendSpecial(special: Bool, first: U32, value: Parsed(Output)) -> Parsed(Output):
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Output{+remaining,+reversed}}:
      Bool.pick(Unit -> Parsed(Output),special,_ => emit(first <> Nil{},remaining,reversed),_ => Done{Output{remaining,reversed}})(Unit{})

def expandedWord(bits: Bits, width: Nat, next: U32, code: U32, previous: Maybe<&2,U32>, special: Bool, emission: Output, expansion: Result<&2,&1,Error,Expanded>) -> Result<&2,&1,Error,Progress>:
  match emission expansion:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Expanded{_,Nil{}}}: Fail{InvalidCode{}}
    case Output{remaining,reversed} Done{Expanded{dictionary,+first <> rest}}:
      outputWord(dictionary,bits,width,next,code,previous,first,appendSpecial(special,first,emit(first <> rest,remaining,reversed)))

def ordinary(clear: U32, +code: U32, bits: Bits, width: Nat, +next: U32, +previous: Maybe<&2,U32>, +output: Output, dictionary: Array<U32>) -> Result<&2,&1,Error,Progress>:
  +special = U32.is_eq(code,next)
  +valid = U32.is_lt(code,next) || (special && Maybe.is_some(&2,U32,previous))
  +index = Bool.pick(U32,special,Maybe.default(&2,U32,previous,0),code)
  Bool.pick(Unit -> Result<&2,&1,Error,Progress>,valid,
    _ => expandedWord(bits,width,next,code,previous,special,output,expand(4096n,clear,index,Nil{},Array.get(U32,dictionary,index))),_ => Fail{InvalidCode{}})(Unit{})

def finish(output: Output) -> Result<&2,&1,Error,Progress>:
  match output:
    case Output{0n,reversed}: Done{Finished{List.reverse(&2,U32,reversed)}}
    case _: Fail{OutputLength{}}

def nextCode(+clear: U32, minimum: Nat, dictionary: Array<U32>, width: Nat, next: U32, previous: Maybe<&2,U32>, +output: Output, result: Parsed(Code)) -> Result<&2,&1,Error,Progress>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Code{+code,+bits}}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Progress>,U32.is_eq(code,clear),
        dictionary => Done{Continue{Decoder{dictionary,bits,minimum + 1n,(clear + 2 : U32),None{},output}}},
        dictionary => Bool.pick(Array<U32> -> Result<&2,&1,Error,Progress>,U32.is_eq(code,(clear + 1 : U32)),_ => finish(output),dictionary => ordinary(clear,code,bits,width,next,previous,output,dictionary) )(dictionary) )(dictionary)

def lzw(fuel: Nat, +clear: U32, +minimum: Nat, state: Result<&2,&1,Error,Progress>) -> Parsed(List<&2,U32>):
  match fuel state:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Finished{symbols}}: Done{symbols}
    case 0n _: Fail{MissingEnd{}}
    case 1n+n Done{Continue{Decoder{dictionary,bits,+width,next,previous,output}}}:
      lzw(n,clear,minimum,nextCode(clear,minimum,dictionary,width,next,previous,output,readCode(3n,width,Done{bits})))

def startLzw(fuel: Nat, +clear: U32, +minimum: Nat, expected: Nat, result: Parsed(Code)) -> Parsed(List<&2,U32>):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Code{code,bits}}:
      Bool.pick(Unit -> Parsed(List<&2,U32>),U32.is_eq(code,clear),
        _ => lzw(fuel,clear,minimum,Done{Continue{Decoder{Array.new(U32,12n,0),bits,minimum + 1n,(clear + 2 : U32),None{},Output{expected,Nil{}}}}}),_ => Fail{InvalidCode{}})(Unit{})

def decompress(+bytes: List<&2,U32>, +minimum: U32, expected: Nat) -> Parsed(List<&2,U32>):
  bind(Nat,List<&2,U32>,length(bytes,0n),count => startLzw(count * 8n + 1n,U32.shln(1,U32.to_nat(minimum)),U32.to_nat(minimum),expected,readCode(3n,U32.to_nat(minimum) + 1n,Done{Bits{bytes,0,0n}})))

type Palette is Data:
  Leaf{pixel: Maybe<&2,U32>}
  Branch{left: Palette, right: Palette}

def paletteEntries(bytes: List<&2,U32>, +transparent: Maybe<&2,U32>, +index: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  match bytes:
    case r <> g <> b <> rest:
      alpha = Bool.pick(U32,U32.is_eq(index,Maybe.default(&2,U32,transparent,256)),0,255)
      pixel = U32.or(U32.shln(r,24n),U32.or(U32.shln(g,16n),U32.or(U32.shln(b,8n),alpha)))
      paletteEntries(rest,transparent,(index + 1 : U32),pixel <> reversed)
    case _: List.reverse(&2,U32,reversed)

def skip(count: Nat, values: List<&2,U32>) -> List<&2,U32>:
  match count values:
    case 0n rest: rest
    case 1n+n _ <> rest: skip(n,rest)
    case _ Nil{}: Nil{}

def paletteTree(depth: Nat, values: List<&2,U32>) -> Palette:
  match depth values:
    case 0n Nil{}: Leaf{None{}}
    case 0n pixel <> _: Leaf{Some{pixel}}
    case 1n+ +n +rest: Branch{paletteTree(n,rest),paletteTree(n,skip(U32.to_nat(U32.shln(1,n)),rest))}

def lookup(table: Palette, +index: U32, +bit: U32) -> Parsed(U32):
  match table:
    case Leaf{None{}}: Fail{PaletteIndex{}}
    case Leaf{Some{pixel}}: Done{pixel}
    case Branch{left,right}:
      Bool.pick(Unit -> Parsed(U32),U32.is_eq(U32.and(index,bit),0),_ => lookup(left,index,U32.shr(bit)),_ => lookup(right,index,U32.shr(bit)))(Unit{})

type Painted is Type: Painted{pixels: Array<U32>, symbols: List<&2,U32>}

def pixelAt(index: U32, pixels: Array<U32>, symbols: List<&2,U32>, value: Parsed(U32)) -> Result<&2,&1,Error,Painted>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{pixel}: Done{Painted{Array.set(U32,pixels,index,pixel),symbols}}

def paintRow(count: Nat, +index: U32, +palette: Palette, state: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Painted>:
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n state: state
    case 1n+n Done{Painted{pixels,symbol <> rest}}: paintRow(n,(index + 1 : U32),palette,pixelAt(index,pixels,rest,lookup(palette,symbol,128)))
    case _ _: Fail{OutputLength{}}

def passRows(count: Nat, +row: U32, +step: U32, +width: U32, +screenWidth: U32, +left: U32, +top: U32, +palette: Palette, state: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Painted>:
  match count:
    case 0n: state
    case 1n+n: passRows(n,(row + step : U32),step,width,screenWidth,left,top,palette,paintRow(U32.to_nat(width),((top + row) * screenWidth + left : U32),palette,state))

def pass(+start: U32, +step: U32, +height: U32, width: U32, screenWidth: U32, left: U32, top: U32, palette: Palette, state: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Painted>:
  passRows((U32.to_nat(height) + U32.to_nat(step) - 1n - U32.to_nat(start)) / U32.to_nat(step),start,step,width,screenWidth,left,top,palette,state)

def passes(interlaced: Bool, +height: U32, +width: U32, +screenWidth: U32, +left: U32, +top: U32, +palette: Palette, state: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Painted>:
  match interlaced:
    case False{}: pass(0,1,height,width,screenWidth,left,top,palette,state)
    case True{}:
      pass(1,2,height,width,screenWidth,left,top,palette,pass(2,4,height,width,screenWidth,left,top,palette,pass(4,8,height,width,screenWidth,left,top,palette,pass(0,8,height,width,screenWidth,left,top,palette,state))))

def raster(width: U32, height: U32, value: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Painted{pixels,Nil{}}}: Done{Image.Raster{width,height,pixels}}
    case _: Fail{OutputLength{}}

def paint(+screenWidth: U32, +screenHeight: U32, left: U32, top: U32, width: U32, height: U32, interlaced: Bool, palette: Palette, result: Parsed(List<&2,U32>)) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{symbols}:
      raster(screenWidth,screenHeight,passes(interlaced,height,width,screenWidth,left,top,palette,Done{Painted{Array.new(U32,Image.depth(31n,(screenWidth * screenHeight : U32),1,0n),0),symbols}}))

def render(result: Parsed(Frame)) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Frame{screenWidth,screenHeight,left,top,+width,+height,interlaced,palette,transparent,minimum,compressed}}:
      paint(screenWidth,screenHeight,left,top,width,height,interlaced,paletteTree(8n,paletteEntries(palette,transparent,0,Nil{})),decompress(compressed,minimum,U32.to_nat(width) * U32.to_nat(height)))

def checked(bytes: List<&2,U32>, pixelLimit: Nat, result: Parsed(Nat)) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{count}: render(signature(count,pixelLimit,bytes))

def decode(+bytes: List<&2,U32>, pixelLimit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  checked(bytes,pixelLimit,length(bytes,0n))
