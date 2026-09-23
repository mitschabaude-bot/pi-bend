import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as V
import ../packages/coding-agent/src/core/session-manager.bend as Tree
import ../packages/coding-agent/src/core/tools/index.bend as Tools
import ../packages/coding-agent/src/modes/interactive/components/session-selector.bend as Selector

def entry(id: String,parent: Maybe<&2,String>,text: String) -> Selector.Entry():
  Tree.SessionMessageEntry{Tree.SessionEntryBase{id,parent,"2025-01-01T00:00:00Z"},Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},F.fromU32(1)}}}}
def node(value: Selector.Entry(),children: List<&2,Selector.Node()>) -> Selector.Node():
  Tree.SessionTreeNode{value,children,None{},None{}}
def expect(value: Maybe<&2,String>,wanted: String) -> IO(Unit):
  match value:
    case Some{+found}: Bool.pick(Unit -> IO(Unit),String.eq(found,wanted),_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,"wrong selected entry: " ++ found))(Unit{})
    case None{}: IO.die(Unit,1,"missing selected entry")
def main() -> IO(Unit):
  do IO<Unit>:
    +first : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u1",None{},"first"))
    +second : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u2",Some{"u1"},"second"))
    +branch : Selector.Entry() <- IO.pure(Selector.Entry(),entry("u3",Some{"u1"},"branch"))
    +tree : List<&2,Selector.Node()> <- IO.pure(List<&2,Selector.Node()>,node(first,node(second,Nil{}) <> node(branch,Nil{}) <> Nil{}) <> Nil{})
    +shown : Selector.State <- IO.pure(Selector.State,Selector.create(tree,Some{"u3"},Selector.TreeMode{},24n))
    check0 : Unit <- expect(Selector.selectedId(shown),"u3")
    check1 : Unit <- expect(Selector.selectedId(Selector.move(shown,True{})),"u1")
    +fork : Selector.State <- IO.pure(Selector.State,Selector.createFork(first <> second <> branch <> Nil{},24n))
    check2 : Unit <- expect(Selector.selectedId(fork),"u3")
    check3 : Unit <- expect(Selector.selectedId(Selector.move(fork,True{})),"u2")
    IO.print("tree active branch and chronological fork selection: ok")
