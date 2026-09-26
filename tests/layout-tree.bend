import Base
import ../packages/tui/src/layout-node.bend as N
import ../packages/tui/src/layout-tree.bend as T
import ../packages/tui/src/layout.bend as L
import ../packages/tui/src/components/stack.bend as S
import ../packages/tui/src/components/scroll-view.bend as Scroll
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/callback.bend as Callback

def draw(lines: List<&2,String>,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,lines)
def ignore(context: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def component(id: Nat,renderer: Callback.Callback<Nat,List<&2,String>>,invalidator: Callback.Callback<Unit,Unit>) -> C.Component:
  C.Component{C.ComponentId{id},renderer,None{},None{},invalidator,None{},False{}}
def two(first: N.LayoutNode,second: N.LayoutNode) -> N.LayoutNode: N.Children{first,N.Children{second,N.Empty{}}}
def four(a: N.LayoutNode,b: N.LayoutNode,c: N.LayoutNode,d: N.LayoutNode) -> N.LayoutNode: N.Children{a,N.Children{b,N.Children{c,N.Children{d,N.Empty{}}}}}
def child(component: C.Component,size: S.StackEntryOptions) -> N.LayoutNode: N.child(N.Leaf{component},size,None{})
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: U.trimEnd(U.stripTerminalSequences(line))
    case line <> rest: U.trimEnd(U.stripTerminalSequences(line)) ++ "|" ++ clean(rest)
def heights(boxes: List<&2,L.LayoutBox>) -> String:
  match boxes:
    case Nil{}: ""
    case L.LayoutBox{_,L.LayoutRect{_,_,_,height},_,_,_,_,_} <> Nil{}: Nat.show(height)
    case L.LayoutBox{_,L.LayoutRect{_,_,_,height},_,_,_,_,_} <> rest: Nat.show(height) ++ "," ++ heights(rest)
def report(value: T.TreeFrame) -> IO(Unit):
  match value:
    case T.TreeFrame{_,L.LayoutFrame{L.LayoutBox{_,_,_,children,_,_,_},_,_,lines}}:
      IO.print("nested:" ++ heights(children) ++ ":[" ++ clean(lines) ++ "]")
def horizontal(value: T.TreeFrame) -> IO(Unit):
  match value:
    case T.TreeFrame{_,L.LayoutFrame{L.LayoutBox{_,_,_,children,_,_,_},_,_,lines}}:
      IO.print("horizontal:" ++ heights(children) ++ ":[" ++ clean(lines) ++ "]")
def main() -> IO(Unit):
  do IO<Unit>:
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +bodyDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"body" <> Nil{})
    +topDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"top1" <> "top2" <> "top3" <> Nil{})
    +selectorDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"selector" <> Nil{})
    +belowDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"below" <> Nil{})
    +footerDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"footer" <> Nil{})
    +body : C.Component <- IO.pure(C.Component,component(1n,bodyDraw,invalidator))
    +top : C.Component <- IO.pure(C.Component,component(2n,topDraw,invalidator))
    +selector : C.Component <- IO.pure(C.Component,component(3n,selectorDraw,invalidator))
    +below : C.Component <- IO.pure(C.Component,component(4n,belowDraw,invalidator))
    +footer : C.Component <- IO.pure(C.Component,component(5n,footerDraw,invalidator))
    +dock : N.LayoutNode <- IO.pure(N.LayoutNode,N.VStack{four(child(top,S.defaultSize()),child(selector,S.sized(None{},0n,1n,3n,10n)),child(below,S.defaultSize()),child(footer,S.sized(None{},0n,1n,1n,10n))),0n})
    +root : N.LayoutNode <- IO.pure(N.LayoutNode,N.VStack{two(child(body,S.sized(Some{0n},1n,1n,1n,10n)),N.child(dock,S.sized(None{},0n,1n,1n,10n),None{})),0n})
    frame : T.TreeFrame <- T.renderTreeFrame(root,10n,9n)
    report(frame)
    +leftDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"left" <> Nil{})
    +rightDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"right" <> Nil{})
    +left : C.Component <- IO.pure(C.Component,component(6n,leftDraw,invalidator))
    +right : C.Component <- IO.pure(C.Component,component(7n,rightDraw,invalidator))
    +row : N.LayoutNode <- IO.pure(N.LayoutNode,N.HStack{two(child(left,S.sized(Some{6n},0n,0n,0n,10n)),child(right,S.sized(Some{6n},0n,0n,0n,10n))),0n,S.Start{}})
    rowFrame : T.TreeFrame <- T.renderTreeFrame(row,12n,1n)
    horizontal(rowFrame)
    +scrollDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"one" <> "two" <> "three" <> Nil{})
    +dockDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"dock" <> Nil{})
    +scrollChild : C.Component <- IO.pure(C.Component,component(8n,scrollDraw,invalidator))
    +dockChild : C.Component <- IO.pure(C.Component,component(9n,dockDraw,invalidator))
    +view : Scroll.ScrollView <- IO.pure(Scroll.ScrollView,Scroll.new(scrollChild,Scroll.defaults()))
    +scrollRoot : N.LayoutNode <- IO.pure(N.LayoutNode,N.VStack{two(N.child(N.ScrollNode{view},S.sized(Some{0n},1n,1n,0n,10n),None{}),child(dockChild,S.defaultSize())),0n})
    scrollFrame : T.TreeFrame <- T.renderTreeFrame(scrollRoot,10n,3n)
    horizontal(scrollFrame)
    # Regular document overflow must survive a full-height picker and shrink.
    +inlineRoot : N.LayoutNode <- IO.pure(N.LayoutNode,N.Inline{N.VStack{two(N.child(N.ScrollNode{view},S.defaultSize(),None{}),child(dockChild,S.defaultSize())),0n}})
    inlineFrame : T.TreeFrame <- T.renderTreeFrame(inlineRoot,10n,3n)
    horizontal(inlineFrame)
    +shortRoot : N.LayoutNode <- IO.pure(N.LayoutNode,N.Inline{N.VStack{two(child(body,S.defaultSize()),child(dockChild,S.defaultSize())),0n}})
    shortFrame : T.TreeFrame <- T.renderTreeFrame(shortRoot,10n,3n)
    horizontal(shortFrame)
    leafFrame : T.TreeFrame <- T.renderTreeFrame(N.Inline{N.Leaf{scrollChild}},10n,2n)
    horizontal(leafFrame)
    Callback.dispose(Nat,List<&2,String>,bodyDraw)
    Callback.dispose(Nat,List<&2,String>,topDraw)
    Callback.dispose(Nat,List<&2,String>,selectorDraw)
    Callback.dispose(Nat,List<&2,String>,belowDraw)
    Callback.dispose(Nat,List<&2,String>,footerDraw)
    Callback.dispose(Nat,List<&2,String>,leftDraw)
    Callback.dispose(Nat,List<&2,String>,rightDraw)
    Callback.dispose(Nat,List<&2,String>,scrollDraw)
    Callback.dispose(Nat,List<&2,String>,dockDraw)
    Callback.dispose(Unit,Unit,invalidator)
