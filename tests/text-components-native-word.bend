import Base
import ../packages/tui/src/components/input.bend as I
import ../packages/tui/src/components/settings-list.bend as S
import ../packages/tui/src/word-navigation.bend as Word
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/keybindings.bend as KB
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/word-segmenter.bend as W
import ../packages/runtime/src/word-rules.bend as Rules
import ../packages/runtime/src/cjk-dictionary.bend as D
import ../packages/runtime/src/sea-word-data.bend as K
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}
def atomic(context: W.Context,value: String) -> Bool: False{}
def paint(unused: Unit,value: S.ThemeText) -> IO(String):
  match value:
    case S.ThemeText{text,_}: IO.pure(String,text)
def plain(unused: Unit,value: String) -> IO(String): IO.pure(String,value)
def changed(unused: Unit,value: S.Change) -> IO(Unit): IO.pure(Unit,Unit{})
def cancelled(unused: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def completed(unused: Unit,value: S.Completion) -> IO(Unit): IO.pure(Unit,Unit{})
def shown(state: I.Input) -> String:
  +state = {state: I.Input}
  "{\"value\":" ++ J.quote(I.getValue(state)) ++ ",\"cursor\":" ++ Nat.show(I.getCursor(state)) ++ "}"
def error(value: Word.Error) -> String:
  match value:
    case Word.MissingWordEngine{language}: "MissingWordEngine:" ++ language
    case Word.InvalidSegments{}: "InvalidSegments"
    case Word.InvalidCursor{}: "InvalidCursor"
    case Word.WordData{_}: "WordData"
    case Word.WordDataPending{}: "WordDataPending"
def received(state: I.Input,value: Word.ResultOf(I.Input)) -> I.Input & String:
  match value:
    case Done{+next}: (next,shown(next))
    case Fail{failure}: (state,"{\"error\":" ++ J.quote(error(failure)) ++ "}")
def selected(value: Maybe<&2,S.SettingItem>) -> String:
  match value:
    case Some{S.SettingItem{id,_,_,_,_,_}}: J.quote(id)
    case _: "null"
def settingsShown(+state: S.SettingsList) -> String:
  match state:
    case S.SettingsList{_,_,_,_,_,_,_,_,Some{input},_,_,_}: "{\"input\":" ++ shown(input) ++ ",\"selected\":" ++ selected(S.getSelectedItem(state)) ++ "}"
    case _: "null"
def settingsReceived(state: S.SettingsList,value: Word.ResultOf(S.SettingsList)) -> S.SettingsList & String:
  match value:
    case Done{+next}: (next,settingsShown(next))
    case Fail{failure}: (state,"{\"error\":" ++ J.quote(error(failure)) ++ "}")
type State is Data: State{input: I.Input,settings: S.SettingsList,observations: List<&2,String>}
def observed(input: I.Input & String,settings: S.SettingsList & String,observations: List<&2,String>) -> State:
  match input settings:
    case Tuple{input,inputShown} Tuple{settings,settingsShown}: State{input,settings,("{\"input\":" ++ inputShown ++ ",\"settings\":" ++ settingsShown ++ "}") <> observations}
def step(+context: W.Context,+manager: KB.KeybindingsManager,+key: String,state: State) -> IO(State):
  match state:
    case State{+input,+settings,observations}:
      do IO<State>:
        inputResult : Word.ResultOf(I.Input) <- I.handleInput(~W.Context,~Word.nativeSegments,~atomic,context,input,manager,Keys.Context{False{},False{}},key)
        settingsResult : Word.ResultOf(S.SettingsList) <- S.handleInput(~W.Context,~Word.nativeSegments,~atomic,context,settings,manager,Keys.Context{False{},False{}},key)
        return observed(received(input,inputResult),settingsReceived(settings,settingsResult),observations)
def finished(state: State) -> String:
  match state:
    case State{input,settings,observations}: "{\"observations\":[" ++ String.join(List.reverse(&2,String,observations),",") ++ "],\"finalInput\":" ++ shown(input) ++ ",\"finalSettings\":" ++ settingsShown(settings) ++ "}"
def steps(keys: List<&2,V.Value>,+context: W.Context,+manager: KB.KeybindingsManager,state: State) -> IO(String):
  match keys:
    case Nil{}: IO.pure(String,finished(state))
    case V.Text{key} <> rest:
      do IO<String>:
        next : State <- step(context,manager,key,state)
        steps(rest,context,manager,next)
    case _: IO.die(String,1,"expected key string")
def runOne(+context: W.Context,+value: V.Value) -> IO(Unit):
  do IO<Unit>:
    +paintCallback : C.Callback<S.ThemeText,String> <- C.create(~Unit,~S.ThemeText,~String,~paint,Unit{})
    +plainCallback : C.Callback<String,String> <- C.create(~Unit,~String,~String,~plain,Unit{})
    +changeCallback : C.Callback<S.Change,Unit> <- C.create(~Unit,~S.Change,~Unit,~changed,Unit{})
    +cancelCallback : C.Callback<Unit,Unit> <- C.create(~Unit,~Unit,~Unit,~cancelled,Unit{})
    +completeCallback : C.Callback<S.Completion,Unit> <- C.create(~Unit,~S.Completion,~Unit,~completed,Unit{})
    initial : State = State{I.new(None{}),S.new(S.SettingItem{"text",text(get(value,"text")),None{},"value",None{},None{}} <> S.SettingItem{"other","Unrelated",None{},"value",None{},None{}} <> Nil{},5n,S.SettingsListTheme{paintCallback,paintCallback,plainCallback,"> ",plainCallback},changeCallback,cancelCallback,Some{S.SettingsListOptions{True{}}},completeCallback),Nil{}}
    output : String <- steps(V.Text{"\u{1b}[200~" ++ text(get(value,"text")) ++ "\u{1b}[201~"} <> array(get(value,"keys")),context,KB.create(KB.TUI_KEYBINDINGS(),R.new(List<&2,Keys.KeyId>)),initial)
    C.dispose(S.ThemeText,String,paintCallback)
    C.dispose(String,String,plainCallback)
    C.dispose(S.Change,Unit,changeCallback)
    C.dispose(Unit,Unit,cancelCallback)
    C.dispose(S.Completion,Unit,completeCallback)
    IO.print(output)
def cases(values: List<&2,V.Value>,+context: W.Context) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        runOne(context,value)
        cases(rest,context)
def inputs(context: W.Context,result: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match result:
    case Done{V.ArrayValue{values}}: cases(values,context)
    case _: IO.die(Unit,1,"expected JSON array")
def rulesDecoded(thai: D.Trie,myanmar: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: Rules.Parsed(Rules.Rules)) -> IO(Unit):
  match result:
    case Done{rules}: inputs(W.create(rules,dictionary,khmer,lao,thai,myanmar),J.parse(input))
    case Fail{_}: IO.die(Unit,1,"invalid word rules")
def rulesRead(thai: D.Trie,myanmar: D.Trie,lao: D.Trie,khmer: D.Trie,dictionary: D.Trie,input: String,result: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Done{bytes}: rulesDecoded(thai,myanmar,lao,khmer,dictionary,input,Rules.decode(bytes))
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
    case _: IO.die(Unit,1,"expected JSON fixture path")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
