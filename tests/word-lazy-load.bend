import Base
import ../packages/runtime/src/word-segmenter.bend as Word
import ../packages/tui/src/word-navigation.bend as Navigation

# Word data loads lazily: the rules first, each dictionary when text of its
# script is segmented. Segments through `readyFor` must equal those of the
# fully loaded context, and a source readied for other text reports the data
# as pending instead of segmenting without a needed dictionary.
def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def navShown(parts: List<&2,Navigation.Segment>) -> String:
  match parts:
    case Nil{}: ""
    case Navigation.Segment{text,word} <> rest: text ++ "/" ++ Bool.show(word) ++ "|" ++ navShown(rest)
def navShownWord(parts: List<&2,Word.Segment>) -> String:
  match parts:
    case Nil{}: ""
    case Word.Segment{text,word,_} <> rest: text ++ "/" ++ Bool.show(word) ++ "|" ++ navShownWord(rest)
def navShownResult(result: Word.ResultOf(List<&2,Word.Segment>)) -> String:
  match result:
    case Done{parts}: navShownWord(parts)
    case Fail{_}: "error"
def navExpected(context: Word.Context,text: String) -> String: navShownResult(Word.segments(context,text))
def lazyShown(result: Navigation.ResultOf(List<&2,Navigation.Segment>)) -> String:
  match result:
    case Done{parts}: navShown(parts)
    case Fail{Navigation.WordDataPending{}}: "pending"
    case Fail{_}: "error"
def texts() -> List<&2,String>:
  ["hello world foo.bar", "日本語のテキスト test", "한국어 문장", "ภาษาไทยง่าย", "ພາສາລາວ", "မြန်မာစာ", "ភាសាខ្មែរ", "mixed 中文 ไทย ລາວ ខ្មែរ မြန် end"]
def each(texts: List<&2,String>,+full: Word.Context) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit,Unit{})
    case +text <> rest:
      do IO<Unit>:
        source : Word.Source <- Word.readyFor(Word.Pending{"packages/runtime/data"},text)
        check(String.eq(lazyShown(Navigation.sourceSegments(source,text)),navExpected(full,text)),"lazy segments equal full segments: " ++ text)
        each(rest,full)
def fullContext(result: Word.Loaded(Word.Context)) -> IO(Word.Context):
  match result:
    case Done{context}: IO.pure(Word.Context,context)
    case Fail{_}: IO.die(Word.Context,1,"word assets did not load")
def main() -> IO(Unit):
  do IO<Unit>:
    loaded : Word.Loaded(Word.Context) <- Word.loadDefault("packages/runtime/data")
    +full : Word.Context <- fullContext(loaded)
    each(texts(),full)
    ascii : Word.Source <- Word.readyFor(Word.Pending{"packages/runtime/data"},"plain ascii")
    check(String.eq(lazyShown(Navigation.sourceSegments(ascii,"日本語")),"pending"),"text needing an unloaded dictionary is pending")
