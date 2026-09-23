import Base
import ../../../runtime/src/text.bend as Text
import ./image-convert.bend as Convert
import ./image-resize.bend as Resize
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/number-string.bend as Strings

type ProcessImageOptions is Data:
  ProcessImageOptions{autoResizeImages: Maybe<&2,Bool>, resizeOptions: Maybe<&2,Resize.ImageResizeOptions>}

type ProcessImageResult is Data:
  Processed{data: String, mimeType: String, hints: List<&2,String>}
  Unsupported{message: String}

type NormalizedImage is Data:
  NormalizedImage{bytes: List<&2,U32>, mimeType: String, convertedFrom: Maybe<&2,String>}

def mimePrefix(text: String, reversed: String) -> String:
  match text:
    case SNil{}: Strings.reverseInto(reversed,"")
    case SCon{';',_}: Strings.reverseInto(reversed,"")
    case SCon{char,rest}: mimePrefix(rest,SCon{char,reversed})

def baseMimeType(mimeType: String) -> String: String.to_lower(Text.trim(mimePrefix(mimeType,"")))

def normalizeSupportedImageMimeType(mimeType: String) -> Maybe<&2,String>:
  match mimeType:
    case "image/png": Some{"image/png"}
    case "image/jpeg": Some{"image/jpeg"}
    case "image/jpg": Some{"image/jpeg"}
    case "image/gif": Some{"image/gif"}
    case "image/webp": Some{"image/webp"}
    case _: None{}

def converted(mime: String, value: Maybe<&2,List<&2,U32>>) -> Maybe<&2,NormalizedImage>:
  match value:
    case None{}: None{}
    case Some{bytes}: Some{NormalizedImage{bytes,"image/png",Some{mime}}}

def normalized(bytes: List<&2,U32>, originalMime: String, mime: Maybe<&2,String>) -> Maybe<&2,NormalizedImage>:
  match mime:
    case Some{value}: Some{NormalizedImage{bytes,value,None{}}}
    case None{}: converted(originalMime,Convert.convertImageBytesToPng(bytes))

def conversionHint(from: Maybe<&2,String>, +to: String) -> List<&2,String>:
  match from:
    case None{}: Nil{}
    case Some{+value}: Bool.pick(List<&2,String>,String.is_empty(value) || String.eq(value,to),Nil{},("[Image converted from " ++ value ++ " to " ++ to ++ ".]") <> Nil{})

def dimensionHints(value: Maybe<&2,String>) -> List<&2,String>:
  match value:
    case None{}: Nil{}
    case Some{note}: note <> Nil{}

def resized(from: Maybe<&2,String>, value: Maybe<&2,Resize.ResizedImage>) -> ProcessImageResult:
  match value:
    case None{}: Unsupported{"[Image omitted: could not be resized below the inline image size limit.]"}
    case Some{Resize.ResizedImage{+data,+mime,ow,oh,w,h,changed}}:
      Processed{data,mime,List.append(&2,String,conversionHint(from,mime),dimensionHints(Resize.formatDimensionNote(Resize.ResizedImage{data,mime,ow,oh,w,h,changed})))}

def encoded(+mime: String, from: Maybe<&2,String>, value: Result<&2,&2,Base64.Error,String>) -> ProcessImageResult:
  match value:
    case Fail{_}: Unsupported{"[Image omitted: could not be converted to a supported inline image format.]"}
    case Done{data}: Processed{data,mime,conversionHint(from,mime)}

def processNormalized(options: ProcessImageOptions, value: Maybe<&2,NormalizedImage>) -> ProcessImageResult:
  match options value:
    case _ None{}: Unsupported{"[Image omitted: could not be converted to a supported inline image format.]"}
    case ProcessImageOptions{resize,configuration} Some{NormalizedImage{+bytes,+mime,+from}}:
      Bool.pick(Unit -> ProcessImageResult,Maybe.default(&2,Bool,resize,True{}),
        _ => resized(from,Resize.resizeImageInProcess(bytes,mime,Maybe.default(&2,Resize.ImageResizeOptions,configuration,Resize.defaults()))),
        _ => encoded(mime,from,Base64.encode(bytes)))(Unit{})

def processImage(bytes: List<&2,U32>, mimeType: String, options: ProcessImageOptions) -> ProcessImageResult:
  +mime = baseMimeType(mimeType)
  processNormalized(options,normalized(bytes,mime,normalizeSupportedImageMimeType(mime)))
