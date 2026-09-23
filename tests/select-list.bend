import Base
import ../packages/tui/src/components/select-list.bend as S
import ../packages/tui/src/tui.bend as Tui
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/keybindings.bend as KB
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/f64.bend as F
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

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
def optionalNumber(value: V.Value) -> Maybe<&2,Nat>:
  match value:
    case V.Number{value}: Some{U32.to_nat(F64.to_u32(value))}
    case _: None{}
def array(value: V.Value) -> List<&2,V.Value>:
  match value:
    case V.ArrayValue{values}: values
    case _: Nil{}
def field(name: String,value: V.Value) -> R.Property<V.Value>: R.Property{name,value}
def strings(values: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match values:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case value <> rest: strings(rest,V.Text{value} <> reversed)
def boolean(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def optionalText(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{value}: Some{value}
    case _: None{}
def object(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def num(value: Nat) -> V.Value: V.Number{Tui.dimension(value)}
def signed(value: V.Value) -> Tui.Offset:
  match value:
    case V.Number{+value}: Bool.pick(Tui.Offset,F64.is_lt(value,U32.to_f64(0)),Tui.Backward{U32.to_nat(F64.to_u32(F.negate(value)))},Tui.Forward{U32.to_nat(F64.to_u32(value))})
    case _: Tui.Forward{0n}
def signedValue(value: Tui.Offset) -> V.Value:
  match value:
    case Tui.Forward{value}: num(value)
    case Tui.Backward{value}: V.Number{F.negate(Tui.dimension(value))}
def item(+value: V.Value) -> S.SelectItem: S.SelectItem{text(get(value,"value")),text(get(value,"label")),optionalText(get(value,"description"))}
def items(values: List<&2,V.Value>,reversed: List<&2,S.SelectItem>) -> List<&2,S.SelectItem>:
  match values:
    case Nil{}: List.reverse(&2,S.SelectItem,reversed)
    case value <> rest: items(rest,item(value) <> reversed)
def itemValue(value: S.SelectItem) -> V.Value:
  match value:
    case S.SelectItem{value,label,description}:
      object(field("value",V.Text{value}) <> field("label",V.Text{label}) <> Maybe.default(&2,List<&2,R.Property<V.Value>>,Maybe.map(&2,String,List<&2,R.Property<V.Value>>,desc => field("description",V.Text{desc}) <> Nil{},description),Nil{}))
def selected(value: Maybe<&2,S.SelectItem>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: itemValue(value)
def log(calls: Ref.Ref<List<&2,V.Value>>,value: V.Value) -> IO(Unit):
  Ref.modify(List<&2,V.Value>,Unit,calls,previous => (value <> previous,Unit{}))
type ThemeEnvironment is Data:
  ThemeEnvironment{kind: String,styled: Bool,calls: Ref.Ref<List<&2,V.Value>>}
def paint(environment: ThemeEnvironment,input: String) -> IO(String):
  match environment:
    case ThemeEnvironment{kind,styled,calls}:
      +input = {input: String}
      do IO<String>:
        log(calls,object(field("kind",V.Text{kind}) <> field("text",V.Text{input}) <> Nil{}))
        return Bool.pick(String,styled,"\u{1b}[31m" ++ input ++ "\u{1b}[39m",input)
type EventEnvironment is Data:
  EventEnvironment{kind: String,calls: Ref.Ref<List<&2,V.Value>>}
def event(environment: EventEnvironment,input: S.SelectItem) -> IO(Unit):
  match environment:
    case EventEnvironment{kind,calls}: log(calls,object(field("kind",V.Text{kind}) <> field("item",itemValue(input)) <> Nil{}))
def cancel(calls: Ref.Ref<List<&2,V.Value>>,unused: Unit) -> IO(Unit):
  log(calls,object(field("kind",V.Text{"cancel"}) <> Nil{}))
def take(text: String,count: Nat,reversed: String) -> String:
  match text count:
    case SCon{char,rest} Succ{count}: take(rest,count,SCon{char,reversed})
    case _ _: String.reverse(reversed)
def custom(environment: EventEnvironment,input: S.SelectListTruncatePrimaryContext) -> IO(String):
  match environment input:
    case EventEnvironment{+kind,calls} S.SelectListTruncatePrimaryContext{+text,+maxWidth,columnWidth,item,isSelected}:
      do IO<String>:
        log(calls,object(field("kind",V.Text{"truncatePrimary"}) <> field("text",V.Text{text}) <> field("maxWidth",signedValue(maxWidth)) <> field("columnWidth",signedValue(columnWidth)) <> field("item",itemValue(item)) <> field("isSelected",V.Boolean{isSelected}) <> Nil{}))
        return Bool.pick(String,String.eq(kind,"overflow"),text ++ " extra primary text",Bool.pick(String,String.eq(kind,"ellipsis") && Bool.not(Nat.is_le(String.length(text),S.nonnegative(maxWidth))),take(text,S.nonnegative(maxWidth) - 1n,"") ++ "…",text))
def keyList(values: V.Value) -> List<&2,Keys.KeyId>:
  match values:
    case V.Text{value}: Maybe.default(&2,List<&2,Keys.KeyId>,Maybe.map(&2,Keys.KeyId,List<&2,Keys.KeyId>,key => key <> Nil{},Keys.parseKeyId(value)),Nil{})
    case _: Nil{}
def bindings(values: List<&2,R.Property<V.Value>>,reversed: List<&2,R.Property<List<&2,Keys.KeyId>>>) -> KB.KeybindingsConfig():
  match values:
    case Nil{}: R.Record{List.reverse(&2,R.Property<List<&2,Keys.KeyId>>,reversed)}
    case R.Property{name,value} <> rest: bindings(rest,R.Property{name,keyList(value)} <> reversed)
def manager(value: V.Value) -> KB.KeybindingsManager:
  match value:
    case V.ObjectValue{R.Record{values}}: KB.create(KB.TUI_KEYBINDINGS(),bindings(values,Nil{}))
    case _: KB.create(KB.TUI_KEYBINDINGS(),R.new(List<&2,Keys.KeyId>))
def mouseType(value: String) -> Tui.TuiMouseEventType:
  match value:
    case "press": Tui.MousePress{}
    case "click": Tui.MouseClick{}
    case "wheel": Tui.MouseWheel{}
    case "release": Tui.MouseRelease{}
    case "drag": Tui.MouseDrag{}
    case _: Tui.MouseMove{}
def mouseButton(value: String) -> Tui.TuiMouseButton:
  match value:
    case "left": Tui.MouseLeft{}
    case "right": Tui.MouseRight{}
    case "middle": Tui.MouseMiddle{}
    case _: Tui.NoButton{}
def mouse(+value: V.Value) -> Tui.TuiMouseEvent:
  Tui.TuiMouseEvent{mouseType(text(get(value,"type"))),mouseButton(text(get(value,"button"))),signed(get(value,"x")),signed(get(value,"y")),signed(get(value,"screenX")),signed(get(value,"screenY")),number(get(value,"width")),number(get(value,"height")),boolean(get(value,"shift")),boolean(get(value,"alt")),boolean(get(value,"ctrl")),Some{signed(get(value,"wheelDelta"))},optionalNumber(get(value,"clickCount"))}
def result(value: Maybe<&2,Tui.TuiMouseEventResult>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Tui.TuiMouseEventResult{handled,_,focus,render}}:
      object(field("handled",V.Boolean{handled}) <> List.append(&2,R.Property<V.Value>,Bool.pick(List<&2,R.Property<V.Value>>,focus,field("focus",V.Boolean{True{}}) <> Nil{},Nil{}),Maybe.default(&2,List<&2,R.Property<V.Value>>,Maybe.map(&2,Bool,List<&2,R.Property<V.Value>>,value => field("render",V.Boolean{value}) <> Nil{},render),Nil{})))
def inputResult(state: S.SelectList) -> S.SelectList & Maybe<&2,V.Value>: (state,None{})
def mouseResult(pair: S.SelectList & Maybe<&2,Tui.TuiMouseEventResult>) -> S.SelectList & Maybe<&2,V.Value>:
  match pair:
    case (state,value): (state,Some{object(field("mouse",result(value)) <> Nil{})})
def step(+command: V.Value,+state: S.SelectList,keybindings: KB.KeybindingsManager,context: Keys.Context) -> IO(S.SelectList & Maybe<&2,V.Value>):
  +op = text(get(command,"op"))
  Bool.pick(Unit -> IO(S.SelectList & Maybe<&2,V.Value>),String.eq(op,"render"),
    _ =>
      do IO<S.SelectList & Maybe<&2,V.Value>>:
        lines : List<&2,String> <- S.render(state,number(get(command,"width")))
        return (state,Some{object(field("lines",strings(lines,Nil{})) <> Nil{})}),
    _ => Bool.pick(Unit -> IO(S.SelectList & Maybe<&2,V.Value>),String.eq(op,"input"),
      _ =>
        do IO<S.SelectList & Maybe<&2,V.Value>>:
          next : S.SelectList <- S.handleInput(state,keybindings,context,text(get(command,"data")))
          return inputResult(next),
      _ => Bool.pick(Unit -> IO(S.SelectList & Maybe<&2,V.Value>),String.eq(op,"mouse"),
        _ =>
          do IO<S.SelectList & Maybe<&2,V.Value>>:
            next : S.SelectList & Maybe<&2,Tui.TuiMouseEventResult> <- S.handleMouse(state,mouse(get(command,"event")))
            return mouseResult(next),
        _ => IO.pure(S.SelectList & Maybe<&2,V.Value>,inputResult(Bool.pick(S.SelectList,String.eq(op,"filter"),S.setFilter(state,text(get(command,"filter"))),Bool.pick(S.SelectList,String.eq(op,"index"),S.setSelectedIndex(state,number(get(command,"index"))),S.invalidate(state))))))(Unit{}))(Unit{}))(Unit{})
def observation(value: S.SelectList & Maybe<&2,V.Value>,+reversed: List<&2,V.Value>) -> S.SelectList & List<&2,V.Value>:
  match value:
    case (+state,extra): (state,object(field("selected",selected(S.getSelectedItem(state))) <> Nil{}) <> Maybe.default(&2,List<&2,V.Value>,Maybe.map(&2,V.Value,List<&2,V.Value>,entry => entry <> reversed,extra),reversed))
def steps(commands: List<&2,V.Value>,+keybindings: KB.KeybindingsManager,+context: Keys.Context,pair: S.SelectList & List<&2,V.Value>) -> IO(List<&2,V.Value>):
  match commands pair:
    case Nil{} Tuple{_,reversed}: IO.pure(List<&2,V.Value>,List.reverse(&2,V.Value,reversed))
    case command <> rest Tuple{state,reversed}:
      do IO<List<&2,V.Value>>:
        next : S.SelectList & Maybe<&2,V.Value> <- step(command,state,keybindings,context)
        steps(rest,keybindings,context,observation(next,reversed))
def commands(+value: V.Value) -> List<&2,V.Value>:
  +provided = array(get(value,"steps"))
  Bool.pick(List<&2,V.Value>,List.is_empty(&2,V.Value,provided),object(field("op",V.Text{"render"}) <> field("width",get(value,"width")) <> Nil{}) <> Nil{},provided)
def runOne(+value: V.Value) -> IO(V.Value):
  +layout = get(value,"layout")
  do IO<V.Value>:
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +prefix : C.Callback<String,String> <- C.create(~ThemeEnvironment,~String,~String,~paint,ThemeEnvironment{"selectedPrefix",boolean(get(value,"styled")),calls})
    +paintText : C.Callback<String,String> <- C.create(~ThemeEnvironment,~String,~String,~paint,ThemeEnvironment{"selectedText",boolean(get(value,"styled")),calls})
    +paintDesc : C.Callback<String,String> <- C.create(~ThemeEnvironment,~String,~String,~paint,ThemeEnvironment{"description",boolean(get(value,"styled")),calls})
    +scroll : C.Callback<String,String> <- C.create(~ThemeEnvironment,~String,~String,~paint,ThemeEnvironment{"scrollInfo",boolean(get(value,"styled")),calls})
    +noMatch : C.Callback<String,String> <- C.create(~ThemeEnvironment,~String,~String,~paint,ThemeEnvironment{"noMatch",boolean(get(value,"styled")),calls})
    +primary : C.Callback<S.SelectListTruncatePrimaryContext,String> <- C.create(~EventEnvironment,~S.SelectListTruncatePrimaryContext,~String,~custom,EventEnvironment{text(get(value,"primary")),calls})
    +select : C.Callback<S.SelectItem,Unit> <- C.create(~EventEnvironment,~S.SelectItem,~Unit,~event,EventEnvironment{"select",calls})
    +change : C.Callback<S.SelectItem,Unit> <- C.create(~EventEnvironment,~S.SelectItem,~Unit,~event,EventEnvironment{"change",calls})
    +onCancel : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<List<&2,V.Value>>,~Unit,~Unit,~cancel,calls)
    observations : List<&2,V.Value> <- steps(commands(value),manager(get(value,"bindings")),Keys.Context{boolean(get(value,"kitty")),False{}},(S.setCallbacks(S.new(items(array(get(value,"items")),Nil{}),Maybe.default(&2,Nat,optionalNumber(get(value,"maxVisible")),5n),S.SelectListTheme{prefix,paintText,paintDesc,scroll,noMatch},Some{S.SelectListLayoutOptions{optionalNumber(get(layout,"minPrimaryColumnWidth")),optionalNumber(get(layout,"maxPrimaryColumnWidth")),Bool.pick(Maybe<&2,C.Callback<S.SelectListTruncatePrimaryContext,String>>,String.eq(text(get(value,"primary")),""),None{},Some{primary})}}),Bool.pick(Maybe<&2,C.Callback<S.SelectItem,Unit>>,String.eq(text(get(value,"events")),"none"),None{},Some{select}),Bool.pick(Maybe<&2,C.Callback<Unit,Unit>>,String.eq(text(get(value,"events")),"none"),None{},Some{onCancel}),Bool.pick(Maybe<&2,C.Callback<S.SelectItem,Unit>>,String.eq(text(get(value,"events")),"none"),None{},Some{change})),Nil{}))
    C.dispose(String,String,prefix)
    C.dispose(String,String,paintText)
    C.dispose(String,String,paintDesc)
    C.dispose(String,String,scroll)
    C.dispose(String,String,noMatch)
    C.dispose(S.SelectListTruncatePrimaryContext,String,primary)
    C.dispose(S.SelectItem,Unit,select)
    C.dispose(S.SelectItem,Unit,change)
    C.dispose(Unit,Unit,onCancel)
    recorded : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,calls)
    return object(field("observations",V.ArrayValue{observations}) <> field("calls",V.ArrayValue{List.reverse(&2,V.Value,recorded)}) <> Nil{})

def runAll(values: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match values:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case value <> rest:
      do IO<V.Value>:
        result : V.Value <- runOne(value)
        runAll(rest,result <> reversed)
def parsed(result: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"invalid JSON fixture")
    case Done{value}:
      do IO<Unit>:
        output : V.Value <- runAll(array(value),Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(output)),"null"))
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    parsed(J.parse(Maybe.default(&1,String,List.head(&1,String,arguments),"[]")))
