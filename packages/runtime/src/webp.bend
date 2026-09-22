import Base
import ./image.bend as Image
import ./webp-lossless.bend as Lossless
import ./vp8.bend as VP8

# The container owns RIFF extents, alpha reconstruction and first-frame canvas
# composition. Entropy decoders receive exactly their bounded chunk payload.
type Error is Data:
  InvalidByte{}
  Signature{}
  Truncated{}
  Chunk{}
  Header{}
  Dimensions{}
  PixelLimit{}
  Alpha{}
  LosslessError{cause: Lossless.Error}
  LossyError{cause: VP8.Error}

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>
def bind(-A: Data, -B: Data, value: Parsed(A), next: A -> Parsed(B)) -> Parsed(B):
  match value:
    case Fail{cause}: Fail{cause}
    case Done{value}: next(value)

def count(bytes: List<&2,U32>, size: Nat) -> Parsed(Nat):
  match bytes:
    case Nil{}: Done{size}
    case byte <> +rest: Bool.pick(Unit -> Parsed(Nat),U32.is_le(byte,255),_ => count(rest,1n + size),_ => Fail{InvalidByte{}})(Unit{})

def skip(n: Nat, bytes: List<&2,U32>) -> List<&2,U32>:
  match n bytes:
    case 0n rest: rest
    case 1n+n _ <> rest: skip(n,rest)
    case _ _: Nil{}

def word(n: Nat, bytes: List<&2,U32>, +scale: U32, value: U32) -> U32:
  match n bytes:
    case 0n _: value
    case 1n+n byte <> rest: word(n,rest,U32.shln(scale,8n),(value + byte * scale : U32))
    case _ _: value

def at(offset: Nat, n: Nat, bytes: List<&2,U32>) -> U32: word(n,skip(offset,bytes),1,0)

def prefix(n: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> List<&2,U32>:
  match n bytes:
    case 0n _: List.reverse(&2,U32,reversed)
    case 1n+n byte <> rest: prefix(n,rest,byte <> reversed)
    case _ _: List.reverse(&2,U32,reversed)

type RiffChunk is Data: RiffChunk{kind: U32, bytes: List<&2,U32>, size: Nat}

# Chunk parsing is tail-recursive; each input byte is traversed a bounded number
# of times. Padding belongs to the outer chunk, never the codec payload.
def chunks(fuel: Nat, +remaining: Nat, +bytes: List<&2,U32>, reversed: List<&2,RiffChunk>) -> Parsed(List<&2,RiffChunk>):
  match fuel remaining:
    case _ 0n: Done{List.reverse(&2,RiffChunk,reversed)}
    case 0n _: Fail{Truncated{}}
    case 1n+n remaining:
      +size = U32.to_nat(at(4n,4n,bytes))
      +extent = 8n + size + size % 2n
      Bool.pick(List<&2,RiffChunk> -> Parsed(List<&2,RiffChunk>),Nat.is_ge(remaining,8n) && Nat.is_le(extent,remaining),
        reversed => chunks(n,remaining - extent,skip(extent,bytes),RiffChunk{at(0n,4n,bytes),prefix(size,skip(8n,bytes),Nil{}),size} <> reversed),
        _ => Fail{Truncated{}})(reversed)

type Canvas is Data: Canvas{width: U32, height: U32, alpha: Bool, animation: Bool}
type Frame is Data:
  Frame{width: U32, height: U32, x: U32, y: U32, blend: Bool, kind: U32, bytes: List<&2,U32>, alpha: Maybe<&2,List<&2,U32>>}
type Selection is Data: Selection{canvas: Canvas, background: U32, frame: Frame}

def dimensions(+width: U32, +height: U32, limit: Nat) -> Parsed(Unit):
  Bool.pick(Parsed(Unit),Image.validDimensions(width,height),Bool.pick(Parsed(Unit),Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit),Done{Unit{}},Fail{PixelLimit{}}),Fail{Dimensions{}})

def extendedHeader(+bytes: List<&2,U32>, size: Nat, limit: Nat) -> Parsed(Canvas):
  +flags = at(0n,1n,bytes)
  +width = (at(4n,3n,bytes) + 1 : U32)
  +height = (at(7n,3n,bytes) + 1 : U32)
  Bool.pick(Unit -> Parsed(Canvas),Nat.is_eq(size,10n) && U32.is_eq(U32.and(flags,193),0) && U32.is_eq(at(1n,3n,bytes),0),
    _ => bind(Unit,Canvas,dimensions(width,height,limit),_ => Done{Canvas{width,height,U32.is_gt(U32.and(flags,16),0),U32.is_gt(U32.and(flags,2),0)}}),_ => Fail{Header{}})(Unit{})

# FourCC values are little-endian words: VP8 / VP8L / VP8X / ALPH.
def alphaImage(rest: List<&2,RiffChunk>, alpha: List<&2,U32>, width: U32, height: U32, x: U32, y: U32, blend: Bool) -> Parsed(Frame):
  match rest:
    case RiffChunk{kind,bytes,_} <> _:
      Bool.pick(Parsed(Frame),U32.is_eq(kind,540561494),Done{Frame{width,height,x,y,blend,540561494,bytes,Some{alpha}}},Fail{Chunk{}})
    case _: Fail{Truncated{}}

def imageChunks(parts: List<&2,RiffChunk>, +width: U32, +height: U32, +x: U32, +y: U32, +blending: Bool) -> Parsed(Frame):
  match parts:
    case RiffChunk{+kind,+bytes,_} <> rest:
      Bool.pick(Unit -> Parsed(Frame),U32.is_eq(kind,1213221953),_ => alphaImage(rest,bytes,width,height,x,y,blending),
        _ => Bool.pick(Parsed(Frame),U32.is_eq(kind,540561494) || U32.is_eq(kind,1278758998),Done{Frame{width,height,x,y,blending,kind,bytes,None{}}},Fail{Chunk{}}))(Unit{})
    case _: Fail{Truncated{}}

def animatedFrame(canvas: Canvas, +bytes: List<&2,U32>, +size: Nat) -> Parsed(Frame):
  match canvas:
    case Canvas{cw,ch,_,_}:
      +x = (at(0n,3n,bytes) * 2 : U32)
      +y = (at(3n,3n,bytes) * 2 : U32)
      +width = (at(6n,3n,bytes) + 1 : U32)
      +height = (at(9n,3n,bytes) + 1 : U32)
      +flags = at(15n,1n,bytes)
      Bool.pick(Unit -> Parsed(Frame),Nat.is_ge(size,16n) && U32.is_eq(U32.and(flags,252),0) && Nat.is_le(U32.to_nat(x) + U32.to_nat(width),U32.to_nat(cw)) && Nat.is_le(U32.to_nat(y) + U32.to_nat(height),U32.to_nat(ch)),
        _ => bind(List<&2,RiffChunk>,Frame,chunks(size,size - 16n,skip(16n,bytes),Nil{}),parts => imageChunks(parts,width,height,x,y,U32.is_eq(U32.and(flags,2),0))),_ => Fail{Header{}})(Unit{})

def staticSelection(canvas: Canvas, static: Maybe<&2,Frame>) -> Parsed(Selection):
  match canvas static:
    case Canvas{width,height,alpha,animation} Some{frame}:
      Bool.pick(Parsed(Selection),animation,Fail{Header{}},Done{Selection{Canvas{width,height,alpha,False{}},0,frame}})
    case _ None{}: Fail{Header{}}

def animatedSelection(canvas: Canvas, background: U32, frame: Frame) -> Parsed(Selection):
  match canvas:
    case Canvas{width,height,alpha,animation}:
      Bool.pick(Parsed(Selection),animation,Done{Selection{Canvas{width,height,alpha,True{}},background,frame}},Fail{Header{}})

def choose(canvas: Canvas, background: Maybe<&2,U32>, frame: Maybe<&2,Frame>, static: Maybe<&2,Frame>) -> Parsed(Selection):
  match background frame:
    case Some{background} Some{frame}: animatedSelection(canvas,background,frame)
    case _ _: staticSelection(canvas,static)

# Parse metadata once, retain only the first frame. Later animation payloads are
# bounded RIFF data; the default still-image API never executes their codecs.
def extended(parts: List<&2,RiffChunk>, +canvas: Canvas, +background: Maybe<&2,U32>, +frame: Maybe<&2,Frame>, +static: Maybe<&2,Frame>, +pending: Maybe<&2,List<&2,U32>>) -> Parsed(Selection):
  match parts:
    case Nil{}: Bool.pick(Parsed(Selection),Maybe.is_none(&2,List<&2,U32>,pending),choose(canvas,background,frame,static),Fail{Alpha{}})
    case RiffChunk{+kind,+bytes,+size} <> +rest:
      Bool.pick(Unit -> Parsed(Selection),Maybe.is_some(&2,List<&2,U32>,pending) && Bool.not(U32.is_eq(kind,540561494)),_ => Fail{Alpha{}},
        _ => Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,1296649793),
          _ => Bool.pick(Unit -> Parsed(Selection),Nat.is_eq(size,6n) && Maybe.is_none(&2,U32,background),
            _ => extended(rest,canvas,Some{U32.or(U32.shln(at(2n,1n,bytes),24n),U32.or(U32.shln(at(1n,1n,bytes),16n),U32.or(U32.shln(at(0n,1n,bytes),8n),at(3n,1n,bytes))))},frame,static,None{}),_ => Fail{Header{}})(Unit{}),
          _ => Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,1179471425),
            _ => bind(Frame,Selection,animatedFrame(canvas,bytes,size),value => extended(rest,canvas,background,Maybe.or(&2,Frame,frame,Some{value}),static,None{})),
            _ => Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,1213221953),_ => extended(rest,canvas,background,frame,static,Some{bytes}),
              _ => Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,540561494) || U32.is_eq(kind,1278758998),
                _ => extended(rest,canvas,background,frame,Maybe.or(&2,Frame,static,Some{Frame{0,0,0,0,False{},kind,bytes,pending}}),None{}),
                _ => Bool.pick(Unit -> Parsed(Selection),Bool.not(U32.is_eq(kind,1480085590) || U32.is_eq(kind,1179011410) || U32.is_eq(kind,1346520407)),_ => extended(rest,canvas,background,frame,static,None{}),_ => Fail{Chunk{}})(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def rawAlpha(bytes: List<&2,U32>, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: pixels
    case value <> rest: rawAlpha(rest,(index + 1 : U32),Array.set(U32,pixels,index,U32.shln(value,8n)))

def rawAlphaResult(+width: U32, +height: U32, bytes: List<&2,U32>, size: Parsed(Nat)) -> Result<&2,&1,Error,Array<U32>>:
  match size:
    case Fail{cause}: Fail{cause}
    case Done{size}:
      Bool.pick(Unit -> Result<&2,&1,Error,Array<U32>>,Nat.is_eq(size,U32.to_nat(width) * U32.to_nat(height)),
        _ => Done{rawAlpha(bytes,0,Array.new(U32,Image.depth(31n,(width * height : U32),1,0n),0))},_ => Fail{Alpha{}})(Unit{})

def compressedAlpha(value: Result<&2,&1,Lossless.Error,Array<U32>>) -> Result<&2,&1,Error,Array<U32>>:
  match value:
    case Fail{cause}: Fail{LosslessError{cause}}
    case Done{pixels}: Done{pixels}

def alphaPixels(+width: U32, +height: U32, bytes: List<&2,U32>, +limit: Nat) -> Result<&2,&1,Error,Array<U32>>:
  match bytes:
    case +header <> +rest:
      Bool.pick(Unit -> Result<&2,&1,Error,Array<U32>>,U32.is_le(U32.shrn(header,4n),1) && U32.is_le(U32.and(header,3),1),
        _ => Bool.pick(Unit -> Result<&2,&1,Error,Array<U32>>,U32.is_eq(U32.and(header,3),0),
          _ => rawAlphaResult(width,height,rest,count(rest,0n)),
          _ => compressedAlpha(Lossless.decodeImplicit(width,height,rest,limit)))(Unit{}),_ => Fail{Alpha{}})(Unit{})
    case _: Fail{Truncated{}}

# A gathered neighborhood keeps owned arrays explicit without sharing mutable
# references. All four indexes are clamped at the image borders before lookup.
def gather(indices: List<&2,U32>, value: Array<U32> & U32, reversed: List<&2,U32>) -> Array<U32> & List<&2,U32>:
  match indices value:
    case Nil{} Tuple{pixels,pixel}: (pixels,List.reverse(&2,U32,pixel <> reversed))
    case index <> rest Tuple{pixels,pixel}: gather(rest,Array.get(U32,pixels,index),pixel <> reversed)

def prediction(+method: U32, +index: U32, +width: U32, +left: U32, +top: U32, +topLeft: U32) -> U32:
  +border = Bool.pick(U32,U32.is_eq(index,0),0,Bool.pick(U32,U32.is_lt(index,width),left,top))
  +sum = (left + top : U32)
  +gradient = Bool.pick(U32,U32.is_lt(sum,topLeft),0,U32.min(255,(sum - topLeft : U32)))
  Bool.pick(U32,U32.is_eq(method,0),0,
    Bool.pick(U32,U32.is_eq(method,1),Bool.pick(U32,U32.is_eq((index % width : U32),0),border,left),
      Bool.pick(U32,U32.is_eq(method,2),Bool.pick(U32,U32.is_lt(index,width),border,top),Bool.pick(U32,U32.is_lt(index,width) || U32.is_eq((index % width : U32),0),border,gradient))))

def filterPixel(+method: U32, +index: U32, +width: U32, value: Array<U32> & List<&2,U32>) -> Array<U32>:
  match value:
    case Tuple{pixels,sample <> left <> top <> topLeft <> Nil{}}:
      +alpha = U32.and((U32.and(U32.shrn(sample,8n),255) + prediction(method,index,width,U32.and(left,255),U32.and(top,255),U32.and(topLeft,255)) : U32),255)
      Array.set(U32,pixels,index,alpha)
    case Tuple{pixels,_}: pixels

def unfilter(count: Nat, +method: U32, +width: U32, +index: U32, pixels: Array<U32>) -> Array<U32>:
  match count:
    case 0n: pixels
    case 1n+n:
      +left = Bool.pick(U32,U32.is_eq(index,0),0,(index - 1 : U32))
      +top = Bool.pick(U32,U32.is_lt(index,width),0,(index - width : U32))
      +topLeft = Bool.pick(U32,U32.is_le(index,width),0,(index - width - 1 : U32))
      unfilter(n,method,width,(index + 1 : U32),filterPixel(method,index,width,gather(left <> top <> topLeft <> Nil{},Array.get(U32,pixels,index),Nil{})))

def alphaSample(index: U32, image: Array<U32> & U32, alpha: Array<U32> & U32) -> Array<U32> & Array<U32>:
  match image alpha:
    case Tuple{image,pixel} Tuple{alpha,value}: (Array.set(U32,image,index,U32.or(U32.and(pixel,4294967040),value)),alpha)

def overlay(count: Nat, +index: U32, value: Array<U32> & Array<U32>) -> Array<U32>:
  match count value:
    case 0n Tuple{image,_}: image
    case 1n+n Tuple{image,alpha}: overlay(n,(index + 1 : U32),alphaSample(index,Array.get(U32,image,index),Array.get(U32,alpha,index)))

def alphaResult(+width: U32, +height: U32, method: U32, image: Array<U32>, result: Result<&2,&1,Error,Array<U32>>) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{alpha}:
      +count = U32.to_nat(width) * U32.to_nat(height)
      Done{Image.Raster{width,height,overlay(count,0,(image,unfilter(count,method,width,0,alpha)))}}

def withAlpha(alpha: Maybe<&2,List<&2,U32>>, limit: Nat, image: Image.Raster) -> Result<&2,&1,Error,Image.Raster>:
  match alpha image:
    case None{} image: Done{image}
    case Some{+bytes} Image.Raster{+width,+height,pixels}:
      alphaResult(width,height,U32.and(U32.shrn(at(0n,1n,bytes),2n),3),pixels,alphaPixels(width,height,bytes,limit))

# Keep the reference expression order: IEEE754 rounding followed by truncation
# can differ by one from algebraically simplified integer alpha blending.
def blendChannel(source: U32, destination: U32, +sourceAlpha: F64, +destinationAlpha: F64, +remaining: F64, alpha: F64) -> U32:
  F64.to_u32(F64.div(F64.add(F64.mul(U32.to_f64(source),sourceAlpha),F64.mul(F64.mul(U32.to_f64(destination),destinationAlpha),remaining)),alpha))

def blend(+source: U32, +destination: U32) -> U32:
  +sa = U32.to_f64(U32.and(source,255))
  +da = U32.to_f64(U32.and(destination,255))
  +remaining = F64.sub(U32.to_f64(1),F64.div(sa,U32.to_f64(255)))
  +alpha = F64.add(sa,F64.mul(da,remaining))
  +a = F64.to_u32(alpha)
  Bool.pick(Unit -> U32,U32.is_eq(a,0),_ => 0,_ => U32.or(a,U32.or(U32.shln(blendChannel(U32.shrn(source,24n),U32.shrn(destination,24n),sa,da,remaining,alpha),24n),U32.or(U32.shln(blendChannel(U32.and(U32.shrn(source,16n),255),U32.and(U32.shrn(destination,16n),255),sa,da,remaining,alpha),16n),U32.shln(blendChannel(U32.and(U32.shrn(source,8n),255),U32.and(U32.shrn(destination,8n),255),sa,da,remaining,alpha),8n)))))(Unit{})

def drawPixel(+target: U32, blending: Bool, source: Array<U32> & U32, destination: Array<U32> & U32) -> Array<U32> & Array<U32>:
  match source destination:
    case Tuple{source,+pixel} Tuple{destination,background}:
      (source,Array.set(U32,destination,target,Bool.pick(U32,blending,blend(pixel,background),pixel)))

def draw(count: Nat, +index: U32, +width: U32, +canvasWidth: U32, +x: U32, +y: U32, +blending: Bool, value: Array<U32> & Array<U32>) -> Array<U32>:
  match count value:
    case 0n Tuple{_,destination}: destination
    case 1n+n Tuple{source,destination}:
      +target = ((y + index / width) * canvasWidth + x + index % width : U32)
      draw(n,(index + 1 : U32),width,canvasWidth,x,y,blending,drawPixel(target,blending,Array.get(U32,source,index),Array.get(U32,destination,target)))

def compose(canvas: Canvas, background: U32, frame: Frame, image: Image.Raster) -> Result<&2,&1,Error,Image.Raster>:
  match canvas frame image:
    case Canvas{+cw,+ch,+alpha,animation} Frame{+fw,+fh,x,y,blending,_,_,_} Image.Raster{+width,+height,pixels}:
      +expectedWidth = Bool.pick(U32,U32.is_eq(fw,0),Bool.pick(U32,U32.is_eq(cw,0),width,cw),fw)
      +expectedHeight = Bool.pick(U32,U32.is_eq(fh,0),Bool.pick(U32,U32.is_eq(ch,0),height,ch),fh)
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Image.Raster>,U32.is_eq(width,expectedWidth) && U32.is_eq(height,expectedHeight),
        pixels => Bool.pick(Array<U32> -> Result<&2,&1,Error,Image.Raster>,animation && Bool.not(U32.is_eq(cw,width) && U32.is_eq(ch,height)),
          pixels => Done{Image.Raster{cw,ch,draw(U32.to_nat(width) * U32.to_nat(height),0,width,cw,x,y,blending,(pixels,Array.new(U32,Image.depth(31n,(cw * ch : U32),1,0n),Bool.pick(U32,alpha,0,background))))}},
          pixels => Done{Image.Raster{width,height,pixels}})(pixels),_ => Fail{Dimensions{}})(pixels)

def losslessResult(value: Result<&2,&1,Lossless.Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{LosslessError{cause}}
    case Done{image}: Done{image}

def lossyResult(value: Result<&2,&1,VP8.Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{LossyError{cause}}
    case Done{image}: Done{image}

def finish(canvas: Canvas, background: U32, frame: Frame, value: Result<&2,&1,Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{image}: compose(canvas,background,frame,image)

def decoded(canvas: Canvas, background: U32, frame: Frame, alpha: Maybe<&2,List<&2,U32>>, limit: Nat, value: Result<&2,&1,Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{image}: finish(canvas,background,frame,withAlpha(alpha,limit,image))

def selected(+limit: Nat, value: Parsed(Selection)) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{Selection{canvas,background,Frame{+width,+height,+x,+y,+blending,+kind,bytes,+alpha}}}:
      +frame = {Frame{width,height,x,y,blending,kind,Nil{},alpha} : Frame}
      decoded(canvas,background,frame,alpha,limit,Bool.pick(List<&2,U32> -> Result<&2,&1,Error,Image.Raster>,U32.is_eq(kind,1278758998),bytes => losslessResult(Lossless.decode(bytes,limit)),bytes => lossyResult(VP8.decode(bytes,limit)))(bytes))

def extendedChunks(parts: List<&2,RiffChunk>, header: Parsed(Canvas)) -> Parsed(Selection):
  match header:
    case Fail{cause}: Fail{cause}
    case Done{canvas}: extended(parts,canvas,None{},None{},None{},None{})

def select(parts: Parsed(List<&2,RiffChunk>), +limit: Nat) -> Parsed(Selection):
  match parts:
    case Fail{cause}: Fail{cause}
    case Done{RiffChunk{+kind,+bytes,+size} <> +rest}:
      Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,1480085590),_ => extendedChunks(rest,extendedHeader(bytes,size,limit)),
        _ => Bool.pick(Unit -> Parsed(Selection),U32.is_eq(kind,540561494) || U32.is_eq(kind,1278758998),
          _ => Done{Selection{Canvas{0,0,False{},False{}},0,Frame{0,0,0,0,False{},kind,bytes,None{}}}},_ => Fail{Chunk{}})(Unit{}))(Unit{})
    case Done{Nil{}}: Fail{Truncated{}}

def riff(+bytes: List<&2,U32>, +limit: Nat, total: Parsed(Nat)) -> Result<&2,&1,Error,Image.Raster>:
  match total:
    case Fail{cause}: Fail{cause}
    case Done{+total}:
      Bool.pick(Unit -> Result<&2,&1,Error,Image.Raster>,Nat.is_ge(total,12n) && U32.is_eq(at(0n,4n,bytes),1179011410) && U32.is_eq(at(8n,4n,bytes),1346520407),
        _ => Bool.pick(Unit -> Result<&2,&1,Error,Image.Raster>,Nat.is_eq(U32.to_nat(at(4n,4n,bytes)) + 8n,total),
          _ => selected(limit,select(chunks(total,total - 12n,skip(12n,bytes),Nil{}),limit)),_ => Fail{Truncated{}})(Unit{}),_ => Fail{Signature{}})(Unit{})

def decode(+bytes: List<&2,U32>, pixelLimit: Nat) -> Result<&2,&1,Error,Image.Raster>: riff(bytes,pixelLimit,count(bytes,0n))
