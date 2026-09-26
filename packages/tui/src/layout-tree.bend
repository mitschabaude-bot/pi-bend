import Base
import ./layout-node.bend as N
import ./layout.bend as L
import ./component.bend as C
import ./utils.bend as U
import ./components/stack.bend as S
import ./components/scroll-view.bend as Scroll
import ../../runtime/src/callback.bend as Callback

type CachedLine is Data: CachedLine{component: C.ComponentId,width: Nat,lines: List<&2,String>}
type Rendered is Data: Rendered{lines: List<&2,String>,cache: List<&2,CachedLine>}
# A natural width is known, or the widest of the item's lines, measured only
# when a horizontal stack or an enclosing measure asks for it (upstream
# measures widths only there; a scroll view's content can be the whole
# transcript).
type Width is Data: Known{value: Nat} OfLines{}
type Item is Data:
  Item{node: N.LayoutNode,box: L.LayoutBox,lines: List<&2,String>,naturalWidth: Width,naturalHeight: Nat,size: Maybe<&2,S.StackEntryOptions>}
type Result is Data:
  Single{item: Item,cache: List<&2,CachedLine>}
  Group{entries: N.LayoutNode,items: List<&2,Item>,cache: List<&2,CachedLine>}
  Skipped{cache: List<&2,CachedLine>}
type Mode is Data:
  Measure{width: Nat,viewport: S.LayoutViewport}
  Place{x: Nat,y: Nat,width: Nat,height: Nat,clip: L.LayoutRect,viewport: S.LayoutViewport}
  PlaceV{x: Nat,y: Nat,width: Nat,sizes: List<&2,Nat>,gap: Nat,clip: L.LayoutRect,viewport: S.LayoutViewport}
  PlaceH{x: Nat,y: Nat,widths: List<&2,Nat>,height: Nat,gap: Nat,align: S.Align,clip: L.LayoutRect,viewport: S.LayoutViewport}
type TreeFrame is Data: TreeFrame{node: N.LayoutNode,frame: L.LayoutFrame}

def lookup(cache: List<&2,CachedLine>,+component: C.ComponentId,+width: Nat) -> Maybe<&2,List<&2,String>>:
  match cache:
    case Nil{}: None{}
    case CachedLine{identifier,cachedWidth,lines} <> rest:
      Bool.pick(Unit -> Maybe<&2,List<&2,String>>,C.same(identifier,component) && Nat.is_eq(width,cachedWidth),_ => Some{lines},_ => lookup(rest,component,width))(Unit{})
def renderedHit(cache: List<&2,CachedLine>,found: Maybe<&2,List<&2,String>>) -> Maybe<&2,Rendered>:
  match found:
    case None{}: None{}
    case Some{lines}: Some{Rendered{lines,cache}}
def renderedFresh(+component: C.Component,+width: Nat,cache: List<&2,CachedLine>) -> IO(Rendered):
  do IO<Rendered>:
    +lines : List<&2,String> <- C.render(component,width)
    return Rendered{lines,CachedLine{C.id(component),width,lines} <> cache}
def renderCachedHit(component: C.Component,width: Nat,cache: List<&2,CachedLine>,hit: Maybe<&2,Rendered>) -> IO(Rendered):
  match hit:
    case Some{result}: IO.pure(Rendered,result)
    case None{}: renderedFresh(component,width,cache)
def renderCached(+component: C.Component,+width: Nat,+cache: List<&2,CachedLine>) -> IO(Rendered):
  renderCachedHit(component,width,cache,renderedHit(cache,lookup(cache,C.id(component),width)))
def resultCache(value: Result) -> List<&2,CachedLine>:
  match value:
    case Single{_,cache}: cache
    case Group{_,_,cache}: cache
    case Skipped{cache}: cache
def resultItem(value: Result) -> Maybe<&2,Item>:
  match value:
    case Single{item,_}: Some{item}
    case _: None{}
def resultEntries(value: Result) -> N.LayoutNode:
  match value:
    case Group{entries,_,_}: entries
    case _: N.Empty{}
def resultItems(value: Result) -> List<&2,Item>:
  match value:
    case Group{_,items,_}: items
    case _: Nil{}
def itemNode(value: Item) -> N.LayoutNode:
  match value: case Item{node,_,_,_,_,_}: node
def itemWidth(value: Item) -> Nat:
  match value:
    case Item{_,_,_,Known{width},_,_}: width
    case Item{_,_,lines,OfLines{},_,_}: L.lineWidth(lines)
def itemHeight(value: Item) -> Nat:
  match value: case Item{_,_,_,_,height,_}: height
def itemSize(value: Item) -> S.StackEntryOptions:
  match value: case Item{_,_,_,_,_,Some{size}}: size case _: S.defaultSize()
def naturalWidths(items: List<&2,Item>) -> List<&2,Nat>:
  match items: case Nil{}: Nil{} case item <> rest: itemWidth(item) <> naturalWidths(rest)
def naturalHeights(items: List<&2,Item>) -> List<&2,Nat>:
  match items: case Nil{}: Nil{} case item <> rest: itemHeight(item) <> naturalHeights(rest)
def options(items: List<&2,Item>) -> List<&2,S.StackEntryOptions>:
  match items: case Nil{}: Nil{} case item <> rest: itemSize(item) <> options(rest)
def total(values: List<&2,Nat>) -> Nat:
  match values: case Nil{}: 0n case value <> rest: value + total(rest)
def maxValue(values: List<&2,Nat>) -> Nat:
  match values: case Nil{}: 0n case value <> rest: Nat.max(value,maxValue(rest))
def gapTotal(items: List<&2,Item>,gap: Nat) -> Nat:
  (List.length(&2,Item,items) - 1n) * gap
def boxOf(item: Item) -> L.LayoutBox:
  match item: case Item{_,box,_,_,_,_}: box
def boxes(items: List<&2,Item>) -> List<&2,L.LayoutBox>:
  match items: case Nil{}: Nil{} case item <> rest: boxOf(item) <> boxes(rest)
def painted(items: List<&2,Item>,rows: List<&2,String>,+parentX: Nat,+parentY: Nat,+width: Nat) -> List<&2,String>:
  match items:
    case Nil{}: rows
    case Item{_,L.LayoutBox{_,L.LayoutRect{x,y,childWidth,childHeight},_,_,_,_,_},lines,_,_,_} <> rest:
      painted(rest,L.paint(rows,lines,y - parentY,x - parentX,childWidth,childHeight,width),parentX,parentY,width)
def verticalPaint(items: List<&2,Item>,+parentY: Nat,+used: Nat,+height: Nat,+width: Nat) -> List<&2,String>:
  match items:
    case Nil{}: L.blank(height - used,Nil{})
    case Item{_,L.LayoutBox{_,L.LayoutRect{_,y,childWidth,childHeight},_,_,_,_,_},lines,_,_,_} <> rest:
      +top = Nat.min(height,y - parentY)
      +space = L.blank(top - used,Nil{})
      +visible = Nat.min(childHeight,height - top)
      +child = L.paint(L.blank(visible,Nil{}),lines,0n,0n,childWidth,visible,width)
      List.append(&2,String,space,List.append(&2,String,child,verticalPaint(rest,parentY,top + visible,height,width)))
def one(node: N.LayoutNode,box: L.LayoutBox,lines: List<&2,String>,naturalWidth: Nat,naturalHeight: Nat,cache: List<&2,CachedLine>) -> Result:
  Single{Item{node,box,lines,Known{naturalWidth},naturalHeight,None{}},cache}
def placeholder(node: N.LayoutNode,+width: Nat,+height: Nat,lines: List<&2,String>,cache: List<&2,CachedLine>) -> Result:
  +bounds = L.rect(0n,0n,width,height)
  one(node,L.LayoutBox{None{},bounds,bounds,Nil{},None{},0n,0n},lines,width,height,cache)
def leafBox(component: C.Component,lines: List<&2,String>,+bounds: L.LayoutRect,clip: L.LayoutRect) -> L.LayoutBox:
  L.LayoutBox{Some{C.id(component)},bounds,L.intersect(clip,bounds),Nil{},Some{lines},0n,0n}
def leafResult(+component: C.Component,+lines: List<&2,String>,cache: List<&2,CachedLine>,x: Nat,y: Nat,width: Nat,height: Nat,clip: L.LayoutRect) -> Result:
  +bounds = L.rect(x,y,width,height)
  +box = leafBox(component,lines,bounds,clip)
  one(N.Leaf{component},box,lines,L.lineWidth(lines),List.length(&2,String,lines),cache)
def wrapEntry(result: Result,+size: S.StackEntryOptions,visible: Maybe<&2,Callback.Callback<S.LayoutViewport,Bool>>) -> Result:
  match result:
    case Single{Item{node,box,lines,width,height,_},cache}:
      Single{Item{N.Entry{node,size,visible},box,lines,width,height,Some{size}},cache}
    case Skipped{cache}: Skipped{cache}
    case Group{entries,items,cache}: Group{entries,items,cache}
def fixedEntry(node: N.LayoutNode,+size: S.StackEntryOptions,visible: Maybe<&2,Callback.Callback<S.LayoutViewport,Bool>>,+basis: Nat,cache: List<&2,CachedLine>) -> Result:
  +bounds = L.rect(0n,0n,basis,basis)
  Single{Item{N.Entry{node,size,visible},L.LayoutBox{None{},bounds,bounds,Nil{},None{},0n,0n},Nil{},Known{basis},basis,Some{size}},cache}
def visible(predicate: Maybe<&2,Callback.Callback<S.LayoutViewport,Bool>>,viewport: S.LayoutViewport) -> IO(Bool):
  match predicate:
    case None{}: IO.pure(Bool,True{})
    case Some{callback}: Callback.call(S.LayoutViewport,Bool,callback,viewport)
def combine(first: Result,tail: Result) -> Result:
  match first tail:
    case Single{+item,_} Group{rest,items,cache}:
      Group{N.Children{itemNode(item),rest},item <> items,cache}
    case Skipped{_} Group{rest,items,cache}: Group{rest,items,cache}
    case _ _: Group{N.Empty{},Nil{},resultCache(tail)}
def stackMeasure(axis: S.Axis,entries: N.LayoutNode,+items: List<&2,Item>,+gap: Nat,align: S.Align,width: Nat,cache: List<&2,CachedLine>) -> Result:
  match axis:
    case S.Vertical{}:
      +sizes = S.allocateStackSizes(options(items),naturalHeights(items),None{},gap)
      placeholder(N.VStack{entries,gap},maxValue(naturalWidths(items)),total(sizes) + gapTotal(items,gap),Nil{},cache)
    case S.Horizontal{}:
      +sizes = S.allocateStackSizes(options(items),naturalWidths(items),Some{width},gap)
      placeholder(N.HStack{entries,gap,align},total(sizes) + gapTotal(items,gap),maxValue(naturalHeights(items)),Nil{},cache)
def stackNode(axis: S.Axis,entries: N.LayoutNode,gap: Nat,align: S.Align) -> N.LayoutNode:
  match axis:
    case S.Vertical{}: N.VStack{entries,gap}
    case S.Horizontal{}: N.HStack{entries,gap,align}
def stackScreen(axis: S.Axis,items: List<&2,Item>,x: Nat,y: Nat,width: Nat,height: Nat) -> List<&2,String>:
  match axis:
    case S.Vertical{}: verticalPaint(items,y,0n,height,width)
    case S.Horizontal{}: painted(items,L.blank(height,Nil{}),x,y,width)
def stackPlaced(+axis: S.Axis,entries: N.LayoutNode,+items: List<&2,Item>,+gap: Nat,align: S.Align,+x: Nat,+y: Nat,+width: Nat,+height: Nat,clip: L.LayoutRect,cache: List<&2,CachedLine>) -> Result:
  +bounds = L.rect(x,y,width,height)
  +screen = stackScreen(axis,items,x,y,width,height)
  +node = stackNode(axis,entries,gap,align)
  one(node,L.LayoutBox{None{},bounds,L.intersect(clip,bounds),boxes(items),None{},0n,0n},screen,width,height,cache)
def shiftScrollChild(children: List<&2,L.LayoutBox>,x: Nat,y: Nat,clip: L.LayoutRect) -> List<&2,L.LayoutBox>:
  match children:
    case Nil{}: Nil{}
    case L.LayoutBox{component,L.LayoutRect{_,_,width,height},_,_,lines,offset,layer} <> rest:
      +bounds = L.rect(x,y,width,height)
      L.LayoutBox{component,bounds,L.intersect(clip,bounds),Nil{},lines,offset,layer} <> Nil{}
def shiftedScroll(view: Scroll.ScrollView,frame: L.LayoutFrame,+x: Nat,+y: Nat,+clip: L.LayoutRect) -> L.LayoutBox:
  match frame:
    case L.LayoutFrame{L.LayoutBox{_,_,_,children,_,_,_},width,height,_}:
      +bounds = L.rect(x,y,width,height)
      +inner = shiftScrollChild(children,x,y,L.intersect(clip,bounds))
      L.LayoutBox{None{},bounds,L.intersect(clip,bounds),inner,None{},0n,0n}
def measuredLeaf(component: C.Component,rendered: Rendered,+width: Nat) -> Result:
  match rendered:
    case Rendered{+lines,cache}:
      leafResult(component,lines,cache,0n,0n,width,List.length(&2,String,lines),L.rect(0n,0n,width,List.length(&2,String,lines)))
def placedLeaf(+component: C.Component,rendered: Rendered,x: Nat,y: Nat,+width: Nat,+height: Nat,clip: L.LayoutRect) -> Result:
  match rendered:
    case Rendered{+lines,cache}:
      +bounds = L.rect(x,y,width,height)
      one(N.Leaf{component},leafBox(component,lines,bounds,clip),lines,width,height,cache)
def measuredScroll(view: Scroll.ScrollView,rendered: Rendered,width: Nat) -> Result:
  match rendered:
    case Rendered{+lines,cache}:
      +height = List.length(&2,String,lines)
      +bounds = L.rect(0n,0n,0n,height)
      Single{Item{N.ScrollNode{view},L.LayoutBox{None{},bounds,bounds,Nil{},None{},0n,0n},lines,OfLines{},height,None{}},cache}
def placedScrollFrame(value: L.ScrollLayoutFrame,cache: List<&2,CachedLine>,x: Nat,y: Nat,clip: L.LayoutRect,naturalHeight: Nat) -> Result:
  match value:
    case L.ScrollLayoutFrame{+next,L.LayoutFrame{box,width,height,+screen}}:
      one(N.ScrollNode{next},shiftedScroll(next,L.LayoutFrame{box,width,height,screen},x,y,clip),screen,L.lineWidth(screen),naturalHeight,cache)
def placedScroll(view: Scroll.ScrollView,rendered: Rendered,x: Nat,y: Nat,width: Nat,height: Nat,contentWidth: Nat,clip: L.LayoutRect) -> Result:
  match rendered:
    case Rendered{+lines,cache}:
      placedScrollFrame(L.scrollFrame(view,lines,width,height,contentWidth),cache,x,y,clip,List.length(&2,String,lines))
def maybeHeight(item: Maybe<&2,Item>) -> Nat:
  match item:
    case None{}: 0n
    case Some{value}: itemHeight(value)
@unsafe def run(node: N.LayoutNode,mode: Mode,+cache: List<&2,CachedLine>) -> IO(Result):
  match node mode:
    case N.Inline{child} mode: run(child,mode,cache)
    case N.Leaf{+component} Measure{+width,_}:
      do IO<Result>:
        rendered : Rendered <- renderCached(component,width,cache)
        return measuredLeaf(component,rendered,width)
    case N.Leaf{+component} Place{x,y,+width,height,clip,_}:
      do IO<Result>:
        rendered : Rendered <- renderCached(component,width,cache)
        return placedLeaf(component,rendered,x,y,width,height,clip)
    case N.ScrollNode{+view} Measure{+width,_}:
      do IO<Result>:
        +contentWidth : Nat <- IO.pure(Nat,Scroll.getContentWidth(view,width))
        rendered : Rendered <- renderCached(L.viewChild(view),contentWidth,cache)
        return measuredScroll(view,rendered,width)
    case N.ScrollNode{+view} Place{x,y,+width,height,clip,_}:
      do IO<Result>:
        +contentWidth : Nat <- IO.pure(Nat,Scroll.getContentWidth(view,width))
        rendered : Rendered <- renderCached(L.viewChild(view),contentWidth,cache)
        return placedScroll(view,rendered,x,y,width,height,contentWidth,clip)
    case N.Spacer{+lines} Measure{_,_}: IO.pure(Result,placeholder(N.Spacer{lines},0n,lines,Nil{},cache))
    case N.Spacer{lines} Place{x,y,width,+height,clip,_}:
      +bounds = L.rect(x,y,width,height)
      IO.pure(Result,one(N.Spacer{lines},L.LayoutBox{None{},bounds,L.intersect(clip,bounds),Nil{},None{},0n,0n},L.blank(height,Nil{}),0n,height,cache))
    case N.Empty{} Measure{_,_}: IO.pure(Result,Group{N.Empty{},Nil{},cache})
    case N.Empty{} PlaceV{_,_,_,_,_,_,_}: IO.pure(Result,Group{N.Empty{},Nil{},cache})
    case N.Empty{} PlaceH{_,_,_,_,_,_,_,_}: IO.pure(Result,Group{N.Empty{},Nil{},cache})
    case N.Children{first,rest} Measure{+width,+viewport}:
      do IO<Result>:
        +head : Result <- run(first,Measure{width,viewport},cache)
        tail : Result <- run(rest,Measure{width,viewport},resultCache(head))
        return combine(head,tail)
    case N.Children{first,rest} PlaceV{+x,+y,+width,+size <> more,+gap,+clip,+viewport}:
      do IO<Result>:
        +head : Result <- run(first,Place{x,y,width,size,clip,viewport},cache)
        tail : Result <- run(rest,PlaceV{x,y + size + gap,width,more,gap,clip,viewport},resultCache(head))
        return combine(head,tail)
    case N.Children{first,rest} PlaceV{x,y,width,Nil{},gap,clip,viewport}:
      IO.pure(Result,Group{N.Empty{},Nil{},cache})
    case N.Children{+first,rest} PlaceH{+x,+y,+width <> more,+height,+gap,+align,+clip,+viewport}:
      do IO<Result>:
        +measured : Result <- run(first,Measure{Nat.max(1n,width),viewport},cache)
        +natural : Nat <- IO.pure(Nat,maybeHeight(resultItem(measured)))
        +childHeight : Nat <- IO.pure(Nat,L.childHeight(align,height,natural))
        +childY : Nat <- IO.pure(Nat,y + L.aligned(align,height,childHeight))
        +head : Result <- run(first,Place{x,childY,width,childHeight,clip,viewport},resultCache(measured))
        tail : Result <- run(rest,PlaceH{x + width + gap,y,more,height,gap,align,clip,viewport},resultCache(head))
        return combine(head,tail)
    case N.Children{first,rest} PlaceH{x,y,Nil{},height,gap,align,clip,viewport}:
      IO.pure(Result,Group{N.Empty{},Nil{},cache})
    case N.Entry{child,S.StackEntryOptions{Some{+basis},grow,shrink,minimum,maximum},+condition} Measure{width,viewport}:
      do IO<Result>:
        shown : Bool <- visible(condition,viewport)
        return Bool.pick(Result,shown,fixedEntry(child,S.StackEntryOptions{Some{basis},grow,shrink,minimum,maximum},condition,basis,cache),Skipped{cache})
    case N.Entry{+child,S.StackEntryOptions{None{},grow,shrink,minimum,maximum},+condition} Measure{width,+viewport}:
      do IO<Result>:
        shown : Bool <- visible(condition,viewport)
        Bool.pick(Unit -> IO(Result),shown,
          _ => do IO<Result>:
            result : Result <- run(child,Measure{width,viewport},cache)
            return wrapEntry(result,S.StackEntryOptions{None{},grow,shrink,minimum,maximum},condition),
          _ => IO.pure(Result,Skipped{cache}))(Unit{})
    case N.Entry{child,size,condition} Place{x,y,width,height,clip,viewport}:
      do IO<Result>:
        result : Result <- run(child,Place{x,y,width,height,clip,viewport},cache)
        return wrapEntry(result,size,condition)
    case N.VStack{entries,gap} Measure{+width,viewport}:
      do IO<Result>:
        +result : Result <- run(entries,Measure{width,viewport},cache)
        return stackMeasure(S.Vertical{},resultEntries(result),resultItems(result),gap,S.Stretch{},width,resultCache(result))
    case N.HStack{entries,gap,align} Measure{+width,viewport}:
      do IO<Result>:
        +result : Result <- run(entries,Measure{width,viewport},cache)
        return stackMeasure(S.Horizontal{},resultEntries(result),resultItems(result),gap,align,width,resultCache(result))
    case N.VStack{entries,+gap} Place{+x,+y,+width,+height,+clip,+viewport}:
      do IO<Result>:
        +measured : Result <- run(entries,Measure{width,viewport},cache)
        +items : List<&2,Item> <- IO.pure(List<&2,Item>,resultItems(measured))
        +allocated : List<&2,Nat> <- IO.pure(List<&2,Nat>,S.allocateStackSizes(options(items),naturalHeights(items),Some{height},gap))
        +placed : Result <- run(resultEntries(measured),PlaceV{x,y,width,allocated,gap,clip,viewport},resultCache(measured))
        return stackPlaced(S.Vertical{},resultEntries(placed),resultItems(placed),gap,S.Stretch{},x,y,width,height,clip,resultCache(placed))
    case N.HStack{entries,+gap,+align} Place{+x,+y,+width,+height,+clip,+viewport}:
      do IO<Result>:
        +measured : Result <- run(entries,Measure{width,viewport},cache)
        +items : List<&2,Item> <- IO.pure(List<&2,Item>,resultItems(measured))
        +allocated : List<&2,Nat> <- IO.pure(List<&2,Nat>,S.allocateStackSizes(options(items),naturalWidths(items),Some{width},gap))
        +placed : Result <- run(resultEntries(measured),PlaceH{x,y,allocated,height,gap,align,clip,viewport},resultCache(measured))
        return stackPlaced(S.Horizontal{},resultEntries(placed),resultItems(placed),gap,align,x,y,width,height,clip,resultCache(placed))
    case _ _: IO.pure(Result,Skipped{cache})

def treeFrame(result: Result,+width: Nat,+height: Nat) -> TreeFrame:
  match result:
    case Single{Item{node,box,lines,_,_,_},_}:
      TreeFrame{node,L.LayoutFrame{box,width,height,L.paint(L.blank(height,Nil{}),lines,0n,0n,width,height,width)}}
    case _: TreeFrame{N.Empty{},L.LayoutFrame{L.LayoutBox{None{},L.rect(0n,0n,width,height),L.rect(0n,0n,width,height),Nil{},None{},0n,0n},width,height,L.blank(height,Nil{})}}
def viewport(width: Nat,height: Nat) -> S.LayoutViewport: S.LayoutViewport{width,height}
def wrappedFrame(value: TreeFrame) -> TreeFrame:
  match value:
    case TreeFrame{node,frame}: TreeFrame{N.Inline{node},frame}
def inlineFrame(result: Result,width: Nat,height: Nat) -> TreeFrame:
  match result:
    # A placed stack already contains its complete screen; repainting it
    # over another blank screen repeats every column's ANSI composition.
    case Single{Item{N.VStack{entries,gap},box,lines,_,_,_},_}:
      TreeFrame{N.Inline{N.VStack{entries,gap}},L.LayoutFrame{box,width,height,lines}}
    case result: wrappedFrame(treeFrame(result,width,height))
# Regular mode is an unbounded document: the main-screen renderer scrolls
# overflow into terminal history. Only fullscreen allocates viewport height.
def renderInline(node: N.LayoutNode,width: Nat,height: Nat) -> IO(TreeFrame):
  match node:
    case N.VStack{entries,+gap}:
      +safeWidth = Nat.max(1n,width)
      +safeHeight = Nat.max(1n,height)
      +view = viewport(safeWidth,safeHeight)
      do IO<TreeFrame>:
        +measured : Result <- run(entries,Measure{safeWidth,view},Nil{})
        +items : List<&2,Item> <- IO.pure(List<&2,Item>,resultItems(measured))
        +natural : List<&2,Nat> <- IO.pure(List<&2,Nat>,S.allocateStackSizes(options(items),naturalHeights(items),None{},gap))
        +contentHeight : Nat <- IO.pure(Nat,Nat.max(1n,total(natural) + gapTotal(items,gap)))
        +placed : Result <- run(resultEntries(measured),PlaceV{0n,0n,safeWidth,natural,gap,L.rect(0n,0n,safeWidth,contentHeight),view},resultCache(measured))
        return inlineFrame(stackPlaced(S.Vertical{},resultEntries(placed),resultItems(placed),gap,S.Stretch{},0n,0n,safeWidth,contentHeight,L.rect(0n,0n,safeWidth,contentHeight),resultCache(placed)),safeWidth,contentHeight)
    case +node:
      +safeWidth = Nat.max(1n,width)
      +safeHeight = Nat.max(1n,height)
      +view = viewport(safeWidth,safeHeight)
      do IO<TreeFrame>:
        +measured : Result <- run(node,Measure{safeWidth,view},Nil{})
        +contentHeight : Nat <- IO.pure(Nat,Nat.max(1n,maybeHeight(resultItem(measured))))
        result : Result <- run(node,Place{0n,0n,safeWidth,contentHeight,L.rect(0n,0n,safeWidth,contentHeight),view},resultCache(measured))
        return inlineFrame(result,safeWidth,contentHeight)
def renderTreeFrame(node: N.LayoutNode,width: Nat,height: Nat) -> IO(TreeFrame):
  match node:
    case N.Inline{child}: renderInline(child,width,height)
    case node:
      +safeWidth = Nat.max(1n,width)
      +safeHeight = Nat.max(1n,height)
      +viewport = viewport(safeWidth,safeHeight)
      do IO<TreeFrame>:
        result : Result <- run(node,Place{0n,0n,safeWidth,safeHeight,L.rect(0n,0n,safeWidth,safeHeight),viewport},Nil{})
        return treeFrame(result,safeWidth,safeHeight)
