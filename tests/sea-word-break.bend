import Base
import ../packages/runtime/src/sea-word-break.bend as W
import ../packages/runtime/src/cjk-dictionary.bend as D
import ../packages/runtime/src/sea-word-data.bend as K
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/string.bend as Text

def lengths(values: List<&2,W.Candidate>,reversed: List<&2,String>) -> String:
  match values:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case W.Candidate{length,_} <> rest: lengths(rest,Nat.show(length) <> reversed)
def shown(value: W.Matches) -> String:
  match value:
    case W.Matches{prefix,words}: "[" ++ Nat.show(prefix) ++ "," ++ lengths(words,Nil{}) ++ "]"
def row(context: W.Context,fields: List<&2,String>) -> Bool:
  match fields:
    case text <> expected <> Nil{}: Text.equal(shown(W.matches(context,text)),expected)
    case _: False{}
def cases(+context: W.Context,values: List<&2,String>,count: Nat) -> Result<&2,&2,String,Nat>:
  match values:
    case Nil{}: Done{count}
    case +text <> +rest:
      Bool.pick(Unit -> Result<&2,&2,String,Nat>,row(context,Text.split(text,'\t')),
        _ => cases(context,rest,Succ{count}),_ => Fail{text})(Unit{})
def checked(result: Result<&2,&2,String,Nat>) -> IO(Unit):
  match result:
    case Done{count}: IO.print(Nat.show(count))
    case Fail{text}: IO.die(Unit,1,"prefix mismatch: " ++ text)
def decoded(language: K.Language,result: D.Parsed(D.Trie),input: String) -> IO(Unit):
  match result:
    case Done{dictionary}: checked(cases(W.Context{language,dictionary},Text.split(input,'\n'),0n))
    case Fail{_}: IO.die(Unit,1,"invalid Khmer dictionary")
def decode(language: K.Language,bytes: List<&2,U32>) -> D.Parsed(D.Trie):
  match language:
    case K.Khmer{}: K.decodeKhmer(bytes)
    case K.Lao{}: K.decodeLao(bytes)
    case K.Thai{}: K.decodeThai(bytes)
    case K.Myanmar{}: K.decodeMyanmar(bytes)
def asset(language: K.Language) -> String:
  match language:
    case K.Khmer{}: "packages/runtime/data/icu78-khmer.bin"
    case K.Lao{}: "packages/runtime/data/icu78-lao.bin"
    case K.Thai{}: "packages/runtime/data/icu78-thai.bin"
    case K.Myanmar{}: "packages/runtime/data/icu78-burmese.bin"
def loaded(+language: K.Language,result: Result<&2,&2,FS.Error,List<&2,U32>>,input: String) -> IO(Unit):
  match result:
    case Done{bytes}: decoded(language,decode(language,bytes),input)
    case Fail{_}: IO.die(Unit,1,"dictionary read failed")
def run(+language: K.Language,input: String) -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(asset(language))
    loaded(language,bytes,input)
def fixture(language: K.Language,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: run(language,Utf8.decodeBytes(bytes))
    case Fail{_}: IO.die(Unit,1,"fixture read failed")
def input(language: K.Language,path: String) -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    fixture(language,bytes)
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case "khmer" <> path <> Nil{}: input(K.Khmer{},path)
    case "lao" <> path <> Nil{}: input(K.Lao{},path)
    case "thai" <> path <> Nil{}: input(K.Thai{},path)
    case "burmese" <> path <> Nil{}: input(K.Myanmar{},path)
    case _: IO.die(Unit,1,"expected language and TSV fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
