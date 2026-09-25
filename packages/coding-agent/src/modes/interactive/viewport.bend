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
type Document is Data: Document{newest: List<&2,Component.Component>}
type View is Type:
  View{document: Serial.Owner<Document>,header: Maybe<&1,Header.Owner>,headerHandle: Maybe<&2,Header.Handle>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{document: Serial.Handle<Document>,header: Maybe<&2,Header.Handle>}
type Display is Data: Display{document: Serial.Handle<Document>,header: Maybe<&2,Component.Component>}

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
def renderedDocument(document: Document,+width: Nat) -> IO(Document & List<&2,String>):
  match document:
    case Document{+newest}:
      do IO<Document & List<&2,String>>:
        lines : List<&2,String> <- prepended(newest,width,Nil{})
        return (Document{newest},lines)
def draw(display: Display,width: Nat) -> IO(List<&2,String>):
  match display:
    case Display{document,header}:
      do IO<List<&2,String>>:
        +size : Nat <- IO.pure(Nat,width)
        lines : List<&2,String> <- Serial.run(Document,List<&2,String>,document,current => renderedDocument(current,size))
        heading : List<&2,String> <- headerLines(header,size)
        return List.append(&2,String,heading,lines)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def withDocument(id: Component.ComponentId,pair: Serial.Owner<Document> & Serial.Handle<Document>,header: Maybe<&1,Header.Owner>,component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  match pair:
    case (document,+shared):
      do IO<View>:
        +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Display,~Nat,~List<&2,String>,~draw,Display{shared,component})
        +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
        return View{document,header,handle,Component.Component{id,render,None{},None{},invalidate,None{},False{}},render,invalidate}
def created(id: Component.ComponentId,header: Maybe<&1,Header.Owner>,component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  do IO<View>:
    document : Serial.Owner<Document> <- Serial.create(Document,Document{Nil{}})
    withDocument(id,Serial.borrow(Document,document),header,component,handle)
def create(id: Component.ComponentId) -> IO(View): created(id,None{},None{},None{})
def withHeader(id: Component.ComponentId,pair: Header.Owner & Component.Component & Header.Handle) -> IO(View):
  match pair:
    case (owner,component,handle): created(id,Some{owner},Some{component},Some{handle})
def createWithHeader(id: Component.ComponentId,theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>) -> IO(View):
  do IO<View>:
    header : Header.Owner <- Header.create(theme,quiet,cwd,home,contexts,skills)
    withHeader(id,Header.borrow(header))
def borrowedView(pair: Serial.Owner<Document> & Serial.Handle<Document>,header: Maybe<&1,Header.Owner>,+handle: Maybe<&2,Header.Handle>,+value: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>) -> View & Component.Component & Handle:
  match pair:
    case (document,shared): (View{document,header,handle,value,render,invalidate},value,Handle{shared,handle})
def borrow(view: View) -> View & Component.Component & Handle:
  match view:
    case View{document,header,handle,value,render,invalidate}: borrowedView(Serial.borrow(Document,document),header,handle,value,render,invalidate)
def headerHandle(handle: Handle) -> Maybe<&2,Header.Handle>:
  match handle: case Handle{_,value}: value
def added(current: Document,entry: Component.Component) -> IO(Document & Unit):
  match current: case Document{newest}: IO.pure(Document & Unit,(Document{entry <> newest},Unit{}))
def append(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_}: Serial.run(Document,Unit,document,current => added(current,entry))
def emptied(current: Document) -> IO(Document & Unit): IO.pure(Document & Unit,(Document{Nil{}},Unit{}))
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_}: Serial.run(Document,Unit,document,emptied)
def disposeHeader(header: Maybe<&1,Header.Owner>) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{owner}: Header.dispose(owner)
def dispose(view: View) -> IO(Unit):
  match view:
    case View{document,header,_,_,render,invalidate}:
      do IO<Unit>:
        old : Document <- Serial.retire(Document,document)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        disposeHeader(header)

# upstream widgetContainerAbove holds a Spacer(1) when no widgets are set; it
# keeps its line when the transcript overflows.
def entries(document: Component.Component,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> Node.LayoutNode:
  +scrollbar = Bool.pick(Scroll.ScrollViewScrollbar,fullscreen,Scroll.Auto{},Scroll.Hidden{})
  +scroll = Scroll.new(document,Scroll.ScrollViewOptions{Scroll.FollowEnd{},True{},Scroll.Chain{},scrollbar,1000n})
  Node.Children{Node.child(Node.ScrollNode{scroll},Stack.sized(None{},1n,1n,0n,100000n),None{}),
    Node.Children{Node.child(Node.Spacer{1n},Stack.sized(None{},0n,0n,1n,1n),None{}),
      Node.Children{Node.child(Node.Leaf{editor},Stack.sized(None{},0n,0n,1n,100000n),None{}),
        Node.Children{Node.child(Node.Leaf{footer},Stack.sized(None{},0n,0n,1n,100000n),None{}),Node.Empty{}}}}}
def layout(+document: Component.Component,+editor: Component.Component,+footer: Component.Component) -> Node.LayoutNode:
  Node.Inline{Node.VStack{entries(document,editor,footer,False{}),0n}}
def layoutFor(+document: Component.Component,+editor: Component.Component,+footer: Component.Component,fullscreen: Bool) -> Node.LayoutNode:
  match fullscreen:
    case False{}: layout(document,editor,footer)
    case True{}: Node.VStack{entries(document,editor,footer,True{}),0n}
def mountComponents(+document: Component.Component,+editor: Component.Component,+footer: Component.Component,fullscreen: Bool) -> IO(Tui.ResultOf(Tui.TuiBase)):
  +base = Tui.setLayoutRoot(Tui.added(Tui.added(Tui.added(Tui.newTui(),document),editor),footer),Some{layoutFor(document,editor,footer,fullscreen)})
  Tui.setFocus(base,document <> editor <> footer <> Nil{},Component.id(document) <> Component.id(editor) <> Component.id(footer) <> Nil{},Some{Component.id(editor)})
def mountBorrowed(pair: View & Component.Component & Handle,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  match pair:
    case (view,document,handle):
      do IO<View & Handle & Tui.ResultOf(Tui.TuiBase)>:
        result : Tui.ResultOf(Tui.TuiBase) <- mountComponents(document,editor,footer,fullscreen)
        return (view,handle,result)
def mountFor(view: View,editor: Component.Component,footer: Component.Component,fullscreen: Bool) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountBorrowed(borrow(view),editor,footer,fullscreen)
def mount(view: View,editor: Component.Component,footer: Component.Component) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountFor(view,editor,footer,False{})
