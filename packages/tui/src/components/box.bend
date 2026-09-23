import Base
import ../component.bend as Component
import ../utils.bend as U
import ../tui.bend as T
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/string.bend as Strings

# Box is immutable state around the shared functional Container.  Callback
# handles are borrowed: Box never disposes the background callback.
type Cache is Data:
  Cache{childLines: List<&2,String>,width: Nat,bgSample: Maybe<&2,String>,lines: List<&2,String>}
type Box is Data:
  Box{container: Component.Container,paddingX: Nat,paddingY: Nat,bgFn: Maybe<&2,Callback.Callback<String,String>>,cache: Maybe<&2,Cache>}

def new(paddingX: Maybe<&2,Nat>,paddingY: Maybe<&2,Nat>,background: Maybe<&2,Callback.Callback<String,String>>) -> Box:
  Box{Component.new(),Maybe.default(&2,Nat,paddingX,1n),Maybe.default(&2,Nat,paddingY,1n),background,None{}}
def invalidate(state: Box) -> IO(Box):
  match state:
    case Box{+container,x,y,bg,_}:
      do IO<Box>:
        Component.invalidateContainer(container)
        return Box{container,x,y,bg,None{}}
def addChild(state: Box,child: Component.Component) -> Box:
  match state:
    case Box{container,x,y,bg,_}: Box{Component.addChild(container,child),x,y,bg,None{}}
def removeChild(state: Box,child: Component.ComponentId) -> Box:
  match state:
    case Box{container,x,y,bg,_}: Box{Component.removeChild(container,child),x,y,bg,None{}}
def clear(state: Box) -> Box:
  match state:
    case Box{container,x,y,bg,_}: Box{Component.clear(container),x,y,bg,None{}}
def setBgFn(state: Box,background: Maybe<&2,Callback.Callback<String,String>>) -> Box:
  match state:
    # Deliberately retain the render cache.  As in upstream, a sample made at
    # render time detects callbacks whose output has changed.
    case Box{container,x,y,_,cache}: Box{container,x,y,background,cache}

def prependMargin(lines: List<&2,String>,+margin: String,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: prependMargin(rest,margin,(margin ++ line) <> reversed)
def sameLines(left: List<&2,String>,right: List<&2,String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case left <> leftRest right <> rightRest: Strings.equal(left,right) && sameLines(leftRest,rightRest)
    case _ _: False{}

def background(+line: String,width: Nat,callback: Maybe<&2,Callback.Callback<String,String>>) -> IO(String):
  match callback:
    case None{}: IO.pure(String,U.padResult(line,U.visibleWidth(line),width,True{}))
    case Some{callback}: U.applyBackgroundToLine(line,width,callback)
def paintPadding(count: Nat,+width: Nat,+callback: Maybe<&2,Callback.Callback<String,String>>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{rest}:
      do IO<List<&2,String>>:
        line : String <- background("",width,callback)
        paintPadding(rest,width,callback,line <> reversed)
def paintContent(lines: List<&2,String>,+width: Nat,+callback: Maybe<&2,Callback.Callback<String,String>>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        painted : String <- background(line,width,callback)
        paintContent(rest,width,callback,painted <> reversed)
def bgSample(callback: Maybe<&2,Callback.Callback<String,String>>) -> IO(Maybe<&2,String>):
  match callback:
    case None{}: IO.pure(Maybe<&2,String>,None{})
    case Some{callback}:
      do IO<Maybe<&2,String>>:
        sample : String <- Callback.call(String,String,callback,"test")
        return Some{sample}
def sameSample(left: Maybe<&2,String>,right: Maybe<&2,String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{left} Some{right}: Strings.equal(left,right)
    case _ _: False{}
def cacheOf(+state: Box) -> Maybe<&2,Cache>:
  match state: case Box{_,_,_,_,cache}: cache
def cached(cache: Maybe<&2,Cache>,+width: Nat,+childLines: List<&2,String>,+sample: Maybe<&2,String>) -> Maybe<&2,List<&2,String>>:
  match cache:
    case Some{Cache{oldLines,cachedWidth,oldSample,lines}}:
      Bool.pick(Unit -> Maybe<&2,List<&2,String>>,Nat.is_eq(width,cachedWidth) && sameSample(oldSample,sample) && sameLines(oldLines,childLines),_ => Some{lines},_ => None{})(Unit{})
    case _: None{}
def rendered(state: Box,width: Nat,+childLines: List<&2,String>,+sample: Maybe<&2,String>,+lines: List<&2,String>) -> Box & List<&2,String>:
  match state:
    case Box{container,x,y,bg,_}: (Box{container,x,y,bg,Some{Cache{childLines,width,sample,lines}}},lines)
def stateContainer(state: Box) -> Component.Container:
  match state: case Box{container,_,_,_,_}: container
def replaceContainer(state: Box,container: Component.Container) -> Box:
  match state: case Box{_,x,y,bg,cache}: Box{container,x,y,bg,cache}
def paddingX(state: Box) -> Nat: match state: case Box{_,x,_,_,_}: x
def paddingY(state: Box) -> Nat: match state: case Box{_,_,y,_,_}: y
def backgroundFn(state: Box) -> Maybe<&2,Callback.Callback<String,String>>: match state: case Box{_,_,_,bg,_}: bg
def paddingDouble(state: Box) -> Nat: paddingX(state) * 2n

def finishCache(+state: Box,+width: Nat,+container: Component.Container,+childLines: List<&2,String>,+sample: Maybe<&2,String>,hit: Maybe<&2,List<&2,String>>) -> IO(Box & List<&2,String>):
  match hit:
    case Some{lines}: IO.pure(Box & List<&2,String>,(replaceContainer(state,container),lines))
    case None{}:
      do IO<Box & List<&2,String>>:
        top : List<&2,String> <- paintPadding(paddingY(state),width,backgroundFn(state),Nil{})
        body : List<&2,String> <- paintContent(childLines,width,backgroundFn(state),Nil{})
        bottom : List<&2,String> <- paintPadding(paddingY(state),width,backgroundFn(state),Nil{})
        lines : List<&2,String> <- IO.pure(List<&2,String>,List.append(&2,String,top,List.append(&2,String,body,bottom)))
        return rendered(replaceContainer(state,container),width,childLines,sample,lines)
def finishMeasured(+state: Box,+width: Nat,+container: Component.Container,+childLines: List<&2,String>,+sample: Maybe<&2,String>) -> IO(Box & List<&2,String>):
  +cache = cacheOf(state)
  +hit = cached(cache,width,childLines,sample)
  finishCache(state,width,container,childLines,sample,hit)
def renderMeasured(+state: Box,+width: Nat,measured: Component.Container & List<&2,String>) -> IO(Box & List<&2,String>):
  match measured:
    case Tuple{+container,rawLines}:
      +margin = U.spaces(paddingX(state),"")
      +bg = backgroundFn(state)
      +childLines = prependMargin(rawLines,margin,Nil{})
      Bool.pick(Unit -> IO(Box & List<&2,String>),List.is_empty(&2,String,childLines),
        _ => IO.pure(Box & List<&2,String>,(replaceContainer(state,container),Nil{})),
        _ => do IO<Box & List<&2,String>>:
          sample : Maybe<&2,String> <- bgSample(bg)
          finishMeasured(state,width,container,childLines,sample))(Unit{})
def renderNonempty(+state: Box,+width: Nat) -> IO(Box & List<&2,String>):
  do IO<Box & List<&2,String>>:
    measured : Component.Container & List<&2,String> <- Component.renderContainer(stateContainer(state),Nat.max(1n,width - paddingDouble(state)))
    renderMeasured(state,width,measured)
def render(state: Box,width: Nat) -> IO(Box & List<&2,String>):
  match state:
    case Box{Component.Container{Nil{},_},_,_,_,_}: IO.pure(Box & List<&2,String>,(state,Nil{}))
    case state: renderNonempty(state,width)

def nonnegative(value: T.Offset) -> Bool:
  match value:
    case T.Forward{_}: True{}
    case T.Backward{amount}: Nat.is_eq(amount,0n)
def insideX(value: T.Offset,width: Nat) -> Bool:
  match value:
    case T.Forward{amount}: Nat.is_lt(amount,width)
    case T.Backward{amount}: Nat.is_eq(amount,0n) && Nat.is_gt(width,0n)
def innerEvent(event: T.TuiMouseEvent,paddingX: Nat,paddingY: Nat,width: Nat) -> T.TuiMouseEvent:
  match event:
    case T.TuiMouseEvent{kind,button,x,y,sx,sy,_,height,shift,alt,ctrl,wheel,clicks}:
      T.TuiMouseEvent{kind,button,Component.subtract(x,T.Forward{paddingX}),Component.subtract(y,T.Forward{paddingY}),sx,sy,width,height,shift,alt,ctrl,wheel,clicks}
def routeInner(container: Component.Container,+inner: T.TuiMouseEvent,+contentWidth: Nat) -> IO(Maybe<&2,Component.TuiMouseDispatchResult>):
  match inner:
    case T.TuiMouseEvent{_,_,x,y,_,_,_,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(Maybe<&2,Component.TuiMouseDispatchResult>),nonnegative(y) && insideX(x,contentWidth),
        _ => do IO<Maybe<&2,Component.TuiMouseDispatchResult>>:
          children : List<&2,Component.ChildLayout> <- Component.mouseChildren(container,contentWidth)
          Component.routeMouse(children,inner,y,0n),
        _ => IO.pure(Maybe<&2,Component.TuiMouseDispatchResult>,None{}))(Unit{})
def eventWidth(event: T.TuiMouseEvent) -> Nat:
  match event: case T.TuiMouseEvent{_,_,_,_,_,_,width,_,_,_,_,_,_}: width
def handleMouse(state: Box,+event: T.TuiMouseEvent) -> IO(Maybe<&2,Component.TuiMouseDispatchResult>):
  match state:
    case Box{container,+x,+y,_,_}:
      +contentWidth = Nat.max(1n,eventWidth(event) - x * 2n)
      routeInner(container,innerEvent(event,x,y,contentWidth),contentWidth)
