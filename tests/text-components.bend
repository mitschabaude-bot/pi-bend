import Base
import ../packages/tui/src/components/text.bend as T
import ../packages/tui/src/components/truncated-text.bend as Short
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
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
def record(kind: String,input: String,+calls: List<&2,V.Value>) -> List<&2,V.Value> & Nat:
  (V.ObjectValue{R.Record{field("kind",V.Text{kind}) <> field("text",V.Text{input}) <> Nil{}}} <> calls,Succ{List.length(&2,V.Value,calls)})
type Background is Data:
  Background{kind: String,calls: Ref.Ref<List<&2,V.Value>>}
def background(environment: Background,input: String) -> IO(String):
  match environment:
    case Background{+kind,calls}:
      +input = {input: String}
      do IO<String>:
        count : Nat <- Ref.modify(List<&2,V.Value>,Nat,calls,previous => record(kind,input,previous))
        return Bool.pick(String,String.eq(kind,"counter"),"[" ++ Nat.show(count) ++ "]" ++ input,"\u{1b}[" ++ Bool.pick(String,String.eq(kind,"red"),"41","44") ++ "m" ++ input ++ "\u{1b}[49m")
type Backgrounds is Data:
  Backgrounds{red: C.Callback<String,String>,blue: C.Callback<String,String>,counter: C.Callback<String,String>}
def selected(callbacks: Backgrounds,kind: String) -> Maybe<&2,C.Callback<String,String>>:
  match callbacks kind:
    case Backgrounds{red,_,_} "red": Some{red}
    case Backgrounds{_,blue,_} "blue": Some{blue}
    case Backgrounds{_,_,counter} "counter": Some{counter}
    case _ _: None{}

def rendered(pair: T.Text & List<&2,String>,reversed: List<&2,V.Value>) -> T.Text & List<&2,V.Value>:
  match pair:
    case (state,lines): (state,strings(lines,Nil{}) <> reversed)
def step(+command: V.Value,+callbacks: Backgrounds,+state: T.Text,+reversed: List<&2,V.Value>) -> IO(T.Text & List<&2,V.Value>):
  +operation = text(get(command,"op"))
  Bool.pick(Unit -> IO(T.Text & List<&2,V.Value>),String.eq(operation,"render"),
    _ =>
      do IO<T.Text & List<&2,V.Value>>:
        pair : T.Text & List<&2,String> <- T.render(state,number(get(command,"width")))
        return rendered(pair,reversed),
    _ => IO.pure(T.Text & List<&2,V.Value>,(Bool.pick(T.Text,String.eq(operation,"text"),T.setText(state,text(get(command,"text"))),Bool.pick(T.Text,String.eq(operation,"background"),T.setCustomBgFn(state,selected(callbacks,text(get(command,"kind")))),T.invalidate(state))),reversed)))(Unit{})
def steps(commands: List<&2,V.Value>,+callbacks: Backgrounds,pair: T.Text & List<&2,V.Value>) -> IO(List<&2,V.Value>):
  match commands pair:
    case Nil{} Tuple{_,reversed}: IO.pure(List<&2,V.Value>,List.reverse(&2,V.Value,reversed))
    case Con{command,rest} Tuple{state,reversed}:
      do IO<List<&2,V.Value>>:
        next : T.Text & List<&2,V.Value> <- step(command,callbacks,state,reversed)
        steps(rest,callbacks,next)
def commands(+value: V.Value) -> List<&2,V.Value>:
  +provided = array(get(value,"steps"))
  Bool.pick(List<&2,V.Value>,List.is_empty(&2,V.Value,provided),V.ObjectValue{R.Record{field("op",V.Text{"render"}) <> field("width",get(value,"width")) <> Nil{}}} <> Nil{},provided)
def query(+value: V.Value,+callbacks: Backgrounds) -> IO(List<&2,V.Value>):
  Bool.pick(Unit -> IO(List<&2,V.Value>),String.eq(text(get(value,"component")),"truncated"),
    _ => IO.pure(List<&2,V.Value>,strings(Short.render(Short.invalidate(Short.new(text(get(value,"text")),optionalNumber(get(value,"paddingX")),optionalNumber(get(value,"paddingY")))),number(get(value,"width"))),Nil{}) <> Nil{}),
    _ => steps(commands(value),callbacks,(T.new(text(get(value,"text")),optionalNumber(get(value,"paddingX")),optionalNumber(get(value,"paddingY")),selected(callbacks,text(get(value,"background")))),Nil{})))(Unit{})
def runOne(value: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +calls : Ref.Ref<List<&2,V.Value>> <- Ref.new(List<&2,V.Value>,Nil{})
    +red : C.Callback<String,String> <- C.create(~Background,~String,~String,~background,Background{"red",calls})
    +blue : C.Callback<String,String> <- C.create(~Background,~String,~String,~background,Background{"blue",calls})
    +counter : C.Callback<String,String> <- C.create(~Background,~String,~String,~background,Background{"counter",calls})
    results : List<&2,V.Value> <- query(value,Backgrounds{red,blue,counter})
    C.dispose(String,String,red)
    C.dispose(String,String,blue)
    C.dispose(String,String,counter)
    recorded : List<&2,V.Value> <- Ref.dispose(List<&2,V.Value>,calls)
    return V.ObjectValue{R.Record{field("renders",V.ArrayValue{results}) <> field("calls",V.ArrayValue{List.reverse(&2,V.Value,recorded)}) <> Nil{}}}
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
