import Base
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson

def get(value: V.Value,key: String) -> V.Value:
  match value:
    case V.ObjectValue{fields}: Maybe.default(&2,V.Value,R.get(V.Value,fields,key),V.Null{})
    case _: V.Null{}
def natural(value: V.Value) -> Nat:
  match value:
    case V.Number{value}: U32.to_nat(F64.to_u32(F.maximum(F.fromU32(0),value)))
    case _: 0n
def percent(value: Result<&2,&2,J.ParseError,V.Value>) -> Maybe<&2,T.SizeValue>:
  match value:
    case Done{V.Number{value}}: Some{T.Percent{value}}
    case _: Some{T.Percent{F.nan()}}
def size(value: V.Value) -> Maybe<&2,T.SizeValue>:
  match value:
    case V.Null{}: None{}
    case V.Number{value}: Some{T.Cells{natural(V.Number{value})}}
    case V.Text{+value}: percent(J.parse(String.take(value,String.length(value) - 1n)))
    case _: Some{T.Percent{F.nan()}}
def offset(value: V.Value) -> T.Offset:
  match value:
    case V.Number{+value}: Bool.pick(Unit -> T.Offset,F.isGreater(F.compare(F.fromU32(0),value)),_ => T.Backward{U32.to_nat(F64.to_u32(F.negate(value)))},_ => T.Forward{U32.to_nat(F64.to_u32(value))})(Unit{})
    case _: T.Forward{0n}
def anchor(value: V.Value) -> T.OverlayAnchor:
  match value:
    case V.Text{"top-left"}: T.TopLeft{}
    case V.Text{"top-right"}: T.TopRight{}
    case V.Text{"bottom-left"}: T.BottomLeft{}
    case V.Text{"bottom-right"}: T.BottomRight{}
    case V.Text{"top-center"}: T.TopCenter{}
    case V.Text{"bottom-center"}: T.BottomCenter{}
    case V.Text{"left-center"}: T.LeftCenter{}
    case V.Text{"right-center"}: T.RightCenter{}
    case _: T.Center{}
def margin(+value: V.Value) -> T.OverlayMargin:
  match value:
    case V.Number{_}: T.OverlayMargin{natural(value),natural(value),natural(value),natural(value)}
    case _: T.OverlayMargin{natural(get(value,"top")),natural(get(value,"right")),natural(get(value,"bottom")),natural(get(value,"left"))}
def options(+value: V.Value) -> T.OverlayGeometry:
  T.OverlayGeometry{size(get(value,"width")),natural(get(value,"minWidth")),size(get(value,"maxHeight")),anchor(get(value,"anchor")),offset(get(value,"offsetX")),offset(get(value,"offsetY")),size(get(value,"row")),size(get(value,"col")),margin(get(value,"margin"))}
def count(value: Nat) -> V.Value: V.Number{T.dimension(value)}
def result(value: Result<&2,&2,T.LayoutError,T.OverlayLayout>) -> V.Value:
  match value:
    case Fail{T.InvalidPercentage{}}: V.Text{"invalid-percentage"}
    case Fail{T.UnrepresentablePosition{}}: V.Text{"unrepresentable-position"}
    case Done{T.OverlayLayout{width,row,col,maximum}}:
      V.ObjectValue{R.set(V.Value,R.set(V.Value,R.set(V.Value,R.set(V.Value,R.new(V.Value),"width",count(width)),"row",count(row)),"col",count(col)),"maxHeight",Maybe.default(&2,V.Value,Maybe.map(&2,Nat,V.Value,count,maximum),V.Null{}))}
def query(+value: V.Value) -> V.Value:
  result(T.resolveOverlayLayout(options(get(value,"options")),natural(get(value,"height")),natural(get(value,"columns")),natural(get(value,"rows"))))
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case item <> rest: queries(rest,query(item) <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(queries(items,Nil{}))),"null"))
    case _: IO.die(Unit,1,"Invalid overlay fixture input")
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
