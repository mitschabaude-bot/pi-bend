import Base
import ../../../runtime/src/image.bend as Image
import ../../../runtime/src/png.bend as Png
import ../../../runtime/src/bmp.bend as Bmp
import ../../../runtime/src/gif.bend as Gif
import ../../../runtime/src/jpeg.bend as Jpeg
import ../../../runtime/src/base64.bend as Base64
import ./exif-orientation.bend as Exif

type ConvertedImage is Data:
  ConvertedImage{data: String, mimeType: String}

# Dispatch on bytes, not a caller-supplied MIME label, as Photon does.
# PNG, BMP, GIF and JPEG are integrated; WebP decoding remains pending.
def decoded(-E: Data, value: Result<&2,&1,E,Image.Raster>) -> Maybe<&1,Image.Raster>:
  match value:
    case Fail{_}: None{}
    case Done{image}: Some{image}

def decodeImage(+bytes: List<&2,U32>, pixelLimit: Nat) -> Maybe<&1,Image.Raster>:
  match bytes:
    case 137 <> 80 <> 78 <> 71 <> rest: decoded(Png.Error,Png.decode(137 <> 80 <> 78 <> 71 <> rest,pixelLimit))
    case 66 <> 77 <> rest: decoded(Bmp.Error,Bmp.decode(66 <> 77 <> rest,pixelLimit))
    case 71 <> 73 <> 70 <> rest: decoded(Gif.Error,Gif.decode(71 <> 73 <> 70 <> rest,pixelLimit))
    case 255 <> 216 <> rest: decoded(Jpeg.Error,Jpeg.decode(255 <> 216 <> rest,pixelLimit))
    case _: None{}

def encoded(pair: Image.Raster & Result<&2,&2,Png.Error,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match pair:
    case Tuple{_,Done{bytes}}: Some{bytes}
    case _: None{}

def oriented(byteLimit: Nat, value: Result<&2,&1,Exif.Error,Image.Raster>) -> Maybe<&2,List<&2,U32>>:
  match value:
    case Fail{_}: None{}
    case Done{image}: encoded(Png.encode(image,byteLimit))

def convertDecoded(bytes: List<&2,U32>, byteLimit: Nat, value: Maybe<&1,Image.Raster>) -> Maybe<&2,List<&2,U32>>:
  match value:
    case None{}: None{}
    case Some{image}: oriented(byteLimit,Exif.applyExifOrientation(image,bytes))

# Limits are checked by the codecs before pixel/output allocation. Encoding
# can produce different compressed bytes from Photon while preserving pixels.
def convertImageBytesToPngWithLimits(+bytes: List<&2,U32>, pixelLimit: Nat, byteLimit: Nat) -> Maybe<&2,List<&2,U32>>:
  convertDecoded(bytes,byteLimit,decodeImage(bytes,pixelLimit))

def convertImageBytesToPng(bytes: List<&2,U32>) -> Maybe<&2,List<&2,U32>>:
  convertImageBytesToPngWithLimits(bytes,2147483648n,2147483648n)

def base64Result(value: Result<&2,&2,Base64.Error,String>) -> Maybe<&2,ConvertedImage>:
  match value:
    case Fail{_}: None{}
    case Done{data}: Some{ConvertedImage{data,"image/png"}}

def converted(value: Maybe<&2,List<&2,U32>>) -> Maybe<&2,ConvertedImage>:
  match value:
    case None{}: None{}
    case Some{bytes}: base64Result(Base64.encode(bytes))

def convertBase64(value: Result<&2,&2,Base64.Error,List<&2,U32>>) -> Maybe<&2,ConvertedImage>:
  match value:
    case Fail{_}: None{}
    case Done{bytes}: converted(convertImageBytesToPng(bytes))

# Terminal PNG input is deliberately passed through unchanged, matching Pi.
# Other MIME labels request conversion of the actual decoded byte format.
def convertToPng(base64Data: String, mimeType: String) -> Maybe<&2,ConvertedImage>:
  match mimeType:
    case "image/png": Some{ConvertedImage{base64Data,"image/png"}}
    case _: convertBase64(Base64.decode(base64Data))
