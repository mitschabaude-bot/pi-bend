import Base
import ../../../../tui/src/tui.bend as Mouse
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/scroll-view.bend as Scroll
import ../../../../tui/src/components/stack.bend as Stack
import ../../../../tui/src/layout-node.bend as Node
import ../../../../tui/src/tui-base.bend as Tui
import ./components/header.bend as Header
import ./theme/theme.bend as Theme
import ../../core/system-prompt.bend as Prompt
import ../../core/skills.bend as Skills

# The document changes as session events arrive; the editor and footer stay
# mounted. A frame paints the document's children at the current width, so
# resizes do not freeze earlier message wrapping. Frames and document changes
# are serialized: once `clear` returns, no frame still renders the removed
# children, so their owners may be disposed. Children are kept newest first:
# appending is constant time, and a frame prepends each child's lines.
# A displayed hit map stores geometry, not another copy of every callback.
# Append/flush retain message roots; clear invalidates the map before retirement.
type Height is Data: Height{component: Component.ComponentId,height: Nat}
type Heights is Data: Heights{width: Nat,children: List<&2,Height>}
type Layouts is Data:
  Layouts{all: Maybe<&2,Heights>,chat: Maybe<&2,Heights>,pending: Maybe<&2,Heights>}
type Document is Data:
  Document{newest: List<&2,Component.Component>,pending: List<&2,Component.Component>,layouts: Layouts}
type View is Type:
  View{document: Serial.Owner<Document>,header: Maybe<&1,Header.Owner>,headerHandle: Maybe<&2,Header.Handle>,exit: Ref.Ref<Maybe<&2,Bool>>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,chatRender: Component.Component,pendingRender: Component.Component,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{document: Serial.Handle<Document>,header: Maybe<&2,Header.Handle>,exit: Ref.Ref<Maybe<&2,Bool>>}
type Section is Data:
  All{}
  Chat{}
  Pending{}
type Display is Data: Display{section: Section,document: Serial.Handle<Document>,header: Maybe<&2,Component.Component>,exit: Ref.Ref<Maybe<&2,Bool>>}

def headerLines(header: Maybe<&2,Component.Component>,width: Nat) -> IO(List<&2,String>):
  match header:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{component}: Component.render(component,width)
# Build the displayed rows and their hit-test height in the same traversal.
def countedRow(row: String,result: List<&2,String> & Nat) -> List<&2,String> & Nat:
  match result:
    case Tuple{rows,height}: (row <> rows,height + 1n)
def countedAppend(rows: List<&2,String>,below: List<&2,String>) -> List<&2,String> & Nat:
  match rows:
    case Nil{}: (below,0n)
    case row <> rest: countedRow(row,countedAppend(rest,below))
def prependedResult(child: Component.Component,layout: List<&2,Height>,result: List<&2,String> & Nat,next: List<&2,String> -> List<&2,Height> -> IO(List<&2,String> & List<&2,Height>)) -> IO(List<&2,String> & List<&2,Height>):
  match result:
    case Tuple{rows,height}: next(rows)(Height{Component.id(child),height} <> layout)
def prepended(children: List<&2,Component.Component>,+width: Nat,below: List<&2,String>,layout: List<&2,Height>) -> IO(List<&2,String> & List<&2,Height>):
  match children:
    case Nil{}: IO.pure(List<&2,String> & List<&2,Height>,(below,layout))
    case +child <> older:
      do IO<List<&2,String> & List<&2,Height>>:
        lines : List<&2,String> <- Component.render(child,width)
        prependedResult(child,layout,countedAppend(lines,below),rows => layout => prepended(older,width,rows,layout))
def sectionChildren(+newest: List<&2,Component.Component>,+pending: List<&2,Component.Component>,section: Section) -> List<&2,Component.Component>:
  match section:
    case All{}: List.append(&2,Component.Component,pending,newest)
    case Chat{}: newest
    case Pending{}: pending
def remembered(section: Section,layout: Heights,layouts: Layouts) -> Layouts:
  match section layouts:
    case All{} Layouts{_,chat,pending}: Layouts{Some{layout},chat,pending}
    case Chat{} Layouts{all,_,pending}: Layouts{all,Some{layout},pending}
    case Pending{} Layouts{all,chat,_}: Layouts{all,chat,Some{layout}}
def cached(section: Section,layouts: Layouts) -> Maybe<&2,Heights>:
  match section layouts:
    case All{} Layouts{all,_,_}: all
    case Chat{} Layouts{_,chat,_}: chat
    case Pending{} Layouts{_,_,pending}: pending
def isPending(section: Section) -> Bool:
  match section:
    case Pending{}: True{}
    case _: False{}
def optionalChild(header: Maybe<&2,Component.Component>) -> List<&2,Component.Component>:
  match header:
    case Some{component}: component <> Nil{}
    case None{}: Nil{}
def headerLayout(header: Maybe<&2,Component.Component>,height: Nat) -> List<&2,Height>:
  match header:
    case Some{component}: Height{Component.id(component),height} <> Nil{}
    case None{}: Nil{}
def exitRows(lines: List<&2,String>,leaving: Maybe<&2,Bool>) -> List<&2,String>:
  match leaving:
    case Some{True{}}: List.append(&2,String,lines,"" <> Nil{})
    case _: lines
def decorate(+header: Maybe<&2,Component.Component>,+width: Nat,lines: List<&2,String>,layout: List<&2,Height>,leaving: Maybe<&2,Bool>) -> IO(List<&2,String> & List<&2,Height>):
  match leaving:
    case Some{False{}}: IO.pure(List<&2,String> & List<&2,Height>,("" <> Nil{},Nil{}))
    case _:
      do IO<List<&2,String> & List<&2,Height>>:
        +heading : List<&2,String> <- headerLines(header,width)
        headerLayout : List<&2,Height> = headerLayout(header,List.length(&2,String,heading))
        combined : List<&2,String> = List.append(&2,String,heading,lines)
        return (exitRows(combined,leaving),List.append(&2,Height,headerLayout,layout))
def published(document: Document,width: Nat,section: Section,result: List<&2,String> & List<&2,Height>) -> Document & List<&2,String>:
  match document result:
    case Document{newest,pending,layouts} Tuple{lines,children}: (Document{newest,pending,remembered(section,Heights{width,children},layouts)},lines)
def finishDocument(document: Document,+width: Nat,+section: Section,header: Maybe<&2,Component.Component>,leaving: Maybe<&2,Bool>,result: List<&2,String> & List<&2,Height>) -> IO(Document & List<&2,String>):
  match result:
    case Tuple{+lines,+layout}:
      do IO<Document & List<&2,String>>:
        decorated : List<&2,String> & List<&2,Height> <- Bool.pick(Unit -> IO(List<&2,String> & List<&2,Height>),isPending(section),_ => IO.pure(List<&2,String> & List<&2,Height>,(lines,layout)),_ => decorate(header,width,lines,layout,leaving))(Unit{})
        return published(document,width,section,decorated)
def visibleChildren(newest: List<&2,Component.Component>,pending: List<&2,Component.Component>,+section: Section,header: Maybe<&2,Component.Component>,leaving: Maybe<&2,Bool>) -> List<&2,Component.Component>:
  +roots = List.reverse(&2,Component.Component,sectionChildren(newest,pending,section))
  rootChildren = Bool.pick(List<&2,Component.Component>,isPending(section),roots,List.append(&2,Component.Component,optionalChild(header),roots))
  Bool.pick(List<&2,Component.Component>,Bool.not(isPending(section)) && Bool.not(Maybe.default(&2,Bool,leaving,True{})),Nil{},rootChildren)
def topology(document: Document,section: Section,header: Maybe<&2,Component.Component>,leaving: Maybe<&2,Bool>) -> IO(Document & List<&2,Component.Component>):
  match document:
    case Document{+newest,+pending,layouts}:
      IO.pure(Document & List<&2,Component.Component>,(Document{newest,pending,layouts},visibleChildren(newest,pending,section,header,leaving)))
def children(display: Display,_: Unit) -> IO(List<&2,Component.Component>):
  match display:
    case Display{section,document,header,exit}:
      do IO<List<&2,Component.Component>>:
        leaving : Maybe<&2,Bool> <- Ref.read(Maybe<&2,Bool>,exit)
        Serial.run(Document,List<&2,Component.Component>,document,current => topology(current,section,header,leaving))
type MouseDocument is Data:
  MouseDocument{current: List<&2,Component.Component>,available: List<&2,Component.Component>,cached: Maybe<&2,Heights>}
type Hit is Data: Hit{component: Component.ComponentId,start: Nat,height: Nat}
def mouseDocument(document: Document,+section: Section,+header: Maybe<&2,Component.Component>,leaving: Maybe<&2,Bool>) -> IO(Document & MouseDocument):
  match document:
    case Document{+newest,+pending,+layouts}:
      IO.pure(Document & MouseDocument,(Document{newest,pending,layouts},MouseDocument{visibleChildren(newest,pending,section,header,leaving),List.append(&2,Component.Component,optionalChild(header),List.append(&2,Component.Component,pending,newest)),cached(section,layouts)}))
def geometryHit(heights: List<&2,Height>,+y: Mouse.Offset,+start: Nat) -> Maybe<&2,Hit>:
  match heights:
    case Nil{}: None{}
    case Height{component,+height} <> rest:
      Bool.pick(Unit -> Maybe<&2,Hit>,Component.within(y,start,height),_ => Some{Hit{component,start,height}},_ => geometryHit(rest,y,start + height))(Unit{})
def hitComponent(component: Maybe<&2,Component.Component>,hit: Hit,event: Mouse.TuiMouseEvent) -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>):
  match component hit:
    case Some{component} Hit{_,start,height}: Component.dispatchMouseEvent(component,Component.childEvent(event,start,height))
    case None{} _: IO.pure(Maybe<&2,Component.TuiMouseDispatchResult()>,None{})
def cachedMouse(hit: Maybe<&2,Hit>,available: List<&2,Component.Component>,event: Mouse.TuiMouseEvent) -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>):
  match hit:
    case None{}: IO.pure(Maybe<&2,Component.TuiMouseDispatchResult()>,None{})
    case Some{Hit{+component,start,height}}:
      do IO<Maybe<&2,Component.TuiMouseDispatchResult()>>:
        receiver : Maybe<&2,Component.Component> <- Component.lookup(available,component)
        hitComponent(receiver,Hit{component,start,height},event)
def freshMouse(current: List<&2,Component.Component>,+event: Mouse.TuiMouseEvent,y: Mouse.Offset,width: Nat) -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>):
  do IO<Maybe<&2,Component.TuiMouseDispatchResult()>>:
    children : List<&2,Component.ChildLayout> <- Component.mouseChildren(Component.Container{current,None{}},width)
    Component.routeMouse(children,event,y,0n)
def documentMouse(document: MouseDocument,+event: Mouse.TuiMouseEvent,+y: Mouse.Offset,+width: Nat) -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>):
  match document:
    case MouseDocument{+current,available,Some{Heights{cachedWidth,heights}}}:
      Bool.pick(Unit -> IO(Maybe<&2,Component.TuiMouseDispatchResult()>),Nat.is_eq(width,cachedWidth),_ => cachedMouse(geometryHit(heights,y,0n),available,event),_ => freshMouse(current,event,y,width))(Unit{})
    case MouseDocument{current,_,None{}}: freshMouse(current,event,y,width)
def mouseRequest(display: Display,+event: Mouse.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match display event:
    case Display{section,document,header,exit} Mouse.TuiMouseEvent{_,_,_,+y,_,_,width,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        leaving : Maybe<&2,Bool> <- Ref.read(Maybe<&2,Bool>,exit)
        snapshot : MouseDocument <- Serial.run(Document,MouseDocument,document,current => mouseDocument(current,section,header,leaving))
        result : Maybe<&2,Component.TuiMouseDispatchResult()> <- documentMouse(snapshot,event,y,width)
        return Maybe.map(&2,Component.TuiMouseDispatchResult(),Component.MouseResponse(),value => Component.DispatchedResult{value},result)
def mouse(display: Display,event: Mouse.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  mouseRequest(display,event)

def section(+display: Display,id: Component.ComponentId,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>) -> IO(Component.Component):
  do IO<Component.Component>:
    +children : Callback.Callback<Unit,List<&2,Component.Component>> <- Callback.create(~Display,~Unit,~List<&2,Component.Component>,~children,display)
    mouse : Callback.Callback<Mouse.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Display,~Mouse.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,display)
    return Component.Group{Component.Component{id,render,None{},Some{mouse},invalidate,None{},False{}},children}
def paintDocument(document: Document,+width: Nat,+section: Section,header: Maybe<&2,Component.Component>,leaving: Maybe<&2,Bool>) -> IO(Document & List<&2,String>):
  match document:
    case Document{+newest,+pending,layouts}:
      do IO<Document & List<&2,String>>:
        result : List<&2,String> & List<&2,Height> <- prepended(sectionChildren(newest,pending,section),width,Nil{},Nil{})
        finishDocument(Document{newest,pending,layouts},width,section,header,leaving,result)
def draw(display: Display,width: Nat) -> IO(List<&2,String>):
  match display:
    case Display{+section,document,header,exit}:
      do IO<List<&2,String>>:
        leaving : Maybe<&2,Bool> <- Ref.read(Maybe<&2,Bool>,exit)
        Serial.run(Document,List<&2,String>,document,current => paintDocument(current,width,section,header,leaving))
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def withDocument(+id: Component.ComponentId,pair: Serial.Owner<Document> & Serial.Handle<Document>,header: Maybe<&1,Header.Owner>,+component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  match pair:
    case (document,+shared):
      do IO<View>:
        +exit : Ref.Ref<Maybe<&2,Bool>> <- Ref.new(Maybe<&2,Bool>,None{})
        +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Display,~Nat,~List<&2,String>,~draw,Display{All{},shared,component,exit})
        chatRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Display,~Nat,~List<&2,String>,~draw,Display{Chat{},shared,component,exit})
        pendingRender : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Display,~Nat,~List<&2,String>,~draw,Display{Pending{},shared,None{},exit})
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
        value : Component.Component <- section(Display{All{},shared,component,exit},id,render,invalidate)
        chat : Component.Component <- section(Display{Chat{},shared,component,exit},id,chatRender,invalidate)
        pending : Component.Component <- section(Display{Pending{},shared,None{},exit},Component.ComponentId{0n},pendingRender,invalidate)
        return View{document,header,handle,exit,value,render,chat,pending,invalidate}
def created(id: Component.ComponentId,header: Maybe<&1,Header.Owner>,component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  do IO<View>:
    document : Serial.Owner<Document> <- Serial.create(Document,Document{Nil{},Nil{},Layouts{None{},None{},None{}}})
    withDocument(id,Serial.borrow(Document,document),header,component,handle)
def create(id: Component.ComponentId) -> IO(View): created(id,None{},None{},None{})
def withHeader(id: Component.ComponentId,pair: Header.Owner & Component.Component & Header.Handle) -> IO(View):
  match pair:
    case (owner,component,handle): created(id,Some{owner},Some{component},Some{handle})
def createWithHeader(id: Component.ComponentId,theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>,themeDir: String) -> IO(View):
  do IO<View>:
    header : Header.Owner <- Header.create(theme,quiet,cwd,home,contexts,skills,themeDir)
    withHeader(id,Header.borrow(header))
def borrowedView(pair: Serial.Owner<Document> & Serial.Handle<Document>,header: Maybe<&1,Header.Owner>,+handle: Maybe<&2,Header.Handle>,+exit: Ref.Ref<Maybe<&2,Bool>>,+value: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,chatRender: Component.Component,pendingRender: Component.Component,invalidate: Callback.Callback<Unit,Unit>) -> View & Component.Component & Handle:
  match pair:
    case (document,shared): (View{document,header,handle,exit,value,render,chatRender,pendingRender,invalidate},value,Handle{shared,handle,exit})
def borrow(view: View) -> View & Component.Component & Handle:
  match view:
    case View{document,header,handle,exit,value,render,chatRender,pendingRender,invalidate}: borrowedView(Serial.borrow(Document,document),header,handle,exit,value,render,chatRender,pendingRender,invalidate)
def headerHandle(handle: Handle) -> Maybe<&2,Header.Handle>:
  match handle: case Handle{_,value,_}: value
def prepareExit(handle: Handle,hasMessages: Bool) -> IO(Unit):
  match handle: case Handle{_,_,exit}: Ref.write(Maybe<&2,Bool>,exit,Some{hasMessages})
def added(current: Document,entry: Component.Component) -> IO(Document & Unit):
  match current: case Document{newest,pending,layouts}: IO.pure(Document & Unit,(Document{entry <> newest,pending,layouts},Unit{}))
def append(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,current => added(current,entry))
# Bash commands submitted during a model run stay below later chat entries.
# The next ordinary prompt moves them into chat before its own message.
def pendingAdded(current: Document,entry: Component.Component) -> IO(Document & Unit):
  match current: case Document{newest,pending,layouts}: IO.pure(Document & Unit,(Document{newest,entry <> pending,layouts},Unit{}))
def appendPending(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,current => pendingAdded(current,entry))
def pendingFlushed(current: Document) -> IO(Document & Unit):
  match current:
    case Document{newest,pending,layouts}: IO.pure(Document & Unit,(Document{List.append(&2,Component.Component,pending,newest),Nil{},layouts},Unit{}))
def flushPending(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,pendingFlushed)
def emptied(current: Document) -> IO(Document & Unit): IO.pure(Document & Unit,(Document{Nil{},Nil{},Layouts{None{},None{},None{}}},Unit{}))
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,emptied)
def disposeHeader(header: Maybe<&1,Header.Owner>) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{owner}: Header.dispose(owner)
def disposeSection(component: Component.Component) -> IO(Unit):
  match component:
    case Component.Group{Component.Component{_,render,_,Some{mouse},_,_,_},children}:
      do IO<Unit>:
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Mouse.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouse)
        Callback.dispose(Unit,List<&2,Component.Component>,children)
    case _: IO.pure(Unit,Unit{})
def dispose(view: View) -> IO(Unit):
  match view:
    case View{document,header,_,exit,value,_,chat,pending,invalidate}:
      do IO<Unit>:
        old : Document <- Serial.retire(Document,document)
        disposeSection(value)
        disposeSection(chat)
        disposeSection(pending)
        Callback.dispose(Unit,Unit,invalidate)
        disposeHeader(header)
        oldExit : Maybe<&2,Bool> <- Ref.dispose(Maybe<&2,Bool>,exit)
        return Unit{}

# upstream widgetContainerAbove holds a Spacer(1) when no widgets are set; it
# keeps its line when the transcript overflows.
def dockEntries(editor: Component.Component,footer: Component.Component,+fullscreen: Bool) -> Node.LayoutNode:
  Node.Children{Node.child(Node.Spacer{1n},Stack.sized(None{},0n,1n,0n,1n),None{}),
    Node.Children{Node.child(Node.Leaf{editor},Stack.sized(None{},0n,1n,Bool.pick(Nat,fullscreen,3n,1n),100000n),None{}),
      Node.Children{Node.child(Node.Leaf{footer},Stack.sized(None{},0n,1n,0n,100000n),None{}),Node.Empty{}}}}
def dock(+editor: Component.Component,+footer: Component.Component,+fullscreen: Bool,pending: Maybe<&2,Component.Component>) -> Node.LayoutNode:
  match pending:
    case None{}: Node.VStack{dockEntries(editor,footer,fullscreen),0n}
    case Some{component}: Node.VStack{Node.Children{Node.child(Node.Leaf{component},Stack.sized(None{},0n,1n,0n,100000n),None{}),dockEntries(editor,footer,fullscreen)},0n}
def entries(document: Component.Component,editor: Component.Component,footer: Component.Component,+fullscreen: Bool,pending: Maybe<&2,Component.Component>) -> Node.LayoutNode:
  +scrollbar = Bool.pick(Scroll.ScrollViewScrollbar,fullscreen,Scroll.Auto{},Scroll.Hidden{})
  +scroll = Scroll.new(document,Scroll.ScrollViewOptions{Scroll.FollowEnd{},True{},Scroll.Chain{},scrollbar,1000n})
  Node.Children{Node.child(Node.ScrollNode{scroll},Stack.sized(Bool.pick(Maybe<&2,Nat>,fullscreen,Some{0n},None{}),1n,1n,Bool.pick(Nat,fullscreen,1n,0n),100000n),None{}),
    Node.Children{Node.child(dock(editor,footer,fullscreen,pending),Stack.sized(None{},0n,1n,1n,100000n),None{}),Node.Empty{}}}
def layout(+document: Component.Component,+editor: Component.Component,+footer: Component.Component) -> Node.LayoutNode:
  Node.Inline{Node.VStack{entries(document,editor,footer,False{},None{}),0n}}
def layoutFor(+document: Component.Component,+editor: Component.Component,+footer: Component.Component,fullscreen: Bool,pending: Maybe<&2,Component.Component>) -> Node.LayoutNode:
  match fullscreen:
    case False{}: layout(document,editor,footer)
    case True{}: Node.VStack{entries(document,editor,footer,True{},pending),0n}
def mountComponents(+document: Component.Component,+editor: Component.Component,+footer: Component.Component,+fullscreen: Bool,+pending: Component.Component) -> IO(Tui.ResultOf(Tui.TuiBase)):
  +base = Tui.setLayoutRoot(Tui.added(Tui.added(Tui.added(Tui.added(Tui.newTui(),document),pending),editor),footer),Some{layoutFor(document,editor,footer,fullscreen,Some{pending})})
  Tui.setFocus(base,document <> editor <> footer <> Nil{},Component.id(document) <> Component.id(editor) <> Component.id(footer) <> Nil{},Some{Component.id(editor)})
def nextId(document: Component.ComponentId,editor: Component.ComponentId,footer: Component.ComponentId) -> Component.ComponentId:
  match document editor footer:
    case Component.ComponentId{a} Component.ComponentId{b} Component.ComponentId{c}: Component.ComponentId{Nat.max(a,Nat.max(b,c)) + 1n}
def mountedSections(view: View,+document: Component.Component,handle: Handle,+editor: Component.Component,+footer: Component.Component,+fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  match view:
    case View{owner,header,headerHandle,exit,value,render,+chat,+pending,invalidate}:
      do IO<View & Handle & Tui.ResultOf(Tui.TuiBase)>:
        +pending : Component.Component = Component.withId(pending,nextId(Component.id(document),Component.id(editor),Component.id(footer)))
        result : Tui.ResultOf(Tui.TuiBase) <- mountComponents(Bool.pick(Component.Component,fullscreen,chat,document),editor,footer,fullscreen,pending)
        return (View{owner,header,headerHandle,exit,value,render,chat,pending,invalidate},handle,result)
def mountBorrowed(pair: View & Component.Component & Handle,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  match pair:
    case (view,document,handle): mountedSections(view,document,handle,editor,footer,fullscreen)
def mountFor(view: View,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountBorrowed(borrow(view),editor,footer,fullscreen)
def mount(view: View,editor: Component.Component,footer: Component.Component) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountFor(view,editor,footer,False{})
