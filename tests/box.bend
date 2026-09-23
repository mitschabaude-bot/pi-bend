import Base
import ../packages/tui/src/components/box.bend as Box
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

type Child is Data: Child{text: Ref.Ref<String>,mouse: Ref.Ref<String>,invalidations: Ref.Ref<Nat>}
def draw(child: Child,width: Nat) -> IO(List<&2,String>):
  match child:
    case Child{text,_,_}:
      do IO<List<&2,String>>:
        value : String <- Ref.read(String,text)
        return value <> Nil{}
def ignore(child: Child,unused: Unit) -> IO(Unit):
  match child:
    case Child{_,_,invalidations}: Ref.modify(Nat,Unit,invalidations,current => (Succ{current},Unit{}))
def signed(value: T.Offset) -> String:
  match value:
    case T.Forward{n}: Nat.show(n)
    case T.Backward{n}: "-" ++ Nat.show(n)
def onMouse(child: Child,event: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse>):
  match child event:
    case Child{_,mouse,_} T.TuiMouseEvent{_,_,x,y,_,_,width,height,_,_,_,_,_}:
      do IO<Maybe<&2,C.MouseResponse>>:
        Ref.write(String,mouse,signed(x) ++ "," ++ signed(y) ++ "," ++ Nat.show(width) ++ "," ++ Nat.show(height))
        return Some{C.LocalResult{T.TuiMouseEventResult{True{},False{},True{},None{}}}}
def painted(text: Unit,value: String) -> IO(String): IO.pure(String,"<" ++ value ++ ">")
def boxOf(pair: Box.Box & List<&2,String>) -> Box.Box:
  match pair: case (state,_): state
def linesOf(pair: Box.Box & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def show(lines: List<&2,String>) -> String: "[" ++ String.join(lines,"|") ++ "]"
def report(pair: Box.Box & List<&2,String>) -> IO(Box.Box):
  match pair:
    case (state,lines):
      do IO<Box.Box>:
        IO.print(show(lines))
        return state
def mouseEvent(+x: Nat,+y: Nat) -> T.TuiMouseEvent:
  T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},T.Forward{x},T.Forward{y},T.Forward{10n + x},T.Forward{20n + y},6n,3n,False{},False{},False{},None{},None{}}
def main() -> IO(Unit):
  do IO<Unit>:
    +text : Ref.Ref<String> <- Ref.new(String,"abc")
    +mouse : Ref.Ref<String> <- Ref.new(String,"")
    +invalidations : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +drawCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Child,~Nat,~List<&2,String>,~draw,Child{text,mouse,invalidations})
    +mouseCallback : Callback.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse>> <- Callback.create(~Child,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse>,~onMouse,Child{text,mouse,invalidations})
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Child,~Unit,~Unit,~ignore,Child{text,mouse,invalidations})
    +background : Callback.Callback<String,String> <- Callback.create(~Unit,~String,~String,~painted,Unit{})
    component : C.Component <- IO.pure(C.Component,C.Component{C.ComponentId{1n},drawCallback,None{},Some{mouseCallback},invalidator,None{},False{}})
    empty : Box.Box & List<&2,String> <- Box.render(Box.new(Some{1n},Some{1n},None{}),6n)
    IO.print(show(linesOf(empty)))
    firstPair : Box.Box & List<&2,String> <- Box.render(Box.addChild(Box.new(Some{1n},Some{1n},None{}),component),6n)
    first : Box.Box <- report(firstPair)
    Ref.write(String,text,"xyz")
    changedPair : Box.Box & List<&2,String> <- Box.render(first,6n)
    +changed : Box.Box <- report(changedPair)
    hit : Maybe<&2,C.TuiMouseDispatchResult> <- Box.handleMouse(changed,mouseEvent(2n,1n))
    seen : String <- Ref.read(String,mouse)
    IO.print(seen)
    missed : Maybe<&2,C.TuiMouseDispatchResult> <- Box.handleMouse(changed,mouseEvent(0n,1n))
    afterMiss : String <- Ref.read(String,mouse)
    IO.print(afterMiss)
    invalidated : Box.Box <- Box.invalidate(changed)
    count : Nat <- Ref.read(Nat,invalidations)
    IO.print(Nat.show(count))
    colored : Box.Box & List<&2,String> <- Box.render(Box.setBgFn(invalidated,Some{background}),6n)
    IO.print(show(linesOf(colored)))
    Callback.dispose(Nat,List<&2,String>,drawCallback)
    Callback.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse>,mouseCallback)
    Callback.dispose(Unit,Unit,invalidator)
    Callback.dispose(String,String,background)
    oldText : String <- Ref.dispose(String,text)
    oldMouse : String <- Ref.dispose(String,mouse)
    oldCount : Nat <- Ref.dispose(Nat,invalidations)
    return Unit{}
