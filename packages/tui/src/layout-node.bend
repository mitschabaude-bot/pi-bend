import Base
import ./component.bend as C
import ./components/stack.bend as Stack
import ./components/scroll-view.bend as Scroll
import ./tui.bend as T
import ../../runtime/src/callback.bend as Callback

# A recursive layout tree keeps the upstream node distinctions without adding
# layout metadata to every ordinary Component. Children/Empty are the native
# immutable representation of a stack's ordered entry collection.
type LayoutNode is Data:
  Leaf{component: C.Component}
  Inline{node: LayoutNode}
  VStack{entries: LayoutNode,gap: Nat}
  HStack{entries: LayoutNode,gap: Nat,align: Stack.Align}
  ScrollNode{view: Scroll.ScrollView}
  Spacer{lines: Nat}
  Entry{node: LayoutNode,size: Stack.StackEntryOptions,visible: Maybe<&2,Callback.Callback<Stack.LayoutViewport,Bool>>}
  Children{first: LayoutNode,rest: LayoutNode}
  Empty{}

def append(entries: LayoutNode,entry: LayoutNode) -> LayoutNode:
  match entries:
    case Empty{}: Children{entry,Empty{}}
    case Children{first,rest}: Children{first,append(rest,entry)}
    case _: Children{entry,Empty{}}
def child(node: LayoutNode,size: Stack.StackEntryOptions,visible: Maybe<&2,Callback.Callback<Stack.LayoutViewport,Bool>>) -> LayoutNode:
  Entry{node,size,visible}

# A viewport can nest inside stacks and inline layouts. Keep its updated
# immutable node in the tree so the next layout frame retains manual scroll.
type ScrollMotion is Data: ScrollLines{delta: T.Offset} ScrollPageUp{} ScrollPageDown{} ScrollHalfPageUp{} ScrollHalfPageDown{} ScrollTop{} ScrollBottom{}
type ScrollResult is Data: ScrollResult{node: LayoutNode,found: Bool,unused: T.Offset,render: Bool}
def pageDelta(view: Scroll.ScrollView,up: Bool) -> T.Offset:
  +lines = Nat.max(1n,Scroll.visibleRows(view) - 4n)
  Bool.pick(T.Offset,up,T.Backward{lines},T.Forward{lines})
def halfPageDelta(view: Scroll.ScrollView,up: Bool) -> T.Offset:
  +lines = Nat.max(1n,Scroll.visibleRows(view) / 2n)
  Bool.pick(T.Offset,up,T.Backward{lines},T.Forward{lines})
def noScroll(node: LayoutNode) -> ScrollResult: ScrollResult{node,False{},T.Forward{0n},False{}}
def scrolled(result: Scroll.ScrollByResult) -> ScrollResult:
  match result:
    case Scroll.ScrollByResult{view,unused,render}: ScrollResult{ScrollNode{view},True{},unused,render}
def jumped(result: Scroll.Transition) -> ScrollResult:
  match result:
    case Scroll.Transition{view,render}: ScrollResult{ScrollNode{view},True{},T.Forward{0n},render}
def scrollPrimaryView(+view: Scroll.ScrollView,motion: ScrollMotion,now: Nat) -> ScrollResult:
  match motion:
    case ScrollTop{}: jumped(Scroll.scrollToStart(view,now))
    case ScrollBottom{}: jumped(Scroll.scrollToEnd(view,now))
    case ScrollLines{delta}: scrolled(Scroll.scrollBy(view,delta,now))
    case ScrollPageUp{}: scrolled(Scroll.scrollBy(view,pageDelta(view,True{}),now))
    case ScrollPageDown{}: scrolled(Scroll.scrollBy(view,pageDelta(view,False{}),now))
    case ScrollHalfPageUp{}: scrolled(Scroll.scrollBy(view,halfPageDelta(view,True{}),now))
    case ScrollHalfPageDown{}: scrolled(Scroll.scrollBy(view,halfPageDelta(view,False{}),now))
def scrollView(+view: Scroll.ScrollView,motion: ScrollMotion,now: Nat,primary: Bool) -> ScrollResult:
  match primary:
    case False{}: noScroll(ScrollNode{view})
    case True{}: scrollPrimaryView(view,motion,now)
def inlineResult(result: ScrollResult) -> ScrollResult:
  match result:
    case ScrollResult{node,found,unused,render}: ScrollResult{Inline{node},found,unused,render}
def verticalResult(result: ScrollResult,gap: Nat) -> ScrollResult:
  match result:
    case ScrollResult{node,found,unused,render}: ScrollResult{VStack{node,gap},found,unused,render}
def horizontalResult(result: ScrollResult,gap: Nat,align: Stack.Align) -> ScrollResult:
  match result:
    case ScrollResult{node,found,unused,render}: ScrollResult{HStack{node,gap,align},found,unused,render}
def entryResult(result: ScrollResult,size: Stack.StackEntryOptions,visible: Maybe<&2,Callback.Callback<Stack.LayoutViewport,Bool>>) -> ScrollResult:
  match result:
    case ScrollResult{node,found,unused,render}: ScrollResult{Entry{node,size,visible},found,unused,render}
def childrenResult(head: ScrollResult,tail: ScrollResult) -> ScrollResult:
  match head tail:
    case ScrollResult{first,True{},unused,render} ScrollResult{rest,_,_,_}: ScrollResult{Children{first,rest},True{},unused,render}
    case ScrollResult{first,False{},_,_} ScrollResult{rest,found,unused,render}: ScrollResult{Children{first,rest},found,unused,render}
def scrollPrimary(node: LayoutNode,+motion: ScrollMotion,+now: Nat) -> ScrollResult:
  match node:
    case ScrollNode{+view}: scrollView(view,motion,now,Scroll.isPrimary(view))
    case Inline{nested}: inlineResult(scrollPrimary(nested,motion,now))
    case VStack{entries,gap}: verticalResult(scrollPrimary(entries,motion,now),gap)
    case HStack{entries,gap,align}: horizontalResult(scrollPrimary(entries,motion,now),gap,align)
    case Entry{nested,size,visible}: entryResult(scrollPrimary(nested,motion,now),size,visible)
    case Children{first,rest}: childrenResult(scrollPrimary(first,motion,now),scrollPrimary(rest,motion,now))
    case node: noScroll(node)

# A manually scrolled follow-end viewport offers a jump-back cue at its last
# visible row. The primary viewport is unique in the interactive layout.
def scrollIndicator(view: Scroll.ScrollView) -> Maybe<&2,Nat>:
  match view:
    case Scroll.ScrollView{_,follow,primary,_,_,_,_,_,+rows,following,_,_,_,_}:
      Bool.pick(Maybe<&2,Nat>,follow && primary && Bool.not(following) && Nat.is_gt(rows,0n),Some{rows - 1n},None{})
def firstIndicator(first: Maybe<&2,Nat>,rest: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match first:
    case Some{_}: first
    case None{}: rest
def indicatorRow(node: LayoutNode) -> Maybe<&2,Nat>:
  match node:
    case ScrollNode{view}: scrollIndicator(view)
    case Inline{nested}: indicatorRow(nested)
    case VStack{entries,_}: indicatorRow(entries)
    case HStack{entries,_,_}: indicatorRow(entries)
    case Entry{nested,_,_}: indicatorRow(nested)
    case Children{first,rest}: firstIndicator(indicatorRow(first),indicatorRow(rest))
    case _: None{}
