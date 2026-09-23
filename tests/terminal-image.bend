import Base
import ../packages/tui/src/terminal-image.bend as I
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
def number(value: V.Value) -> F64:
  match value:
    case V.Number{value}: value
    case _: U32.to_f64(0)
def n(value: V.Value) -> Nat: U32.to_nat(F64.to_u32(number(value)))
def b(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: False{}
def flag(value: V.Value) -> Bool:
  match value:
    case V.Boolean{value}: value
    case _: True{}
def optionalNumber(value: V.Value) -> Maybe<&2,F64>:
  match value:
    case V.Number{value}: Some{value}
    case _: None{}
def optionalNat(value: V.Value) -> Maybe<&2,Nat>: Maybe.map(&2,F64,Nat,v => U32.to_nat(F64.to_u32(v)),optionalNumber(value))
def optionalId(value: V.Value) -> Maybe<&2,U32>: Maybe.map(&2,F64,U32,F64.to_u32,optionalNumber(value))
def optionalText(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{value}: Some{value}
    case _: None{}
def optionalBool(value: V.Value) -> Maybe<&2,Bool>:
  match value:
    case V.Boolean{value}: Some{value}
    case _: None{}
def dimension(value: V.Value) -> Maybe<&2,I.ImageDimension>:
  match value:
    case V.Null{}: None{}
    case V.Text{_}: Some{I.Auto{}}
    case V.Number{value}: Some{I.Cells{U32.to_nat(F64.to_u32(value))}}
    case +value: Some{Bool.pick(I.ImageDimension,String.eq(text(get(value,"unit")),"pixels"),I.Pixels{n(get(value,"value"))},I.Percent{number(get(value,"value"))})}
def protocol(value: String) -> I.ImageProtocol:
  match value:
    case "kitty": I.Kitty{}
    case "iterm2": I.ITerm2{}
    case _: I.NoImages{}
def overrides(+v: V.Value) -> I.CapabilityOverrides:
  I.CapabilityOverrides{Maybe.map(&2,String,I.ImageProtocol,protocol,optionalText(get(v,"images"))),optionalBool(get(v,"trueColor")),optionalBool(get(v,"hyperlinks"))}
def variables(items: List<&2,R.Property<V.Value>>,record: R.Record<String>) -> R.Record<String>:
  match items:
    case Nil{}: record
    case R.Property{key,V.Text{value}} <> rest: variables(rest,R.set(String,record,key,value))
    case _ <> rest: variables(rest,record)
def envFields(v: V.Value) -> R.Record<String>:
  match v:
    case V.ObjectValue{R.Record{fields}}: variables(fields,R.new(String))
    case _: R.new(String)
def environment(+v: V.Value) -> I.Environment: I.Environment{envFields(get(v,"env")),text(get(v,"platform")),text(get(v,"home"))}
def dims(+v: V.Value) -> I.ImageDimensions: I.ImageDimensions{F64.to_u32(number(get(v,"widthPx"))),F64.to_u32(number(get(v,"heightPx")))}
def cells(v: V.Value) -> I.CellDimensions:
  match v:
    case V.Null{}: I.defaultCellDimensions()
    case +v: I.CellDimensions{number(get(v,"widthPx")),number(get(v,"heightPx"))}
def obj(fields: List<&2,R.Property<V.Value>>) -> V.Value: V.ObjectValue{R.Record{fields}}
def c(n: Nat) -> V.Value: V.Number{U32.to_f64(U32.from_nat(n))}
def protocolValue(p: I.ImageProtocol) -> V.Value:
  match p:
    case I.Kitty{}: V.Text{"kitty"}
    case I.ITerm2{}: V.Text{"iterm2"}
    case I.NoImages{}: V.Null{}
def caps(value: I.TerminalCapabilities) -> V.Value:
  match value:
    case I.TerminalCapabilities{p,color,links}: obj([R.Property{"images",protocolValue(p)},R.Property{"trueColor",V.Boolean{color}},R.Property{"hyperlinks",V.Boolean{links}}])
def sizeResult(value: Result<&2,&2,I.Error,I.ImageCellSize>) -> V.Value:
  match value:
    case Fail{_}: V.Null{}
    case Done{I.ImageCellSize{columns,rows}}: obj([R.Property{"columns",c(columns)},R.Property{"rows",c(rows)}])
def textResult(value: Result<&2,&2,I.Error,String>) -> V.Value:
  match value:
    case Fail{_}: V.Null{}
    case Done{text}: V.Text{text}
def dimsResult(value: Result<&2,&2,I.Error,I.ImageDimensions>) -> V.Value:
  match value:
    case Fail{_}: V.Null{}
    case Done{I.ImageDimensions{w,h}}: obj([R.Property{"widthPx",c(U32.to_nat(w))},R.Property{"heightPx",c(U32.to_nat(h))}])
def options(+v: V.Value) -> I.ImageRenderOptions: I.ImageRenderOptions{optionalNumber(get(v,"maxWidthCells")),optionalNumber(get(v,"maxHeightCells")),flag(get(v,"preserveAspectRatio")),optionalId(get(v,"imageId")),flag(get(v,"moveCursor"))}
def kitty(+v: V.Value) -> I.KittyOptions: I.KittyOptions{optionalNat(get(v,"columns")),optionalNat(get(v,"rows")),optionalId(get(v,"imageId")),flag(get(v,"moveCursor"))}
def iterm(+v: V.Value) -> I.ITerm2Options: I.ITerm2Options{dimension(get(v,"width")),dimension(get(v,"height")),optionalText(get(v,"name")),flag(get(v,"preserveAspectRatio")),flag(get(v,"inline"))}
def rendered(value: Result<&2,&2,I.Error,I.Rendered>) -> V.Value:
  match value:
    case Done{I.Rendered{_,Some{I.RenderResult{sequence,columns,rows,id}}}}: obj([R.Property{"sequence",V.Text{sequence}},R.Property{"columns",c(columns)},R.Property{"rows",c(rows)},R.Property{"imageId",Maybe.default(&2,V.Value,Maybe.map(&2,U32,V.Value,id => c(U32.to_nat(id)),id),V.Null{})}])
    case _: V.Null{}
def placement(value: Maybe<&2,I.KittyImagePlacement>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{I.KittyImagePlacement{id,generation,bytes,decoded,sequence,replacement}}: obj([R.Property{"imageId",c(U32.to_nat(id))},R.Property{"transmissionGeneration",c(generation)},R.Property{"transmissionBytes",c(bytes)},R.Property{"estimatedDecodedBytes",c(decoded)},R.Property{"sequence",V.Text{sequence}},R.Property{"replacementLine",V.Text{replacement}}])
def stateResult(value: Result<&2,&2,I.Error,I.State>) -> I.State:
  match value:
    case Done{state}: state
    case Fail{_}: I.create()
def prepared(+v: V.Value) -> I.State:
  I.setCapabilityOverrides(stateResult(I.setCellDimensions(I.create(),cells(get(v,"cells")))),overrides(get(v,"overrides")))
def withMetadata(+v: V.Value) -> I.State:
  stateResult(I.registerKittyImageMetadata(prepared(v),I.KittyImageMetadata{F64.to_u32(number(get(v,"imageId"))),n(get(v,"columns")),n(get(v,"rows")),F64.to_u32(number(get(v,"widthPx"))),F64.to_u32(number(get(v,"heightPx")))}))
def capabilityResult(pair: I.State & I.TerminalCapabilities) -> V.Value:
  match pair:
    case (_,capabilities): caps(capabilities)
def optionalDims(v: V.Value) -> Maybe<&2,I.ImageDimensions>:
  match v:
    case V.Null{}: None{}
    case v: Some{dims(v)}
def repeated(times: Nat,+part: String,reversed: String) -> String:
  match times:
    case 0n: I.reverseInto(reversed,"")
    case 1n+rest: repeated(rest,part,I.reverseInto(part,reversed))
def inputText(+v: V.Value) -> String:
  text(get(v,"text")) ++ repeated(n(get(v,"repeat")),text(get(v,"repeated")),"") ++ text(get(v,"suffix"))
def metadata(value: Maybe<&2,I.KittyImageMetadata>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{I.KittyImageMetadata{id,columns,rows,width,height}}: obj([R.Property{"imageId",c(U32.to_nat(id))},R.Property{"columns",c(columns)},R.Property{"rows",c(rows)},R.Property{"widthPx",c(U32.to_nat(width))},R.Property{"heightPx",c(U32.to_nat(height))}])
def query(method: String,+v: V.Value) -> V.Value:
  match method:
    case "isImageLine": V.Boolean{I.isImageLine(inputText(v))}
    case "encodeKitty": textResult(I.encodeKitty(text(get(v,"data")),kitty(get(v,"options"))))
    case "encodeITerm2": textResult(I.encodeITerm2(text(get(v,"data")),iterm(get(v,"options"))))
    case "dimensions": dimsResult(I.getImageDimensions(text(get(v,"data")),text(get(v,"mime"))))
    case "size": sizeResult(I.calculateImageCellSize(dims(get(v,"dimensions")),number(get(v,"width")),optionalNumber(get(v,"height")),cells(get(v,"cells"))))
    case "caps": capabilityResult(I.getCapabilities(prepared(v),environment(v),b(get(v,"probe"))))
    case "render": rendered(I.renderImage(prepared(v),environment(v),b(get(v,"probe")),text(get(v,"data")),dims(get(v,"dimensions")),options(get(v,"options"))))
    case "metadata": metadata(I.getKittyImageMetadata(withMetadata(v),text(get(v,"text"))))
    case "crop": textResult(I.cropKittyImageLine(withMetadata(v),text(get(v,"text")),n(get(v,"hidden")),n(get(v,"visible"))))
    case "placement": placement(I.getKittyImagePlacement(withMetadata(v),text(get(v,"text"))))
    case "hyperlink": textResult(I.hyperlink(text(get(v,"text")),text(get(v,"url"))))
    case "fallback": textResult(I.imageFallback(text(get(v,"mime")),optionalDims(get(v,"dimensions")),optionalText(get(v,"filename")),text(get(v,"home")),I.applyOverrides(I.detectCapabilities(environment(v),b(get(v,"probe"))),overrides(get(v,"overrides")))))
    case "delete": textResult(I.deleteKittyImage(F64.to_u32(number(get(v,"imageId")))))
    case "deleteAll": V.Text{I.deleteAllKittyImages()}
    case "deletePlacements": V.Text{I.deleteAllKittyPlacements()}
    case _: V.Null{}
def queries(items: List<&2,V.Value>,reversed: List<&2,V.Value>) -> V.Value:
  match items:
    case Nil{}: V.ArrayValue{List.reverse(&2,V.Value,reversed)}
    case +v <> rest: queries(rest,query(text(get(v,"method")),v) <> reversed)
def program(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{items}}: IO.print(Maybe.default(&2,String,Render.stringify(SchemaJson.toJson(queries(items,Nil{}))),"null"))
    case _: IO.die(Unit,1,"Invalid terminal image fixture input")
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
