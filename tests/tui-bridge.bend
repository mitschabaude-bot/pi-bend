import Base
import ../packages/tui/src/components/editor.bend as E
import ../packages/tui/src/components/editor-component.bend as Live
import ../packages/tui/src/components/select-list.bend as Select
import ../packages/tui/src/components/input.bend as Input
import ../packages/tui/src/components/settings-list.bend as Settings
import ../packages/tui/src/component.bend as Component
import ../packages/tui/src/tui.bend as Tui
import ../packages/tui/src/keybindings.bend as KB
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/utils.bend as U
import ../packages/tui/src/word-navigation.bend as Word
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/word-segmenter.bend as Segmenter
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as J
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

# A synchronous test bridge: tests/tui_bridge.ts runs original upstream tui
# test bodies and forwards each component call here as one JSON line on stdin,
# answered by one JSON line on stdout. Theme functions and component callbacks
# call back into the test ({"call": name, "object": id, ...}) and block on its
# one-line reply, so they run synchronously within the native operation, as
# upstream's do. Components (Editor, Input, SelectList, SettingsList) are pure
# values; editor and input keys go through the same segmenter preparation as
# the live components. Test-only.

# Bytes read past the current line wait here for the next line.
type Link is Data: Link{pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String}

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def text(value: V.Value) -> String:
  match value:
    case V.Text{value}: value
    case _: ""
def number(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(value))
    case _: 0n
def flag(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def items(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case _: Nil{}
def num(n: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(n))}
def obj(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def strings(values: List<&2,String>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> strings(rest)

# One line of stdin, without its newline; None at end of input.
type Split is Data: Split{line: List<&2,U32>,rest: List<&2,U32>}
def splitLine(bytes: List<&2,U32>,+reversed: List<&2,U32>) -> Maybe<&2,Split>:
  match bytes:
    case Nil{}: None{}
    case +byte <> +rest:
      Bool.pick(Unit -> Maybe<&2,Split>,U32.is_eq(byte,10),
        _ => Some{Split{List.reverse(&2,U32,reversed),rest}},
        _ => splitLine(rest,byte <> reversed))(Unit{})
def readClosed(pair: File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  match pair:
    case (file,result):
      do IO<List<&2,U32>>:
        File.close(file)
        return Result.default(&1,&1,U32 & String,List<&2,U32>,result,Nil{})
def readMore(file: Result<&1,&1,U32 & String,File>) -> IO(List<&2,U32>):
  match file:
    case Fail{_}: IO.pure(List<&2,U32>,Nil{})
    case Done{file}:
      do IO<List<&2,U32>>:
        pair : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,65536)
        readClosed(pair)
def decodedText(result: Result<&2,&2,Utf8.Error,String>) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: ""
def decodedLine(line: List<&2,U32>) -> String: decodedText(Utf8.decodeStrict(line))
@unsafe
def readSplit(+pending: Ref.Ref<List<&2,U32>>,+buffered: List<&2,U32>,split: Maybe<&2,Split>) -> IO(Maybe<&2,String>):
  match split:
    case Some{Split{line,rest}}:
      do IO<Maybe<&2,String>>:
        Ref.write(List<&2,U32>,pending,rest)
        return Some{decodedLine(line)}
    case None{}:
      do IO<Maybe<&2,String>>:
        file : Result<&1,&1,U32 & String,File> <- File.open("/dev/stdin","r")
        +more : List<&2,U32> <- readMore(file)
        +all : List<&2,U32> <- IO.pure(List<&2,U32>,List.append(&2,U32,buffered,more))
        Bool.pick(Unit -> IO(Maybe<&2,String>),List.is_empty(&2,U32,more),
          _ => IO.pure(Maybe<&2,String>,None{}),
          _ => readSplit(pending,all,splitLine(all,Nil{})))(Unit{})
def nextLine(+pending: Ref.Ref<List<&2,U32>>) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    +buffered : List<&2,U32> <- Ref.read(List<&2,U32>,pending)
    readSplit(pending,buffered,splitLine(buffered,Nil{}))
def emit(value: V.Value) -> IO(Unit): IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(value)),"null"))

# A callback into the test, answered by {"value": ...}.
def call(link: Link,fields: List<&2,R.Property<V.Value>>) -> IO(V.Value):
  match link:
    case Link{+pending,object,name}:
      do IO<V.Value>:
        emit(obj(R.Property{"call",V.Text{name}} <> R.Property{"object",num(object)} <> fields))
        line : Maybe<&2,String> <- nextLine(pending)
        return get(Result.default(&2,&2,J.ParseError,V.Value,J.parse(Maybe.default(&2,String,line,"")),V.Null{}),"value")
def paint(link: Link,argument: String) -> IO(String):
  do IO<String>:
    value : V.Value <- call(link,[R.Property{"text",V.Text{argument}}])
    return text(value)
def paintSelected(link: Link,argument: Settings.ThemeText) -> IO(String):
  match argument:
    case Settings.ThemeText{argument,selected}:
      do IO<String>:
        value : V.Value <- call(link,[R.Property{"text",V.Text{argument}},R.Property{"selected",V.Boolean{selected}}])
        return text(value)
def notify(link: Link,argument: String) -> IO(Unit):
  do IO<Unit>:
    value : V.Value <- call(link,[R.Property{"text",V.Text{argument}}])
    return Unit{}
def notifyItem(link: Link,item: Select.SelectItem) -> IO(Unit):
  match item:
    case Select.SelectItem{value,_,_}:
      do IO<Unit>:
        reply : V.Value <- call(link,[R.Property{"text",V.Text{value}}])
        return Unit{}
def notifyUnit(link: Link,unit: Unit) -> IO(Unit):
  do IO<Unit>:
    reply : V.Value <- call(link,Nil{})
    return Unit{}
def notifyChange(link: Link,change: Settings.Change) -> IO(Unit):
  match change:
    case Settings.Change{id,value}:
      do IO<Unit>:
        reply : V.Value <- call(link,[R.Property{"id",V.Text{id}},R.Property{"value",V.Text{value}}])
        return Unit{}
def ignoreCompletion(unit: Unit,completion: Settings.Completion) -> IO(Unit): IO.pure(Unit,Unit{})
def painter(+pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String) -> IO(C.Callback<String,String>):
  C.create(~Link,~String,~String,~paint,Link{pending,object,name})
def selectedPainter(+pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String) -> IO(C.Callback<Settings.ThemeText,String>):
  C.create(~Link,~Settings.ThemeText,~String,~paintSelected,Link{pending,object,name})
def notifier(+pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String,enabled: Bool) -> IO(Maybe<&2,C.Callback<String,Unit>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2,C.Callback<String,Unit>>,None{})
    case True{}:
      do IO<Maybe<&2,C.Callback<String,Unit>>>:
        callback : C.Callback<String,Unit> <- C.create(~Link,~String,~Unit,~notify,Link{pending,object,name})
        return Some{callback}
def itemNotifier(+pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String,enabled: Bool) -> IO(Maybe<&2,C.Callback<Select.SelectItem,Unit>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2,C.Callback<Select.SelectItem,Unit>>,None{})
    case True{}:
      do IO<Maybe<&2,C.Callback<Select.SelectItem,Unit>>>:
        callback : C.Callback<Select.SelectItem,Unit> <- C.create(~Link,~Select.SelectItem,~Unit,~notifyItem,Link{pending,object,name})
        return Some{callback}
def unitNotifier(+pending: Ref.Ref<List<&2,U32>>,object: Nat,name: String,enabled: Bool) -> IO(Maybe<&2,C.Callback<Unit,Unit>>):
  match enabled:
    case False{}: IO.pure(Maybe<&2,C.Callback<Unit,Unit>>,None{})
    case True{}:
      do IO<Maybe<&2,C.Callback<Unit,Unit>>>:
        callback : C.Callback<Unit,Unit> <- C.create(~Link,~Unit,~Unit,~notifyUnit,Link{pending,object,name})
        return Some{callback}
def selectTheme(+pending: Ref.Ref<List<&2,U32>>,+object: Nat) -> IO(Select.SelectListTheme):
  do IO<Select.SelectListTheme>:
    selectedPrefix : C.Callback<String,String> <- painter(pending,object,"selectedPrefix")
    selectedText : C.Callback<String,String> <- painter(pending,object,"selectedText")
    description : C.Callback<String,String> <- painter(pending,object,"description")
    scrollInfo : C.Callback<String,String> <- painter(pending,object,"scrollInfo")
    noMatch : C.Callback<String,String> <- painter(pending,object,"noMatch")
    return Select.SelectListTheme{selectedPrefix,selectedText,description,scrollInfo,noMatch}

# Each object is one native component value.
type Entry is Data:
  EditorEntry{editor: E.Editor,words: Segmenter.Source,rows: Nat}
  InputEntry{input: Input.Input,words: Segmenter.Source}
  SelectEntry{list: Select.SelectList}
  SettingsEntry{list: Settings.SettingsList,words: Segmenter.Source}
type Server is Data: Server{entries: List<&2,Entry>,manager: KB.KeybindingsManager}
def defaultManager() -> KB.KeybindingsManager: KB.create(KB.TUI_KEYBINDINGS(),R.new(List<&2,Keys.KeyId>))
def words() -> Segmenter.Source: Segmenter.Pending{"packages/runtime/data"}

def entryAt(entries: List<&2,Entry>,index: Nat) -> Maybe<&2,Entry>: List.get(&2,Entry,entries,index)
def replaced(entries: List<&2,Entry>,+index: Nat,entry: Entry) -> List<&2,Entry>:
  match entries index:
    case Nil{} _: Nil{}
    case _ <> rest 0n: entry <> rest
    case first <> rest Succ{previous}: first <> replaced(rest,previous,entry)

def options(+value: V.Value) -> Maybe<&2,E.EditorOptions>:
  match value:
    case V.ObjectValue{_}:
      +padding = number(get(value,"paddingX"))
      +maximum = get(value,"autocompleteMaxVisible")
      Some{E.EditorOptions{padding,Bool.pick(Nat,V.equal(maximum,V.Null{}),5n,number(maximum))}}
    case _: None{}
def maybeText(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{value}: Some{value}
    case _: None{}
def selectItems(values: List<&2,V.Value>) -> List<&2,Select.SelectItem>:
  match values:
    case Nil{}: Nil{}
    case +value <> rest: Select.SelectItem{text(get(value,"value")),text(get(value,"label")),maybeText(get(value,"description"))} <> selectItems(rest)
def texts(values: List<&2,V.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: text(value) <> texts(rest)
def settingValues(value: V.Value) -> Maybe<&2,List<&2,String>>:
  match value:
    case V.ArrayValue{items}: Some{texts(items)}
    case _: None{}
def settingItems(values: List<&2,V.Value>) -> List<&2,Settings.SettingItem>:
  match values:
    case Nil{}: Nil{}
    case +value <> rest: Settings.SettingItem{text(get(value,"id")),text(get(value,"label")),maybeText(get(value,"description")),text(get(value,"currentValue")),settingValues(get(value,"values")),None{}} <> settingItems(rest)
def createdEditor(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,+request: V.Value) -> IO(Entry):
  do IO<Entry>:
    border : C.Callback<String,String> <- painter(pending,index,"borderColor")
    theme : Select.SelectListTheme <- selectTheme(pending,index)
    editor : E.Editor <- E.new(E.EditorTheme{border,theme},options(get(request,"options")))
    return EditorEntry{editor,words(),number(get(request,"rows"))}
def createdSelect(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,+request: V.Value) -> IO(Entry):
  do IO<Entry>:
    theme : Select.SelectListTheme <- selectTheme(pending,index)
    return SelectEntry{Select.new(selectItems(items(get(request,"items"))),number(get(request,"maxVisible")),theme,None{})}
def createdSettings(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,+request: V.Value) -> IO(Entry):
  do IO<Entry>:
    label : C.Callback<Settings.ThemeText,String> <- selectedPainter(pending,index,"label")
    value : C.Callback<Settings.ThemeText,String> <- selectedPainter(pending,index,"value")
    description : C.Callback<String,String> <- painter(pending,index,"description")
    hint : C.Callback<String,String> <- painter(pending,index,"hint")
    change : C.Callback<Settings.Change,Unit> <- C.create(~Link,~Settings.Change,~Unit,~notifyChange,Link{pending,index,"onChange"})
    cancel : C.Callback<Unit,Unit> <- C.create(~Link,~Unit,~Unit,~notifyUnit,Link{pending,index,"onCancel"})
    completion : C.Callback<Settings.Completion,Unit> <- C.create(~Unit,~Settings.Completion,~Unit,~ignoreCompletion,Unit{})
    +theme : Settings.SettingsListTheme <- IO.pure(Settings.SettingsListTheme,Settings.SettingsListTheme{label,value,description,text(get(request,"cursor")),hint})
    return SettingsEntry{Settings.new(settingItems(items(get(request,"items"))),number(get(request,"maxVisible")),theme,change,cancel,Some{Settings.SettingsListOptions{flag(get(request,"enableSearch"))}},completion),words()}
def created(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,kind: String,+request: V.Value) -> IO(Entry):
  match kind:
    case "input": IO.pure(Entry,InputEntry{Input.new(None{}),words()})
    case "select": createdSelect(pending,index,request)
    case "settings": createdSettings(pending,index,request)
    case _: createdEditor(pending,index,request)

type Reply is Data: Reply{entry: Maybe<&2,Entry>,value: V.Value}
def done(entry: Entry,value: V.Value) -> IO(Reply): IO.pure(Reply,Reply{Some{entry},value})
def unchanged(entry: Entry) -> IO(Reply): IO.pure(Reply,Reply{Some{entry},V.Null{}})
def failed(message: String) -> IO(Reply): IO.pure(Reply,Reply{None{},obj([R.Property{"error",V.Text{message}}])})
def edited(words: Segmenter.Source,rows: Nat,result: E.ResultOf(E.Editor)) -> IO(Reply):
  match result:
    case Done{editor}: unchanged(EditorEntry{editor,words,rows})
    case Fail{_}: failed("editor operation failed")
def input(+editor: E.Editor,words: Segmenter.Source,+rows: Nat,+manager: KB.KeybindingsManager,+data: String) -> IO(Reply):
  do IO<Reply>:
    +keyboard : Keys.Context <- IO.pure(Keys.Context,Keys.defaults())
    +source : Segmenter.Source <- Live.wordsFor(Live.wordCommand(manager,keyboard,data),words,E.getText(editor))
    result : E.ResultOf(E.Editor) <- E.handleInput(~Segmenter.Source,~Word.sourceSegments,source,editor,manager,keyboard,data,rows)
    edited(source,rows,result)
def cursor(pair: Nat & Nat) -> V.Value:
  match pair:
    case (line,column): obj([R.Property{"line",num(line)},R.Property{"col",num(column)}])
def rendered(words: Segmenter.Source,rows: Nat,pair: E.Editor & List<&2,String>) -> IO(Reply):
  match pair:
    case (editor,lines): done(EditorEntry{editor,words,rows},V.ArrayValue{strings(lines)})
def polledRender(words: Segmenter.Source,+rows: Nat,width: Nat,result: E.ResultOf(E.Editor)) -> IO(Reply):
  match result:
    case Done{editor}:
      do IO<Reply>:
        pair : E.Editor & List<&2,String> <- E.render(editor,width,rows)
        rendered(words,rows,pair)
    case Fail{_}: failed("autocomplete failed")
def editorCallbacks(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,editor: E.Editor,words: Segmenter.Source,rows: Nat,+request: V.Value) -> IO(Reply):
  do IO<Reply>:
    submit : Maybe<&2,C.Callback<String,Unit>> <- notifier(pending,index,"onSubmit",flag(get(request,"onSubmit")))
    change : Maybe<&2,C.Callback<String,Unit>> <- notifier(pending,index,"onChange",flag(get(request,"onChange")))
    unchanged(EditorEntry{E.setCallbacks(editor,E.EditorCallbacks{change,submit,None{}}),words,rows})

# Mouse events and results as upstream's TuiMouseEvent/TuiMouseEventResult.
def offset(value: V.Value) -> Tui.Offset:
  match value:
    case V.Number{+value}: Bool.pick(Tui.Offset,F64.is_lt(value,U32.to_f64(0)),Tui.Backward{U32.to_nat(F64.to_u32(F64.neg(value)))},Tui.Forward{U32.to_nat(F64.to_u32(value))})
    case _: Tui.Forward{0n}
def eventType(value: String) -> Tui.TuiMouseEventType:
  match value:
    case "press": Tui.MousePress{}
    case "release": Tui.MouseRelease{}
    case "move": Tui.MouseMove{}
    case "drag": Tui.MouseDrag{}
    case "click": Tui.MouseClick{}
    case _: Tui.MouseWheel{}
def button(value: String) -> Tui.TuiMouseButton:
  match value:
    case "left": Tui.MouseLeft{}
    case "middle": Tui.MouseMiddle{}
    case "right": Tui.MouseRight{}
    case _: Tui.NoButton{}
def optionalOffset(+value: V.Value) -> Maybe<&2,Tui.Offset>: Bool.pick(Maybe<&2,Tui.Offset>,V.equal(value,V.Null{}),None{},Some{offset(value)})
def optionalNumber(+value: V.Value) -> Maybe<&2,Nat>: Bool.pick(Maybe<&2,Nat>,V.equal(value,V.Null{}),None{},Some{number(value)})
def mouseEvent(+value: V.Value) -> Tui.TuiMouseEvent:
  Tui.TuiMouseEvent{eventType(text(get(value,"type"))),button(text(get(value,"button"))),offset(get(value,"x")),offset(get(value,"y")),offset(get(value,"screenX")),offset(get(value,"screenY")),number(get(value,"width")),number(get(value,"height")),flag(get(value,"shift")),flag(get(value,"alt")),flag(get(value,"ctrl")),optionalOffset(get(value,"wheelDelta")),optionalNumber(get(value,"clickCount"))}
def renderFlag(value: Maybe<&2,Bool>) -> List<&2,R.Property<V.Value>>:
  match value:
    case None{}: Nil{}
    case Some{render}: [R.Property{"render",V.Boolean{render}}]
def mouseResult(value: Maybe<&2,Tui.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Tui.TuiMouseEventResult{handled,capture,focus,render}}: obj(R.Property{"handled",V.Boolean{handled}} <> R.Property{"capture",V.Boolean{capture}} <> R.Property{"focus",V.Boolean{focus}} <> renderFlag(render))
# A dispatched result was handled by its target.
def mouseResponse(value: Maybe<&2,Component.MouseResponse>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Component.LocalResult{result}}: mouseResult(Some{result})
    case Some{Component.DispatchedResult{Component.TuiMouseDispatchResult{_,_,capture,focus,render}}}: mouseResult(Some{Tui.TuiMouseEventResult{True{},capture,focus,render}})
def editorMoused(words: Segmenter.Source,rows: Nat,result: E.ResultOf(E.MouseResult)) -> IO(Reply):
  match result:
    case Done{E.MouseResult{editor,mouse}}: done(EditorEntry{editor,words,rows},mouseResult(mouse))
    case Fail{_}: failed("editor mouse operation failed")

def editorOp(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,+editor: E.Editor,words: Segmenter.Source,+rows: Nat,+manager: KB.KeybindingsManager,op: String,+request: V.Value) -> IO(Reply):
  match op:
    case "input": input(editor,words,rows,manager,text(get(request,"data")))
    case "getText": done(EditorEntry{editor,words,rows},V.Text{E.getText(editor)})
    case "getExpandedText": done(EditorEntry{editor,words,rows},V.Text{E.getExpandedText(editor)})
    case "getLines": done(EditorEntry{editor,words,rows},V.ArrayValue{strings(E.getLines(editor))})
    case "getCursor": done(EditorEntry{editor,words,rows},cursor(E.getCursor(editor)))
    case "isShowingAutocomplete": done(EditorEntry{editor,words,rows},V.Boolean{E.isShowingAutocomplete(editor)})
    case "addToHistory": unchanged(EditorEntry{E.addToHistory(editor,text(get(request,"text"))),words,rows})
    case "setFocused": unchanged(EditorEntry{E.setFocused(editor,flag(get(request,"value"))),words,rows})
    case "setDisableSubmit": unchanged(EditorEntry{E.setDisableSubmit(editor,flag(get(request,"value"))),words,rows})
    case "setText":
      do IO<Reply>:
        next : E.Editor <- E.setText(editor,text(get(request,"text")))
        unchanged(EditorEntry{next,words,rows})
    case "insertTextAtCursor":
      do IO<Reply>:
        next : E.Editor <- E.insertTextAtCursor(editor,text(get(request,"text")))
        unchanged(EditorEntry{next,words,rows})
    case "render":
      do IO<Reply>:
        result : E.ResultOf(E.Editor) <- E.pollAutocomplete(editor)
        polledRender(words,rows,number(get(request,"width")),result)
    case "handleMouse":
      do IO<Reply>:
        result : E.ResultOf(E.MouseResult) <- E.handleMouse(editor,mouseEvent(get(request,"event")))
        editorMoused(words,rows,result)
    case "setCallbacks": editorCallbacks(pending,index,editor,words,rows,request)
    case _: failed("unknown editor operation " ++ op)

def nonAtomic(source: Segmenter.Source,text: String) -> Bool: False{}
def inputEdited(words: Segmenter.Source,result: Word.ResultOf(Input.Input)) -> IO(Reply):
  match result:
    case Done{input}: unchanged(InputEntry{input,words})
    case Fail{_}: failed("input operation failed")
def inputRendered(words: Segmenter.Source,pair: Input.Input & List<&2,String>) -> IO(Reply):
  match pair:
    case (input,lines): done(InputEntry{input,words},V.ArrayValue{strings(lines)})
def inputMoused(words: Segmenter.Source,pair: Input.Input & Maybe<&2,Tui.TuiMouseEventResult>) -> IO(Reply):
  match pair:
    case (input,result): done(InputEntry{input,words},mouseResult(result))
def inputOp(+input: Input.Input,words: Segmenter.Source,+manager: KB.KeybindingsManager,op: String,+request: V.Value) -> IO(Reply):
  match op:
    case "getValue": done(InputEntry{input,words},V.Text{Input.getValue(input)})
    case "setValue": unchanged(InputEntry{Input.setValue(input,text(get(request,"value"))),words})
    case "render":
      do IO<Reply>:
        pair : Input.Input & List<&2,String> <- Input.render(input,number(get(request,"width")))
        inputRendered(words,pair)
    case "handleMouse": inputMoused(words,Input.handleMouse(input,mouseEvent(get(request,"event"))))
    case "input":
      do IO<Reply>:
        +source : Segmenter.Source <- Segmenter.readyFor(words,Input.getValue(input))
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,input,manager,Keys.defaults(),text(get(request,"data")))
        inputEdited(source,result)
    case _: failed("unknown input operation " ++ op)

def item(value: Maybe<&2,Select.SelectItem>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Select.SelectItem{value,label,description}}: obj(R.Property{"value",V.Text{value}} <> R.Property{"label",V.Text{label}} <> Maybe.default(&2,List<&2,R.Property<V.Value>>,Maybe.map(&2,String,List<&2,R.Property<V.Value>>,text => [R.Property{"description",V.Text{text}}],description),Nil{}))
def selectRendered(list: Select.SelectList,lines: List<&2,String>) -> IO(Reply): done(SelectEntry{list},V.ArrayValue{strings(lines)})
def selectMoused(pair: Select.SelectList & Maybe<&2,Tui.TuiMouseEventResult>) -> IO(Reply):
  match pair:
    case (list,result): done(SelectEntry{list},mouseResult(result))
def selectCallbacks(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,list: Select.SelectList,+request: V.Value) -> IO(Reply):
  do IO<Reply>:
    select : Maybe<&2,C.Callback<Select.SelectItem,Unit>> <- itemNotifier(pending,index,"onSelect",flag(get(request,"onSelect")))
    cancel : Maybe<&2,C.Callback<Unit,Unit>> <- unitNotifier(pending,index,"onCancel",flag(get(request,"onCancel")))
    change : Maybe<&2,C.Callback<Select.SelectItem,Unit>> <- itemNotifier(pending,index,"onSelectionChange",flag(get(request,"onSelectionChange")))
    unchanged(SelectEntry{Select.setCallbacks(list,select,cancel,change)})
def selectOp(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,+list: Select.SelectList,+manager: KB.KeybindingsManager,op: String,+request: V.Value) -> IO(Reply):
  match op:
    case "getSelectedItem": done(SelectEntry{list},item(Select.getSelectedItem(list)))
    case "setSelectedIndex": unchanged(SelectEntry{Select.setSelectedIndex(list,number(get(request,"index")))})
    case "render":
      do IO<Reply>:
        lines : List<&2,String> <- Select.render(list,number(get(request,"width")))
        selectRendered(list,lines)
    case "handleMouse":
      do IO<Reply>:
        pair : Select.SelectList & Maybe<&2,Tui.TuiMouseEventResult> <- Select.handleMouse(list,mouseEvent(get(request,"event")))
        selectMoused(pair)
    case "input":
      do IO<Reply>:
        next : Select.SelectList <- Select.handleInput(list,manager,Keys.defaults(),text(get(request,"data")))
        unchanged(SelectEntry{next})
    case "setCallbacks": selectCallbacks(pending,index,list,request)
    case _: failed("unknown select-list operation " ++ op)

def settingsRendered(words: Segmenter.Source,pair: Settings.SettingsList & List<&2,String>) -> IO(Reply):
  match pair:
    case (list,lines): done(SettingsEntry{list,words},V.ArrayValue{strings(lines)})
def settingsMoused(words: Segmenter.Source,pair: Settings.SettingsList & Maybe<&2,Component.MouseResponse>) -> IO(Reply):
  match pair:
    case (list,result): done(SettingsEntry{list,words},mouseResponse(result))
def settingsEdited(words: Segmenter.Source,result: Word.ResultOf(Settings.SettingsList)) -> IO(Reply):
  match result:
    case Done{list}: unchanged(SettingsEntry{list,words})
    case Fail{_}: failed("settings-list operation failed")
def settingsOp(+list: Settings.SettingsList,words: Segmenter.Source,+manager: KB.KeybindingsManager,op: String,+request: V.Value) -> IO(Reply):
  match op:
    case "selectItem": unchanged(SettingsEntry{Settings.selectItem(list,text(get(request,"id"))),words})
    case "render":
      do IO<Reply>:
        pair : Settings.SettingsList & List<&2,String> <- Settings.render(list,number(get(request,"width")))
        settingsRendered(words,pair)
    case "handleMouse":
      do IO<Reply>:
        pair : Settings.SettingsList & Maybe<&2,Component.MouseResponse> <- Settings.handleMouse(list,mouseEvent(get(request,"event")))
        settingsMoused(words,pair)
    case "input":
      do IO<Reply>:
        +source : Segmenter.Source <- Segmenter.ready(words)
        result : Word.ResultOf(Settings.SettingsList) <- Settings.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,list,manager,Keys.defaults(),text(get(request,"data")))
        settingsEdited(source,result)
    case _: failed("unknown settings-list operation " ++ op)

def entryOp(+pending: Ref.Ref<List<&2,U32>>,+index: Nat,entry: Entry,+manager: KB.KeybindingsManager,op: String,+request: V.Value) -> IO(Reply):
  match entry:
    case EditorEntry{editor,words,rows}: editorOp(pending,index,editor,words,rows,manager,op,request)
    case InputEntry{input,words}: inputOp(input,words,manager,op,request)
    case SelectEntry{list}: selectOp(pending,index,list,manager,op,request)
    case SettingsEntry{list,words}: settingsOp(list,words,manager,op,request)
def keyParsed(key: Maybe<&2,Keys.KeyId>,rest: List<&2,Keys.KeyId>) -> List<&2,Keys.KeyId>:
  match key:
    case Some{key}: key <> rest
    case None{}: rest
def keyList(values: List<&2,V.Value>) -> List<&2,Keys.KeyId>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: keyParsed(Keys.parseKeyId(text(value)),keyList(rest))
def keyConfig(fields: List<&2,R.Property<V.Value>>,config: R.Record<List<&2,Keys.KeyId>>) -> R.Record<List<&2,Keys.KeyId>>:
  match fields:
    case Nil{}: config
    case R.Property{action,V.Text{key}} <> rest: keyConfig(rest,R.set(List<&2,Keys.KeyId>,config,action,keyList([V.Text{key}])))
    case R.Property{action,value} <> rest: keyConfig(rest,R.set(List<&2,Keys.KeyId>,config,action,keyList(items(value))))
def keybindings(value: V.Value) -> KB.KeybindingsManager:
  match value:
    case V.ObjectValue{R.Record{fields}}: KB.create(KB.TUI_KEYBINDINGS(),keyConfig(fields,R.new(List<&2,Keys.KeyId>)))
    case _: defaultManager()

def chunk(value: E.TextChunk) -> V.Value:
  match value:
    case E.TextChunk{text,start,end}: obj([R.Property{"text",V.Text{text}},R.Property{"startIndex",num(start)},R.Property{"endIndex",num(end)}])
def chunks(values: List<&2,E.TextChunk>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: chunk(value) <> chunks(rest)

# Upstream's pre-segmented paste markers are the native paste registry.
def pasteIds(values: List<&2,V.Value>) -> List<&2,E.Paste>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: E.Paste{number(value),""} <> pasteIds(rest)
type Step is Data: Step{server: Server,value: V.Value}
def stored(entries: List<&2,Entry>,manager: KB.KeybindingsManager,+index: Nat,reply: Reply) -> Step:
  match reply:
    case Reply{Some{entry},value}: Step{Server{replaced(entries,index,entry),manager},obj([R.Property{"result",value}])}
    case Reply{None{},value}: Step{Server{entries,manager},value}
def appended(entries: List<&2,Entry>,manager: KB.KeybindingsManager,+index: Nat,entry: Entry) -> Step:
  Step{Server{List.append(&2,Entry,entries,[entry]),manager},obj([R.Property{"result",num(index)}])}
def handleEntry(+pending: Ref.Ref<List<&2,U32>>,entries: List<&2,Entry>,+manager: KB.KeybindingsManager,op: String,+request: V.Value,+index: Nat,found: Maybe<&2,Entry>) -> IO(Step):
  match found:
    case None{}: IO.pure(Step,Step{Server{entries,manager},obj([R.Property{"error",V.Text{"no such object"}}])})
    case Some{entry}:
      do IO<Step>:
        reply : Reply <- entryOp(pending,index,entry,manager,op,request)
        return stored(entries,manager,index,reply)

def handleEditor(+pending: Ref.Ref<List<&2,U32>>,+entries: List<&2,Entry>,+manager: KB.KeybindingsManager,op: String,+request: V.Value,+index: Nat) -> IO(Step):
  handleEntry(pending,entries,manager,op,request,index,entryAt(entries,index))
def handleOp(+pending: Ref.Ref<List<&2,U32>>,server: Server,op: String,+request: V.Value) -> IO(Step):
  match server:
    case Server{+entries,+manager}:
      match op:
        case "new":
          +index = List.length(&2,Entry,entries)
          do IO<Step>:
            entry : Entry <- created(pending,index,text(get(request,"kind")),request)
            return appended(entries,manager,index,entry)
        case "keybindings": IO.pure(Step,Step{Server{entries,keybindings(get(request,"bindings"))},obj([R.Property{"result",V.Null{}}])})
        case "wordWrapLine": IO.pure(Step,Step{Server{entries,manager},obj([R.Property{"result",V.ArrayValue{chunks(E.wordWrapLineWithMarkers(text(get(request,"line")),number(get(request,"width")),pasteIds(items(get(request,"pastes")))))}}])})
        case "visibleWidth": IO.pure(Step,Step{Server{entries,manager},obj([R.Property{"result",num(U.visibleWidth(text(get(request,"text"))))}])})
        case _: handleEditor(pending,entries,manager,op,request,number(get(request,"object")))
def handle(+pending: Ref.Ref<List<&2,U32>>,server: Server,+request: V.Value) -> IO(Step): handleOp(pending,server,text(get(request,"op")),request)
type Phase is Data:
  Read{server: Server}
  Line{server: Server,line: Maybe<&2,String>}
  Parsed{server: Server,parsed: Result<&2,&2,J.ParseError,V.Value>}
  Stepped{step: Step}
@unsafe
def serve(+pending: Ref.Ref<List<&2,U32>>,phase: Phase) -> IO(Unit):
  match phase:
    case Read{server}:
      do IO<Unit>:
        line : Maybe<&2,String> <- nextLine(pending)
        serve(pending,Line{server,line})
    case Line{_,None{}}: IO.pure(Unit,Unit{})
    case Line{server,Some{text}}: serve(pending,Parsed{server,J.parse(text)})
    case Parsed{server,Fail{_}}:
      do IO<Unit>:
        emit(obj([R.Property{"error",V.Text{"invalid request"}}]))
        serve(pending,Read{server})
    case Parsed{server,Done{request}}:
      do IO<Unit>:
        step : Step <- handle(pending,server,request)
        serve(pending,Stepped{step})
    case Stepped{Step{server,value}}:
      do IO<Unit>:
        emit(value)
        serve(pending,Read{server})

def main() -> IO(Unit):
  do IO<Unit>:
    pending : Ref.Ref<List<&2,U32>> <- Ref.new(List<&2,U32>,Nil{})
    serve(pending,Read{Server{Nil{},defaultManager()}})
