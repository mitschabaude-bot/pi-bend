import Base
import ../terminal-image.bend as Terminal
import ../utils.bend as Utils
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/f64.bend as Number
import ../../../runtime/src/random.bend as Random

type ImageTheme is Data:
  ImageTheme{fallbackColor: Callback.Callback<String,String>}
type ImageOptions is Data:
  ImageOptions{maxWidthCells: Maybe<&2,F64>,maxHeightCells: Maybe<&2,F64>,filename: Maybe<&2,String>,imageId: Maybe<&2,U32>}
type Cache is Data: Cache{width: Nat,lines: List<&2,String>}
type ImageComponent is Data:
  ImageComponent{base64Data: String,mimeType: String,dimensions: Terminal.ImageDimensions,theme: ImageTheme,options: ImageOptions,imageId: Maybe<&2,U32>,cache: Maybe<&2,Cache>}
type Error is Data:
  ImageError{cause: Terminal.Error}
  EntropyError{cause: Random.Error}
type Rendered is Data:
  Rendered{image: ImageComponent,terminal: Terminal.State,lines: List<&2,String>}

def defaultOptions() -> ImageOptions: ImageOptions{None{},None{},None{},None{}}
def dimensions(value: Result<&2,&2,Terminal.Error,Terminal.ImageDimensions>) -> Terminal.ImageDimensions:
  match value:
    case Done{value}: value
    case Fail{_}: Terminal.ImageDimensions{800,600}
def chosenDimensions(data: String,mime: String,provided: Maybe<&2,Terminal.ImageDimensions>) -> Terminal.ImageDimensions:
  match provided:
    case Some{value}: value
    case None{}: dimensions(Terminal.getImageDimensions(data,mime))
def validOptions(options: ImageOptions) -> Bool:
  match options:
    case ImageOptions{width,height,_,id}: Terminal.validHeight(width) && Terminal.validHeight(height) && Terminal.validId(id)

# Unknown/unreadable headers intentionally use Pi's 800x600 estimate. Supplied
# dimensions/options reject invalid values; payload validation remains lazy so
# a text-only terminal can still show a useful fallback for an unknown format.
# The theme callback is borrowed and is never disposed by this component.
def new(+data: String,+mime: String,theme: ImageTheme,+options: ImageOptions,provided: Maybe<&2,Terminal.ImageDimensions>) -> Result<&2,&2,Error,ImageComponent>:
  match options:
    case ImageOptions{_,_,_,id}:
      +size = chosenDimensions(data,mime,provided)
      Bool.pick(Result<&2,&2,Error,ImageComponent>,Terminal.pixelDimensions(size) && validOptions(options),Done{ImageComponent{data,mime,size,theme,options,id,None{}}},Fail{ImageError{Terminal.InvalidDimensions{}}})
def getImageId(image: ImageComponent) -> Maybe<&2,U32>:
  match image:
    case ImageComponent{_,_,_,_,_,id,_}: id
def invalidate(image: ImageComponent) -> ImageComponent:
  match image:
    case ImageComponent{data,mime,size,theme,options,id,_}: ImageComponent{data,mime,size,theme,options,id,None{}}
def withId(image: ImageComponent,id: U32) -> ImageComponent:
  match image:
    case ImageComponent{data,mime,size,theme,options,_,cache}: ImageComponent{data,mime,size,theme,options,Some{id},cache}
def withCache(image: ImageComponent,width: Nat,+lines: List<&2,String>) -> ImageComponent:
  match image:
    case ImageComponent{data,mime,size,theme,options,id,_}: ImageComponent{data,mime,size,theme,options,id,Some{Cache{width,lines}}}
def completed(image: ImageComponent,terminal: Terminal.State,width: Nat,+lines: List<&2,String>) -> Result<&2,&2,Error,Rendered>:
  Done{Rendered{withCache(image,width,lines),terminal,lines}}
def needsId(image: ImageComponent,protocol: Terminal.ImageProtocol) -> Bool:
  match image protocol:
    case ImageComponent{_,_,_,_,_,None{},_} Terminal.Kitty{}: True{}
    case _ _: False{}
def allocated(image: ImageComponent,result: Result<&2,&2,Random.Error,U32>) -> Result<&2,&2,Error,ImageComponent>:
  match result:
    case Fail{cause}: Fail{EntropyError{cause}}
    case Done{id}: Done{withId(image,id)}
def allocate(+image: ImageComponent,protocol: Terminal.ImageProtocol) -> IO(Result<&2,&2,Error,ImageComponent>):
  Bool.pick(Unit -> IO(Result<&2,&2,Error,ImageComponent>),needsId(image,protocol),_ =>
    do IO<Result<&2,&2,Error,ImageComponent>>:
      id : Result<&2,&2,Random.Error,U32> <- Terminal.allocateImageId()
      return allocated(image,id),_ => IO.pure(Result<&2,&2,Error,ImageComponent>,Done{image}))(Unit{})

def emptyLines(count: Nat,result: List<&2,String>) -> List<&2,String>:
  match count:
    case 0n: result
    case 1n+rest: emptyLines(rest,"" <> result)
def imageLines(protocol: Terminal.ImageProtocol,sequence: String,+rows: Nat) -> List<&2,String>:
  match protocol:
    case Terminal.Kitty{}: sequence <> emptyLines(rows-1n,Nil{})
    case Terminal.ITerm2{}:
      +offset = rows-1n
      up = Bool.pick(String,Nat.is_eq(offset,0n),"","\u{1b}[" ++ Nat.show(offset) ++ "A")
      emptyLines(offset,(up ++ sequence) <> Nil{})
    case Terminal.NoImages{}: Nil{}
def fallbackText(image: ImageComponent,terminal: Terminal.State,+width: Nat,callback: Callback.Callback<String,String>,text: Result<&2,&2,Terminal.Error,String>) -> IO(Result<&2,&2,Error,Rendered>):
  match text:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Rendered>,Fail{ImageError{cause}})
    case Done{value}:
      do IO<Result<&2,&2,Error,Rendered>>:
        colored : String <- Callback.call(String,String,callback,value)
        return completed(image,terminal,width,[Utils.truncateToWidth(colored,width,"...",False{})])
def fallback(+image: ImageComponent,terminal: Terminal.State,width: Nat,environment: Terminal.Environment,capabilities: Terminal.TerminalCapabilities) -> IO(Result<&2,&2,Error,Rendered>):
  match image environment:
    case ImageComponent{_,mime,size,ImageTheme{callback},ImageOptions{_,_,filename,_},_,_} Terminal.Environment{_,_,home}:
      fallbackText(image,terminal,width,callback,Terminal.imageFallback(mime,Some{size},filename,home,capabilities))
def imageResult(+image: ImageComponent,width: Nat,environment: Terminal.Environment,+capabilities: Terminal.TerminalCapabilities,result: Result<&2,&2,Terminal.Error,Terminal.Rendered>) -> IO(Result<&2,&2,Error,Rendered>):
  match capabilities result:
    case _ Fail{cause}: IO.pure(Result<&2,&2,Error,Rendered>,Fail{ImageError{cause}})
    case _ Done{Terminal.Rendered{terminal,None{}}}: fallback(image,terminal,width,environment,capabilities)
    case Terminal.TerminalCapabilities{protocol,_,_} Done{Terminal.Rendered{terminal,Some{Terminal.RenderResult{sequence,_,rows,id}}}}:
      IO.pure(Result<&2,&2,Error,Rendered>,completed(image,terminal,width,imageLines(protocol,sequence,rows)))
def widthLimit(width: Nat,configured: Maybe<&2,F64>) -> F64:
  Number.maximum(Number.fromU32(1),Number.minimum(Number.fromU32(U32.from_nat(Nat.min(width-2n,4294967295n))),Maybe.default(&2,F64,configured,Number.fromU32(60))))
def maximumHeight(configured: Maybe<&2,F64>,width: F64,cells: Terminal.CellDimensions) -> F64:
  match configured cells:
    case Some{value} _: value
    case None{} Terminal.CellDimensions{cellWidth,cellHeight}: Number.maximum(Number.fromU32(1),Number.ceil(Number.divide(Number.multiply(width,cellWidth),cellHeight)))
def drawImage(+image: ImageComponent,+terminal: Terminal.State,+width: Nat,+environment: Terminal.Environment,+capabilities: Terminal.TerminalCapabilities) -> IO(Result<&2,&2,Error,Rendered>):
  match image:
    case ImageComponent{data,_,size,_,ImageOptions{limit,height,_,_},id,_}:
      +maxWidth = widthLimit(width,limit)
      maxHeight = maximumHeight(height,maxWidth,Terminal.getCellDimensions(terminal))
      imageResult(image,width,environment,capabilities,Terminal.renderImage(terminal,environment,False{},data,size,Terminal.ImageRenderOptions{Some{maxWidth},Some{maxHeight},True{},id,False{}}))
def draw(allocated: Result<&2,&2,Error,ImageComponent>,terminal: Terminal.State,width: Nat,environment: Terminal.Environment,capabilities: Terminal.TerminalCapabilities) -> IO(Result<&2,&2,Error,Rendered>):
  match allocated:
    case Fail{cause}: IO.pure(Result<&2,&2,Error,Rendered>,Fail{cause})
    case Done{image}: drawImage(image,terminal,width,environment,capabilities)
def detected(+image: ImageComponent,width: Nat,environment: Terminal.Environment,pair: Terminal.State & Terminal.TerminalCapabilities) -> IO(Result<&2,&2,Error,Rendered>):
  match pair:
    case (terminal,Terminal.TerminalCapabilities{Terminal.NoImages{},color,links}): fallback(image,terminal,width,environment,Terminal.TerminalCapabilities{Terminal.NoImages{},color,links})
    case (terminal,Terminal.TerminalCapabilities{+protocol,color,links}):
      do IO<Result<&2,&2,Error,Rendered>>:
        ready : Result<&2,&2,Error,ImageComponent> <- allocate(image,protocol)
        draw(ready,terminal,width,environment,Terminal.TerminalCapabilities{protocol,color,links})

# A width hit returns the original cached lines without callbacks, allocation or
# capability inspection. Invalidate explicitly when terminal/theme state changes.
def render(+image: ImageComponent,+width: Nat,+terminal: Terminal.State,+environment: Terminal.Environment,+tmuxHyperlinks: Bool) -> IO(Result<&2,&2,Error,Rendered>):
  match image:
    case ImageComponent{_,_,_,_,_,_,Some{Cache{cachedWidth,lines}}}:
      Bool.pick(Unit -> IO(Result<&2,&2,Error,Rendered>),Nat.is_eq(width,cachedWidth),_ => IO.pure(Result<&2,&2,Error,Rendered>,Done{Rendered{image,terminal,lines}}),_ => detected(image,width,environment,Terminal.getCapabilities(terminal,environment,tmuxHyperlinks)))(Unit{})
    case _: detected(image,width,environment,Terminal.getCapabilities(terminal,environment,tmuxHyperlinks))
