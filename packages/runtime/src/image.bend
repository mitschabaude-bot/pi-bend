import Base

# Row-major RGBA8 pixels packed as 0xRRGGBBAA. Codecs and transforms share
# this owned image; padding in the power-of-two array is not part of the image.
type Raster is Type:
  Raster{width: U32, height: U32, pixels: Array<U32>}

type Error is Data:
  InvalidDimensions{}
  InvalidPixelCount{}
  InvalidOrientation{}

# Array capacities are powers of two. Limiting the logical count to 2^31
# keeps both capacity and every row-major index representable as U32.
def validDimensions(+width: U32, +height: U32) -> Bool:
  Bool.pick(Unit -> Bool,U32.is_eq(height,0),_ => False{},_ => U32.is_gt(width,0) && U32.is_le(width,(2147483648 / height : U32)))(Unit{})

def depth(fuel: Nat, +count: U32, +capacity: U32, +level: Nat) -> Nat:
  match fuel:
    case 0n: level
    case 1n+n:
      Bool.pick(Unit -> Nat,U32.is_ge(capacity,count),_ => level,_ => depth(n,count,U32.shl(capacity),1n+level))(Unit{})

# EXIF's eight orientations are permutations, preserving all four channels.
# Orientations 5 through 8 exchange the output width and height.
def destination(orientation: U32, +x: U32, +y: U32, +width: U32, +height: U32) -> U32:
  match orientation:
    case 2: (y * width + width - 1 - x : U32)
    case 3: ((height - 1 - y) * width + width - 1 - x : U32)
    case 4: ((height - 1 - y) * width + x : U32)
    case 5: (x * height + y : U32)
    case 6: (x * height + height - 1 - y : U32)
    case 7: ((width - 1 - x) * height + height - 1 - y : U32)
    case 8: ((width - 1 - x) * height + y : U32)
    case _: (y * width + x : U32)

def scatter(pixels: List<&2,U32>, +orientation: U32, +width: U32, +height: U32, +index: U32, target: Array<U32>) -> Array<U32>:
  match pixels:
    case Nil{}: target
    case pixel <> rest:
      next = Array.set(U32,target,destination(orientation,(index % width : U32),(index / width : U32),width,height),pixel)
      scatter(rest,orientation,width,height,(index + 1 : U32),next)

def pixelCount(pixels: List<&2,U32>, count: Nat) -> Nat:
  match pixels:
    case Nil{}: count
    case _ <> rest: pixelCount(rest,1n+count)

def fromPixels(+width: U32, +height: U32, +pixels: List<&2,U32>) -> Result<&2,&1,Error,Raster>:
  Bool.pick(Unit -> Result<&2,&1,Error,Raster>,validDimensions(width,height),
    _ => Bool.pick(Unit -> Result<&2,&1,Error,Raster>,Nat.is_eq(pixelCount(pixels,0n),U32.to_nat(width) * U32.to_nat(height)),
      _ => Done{Raster{width,height,scatter(pixels,1,width,height,0,Array.new(U32,depth(31n,(width * height : U32),1,0n),0))}},
      _ => Fail{InvalidPixelCount{}})(Unit{}),
    _ => Fail{InvalidDimensions{}})(Unit{})

def takePixels(count: Nat, pixels: List<U32>, reversed: List<U32>) -> List<U32>:
  match count pixels:
    case 0n _: List.reverse(&1,U32,reversed)
    case _ Nil{}: List.reverse(&1,U32,reversed)
    case 1n+n pixel <> rest: takePixels(n,rest,pixel <> reversed)

# Consumes a valid raster and omits unused array capacity.
def toPixels(image: Raster) -> List<U32>:
  match image:
    case Raster{width,height,pixels}: takePixels(U32.to_nat(width) * U32.to_nat(height),Array.to_list(~U32,pixels),Nil{})

def moved(+index: U32, orientation: U32, +width: U32, height: U32, target: Array<U32>, fetched: Array<U32> & U32) -> Array<U32> & Array<U32>:
  match fetched:
    case (source,pixel):
      (source,Array.set(U32,target,destination(orientation,(index % width : U32),(index / width : U32),width,height),pixel))

def movePixel(+index: U32, orientation: U32, +width: U32, height: U32, buffers: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match buffers:
    case (source,target): moved(index,orientation,width,height,target,Array.get(U32,source,index))

def targetPixels(buffers: Array<U32> & Array<U32>) -> Array<U32>:
  match buffers:
    case (_,target): target

def rearrange(count: Nat, +index: U32, +orientation: U32, +width: U32, +height: U32, buffers: Array<U32> & Array<U32>) -> Array<U32>:
  match count:
    case 0n: targetPixels(buffers)
    case 1n+n: rearrange(n,(index + 1 : U32),orientation,width,height,movePixel(index,orientation,width,height,buffers))

def permuteRotated(+orientation: U32, image: Raster) -> Raster:
  match image:
    case Raster{+width,+height,pixels}:
      +count = (width * height : U32)
      result = rearrange(U32.to_nat(count),0,orientation,width,height,(pixels,Array.new(U32,depth(31n,count,1,0n),0)))
      Raster{Bool.pick(U32,U32.is_ge(orientation,5),height,width),Bool.pick(U32,U32.is_ge(orientation,5),width,height),result}

def permute(+orientation: U32, image: Raster) -> Raster:
  Bool.pick(Raster -> Raster,U32.is_eq(orientation,1),value => value,value => permuteRotated(orientation,value))(image)

def orientCapacity(orientation: U32, +width: U32, +height: U32, sized: Array<U32> & U32) -> Result<&2,&1,Error,Raster>:
  match sized:
    case (pixels,capacity):
      Bool.pick(Unit -> Result<&2,&1,Error,Raster>,U32.is_ge(capacity,(width * height : U32)),
        _ => Done{permute(orientation,Raster{width,height,pixels})},_ => Fail{InvalidPixelCount{}})(Unit{})

def orientValid(valid: Bool, orientation: U32, image: Raster) -> Result<&2,&1,Error,Raster>:
  match valid image:
    case False{} _: Fail{InvalidOrientation{}}
    case True{} Raster{+width,+height,pixels}:
      Bool.pick(Unit -> Result<&2,&1,Error,Raster>,validDimensions(width,height),
        _ => orientCapacity(orientation,width,height,Array.size(U32,pixels)),_ => Fail{InvalidDimensions{}})(Unit{})

def orient(+orientation: U32, image: Raster) -> Result<&2,&1,Error,Raster>:
  orientValid(U32.is_ge(orientation,1) && U32.is_le(orientation,8),orientation,image)
