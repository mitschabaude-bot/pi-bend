import Base
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/word-rules.bend as R
import ../packages/runtime/src/cjk-dictionary.bend as D
import ../packages/runtime/src/sea-word-data.bend as K
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/string.bend as Text

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
def compared(context: W.Context,+expected: String,result: Result<&2,&2,J.ParseError,V.Value>) -> Bool:
  match result:
    case Done{V.Text{text}}: Text.equal(shown(W.segments(context,text)),expected)
    case _: False{}
def row(context: W.Context,fields: List<&2,String>) -> Bool:
  match fields:
    case encodedText <> expected <> Nil{}: compared(context,expected,J.parse(encodedText))
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
    case Fail{message}: IO.die(Unit,1,"word mismatch: " ++ message)
def rulesDecoded(thai: D.Trie,myanmar: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: R.Parsed(R.Rules)) -> IO(Unit):
  match result:
    case Done{rules}: checked(cases(W.create(rules,dictionary,khmer,lao,thai,myanmar),Text.split(input,'\n'),0n))
    case Fail{_}: IO.die(Unit,1,"invalid word rules")
def rulesRead(thai: D.Trie,myanmar: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: rulesDecoded(thai,myanmar,lao,khmer,dictionary,input,R.decode(bytes))
    case Fail{_}: IO.die(Unit,1,"word rules read failed")
def myanmarDecoded(thai: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: D.Parsed(D.Trie)) -> IO(Unit):
  match result:
    case Done{myanmar}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-word-rules.bin")
        rulesRead(thai,myanmar,lao,khmer,dictionary,input,bytes)
    case Fail{_}: IO.die(Unit,1,"invalid Myanmar dictionary")
def myanmarRead(thai: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: myanmarDecoded(thai,lao,khmer,dictionary,input,K.decodeMyanmar(bytes))
    case Fail{_}: IO.die(Unit,1,"Myanmar dictionary read failed")
def thaiDecoded(lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: D.Parsed(D.Trie)) -> IO(Unit):
  match result:
    case Done{thai}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-burmese.bin")
        myanmarRead(thai,lao,khmer,dictionary,input,bytes)
    case Fail{_}: IO.die(Unit,1,"invalid Thai dictionary")
def thaiRead(lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: thaiDecoded(lao,khmer,dictionary,input,K.decodeThai(bytes))
    case Fail{_}: IO.die(Unit,1,"Thai dictionary read failed")
def laoDecoded(khmer: D.Trie,dictionary: D.Trie,input: String,result: D.Parsed(D.Trie)) -> IO(Unit):
  match result:
    case Done{lao}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-thai.bin")
        thaiRead(lao,khmer,dictionary,input,bytes)
    case Fail{_}: IO.die(Unit,1,"invalid Lao dictionary")
def laoRead(khmer: D.Trie,dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: laoDecoded(khmer,dictionary,input,K.decodeLao(bytes))
    case Fail{_}: IO.die(Unit,1,"Lao dictionary read failed")
def khmerDecoded(dictionary: D.Trie,input: String,result: D.Parsed(D.Trie)) -> IO(Unit):
  match result:
    case Done{khmer}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-lao.bin")
        laoRead(khmer,dictionary,input,bytes)
    case Fail{_}: IO.die(Unit,1,"invalid Khmer dictionary")
def khmerRead(dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: khmerDecoded(dictionary,input,K.decodeKhmer(bytes))
    case Fail{_}: IO.die(Unit,1,"Khmer dictionary read failed")
def decoded(result: D.Parsed(D.Trie),input: String) -> IO(Unit):
  match result:
    case Done{dictionary}:
      do IO<Unit>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("packages/runtime/data/icu78-khmer.bin")
        khmerRead(dictionary,input,bytes)
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
    case _: IO.die(Unit,1,"expected TSV fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
