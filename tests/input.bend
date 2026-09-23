import Base
import ../packages/tui/src/components/input.bend as I
import ../packages/tui/src/tui.bend as Tui
import ../packages/tui/src/word-navigation.bend as Word
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

def parts(values: List<&2,V.Value>,reversed: List<&2,Word.Segment>) -> List<&2,Word.Segment>:
  match values:
    case Nil{}: List.reverse(&2,Word.Segment,reversed)
    case V.ArrayValue{V.Text{text} <> V.Boolean{word} <> Nil{}} <> rest: parts(rest,Word.Segment{text,word} <> reversed)
    case _: Word.Segment{"",False{}} <> Nil{}
def segment(context: V.Value,input: String) -> Word.ResultOf(List<&2,Word.Segment>):
  match context:
    case V.Text{language}: Fail{Word.MissingWordEngine{language}}
    case context: Done{parts(array(get(context,input)),Nil{})}
def atomic(context: V.Value,input: String) -> Bool: False{}
def log(calls: Ref.Ref<List<&2,V.Value>>,value: V.Value) -> IO(Unit):
  Ref.modify(List<&2,V.Value>,Unit,calls,previous => (value <> previous,Unit{}))
def style(calls: Ref.Ref<List<&2,V.Value>>,input: String) -> IO(String):
  +input = {input: String}
  do IO<String>:
    log(calls,object(field("kind",V.Text{"style"}) <> field("text",V.Text{input}) <> Nil{}))
    return "\u{1b}[2m" ++ input ++ "\u{1b}[22m"
def submit(calls: Ref.Ref<List<&2,V.Value>>,value: String) -> IO(Unit):
  log(calls,object(field("kind",V.Text{"submit"}) <> field("value",V.Text{value}) <> Nil{}))
def escape(calls: Ref.Ref<List<&2,V.Value>>,unused: Unit) -> IO(Unit):
  log(calls,object(field("kind",V.Text{"escape"}) <> Nil{}))
def rendered(pair: I.Input & List<&2,String>) -> I.Input & List<&2,R.Property<V.Value>>:
  match pair:
    case (state,lines): (state,field("lines",strings(lines,Nil{})) <> Nil{})
def clicked(pair: I.Input & Maybe<&2,Tui.TuiMouseEventResult>) -> I.Input & List<&2,R.Property<V.Value>>:
  match pair:
    case (state,value): (state,field("mouse",result(value)) <> Nil{})
def received(state: I.Input,value: Word.ResultOf(I.Input)) -> IO(I.Input & List<&2,R.Property<V.Value>>):
  match value:
    case Done{state}: IO.pure(I.Input & List<&2,R.Property<V.Value>>,(state,Nil{}))
    case Fail{Word.MissingWordEngine{language}}: IO.pure(I.Input & List<&2,R.Property<V.Value>>,(state,field("error",object(field("missingWordEngine",V.Text{language}) <> Nil{})) <> Nil{}))
    case Fail{_}: IO.die(I.Input & List<&2,R.Property<V.Value>>,1,"invalid injected word segmentation")
def step(+command: V.Value,state: I.Input,keybindings: KB.KeybindingsManager,context: Keys.Context) -> IO(I.Input & List<&2,R.Property<V.Value>>):
  +state = I.setFocused(state,boolean(get(command,"focused")))
  +op = text(get(command,"op"))
  Bool.pick(Unit -> IO(I.Input & List<&2,R.Property<V.Value>>),String.eq(op,"input"),
    _ =>
      do IO<I.Input & List<&2,R.Property<V.Value>>>:
        next : Word.ResultOf(I.Input) <- I.handleInput(~V.Value,~segment,~atomic,get(command,"segments"),state,keybindings,context,text(get(command,"data")))
        received(state,next),
    _ => Bool.pick(Unit -> IO(I.Input & List<&2,R.Property<V.Value>>),String.eq(op,"render"),
      _ =>
        do IO<I.Input & List<&2,R.Property<V.Value>>>:
          next : I.Input & List<&2,String> <- I.render(state,number(get(command,"width")))
          return rendered(next),
      _ => IO.pure(I.Input & List<&2,R.Property<V.Value>>,Bool.pick(Unit -> I.Input & List<&2,R.Property<V.Value>>,String.eq(op,"mouse"),
        _ => clicked(I.handleMouse(state,mouse(get(command,"event")))),
        _ => (Bool.pick(I.Input,String.eq(op,"set"),I.setValue(state,text(get(command,"value"))),I.invalidate(state)),Nil{}))(Unit{})))(Unit{}))(Unit{})
def observation(pair: I.Input & List<&2,R.Property<V.Value>>,reversed: List<&2,V.Value>) -> I.Input & List<&2,V.Value>:
  match pair:
    case (+state,extra): (state,object(field("value",V.Text{I.getValue(state)}) <> field("cursor",num(I.getCursor(state))) <> extra) <> reversed)
def steps(commands: List<&2,V.Value>,+keybindings: KB.KeybindingsManager,+context: Keys.Context,pair: I.Input & List<&2,V.Value>) -> IO(List<&2,V.Value>):
  match commands pair:
    case Nil{} Tuple{_,reversed}: IO.pure(List<&2,V.Value>,List.reverse(&2,V.Value,reversed))
    case command <> rest Tuple{state,reversed}:
      do IO<List<&2,V.Value>>:
        next : I.Input & List<&2,R.Property<V.Value>> <- step(command,state,keybindings,context)
        steps(rest,keybindings,context,observation(next,reversed))
def runOne(+value: V.Value) -> IO(V.Value):
  +options = get(value,"options")
  do IO<V.Value>:
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +placeholderStyle : C.Callback<String,String> <- C.create(~Ref.Ref<List<&2,V.Value>>,~String,~String,~style,calls)
    +onSubmit : C.Callback<String,Unit> <- C.create(~Ref.Ref<List<&2,V.Value>>,~String,~Unit,~submit,calls)
    +onEscape : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<List<&2,V.Value>>,~Unit,~Unit,~escape,calls)
    observations : List<&2,V.Value> <- steps(array(get(value,"steps")),manager(get(value,"bindings")),Keys.Context{boolean(get(value,"kitty")),False{}},(I.setCallbacks(I.new(Some{I.InputOptions{optionalText(get(options,"prompt")),optionalText(get(options,"placeholder")),Bool.pick(Maybe<&2,C.Callback<String,String>>,String.eq(text(get(options,"style")),""),None{},Some{placeholderStyle})}}),Some{onSubmit},Some{onEscape}),Nil{}))
    C.dispose(String,String,placeholderStyle)
    C.dispose(String,Unit,onSubmit)
    C.dispose(Unit,Unit,onEscape)
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
