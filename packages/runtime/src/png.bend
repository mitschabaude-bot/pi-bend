import Base
import ./deflate.bend as Deflate
import ./image.bend as Image
import ./deflate-encode.bend as Encode

# Decode one complete PNG into the shared straight-alpha RGBA8 raster.
# All legal static color/depth combinations, Adam7 and tRNS are supported.
# For APNG, this decodes the default IDAT image, not later animation frames.
# Ancillary metadata is CRC-checked but not interpreted or color-managed.
# Chunk framing and critical/tRNS ordering are checked; this is not a validator
# for the internal syntax or ordering rules of ignored metadata extensions.

type Error is Data:
  Signature{}
  Truncated{}
  InvalidByte{}
  ChunkLength{}
  ChunkType{}
  Crc{kind: U32}
  InvalidHeader{}
  ChunkOrder{}
  Palette{}
  Transparency{}
  CriticalChunk{kind: U32}
  Compressed{cause: Deflate.Error}
  Scanline{}
  Filter{}
  PaletteIndex{}
  PixelLimit{}
  InvalidRaster{}
  OutputLimit{}
  Encoding{cause: Encode.Error}

type Header is Data:
  Header{width: U32, height: U32, depth: U32, color: U32, interlace: U32}

def length(bytes: List<&2,U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: length(rest,1n + count)

def packWord(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.or(U32.shln(a,24n),U32.or(U32.shln(b,16n),U32.or(U32.shln(c,8n),d)))

# CRC-32 reflected polynomial, two four-bit steps per byte.
def crcNibble(value: U32) -> U32:
  match value:
    case 0: 0
    case 1: 498536548
    case 2: 997073096
    case 3: 651767980
    case 4: 1994146192
    case 5: 1802195444
    case 6: 1303535960
    case 7: 1342533948
    case 8: 3988292384
    case 9: 4027552580
    case 10: 3604390888
    case 11: 3412177804
    case 12: 2607071920
    case 13: 2262029012
    case 14: 2685067896
    case _: 3183342108

def crcStep(+value: U32) -> U32:
  U32.xor(U32.shrn(value,4n),crcNibble(U32.and(value,15)))

def crcByte(crc: U32, byte: U32) -> U32: crcStep(crcStep(U32.xor(crc,byte)))

def letter(+byte: U32) -> Bool:
  (U32.is_ge(byte,65) && U32.is_le(byte,90)) || (U32.is_ge(byte,97) && U32.is_le(byte,122))

type Chunk is Data:
  Chunk{kind: U32, bytes: List<&2,U32>, rest: List<&2,U32>}

def chunkCrc(+kind: U32, crc: U32, data: List<&2,U32>, bytes: List<&2,U32>) -> Result<&2,&2,Error,Chunk>:
  match bytes:
    case a <> b <> c <> d <> rest:
      Bool.pick(Result<&2,&2,Error,Chunk>,U32.is_eq(U32.xor(crc,4294967295),packWord(a,b,c,d)),Done{Chunk{kind,List.reverse(&2,U32,data),rest}},Fail{Crc{kind}})
    case _: Fail{Truncated{}}

def chunkData(count: Nat, +kind: U32, crc: U32, data: List<&2,U32>, bytes: List<&2,U32>) -> Result<&2,&2,Error,Chunk>:
  match count bytes:
    case 0n bytes: chunkCrc(kind,crc,data,bytes)
    case _ Nil{}: Fail{Truncated{}}
    case 1n+n +byte <> rest: chunkData(n,kind,crcByte(crc,byte),byte <> data,rest)

def chunkHeader(valid: Bool, count: U32, +a: U32, +b: U32, +c: U32, +d: U32, rest: List<&2,U32>) -> Result<&2,&2,Error,Chunk>:
  match valid:
    case False{}: Fail{ChunkLength{}}
    case True{}:
      Bool.pick(Unit -> Result<&2,&2,Error,Chunk>,letter(a) && letter(b) && letter(c) && letter(d) && U32.is_eq(U32.and(c,32),0),
        _ => chunkData(U32.to_nat(count),packWord(a,b,c,d),crcByte(crcByte(crcByte(crcByte(4294967295,a),b),c),d),Nil{},rest),_ => Fail{ChunkType{}})(Unit{})

def chunk(bytes: List<&2,U32>) -> Result<&2,&2,Error,Chunk>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> rest:
      +count = packWord(a,b,c,d)
      chunkHeader(U32.is_le(count,2147483647),count,e,f,g,h,rest)
    case _: Fail{Truncated{}}

def depthAllowed(color: U32, depth: U32) -> Bool:
  match color depth:
    case 0 1: True{}
    case 0 2: True{}
    case 0 4: True{}
    case 0 8: True{}
    case 0 16: True{}
    case 3 1: True{}
    case 3 2: True{}
    case 3 4: True{}
    case 3 8: True{}
    case 2 8: True{}
    case 2 16: True{}
    case 4 8: True{}
    case 4 16: True{}
    case 6 8: True{}
    case 6 16: True{}
    case _ _: False{}

def headerBounds(valid: Bool, +width: U32, +height: U32, depth: U32, color: U32, interlace: U32, limit: Nat) -> Result<&2,&2,Error,Header>:
  match valid:
    case False{}: Fail{InvalidHeader{}}
    case True{}:
      Bool.pick(Result<&2,&2,Error,Header>,U32.is_le(width,(2147483648 / height : U32)) && Nat.is_le(U32.to_nat((width * height : U32)),limit),Done{Header{width,height,depth,color,interlace}},Fail{PixelLimit{}})

def readHeader(bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,Header>:
  match bytes:
    case a <> b <> c <> d <> e <> f <> g <> h <> +depth <> +color <> compression <> filter <> +interlace <> Nil{}:
      +width = packWord(a,b,c,d)
      +height = packWord(e,f,g,h)
      headerBounds(U32.is_gt(width,0) && U32.is_gt(height,0) && U32.is_le(width,2147483647) && U32.is_le(height,2147483647) && depthAllowed(color,depth) && U32.is_eq(compression,0) && U32.is_eq(filter,0) && U32.is_le(interlace,1),width,height,depth,color,interlace,limit)
    case _: Fail{InvalidHeader{}}

type Parsed is Data:
  Parsed{header: Header, palette: Maybe<&2,List<&2,U32>>, transparency: Maybe<&2,List<&2,U32>>, compressed: List<&2,U32>, phase: U32}

def paletteValid(header: Header, +size: Nat) -> Bool:
  match header:
    case Header{_,_,depth,+color,_}:
      Nat.is_gt(size,0n) && Nat.is_le(size,768n) && Nat.is_eq(size % 3n,0n) && (U32.is_eq(color,2) || U32.is_eq(color,6) || (U32.is_eq(color,3) && Nat.is_le(size / 3n,U32.to_nat(U32.shln(1,U32.to_nat(depth))))))

def paletteChunk(+data: List<&2,U32>, state: Parsed) -> Result<&2,&2,Error,Parsed>:
  match state:
    case Parsed{+header,None{},None{},compressed,0}:
      Bool.pick(Result<&2,&2,Error,Parsed>,paletteValid(header,length(data,0n)),Done{Parsed{header,Some{data},None{},compressed,0}},Fail{Palette{}})
    case _: Fail{ChunkOrder{}}

def transparencyValid(header: Header, palette: Maybe<&2,List<&2,U32>>, data: List<&2,U32>) -> Bool:
  match header palette data:
    case Header{_,_,depth,0,_} _ a <> b <> Nil{}: U32.is_lt((a * 256 + b : U32),U32.shln(1,U32.to_nat(depth)))
    case Header{_,_,depth,2,_} _ a <> b <> c <> d <> e <> f <> Nil{}:
      +limit = U32.shln(1,U32.to_nat(depth))
      U32.is_lt((a * 256 + b : U32),limit) && U32.is_lt((c * 256 + d : U32),limit) && U32.is_lt((e * 256 + f : U32),limit)
    case Header{_,_,_,3,_} Some{colors} data:
      +size = length(data,0n)
      Nat.is_gt(size,0n) && Nat.is_le(size,length(colors,0n) / 3n)
    case _ _ _: False{}

def transparencyChunk(+data: List<&2,U32>, state: Parsed) -> Result<&2,&2,Error,Parsed>:
  match state:
    case Parsed{+header,+palette,None{},compressed,0}:
      Bool.pick(Result<&2,&2,Error,Parsed>,transparencyValid(header,palette,data),Done{Parsed{header,palette,Some{data},compressed,0}},Fail{Transparency{}})
    case _: Fail{ChunkOrder{}}

def palettePresent(header: Header, palette: Maybe<&2,List<&2,U32>>) -> Bool:
  match header palette:
    case Header{_,_,_,3,_} None{}: False{}
    case _ _: True{}

def dataChunk(data: List<&2,U32>, state: Parsed) -> Result<&2,&2,Error,Parsed>:
  match state:
    case Parsed{+header,+palette,transparency,compressed,+phase}:
      Bool.pick(Result<&2,&2,Error,Parsed>,U32.is_le(phase,1) && palettePresent(header,palette),Done{Parsed{header,palette,transparency,List.reverse.go(&2,U32,data,compressed),1}},Fail{ChunkOrder{}})

def ancillary(+kind: U32, state: Parsed) -> Result<&2,&2,Error,Parsed>:
  match state:
    case Parsed{header,palette,transparency,compressed,+phase}:
      Bool.pick(Result<&2,&2,Error,Parsed>,U32.is_gt(U32.and(kind,536870912),0),Done{Parsed{header,palette,transparency,compressed,Bool.pick(U32,U32.is_eq(phase,1),2,phase)}},Fail{CriticalChunk{kind}})

def accepted(kind: U32, data: List<&2,U32>, state: Parsed) -> Result<&2,&2,Error,Parsed>:
  match kind:
    case 1229472850: Fail{ChunkOrder{}}
    case 1347179589: paletteChunk(data,state)
    case 1951551059: transparencyChunk(data,state)
    case 1229209940: dataChunk(data,state)
    case _: ancillary(kind,state)

type Parsing is Data:
  More{parsed: Parsed, bytes: List<&2,U32>}
  Complete{parsed: Parsed}

def endChunk(data: List<&2,U32>, rest: List<&2,U32>, state: Parsed) -> Result<&2,&2,Error,Parsing>:
  match data rest state:
    case Nil{} Nil{} Parsed{header,palette,transparency,compressed,+phase}:
      Bool.pick(Result<&2,&2,Error,Parsing>,U32.is_gt(phase,0),Done{Complete{Parsed{header,palette,transparency,List.reverse(&2,U32,compressed),phase}}},Fail{ChunkOrder{}})
    case _ _ _: Fail{ChunkOrder{}}

def nextChunk(state: Parsed, read: Result<&2,&2,Error,Chunk>) -> Result<&2,&2,Error,Parsing>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Chunk{1229278788,data,rest}}: endChunk(data,rest,state)
    case Done{Chunk{kind,data,rest}}: Result.map(&2,&2,Error,Parsed,Parsing,x => More{x,rest},accepted(kind,data,state))

# Every iteration consumes a complete chunk (at least twelve input bytes).
@unsafe def chunks(state: Result<&2,&2,Error,Parsing>) -> Result<&2,&2,Error,Parsed>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Complete{parsed}}: Done{parsed}
    case Done{More{parsed,bytes}}: chunks(nextChunk(parsed,chunk(bytes)))

def firstChunk(limit: Nat, read: Result<&2,&2,Error,Chunk>) -> Result<&2,&2,Error,Parsed>:
  match read:
    case Fail{error}: Fail{error}
    case Done{Chunk{1229472850,data,rest}}:
      chunks(Result.map(&2,&2,Error,Header,Parsing,h => More{Parsed{h,None{},None{},Nil{},0},rest},readHeader(data,limit)))
    case _: Fail{ChunkOrder{}}

def signature(bytes: List<&2,U32>, limit: Nat) -> Result<&2,&2,Error,Parsed>:
  match bytes:
    case 137 <> 80 <> 78 <> 71 <> 13 <> 10 <> 26 <> 10 <> rest: firstChunk(limit,chunk(rest))
    case _: Fail{Signature{}}

def channels(color: U32) -> U32:
  match color:
    case 2: 3
    case 4: 2
    case 6: 4
    case _: 1

type Pass is Data:
  Pass{x: U32, y: U32, dx: U32, dy: U32}

def passes(interlace: U32) -> List<&2,Pass>:
  match interlace:
    case 0: Pass{0,0,1,1} <> Nil{}
    case _: Pass{0,0,8,8} <> Pass{4,0,8,8} <> Pass{0,4,4,8} <> Pass{2,0,4,4} <> Pass{0,2,2,4} <> Pass{1,0,2,2} <> Pass{0,1,1,2} <> Nil{}

def extent(+size: U32, +start: U32, +stride: U32) -> U32:
  Bool.pick(U32,U32.is_gt(size,start),((size - start + stride - 1) / stride : U32),0)

def rowBytes(width: U32, bits: U32) -> Nat: (U32.to_nat(width) * U32.to_nat(bits) + 7n) / 8n

def passBytes(pass: Pass, +header: Header) -> Nat:
  match pass header:
    case Pass{x,y,dx,dy} Header{width,height,depth,color,_}:
      +w = extent(width,x,dx)
      +h = extent(height,y,dy)
      Bool.pick(Nat,U32.is_eq(w,0) || U32.is_eq(h,0),0n,(rowBytes(w,(depth * channels(color) : U32)) + 1n) * U32.to_nat(h))

def inflatedSize(passes: List<&2,Pass>, +header: Header, accumulator: Nat) -> Nat:
  match passes:
    case Nil{}: accumulator
    case pass <> rest: inflatedSize(rest,header,accumulator + passBytes(pass,header))

def paletteEntries(colors: List<&2,U32>, alpha: List<&2,U32>, +index: U32, table: Array<U32>) -> Array<U32>:
  match colors alpha:
    case r <> g <> b <> rest a <> more: paletteEntries(rest,more,(index + 1 : U32),Array.set(U32,table,index,packWord(r,g,b,a)))
    case r <> g <> b <> rest Nil{}: paletteEntries(rest,Nil{},(index + 1 : U32),Array.set(U32,table,index,packWord(r,g,b,255)))
    case _ _: table

type Transparent is Data:
  Opaque{}
  GrayKey{value: U32}
  RgbKey{r: U32, g: U32, b: U32}

def transparencyKey(color: U32, bytes: List<&2,U32>) -> Transparent:
  match color bytes:
    case 0 a <> b <> Nil{}: GrayKey{(a * 256 + b : U32)}
    case 2 a <> b <> c <> d <> e <> f <> Nil{}: RgbKey{(a * 256 + b : U32),(c * 256 + d : U32),(e * 256 + f : U32)}
    case _ _: Opaque{}

def scale(+value: U32, depth: U32) -> U32:
  match depth:
    case 16: ((value + 128) / 257 : U32)
    case 8: value
    case 4: (value * 17 : U32)
    case 2: (value * 85 : U32)
    case _: (value * 255 : U32)

def grayAlpha(key: Transparent, value: U32) -> U32:
  match key:
    case GrayKey{sample}: Bool.pick(U32,U32.is_eq(sample,value),0,255)
    case _: 255

def rgbAlpha(key: Transparent, r: U32, g: U32, b: U32) -> U32:
  match key:
    case RgbKey{x,y,z}: Bool.pick(U32,U32.is_eq(r,x) && U32.is_eq(g,y) && U32.is_eq(b,z),0,255)
    case _: 255

def pixel(color: U32, +depth: U32, key: Transparent, samples: List<&2,U32>) -> U32:
  match color samples:
    case 0 +gray <> Nil{}:
      +g = scale(gray,depth)
      packWord(g,g,g,grayAlpha(key,gray))
    case 2 +r <> +g <> +b <> Nil{}: packWord(scale(r,depth),scale(g,depth),scale(b,depth),rgbAlpha(key,r,g,b))
    case 4 gray <> a <> Nil{}:
      +g = scale(gray,depth)
      packWord(g,g,g,scale(a,depth))
    case 6 r <> g <> b <> a <> Nil{}: packWord(scale(r,depth),scale(g,depth),scale(b,depth),scale(a,depth))
    case _ _: 0

type Samples is Data:
  Samples{bytes: List<&2,U32>, word: U32, remaining: U32}

type Sample is Data:
  Sample{value: U32, cursor: Samples}

type SampleRead is Data:
  SampleRead{values: List<&2,U32>, cursor: Samples}

def sampleSmall(+depth: U32, state: Samples) -> Result<&2,&2,Error,Sample>:
  match state:
    case Samples{bytes,+word,+remaining}:
      Bool.pick(Unit -> Result<&2,&2,Error,Sample>,U32.is_ge(remaining,depth),
        _ => Done{Sample{U32.and(U32.shrn(word,U32.to_nat((remaining - depth : U32))),(U32.shln(1,U32.to_nat(depth)) - 1 : U32)),Samples{bytes,word,(remaining - depth : U32)}}},_ => Fail{Scanline{}})(Unit{})

def sample(depth: U32, state: Samples) -> Result<&2,&2,Error,Sample>:
  match depth state:
    case 16 Samples{a <> b <> rest,_,_}: Done{Sample{(a * 256 + b : U32),Samples{rest,0,0}}}
    case 8 Samples{byte <> rest,_,_}: Done{Sample{byte,Samples{rest,0,0}}}
    case depth Samples{byte <> rest,_,0}: sampleSmall(depth,Samples{rest,byte,8})
    case depth state: sampleSmall(depth,state)

def sampleMore(reversed: List<&2,U32>, result: Result<&2,&2,Error,Sample>) -> Result<&2,&2,Error,SampleRead>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Sample{value,state}}: Done{SampleRead{value <> reversed,state}}

# Each pixel has at most four samples; the fixed channel count bounds this loop.
def samples(count: Nat, +depth: U32, state: Result<&2,&2,Error,SampleRead>) -> Result<&2,&2,Error,SampleRead>:
  match count state:
    case _ Fail{error}: Fail{error}
    case 0n Done{SampleRead{reversed,cursor}}: Done{SampleRead{List.reverse(&2,U32,reversed),cursor}}
    case 1n+n Done{SampleRead{reversed,cursor}}: samples(n,depth,sampleMore(reversed,sample(depth,cursor)))

# Nonnegative forms of |b-c|, |a-c|, |a+b-2c| avoid signed overflow.
def difference(+a: U32, +b: U32) -> U32: Bool.pick(U32,U32.is_ge(a,b),(a - b : U32),(b - a : U32))

def paeth(+a: U32, +b: U32, +c: U32) -> U32:
  +pa = difference(b,c)
  +pb = difference(a,c)
  +pc = difference((a + b : U32),(c * 2 : U32))
  Bool.pick(U32,U32.is_le(pa,pb) && U32.is_le(pa,pc),a,Bool.pick(U32,U32.is_le(pb,pc),b,c))

def predictor(filter: U32, a: U32, b: U32, c: U32) -> U32:
  match filter:
    case 1: a
    case 2: b
    case 3: ((a + b) / 2 : U32)
    case 4: paeth(a,b,c)
    case _: 0

type Row is Data:
  Row{values: List<&2,U32>, rest: List<&2,U32>}

type Unfilter is Type:
  Unfilter{bytes: List<&2,U32>, above: List<&2,U32>, window: Array<U32>, index: U32, reversed: List<&2,U32>}

# The eight-cell window holds (left | upper-left<<8) at distance bpp.
# Updating one cell per byte handles every legal channel/depth combination.
def unfilterByte(filter: U32, +bpp: U32, byte: U32, +above: U32, rest: List<&2,U32>, previousRow: List<&2,U32>, fetched: Array<U32> & U32, +index: U32, reversed: List<&2,U32>) -> Unfilter:
  match fetched:
    case (window,+pair):
      +value = U32.and((byte + predictor(filter,U32.and(pair,255),above,U32.shrn(pair,8n)) : U32),255)
      Unfilter{rest,previousRow,Array.set(U32,window,index,U32.or(value,U32.shln(above,8n))),Bool.pick(U32,U32.is_eq((index + 1 : U32),bpp),0,(index + 1 : U32)),value <> reversed}

def unfilterAbove(filter: U32, bpp: U32, byte: U32, rest: List<&2,U32>, above: List<&2,U32>, window: Array<U32>, +index: U32, reversed: List<&2,U32>) -> Unfilter:
  match above:
    case Nil{}: unfilterByte(filter,bpp,byte,0,rest,Nil{},Array.get(U32,window,index),index,reversed)
    case value <> more: unfilterByte(filter,bpp,byte,value,rest,more,Array.get(U32,window,index),index,reversed)

def unfilter(count: Nat, +filter: U32, +bpp: U32, state: Unfilter) -> Result<&2,&2,Error,Row>:
  match count state:
    case 0n Unfilter{bytes,_,_,_,reversed}: Done{Row{List.reverse(&2,U32,reversed),bytes}}
    case _ Unfilter{Nil{},_,_,_,_}: Fail{Scanline{}}
    case 1n+n Unfilter{byte <> rest,above,window,index,reversed}: unfilter(n,filter,bpp,unfilterAbove(filter,bpp,byte,rest,above,window,index,reversed))

type Canvas is Type:
  Canvas{palette: Array<U32>, pixels: Array<U32>}

type Render is Data:
  Render{width: U32, depth: U32, color: U32, transparent: Transparent, paletteSize: U32}

type Painted is Type:
  Painted{canvas: Canvas, cursor: Samples}

def palettePixel(index: U32, cursor: Samples, pixels: Array<U32>, fetched: Array<U32> & U32) -> Painted:
  match fetched:
    case (palette,value): Painted{Canvas{palette,Array.set(U32,pixels,index,value)},cursor}

def indexedPixel(valid: Bool, value: U32, index: U32, cursor: Samples, canvas: Canvas) -> Result<&2,&1,Error,Painted>:
  match valid canvas:
    case False{} _: Fail{PaletteIndex{}}
    case True{} Canvas{palette,pixels}: Done{palettePixel(index,cursor,pixels,Array.get(U32,palette,value))}

def paintPixel(render: Render, index: U32, canvas: Canvas, result: Result<&2,&2,Error,SampleRead>) -> Result<&2,&1,Error,Painted>:
  match render canvas result:
    case _ _ Fail{error}: Fail{error}
    case Render{_,_,3,_,size} canvas Done{SampleRead{+value <> Nil{},cursor}}: indexedPixel(U32.is_lt(value,size),value,index,cursor,canvas)
    case Render{_,depth,color,transparent,_} Canvas{palette,pixels} Done{SampleRead{values,cursor}}:
      Done{Painted{Canvas{palette,Array.set(U32,pixels,index,pixel(color,depth,transparent,values))},cursor}}

def pixelSamples(render: Render, cursor: Samples) -> Result<&2,&2,Error,SampleRead>:
  match render:
    case Render{_,depth,color,_,_}: samples(U32.to_nat(channels(color)),depth,Done{SampleRead{Nil{},cursor}})

def paint(count: Nat, +render: Render, +index: U32, +stride: U32, state: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Painted>:
  match count state:
    case _ Fail{error}: Fail{error}
    case 0n state: state
    case 1n+n Done{Painted{canvas,cursor}}: paint(n,render,(index + stride : U32),stride,paintPixel(render,index,canvas,pixelSamples(render,cursor)))

type Rows is Type:
  Rows{canvas: Canvas, bytes: List<&2,U32>, previous: List<&2,U32>}

def paintedRow(row: List<&2,U32>, rest: List<&2,U32>, result: Result<&2,&1,Error,Painted>) -> Result<&2,&1,Error,Rows>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Painted{canvas,_}}: Done{Rows{canvas,rest,row}}

def paintRow(width: U32, render: Render, index: U32, stride: U32, canvas: Canvas, result: Result<&2,&2,Error,Row>) -> Result<&2,&1,Error,Rows>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Row{+row,rest}}: paintedRow(row,rest,paint(U32.to_nat(width),render,index,stride,Done{Painted{canvas,Samples{row,0,0}}}))

def rowFilter(valid: Bool, width: U32, render: Render, index: U32, stride: U32, canvas: Canvas, filter: U32, bpp: U32, rowSize: Nat, rest: List<&2,U32>, previous: List<&2,U32>) -> Result<&2,&1,Error,Rows>:
  match valid:
    case False{}: Fail{Filter{}}
    case True{}: paintRow(width,render,index,stride,canvas,unfilter(rowSize,filter,bpp,Unfilter{rest,previous,Array.new(U32,3n,0),0,Nil{}}))

def renderRow(width: U32, render: Render, index: U32, stride: U32, bpp: U32, rowSize: Nat, state: Rows) -> Result<&2,&1,Error,Rows>:
  match state:
    case Rows{canvas,+filter <> rest,previous}: rowFilter(U32.is_le(filter,4),width,render,index,stride,canvas,filter,bpp,rowSize,rest,previous)
    case _: Fail{Scanline{}}

def rows(count: Nat, +width: U32, +render: Render, +index: U32, +stride: U32, +rowStride: U32, +bpp: U32, +rowSize: Nat, state: Result<&2,&1,Error,Rows>) -> Result<&2,&1,Error,Rows>:
  match count state:
    case _ Fail{error}: Fail{error}
    case 0n state: state
    case 1n+n Done{state}: rows(n,width,render,(index + rowStride : U32),stride,rowStride,bpp,rowSize,renderRow(width,render,index,stride,bpp,rowSize,state))

def passSized(empty: Bool, +width: U32, height: U32, render: Render, index: U32, stride: U32, rowStride: U32, +bits: U32, canvas: Canvas, bytes: List<&2,U32>) -> Result<&2,&1,Error,Rows>:
  match empty:
    case True{}: Done{Rows{canvas,bytes,Nil{}}}
    case False{}: rows(U32.to_nat(height),width,render,index,stride,rowStride,((bits + 7) / 8 : U32),rowBytes(width,bits),Done{Rows{canvas,bytes,Nil{}}})

def renderPass(pass: Pass, header: Header, render: Render, canvas: Canvas, bytes: List<&2,U32>) -> Result<&2,&1,Error,Rows>:
  match pass header:
    case Pass{+x,+y,+dx,+dy} Header{+width,height,depth,color,_}:
      +w = extent(width,x,dx)
      +h = extent(height,y,dy)
      passSized(U32.is_eq(w,0) || U32.is_eq(h,0),w,h,render,(y * width + x : U32),dx,(dy * width : U32),(depth * channels(color) : U32),canvas,bytes)

# Adam7 partitions the image coordinates; each pass resets its previous row.
# No pixel is inferred from neighbouring passes, and no scanline crosses a pass.
def renderPasses(passes: List<&2,Pass>, +header: Header, +render: Render, state: Result<&2,&1,Error,Rows>) -> Result<&2,&1,Error,Rows>:
  match passes state:
    case _ Fail{error}: Fail{error}
    case Nil{} state: state
    case one <> rest Done{Rows{canvas,bytes,_}}: renderPasses(rest,header,render,renderPass(one,header,render,canvas,bytes))

def rendered(width: U32, height: U32, state: Result<&2,&1,Error,Rows>) -> Result<&2,&1,Error,Image.Raster>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Rows{Canvas{_,pixels},Nil{},_}}: Done{Image.Raster{width,height,pixels}}
    case _: Fail{Scanline{}}

def inflated(+header: Header, +palette: List<&2,U32>, +alpha: List<&2,U32>, result: Result<&2,&2,Deflate.Error,List<&2,U32>>) -> Result<&2,&1,Error,Image.Raster>:
  match header result:
    case _ Fail{error}: Fail{Compressed{error}}
    case Header{+width,+height,+depth,+color,interlace} Done{bytes}:
      render = {Render{width,depth,color,transparencyKey(color,alpha),U32.from_nat(length(palette,0n) / 3n)} : Render}
      canvas = {Canvas{paletteEntries(palette,alpha,0,Array.new(U32,8n,0)),Array.new(U32,Image.depth(31n,(width * height : U32),1,0n),0)} : Canvas}
      rendered(width,height,renderPasses(passes(interlace),header,render,Done{Rows{canvas,bytes,Nil{}}}))

def decompress(state: Result<&2,&2,Error,Parsed>) -> Result<&2,&1,Error,Image.Raster>:
  match state:
    case Fail{error}: Fail{error}
    case Done{Parsed{Header{w,h,d,c,+interlace},palette,alpha,compressed,_}}:
      +header = {Header{w,h,d,c,interlace} : Header}
      inflated(header,Maybe.default(&2,List<&2,U32>,palette,Nil{}),Maybe.default(&2,List<&2,U32>,alpha,Nil{}),Deflate.inflateZlib(compressed,inflatedSize(passes(interlace),header,0n)))

def checkedBytes(valid: Bool, bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  match valid:
    case False{}: Fail{InvalidByte{}}
    case True{}: decompress(signature(bytes,limit))

# The pixel limit is checked at IHDR, before any pixel-buffer allocation.
# The decompression budget is the exact sum of all nonempty pass scanlines.
def decode(+bytes: List<&2,U32>, limit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  checkedBytes(Deflate.validBytes(bytes),bytes,limit)

# PNG encoding uses the same RGBA8 representation as Photon's image pipeline.
# Adaptive filtering scores signed-byte residuals for Sub, Up, Average, Paeth;
# ties select the later filter, matching image/png's default adaptive heuristic.
# Compression choices differ from Photon, so lossless files need not have the
# same bytes or size; callers must evaluate their actual encoded-size budget.
type Filters is Data:
  Filters{sub: Nat, up: Nat, average: Nat, paeth: Nat, subs: List<&2,U32>, ups: List<&2,U32>, averages: List<&2,U32>, paeths: List<&2,U32>}

def octet(value: U32, shift: Nat) -> U32: U32.and(U32.shrn(value,shift),255)

def residual(filter: U32, value: U32, left: U32, above: U32, upperLeft: U32) -> U32:
  U32.and((value - predictor(filter,left,above,upperLeft) : U32),255)

def filterPixel(+filter: U32, +value: U32, +left: U32, +above: U32, +upperLeft: U32) -> U32:
  packWord(residual(filter,octet(value,24n),octet(left,24n),octet(above,24n),octet(upperLeft,24n)),residual(filter,octet(value,16n),octet(left,16n),octet(above,16n),octet(upperLeft,16n)),residual(filter,octet(value,8n),octet(left,8n),octet(above,8n),octet(upperLeft,8n)),residual(filter,octet(value,0n),octet(left,0n),octet(above,0n),octet(upperLeft,0n)))

def scoreByte(+value: U32) -> U32: Bool.pick(U32,U32.is_le(value,128),value,(256 - value : U32))

def scorePixel(+value: U32) -> Nat:
  U32.to_nat((scoreByte(octet(value,24n)) + scoreByte(octet(value,16n)) + scoreByte(octet(value,8n)) + scoreByte(octet(value,0n)) : U32))

def addFilters(+sub: U32, +up: U32, +average: U32, +paeth: U32, filters: Filters) -> Filters:
  match filters:
    case Filters{s,u,a,p,ss,us,as,ps}: Filters{s + scorePixel(sub),u + scorePixel(up),a + scorePixel(average),p + scorePixel(paeth),sub <> ss,up <> us,average <> as,paeth <> ps}

type Filtering is Type:
  Filtering{pixels: Array<U32>, index: U32, left: U32, upperLeft: U32, filters: Filters}

def filteredPixel(index: U32, +current: U32, +above: U32, +left: U32, +upperLeft: U32, filters: Filters, pixels: Array<U32>) -> Filtering:
  Filtering{pixels,(index + 1 : U32),current,above,addFilters(filterPixel(1,current,left,above,upperLeft),filterPixel(2,current,left,above,upperLeft),filterPixel(3,current,left,above,upperLeft),filterPixel(4,current,left,above,upperLeft),filters)}

def abovePixel(index: U32, current: U32, left: U32, upperLeft: U32, filters: Filters, fetched: Array<U32> & U32) -> Filtering:
  match fetched:
    case (pixels,above): filteredPixel(index,current,above,left,upperLeft,filters,pixels)

def currentPixel(firstRow: Bool, width: U32, +index: U32, left: U32, upperLeft: U32, filters: Filters, fetched: Array<U32> & U32) -> Filtering:
  match firstRow fetched:
    case True{} Tuple{pixels,current}: filteredPixel(index,current,0,left,upperLeft,filters,pixels)
    case False{} Tuple{pixels,current}: abovePixel(index,current,left,upperLeft,filters,Array.get(U32,pixels,(index - width : U32)))

def filterRow(count: Nat, +firstRow: Bool, +width: U32, state: Filtering) -> Filtering:
  match count state:
    case 0n state: state
    case 1n+n Filtering{pixels,+index,left,upperLeft,filters}: filterRow(n,firstRow,width,currentPixel(firstRow,width,index,left,upperLeft,filters,Array.get(U32,pixels,index)))

type FilterChoice is Data:
  FilterChoice{kind: U32, score: Nat, words: List<&2,U32>}

def prefer(+kind: U32, +score: Nat, +words: List<&2,U32>, previous: FilterChoice) -> FilterChoice:
  match previous:
    case FilterChoice{oldKind,+oldScore,oldWords}: Bool.pick(FilterChoice,Nat.is_le(score,oldScore),FilterChoice{kind,score,words},FilterChoice{oldKind,oldScore,oldWords})

def chooseFilter(filters: Filters) -> FilterChoice:
  match filters:
    case Filters{s,u,a,p,ss,us,as,ps}: prefer(4,p,ps,prefer(3,a,as,prefer(2,u,us,FilterChoice{1,s,ss})))

# All byte builders accumulate in reverse order, including chunk payloads.
def appendWord(+value: U32, reversed: List<&2,U32>) -> List<&2,U32>:
  octet(value,0n) <> octet(value,8n) <> octet(value,16n) <> octet(value,24n) <> reversed

def appendPixels(words: List<&2,U32>, reversed: List<&2,U32>) -> List<&2,U32>:
  match words:
    case Nil{}: reversed
    case value <> rest: appendPixels(rest,appendWord(value,reversed))

def appendFiltered(choice: FilterChoice, reversed: List<&2,U32>) -> List<&2,U32>:
  match choice:
    case FilterChoice{kind,_,words}: appendPixels(List.reverse(&2,U32,words),kind <> reversed)

type Filtered is Type:
  Filtered{pixels: Array<U32>, reversed: List<&2,U32>}

def filteredRow(reversed: List<&2,U32>, state: Filtering) -> Filtered:
  match state:
    case Filtering{pixels,_,_,_,filters}: Filtered{pixels,appendFiltered(chooseFilter(filters),reversed)}

def filterRows(count: Nat, +width: U32, +row: U32, state: Filtered) -> Filtered:
  match count state:
    case 0n state: state
    case 1n+n Filtered{pixels,reversed}:
      filterRows(n,width,(row + 1 : U32),filteredRow(reversed,filterRow(U32.to_nat(width),U32.is_eq(row,0),width,Filtering{pixels,(row * width : U32),0,0,Filters{0n,0n,0n,0n,Nil{},Nil{},Nil{},Nil{}}})))

def crcKind(+kind: U32) -> U32:
  crcByte(crcByte(crcByte(crcByte(4294967295,octet(kind,24n)),octet(kind,16n)),octet(kind,8n)),octet(kind,0n))

type Written is Data:
  Written{rest: List<&2,U32>, reversed: List<&2,U32>, crc: U32}

def writeSpan(count: Nat, state: Written) -> Written:
  match count state:
    case 0n state: state
    case 1n+n Written{+byte <> rest,reversed,crc}: writeSpan(n,Written{rest,byte <> reversed,crcByte(crc,byte)})
    case _ state: state

def endSpan(state: Written) -> Written:
  match state:
    case Written{rest,reversed,crc}: Written{rest,appendWord(U32.xor(crc,4294967295),reversed),0}

def writeChunk(+kind: U32, +count: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Written:
  endSpan(writeSpan(count,Written{bytes,appendWord(kind,appendWord(U32.from_nat(count),reversed)),crcKind(kind)}))

def writeData(count: Nat, +remaining: Nat, state: Written) -> Written:
  match count state:
    case 0n state: state
    case 1n+n Written{rest,reversed,_}:
      +size = Bool.pick(Nat,Nat.is_le(remaining,2147483647n),remaining,2147483647n)
      writeData(n,remaining - size,writeChunk(1229209940,size,rest,reversed))

def endImage(state: Written) -> List<&2,U32>:
  match state:
    case Written{_,reversed,_}: List.reverse(&2,U32,appendWord(2923585666,appendWord(1229278788,appendWord(0,reversed))))

def writeImageData(count: Nat, size: Nat, bytes: List<&2,U32>, state: Written) -> List<&2,U32>:
  match state:
    case Written{_,reversed,_}: endImage(writeData(count,size,Written{bytes,reversed,0}))

def encodeChunks(+width: U32, +height: U32, +bytes: List<&2,U32>, +limit: Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  +size = length(bytes,0n)
  +count = (size + 2147483646n) / 2147483647n
  Bool.pick(Unit -> Result<&2,&2,Error,List<&2,U32>>,Nat.is_le(45n + size + count * 12n,limit),_ =>
    header = {octet(width,24n) <> octet(width,16n) <> octet(width,8n) <> octet(width,0n) <> octet(height,24n) <> octet(height,16n) <> octet(height,8n) <> octet(height,0n) <> 8 <> 6 <> 0 <> 0 <> 0 <> Nil{} : List<&2,U32>}
    Done{writeImageData(count,size,bytes,writeChunk(1229472850,13n,header,10 <> 26 <> 10 <> 13 <> 71 <> 78 <> 80 <> 137 <> Nil{}))},_ => Fail{OutputLimit{}})(Unit{})

def compressedImage(width: U32, height: U32, limit: Nat, result: Result<&2,&2,Encode.Error,List<&2,U32>>) -> Result<&2,&2,Error,List<&2,U32>>:
  match result:
    case Fail{Encode.OutputLimit{}}: Fail{OutputLimit{}}
    case Fail{error}: Fail{Encoding{error}}
    case Done{bytes}: encodeChunks(width,height,bytes,limit)

def encodeFiltered(+width: U32, +height: U32, +limit: Nat, filtered: Filtered) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match filtered:
    case Filtered{pixels,reversed}:
      (Image.Raster{width,height,pixels},compressedImage(width,height,limit,Encode.compressZlib(List.reverse(&2,U32,reversed),limit - 57n)))

def encodeCapacity(valid: Bool, +width: U32, +height: U32, +limit: Nat, sized: Array<U32> & U32) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match valid sized:
    case False{} Tuple{pixels,_}: (Image.Raster{width,height,pixels},Fail{InvalidRaster{}})
    case True{} Tuple{pixels,+capacity}:
      Bool.pick(Array<U32> -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>,U32.is_ge(capacity,(width * height : U32)),
        buffer => encodeFiltered(width,height,limit,filterRows(U32.to_nat(height),width,0,Filtered{buffer,Nil{}})),
        buffer => (Image.Raster{width,height,buffer},Fail{InvalidRaster{}}))(pixels)

def encodeBudget(enough: Bool, image: Image.Raster, limit: Nat) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  match enough image:
    case False{} image: (image,Fail{OutputLimit{}})
    case True{} Image.Raster{+width,+height,pixels}:
      encodeCapacity(Image.validDimensions(width,height) && U32.is_le(width,2147483647) && U32.is_le(height,2147483647),width,height,limit,Array.size(U32,pixels))

# Encoding preserves the owned raster so PNG/JPEG trials can share its buffer.
# The byte limit includes the signature, chunk framing and checksums.
def encode(image: Image.Raster, +limit: Nat) -> Image.Raster & Result<&2,&2,Error,List<&2,U32>>:
  encodeBudget(Nat.is_ge(limit,57n),image,limit)
