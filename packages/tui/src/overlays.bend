import Base
import ./component.bend as C

# Pure overlay/focus policy. The renderer refreshes visibility predicates and
# supplies the mounted component IDs before applying a transition. Changes
# describe ordered focus assignments followed by cursor/render effects.
type OverlayHandle is Data: OverlayHandle{value: Nat}
type Entry is Data:
  Entry{handle: OverlayHandle,component: C.ComponentId,preFocus: Maybe<&2,C.ComponentId>,hidden: Bool,visible: Bool,nonCapturing: Bool,focusOrder: Nat}
type Resume is Data:
  RestoreOverlay{}
  FocusTarget{target: Maybe<&2,C.ComponentId>}
type Restore is Data:
  Inactive{}
  Eligible{overlay: OverlayHandle}
  Blocked{overlay: OverlayHandle,blockedBy: C.ComponentId,resume: Resume}
type State is Data:
  State{entries: List<&2,Entry>,focus: Maybe<&2,C.ComponentId>,restore: Restore,order: Nat,nextId: Nat}
type FocusChange is Data:
  FocusChange{previous: Maybe<&2,C.ComponentId>,next: Maybe<&2,C.ComponentId>}
type Change is Data:
  Change{state: State,focusChanges: List<&2,FocusChange>,hideCursor: Bool,render: Bool}
type Decision is Data:
  Decision{target: Maybe<&2,C.ComponentId>,restore: Restore}

def new() -> State: State{Nil{},None{},Inactive{},0n,1n}
def sameHandle(left: OverlayHandle,right: OverlayHandle) -> Bool:
  match left right:
    case OverlayHandle{a} OverlayHandle{b}: Nat.is_eq(a,b)
def sameFocus(left: Maybe<&2,C.ComponentId>,right: Maybe<&2,C.ComponentId>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: C.same(a,b)
    case _ _: False{}
def entryHandle(entry: Entry) -> OverlayHandle:
  match entry:
    case Entry{handle,_,_,_,_,_,_}: handle
def entryComponent(entry: Entry) -> C.ComponentId:
  match entry:
    case Entry{_,component,_,_,_,_,_}: component
def preFocus(entry: Entry) -> Maybe<&2,C.ComponentId>:
  match entry:
    case Entry{_,_,value,_,_,_,_}: value
def isVisible(entry: Entry) -> Bool:
  match entry:
    case Entry{_,_,_,hidden,visible,_,_}: Bool.not(hidden) && visible
def find(entries: List<&2,Entry>,+handle: OverlayHandle) -> Maybe<&2,Entry>:
  match entries:
    case Nil{}: None{}
    case +entry <> rest: Bool.pick(Unit -> Maybe<&2,Entry>,sameHandle(entryHandle(entry),handle),_ => Some{entry},_ => find(rest,handle))(Unit{})
def byComponent(entries: List<&2,Entry>,+component: Maybe<&2,C.ComponentId>,+visibleOnly: Bool) -> Maybe<&2,Entry>:
  match entries:
    case Nil{}: None{}
    case +entry <> rest:
      Bool.pick(Unit -> Maybe<&2,Entry>,sameFocus(Some{entryComponent(entry)},component) && (Bool.not(visibleOnly) || isVisible(entry)),_ => Some{entry},_ => byComponent(rest,component,visibleOnly))(Unit{})
def mounted(components: List<&2,C.ComponentId>,+component: C.ComponentId) -> Bool:
  match components:
    case Nil{}: False{}
    case item <> rest: Bool.pick(Unit -> Bool,C.same(item,component),_ => True{},_ => mounted(rest,component))(Unit{})
def optionalPreFocus(entry: Maybe<&2,Entry>) -> Maybe<&2,C.ComponentId>:
  match entry:
    case Some{value}: preFocus(value)
    case None{}: None{}
# At most one link per overlay, plus its base target. This structural bound
# stops cycles without a mutable visited set or an arbitrary recursion limit.
def ancestor(fuel: Nat,+entries: List<&2,Entry>,current: Maybe<&2,C.ComponentId>,+wanted: C.ComponentId) -> Bool:
  match fuel current:
    case Succ{remaining} Some{+current}:
      Bool.pick(Unit -> Bool,C.same(current,wanted),_ => True{},_ => ancestor(remaining,entries,optionalPreFocus(byComponent(entries,Some{current},False{})),wanted))(Unit{})
    case _ _: False{}
def restores(restore: Restore,handle: OverlayHandle) -> Bool:
  match restore:
    case Inactive{}: False{}
    case Eligible{value}: sameHandle(value,handle)
    case Blocked{value,_,_}: sameHandle(value,handle)
def visibleRestoreEntry(+restore: Restore,entry: Maybe<&2,Entry>) -> Restore:
  match entry:
    case Some{value}: Bool.pick(Restore,isVisible(value),restore,Inactive{})
    case None{}: Inactive{}
def visibleRestore(entries: List<&2,Entry>,+restore: Restore) -> Restore:
  match restore:
    case Inactive{}: Inactive{}
    case Eligible{handle}: visibleRestoreEntry(restore,find(entries,handle))
    case Blocked{handle,_,_}: visibleRestoreEntry(restore,find(entries,handle))
def clearFor(restore: Restore,handle: OverlayHandle) -> Restore:
  +restore = {restore: Restore}
  Bool.pick(Restore,restores(restore,handle),Inactive{},restore)
def resumeFocus(entries: List<&2,Entry>,handle: OverlayHandle,resume: Resume,restore: Restore) -> Decision:
  match resume:
    case FocusTarget{target}: Decision{target,Inactive{}}
    case RestoreOverlay{}: Decision{Maybe.map(&2,Entry,C.ComponentId,entryComponent,find(entries,handle)),restore}
def ordinaryFocus(+entries: List<&2,Entry>,requested: C.ComponentId,+restore: Restore,previousOverlay: Maybe<&2,Entry>) -> Decision:
  match previousOverlay:
    case Some{+entry}:
      +requested = {requested: C.ComponentId}
      blocked = restores(visibleRestore(entries,restore),entryHandle(entry)) && Bool.not(ancestor(Succ{List.length(&2,Entry,entries)},entries,preFocus(entry),requested))
      Decision{Some{requested},Bool.pick(Restore,blocked,Blocked{entryHandle(entry),requested,RestoreOverlay{}},restore)}
    case None{}: Decision{Some{requested},restore}
def transferBlock(handle: OverlayHandle,+requested: C.ComponentId,resume: Resume) -> Decision:
  match resume:
    case FocusTarget{target}: Decision{target,Inactive{}}
    case RestoreOverlay{}: Decision{Some{requested},Blocked{handle,requested,RestoreOverlay{}}}
def nonOverlayFocus(+entries: List<&2,Entry>,components: List<&2,C.ComponentId>,previous: Maybe<&2,C.ComponentId>,requested: C.ComponentId,+stored: Restore,active: Restore,previousOverlay: Maybe<&2,Entry>) -> Decision:
  match active:
    case Blocked{+handle,+blockedBy,+resume}:
      +requested = {requested: C.ComponentId}
      Bool.pick(Unit -> Decision,sameFocus(previous,Some{blockedBy}),
        _ => Bool.pick(Unit -> Decision,Bool.not(mounted(components,blockedBy)),_ => resumeFocus(entries,handle,resume,stored),_ => transferBlock(handle,requested,resume))(Unit{}),
        _ => ordinaryFocus(entries,requested,stored,previousOverlay))(Unit{})
    case _: ordinaryFocus(entries,requested,stored,previousOverlay)
def clearedFocus(entries: List<&2,Entry>,previous: Maybe<&2,C.ComponentId>,+stored: Restore,active: Restore,preserve: Bool) -> Decision:
  match active:
    case Blocked{handle,blockedBy,resume}:
      Bool.pick(Unit -> Decision,sameFocus(previous,Some{blockedBy}),_ => resumeFocus(entries,handle,resume,stored),_ => Decision{None{},Bool.pick(Restore,preserve,stored,Inactive{})})(Unit{})
    case _: Decision{None{},Bool.pick(Restore,preserve,stored,Inactive{})}
def chooseFocus(+entries: List<&2,Entry>,components: List<&2,C.ComponentId>,+previous: Maybe<&2,C.ComponentId>,requested: Maybe<&2,C.ComponentId>,+stored: Restore,preserve: Bool) -> Decision:
  match requested:
    case None{}: clearedFocus(entries,previous,stored,visibleRestore(entries,stored),preserve)
    case Some{+requested}:
      Bool.pick(Unit -> Decision,Maybe.is_none(&2,Entry,byComponent(entries,Some{requested},False{})),
        _ => nonOverlayFocus(entries,components,previous,requested,stored,visibleRestore(entries,stored),byComponent(entries,previous,True{})),
        _ => Decision{Some{requested},stored})(Unit{})
def eligible(entry: Maybe<&2,Entry>,otherwise: Restore) -> Restore:
  match entry:
    case Some{value}: Eligible{entryHandle(value)}
    case None{}: otherwise
def changedFocus(+entries: List<&2,Entry>,previous: Maybe<&2,C.ComponentId>,order: Nat,nextId: Nat,decision: Decision) -> Change:
  match decision:
    case Decision{+next,restore}: Change{State{entries,next,eligible(byComponent(entries,next,True{}),restore),order,nextId},FocusChange{previous,next} <> Nil{},False{},False{}}
def setFocusInternal(state: State,components: List<&2,C.ComponentId>,target: Maybe<&2,C.ComponentId>,preserve: Bool) -> Change:
  match state:
    case State{+entries,+previous,restore,order,nextId}: changedFocus(entries,previous,order,nextId,chooseFocus(entries,components,previous,target,restore,preserve))
def setFocus(state: State,components: List<&2,C.ComponentId>,target: Maybe<&2,C.ComponentId>) -> Change:
  setFocusInternal(state,components,target,False{})
def unchanged(state: State) -> Change: Change{state,Nil{},False{},False{}}
def effects(change: Change,hideCursor: Bool,render: Bool) -> Change:
  match change:
    case Change{state,focus,oldHide,oldRender}: Change{state,focus,oldHide || hideCursor,oldRender || render}
def setRestore(state: State,restore: Restore) -> State:
  match state:
    case State{entries,focus,_,order,nextId}: State{entries,focus,restore,order,nextId}
def entryOrder(entry: Entry) -> Nat:
  match entry:
    case Entry{_,_,_,_,_,_,order}: order
def latest(current: Maybe<&2,Entry>,+entry: Entry) -> Maybe<&2,Entry>:
  match current:
    case Some{+old}: Bool.pick(Maybe<&2,Entry>,Nat.is_gt(entryOrder(entry),entryOrder(old)),Some{entry},Some{old})
    case None{}: Some{entry}
def topmost(entries: List<&2,Entry>,current: Maybe<&2,Entry>) -> Maybe<&2,Entry>:
  match entries:
    case Nil{}: current
    case Entry{handle,component,previous,hidden,visible,+nonCapturing,order} <> rest:
      +entry = {Entry{handle,component,previous,hidden,visible,nonCapturing,order}: Entry}
      +current = {current: Maybe<&2,Entry>}
      topmost(rest,Bool.pick(Maybe<&2,Entry>,Bool.not(nonCapturing) && isVisible(entry),latest(current,entry),current))
def fallback(entries: List<&2,Entry>,otherwise: Maybe<&2,C.ComponentId>) -> Maybe<&2,C.ComponentId>:
  Maybe.default(&2,Maybe<&2,C.ComponentId>,Maybe.map(&2,Entry,Maybe<&2,C.ComponentId>,entry => Some{entryComponent(entry)},topmost(entries,None{})),otherwise)

def showOverlay(state: State,components: List<&2,C.ComponentId>,+component: C.ComponentId,+nonCapturing: Bool,+visible: Bool) -> Change & OverlayHandle:
  match state:
    case State{entries,+focus,restore,+order,+nextId}:
      +handle = {OverlayHandle{nextId}: OverlayHandle}
      +next = {State{List.append(&2,Entry,entries,Entry{handle,component,focus,False{},visible,nonCapturing,Succ{order}} <> Nil{}),focus,restore,Succ{order},Succ{nextId}}: State}
      (effects(Bool.pick(Unit -> Change,Bool.not(nonCapturing) && visible,_ => setFocus(next,components,Some{component}),_ => unchanged(next))(Unit{}),True{},True{}),handle)
def removeEntries(entries: List<&2,Entry>,+removed: Entry,reversed: List<&2,Entry>) -> List<&2,Entry>:
  match entries:
    case Nil{}: List.reverse(&2,Entry,reversed)
    case Entry{+handle,component,+previous,hidden,visible,passive,order} <> rest:
      +kept = {Entry{handle,component,Bool.pick(Maybe<&2,C.ComponentId>,sameFocus(previous,Some{entryComponent(removed)}),preFocus(removed),previous),hidden,visible,passive,order}: Entry}
      +reversed = {reversed: List<&2,Entry>}
      removeEntries(rest,removed,Bool.pick(List<&2,Entry>,sameHandle(handle,entryHandle(removed)),reversed,kept <> reversed))
def hideEntry(state: State,components: List<&2,C.ComponentId>,entry: Maybe<&2,Entry>) -> Change:
  match state entry:
    case State{entries,+focus,restore,order,nextId} Some{+removed}:
      +entries = removeEntries(entries,removed,Nil{})
      +next = {State{entries,focus,clearFor(restore,entryHandle(removed)),order,nextId}: State}
      effects(Bool.pick(Unit -> Change,sameFocus(focus,Some{entryComponent(removed)}),_ => setFocus(next,components,fallback(entries,preFocus(removed))),_ => unchanged(next))(Unit{}),List.is_empty(&2,Entry,entries),True{})
    case state None{}: unchanged(state)
def hide(+state: State,components: List<&2,C.ComponentId>,handle: OverlayHandle) -> Change:
  match state:
    case State{entries,_,_,_,_}: hideEntry(state,components,find(entries,handle))
def lastEntry(entries: List<&2,Entry>,last: Maybe<&2,Entry>) -> Maybe<&2,Entry>:
  match entries:
    case Nil{}: last
    case entry <> rest: lastEntry(rest,Some{entry})
def hideOverlay(+state: State,components: List<&2,C.ComponentId>) -> Change:
  match state:
    case State{entries,_,_,_,_}: hideEntry(state,components,lastEntry(entries,None{}))

def replace(entries: List<&2,Entry>,+replacement: Entry,reversed: List<&2,Entry>) -> List<&2,Entry>:
  match entries:
    case Nil{}: List.reverse(&2,Entry,reversed)
    case +entry <> rest: replace(rest,replacement,Bool.pick(Entry,sameHandle(entryHandle(entry),entryHandle(replacement)),replacement,entry) <> reversed)
def focusEntry(state: State,components: List<&2,C.ComponentId>,entry: Maybe<&2,Entry>) -> Change:
  match state entry:
    case State{+entries,+current,+restore,+order,+nextId} Some{Entry{handle,+component,previous,+hidden,+visible,passive,_}}:
      Bool.pick(Unit -> Change,Bool.not(hidden) && visible,
        _ => effects(setFocus(State{replace(entries,Entry{handle,component,previous,hidden,visible,passive,Succ{order}},Nil{}),current,restore,Succ{order},nextId},components,Some{component}),False{},True{}),
        _ => unchanged(State{entries,current,restore,order,nextId}))(Unit{})
    case state None{}: unchanged(state)
def focusOverlay(+state: State,components: List<&2,C.ComponentId>,handle: OverlayHandle) -> Change:
  match state:
    case State{entries,_,_,_,_}: focusEntry(state,components,find(entries,handle))
def updateHidden(state: State,+components: List<&2,C.ComponentId>,entry: Entry,+hidden: Bool) -> Change:
  match state entry:
    case State{+entries,+current,+restore,+order,nextId} Entry{+handle,+component,+previous,_,+visible,+passive,oldOrder}:
      +shouldFocus = Bool.not(hidden) && Bool.not(passive) && visible
      +newOrder = Bool.pick(Nat,shouldFocus,Succ{order},order)
      +entries = replace(entries,Entry{handle,component,previous,hidden,visible,passive,Bool.pick(Nat,shouldFocus,newOrder,oldOrder)},Nil{})
      +next = {State{entries,current,Bool.pick(Restore,hidden,clearFor(restore,handle),restore),newOrder,nextId}: State}
      effects(Bool.pick(Unit -> Change,hidden && sameFocus(current,Some{component}),
        _ => setFocus(next,components,fallback(entries,previous)),
        _ => Bool.pick(Unit -> Change,shouldFocus,_ => setFocus(next,components,Some{component}),_ => unchanged(next))(Unit{}))(Unit{}),False{},True{})
def entryHidden(entry: Entry) -> Bool:
  match entry:
    case Entry{_,_,_,hidden,_,_,_}: hidden
def hiddenEntry(+state: State,components: List<&2,C.ComponentId>,entry: Maybe<&2,Entry>,+hidden: Bool) -> Change:
  match entry:
    case Some{+value}:
      Bool.pick(Unit -> Change,Bool.pick(Bool,hidden,entryHidden(value),Bool.not(entryHidden(value))),_ => unchanged(state),_ => updateHidden(state,components,value,hidden))(Unit{})
    case None{}: unchanged(state)
def setHidden(+state: State,components: List<&2,C.ComponentId>,handle: OverlayHandle,hidden: Bool) -> Change:
  match state:
    case State{entries,_,_,_,_}: hiddenEntry(state,components,find(entries,handle),hidden)
def visibleEntry(state: State,entry: Maybe<&2,Entry>,visible: Bool) -> State:
  match state entry:
    case State{entries,current,restore,order,nextId} Some{Entry{handle,component,previous,hidden,_,passive,rank}}:
      State{replace(entries,Entry{handle,component,previous,hidden,visible,passive,rank},Nil{}),current,restore,order,nextId}
    case state None{}: state
# Refreshing a predicate does not itself steal focus or request a render.
def setVisibility(+state: State,handle: OverlayHandle,visible: Bool) -> State:
  match state:
    case State{entries,_,_,_,_}: visibleEntry(state,find(entries,handle),visible)
def releaseTarget(+entry: Entry,top: Maybe<&2,Entry>) -> Maybe<&2,C.ComponentId>:
  match top:
    case Some{+value}: Bool.pick(Maybe<&2,C.ComponentId>,sameHandle(entryHandle(entry),entryHandle(value)),preFocus(entry),Some{entryComponent(value)})
    case None{}: preFocus(entry)
def releaseFocus(state: State,components: List<&2,C.ComponentId>,+entry: Entry,+explicit: Maybe<&2,Maybe<&2,C.ComponentId>>) -> Change:
  match state:
    case State{+entries,+current,restore,order,nextId}:
      +next = {State{entries,current,clearFor(restore,entryHandle(entry)),order,nextId}: State}
      effects(Bool.pick(Unit -> Change,sameFocus(current,Some{entryComponent(entry)}) || Bool.not(Maybe.is_none(&2,Maybe<&2,C.ComponentId>,explicit)),
        _ => setFocus(next,components,Maybe.default(&2,Maybe<&2,C.ComponentId>,explicit,releaseTarget(entry,topmost(entries,None{})))),_ => unchanged(next))(Unit{}),False{},True{})
def blockedRelease(state: State,handle: OverlayHandle,blockedBy: C.ComponentId,explicit: Maybe<&2,Maybe<&2,C.ComponentId>>) -> Change:
  match explicit:
    case None{}: effects(unchanged(setRestore(state,Inactive{})),False{},True{})
    case Some{target}: effects(unchanged(setRestore(state,Blocked{handle,blockedBy,FocusTarget{target}})),False{},True{})
def releasePending(+state: State,components: List<&2,C.ComponentId>,+entry: Entry,+explicit: Maybe<&2,Maybe<&2,C.ComponentId>>,current: Maybe<&2,C.ComponentId>,restore: Restore) -> Change:
  match restore:
    case Blocked{+handle,+blockedBy,_}:
      Bool.pick(Unit -> Change,sameHandle(handle,entryHandle(entry)) && sameFocus(current,Some{blockedBy}),_ => blockedRelease(state,handle,blockedBy,explicit),_ => releaseFocus(state,components,entry,explicit))(Unit{})
    case _: releaseFocus(state,components,entry,explicit)
def unfocusEntry(+state: State,components: List<&2,C.ComponentId>,entry: Maybe<&2,Entry>,explicit: Maybe<&2,Maybe<&2,C.ComponentId>>) -> Change:
  match state entry:
    case State{_,+current,+restore,_,_} Some{+entry}:
      Bool.pick(Unit -> Change,sameFocus(current,Some{entryComponent(entry)}) || restores(restore,entryHandle(entry)),_ => releasePending(state,components,entry,explicit,current,restore),_ => unchanged(state))(Unit{})
    case _ None{}: unchanged(state)
def unfocus(+state: State,components: List<&2,C.ComponentId>,handle: OverlayHandle,explicit: Maybe<&2,Maybe<&2,C.ComponentId>>) -> Change:
  match state:
    case State{entries,_,_,_,_}: unfocusEntry(state,components,find(entries,handle),explicit)

def inputFallback(+state: State,components: List<&2,C.ComponentId>,entry: Maybe<&2,Entry>,+top: Maybe<&2,Entry>) -> Change:
  match entry:
    case Some{+entry}:
      Bool.pick(Unit -> Change,isVisible(entry),_ => unchanged(state),_ =>
        setFocusInternal(state,components,Maybe.default(&2,Maybe<&2,C.ComponentId>,Maybe.map(&2,Entry,Maybe<&2,C.ComponentId>,value => Some{entryComponent(value)},top),preFocus(entry)),Maybe.is_none(&2,Entry,top)))(Unit{})
    case None{}: unchanged(state)
def inputResume(state: State,components: List<&2,C.ComponentId>,decision: Decision) -> Change:
  match decision:
    case Decision{target,restore}: setFocus(setRestore(state,restore),components,target)
def restoreInputFocus(+state: State,components: List<&2,C.ComponentId>,+entries: List<&2,Entry>,current: Maybe<&2,C.ComponentId>,+stored: Restore,active: Restore) -> Change:
  match active:
    case Eligible{handle}: setFocus(state,components,Maybe.map(&2,Entry,C.ComponentId,entryComponent,find(entries,handle)))
    case Blocked{handle,blockedBy,resume}:
      Bool.pick(Unit -> Change,sameFocus(current,Some{blockedBy}),_ => unchanged(state),_ => inputResume(state,components,resumeFocus(entries,handle,resume,stored)))(Unit{})
    case Inactive{}: unchanged(state)
def prepareRestore(+state: State,components: List<&2,C.ComponentId>) -> Change:
  match state:
    case State{+entries,+current,+restore,_,_}:
      Bool.pick(Unit -> Change,Maybe.is_none(&2,Entry,byComponent(entries,current,False{})),_ => restoreInputFocus(state,components,entries,current,restore,visibleRestore(entries,restore)),_ => unchanged(state))(Unit{})
def appendChanges(previous: List<&2,FocusChange>,change: Change) -> Change:
  match change:
    case Change{state,current,hideCursor,wantsRender}: Change{state,List.append(&2,FocusChange,previous,current),hideCursor,wantsRender}
def prepareNext(change: Change,components: List<&2,C.ComponentId>) -> Change:
  match change:
    case Change{state,previous,_,_}: appendChanges(previous,prepareRestore(state,components))
def prepareInput(+state: State,+components: List<&2,C.ComponentId>) -> Change:
  match state:
    case State{+entries,current,_,_,_}: prepareNext(inputFallback(state,components,byComponent(entries,current,False{}),topmost(entries,None{})),components)
