import Base
import ../packages/tui/src/components/settings-list.bend as S
import ../packages/tui/src/components/input.bend as I
import ../packages/tui/src/component.bend as Component
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

type Context is Data:
  Context{calls: Ref.Ref<List<&2,V.Value>>,pending: Ref.Ref<List<&2,S.Completion>>,done: Ref.Ref<List<&2,S.SubmenuDone>>,children: Ref.Ref<List<&2,Component.Component>>,styled: Bool}
type PaintContext is Data: PaintContext{context: Context,kind: String}
type FactoryContext is Data: FactoryContext{context: Context,spec: V.Value}
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
    case Some{Tui.TuiMouseEventResult{handled,capture,focus,render}}:
      object(field("handled",V.Boolean{handled}) <> List.append(&2,R.Property<V.Value>,List.append(&2,R.Property<V.Value>,Bool.pick(List<&2,R.Property<V.Value>>,capture,field("capture",V.Boolean{True{}}) <> Nil{},Nil{}),Bool.pick(List<&2,R.Property<V.Value>>,focus,field("focus",V.Boolean{True{}}) <> Nil{},Nil{})),Maybe.default(&2,List<&2,R.Property<V.Value>>,Maybe.map(&2,Bool,List<&2,R.Property<V.Value>>,value => field("render",V.Boolean{value}) <> Nil{},render),Nil{})))

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

def isNull(value: V.Value) -> Bool:
  match value:
    case V.Null{}: True{}
    case _: False{}
def hasChild(value: Maybe<&2,Component.Component>) -> Bool:
  match value:
    case Some{_}: True{}
    case _: False{}
def record(context: Context,value: V.Value) -> IO(Unit):
  match context:
    case Context{calls,_,_,_,_}: log(calls,value)
def dispatch(context: Context,value: S.Completion) -> IO(Unit):
  match context:
    case Context{_,pending,_,_,_}: Ref.modify(List<&2,S.Completion>,Unit,pending,previous => (value <> previous,Unit{}))
def painted(context: Context,+text: String) -> String:
  match context:
    case Context{_,_,_,_,styled}: Bool.pick(String,styled,"\u{1b}[31m" ++ text ++ "\u{1b}[39m",text)
def paint(pair: PaintContext,value: S.ThemeText) -> IO(String):
  match pair value:
    case PaintContext{+context,kind} S.ThemeText{+text,selected}:
      do IO<String>:
        record(context,object(field("kind",V.Text{kind}) <> field("text",V.Text{text}) <> field("selected",V.Boolean{selected}) <> Nil{}))
        return painted(context,text)
def plainCore(pair: PaintContext,+text: String) -> IO(String):
  match pair:
    case PaintContext{+context,kind}:
      do IO<String>:
        record(context,object(field("kind",V.Text{kind}) <> field("text",V.Text{text}) <> Nil{}))
        return painted(context,text)
def plain(pair: PaintContext,text: String) -> IO(String): plainCore(pair,text)
def change(context: Context,value: S.Change) -> IO(Unit):
  match value:
    case S.Change{id,value}: record(context,object(field("kind",V.Text{"change"}) <> field("id",V.Text{id}) <> field("value",V.Text{value}) <> Nil{}))
def cancel(context: Context,value: Unit) -> IO(Unit): record(context,object(field("kind",V.Text{"cancel"}) <> Nil{}))
type Child is Data: Child{context: Context,id: String,done: S.SubmenuDone,mouse: String}
def childRecord(child: Child,kind: String,extra: List<&2,R.Property<V.Value>>) -> IO(Unit):
  match child:
    case Child{context,id,_,_}: record(context,object(field("kind",V.Text{kind}) <> field("id",V.Text{id}) <> extra))
def childRenderCore(+child: Child,+width: Nat) -> IO(List<&2,String>):
  match child:
    case Child{_,id,_,_}:
      do IO<List<&2,String>>:
        childRecord(child,"child-render",field("width",num(width)) <> Nil{})
        return ("submenu:" ++ id ++ ":" ++ Nat.show(width)) <> Nil{}
def childRender(child: Child,width: Nat) -> IO(List<&2,String>): childRenderCore(child,width)
def childInvalidate(child: Child,value: Unit) -> IO(Unit): childRecord(child,"child-invalidate",Nil{})
def childInputCore(+child: Child,+data: String) -> IO(Unit):
  match child:
    case Child{_,id,done,_}:
      do IO<Unit>:
        childRecord(child,"child-input",field("data",V.Text{data}) <> Nil{})
        Bool.pick(Unit -> IO(Unit),String.eq(data,"save"),_ => S.complete(done,Some{"selected:" ++ id},None{}),
          _ => Bool.pick(Unit -> IO(Unit),String.eq(data,"cancel"),_ => S.complete(done,None{},None{}),
            _ => Bool.pick(Unit -> IO(Unit),String.eq(String.take(data,5n),"goto:"),_ => S.complete(done,None{},Some{String.drop(data,5n)}),_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{})
def childInput(child: Child,data: String) -> IO(Unit): childInputCore(child,data)
def eventName(event: Tui.TuiMouseEventType) -> String:
  match event:
    case Tui.MousePress{}: "press"
    case Tui.MouseClick{}: "click"
    case Tui.MouseWheel{}: "wheel"
    case Tui.MouseRelease{}: "release"
    case Tui.MouseDrag{}: "drag"
    case _: "move"
def childMouseCore(+child: Child,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match child event:
    case Child{_,_,_,+mode} Tui.TuiMouseEvent{kind,_,_,y,_,_,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        childRecord(child,"child-mouse",field("type",V.Text{eventName(kind)}) <> field("y",signedValue(y)) <> Nil{})
        return Bool.pick(Maybe<&2,Component.MouseResponse>,String.eq(mode,"none"),None{},Some{Component.LocalResult{Tui.TuiMouseEventResult{Bool.not(String.eq(mode,"unhandled")),String.eq(mode,"capture"),False{},Bool.pick(Maybe<&2,Bool>,String.eq(mode,"unhandled"),None{},Some{False{}})}}})
def childMouse(child: Child,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>): childMouseCore(child,event)
def rememberDone(context: Context,done: S.SubmenuDone) -> IO(Unit):
  match context:
    case Context{_,_,values,_,_}: Ref.modify(List<&2,S.SubmenuDone>,Unit,values,previous => (List.append(&2,S.SubmenuDone,previous,done <> Nil{}),Unit{}))
def rememberChild(context: Context,+child: Component.Component) -> IO(Component.Component):
  match context:
    case Context{_,_,_,values,_}:
      do IO<Component.Component>:
        Ref.modify(List<&2,Component.Component>,Unit,values,previous => (child <> previous,Unit{}))
        return child

def factory(pair: FactoryContext,request: S.SubmenuRequest) -> IO(Component.Component):
  match pair request:
    case FactoryContext{+context,+spec} S.SubmenuRequest{value,+done}:
      +child = {Child{context,text(get(spec,"id")),done,text(get(get(spec,"submenu"),"mouse"))}: Child}
      do IO<Component.Component>:
        record(context,object(field("kind",V.Text{"open"}) <> field("id",get(spec,"id")) <> field("currentValue",V.Text{value}) <> Nil{}))
        rememberDone(context,done)
        render : C.Callback<Nat,List<&2,String>> <- C.create(~Child,~Nat,~List<&2,String>,~childRender,child)
        input : C.Callback<String,Unit> <- C.create(~Child,~String,~Unit,~childInput,child)
        mouse : C.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- C.create(~Child,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~childMouse,child)
        invalidate : C.Callback<Unit,Unit> <- C.create(~Child,~Unit,~Unit,~childInvalidate,child)
        rememberChild(context,Component.Component{Component.ComponentId{0n},render,Some{input},Some{mouse},invalidate,None{},False{}})
def texts(values: List<&2,V.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: text(value) <> texts(rest)
def values(value: V.Value) -> Maybe<&2,List<&2,String>>:
  match value:
    case V.ArrayValue{items}: Some{texts(items)}
    case _: None{}
def item(+context: Context,+value: V.Value) -> IO(S.SettingItem):
  do IO<S.SettingItem>:
    submenu : Maybe<&2,C.Callback<S.SubmenuRequest,Component.Component>> <- Bool.pick(Unit -> IO(Maybe<&2,C.Callback<S.SubmenuRequest,Component.Component>>),isNull(get(value,"submenu")),_ => IO.pure(Maybe<&2,C.Callback<S.SubmenuRequest,Component.Component>>,None{}),
      _ =>
        do IO<Maybe<&2,C.Callback<S.SubmenuRequest,Component.Component>>>:
          callback : C.Callback<S.SubmenuRequest,Component.Component> <- C.create(~FactoryContext,~S.SubmenuRequest,~Component.Component,~factory,FactoryContext{context,value})
          return Some{callback})(Unit{})
    return S.SettingItem{text(get(value,"id")),text(get(value,"label")),optionalText(get(value,"description")),text(get(value,"currentValue")),values(get(value,"values")),submenu}
def items(+context: Context,values: List<&2,V.Value>,reversed: List<&2,S.SettingItem>) -> IO(List<&2,S.SettingItem>):
  match values:
    case Nil{}: IO.pure(List<&2,S.SettingItem>,List.reverse(&2,S.SettingItem,reversed))
    case value <> rest:
      do IO<List<&2,S.SettingItem>>:
        next : S.SettingItem <- item(context,value)
        items(context,rest,next <> reversed)
def itemValue(item: S.SettingItem) -> V.Value:
  match item:
    case S.SettingItem{id,_,_,value,_,_}: object(field("id",V.Text{id}) <> field("value",V.Text{value}) <> Nil{})
def itemValues(values: List<&2,S.SettingItem>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: itemValue(value) <> itemValues(rest)
def selected(item: Maybe<&2,S.SettingItem>) -> V.Value:
  match item:
    case Some{S.SettingItem{id,_,_,_,_,_}}: V.Text{id}
    case _: V.Null{}
def snapshot(+state: S.SettingsList,extra: List<&2,R.Property<V.Value>>) -> V.Value:
  match state:
    case S.SettingsList{items,_,_,_,_,_,_,_,search,child,_,_}: object(field("items",V.ArrayValue{itemValues(items)}) <> field("selected",selected(S.getSelectedItem(state))) <> field("search",Maybe.default(&2,V.Value,Maybe.map(&2,I.Input,V.Value,input => V.Text{I.getValue(input)},search),V.Null{})) <> field("submenu",V.Boolean{hasChild(child)}) <> extra)
def rendered(pair: S.SettingsList & List<&2,String>) -> S.SettingsList & List<&2,R.Property<V.Value>>:
  match pair:
    case (state,lines): (state,field("lines",strings(lines,Nil{})) <> Nil{})
def mouseResult(response: Maybe<&2,Component.MouseResponse>) -> V.Value:
  match response:
    case Some{Component.LocalResult{response}}: result(Some{response})
    case _: V.Null{}
def clicked(pair: S.SettingsList & Maybe<&2,Component.MouseResponse>) -> S.SettingsList & List<&2,R.Property<V.Value>>:
  match pair:
    case (state,value): (state,field("mouse",mouseResult(value)) <> Nil{})
def received(value: Word.ResultOf(S.SettingsList)) -> IO(S.SettingsList & List<&2,R.Property<V.Value>>):
  match value:
    case Done{state}: IO.pure(S.SettingsList & List<&2,R.Property<V.Value>>,(state,Nil{}))
    case _: IO.die(S.SettingsList & List<&2,R.Property<V.Value>>,1,"word failure")
def completeAt(values: List<&2,S.SubmenuDone>,index: Nat,selected: Maybe<&2,String>,target: Maybe<&2,String>) -> IO(Unit):
  match values index:
    case done <> _ Zero{}: S.complete(done,selected,target)
    case _ <> rest Succ{index}: completeAt(rest,index,selected,target)
    case _ _: IO.die(Unit,1,"missing completion")
def external(context: Context,+command: V.Value) -> IO(Unit):
  match context:
    case Context{_,_,done,_,_}:
      do IO<Unit>:
        retained : List<&2,S.SubmenuDone> <- Ref.read(List<&2,S.SubmenuDone>,done)
        completeAt(retained,number(get(command,"origin")),optionalText(get(command,"value")),optionalText(get(command,"navigateTo")))
def stepOp(context: Context,+command: V.Value,+state: S.SettingsList,manager: KB.KeybindingsManager,keyboard: Keys.Context,op: String) -> IO(S.SettingsList & List<&2,R.Property<V.Value>>):
  match op:
    case "input":
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        next : Word.ResultOf(S.SettingsList) <- S.handleInput(~V.Value,~segment,~atomic,get(command,"segments"),state,manager,keyboard,text(get(command,"data")))
        received(next)
    case "render":
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        next : S.SettingsList & List<&2,String> <- S.render(state,number(get(command,"width")))
        return rendered(next)
    case "mouse":
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        next : S.SettingsList & Maybe<&2,Component.MouseResponse> <- S.handleMouse(state,mouse(get(command,"event")))
        return clicked(next)
    case "update": IO.pure(S.SettingsList & List<&2,R.Property<V.Value>>,(S.updateValue(state,text(get(command,"id")),text(get(command,"value"))),Nil{}))
    case "select": IO.pure(S.SettingsList & List<&2,R.Property<V.Value>>,(S.selectItem(state,text(get(command,"id"))),Nil{}))
    case "complete":
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        external(context,command)
        return (state,Nil{})
    case _:
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        next : S.SettingsList <- S.invalidate(state)
        return (next,Nil{})
def step(context: Context,+command: V.Value,+state: S.SettingsList,manager: KB.KeybindingsManager,keyboard: Keys.Context) -> IO(S.SettingsList & List<&2,R.Property<V.Value>>):
  stepOp(context,command,state,manager,keyboard,text(get(command,"op")))
def applyPending(values: List<&2,S.Completion>,state: S.SettingsList) -> IO(S.SettingsList):
  match values:
    case Nil{}: IO.pure(S.SettingsList,state)
    case value <> rest:
      do IO<S.SettingsList>:
        next : S.SettingsList <- S.completeSubmenu(state,value)
        applyPending(rest,next)
def drained(context: Context,pair: S.SettingsList & List<&2,R.Property<V.Value>>) -> IO(S.SettingsList & List<&2,R.Property<V.Value>>):
  match context pair:
    case Context{_,pending,_,_,_} Tuple{state,extra}:
      do IO<S.SettingsList & List<&2,R.Property<V.Value>>>:
        values : List<&2,S.Completion> <- Ref.modify(List<&2,S.Completion>,List<&2,S.Completion>,pending,values => (Nil{},List.reverse(&2,S.Completion,values)))
        next : S.SettingsList <- applyPending(values,state)
        return (next,extra)
def observation(pair: S.SettingsList & List<&2,R.Property<V.Value>>,reversed: List<&2,V.Value>) -> S.SettingsList & List<&2,V.Value>:
  match pair:
    case (+state,extra): (state,snapshot(state,extra) <> reversed)
def steps(+context: Context,commands: List<&2,V.Value>,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,pair: S.SettingsList & List<&2,V.Value>) -> IO(List<&2,V.Value>):
  match commands pair:
    case Nil{} Tuple{_,reversed}: IO.pure(List<&2,V.Value>,List.reverse(&2,V.Value,reversed))
    case command <> rest Tuple{state,reversed}:
      do IO<List<&2,V.Value>>:
        next : S.SettingsList & List<&2,R.Property<V.Value>> <- step(context,command,state,manager,keyboard)
        completed : S.SettingsList & List<&2,R.Property<V.Value>> <- drained(context,next)
        steps(context,rest,manager,keyboard,observation(completed,reversed))
def disposeItems(values: List<&2,S.SettingItem>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case S.SettingItem{_,_,_,_,_,Some{callback}} <> rest:
      do IO<Unit>:
        C.dispose(S.SubmenuRequest,Component.Component,callback)
        disposeItems(rest)
    case _ <> rest: disposeItems(rest)
def disposeChildren(values: List<&2,Component.Component>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case Component.Component{_,render,Some{input},Some{mouse},invalidate,_,_} <> rest:
      do IO<Unit>:
        C.dispose(Nat,List<&2,String>,render)
        C.dispose(String,Unit,input)
        C.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouse)
        C.dispose(Unit,Unit,invalidate)
        disposeChildren(rest)
    case _ <> rest: disposeChildren(rest)
def runOne(+value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +pending : Ref.Ref<List<&2,S.Completion>> <- Ref.new(List<&2,S.Completion>,Nil{})
    +done : Ref.Ref<List<&2,S.SubmenuDone>> <- Ref.new(List<&2,S.SubmenuDone>,Nil{})
    +children : Ref.Ref<List<&2,Component.Component>> <- Ref.new(List<&2,Component.Component>,Nil{})
    +context : Context = Context{calls,pending,done,children,boolean(get(value,"styled"))}
    +label : C.Callback<S.ThemeText,String> <- C.create(~PaintContext,~S.ThemeText,~String,~paint,PaintContext{context,"label"})
    +paintValue : C.Callback<S.ThemeText,String> <- C.create(~PaintContext,~S.ThemeText,~String,~paint,PaintContext{context,"value"})
    +description : C.Callback<String,String> <- C.create(~PaintContext,~String,~String,~plain,PaintContext{context,"description"})
    +hint : C.Callback<String,String> <- C.create(~PaintContext,~String,~String,~plain,PaintContext{context,"hint"})
    +onChange : C.Callback<S.Change,Unit> <- C.create(~Context,~S.Change,~Unit,~change,context)
    +onCancel : C.Callback<Unit,Unit> <- C.create(~Context,~Unit,~Unit,~cancel,context)
    +onComplete : C.Callback<S.Completion,Unit> <- C.create(~Context,~S.Completion,~Unit,~dispatch,context)
    +settings : List<&2,S.SettingItem> <- items(context,array(get(value,"items")),Nil{})
    observations : List<&2,V.Value> <- steps(context,array(get(value,"steps")),manager(get(value,"bindings")),Keys.Context{boolean(get(value,"kitty")),False{}},(S.new(settings,number(get(value,"maxVisible")),S.SettingsListTheme{label,paintValue,description,Maybe.default(&2,String,optionalText(get(value,"cursor")),"> "),hint},onChange,onCancel,Some{S.SettingsListOptions{boolean(get(get(value,"options"),"enableSearch"))}},onComplete),Nil{}))
    disposeItems(settings)
    retired : List<&2,Component.Component> <- Ref.dispose(List<&2,Component.Component>,children)
    disposeChildren(retired)
    ignoredDone : List<&2,S.SubmenuDone> <- Ref.dispose(List<&2,S.SubmenuDone>,done)
    ignoredPending : List<&2,S.Completion> <- Ref.dispose(List<&2,S.Completion>,pending)
    C.dispose(S.ThemeText,String,label)
    C.dispose(S.ThemeText,String,paintValue)
    C.dispose(String,String,description)
    C.dispose(String,String,hint)
    C.dispose(S.Change,Unit,onChange)
    C.dispose(Unit,Unit,onCancel)
    C.dispose(S.Completion,Unit,onComplete)
    recorded : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,calls)
    return object(field("observations",V.ArrayValue{observations}) <> field("calls",V.ArrayValue{List.reverse(&2,V.Value,recorded)}) <> Nil{})
def runAll(values: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match values:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case value <> rest:
      do IO<V.Value>:
        next : V.Value <- runOne(value)
        runAll(rest,next <> reversed)
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"invalid JSON fixture")
    case Done{value}:
      do IO<Unit>:
        output : V.Value <- runAll(array(value),Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(output)),"null"))
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    parsed(J.parse(Maybe.default(&1,String,List.head(&1,String,arguments),"[]")))
