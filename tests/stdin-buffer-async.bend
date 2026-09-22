import Base
import ../packages/runtime/src/utf8.bend as UTF8
import ../packages/tui/src/stdin-buffer.bend as B
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/schema-value.bend as V

type Context is Data: Context{handle: Ref.Ref<Maybe<&2,B.AsyncHandle>>, mode: String}
def closed(pair: Timer & Bool) -> IO(Unit):
  match pair:
    case (owner,_): Timer.close(owner)
def sleeping(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (owner,_):
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(owner)
        closed(result)
def sleep(delay: U32) -> IO(Unit):
  do IO<Unit>:
    timer : Timer & TimerCancel <- Timer.new(delay)
    sleeping(timer)
def emit(kind: String,text: String) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- IO.now()
    IO.print("[" ++ J.quote(kind) ++ "," ++ J.quote(text) ++ "," ++ Nat.show(now) ++ "]")
def writeEvent(value: B.InputEvent) -> IO(Unit):
  match value:
    case B.DataEvent{text}: emit("data",text)
    case B.PasteEvent{text}: emit("paste",text)
def reenter(handle: Maybe<&2,B.AsyncHandle>) -> IO(Unit):
  match handle:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        accepted : Bool <- B.processAsync(handle,"r")
        return Unit{}
def isX(value: B.InputEvent) -> Bool:
  match value:
    case B.DataEvent{"x"}: True{}
    case _: False{}
def observed(context: Context,+value: B.InputEvent) -> IO(Unit):
  match context:
    case Context{reference,+mode}:
      do IO<Unit>:
        writeEvent(value)
        handle : Maybe<&2,B.AsyncHandle> <- Ref.read(Maybe<&2,B.AsyncHandle>,reference)
        Bool.pick(Unit -> IO(Unit),String.eq(mode,"reenter") && isX(value),_ => reenter(handle),_ => IO.pure(Unit,Unit{}))(Unit{})
        Bool.pick(Unit -> IO(Unit),String.eq(mode,"slow"),_ => sleep(80),_ => IO.pure(Unit,Unit{}))(Unit{})
        return Unit{}
def flushed(events: List<&2,B.InputEvent>) -> IO(Unit):
  match events:
    case Nil{}: IO.pure(Unit,Unit{})
    case B.DataEvent{text} <> rest:
      do IO<Unit>:
        emit("flush",text)
        flushed(rest)
    case _ <> rest: flushed(rest)
def byteError(error: UTF8.Error) -> String:
  match error:
    case UTF8.InvalidByte{offset,value}: "byte:" ++ Nat.show(offset) ++ ":" ++ U32.show(value)
    case UTF8.InvalidSequence{offset,value}: "invalid:" ++ Nat.show(offset) ++ ":" ++ U32.show(value)
    case UTF8.IncompleteSequence{offset}: "incomplete:" ++ Nat.show(offset)
def byteStatus(result: Result<&2,&2,UTF8.Error,Bool>) -> IO(Unit):
  match result:
    case Fail{error}: emit("error",byteError(error))
    case Done{False{}}: emit("rejected","bytes")
    case Done{True{}}: IO.pure(Unit,Unit{})
def numbers(values: List<&2,V.Value>, reversed: List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: List.reverse(&2,U32,reversed)
    case V.Number{value} <> rest: numbers(rest,F64.to_u32(value) <> reversed)
    case _ <> rest: numbers(rest,reversed)
def operation(+handle: B.AsyncHandle, command: V.Value) -> IO(Unit):
  match command:
    case V.ArrayValue{V.Text{"process"} <> V.Text{text} <> Nil{}}:
      do IO<Unit>:
        accepted : Bool <- B.processAsync(handle,text)
        Bool.pick(Unit -> IO(Unit),accepted,_ => IO.pure(Unit,Unit{}),_ => emit("rejected","text"))(Unit{})
    case V.ArrayValue{V.Text{"sleep"} <> V.Number{milliseconds} <> Nil{}}: sleep(F64.to_u32(milliseconds))
    case V.ArrayValue{V.Text{"bytes"} <> V.ArrayValue{values} <> Nil{}}:
      do IO<Unit>:
        result : Result<&2,&2,UTF8.Error,Bool> <- B.processBytesAsync(handle,numbers(values,Nil{}))
        byteStatus(result)
    case V.Text{"eof"}:
      do IO<Unit>:
        result : Result<&2,&2,UTF8.Error,Bool> <- B.finishBytesAsync(handle)
        byteStatus(result)
    case V.Text{"clear"}: B.clearAsync(handle)
    case V.Text{"flush"}:
      do IO<Unit>:
        events : List<&2,B.InputEvent> <- B.flushAsync(handle)
        flushed(events)
    case V.Text{"get"}:
      do IO<Unit>:
        buffer : String <- B.getBufferAsync(handle)
        emit("buffer",buffer)
    case _: IO.die(Unit,1,"invalid operation")
def operations(+handle: B.AsyncHandle, commands: List<&2,V.Value>) -> IO(Unit):
  match commands:
    case Nil{}: IO.pure(Unit,Unit{})
    case command <> rest:
      do IO<Unit>:
        operation(handle,command)
        operations(handle,rest)
def running(observer: Callback.Callback<B.InputEvent,Unit>, +reference: Ref.Ref<Maybe<&2,B.AsyncHandle>>, commands: List<&2,V.Value>, pair: B.AsyncOwner & B.AsyncHandle) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        Ref.write(Maybe<&2,B.AsyncHandle>,reference,Some{handle})
        emit("start","")
        operations(handle,commands)
        B.disposeAsync(owner)
        emit("disposed","")
        sleep(100)
        Callback.dispose(B.InputEvent,Unit,observer)
        retired : Maybe<&2,B.AsyncHandle> <- Ref.dispose(Maybe<&2,B.AsyncHandle>,reference)
        emit("done","")
def scenario(parsed: Result<&2,&2,J.ParseError,V.Value>) -> IO(Unit):
  match parsed:
    case Done{V.ArrayValue{V.Number{timeout} <> V.Number{escape} <> V.Text{mode} <> V.ArrayValue{commands} <> Nil{}}}:
      do IO<Unit>:
        +reference : Ref.Ref<Maybe<&2,B.AsyncHandle>> <- Ref.new(Maybe<&2,B.AsyncHandle>,None{})
        +observer : Callback.Callback<B.InputEvent,Unit> <- Callback.create(~Context,~B.InputEvent,~Unit,~(context => value => observed(context,value)),Context{reference,mode})
        owner : B.AsyncOwner <- B.createAsync(B.StdinBufferOptions{F64.to_u32(timeout),F64.to_u32(escape)},observer)
        running(observer,reference,commands,B.borrowAsync(owner))
    case _: IO.die(Unit,1,"invalid scenario")
def mainArgs(args: List<String>) -> IO(Unit):
  match args:
    case argument <> Nil{}: scenario(J.parse(argument))
    case _: IO.die(Unit,1,"scenario required")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    mainArgs(args)
