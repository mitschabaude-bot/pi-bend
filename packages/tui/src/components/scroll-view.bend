import Base
import ../component.bend as C
import ../tui.bend as T

type ScrollViewScrollbar is Data: Hidden{} Auto{} Always{}
type Follow is Data: FollowNone{} FollowEnd{}
type Overscroll is Data: Chain{} Contain{}
type ScrollViewOptions is Data:
  ScrollViewOptions{follow: Follow,primary: Bool,overscroll: Overscroll,scrollbar: ScrollViewScrollbar,scrollbarHideDelayMs: Nat}
type ScrollView is Data:
  ScrollView{child: C.Component,followEnd: Bool,primary: Bool,overscroll: Overscroll,scrollbar: ScrollViewScrollbar,scrollbarHideDelayMs: Nat,scrollTop: Nat,contentHeight: Nat,viewportHeight: Nat,followingEnd: Bool,followSuppressedAtEnd: Bool,transientScrollbarVisible: Bool,scrollbarActive: Bool,hideAt: Maybe<&2,Nat>}
type Transition is Data: Transition{view: ScrollView,requestRender: Bool}
type ScrollByResult is Data: ScrollByResult{view: ScrollView,unused: T.Offset,requestRender: Bool}

def defaults() -> ScrollViewOptions: ScrollViewOptions{FollowNone{},False{},Chain{},Hidden{},1000n}
def isFollowEnd(follow: Follow) -> Bool: match follow: case FollowEnd{}: True{} case _: False{}
def new(child: C.Component,options: ScrollViewOptions) -> ScrollView:
  match options:
    case ScrollViewOptions{follow,primary,overscroll,scrollbar,delay}:
      +end = isFollowEnd(follow)
      ScrollView{child,end,primary,overscroll,scrollbar,delay,0n,0n,0n,end,False{},False{},False{},None{}}
def maxScrollTop(view: ScrollView) -> Nat:
  match view: case ScrollView{_,_,_,_,_,_,_,+content,+viewport,_,_,_,_,_}: content - viewport
def isPrimary(view: ScrollView) -> Bool:
  match view: case ScrollView{_,_,primary,_,_,_,_,_,_,_,_,_,_,_}: primary
def visibleRows(view: ScrollView) -> Nat:
  match view: case ScrollView{_,_,_,_,_,_,_,_,rows,_,_,_,_,_}: rows
def getContentWidth(view: ScrollView,+width: Nat) -> Nat:
  match view:
    case ScrollView{_,_,_,_,Always{},_,_,_,_,_,_,_,_,_}: Bool.pick(Nat,Nat.is_gt(width,1n),width - 1n,width)
    case _: width
def isScrollbarVisible(view: ScrollView) -> Bool:
  match view:
    case ScrollView{_,_,_,_,Always{},_,_,_,viewport,_,_,_,_,_}: Nat.is_gt(viewport,0n)
    case ScrollView{_,_,_,_,Auto{},_,_,content,viewport,_,_,visible,_,_}: Nat.is_gt(content,viewport) && visible
    case _: False{}
def updateLayout(view: ScrollView,+contentHeight: Nat,+viewportHeight: Nat) -> ScrollView:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+scrollbar,+delay,+top,_,_,+following,+suppressed,+visible,+active,+hideAt}:
      +maxTop = contentHeight - viewportHeight
      +next = Bool.pick(Nat,following,maxTop,Nat.min(top,maxTop))
      +nextSuppressed = Bool.pick(Bool,Nat.is_lt(next,maxTop),False{},suppressed)
      +nextFollowing = following || (followEnd && Nat.is_eq(next,maxTop) && Bool.not(nextSuppressed))
      +overflow = Nat.is_gt(contentHeight,viewportHeight)
      ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,next,contentHeight,viewportHeight,nextFollowing,nextSuppressed,Bool.pick(Bool,overflow,visible,False{}),active,Bool.pick(Maybe<&2,Nat>,overflow,hideAt,None{})}
type Activity is Data: Activity{visible: Bool,hideAt: Maybe<&2,Nat>}
def markActivity(scrollbar: ScrollViewScrollbar,content: Nat,viewport: Nat,active: Bool,delay: Nat,now: Nat,moved: Bool,visible: Bool,hideAt: Maybe<&2,Nat>) -> Activity:
  match scrollbar:
    case Auto{}:
      Bool.pick(Unit -> Activity,moved && Nat.is_gt(content,viewport),_ => Activity{True{},Bool.pick(Maybe<&2,Nat>,active,None{},Some{now + delay})},_ => Activity{visible,hideAt})(Unit{})
    case _: Activity{visible,hideAt}
def completeScrollTo(child: C.Component,followEnd: Bool,primary: Bool,overscroll: Overscroll,scrollbar: ScrollViewScrollbar,delay: Nat,top: Nat,content: Nat,viewport: Nat,following: Bool,suppressed: Bool,active: Bool,changed: Bool,activity: Activity) -> Transition:
  match activity:
    case Activity{visible,hideAt}: Transition{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,visible,active,hideAt},changed}
def sameBool(a: Bool,b: Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}
def scrollTo(view: ScrollView,target: Nat,disableFollow: Bool,now: Nat) -> Transition:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+scrollbar,+delay,+top,+content,+viewport,+following,+suppressed,+visible,+active,+hideAt}:
      +maxTop = content - viewport
      +next = Nat.min(target,maxTop)
      +nextSuppressed = disableFollow && Nat.is_eq(next,maxTop)
      +nextFollowing = Bool.not(nextSuppressed) && followEnd && Nat.is_eq(next,maxTop)
      +moved = Bool.not(Nat.is_eq(next,top))
      +changed = moved || Bool.not(sameBool(nextFollowing,following)) || Bool.not(sameBool(nextSuppressed,suppressed))
      completeScrollTo(child,followEnd,primary,overscroll,scrollbar,delay,next,content,viewport,nextFollowing,nextSuppressed,active,changed,markActivity(scrollbar,content,viewport,active,delay,now,moved,visible,hideAt))
def advanceTime(view: ScrollView,now: Nat) -> Transition:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+scrollbar,+delay,+top,+content,+viewport,+following,+suppressed,+visible,+active,hideAt}:
      match hideAt:
        case None{}: Transition{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,visible,active,None{}},False{}}
        case Some{+deadline}:
          Bool.pick(Unit -> Transition,Nat.is_le(deadline,now) && Bool.not(active),_ => Transition{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,False{},active,None{}},visible},_ => Transition{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,visible,active,Some{deadline}},False{}})(Unit{})
def move(start: Nat,delta: T.Offset,maxTop: Nat) -> Nat:
  match delta:
    case T.Forward{amount}: Nat.min(maxTop,start + amount)
    case T.Backward{amount}: start - amount
def completeScrollBy(child: C.Component,followEnd: Bool,primary: Bool,overscroll: Overscroll,scrollbar: ScrollViewScrollbar,delay: Nat,top: Nat,content: Nat,viewport: Nat,following: Bool,active: Bool,unused: T.Offset,changed: Bool,activity: Activity) -> ScrollByResult:
  match activity:
    case Activity{visible,hideAt}: ScrollByResult{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,False{},visible,active,hideAt},unused,changed}
def scrollBy(view: ScrollView,+requested: T.Offset,now: Nat) -> ScrollByResult:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+scrollbar,+delay,+top,+content,+viewport,+following,+suppressed,+visible,+active,+hideAt}:
      +maxTop = content - viewport
      +start = Bool.pick(Nat,following,maxTop,top)
      +next = move(start,requested,maxTop)
      +moved = C.difference(next,start)
      +unused = C.subtract(requested,moved)
      +nextFollowing = followEnd && Nat.is_eq(next,maxTop)
      +changed = Bool.not(Nat.is_eq(next,start)) || Bool.not(sameBool(nextFollowing,following))
      completeScrollBy(child,followEnd,primary,overscroll,scrollbar,delay,next,content,viewport,nextFollowing,active,unused,changed,markActivity(scrollbar,content,viewport,active,delay,now,Bool.not(Nat.is_eq(next,start)),visible,hideAt))
def scrollToStart(view: ScrollView,now: Nat) -> Transition: scrollTo(view,0n,False{},now)
def scrollToEnd(+view: ScrollView,now: Nat) -> Transition:
  scrollTo(view,maxScrollTop(view),False{},now)
def sameScrollbar(a: ScrollViewScrollbar,b: ScrollViewScrollbar) -> Bool:
  match a b:
    case Hidden{} Hidden{}: True{}
    case Auto{} Auto{}: True{}
    case Always{} Always{}: True{}
    case _ _: False{}
def isAuto(value: ScrollViewScrollbar) -> Bool: match value: case Auto{}: True{} case _: False{}
def setScrollbar(view: ScrollView,+next: ScrollViewScrollbar,now: Nat) -> Transition:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+current,+delay,+top,+content,+viewport,+following,+suppressed,+visible,+active,+hideAt}:
      +changed = Bool.not(sameScrollbar(current,next))
      +newVisible = Bool.pick(Bool,isAuto(next),visible,False{})
      +newHideAt = Bool.pick(Maybe<&2,Nat>,isAuto(next),hideAt,None{})
      Transition{ScrollView{child,followEnd,primary,overscroll,next,delay,top,content,viewport,following,suppressed,newVisible,active,newHideAt},changed}
def completeActive(child: C.Component,followEnd: Bool,primary: Bool,overscroll: Overscroll,scrollbar: ScrollViewScrollbar,delay: Nat,top: Nat,content: Nat,viewport: Nat,following: Bool,suppressed: Bool,active: Bool,changed: Bool,activity: Activity) -> Transition:
  match activity:
    case Activity{visible,hideAt}: Transition{ScrollView{child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,visible,active,hideAt},changed}
def setScrollbarActive(view: ScrollView,+next: Bool,now: Nat) -> Transition:
  match view:
    case ScrollView{+child,+followEnd,+primary,+overscroll,+scrollbar,+delay,+top,+content,+viewport,+following,+suppressed,+visible,+active,+hideAt}:
      completeActive(child,followEnd,primary,overscroll,scrollbar,delay,top,content,viewport,following,suppressed,next,Bool.not(sameBool(active,next)),markActivity(scrollbar,content,viewport,next,delay,now,Bool.not(sameBool(active,next)),visible,hideAt))
