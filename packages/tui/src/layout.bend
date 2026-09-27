import Base
import ../../runtime/src/stable-sort.bend as Sort
import ./component.bend as C
import ./tui.bend as T
import ./terminal-image.bend as Image
import ./utils.bend as U
import ./components/stack.bend as S
import ./components/scroll-view.bend as Scroll

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
# upstream paintBox: a full-width box painting onto an untouched row (or an
# image line) uses the source line itself. Rows are written with erase-line and
# the final width clamp still truncates over-wide lines, so no padding or
# grapheme segmentation is needed.
def untouchedOrImage(row: String,+line: String) -> Bool:
  match row:
    case SNil{}: True{}
    case _: Image.isImageLine(line)
def compositeWhen(direct: Bool,row: String,line: String,x: Nat,width: Nat,totalWidth: Nat) -> String:
  match direct:
    case True{}: line
    case False{}: T.compositeTuiLine(row,line,x,width,totalWidth)
# upstream OSC133_ZONE_PREFIX: leading semantic-prompt zone marks
# (ESC ] 133 ; A|B|C, ended by BEL or ESC \) are removed before painting.
def zoneKind(kind: Char) -> Bool:
  match kind:
    case 'A': True{}
    case 'B': True{}
    case 'C': True{}
    case _: False{}
def zonePrefixLength(line: String) -> Nat:
  match line:
    case SCon{Chr{27},SCon{']',SCon{'1',SCon{'3',SCon{'3',SCon{';',SCon{kind,SCon{Chr{7},_}}}}}}}}: Bool.pick(Nat,zoneKind(kind),8n,0n)
    case SCon{Chr{27},SCon{']',SCon{'1',SCon{'3',SCon{'3',SCon{';',SCon{kind,SCon{Chr{27},SCon{'\\',_}}}}}}}}}: Bool.pick(Nat,zoneKind(kind),9n,0n)
    case _: 0n
@unsafe
def withoutZonesFrom(line: String,length: Nat) -> String:
  match length:
    case Zero{}: line
    case Succ{count}:
      +rest = String.drop(line,Succ{count})
      withoutZonesFrom(rest,zonePrefixLength(rest))
def withoutZones(+line: String) -> String: withoutZonesFrom(line,zonePrefixLength(line))
def composite(+row: String,line: Maybe<&2,String>,+x: Nat,+width: Nat,+totalWidth: Nat) -> String:
  match line:
    case None{}: row
    case Some{source}:
      +text = withoutZones(source)
      compositeWhen(Nat.is_eq(x,0n) && Nat.is_ge(width,totalWidth) && untouchedOrImage(row,text),row,text,x,width,totalWidth)
def paintLines(rows: List<&2,String>,sourceLines: List<&2,String>,height: Nat,+x: Nat,+width: Nat,+totalWidth: Nat) -> List<&2,String>:
  match rows sourceLines height:
    case row <> rest line <> more Succ{left}:
      composite(row,Some{line},x,width,totalWidth) <> paintLines(rest,more,left,x,width,totalWidth)
    case _ _ _: rows
def paint(rows: List<&2,String>,sourceLines: List<&2,String>,y: Nat,x: Nat,width: Nat,height: Nat,totalWidth: Nat) -> List<&2,String>:
  match rows y:
    case Nil{} _: Nil{}
    case row <> rest Succ{before}: row <> paint(rest,sourceLines,before,x,width,height,totalWidth)
    case rows Zero{}: paintLines(rows,sourceLines,height,x,width,totalWidth)
def vertical(measured: List<&2,Measured>,allocated: List<&2,Nat>,+y: Nat,+gap: Nat,+outer: LayoutRect,screen: List<&2,String>,reversed: List<&2,LayoutBox>) -> Placed:
  match measured allocated:
    case Nil{} _: Placed{List.reverse(&2,LayoutBox,reversed),screen}
    case Measured{S.StackEntry{+component,_,_},+lines,_,_} <> rest +height <> more:
      match outer:
        case LayoutRect{+x,_,+width,_}:
          +bounds = rect(x,y,width,height)
          +clip = intersect(outer,bounds)
          +updated = paint(screen,lines,y,x,width,height,width)
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
            +updated : List<&2,String> <- IO.pure(List<&2,String>,paint(screen,lines,y,x,width,height,totalWidth))
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
type HitBox is Data: HitBox{box: LayoutBox,depth: Nat,layer: Nat}
type HitWork is Data: HitWork{box: LayoutBox,depth: Nat}
def childWork(children: List<&2,LayoutBox>,+depth: Nat) -> List<&2,HitWork>:
  match children: case Nil{}: Nil{} case child <> rest: HitWork{child,depth} <> childWork(rest,depth)
@unsafe def collectHits(pending: List<&2,HitWork>,+x: Nat,+y: Nat,+reversed: List<&2,HitBox>) -> List<&2,HitBox>:
  match pending:
    case Nil{}: List.reverse(&2,HitBox,reversed)
    case HitWork{LayoutBox{component,bounds,+clip,+children,lines,offset,+layer},+depth} <> +rest:
      Bool.pick(Unit -> List<&2,HitBox>,within(clip,x,y),
        _ => collectHits(List.append(&2,HitWork,childWork(children,depth + 1n),rest),x,y,HitBox{LayoutBox{component,bounds,clip,children,lines,offset,layer},depth,layer} <> reversed),
        _ => collectHits(rest,x,y,reversed))(Unit{})
def hitBefore(left: HitBox,right: HitBox) -> Bool:
  match left right:
    case HitBox{_,a,+la} HitBox{_,b,+lb}: Nat.is_lt(lb,la) || (Nat.is_eq(la,lb) && Nat.is_le(b,a))
def hitBoxes(hits: List<&2,HitBox>) -> List<&2,LayoutBox>:
  match hits: case Nil{}: Nil{} case HitBox{box,_,_} <> rest: box <> hitBoxes(rest)
def getLayoutBoxesAt(frame: LayoutFrame,x: Nat,y: Nat) -> List<&2,LayoutBox>:
  match frame: case LayoutFrame{root,_,_,_}: hitBoxes(Sort.sort(~HitBox,~hitBefore,collectHits([HitWork{root,0n}],x,y,Nil{})))

# ScrollView owns state across frames; the returned value is the next immutable
# state to retain.  lineOffset records the scroll translation of its child.
type ScrollLayoutFrame is Data: ScrollLayoutFrame{view: Scroll.ScrollView,frame: LayoutFrame}
type ScrollbarGeometry is Data:
  ScrollbarGeometry{column: Nat,trackTop: Nat,trackHeight: Nat,thumbTop: Nat,thumbHeight: Nat,maxScrollTop: Nat}
def viewTop(view: Scroll.ScrollView) -> Nat:
  match view: case Scroll.ScrollView{_,_,_,_,_,_,top,_,_,_,_,_,_,_}: top
def viewChild(view: Scroll.ScrollView) -> C.Component:
  match view: case Scroll.ScrollView{child,_,_,_,_,_,_,_,_,_,_,_,_,_}: child
def contentHeight(view: Scroll.ScrollView) -> Nat:
  match view: case Scroll.ScrollView{_,_,_,_,_,_,_,content,_,_,_,_,_,_}: content
def viewHeight(view: Scroll.ScrollView) -> Nat:
  match view: case Scroll.ScrollView{_,_,_,_,_,_,_,_,height,_,_,_,_,_}: height
def roundFraction(numerator: Nat,+denominator: Nat) -> Nat:
  (numerator + denominator / 2n) / Nat.max(1n,denominator)
def scrollbarGeometry(+view: Scroll.ScrollView,+width: Nat) -> Maybe<&2,ScrollbarGeometry>:
  +height = viewHeight(view)
  +content = contentHeight(view)
  +top = viewTop(view)
  Bool.pick(Unit -> Maybe<&2,ScrollbarGeometry>,Scroll.isScrollbarVisible(view) && Nat.is_gt(width,0n) && Nat.is_gt(height,0n),_ =>
    +thumb = Nat.max(Nat.min(2n,height),Nat.min(height,roundFraction(height * height,Nat.max(1n,content))))
    +maxTop = content - height
    +maxThumb = height - thumb
    Some{ScrollbarGeometry{width - 1n,0n,height,Bool.pick(Nat,Nat.is_eq(maxTop,0n),0n,roundFraction(top * maxThumb,maxTop)),thumb,maxTop}},_ => None{})(Unit{})
def scrollbarActive(view: Scroll.ScrollView) -> Bool:
  match view: case Scroll.ScrollView{_,_,_,_,_,_,_,_,_,_,_,_,active,_}: active
def scrollbarGlyph(view: Scroll.ScrollView,+row: Nat,geometry: ScrollbarGeometry) -> String:
  match geometry:
    case ScrollbarGeometry{_,_,_,+thumbTop,thumbHeight,_}:
      Bool.pick(String,Nat.is_le(thumbTop,row) && Nat.is_lt(row,thumbTop + thumbHeight),
        Bool.pick(String,scrollbarActive(view),"█","┃"),"│")
def styledGlyph(view: Scroll.ScrollView,+glyph: String) -> String:
  +interactive = Scroll.isPrimary(view)
  +track = Bool.pick(String,interactive,"\u{1b}[38;5;239m","\u{1b}[90m")
  +thumb = Bool.pick(String,interactive,"\u{1b}[38;5;188m","\u{1b}[37m")
  Bool.pick(String,String.eq(glyph,"│"),track ++ glyph ++ "\u{1b}[39m",thumb ++ glyph ++ "\u{1b}[39m")
def targetBackground(tokens: List<&2,U.Token>,state: U.AnsiCodeTracker) -> String:
  match tokens:
    case U.Token{code,True{}} <> rest: targetBackground(rest,U.process(state,code))
    case _: U.getActiveBackgroundCode(state)
def replacedScrollbar(+line: String,+column: Nat,+totalWidth: Nat,replacement: String,preserveBackground: Bool,range: U.GraphemeCellRange) -> String:
  match range:
    case U.GraphemeCellRange{+start,+end}:
      +before = U.sliceByColumn(line,0n,start,True{})
      +target = U.sliceByColumn(line,start,end - start,True{})
      +after = U.sliceByColumn(line,end,totalWidth - end,True{})
      +background = Bool.pick(String,preserveBackground,targetBackground(U.tokens(target),U.emptyTracker()),"")
      before ++ U.spaces(start - U.visibleWidth(before),"") ++ T.segmentReset() ++ background ++
        U.spaces(column - start,"") ++ replacement ++ U.spaces(end - column - 1n,"") ++ after
# Overlay scrollbar cells inherit only background, never text styling or links.
# Reserved scrollbar columns start with default styling. Image rows stay intact.
def replaceScrollbarCell(+line: String,+column: Nat,+totalWidth: Nat,+replacement: String,+preserveBackground: Bool) -> String:
  Bool.pick(Unit -> String,Image.isImageLine(line),_ => line,
    _ => replacedScrollbar(line,column,totalWidth,replacement,preserveBackground,
      Maybe.default(&2,U.GraphemeCellRange,U.getGraphemeCellRange(line,column),U.GraphemeCellRange{column,column + 1n})))(Unit{})
def preservesScrollbarBackground(view: Scroll.ScrollView) -> Bool:
  match view:
    case Scroll.ScrollView{_,_,_,_,Scroll.Always{},_,_,_,_,_,_,_,_,_}: False{}
    case _: True{}
def overScrollbar(row: String,index: Nat,+view: Scroll.ScrollView,width: Nat,geometry: Maybe<&2,ScrollbarGeometry>) -> String:
  match geometry:
    case None{}: row
    case Some{ScrollbarGeometry{+column,top,height,thumbTop,thumbHeight,maxTop}}:
      +glyph = scrollbarGlyph(view,index,ScrollbarGeometry{column,top,height,thumbTop,thumbHeight,maxTop})
      replaceScrollbarCell(row,column,width,styledGlyph(view,glyph),preservesScrollbarBackground(view))
def dropLines(lines: List<&2,String>,offset: Nat) -> List<&2,String>:
  match lines offset:
    case Nil{} _: Nil{}
    case lines Zero{}: lines
    case _ <> rest Succ{left}: dropLines(rest,left)
def scrollRows(lines: List<&2,String>,+index: Nat,+width: Nat,+contentWidth: Nat,+view: Scroll.ScrollView,+geometry: Maybe<&2,ScrollbarGeometry>,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: reversed
    case line <> more:
      +base = composite("",Some{line},0n,contentWidth,width)
      +painted = overScrollbar(base,index,view,width,geometry)
      scrollRows(more,index + 1n,width,contentWidth,view,geometry,painted <> reversed)
def scrollBlank(count: Nat,+index: Nat,+width: Nat,+view: Scroll.ScrollView,+geometry: Maybe<&2,ScrollbarGeometry>,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}:
      +line = overScrollbar("",index,view,width,geometry)
      scrollBlank(rest,index + 1n,width,view,geometry,line <> reversed)
def scrollChild(view: Scroll.ScrollView,lines: List<&2,String>,rootRect: LayoutRect,+childRect: LayoutRect,top: Nat) -> LayoutBox:
  LayoutBox{Some{C.id(viewChild(view))},childRect,intersect(rootRect,childRect),Nil{},Some{lines},top,0n}
def scrollRoot(+rootRect: LayoutRect,child: LayoutBox) -> LayoutBox:
  LayoutBox{None{},rootRect,rootRect,child <> Nil{},None{},0n,0n}
def scrollFrame(view: Scroll.ScrollView,+lines: List<&2,String>,+width: Nat,+height: Nat,+contentWidth: Nat) -> ScrollLayoutFrame:
  +updated = Scroll.updateLayout(view,List.length(&2,String,lines),height)
  +top = viewTop(updated)
  +rootRect = rect(0n,0n,width,height)
  +childRect = rect(0n,0n,contentWidth,List.length(&2,String,lines))
  +child = scrollChild(updated,lines,rootRect,childRect,top)
  +root = scrollRoot(rootRect,child)
  +visible = List.take(&2,String,dropLines(lines,top),height)
  +used = List.length(&2,String,visible)
  +geometry = scrollbarGeometry(updated,width)
  +screen = scrollBlank(height - used,used,width,updated,geometry,scrollRows(visible,0n,width,contentWidth,updated,geometry,Nil{}))
  ScrollLayoutFrame{updated,LayoutFrame{root,width,height,screen}}
def renderScrollViewFrame(+view: Scroll.ScrollView,width: Nat,height: Nat) -> IO(ScrollLayoutFrame):
  +safeWidth = Nat.max(1n,width)
  +safeHeight = Nat.max(1n,height)
  +contentWidth = Scroll.getContentWidth(view,safeWidth)
  do IO<ScrollLayoutFrame>:
    lines : List<&2,String> <- C.render(viewChild(view),contentWidth)
    return scrollFrame(view,lines,safeWidth,safeHeight,contentWidth)
