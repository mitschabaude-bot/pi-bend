import Base
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
type Document is Data: Document{newest: List<&2,Component.Component>,pending: List<&2,Component.Component>}
type View is Type:
  View{document: Serial.Owner<Document>,header: Maybe<&1,Header.Owner>,headerHandle: Maybe<&2,Header.Handle>,exit: Ref.Ref<Maybe<&2,Bool>>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,chatRender: Callback.Callback<Nat,List<&2,String>>,pendingRender: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
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
def prepended(children: List<&2,Component.Component>,+width: Nat,below: List<&2,String>) -> IO(List<&2,String>):
  match children:
    case Nil{}: IO.pure(List<&2,String>,below)
    case child <> older:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- Component.render(child,width)
        prepended(older,width,List.append(&2,String,lines,below))
def renderedDocument(document: Document,+width: Nat,section: Section) -> IO(Document & List<&2,String>):
  match document section:
    case Document{+newest,+pending} All{}:
      do IO<Document & List<&2,String>>:
        below : List<&2,String> <- prepended(pending,width,Nil{})
        lines : List<&2,String> <- prepended(newest,width,below)
        return (Document{newest,pending},lines)
    case Document{+newest,pending} Chat{}:
      do IO<Document & List<&2,String>>:
        lines : List<&2,String> <- prepended(newest,width,Nil{})
        return (Document{newest,pending},lines)
    case Document{newest,+pending} Pending{}:
      do IO<Document & List<&2,String>>:
        lines : List<&2,String> <- prepended(pending,width,Nil{})
        return (Document{newest,pending},lines)
def exitLines(header: Maybe<&2,Component.Component>,width: Nat,lines: List<&2,String>,leaving: Maybe<&2,Bool>) -> IO(List<&2,String>):
  match leaving:
    case Some{False{}}: IO.pure(List<&2,String>,"" <> Nil{})
    case Some{True{}}:
      do IO<List<&2,String>>:
        heading : List<&2,String> <- headerLines(header,width)
        return List.append(&2,String,List.append(&2,String,heading,lines),"" <> Nil{})
    case None{}:
      do IO<List<&2,String>>:
        heading : List<&2,String> <- headerLines(header,width)
        return List.append(&2,String,heading,lines)
def isPending(section: Section) -> Bool:
  match section:
    case Pending{}: True{}
    case _: False{}
def draw(display: Display,width: Nat) -> IO(List<&2,String>):
  match display:
    case Display{+section,document,header,exit}:
      do IO<List<&2,String>>:
        +size : Nat <- IO.pure(Nat,width)
        +lines : List<&2,String> <- Serial.run(Document,List<&2,String>,document,current => renderedDocument(current,size,section))
        leaving : Maybe<&2,Bool> <- Ref.read(Maybe<&2,Bool>,exit)
        Bool.pick(Unit -> IO(List<&2,String>),isPending(section),_ => IO.pure(List<&2,String>,lines),_ => exitLines(header,size,lines,leaving))(Unit{})
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
        return View{document,header,handle,exit,Component.Component{id,render,None{},None{},invalidate,None{},False{}},render,chatRender,pendingRender,invalidate}
def created(id: Component.ComponentId,header: Maybe<&1,Header.Owner>,component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  do IO<View>:
    document : Serial.Owner<Document> <- Serial.create(Document,Document{Nil{},Nil{}})
    withDocument(id,Serial.borrow(Document,document),header,component,handle)
def create(id: Component.ComponentId) -> IO(View): created(id,None{},None{},None{})
def withHeader(id: Component.ComponentId,pair: Header.Owner & Component.Component & Header.Handle) -> IO(View):
  match pair:
    case (owner,component,handle): created(id,Some{owner},Some{component},Some{handle})
def createWithHeader(id: Component.ComponentId,theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>,themeDir: String) -> IO(View):
  do IO<View>:
    header : Header.Owner <- Header.create(theme,quiet,cwd,home,contexts,skills,themeDir)
    withHeader(id,Header.borrow(header))
def borrowedView(pair: Serial.Owner<Document> & Serial.Handle<Document>,header: Maybe<&1,Header.Owner>,+handle: Maybe<&2,Header.Handle>,+exit: Ref.Ref<Maybe<&2,Bool>>,+value: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,chatRender: Callback.Callback<Nat,List<&2,String>>,pendingRender: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>) -> View & Component.Component & Handle:
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
  match current: case Document{newest,pending}: IO.pure(Document & Unit,(Document{entry <> newest,pending},Unit{}))
def append(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,current => added(current,entry))
# Bash commands submitted during a model run stay below later chat entries.
# The next ordinary prompt moves them into chat before its own message.
def pendingAdded(current: Document,entry: Component.Component) -> IO(Document & Unit):
  match current: case Document{newest,pending}: IO.pure(Document & Unit,(Document{newest,entry <> pending},Unit{}))
def appendPending(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,current => pendingAdded(current,entry))
def pendingFlushed(current: Document) -> IO(Document & Unit):
  match current:
    case Document{newest,pending}: IO.pure(Document & Unit,(Document{List.append(&2,Component.Component,pending,newest),Nil{}},Unit{}))
def flushPending(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,pendingFlushed)
def emptied(current: Document) -> IO(Document & Unit): IO.pure(Document & Unit,(Document{Nil{},Nil{}},Unit{}))
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_,_}: Serial.run(Document,Unit,document,emptied)
def disposeHeader(header: Maybe<&1,Header.Owner>) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{owner}: Header.dispose(owner)
def dispose(view: View) -> IO(Unit):
  match view:
    case View{document,header,_,exit,_,render,chatRender,pendingRender,invalidate}:
      do IO<Unit>:
        old : Document <- Serial.retire(Document,document)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Nat,List<&2,String>,chatRender)
        Callback.dispose(Nat,List<&2,String>,pendingRender)
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
  match view document:
    case View{owner,header,headerHandle,exit,value,render,+chatRender,+pendingRender,+invalidate} Component.Component{+id,combined,input,mouse,_,focused,release}:
      do IO<View & Handle & Tui.ResultOf(Tui.TuiBase)>:
        +chat : Component.Component <- IO.pure(Component.Component,Component.Component{id,Bool.pick(Callback.Callback<Nat,List<&2,String>>,fullscreen,chatRender,combined),input,mouse,invalidate,focused,release})
        pending : Component.Component <- IO.pure(Component.Component,Component.Component{nextId(id,Component.id(editor),Component.id(footer)),pendingRender,None{},None{},invalidate,None{},False{}})
        result : Tui.ResultOf(Tui.TuiBase) <- mountComponents(chat,editor,footer,fullscreen,pending)
        return (View{owner,header,headerHandle,exit,value,render,chatRender,pendingRender,invalidate},handle,result)
def mountBorrowed(pair: View & Component.Component & Handle,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  match pair:
    case (view,document,handle): mountedSections(view,document,handle,editor,footer,fullscreen)
def mountFor(view: View,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountBorrowed(borrow(view),editor,footer,fullscreen)
def mount(view: View,editor: Component.Component,footer: Component.Component) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountFor(view,editor,footer,False{})
