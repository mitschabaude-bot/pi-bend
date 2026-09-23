import Base
import ./component.bend as C
import ./tui.bend as T
import ./utils.bend as U
import ./components/stack.bend as S

type LayoutRect is Data: LayoutRect{x: Nat,y: Nat,width: Nat,height: Nat}
type LayoutBox is Data:
  LayoutBox{component: Maybe<&2,C.ComponentId>,rect: LayoutRect,clip: LayoutRect,children: List<&2,LayoutBox>,lines: Maybe<&2,List<&2,String>>,lineOffset: Nat,layer: Nat}
type LayoutFrame is Data: LayoutFrame{root: LayoutBox,width: Nat,height: Nat,lines: List<&2,String>}
type Measured is Data: Measured{entry: S.StackEntry,lines: List<&2,String>,width: Nat,height: Nat}
type Placed is Data: Placed{boxes: List<&2,LayoutBox>,lines: List<&2,String>}

def rect(x: Nat,y: Nat,width: Nat,height: Nat) -> LayoutRect: LayoutRect{x,y,width,height}
def intersect(a: LayoutRect,b: LayoutRect) -> LayoutRect:
  match a b:
    case LayoutRect{+ax,+ay,aw,ah} LayoutRect{+bx,+by,bw,bh}:
      +x = Nat.max(ax,bx)
      +y = Nat.max(ay,by)
      LayoutRect{x,y,Nat.min(ax + aw,bx + bw) - x,Nat.min(ay + ah,by + bh) - y}
def within(rect: LayoutRect,+x: Nat,+y: Nat) -> Bool:
  match rect:
    case LayoutRect{+left,+top,width,height}: Nat.is_le(left,x) && Nat.is_lt(x,left + width) && Nat.is_le(top,y) && Nat.is_lt(y,top + height)
def blank(count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}: blank(rest,"" <> reversed)
def lineWidth(lines: List<&2,String>) -> Nat:
  match lines:
    case Nil{}: 0n
    case line <> rest: Nat.max(U.visibleWidth(line),lineWidth(rest))
def measureEntry(entry: S.StackEntry,width: Nat,axis: S.Axis) -> IO(Measured):
  match entry:
    case S.StackEntry{+component,size,visible}:
      match size axis:
        case S.StackEntryOptions{Some{+basis},grow,shrink,minimum,maximum} S.Horizontal{}:
          IO.pure(Measured,Measured{S.StackEntry{component,S.StackEntryOptions{Some{basis},grow,shrink,minimum,maximum},visible},Nil{},basis,0n})
        case size _:
          do IO<Measured>:
            +lines : List<&2,String> <- C.render(component,width)
            return Measured{S.StackEntry{component,size,visible},lines,lineWidth(lines),List.length(&2,String,lines)}
def measure(entries: List<&2,S.StackEntry>,+width: Nat,+axis: S.Axis,reversed: List<&2,Measured>) -> IO(List<&2,Measured>):
  match entries:
    case Nil{}: IO.pure(List<&2,Measured>,List.reverse(&2,Measured,reversed))
    case entry <> rest:
      do IO<List<&2,Measured>>:
        measured : Measured <- measureEntry(entry,width,axis)
        measure(rest,width,axis,measured <> reversed)
def sizes(measured: List<&2,Measured>,+vertical: Bool) -> List<&2,Nat>:
  match measured:
    case Nil{}: Nil{}
    case Measured{_,_,width,height} <> rest: Bool.pick(Nat,vertical,height,width) <> sizes(rest,vertical)
def source(lines: List<&2,String>,row: Nat) -> Maybe<&2,String>:
  match lines row:
    case Nil{} _: None{}
    case line <> rest Zero{}: Some{line}
    case line <> rest Succ{before}: source(rest,before)
def composite(row: String,line: Maybe<&2,String>,x: Nat,width: Nat,totalWidth: Nat) -> String:
  match line:
    case None{}: row
    case Some{text}: T.compositeTuiLine(row,text,x,width,totalWidth)
def paint(rows: List<&2,String>,+sourceLines: List<&2,String>,+index: Nat,+x: Nat,+y: Nat,+width: Nat,+height: Nat,+totalWidth: Nat) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +painted = Bool.pick(Unit -> String,Nat.is_le(y,index) && Nat.is_lt(index,y + height),_ => composite(row,source(sourceLines,index - y),x,width,totalWidth),_ => row)(Unit{})
      painted <> paint(rest,sourceLines,index + 1n,x,y,width,height,totalWidth)
def vertical(measured: List<&2,Measured>,allocated: List<&2,Nat>,+y: Nat,+gap: Nat,+outer: LayoutRect,screen: List<&2,String>,reversed: List<&2,LayoutBox>) -> Placed:
  match measured allocated:
    case Nil{} _: Placed{List.reverse(&2,LayoutBox,reversed),screen}
    case Measured{S.StackEntry{+component,_,_},+lines,_,_} <> rest +height <> more:
      match outer:
        case LayoutRect{+x,_,+width,_}:
          +bounds = rect(x,y,width,height)
          +clip = intersect(outer,bounds)
          +updated = paint(screen,lines,0n,x,y,width,height,width)
          vertical(rest,more,y + height + gap,gap,outer,updated,LayoutBox{Some{C.id(component)},bounds,clip,Nil{},Some{lines},0n,0n} <> reversed)
    case _ _: Placed{List.reverse(&2,LayoutBox,reversed),screen}
def aligned(align: S.Align,outer: Nat,inner: Nat) -> Nat:
  match align:
    case S.Center{}: (outer - inner) / 2n
    case S.End{}: outer - inner
    case _: 0n
def childHeight(align: S.Align,outer: Nat,natural: Nat) -> Nat:
  match align:
    case S.Stretch{}: outer
    case _: Nat.min(outer,natural)
def horizontal(measured: List<&2,Measured>,allocated: List<&2,Nat>,+x: Nat,+gap: Nat,+align: S.Align,+outer: LayoutRect,screen: List<&2,String>,reversed: List<&2,LayoutBox>) -> IO(Placed):
  match measured allocated:
    case Nil{} _: IO.pure(Placed,Placed{List.reverse(&2,LayoutBox,reversed),screen})
    case Measured{S.StackEntry{+component,_,_},_,_,_} <> rest +width <> more:
      match outer:
        case LayoutRect{_,+top,+totalWidth,+totalHeight}:
          do IO<Placed>:
            +lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),Nat.is_eq(width,0n),_ => IO.pure(List<&2,String>,Nil{}),_ => C.render(component,width))(Unit{})
            +height : Nat <- IO.pure(Nat,childHeight(align,totalHeight,List.length(&2,String,lines)))
            +y : Nat <- IO.pure(Nat,top + aligned(align,totalHeight,height))
            +bounds : LayoutRect <- IO.pure(LayoutRect,rect(x,y,width,height))
            +clip : LayoutRect <- IO.pure(LayoutRect,intersect(outer,bounds))
            +updated : List<&2,String> <- IO.pure(List<&2,String>,paint(screen,lines,0n,x,y,width,height,totalWidth))
            horizontal(rest,more,x + width + gap,gap,align,outer,updated,LayoutBox{Some{C.id(component)},bounds,clip,Nil{},Some{lines},0n,0n} <> reversed)
    case _ _: IO.pure(Placed,Placed{List.reverse(&2,LayoutBox,reversed),screen})
def finish(+root: LayoutRect,result: Placed) -> LayoutFrame:
  match root result:
    case LayoutRect{_,_,width,height} Placed{children,lines}:
      LayoutFrame{LayoutBox{None{},root,root,children,None{},0n,0n},width,height,lines}
def renderMeasured(axis: S.Axis,+entries: List<&2,S.StackEntry>,+measured: List<&2,Measured>,+width: Nat,+height: Nat,+gap: Nat,align: S.Align,+root: LayoutRect) -> IO(LayoutFrame):
  match axis:
    case S.Vertical{}:
      +allocated = S.allocateStackSizes(S.sizeOptions(entries),sizes(measured,True{}),Some{height},gap)
      IO.pure(LayoutFrame,finish(root,vertical(measured,allocated,0n,gap,root,blank(height,Nil{}),Nil{})))
    case S.Horizontal{}:
      do IO<LayoutFrame>:
        +allocated : List<&2,Nat> <- IO.pure(List<&2,Nat>,S.allocateStackSizes(S.sizeOptions(entries),sizes(measured,False{}),Some{width},gap))
        placed : Placed <- horizontal(measured,allocated,0n,gap,align,root,blank(height,Nil{}),Nil{})
        return finish(root,placed)
def renderVisible(stack: S.Stack,+width: Nat,+height: Nat,+entries: List<&2,S.StackEntry>) -> IO(LayoutFrame):
  match stack:
    case S.Stack{_,gap,align,+axis}:
      do IO<LayoutFrame>:
        measured : List<&2,Measured> <- measure(entries,width,axis,Nil{})
        renderMeasured(axis,entries,measured,width,height,gap,align,rect(0n,0n,width,height))
def renderLayoutFrame(+stack: S.Stack,width: Nat,height: Nat) -> IO(LayoutFrame):
  match stack:
    case S.Stack{+entries,_,_,_}:
      do IO<LayoutFrame>:
        +safeWidth : Nat <- IO.pure(Nat,Nat.max(1n,width))
        +safeHeight : Nat <- IO.pure(Nat,Nat.max(1n,height))
        visible : List<&2,S.StackEntry> <- S.visibleStackEntries(entries,S.LayoutViewport{safeWidth,safeHeight})
        renderVisible(stack,safeWidth,safeHeight,visible)
def childHits(children: List<&2,LayoutBox>,+x: Nat,+y: Nat) -> List<&2,LayoutBox>:
  match children:
    case Nil{}: Nil{}
    case LayoutBox{component,bounds,+clip,children,lines,offset,layer} <> +rest:
      Bool.pick(Unit -> List<&2,LayoutBox>,within(clip,x,y),_ => LayoutBox{component,bounds,clip,children,lines,offset,layer} <> childHits(rest,x,y),_ => childHits(rest,x,y))(Unit{})
def boxesAt(box: LayoutBox,+x: Nat,+y: Nat) -> List<&2,LayoutBox>:
  match box:
    case LayoutBox{component,bounds,+clip,+children,lines,offset,layer}:
      Bool.pick(Unit -> List<&2,LayoutBox>,within(clip,x,y),_ => List.append(&2,LayoutBox,childHits(children,x,y),LayoutBox{component,bounds,clip,children,lines,offset,layer} <> Nil{}),_ => Nil{})(Unit{})
def getLayoutBoxesAt(frame: LayoutFrame,x: Nat,y: Nat) -> List<&2,LayoutBox>:
  match frame: case LayoutFrame{root,_,_,_}: boxesAt(root,x,y)
