import Base
import ./image.bend as Image

# Separable Lanczos3 on straight RGBA samples, matching Photon/image-rs:
# vertical float32 intermediate, then horizontal rounding to RGBA8.
# Reference algorithm: image-rs/image v0.24.8 src/imageops/sample.rs.
type Error is Data:
  InvalidImage{cause: Image.Error}
  InvalidDimensions{}
  PixelLimit{}

type Channels is Data:
  Channels{r: F32, g: F32, b: F32, a: F32}

def zero() -> Channels: Channels{0.0,0.0,0.0,0.0}

def unpack(+pixel: U32) -> Channels:
  Channels{U32.to_f32(U32.shrn(pixel,24n)),U32.to_f32(U32.and(U32.shrn(pixel,16n),255)),U32.to_f32(U32.and(U32.shrn(pixel,8n),255)),U32.to_f32(U32.and(pixel,255))}

def rounded(+value: F32) -> U32:
  +whole = F32.floor(value)
  (F32.to_u32(whole) + Bool.pick(U32,F32.is_ge((value - whole : F32),0.5),1,0) : U32)

def byte(value: F32) -> U32: rounded(F32.clamp(value,0.0,255.0))

def pack(channels: Channels) -> U32:
  match channels:
    case Channels{r,g,b,a}: U32.or(U32.shln(byte(r),24n),U32.or(U32.shln(byte(g),16n),U32.or(U32.shln(byte(b),8n),byte(a))))

def weighted(+weight: F32, total: Channels, pixel: Channels) -> Channels:
  match total pixel:
    case Channels{r,g,b,a} Channels{x,y,z,w}: Channels{(r + x * weight : F32),(g + y * weight : F32),(b + z * weight : F32),(a + w * weight : F32)}

def sinc(+value: F32) -> F32:
  +angle = (value * F32.pi() : F32)
  Bool.pick(Unit -> F32,F32.is_eq(value,0.0),_ => 1.0,_ => (F32.sin(angle) / angle : F32))(Unit{})

def kernel(+value: F32) -> F32:
  Bool.pick(Unit -> F32,F32.is_lt(F32.abs(value),3.0),_ => (sinc(value) * sinc((value / 3.0 : F32)) : F32),_ => 0.0)(Unit{})

type Weights is Data:
  Weights{start: U32, values: List<&2,F32>}

def normalized(weights: List<&2,F32>, +sum: F32, values: List<&2,F32>) -> List<&2,F32>:
  match weights:
    case Nil{}: values
    case weight <> rest: normalized(rest,sum,(weight / sum : F32) <> values)

def accumulated(count: Nat, +index: U32, +center: F32, +scale: F32, weights: List<&2,F32>, sum: F32) -> List<&2,F32>:
  match count:
    case 0n: normalized(weights,sum,Nil{})
    case 1n+n:
      +weight = kernel(((U32.to_f32(index) - center) / scale : F32))
      accumulated(n,(index + 1 : U32),center,scale,weight <> weights,(sum + weight : F32))

def weights(+source: U32, target: U32, position: U32) -> Weights:
  +ratio = (U32.to_f32(source) / U32.to_f32(target) : F32)
  +scale = F32.max(ratio,1.0)
  +center = ((U32.to_f32(position) + 0.5) * ratio : F32)
  +support = (3.0 * scale : F32)
  +left = U32.min(F32.to_u32(F32.clamp(F32.floor((center - support : F32)),0.0,2147483648.0)),(source - 1 : U32))
  right = U32.max((left + 1 : U32),U32.min(F32.to_u32(F32.clamp(F32.ceil((center + support : F32)),0.0,2147483648.0)),source))
  Weights{left,accumulated(U32.to_nat((right - left : U32)),left,(center - 0.5 : F32),scale,Nil{},0.0)}

type Sample is Type:
  Sample{pixels: Array<Channels>, total: Channels}

def sampled(weight: F32, total: Channels, fetched: Array<Channels> & Channels) -> Sample:
  match fetched:
    case (pixels,pixel): Sample{pixels,weighted(weight,total,pixel)}

def sample(weights: List<&2,F32>, +index: U32, +stride: U32, state: Sample) -> Sample:
  match weights state:
    case Nil{} state: state
    case weight <> rest Sample{pixels,total}: sample(rest,(index + stride : U32),stride,sampled(weight,total,Array.get(Channels,pixels,index)))

# The same traversal handles both axes; weights are computed once per output
# coordinate and reused across every perpendicular row/column.
type Axis is Data:
  Axis{source: U32, target: U32, lines: U32, sourceStride: U32, lineStride: U32, targetStride: U32, targetLineStride: U32}
type Buffers is Type:
  Buffers{source: Array<Channels>, target: Array<Channels>}

def stored(index: U32, target: Array<Channels>, sampled: Sample) -> Buffers:
  match sampled:
    case Sample{source,total}: Buffers{source,Array.set(Channels,target,index,total)}

def pixel(axis: Axis, weights: Weights, position: U32, +line: U32, state: Buffers) -> Buffers:
  match axis weights state:
    case Axis{_,_,_,+sourceStride,lineStride,targetStride,targetLineStride} Weights{start,values} Buffers{source,target}:
      stored((position * targetStride + line * targetLineStride : U32),target,sample(values,(start * sourceStride + line * lineStride : U32),sourceStride,Sample{source,zero()}))

def lines(count: Nat, +line: U32, +axis: Axis, +weights: Weights, +position: U32, state: Buffers) -> Buffers:
  match count:
    case 0n: state
    case 1n+n: lines(n,(line + 1 : U32),axis,weights,position,pixel(axis,weights,position,line,state))

def strip(+axis: Axis, +position: U32, state: Buffers) -> Buffers:
  match axis:
    case Axis{source,target,lineCount,_,_,_,_}: lines(U32.to_nat(lineCount),0,axis,weights(source,target,position),position,state)

def finished(state: Buffers) -> Array<Channels>:
  match state:
    case Buffers{_,target}: target

def pass(count: Nat, +position: U32, +axis: Axis, state: Buffers) -> Array<Channels>:
  match count:
    case 0n: finished(state)
    case 1n+n: pass(n,(position + 1 : U32),axis,strip(axis,position,state))

def resample(+width: U32, +height: U32, +newWidth: U32, +newHeight: U32, source: Array<U32>) -> Image.Raster:
  vertical = pass(U32.to_nat(newHeight),0,Axis{height,newHeight,width,width,1,width,1},Buffers{Array.map(~U32,~Channels,~(value => unpack(value)),source),Array.new(Channels,Image.depth(31n,(width * newHeight : U32),1,0n),zero())})
  horizontal = pass(U32.to_nat(newWidth),0,Axis{width,newWidth,newHeight,1,width,1,newWidth},Buffers{vertical,Array.new(Channels,Image.depth(31n,(newWidth * newHeight : U32),1,0n),zero())})
  Image.Raster{newWidth,newHeight,Array.map(~Channels,~U32,~pack,horizontal)}

def resizeValid(valid: Bool, +width: U32, +height: U32, +limit: Nat, image: Image.Raster) -> Result<&2,&1,Error,Image.Raster>:
  match valid image:
    case False{} _: Fail{InvalidDimensions{}}
    case True{} Image.Raster{+oldWidth,+oldHeight,pixels}:
      Bool.pick(Array<U32> -> Result<&2,&1,Error,Image.Raster>,Nat.is_le(U32.to_nat(width) * U32.to_nat(height),limit) && Nat.is_le(U32.to_nat(oldWidth) * U32.to_nat(height),limit),
        input => Done{Bool.pick(Array<U32> -> Image.Raster,U32.is_eq(width,oldWidth) && U32.is_eq(height,oldHeight),p => Image.Raster{oldWidth,oldHeight,p},p => resample(oldWidth,oldHeight,width,height,p))(input)},
        _ => Fail{PixelLimit{}})(pixels)

def resizeChecked(+width: U32, +height: U32, limit: Nat, checked: Result<&2,&1,Image.Error,Image.Raster>) -> Result<&2,&1,Error,Image.Raster>:
  match checked:
    case Fail{cause}: Fail{InvalidImage{cause}}
    case Done{Image.Raster{+oldWidth,oldHeight,pixels}}: resizeValid(Image.validDimensions(width,height) && Image.validDimensions(oldWidth,height),width,height,limit,Image.Raster{oldWidth,oldHeight,pixels})

# Pixel budget applies to the output and the vertical intermediate, before
# allocation. Invalid source storage is rejected even for an identity resize.
def resize(image: Image.Raster, width: U32, height: U32, limit: Nat) -> Result<&2,&1,Error,Image.Raster>:
  resizeChecked(width,height,limit,Image.orient(1,image))
