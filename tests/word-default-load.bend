import Base
import ../packages/runtime/src/word-segmenter.bend as Word

def text(parts: List<&2,Word.Segment>) -> String:
  match parts:
    case Nil{}: ""
    case Word.Segment{value,_,_} <> rest: value ++ text(rest)
def segmented(result: Word.ResultOf(List<&2,Word.Segment>)) -> IO(Unit):
  match result:
    case Done{parts}:
      Bool.pick(Unit -> IO(Unit),String.eq(text(parts),"hello world 日本語"),_ => IO.print("word assets loaded and segmented"),_ => IO.die(Unit,1,"segments lost text"))(Unit{})
    case Fail{_}: IO.die(Unit,1,"loaded word engine failed")
def valid(context: Word.Context) -> IO(Unit): segmented(Word.segments(context,"hello world 日本語"))
def loaded(result: Word.Loaded(Word.Context)) -> IO(Unit):
  match result:
    case Done{context}: valid(context)
    case Fail{_}: IO.die(Unit,1,"valid word assets did not load")
def rejected(result: Word.Loaded(Word.Context)) -> IO(Unit):
  match result:
    case Fail{Word.ReadFailed{_,_}}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"missing word assets were accepted")
def main() -> IO(Unit):
  do IO<Unit>:
    missing : Word.Loaded(Word.Context) <- Word.loadDefault("/tmp/pi-bend-no-word-assets")
    rejected(missing)
    result : Word.Loaded(Word.Context) <- Word.loadDefault("packages/runtime/data")
    loaded(result)
