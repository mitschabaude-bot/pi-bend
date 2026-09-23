import Base
import ../packages/runtime/src/khmer-word-break.bend as W
import ../packages/runtime/src/cjk-dictionary.bend as D
import ../packages/runtime/src/khmer-word-data.bend as K
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
def row(dictionary: D.Trie,fields: List<&2,String>) -> Bool:
  match fields:
    case text <> expected <> Nil{}: Text.equal(shown(W.matches(dictionary,text)),expected)
    case _: False{}
def cases(+dictionary: D.Trie,values: List<&2,String>,count: Nat) -> Result<&2,&2,String,Nat>:
  match values:
    case Nil{}: Done{count}
    case +text <> +rest:
      Bool.pick(Unit -> Result<&2,&2,String,Nat>,row(dictionary,Text.split(text,'\t')),
        _ => cases(dictionary,rest,Succ{count}),_ => Fail{text})(Unit{})
def checked(result: Result<&2,&2,String,Nat>) -> IO(Unit):
  match result:
    case Done{count}: IO.print(Nat.show(count))
    case Fail{text}: IO.die(Unit,1,"prefix mismatch: " ++ text)
def decoded(result: D.Parsed(D.Trie),input: String) -> IO(Unit):
  match result:
    case Done{dictionary}: checked(cases(dictionary,Text.split(input,'\n'),0n))
    case Fail{_}: IO.die(Unit,1,"invalid Khmer dictionary")
def loaded(result: Result<&2,&2,FS.Error,List<&2,U32>>,input: String) -> IO(Unit):
  match result:
    case Done{bytes}: decoded(K.decode(bytes),input)
    case Fail{_}: IO.die(Unit,1,"dictionary read failed")
def run(input: String) -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-khmer.bin")
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
    case _: IO.die(Unit,1,"expected TSV fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
