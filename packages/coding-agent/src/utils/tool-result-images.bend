import Base
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/base64.bend as Base64
import ./image-process.bend as Images
import ./image-resize.bend as Resize

# upstream utils/tool-result-images.ts. The read tool and @file attachments
# process their images; tools that produce images themselves (extensions,
# MCP bridges, screenshot tools) hand back arbitrary base64 payloads that
# would go into the session history and every later request. They are
# normalized once, as they enter the history.

def ToolResultContent() -> Data: Ai.TextImageContent

type NormalizeToolResultImagesOptions is Data:
  NormalizeToolResultImagesOptions{autoResizeImages: Maybe<&2, Bool>, resizeOptions: Maybe<&2, Resize.ImageResizeOptions>}

def defaults() -> NormalizeToolResultImagesOptions: NormalizeToolResultImagesOptions{None{}, None{}}

# The normalized blocks so far (reversed) and whether any block changed.
type Normalized is Data: Normalized{reversed: List<&2, Ai.TextImageContent>, changed: Bool}

def kept(+block: Ai.TextImageContent, found: Normalized) -> Normalized:
  match found:
    case Normalized{reversed, changed}: Normalized{block <> reversed, changed}

def hintBlocks(hints: List<&2, String>) -> List<&2, Ai.TextImageContent>:
  match hints:
    case Nil{}: Nil{}
    case _: Ai.TextImageText{Ai.TextContent{String.join(hints, "\n"), None{}}} <> Nil{}

def replaced(+image: Ai.ImageContent, hints: List<&2, String>, found: Normalized) -> Normalized:
  match found:
    case Normalized{reversed, _}: Normalized{List.append(&2, Ai.TextImageContent, List.reverse(&2, Ai.TextImageContent, hintBlocks(hints)), Ai.TextImageImage{image} <> reversed), True{}}

# Unlike read, an image that cannot be processed keeps its original block: the
# tool produced it, and dropping it would silently delete tool output. An
# image processing leaves byte-identical, without hints, is also kept.
def processedBlock(+data: String, +mime: String, result: Images.ProcessImageResult, +found: Normalized) -> Normalized:
  match result:
    case Images.Unsupported{_}: kept(Ai.TextImageImage{Ai.ImageContent{data, mime}}, found)
    case Images.Processed{+newData, +newMime, +hints}:
      Bool.pick(Unit -> Normalized, String.eq(newData, data) && String.eq(newMime, mime) && List.is_empty(&2, String, hints),
        _ => kept(Ai.TextImageImage{Ai.ImageContent{data, mime}}, found),
        _ => replaced(Ai.ImageContent{newData, newMime}, hints, found))(Unit{})

# Base64 that does not decode keeps its block, as upstream keeps an image its
# (lenient) decoder turns into bytes no image reader accepts.
def decodedBlock(+data: String, +mime: String, +options: Images.ProcessImageOptions, decoded: Result<&2, &2, Base64.Error, List<&2, U32>>, +found: Normalized) -> Normalized:
  match decoded:
    case Fail{_}: kept(Ai.TextImageImage{Ai.ImageContent{data, mime}}, found)
    case Done{bytes}: processedBlock(data, mime, Images.processImage(bytes, mime, options), found)

def normalizeBlocks(blocks: List<&2, Ai.TextImageContent>, +options: Images.ProcessImageOptions, found: Normalized) -> Normalized:
  match blocks:
    case Nil{}: found
    case Ai.TextImageImage{Ai.ImageContent{+data, +mime}} <> rest: normalizeBlocks(rest, options, decodedBlock(data, mime, options, Base64.decode(data), found))
    case block <> rest: normalizeBlocks(rest, options, kept(block, found))

def processOptions(options: NormalizeToolResultImagesOptions) -> Images.ProcessImageOptions:
  match options:
    case NormalizeToolResultImagesOptions{resize, profile}: Images.ProcessImageOptions{Some{Maybe.default(&2, Bool, resize, True{})}, profile}

def changedBlocks(found: Normalized) -> Maybe<&2, List<&2, Ai.TextImageContent>>:
  match found:
    case Normalized{reversed, True{}}: Some{List.reverse(&2, Ai.TextImageContent, reversed)}
    case Normalized{_, False{}}: None{}

# The normalized content, or None when nothing changed (upstream returns the
# same array then, so callers can skip rewriting the result).
def normalizeToolResultImages(content: List<&2, Ai.TextImageContent>, options: NormalizeToolResultImagesOptions) -> Maybe<&2, List<&2, Ai.TextImageContent>>:
  changedBlocks(normalizeBlocks(content, processOptions(options), Normalized{Nil{}, False{}}))
