import Base
import ./image.bend as Image

# Windows/OS2 BMP into straight-alpha RGBA8. The explicit pixel budget applies
# before palette construction or pixel allocation; offsets use unbounded Nat.
type Error is Data:
  Signature{}
  InvalidByte{}
  Truncated{}
  Header{}
  Unsupported{}
  Dimensions{}
  PixelLimit{}
  PaletteIndex{}
  Masks{}
  RunLength{}

def Parsed(-A: Data) -> Data: Result<&2,&2,Error,A>

def bind(-A: Data, -B: Data, result: Parsed(A), next: A -> Parsed(B)) -> Parsed(B):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{value}: next(value)

def size(bytes: List<&2,U32>, count: Nat) -> Parsed(Nat):
  match bytes:
    case Nil{}: Done{count}
    case byte <> +rest:
      Bool.pick(Unit -> Parsed(Nat),U32.is_le(byte,255),_ => size(rest,1n + count),_ => Fail{InvalidByte{}})(Unit{})

def skip(count: Nat, bytes: List<&2,U32>) -> List<&2,U32>:
  match count bytes:
    case 0n rest: rest
    case 1n+n _ <> rest: skip(n,rest)
    case _ Nil{}: Nil{}

# Header reads occur only after checking the complete fixed-size header.
def word(count: Nat, bytes: List<&2,U32>, +scale: U32, value: U32) -> U32:
  match count bytes:
    case 0n _: value
    case 1n+n byte <> rest: word(n,rest,U32.shln(scale,8n),(value + byte * scale : U32))
    case _ _: value

def at(offset: Nat, count: Nat, bytes: List<&2,U32>) -> U32: word(count,skip(offset,bytes),1,0)

def pack(r: U32, g: U32, b: U32, a: U32) -> U32:
  U32.or(U32.shln(r,24n),U32.or(U32.shln(g,16n),U32.or(U32.shln(b,8n),a)))

type Field is Data: Field{shift: Nat, bits: Nat}
type Channels is Data: Channels{red: Field, green: Field, blue: Field, alpha: Field}

def ones(fuel: Nat, +mask: U32, +shift: Nat, +bits: Nat) -> Parsed(Field):
  match fuel:
    case 0n: Fail{Masks{}}
    case 1n+n:
      Bool.pick(Unit -> Parsed(Field),U32.is_eq(mask,0),
        _ => Done{Field{shift + Bool.pick(Nat,Nat.is_gt(bits,8n),bits - 8n,0n),Nat.min(bits,8n)}},
        _ => Bool.pick(Unit -> Parsed(Field),U32.is_eq(U32.and(mask,1),1),_ => ones(n,U32.shr(mask),shift,1n + bits),_ => Fail{Masks{}})(Unit{}))(Unit{})

def zeros(fuel: Nat, +mask: U32, +shift: Nat) -> Parsed(Field):
  match fuel:
    case 0n: Fail{Masks{}}
    case 1n+n:
      Bool.pick(Unit -> Parsed(Field),U32.is_eq(U32.and(mask,1),0),_ => zeros(n,U32.shr(mask),1n + shift),_ => ones(33n,mask,shift,0n))(Unit{})

def makeField(+mask: U32) -> Parsed(Field):
  Bool.pick(Unit -> Parsed(Field),U32.is_eq(mask,0),_ => Done{Field{0n,0n}},_ => zeros(32n,mask,0n))(Unit{})

def channels(+r: U32, +g: U32, +b: U32, +a: U32, depth: U32) -> Parsed(Channels):
  Bool.pick(Unit -> Parsed(Channels),U32.is_gt(r,0) && U32.is_gt(g,0) && U32.is_gt(b,0) && U32.is_eq(U32.or(U32.and(r,g),U32.or(U32.and(r,b),U32.or(U32.and(g,b),U32.and(a,U32.or(r,U32.or(g,b)))))),0) && (U32.is_eq(depth,32) || U32.is_le(U32.or(r,U32.or(g,U32.or(b,a))),65535)),
    _ => bind(Field,Channels,makeField(r),red => bind(Field,Channels,makeField(g),green => bind(Field,Channels,makeField(b),blue => bind(Field,Channels,makeField(a),alpha => Done{Channels{red,green,blue,alpha}})))),
    _ => Fail{Masks{}})(Unit{})

def channel(value: U32, field: Field) -> U32:
  match field:
    case Field{_,0n}: 255
    case Field{shift,+bits}:
      +maximum = (U32.shln(1,bits) - 1 : U32)
      +sample = U32.and(U32.shrn(value,shift),maximum)
      Bool.pick(U32,Nat.is_eq(bits,7n),U32.or(U32.shl(sample),U32.shrn(sample,6n)),((sample * 255 + maximum / 2) / maximum : U32))

def color(+value: U32, masks: Channels) -> U32:
  match masks:
    case Channels{r,g,b,a}: pack(channel(value,r),channel(value,g),channel(value,b),channel(value,a))

type HeaderInfo is Data:
  HeaderInfo{width: U32, height: U32, topDown: Bool, depth: U32, compression: U32, headerSize: Nat, offset: Nat, colors: Nat, masks: Channels}

def supported(+core: Bool, +depth: U32, +compression: U32, topDown: Bool) -> Bool:
  Bool.pick(Bool,core,(U32.is_eq(depth,1) || U32.is_eq(depth,4) || U32.is_eq(depth,8) || U32.is_eq(depth,24)) && U32.is_eq(compression,0),
    Bool.pick(Bool,U32.is_eq(compression,0),U32.is_eq(depth,1) || U32.is_eq(depth,2) || U32.is_eq(depth,4) || U32.is_eq(depth,8) || U32.is_eq(depth,16) || U32.is_eq(depth,24) || U32.is_eq(depth,32),
      Bool.pick(Bool,U32.is_eq(compression,3),U32.is_eq(depth,16) || U32.is_eq(depth,32),Bool.not(topDown) && ((U32.is_eq(compression,1) && U32.is_eq(depth,8)) || (U32.is_eq(compression,2) && U32.is_eq(depth,4))))))

def headerMasks(+depth: U32, compression: U32, +dib: Nat, +bytes: List<&2,U32>) -> Parsed(Channels):
  Bool.pick(Unit -> Parsed(Channels),U32.is_eq(compression,3),
    _ => channels(at(54n,4n,bytes),at(58n,4n,bytes),at(62n,4n,bytes),Bool.pick(U32,Nat.is_ge(dib,56n),at(66n,4n,bytes),0),depth),
    _ => Bool.pick(Unit -> Parsed(Channels),U32.is_eq(depth,16),_ => channels(31744,992,31,0,16),_ => channels(16711680,65280,255,0,32))(Unit{}))(Unit{})

def headerFields(+bytes: List<&2,U32>, +total: Nat, +dib: Nat, limit: Nat) -> Parsed(HeaderInfo):
  +core = Nat.is_eq(dib,12n)
  +width = at(18n,Bool.pick(Nat,core,2n,4n),bytes)
  +rawHeight = at(Bool.pick(Nat,core,20n,22n),Bool.pick(Nat,core,2n,4n),bytes)
  +topDown = Bool.not(core) && U32.is_gt(rawHeight,2147483648)
  +height = Bool.pick(U32,topDown,(0 - rawHeight : U32),rawHeight)
  +depth = at(Bool.pick(Nat,core,24n,28n),2n,bytes)
  +compression = Bool.pick(U32,core,0,at(30n,4n,bytes))
  +used = Bool.pick(U32,core,0,at(46n,4n,bytes))
  +capacity = U32.to_nat(U32.shln(1,U32.to_nat(Bool.pick(U32,U32.is_le(depth,8),depth,0))))
  +paletteSize = Bool.pick(Nat,U32.is_le(depth,8),Bool.pick(Nat,U32.is_eq(used,0),capacity,U32.to_nat(used)),0n)
  +offset = U32.to_nat(at(10n,4n,bytes))
  +minimum = 14n + dib + Bool.pick(Nat,Nat.is_eq(dib,40n) && U32.is_eq(compression,3),12n,0n) + paletteSize * Bool.pick(Nat,core,3n,4n)
  Bool.pick(Unit -> Parsed(HeaderInfo),U32.is_gt(width,0) && U32.is_le(width,65535) && U32.is_gt(height,0) && U32.is_le(height,65535) && Image.validDimensions(width,height),
    _ => Bool.pick(Unit -> Parsed(HeaderInfo),Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit),
      _ => Bool.pick(Unit -> Parsed(HeaderInfo),supported(core,depth,compression,topDown),
        _ => Bool.pick(Unit -> Parsed(HeaderInfo),U32.is_eq(at(Bool.pick(Nat,core,22n,26n),2n,bytes),1) && Nat.is_le(paletteSize,capacity) && Nat.is_ge(offset,minimum) && Nat.is_le(offset,total),
          _ => bind(Channels,HeaderInfo,headerMasks(depth,compression,dib,bytes),masks => Done{HeaderInfo{width,height,topDown,depth,compression,dib,offset,paletteSize,masks}}),_ => Fail{Header{}})(Unit{}),
        _ => Fail{Unsupported{}})(Unit{}),_ => Fail{PixelLimit{}})(Unit{}),_ => Fail{Dimensions{}})(Unit{})

def header(bytes: List<&2,U32>, +total: Nat, limit: Nat) -> Parsed(HeaderInfo):
  match bytes:
    case 66 <> 77 <> +rest:
      +all = {66 <> 77 <> rest : List<&2,U32>}
      +dib = U32.to_nat(at(14n,4n,all))
      Bool.pick(Unit -> Parsed(HeaderInfo),Nat.is_ge(total,18n),
        _ => Bool.pick(Unit -> Parsed(HeaderInfo),Nat.is_eq(dib,12n) || Nat.is_eq(dib,40n) || Nat.is_eq(dib,52n) || Nat.is_eq(dib,56n) || Nat.is_eq(dib,108n) || Nat.is_eq(dib,124n),
          _ => Bool.pick(Unit -> Parsed(HeaderInfo),Nat.is_ge(total,14n + dib),_ => headerFields(all,total,dib,limit),_ => Fail{Truncated{}})(Unit{}),_ => Fail{Unsupported{}})(Unit{}),_ => Fail{Truncated{}})(Unit{})
    case _: Fail{Signature{}}

# A fixed eight-level immutable palette keeps per-pixel lookup bounded without
# copying a palette or walking up to 256 list elements for each sample.
type Palette is Data:
  Leaf{pixel: Maybe<&2,U32>}
  Branch{left: Palette, right: Palette}

def paletteTree(depth: Nat, values: List<&2,U32>) -> Palette:
  match depth values:
    case 0n Nil{}: Leaf{None{}}
    case 0n pixel <> _: Leaf{Some{pixel}}
    case 1n+ +n +rest: Branch{paletteTree(n,rest),paletteTree(n,skip(U32.to_nat(U32.shln(1,n)),rest))}

def lookup(table: Palette, +index: U32, +bit: U32) -> Parsed(U32):
  match table:
    case Leaf{None{}}: Fail{PaletteIndex{}}
    case Leaf{Some{pixel}}: Done{pixel}
    case Branch{left,right}: Bool.pick(Unit -> Parsed(U32),U32.is_eq(U32.and(index,bit),0),_ => lookup(left,index,U32.shr(bit)),_ => lookup(right,index,U32.shr(bit)))(Unit{})

def paletteEntries(count: Nat, +core: Bool, bytes: List<&2,U32>, reversed: List<&2,U32>) -> List<&2,U32>:
  match count bytes:
    case 0n _: List.reverse(&2,U32,reversed)
    case 1n+n b <> g <> r <> +rest: paletteEntries(n,core,Bool.pick(List<&2,U32>,core,rest,skip(1n,rest)),pack(r,g,b,255) <> reversed)
    case _ _: List.reverse(&2,U32,reversed)

type Samples is Data: Samples{bytes: List<&2,U32>, buffered: U32, bits: Nat}
type Sample is Data: Sample{value: U32, cursor: Samples}

def packed(+depth: Nat, bytes: List<&2,U32>, +buffered: U32, +bits: Nat) -> Parsed(Sample):
  Bool.pick(Parsed(Sample),Nat.is_le(depth,bits),Done{Sample{U32.and(U32.shrn(buffered,bits - depth),(U32.shln(1,depth) - 1 : U32)),Samples{bytes,buffered,bits - depth}}},Fail{Truncated{}})

def sample(+depth: U32, cursor: Samples) -> Parsed(Sample):
  match cursor:
    case Samples{Nil{},_,0n}: Fail{Truncated{}}
    case Samples{+byte <> +rest,_,0n}:
      Bool.pick(Unit -> Parsed(Sample),U32.is_le(depth,8),_ => packed(U32.to_nat(depth),rest,byte,8n),
            _ => Bool.pick(Unit -> Parsed(Sample),U32.is_eq(depth,16),_ => packed(16n,skip(1n,rest),word(2n,byte <> rest,1,0),16n),
              _ => Done{Sample{word(U32.to_nat((depth / 8 : U32)),byte <> rest,1,0),Samples{skip(U32.to_nat((depth / 8 - 1 : U32)),rest),0,0n}}})(Unit{}))(Unit{})
    case Samples{bytes,buffered,bits}: packed(U32.to_nat(depth),bytes,buffered,bits)

type Row is Data: Row{bytes: List<&2,U32>, reversed: List<&2,U32>}
type RowState is Data: RowState{cursor: Samples, reversed: List<&2,U32>}

def pixelSample(+depth: U32, masks: Channels, palette: Palette, value: Sample) -> Parsed(Sample):
  match value:
    case Sample{+value,+cursor}:
      Bool.pick(Unit -> Parsed(Sample),U32.is_le(depth,8),_ => bind(U32,Sample,lookup(palette,value,128),pixel => Done{Sample{pixel,cursor}}),_ => Done{Sample{color(value,masks),cursor}})(Unit{})

def nextPixel(reversed: List<&2,U32>, value: Sample) -> Parsed(RowState):
  match value:
    case Sample{pixel,cursor}: Done{RowState{cursor,pixel <> reversed}}

def scanPixels(count: Nat, +depth: U32, +masks: Channels, +palette: Palette, state: Parsed(RowState)) -> Parsed(Row):
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n Done{RowState{Samples{bytes,_,_},reversed}}: Done{Row{bytes,reversed}}
    case 1n+n Done{RowState{cursor,reversed}}:
      scanPixels(n,depth,masks,palette,bind(Sample,RowState,bind(Sample,Sample,sample(depth,cursor),value => pixelSample(depth,masks,palette,value)),value => nextPixel(reversed,value)))

def padded(width: U32, depth: U32, value: Row) -> Parsed(Row):
  match value:
    case Row{bytes,reversed}: Done{Row{skip(Nat.mod(4n - Nat.mod((U32.to_nat(width) * U32.to_nat(depth) + 7n) / 8n,4n),4n),bytes),reversed}}

def rows(count: Nat, +width: U32, +depth: U32, +masks: Channels, +palette: Palette, state: Parsed(Row)) -> Parsed(List<&2,U32>):
  match count state:
    case _ Fail{cause}: Fail{cause}
    case 0n Done{Row{_,reversed}}: Done{List.reverse(&2,U32,reversed)}
    case 1n+n Done{Row{bytes,reversed}}:
      rows(n,width,depth,masks,palette,bind(Row,Row,scanPixels(U32.to_nat(width),depth,masks,palette,Done{RowState{Samples{bytes,0,0n},reversed}}),value => padded(width,depth,value)))

def black(count: Nat, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: reversed
    case 1n+n: black(n,255 <> reversed)

def enough(count: Nat, bytes: List<&2,U32>) -> Bool:
  match count bytes:
    case 0n _: True{}
    case 1n+n _ <> rest: enough(n,rest)
    case _ Nil{}: False{}

type RleState is Data:
  RleState{bytes: List<&2,U32>, x: Nat, y: Nat, reversed: List<&2,U32>}
type RleStep is Data:
  Continue{state: RleState}
  Complete{pixels: List<&2,U32>}

def repeated(count: Nat, +depth: U32, +pattern: U32, +high: Bool, +palette: Palette, reversed: List<&2,U32>) -> Parsed(List<&2,U32>):
  match count:
    case 0n: Done{reversed}
    case 1n+n:
      index = Bool.pick(U32,U32.is_eq(depth,8),pattern,Bool.pick(U32,high,U32.shrn(pattern,4n),U32.and(pattern,15)))
      bind(U32,List<&2,U32>,lookup(palette,index,128),pixel => repeated(n,depth,pattern,Bool.not(high),palette,pixel <> reversed))

def runRow(x: Nat, y: Nat, bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(RleStep):
  Done{Continue{RleState{bytes,x,y,reversed}}}

def absoluteRow(x: Nat, y: Nat, padding: Nat, value: Row) -> Parsed(RleStep):
  match value:
    case Row{bytes,reversed}: runRow(x,y,skip(padding,bytes),reversed)

def rleLiteral(+count: Nat, +width: Nat, +x: Nat, y: Nat, +depth: U32, masks: Channels, palette: Palette, +bytes: List<&2,U32>, reversed: List<&2,U32>) -> Parsed(RleStep):
  +byteCount = (count * U32.to_nat(depth) + 7n) / 8n
  +padding = Nat.mod(byteCount,2n)
  Bool.pick(Unit -> Parsed(RleStep),Nat.is_le(x + count,width),
    _ => Bool.pick(Unit -> Parsed(RleStep),enough(byteCount + padding,bytes),
      _ => bind(Row,RleStep,scanPixels(count,depth,masks,palette,Done{RowState{Samples{bytes,0,0n},reversed}}),value => absoluteRow(x + count,y,padding,value)),_ => Fail{Truncated{}})(Unit{}),_ => Fail{RunLength{}})(Unit{})

def instruction(+width: Nat, +height: Nat, +depth: U32, masks: Channels, palette: Palette, state: RleState) -> Parsed(RleStep):
  match state:
    case RleState{0 <> 0 <> rest,+x,+y,reversed}:
      runRow(0n,1n + y,rest,black(width - x,reversed))
    case RleState{0 <> 1 <> _,x,y,reversed}:
      Done{Complete{List.reverse(&2,U32,black(width * (height - y) - x,reversed))}}
    case RleState{0 <> 2 <> dx <> dy <> rest,+x,+y,reversed}:
      +nextX = x + U32.to_nat(dx)
      +nextY = y + U32.to_nat(dy)
      Bool.pick(Unit -> Parsed(RleStep),Nat.is_le(nextX,width) && Nat.is_lt(nextY,height),
        _ => Done{Continue{RleState{rest,nextX,nextY,black((nextY - y)*width + nextX - x,reversed)}}},_ => Fail{RunLength{}})(Unit{})
    case RleState{0 <> count <> rest,x,y,reversed}:
      rleLiteral(U32.to_nat(count),width,x,y,depth,masks,palette,rest,reversed)
    case RleState{count <> pattern <> rest,+x,y,reversed}:
      +n = U32.to_nat(count)
      Bool.pick(Unit -> Parsed(RleStep),Nat.is_le(x + n,width),
        _ => bind(List<&2,U32>,RleStep,repeated(n,depth,pattern,True{},palette,reversed),values => runRow(x + n,y,rest,values)),_ => Fail{RunLength{}})(Unit{})
    case _: Fail{Truncated{}}

def rle(fuel: Nat, +width: Nat, +height: Nat, +depth: U32, +masks: Channels, +palette: Palette, step: Parsed(RleStep)) -> Parsed(List<&2,U32>):
  match fuel step:
    case _ Fail{cause}: Fail{cause}
    case _ Done{Complete{pixels}}: Done{pixels}
    case 0n _: Fail{Truncated{}}
    case 1n+n Done{Continue{RleState{bytes,x,+y,+reversed}}}:
      Bool.pick(Unit -> Parsed(List<&2,U32>),Nat.is_eq(y,height),_ => Done{List.reverse(&2,U32,reversed)},
        _ => rle(n,width,height,depth,masks,palette,instruction(width,height,depth,masks,palette,RleState{bytes,x,y,reversed})))(Unit{})

def decoded(+width: U32, +height: U32, topDown: Bool, value: Parsed(List<&2,U32>)) -> Result<&2,&1,Error,Image.Raster>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{pixels}:
      Done{Image.Raster{width,height,Image.scatter(pixels,Bool.pick(U32,topDown,1,4),width,height,0,Array.new(U32,Image.depth(31n,(width * height : U32),1,0n),0))}}

def render(+bytes: List<&2,U32>, +total: Nat, info: HeaderInfo) -> Result<&2,&1,Error,Image.Raster>:
  match info:
    case HeaderInfo{+width,+height,topDown,+depth,+compression,+dib,+offset,+colors,+masks}:
      +palette = Bool.pick(Unit -> Palette,Nat.is_eq(colors,0n),_ => Leaf{None{}},_ => paletteTree(8n,paletteEntries(colors,Nat.is_eq(dib,12n),skip(14n + dib,bytes),Nil{})))(Unit{})
      +data = skip(offset,bytes)
      +stride = ((U32.to_nat(width) * U32.to_nat(depth) + 31n) / 32n) * 4n
      decoded(width,height,topDown,Bool.pick(Unit -> Parsed(List<&2,U32>),U32.is_eq(compression,1) || U32.is_eq(compression,2),
        _ => rle(1n + total,U32.to_nat(width),U32.to_nat(height),depth,masks,palette,Done{Continue{RleState{data,0n,0n,Nil{}}}}),
        _ => Bool.pick(Unit -> Parsed(List<&2,U32>),Nat.is_le(stride * U32.to_nat(height),total - offset),
          _ => rows(U32.to_nat(height),width,depth,masks,palette,Done{Row{data,Nil{}}}),_ => Fail{Truncated{}})(Unit{}))(Unit{}))

def parsed(bytes: List<&2,U32>, total: Nat, result: Parsed(HeaderInfo)) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{info}: render(bytes,total,info)

def checked(+bytes: List<&2,U32>, limit: Nat, result: Parsed(Nat)) -> Result<&2,&1,Error,Image.Raster>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{+total}: parsed(bytes,total,header(bytes,total,limit))

def decode(+bytes: List<&2,U32>, pixelLimit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  checked(bytes,pixelLimit,size(bytes,0n))
