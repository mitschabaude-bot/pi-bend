import Base
import ../packages/tui/src/tui-main-screen.bend as Screen
import ../packages/runtime/src/string.bend as Strings

def ended(value: Maybe<&2,Screen.Batch>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"unexpected extra bounded write")
def last(value: Maybe<&2,Screen.Batch>,expected: String) -> IO(Unit):
  match value:
    case Some{Screen.Batch{Screen.Write{text},rest}}:
      Bool.pick(Unit -> IO(Unit),Strings.equal(text,expected),
        _ => ended(Screen.nextEffect(rest)),
        _ => IO.die(Unit,1,"wrong final bounded write"))(Unit{})
    case _: IO.die(Unit,1,"missing final bounded write")
def first(value: Maybe<&2,Screen.Batch>,expected: String,suffix: String) -> IO(Unit):
  match value:
    case Some{Screen.Batch{Screen.Write{text},rest}}:
      Bool.pick(Unit -> IO(Unit),Strings.equal(text,expected),
        _ => last(Screen.nextEffect(rest),suffix),
        _ => IO.die(Unit,1,"wrong first bounded write"))(Unit{})
    case _: IO.die(Unit,1,"missing first bounded write")
def check(+prefix: String,+suffix: String) -> IO(Unit):
  first(Screen.nextEffect(Screen.stream(Screen.Text{prefix ++ suffix} <> Nil{})),prefix,suffix)
@unsafe def repeated(+value: String,+count: Nat,+acc: String) -> String:
  match count:
    case Zero{}: acc
    case Succ{left}:
      +take = Nat.is_eq(count % 2n,1n)
      +next = Bool.pick(String,take,acc ++ value,acc)
      repeated(value ++ value,count / 2n,next)
def main() -> IO(Unit):
  do IO<Unit>:
    check(repeated("A",1048576n,""),repeated("B",151424n,""))
    check(repeated("X",1048575n,""),"😀Z")
    IO.print("bounded-ok")
