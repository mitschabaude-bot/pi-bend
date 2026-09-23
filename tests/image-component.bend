import Base
import ../packages/tui/src/components/image.bend as I
import ../packages/tui/src/terminal-image.bend as T
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/json.bend as J
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
def number(value: V.Value) -> F64:
  match value:
    case V.Number{value}: value
    case _: U32.to_f64(0)
def natural(value: Result<&2,&2,F.Error,Nat>) -> Nat:
  match value:
    case Done{value}: value
    case Fail{_}: 0n
def n(value: V.Value) -> Nat: natural(F.convert(number(value)))
def b(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def optionalNumber(value: V.Value) -> Maybe<&2,F64>:
  match value:
    case V.Number{value}: Some{value}
    case _: None{}
def optionalId(value: V.Value) -> Maybe<&2,U32>: Maybe.map(&2,F64,U32,F64.to_u32,optionalNumber(value))
def optionalText(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{value}: Some{value}
    case _: None{}
def optionalBool(value: V.Value) -> Maybe<&2,Bool>:
  match value:
    case V.Boolean{value}: Some{value}
    case _: None{}
def protocol(value: String) -> T.ImageProtocol:
  match value:
    case "kitty": T.Kitty{}
    case "iterm2": T.ITerm2{}
    case _: T.NoImages{}
def overrides(+v: V.Value) -> T.CapabilityOverrides:
  T.CapabilityOverrides{Maybe.map(&2,String,T.ImageProtocol,protocol,optionalText(get(v,"images"))),optionalBool(get(v,"trueColor")),optionalBool(get(v,"hyperlinks"))}
def variables(items: List<&2,R.Property<V.Value>>,record: R.Record<String>) -> R.Record<String>:
  match items:
    case Nil{}: record
    case R.Property{key,V.Text{value}} <> rest: variables(rest,R.set(String,record,key,value))
    case _ <> rest: variables(rest,record)
def envFields(v: V.Value) -> R.Record<String>:
  match v:
    case V.ObjectValue{R.Record{fields}}: variables(fields,R.new(String))
    case _: R.new(String)
def environment(+v: V.Value) -> T.Environment: T.Environment{envFields(get(v,"env")),text(get(v,"platform")),text(get(v,"home"))}
def dims(+v: V.Value) -> T.ImageDimensions: T.ImageDimensions{F64.to_u32(number(get(v,"widthPx"))),F64.to_u32(number(get(v,"heightPx")))}
def cells(v: V.Value) -> T.CellDimensions:
  match v:
    case V.Null{}: T.defaultCellDimensions()
    case +v: T.CellDimensions{number(get(v,"widthPx")),number(get(v,"heightPx"))}
def obj(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def c(n: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(n))}
def stateResult(value: Result<&2,&2,T.Error,T.State>) -> T.State:
  match value:
    case Done{state}: state
    case Fail{_}: T.create()
def prepared(+v: V.Value) -> T.State:
  T.setCapabilityOverrides(stateResult(T.setCellDimensions(T.create(),cells(get(v,"cells")))),overrides(get(v,"overrides")))
def optionalDims(v: V.Value) -> Maybe<&2,T.ImageDimensions>:
  match v:
    case V.Null{}: None{}
    case v: Some{dims(v)}
type Paint is Data: Paint{count: Ref.Ref<Nat>,prefix: String,suffix: String}
def color(paint: Paint,value: String) -> IO(String):
  match paint:
    case Paint{count,prefix,suffix}:
      do IO<String>:
        next : Unit <- Ref.modify(Nat,Unit,count,n => (n+1n,Unit{}))
        return prefix ++ value ++ suffix
def lineValues(values: List<&2,String>,reversed: List<&2,V.Value>) -> V.Value:
  match values:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case value <> rest: lineValues(rest,V.Text{value} <> reversed)
def lines(values: List<&2,String>) -> V.Value: lineValues(values,Nil{})
def step(value: I.Rendered) -> V.Value:
  match value:
    case I.Rendered{+image,_,text}: obj([R.Property{"lines",lines(text)},R.Property{"id",Maybe.default(&2,V.Value,Maybe.map(&2,U32,V.Value,id => c(U32.to_nat(id)),I.getImageId(image)),V.Null{})}])
def one(result: Result<&2,&2,I.Error,I.Rendered>) -> V.Value:
  match result:
    case Done{value}: step(value)
    case Fail{_}: V.Null{}
def configured(+v: V.Value) -> I.ImageOptions: I.ImageOptions{optionalNumber(get(v,"maxWidthCells")),optionalNumber(get(v,"maxHeightCells")),optionalText(get(v,"filename")),optionalId(get(v,"imageId"))}
def after(next: I.ImageComponent -> T.State -> List<&2,V.Value> -> IO(V.Value),result: Result<&2,&2,I.Error,I.Rendered>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match result:
    case Fail{_}: IO.pure(V.Value,V.Null{})
    case Done{I.Rendered{+image,+terminal,+text}}: next(image,terminal,step(I.Rendered{image,terminal,text}) <> reversed)
def terminalUpdate(terminal: T.State,value: V.Value) -> T.State:
  match value:
    case V.Null{}: terminal
    case +value: T.setCapabilities(terminal,T.TerminalCapabilities{protocol(text(get(value,"images"))),b(get(value,"trueColor")),b(get(value,"hyperlinks"))})
@unsafe def rerender(+image: I.ImageComponent,terminal: T.State,+environment: T.Environment,steps: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match steps:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case +item <> rest:
      do IO<V.Value>:
        result : Result<&2,&2,I.Error,I.Rendered> <- I.render(Bool.pick(I.ImageComponent,b(get(item,"invalidate")),I.invalidate(image),image),n(get(item,"width")),terminalUpdate(terminal,get(item,"caps")),environment,False{})
        after(nextImage => nextTerminal => values => rerender(nextImage,nextTerminal,environment,rest,values),result,reversed)
def started(result: Result<&2,&2,I.Error,I.ImageComponent>,terminal: T.State,environment: T.Environment,steps: V.Value) -> IO(V.Value):
  match result steps:
    case Done{image} V.ArrayValue{items}: rerender(image,terminal,environment,items,Nil{})
    case _ _: IO.pure(V.Value,V.Null{})
def query(+v: V.Value) -> IO(V.Value):
  do IO<V.Value>:
    +count : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +callback : C.Callback<String,String> <- C.create(~Paint,~String,~String,~color,Paint{count,text(get(v,"prefix")),text(get(v,"suffix"))})
    output : V.Value <- started(I.new(text(get(v,"data")),text(get(v,"mime")),I.ImageTheme{callback},configured(get(v,"options")),optionalDims(get(v,"dimensions"))),prepared(v),environment(v),get(v,"steps"))
    C.dispose(String,String,callback)
    calls : Nat <- Ref.dispose(Nat,count)
    return obj([R.Property{"results",output},R.Property{"callbacks",c(calls)}])
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> IO(V.Value):
  match items:
    case Nil{}: IO.pure(V.Value,V.ArrayValue{List.reverse(&2,V.Value,reversed)})
    case item <> rest:
      do IO<V.Value>:
        result : V.Value <- query(item)
        queries(rest,result <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}:
      do IO<Unit>:
        result : V.Value <- queries(items,Nil{})
        IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(result)),"null"))
    case _: IO.die(Unit,1,"invalid input")
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case input <> rest:
      do IO<Unit>:
        program(J.parse(input))
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
