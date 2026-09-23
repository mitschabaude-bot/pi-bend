import Base
import ../packages/tui/src/word-navigation.bend as W
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

type Context is Data: Context{parts: List<&2,W.Segment>,atomic: String}
def segment(context: Context,input: String) -> List<&2,W.Segment>:
  match context:
    case Context{parts,_}: parts
def atomic(context: Context,value: String) -> Bool:
  match context:
    case Context{_,marker}: String.eq(marker,value)
def parts(values: List<&2,V.Value>) -> List<&2,W.Segment>:
  match values:
    case Nil{}: Nil{}
    case V.ArrayValue{V.Text{text} <> V.Boolean{word} <> Nil{}} <> rest: W.Segment{text,word} <> parts(rest)
    case _: W.Segment{"",False{}} <> Nil{}
def show(result: W.ResultOf(Nat)) -> String:
  match result:
    case Done{value}: Nat.show(value)
    case Fail{W.InvalidCursor{}}: "InvalidCursor"
    case Fail{W.InvalidSegments{}}: "InvalidSegments"
def row(value: V.Value) -> String:
  match value:
    case V.ArrayValue{V.Text{text} <> V.Text{cursor} <> V.Boolean{backward} <> V.ArrayValue{values} <> V.Text{marker} <> Nil{}}:
      +context = {Context{parts(values),marker}: Context}
      +text = {text: String}
      +cursor = Maybe.default(&2,Nat,Nat.read(cursor),0n)
      show(Bool.pick(Unit -> W.ResultOf(Nat),backward,
        _ => W.findWordBackward(~Context,~segment,~atomic,context,text,cursor),
        _ => W.findWordForward(~Context,~segment,~atomic,context,text,cursor))(Unit{}))
    case _: "InvalidFixture"
def rows(values: List<&2,V.Value>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(row(value))
        rows(rest)
def parsed(value: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ArrayValue{values}}: rows(values)
    case _: IO.die(Unit,1,"expected JSON array")
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case input <> Nil{}: parsed(J.parse(input))
    case _: IO.die(Unit,1,"expected JSON array")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
