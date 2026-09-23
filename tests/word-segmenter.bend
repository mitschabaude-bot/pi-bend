import Base
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/word-rules.bend as R
import ../packages/runtime/src/cjk-dictionary.bend as D
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

def encoded(values: List<&2,W.Segment>,reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case W.Segment{text,word,status} <> rest:
      encoded(rest,("[" ++ J.quote(text) ++ "," ++ Bool.pick(String,word,"true","false") ++ "," ++ U32.show(status) ++ "]") <> reversed)
def shown(result: W.ResultOf(List<&2,W.Segment>)) -> String:
  match result:
    case Done{values}: encoded(values,Nil{})
    case Fail{W.MissingEngine{language}}: J.quote("MissingEngine:" ++ language)
    case Fail{W.InvalidState{}}: J.quote("InvalidState")
def cases(+context: W.Context,values: List<&2,V.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case V.Text{text} <> rest:
      do IO<Unit>:
        IO.print(shown(W.segments(context,text)))
        cases(context,rest)
    case _: IO.die(Unit,1,"expected strings")
def inputs(context: W.Context,result: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match result:
    case Done{V.ArrayValue{values}}: cases(context,values)
    case _: IO.die(Unit,1,"expected JSON array")
def rulesDecoded(dictionary: D.Trie,input: String,result: R.Parsed(R.Rules)) -> IO(Unit):
  match result:
    case Done{rules}: inputs(W.create(rules,dictionary),J.parse(input))
    case Fail{_}: IO.die(Unit,1,"invalid word rules")
def rulesRead(dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: rulesDecoded(dictionary,input,R.decode(bytes))
    case Fail{_}: IO.die(Unit,1,"word rules read failed")
def decoded(result: D.Parsed(D.Trie),input: String) -> IO(Unit):
  match result:
    case Done{dictionary}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-word-rules.bin")
        rulesRead(dictionary,input,bytes)
    case Fail{_}: IO.die(Unit,1,"invalid dictionary")
def loaded(result: Result<&2,&2,FS.Error,List<&2,U32>>,input: String) -> IO(Unit):
  match result:
    case Done{bytes}: decoded(D.decode(bytes),input)
    case Fail{_}: IO.die(Unit,1,"dictionary read failed")
def run(input: String) -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-cjk.bin")
    loaded(bytes,input)
def fixture(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: run(Utf8.decodeBytes(bytes))
    case Fail{_}: IO.die(Unit,1,"fixture read failed")
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case path <> Nil{}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        fixture(bytes)
    case _: IO.die(Unit,1,"expected JSON fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
