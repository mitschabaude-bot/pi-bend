import Base
import ../../../../runtime/src/callback.bend as Callback
import ../../../../runtime/src/ref.bend as Ref
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/scroll-view.bend as Scroll
import ../../../../tui/src/components/stack.bend as Stack
import ../../../../tui/src/layout-node.bend as Node
import ../../../../tui/src/tui-base.bend as Tui

# The document changes as session events arrive; the editor and footer stay
# mounted. A frame reads one document snapshot and paints its children at the
# current width, so resizes do not freeze earlier message wrapping.
type View is Type:
  View{document: Ref.Ref<Component.Container>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{document: Ref.Ref<Component.Container>}

def displayed(pair: Component.Container & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def draw(document: Ref.Ref<Component.Container>,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    current : Component.Container <- Ref.read(Component.Container,document)
    pair : Component.Container & List<&2,String> <- Component.renderContainer(current,width)
    return displayed(pair)
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def create(id: Component.ComponentId) -> IO(View):
  do IO<View>:
    +document : Ref.Ref<Component.Container> <- Ref.new(Component.Container,Component.new())
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<Component.Container>,~Nat,~List<&2,String>,~draw,document)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return View{document,Component.Component{id,render,None{},None{},invalidate,None{},False{}},render,invalidate}
def borrow(view: View) -> View & Component.Component & Handle:
  match view:
    case View{+document,+value,render,invalidate}: (View{document,value,render,invalidate},value,Handle{document})
def added(current: Component.Container,entry: Component.Component) -> Component.Container & Unit:
  (Component.addChild(current,entry),Unit{})
def append(handle: Handle,entry: Component.Component) -> IO(Unit):
  match handle:
    case Handle{document}: Ref.modify(Component.Container,Unit,document,current => added(current,entry))
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{document}: Ref.write(Component.Container,document,Component.new())
def dispose(view: View) -> IO(Unit):
  match view:
    case View{document,_,render,invalidate}:
      do IO<Unit>:
        old : Component.Container <- Ref.dispose(Component.Container,document)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)

def entries(document: Component.Component,editor: Component.Component,footer: Component.Component) -> Node.LayoutNode:
  +scroll = Scroll.new(document,Scroll.ScrollViewOptions{Scroll.FollowEnd{},True{},Scroll.Chain{},Scroll.Hidden{},1000n})
  Node.Children{Node.child(Node.ScrollNode{scroll},Stack.sized(Some{0n},1n,1n,0n,100000n),None{}),
    Node.Children{Node.child(Node.Leaf{editor},Stack.defaultSize(),None{}),
      Node.Children{Node.child(Node.Leaf{footer},Stack.defaultSize(),None{}),Node.Empty{}}}}
def layout(+document: Component.Component,+editor: Component.Component,+footer: Component.Component) -> Node.LayoutNode:
  Node.VStack{entries(document,editor,footer),0n}
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
