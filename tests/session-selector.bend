import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/session-manager.bend as Tree
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/components/tree-selector.bend as Selector

def entry(id: String,parent: Maybe<&2,String>,text: String) -> Selector.Entry():
  Tree.SessionMessageEntry{Tree.SessionEntryBase{id,parent,"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F.fromU32(1)}}}}
def node(value: Selector.Entry(),children: List<&2,Selector.Node()>) -> Selector.Node():
  Tree.SessionTreeNode{value,children,None{},None{}}
def expect(value: Maybe<&2,String>,wanted: String) -> IO(Unit):
  match value:
    case Some{+found}: Bool.pick(Unit -> IO(Unit),String.eq(found,wanted),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong selected entry: " ++ found))(Unit{})
    case None{}: IO.die(Unit,1,"missing selected entry")
def expectCount(state: Selector.TreeList,wanted: Nat) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),Nat.is_eq(List.length(&2,Selector.Row,Selector.visibleOf(state)),wanted),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong visible row count"))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    +first : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u1",None{},"first"))
    +second : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u2",Some{"u1"},"second"))
    +branch : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u3",Some{"u1"},"branch"))
    +tree : List<&2,Selector.Node()> <- IO.pure(List<&2,Selector.Node()>,node(first,node(second,Nil{}) <> node(branch,Nil{}) <> Nil{}) <> Nil{})
    +shown : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.create(tree,Some{"u3"},24n))
    check0 : Unit <- expect(Selector.selectedId(shown),"u3")
    check1 : Unit <- expect(Selector.selectedId(Selector.move(shown,True{})),"u1")
    +searched : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.withSearch(shown,"USER BRANCH"))
    check4 : Unit <- expect(Selector.selectedId(searched),"u3")
    checkSearch : Unit <- expectCount(searched,1n)
    checkNearest : Unit <- expect(Selector.selectedId(Selector.withSearch(shown,"FIRST")),"u1")
    checkPage : Unit <- expect(Selector.selectedId(Selector.page(shown,True{})),"u1")
    +filtered : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.withFilter(shown,Selector.UserOnly{},True{}))
    checkFilter : Unit <- expectCount(filtered,3n)
    checkCycle : Unit <- expectCount(Selector.withFilter(filtered,Selector.nextFilter(Selector.filterOf(filtered)),False{}),0n)
    checkSegmentUp : Unit <- expect(Selector.selectedId(Selector.fold(shown,True{})),"u1")
    checkSegmentDown : Unit <- expect(Selector.selectedId(Selector.fold(Selector.fold(shown,True{}),False{})),"u3")
    +hidden : Selector.Entry() <- IO.pure(Selector.Entry(),Tree.LabelEntry{Tree.SessionEntryBase{"l1",Some{"u1"},"2025-01-01T00:00:00Z"},"u1",Some{"work"}})
    +filteredTree : List<&2,Selector.Node()> <- IO.pure(List<&2,Selector.Node()>,node(first,node(hidden,node(second,Nil{}) <> Nil{}) <> node(branch,Nil{}) <> Nil{}) <> Nil{})
    +throughHidden : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.create(filteredTree,Some{"u2"},24n))
    checkVisibleParent : Unit <- expect(Selector.selectedId(Selector.fold(throughHidden,True{})),"u1")
    checkVisibleChild : Unit <- expect(Selector.selectedId(Selector.fold(Selector.fold(throughHidden,True{}),False{})),"u2")
    +collapsed : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.fold(Selector.move(shown,True{}),True{}))
    check5 : Unit <- expect(Selector.selectedId(Selector.move(collapsed,False{})),"u1")
    +expanded : Selector.TreeList <- IO.pure(Selector.TreeList,Selector.fold(collapsed,False{}))
    check6 : Unit <- expect(Selector.selectedId(Selector.move(expanded,False{})),"u3")
    IO.print("tree search, filter, fold, page, and branch segments: ok")
