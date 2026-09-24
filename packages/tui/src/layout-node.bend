import Base
import ./component.bend as C
import ./components/stack.bend as Stack
import ./components/scroll-view.bend as Scroll
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
