import Base
import ../packages/tui/src/components/stack.bend as S
import ../packages/tui/src/components/v-stack.bend as V
import ../packages/tui/src/components/h-stack.bend as H
import ../packages/tui/src/layout.bend as L
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/utils.bend as U
import ../packages/runtime/src/callback.bend as Callback

def draw(lines: List<&2,String>,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,lines)
def ignore(context: Unit,value: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def hidden(context: Unit,viewport: S.LayoutViewport) -> IO(Bool): IO.pure(Bool,False{})
def component(identifier: Nat,callback: Callback.Callback<Nat,List<&2,String>>,invalidator: Callback.Callback<Unit,Unit>) -> C.Component:
  C.Component{C.ComponentId{identifier},callback,None{},None{},invalidator,None{},False{}}
def numbers(values: List<&2,Nat>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: Nat.show(value)
    case value <> rest: Nat.show(value) ++ "," ++ numbers(rest)
def pair(first: C.Component,firstSize: S.StackEntryOptions,second: C.Component,secondSize: S.StackEntryOptions,axis: S.Axis,gap: Nat) -> S.Stack:
  S.addChild(S.addChild(S.new(axis,gap,S.Stretch{}),S.entry(first,firstSize,None{})),S.entry(second,secondSize,None{}))
def heights(boxes: List<&2,L.LayoutBox>) -> String:
  match boxes:
    case Nil{}: ""
    case L.LayoutBox{_,L.LayoutRect{_,_,_,height},_,_,_,_,_} <> Nil{}: Nat.show(height)
    case L.LayoutBox{_,L.LayoutRect{_,_,_,height},_,_,_,_,_} <> rest: Nat.show(height) ++ "," ++ heights(rest)
def widths(boxes: List<&2,L.LayoutBox>) -> String:
  match boxes:
    case Nil{}: ""
    case L.LayoutBox{_,L.LayoutRect{_,_,width,_},_,_,_,_,_} <> Nil{}: Nat.show(width)
    case L.LayoutBox{_,L.LayoutRect{_,_,width,_},_,_,_,_,_} <> rest: Nat.show(width) ++ "," ++ widths(rest)
def clean(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: U.trimEnd(U.stripTerminalSequences(line))
    case line <> rest: U.trimEnd(U.stripTerminalSequences(line)) ++ "|" ++ clean(rest)
def report(label: String,frame: L.LayoutFrame) -> IO(Unit):
  match frame:
    case L.LayoutFrame{L.LayoutBox{_,_,_,+children,_,_,_},_,_,lines}:
      IO.print(label ++ ":" ++ heights(children) ++ ":" ++ widths(children) ++ ":[" ++ clean(lines) ++ "]")
def main() -> IO(Unit):
  do IO<Unit>:
    +invalidator : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +topDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"top" <> Nil{})
    +bodyDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"body" <> Nil{})
    +aDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"a1" <> "a2" <> "a3" <> Nil{})
    +bDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"b1" <> "b2" <> "b3" <> Nil{})
    +leftDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"left" <> Nil{})
    +rightDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"right" <> Nil{})
    +noDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"hidden" <> Nil{})
    +yesDraw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~List<&2,String>,~Nat,~List<&2,String>,~draw,"shown" <> Nil{})
    +predicate : Callback.Callback<S.LayoutViewport,Bool> <- Callback.create(~Unit,~S.LayoutViewport,~Bool,~hidden,Unit{})
    +top : C.Component <- IO.pure(C.Component,component(1n,topDraw,invalidator))
    +body : C.Component <- IO.pure(C.Component,component(2n,bodyDraw,invalidator))
    +a : C.Component <- IO.pure(C.Component,component(3n,aDraw,invalidator))
    +b : C.Component <- IO.pure(C.Component,component(4n,bDraw,invalidator))
    +left : C.Component <- IO.pure(C.Component,component(5n,leftDraw,invalidator))
    +right : C.Component <- IO.pure(C.Component,component(6n,rightDraw,invalidator))
    +no : C.Component <- IO.pure(C.Component,component(7n,noDraw,invalidator))
    +yes : C.Component <- IO.pure(C.Component,component(8n,yesDraw,invalidator))
    grow : L.LayoutFrame <- L.renderLayoutFrame(pair(top,S.sized(Some{1n},0n,0n,0n,10n),body,S.sized(Some{0n},1n,1n,0n,10n),S.Vertical{},0n),10n,4n)
    report("grow",grow)
    shrink : L.LayoutFrame <- L.renderLayoutFrame(pair(a,S.sized(None{},0n,1n,1n,10n),b,S.sized(None{},0n,0n,0n,10n),S.Vertical{},0n),10n,4n)
    report("shrink",shrink)
    +joined : L.LayoutFrame <- L.renderLayoutFrame(pair(left,S.sized(Some{6n},0n,0n,0n,10n),right,S.sized(Some{6n},0n,0n,0n,10n),S.Horizontal{},0n),12n,1n)
    report("horizontal",joined)
    IO.print("hits:" ++ Nat.show(List.length(&2,L.LayoutBox,L.getLayoutBoxesAt(joined,0n,0n))) ++ "," ++ Nat.show(List.length(&2,L.LayoutBox,L.getLayoutBoxesAt(joined,6n,0n))) ++ "," ++ Nat.show(List.length(&2,L.LayoutBox,L.getLayoutBoxesAt(joined,12n,0n))))
    zero : L.LayoutFrame <- L.renderLayoutFrame(pair(no,S.sized(Some{0n},0n,0n,0n,10n),yes,S.sized(Some{0n},1n,1n,0n,10n),S.Horizontal{},0n),5n,1n)
    report("zero",zero)
    +stack : S.Stack <- IO.pure(S.Stack,S.addChild(S.addChild(S.addChild(V.new(1n,S.Stretch{}),S.entry(top,S.defaultSize(),None{})),S.entry(no,S.defaultSize(),Some{predicate})),S.entry(body,S.defaultSize(),None{})))
    visible : L.LayoutFrame <- L.renderLayoutFrame(stack,10n,3n)
    report("visibility",visible)
    plain : List<&2,String> <- V.render(stack,10n)
    IO.print("standalone-v:[" ++ clean(plain) ++ "]")
    side : List<&2,String> <- H.render(pair(left,S.sized(Some{6n},0n,0n,0n,10n),right,S.sized(Some{6n},0n,0n,0n,10n),S.Horizontal{},0n),12n)
    IO.print("standalone-h:[" ++ clean(side) ++ "]")
    IO.print("grow-cap:[" ++ numbers(S.allocateStackSizes(S.sized(Some{1n},1n,1n,0n,2n) <> S.sized(Some{1n},1n,1n,0n,10n) <> Nil{},0n <> 0n <> Nil{},Some{6n},0n)) ++ "]")
    IO.print("weighted-shrink:[" ++ numbers(S.allocateStackSizes(S.sized(Some{6n},0n,1n,0n,10n) <> S.sized(Some{6n},0n,2n,0n,10n) <> Nil{},0n <> 0n <> Nil{},Some{8n},0n)) ++ "]")
    Callback.dispose(Nat,List<&2,String>,topDraw)
    Callback.dispose(Nat,List<&2,String>,bodyDraw)
    Callback.dispose(Nat,List<&2,String>,aDraw)
    Callback.dispose(Nat,List<&2,String>,bDraw)
    Callback.dispose(Nat,List<&2,String>,leftDraw)
    Callback.dispose(Nat,List<&2,String>,rightDraw)
    Callback.dispose(Nat,List<&2,String>,noDraw)
    Callback.dispose(Nat,List<&2,String>,yesDraw)
    Callback.dispose(S.LayoutViewport,Bool,predicate)
    Callback.dispose(Unit,Unit,invalidator)
