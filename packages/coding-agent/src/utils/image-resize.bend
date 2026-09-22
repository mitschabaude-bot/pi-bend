import Base
import ../../../runtime/src/image.bend as Image
import ../../../runtime/src/image-resize.bend as Resample
import ../../../runtime/src/png.bend as Png
import ../../../runtime/src/jpeg-encode.bend as Jpeg
import ../../../runtime/src/base64.bend as Base64
import ./image-convert.bend as Convert
import ./exif-orientation.bend as Exif

type ImageResizeOptions is Data:
  ImageResizeOptions{maxWidth: Maybe<&2,U32>, maxHeight: Maybe<&2,U32>, maxBytes: Maybe<&2,Nat>, jpegQuality: Maybe<&2,U32>}

type ResizedImage is Data:
  ResizedImage{data: String, mimeType: String, originalWidth: U32, originalHeight: U32, width: U32, height: U32, wasResized: Bool}

type Limits is Data:
  Limits{width: U32, height: U32, bytes: Nat, quality: U32}

type Candidate is Data:
  Candidate{data: String, mimeType: String}

def defaults() -> ImageResizeOptions: ImageResizeOptions{None{},None{},None{},None{}}

def options(value: ImageResizeOptions) -> Limits:
  match value:
    case ImageResizeOptions{w,h,b,q}: Limits{Maybe.default(&2,U32,w,2000),Maybe.default(&2,U32,h,2000),Maybe.default(&2,Nat,b,4718592n),Maybe.default(&2,U32,q,80)}

def length(bytes: List<&2,U32>, count: Nat) -> Nat:
  match bytes:
    case Nil{}: count
    case _ <> rest: length(rest,1n+count)

def encodedCandidate(mime: String, value: Result<&2,&2,Base64.Error,String>) -> Maybe<&2,Candidate>:
  match value:
    case Fail{_}: None{}
    case Done{data}: Some{Candidate{data,mime}}

def candidate(+bytes: List<&2,U32>, mime: String, limit: Nat) -> Maybe<&2,Candidate>:
  Bool.pick(Unit -> Maybe<&2,Candidate>,Nat.is_lt(((length(bytes,0n)+2n)/3n)*4n,limit),_ => encodedCandidate(mime,Base64.encode(bytes)),_ => None{})(Unit{})

# Pi uses a strict base64-size limit, not a binary-byte limit.
def binaryLimit(limit: Nat) -> Nat: ((limit - 1n) / 4n) * 3n

def otherQualities(values: List<&2,U32>, +preferred: U32) -> List<&2,U32>:
  match values:
    case Nil{}: Nil{}
    case +quality <> rest: Bool.pick(List<&2,U32> -> List<&2,U32>,U32.is_eq(quality,preferred),tail => tail,tail => quality <> tail)(otherQualities(rest,preferred))

def qualitySteps(+quality: U32) -> List<&2,U32>:
  quality <> otherQualities(85 <> 70 <> 55 <> 40 <> Nil{},quality)

type Trial is Type:
  Trial{image: Image.Raster, candidate: Maybe<&2,Candidate>}

def jpegResult(limit: Nat, pair: Image.Raster & Result<&2,&2,Jpeg.Error,List<&2,U32>>) -> Trial:
  match pair:
    case Tuple{image,Fail{_}}: Trial{image,None{}}
    case Tuple{image,Done{bytes}}: Trial{image,candidate(bytes,"image/jpeg",limit)}

def tryJpeg(qualities: List<&2,U32>, +limit: Nat, state: Trial) -> Maybe<&2,Candidate>:
  match qualities state:
    case _ Trial{_,Some{value}}: Some{value}
    case Nil{} Trial{_,None{}}: None{}
    case quality <> rest Trial{image,None{}}: tryJpeg(rest,limit,jpegResult(limit,Jpeg.encode(image,quality,binaryLimit(limit))))

def pngResult(limit: Nat, pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> Trial:
  match pair:
    case Tuple{image,Fail{_}}: Trial{image,None{}}
    case Tuple{image,Done{bytes}}: Trial{image,candidate(bytes,"image/png",limit)}

def resized(qualities: List<&2,U32>, +limit: Nat, result: Result<&2,&1,Resample.Error,Image.Raster>) -> Maybe<&2,Candidate>:
  match result:
    case Fail{_}: None{}
    case Done{image}: tryJpeg(qualities,limit,pngResult(limit,Png.encode(image,binaryLimit(limit))))

type Attempt is Type:
  Attempt{original: Image.Raster, candidate: Maybe<&2,Candidate>}

def cloned(+oldWidth: U32, +oldHeight: U32, width: U32, height: U32, quality: U32, limit: Nat, pair: Array<U32> & Array<U32>) -> Attempt:
  match pair:
    case (original,copy): Attempt{Image.Raster{oldWidth,oldHeight,original},resized(qualitySteps(quality),limit,Resample.resize(Image.Raster{oldWidth,oldHeight,copy},width,height,2147483648n))}

def attempt(width: U32, height: U32, quality: U32, limit: Nat, image: Image.Raster) -> Attempt:
  match image:
    case Image.Raster{oldWidth,oldHeight,pixels}: cloned(oldWidth,oldHeight,width,height,quality,limit,Array.clone(U32,pixels))

def reduced(value: U32) -> U32: U32.max(1,U32.from_nat((U32.to_nat(value)*3n)/4n))

# Every failed iteration shrinks at least one dimension until 1x1. The fuel
# is their initial sum, so the recursive traversal is structurally bounded.
def retry(fuel: Nat, +width: U32, +height: U32, +quality: U32, +limit: Nat, state: Attempt) -> Maybe<&2,ResizedImage>:
  match fuel state:
    case _ Attempt{Image.Raster{ow,oh,_},Some{Candidate{data,mime}}}: Some{ResizedImage{data,mime,ow,oh,width,height,True{}}}
    case 0n _: None{}
    case 1n+n Attempt{image,None{}}:
      Bool.pick(Image.Raster -> Maybe<&2,ResizedImage>,U32.is_eq(width,1) && U32.is_eq(height,1),_ => None{},
        original => retry(n,reduced(width),reduced(height),quality,limit,attempt(reduced(width),reduced(height),quality,limit,original)))(image)

# These products fit in Nat: each adjustment only shrinks a valid raster.
# Positive rational rounding is Math.round without floating-point drift.
def proportional(value: U32, bound: U32, +divisor: U32) -> U32:
  U32.from_nat((2n * U32.to_nat(value) * U32.to_nat(bound) + U32.to_nat(divisor)) / (2n * U32.to_nat(divisor)))

def fitHeight(+width: U32, +height: U32, +bound: U32) -> U32 & U32:
  Bool.pick(Unit -> U32 & U32,U32.is_gt(height,bound),_ => (proportional(width,bound,height),bound),_ => (width,height))(Unit{})

def fitWidth(+width: U32, +height: U32, +maxWidth: U32, +maxHeight: U32) -> U32 & U32:
  Bool.pick(Unit -> U32 & U32,U32.is_gt(width,maxWidth),_ => fitHeight(maxWidth,proportional(height,maxWidth,width),maxHeight),_ => fitHeight(width,height,maxHeight))(Unit{})

def start(+quality: U32, +limit: Nat, image: Image.Raster, dimensions: U32 & U32) -> Maybe<&2,ResizedImage>:
  match dimensions:
    case (+width,+height):
      Bool.pick(Image.Raster -> Maybe<&2,ResizedImage>,Image.validDimensions(width,height),
        original => retry(U32.to_nat(width) + U32.to_nat(height),width,height,quality,limit,attempt(width,height,quality,limit,original)),_ => None{})(image)

def original(+width: U32, +height: U32, value: Maybe<&2,Candidate>) -> Maybe<&2,ResizedImage>:
  match value:
    case None{}: None{}
    case Some{Candidate{data,mime}}: Some{ResizedImage{data,mime,width,height,width,height,False{}}}

def process(+bytes: List<&2,U32>, mime: String, limits: Limits, value: Result<&2,&1,Exif.Error,Image.Raster>) -> Maybe<&2,ResizedImage>:
  match limits value:
    case _ Fail{_}: None{}
    case Limits{+mw,+mh,+maximum,quality} Done{Image.Raster{+width,+height,pixels}}:
      Bool.pick(Array<U32> -> Maybe<&2,ResizedImage>,U32.is_le(width,mw) && U32.is_le(height,mh) && Nat.is_lt(((length(bytes,0n)+2n)/3n)*4n,maximum),
        _ => original(width,height,candidate(bytes,mime,maximum)),
        source => start(quality,maximum,Image.Raster{width,height,source},fitWidth(width,height,mw,mh)))(pixels)

def decoded(+bytes: List<&2,U32>, mime: String, limits: Limits, value: Maybe<&1,Image.Raster>) -> Maybe<&2,ResizedImage>:
  match value:
    case None{}: None{}
    case Some{image}: process(bytes,mime,limits,Exif.applyExifOrientation(image,bytes))

def resizeValid(valid: Bool, +bytes: List<&2,U32>, mime: String, limits: Limits) -> Maybe<&2,ResizedImage>:
  match valid:
    case False{}: None{}
    case True{}: decoded(bytes,mime,limits,Convert.decodeImage(bytes,2147483648n))

def resizeOptions(bytes: List<&2,U32>, +mimeType: String, +limits: Limits) -> Maybe<&2,ResizedImage>:
  match limits:
    case Limits{width,height,maximum,quality}:
      resizeValid(U32.is_gt(width,0) && U32.is_gt(height,0) && Nat.is_gt(maximum,0n) && U32.is_le(quality,255),bytes,Bool.pick(String,String.eq(mimeType,""),"image/png",mimeType),limits)

def resizeImageInProcess(bytes: List<&2,U32>, mimeType: String, value: ImageResizeOptions) -> Maybe<&2,ResizedImage>:
  resizeOptions(bytes,mimeType,options(value))
