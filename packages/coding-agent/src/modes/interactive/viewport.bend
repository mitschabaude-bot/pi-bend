import Base
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/ref.bend as Ref
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
# mounted. A frame reads one document snapshot and paints its children at the
# current width, so resizes do not freeze earlier message wrapping.
type View is Type:
  View{document: Ref.Ref<Component.Container>,header: Maybe<&1,Header.Owner>,headerHandle: Maybe<&2,Header.Handle>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{document: Ref.Ref<Component.Container>,header: Maybe<&2,Header.Handle>}
type Display is Data: Display{document: Ref.Ref<Component.Container>,header: Maybe<&2,Component.Component>}

def displayed(pair: Component.Container & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def headerLines(header: Maybe<&2,Component.Component>,width: Nat) -> IO(List<&2,String>):
  match header:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{component}: Component.render(component,width)
def draw(display: Display,width: Nat) -> IO(List<&2,String>):
  match display:
    case Display{document,header}:
      do IO<List<&2,String>>:
        +size : Nat <- IO.pure(Nat,width)
        current : Component.Container <- Ref.read(Component.Container,document)
        pair : Component.Container & List<&2,String> <- Component.renderContainer(current,size)
        heading : List<&2,String> <- headerLines(header,size)
        return List.append(&2,String,heading,displayed(pair))
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def created(id: Component.ComponentId,header: Maybe<&1,Header.Owner>,component: Maybe<&2,Component.Component>,handle: Maybe<&2,Header.Handle>) -> IO(View):
  do IO<View>:
    +document : Ref.Ref<Component.Container> <- Ref.new(Component.Container,Component.new())
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Display,~Nat,~List<&2,String>,~draw,Display{document,component})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return View{document,header,handle,Component.Component{id,render,None{},None{},invalidate,None{},False{}},render,invalidate}
def create(id: Component.ComponentId) -> IO(View): created(id,None{},None{},None{})
def withHeader(id: Component.ComponentId,pair: Header.Owner & Component.Component & Header.Handle) -> IO(View):
  match pair:
    case (owner,component,handle): created(id,Some{owner},Some{component},Some{handle})
def createWithHeader(id: Component.ComponentId,theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>) -> IO(View):
  do IO<View>:
    header : Header.Owner <- Header.create(theme,quiet,cwd,home,contexts,skills)
    withHeader(id,Header.borrow(header))
def borrow(view: View) -> View & Component.Component & Handle:
  match view:
    case View{+document,header,+handle,+value,render,invalidate}: (View{document,header,handle,value,render,invalidate},value,Handle{document,handle})
def headerHandle(handle: Handle) -> Maybe<&2,Header.Handle>:
  match handle: case Handle{_,value}: value
def added(current: Component.Container,entry: Component.Component) -> Component.Container & Unit:
  (Component.addChild(current,entry),Unit{})
def append(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document,_}: Ref.modify(Component.Container,Unit,document,current => added(current,entry))
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document,_}: Ref.write(Component.Container,document,Component.new())
def disposeHeader(header: Maybe<&1,Header.Owner>) -> IO(Unit):
  match header:
    case None{}: IO.pure(Unit,Unit{})
    case Some{owner}: Header.dispose(owner)
def dispose(view: View) -> IO(Unit):
  match view:
    case View{document,header,_,_,render,invalidate}:
      do IO<Unit>:
        old : Component.Container <- Ref.dispose(Component.Container,document)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        disposeHeader(header)

def entries(document: Component.Component,editor: Component.Component,footer: Component.Component) -> Node.LayoutNode:
  +scroll = Scroll.new(document,Scroll.ScrollViewOptions{Scroll.FollowEnd{},True{},Scroll.Chain{},Scroll.Hidden{},1000n})
  Node.Children{Node.child(Node.ScrollNode{scroll},Stack.sized(None{},1n,1n,0n,100000n),None{}),
    Node.Children{Node.child(Node.Spacer{1n},Stack.sized(None{},0n,1n,0n,1n),None{}),
      Node.Children{Node.child(Node.Leaf{editor},Stack.sized(None{},0n,0n,1n,100000n),None{}),
        Node.Children{Node.child(Node.Leaf{footer},Stack.sized(None{},0n,0n,1n,100000n),None{}),Node.Empty{}}}}}
def layout(+document: Component.Component,+editor: Component.Component,+footer: Component.Component) -> Node.LayoutNode:
  Node.Inline{Node.VStack{entries(document,editor,footer),0n}}
def mountComponents(+document: Component.Component,+editor: Component.Component,+footer: Component.Component) -> IO(Tui.ResultOf(Tui.TuiBase)):
  +base = Tui.setLayoutRoot(Tui.added(Tui.added(Tui.added(Tui.newTui(),document),editor),footer),Some{layout(document,editor,footer)})
  Tui.setFocus(base,document <> editor <> footer <> Nil{},Component.id(document) <> Component.id(editor) <> Component.id(footer) <> Nil{},Some{Component.id(editor)})
def mountBorrowed(pair: View & Component.Component & Handle,editor: Component.Component,footer: Component.Component) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  match pair:
    case (view,document,handle):
      do IO<View & Handle & Tui.ResultOf(Tui.TuiBase)>:
        result : Tui.ResultOf(Tui.TuiBase) <- mountComponents(document,editor,footer)
        return (view,handle,result)
def mount(view: View,editor: Component.Component,footer: Component.Component) -> IO(View & Handle & Tui.ResultOf(Tui.TuiBase)):
  mountBorrowed(borrow(view),editor,footer)
