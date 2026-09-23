import Base
import ../src/cli/session-picker.bend as Picker
import ../src/core/session-manager.bend as Session

# Disconnected cycles and orphaned parents stay selectable once each; ordinary
# parent/child paths receive the same branch glyphs as the upstream picker.
def info(+id: String,parent: Maybe<&2,String>) -> Session.SessionInfo:
  Session.SessionInfo{"/sessions/" ++ id,id,"/project",None{},parent,U32.to_f64(1),U32.to_f64(2),1n,id,id}
def sample() -> List<&2,Session.SessionInfo>:
  [info("root",None{}),info("child",Some{"/sessions/root"}),info("orphan",Some{"/sessions/missing"}),info("cycle-a",Some{"/sessions/cycle-b"}),info("cycle-b",Some{"/sessions/cycle-a"})]
def siblings() -> List<&2,Session.SessionInfo>:
  [info("root",None{}),info("first",Some{"/sessions/root"}),info("grandchild",Some{"/sessions/first"}),info("last",Some{"/sessions/root"})]
def ids(items: List<&2,Session.SessionInfo>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case Session.SessionInfo{_,id,_,_,_,_,_,_,_,_} <> rest: id <> ids(rest)
def check(ok: Bool,message: String) -> IO(Unit):
  Bool.pick(IO(Unit),ok,IO.pure(Unit,Unit{}),IO.die(Unit,1,message))
def main() -> IO(Unit):
  do IO<Unit>:
    check(String.eq(String.join(ids(Picker.threaded(sample())),","),"root,child,orphan,cycle-a,cycle-b"),"threaded traversal lost or duplicated an orphan/cycle")
    check(String.eq(Picker.treePrefix(info("child",Some{"/sessions/root"}),sample()),"   └─ "),"child branch prefix")
    check(String.eq(Picker.treePrefix(info("first",Some{"/sessions/root"}),siblings()),"   ├─ "),"first sibling branch prefix")
    check(String.eq(Picker.treePrefix(info("grandchild",Some{"/sessions/first"}),siblings()),"   │  └─ "),"ancestor rail prefix")
    check(String.eq(Picker.treePrefix(info("orphan",Some{"/sessions/missing"}),sample()),""),"orphan should display flat")
    check(String.eq(Picker.treePrefix(info("cycle-a",Some{"/sessions/cycle-b"}),sample()),""),"cycle should display flat")
    check(String.eq(String.join(ids(Picker.arranged(sample(),"\"cycle-a\"",Picker.Recent{})),","),"cycle-a"),"quoted exact phrase search")
    check(String.eq(String.join(ids(Picker.arranged(sample(),"re:^child ",Picker.Recent{})),","),"child"),"case-insensitive regex search")
    check(List.is_empty(&2,Session.SessionInfo,Picker.arranged(sample(),"re:[",Picker.Recent{})),"invalid regex should not match")
    check(List.is_empty(&2,Session.SessionInfo,Picker.arranged(sample(),"re:",Picker.Recent{})),"empty regex should not match")
    check(String.eq(Picker.safeText("hello\n\u{1b}[31m"),"hello  [31m"),"session label controls must be escaped for terminal")
    IO.print("PASS session picker tree")
