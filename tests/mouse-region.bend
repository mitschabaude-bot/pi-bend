import Base
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/components/mouse-region.bend as Region
import ../packages/tui/src/tui.bend as T
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref

def render(lastWidth: Ref.Ref<Nat>,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    Ref.write(Nat,lastWidth,width)
    return "child" <> Nil{}
def tick(count: Nat) -> Nat & Unit: (count + 1n,Unit{})
def invalidate(count: Ref.Ref<Nat>,argument: Unit) -> IO(Unit):
  Ref.modify(Nat,Unit,count,tick)
def childMouse(handled: Bool,event: T.TuiMouseEvent) -> IO(Maybe<&2,C.MouseResponse>):
  IO.pure(Maybe<&2,C.MouseResponse>,Bool.pick(Maybe<&2,C.MouseResponse>,handled,Some{C.LocalResult{T.TuiMouseEventResult{True{},False{},False{},None{}}}},None{}))
def fallback(count: Ref.Ref<Nat>,event: T.TuiMouseEvent) -> IO(Maybe<&2,T.TuiMouseEventResult>):
  do IO<Maybe<&2,T.TuiMouseEventResult>>:
    Ref.modify(Nat,Unit,count,tick)
    return Some{T.TuiMouseEventResult{True{},True{},False{},None{}}}

def event() -> T.TuiMouseEvent:
  T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},T.Forward{0n},T.Forward{0n},T.Forward{0n},T.Forward{0n},10n,1n,False{},False{},False{},None{},None{}}
def checkLines(lines: List<&2,String>) -> Bool:
  match lines:
    case "child" <> Nil{}: True{}
    case _: False{}
def checkChild(result: Maybe<&2,C.MouseResponse>) -> Bool:
  match result:
    case Some{C.DispatchedResult{C.TuiMouseDispatchResult{C.TuiMouseDispatchTarget{C.ComponentId{id},_,_,_,_},_,False{},False{},_}}}: Nat.is_eq(id,1n)
    case _: False{}
def checkFallback(result: Maybe<&2,C.MouseResponse>) -> Bool:
  match result:
    case Some{C.LocalResult{T.TuiMouseEventResult{True{},True{},False{},_}}}: True{}
    case _: False{}
def report(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("mouse region: render, invalidate, child precedence and fallback passed")
    case False{}: IO.die(Unit,1,"mouse region failed")

def main() -> IO(Unit):
  do IO<Unit>:
    +count : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +lastWidth : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +invalidations : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +draw : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Ref.Ref<Nat>,~Nat,~List<&2,String>,~render,lastWidth)
    +clear : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Nat>,~Unit,~Unit,~invalidate,invalidations)
    +accept : Callback.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse>> <- Callback.create(~Bool,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse>,~childMouse,True{})
    +decline : Callback.Callback<T.TuiMouseEvent,Maybe<&2,C.MouseResponse>> <- Callback.create(~Bool,~T.TuiMouseEvent,~Maybe<&2,C.MouseResponse>,~childMouse,False{})
    +onMouse : Callback.Callback<T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>> <- Callback.create(~Ref.Ref<Nat>,~T.TuiMouseEvent,~Maybe<&2,T.TuiMouseEventResult>,~fallback,count)
    +active : Region.MouseRegion <- IO.pure(Region.MouseRegion,Region.new(C.Component{C.ComponentId{1n},draw,None{},Some{accept},clear,None{},False{}},onMouse))
    +idle : Region.MouseRegion <- IO.pure(Region.MouseRegion,Region.new(C.Component{C.ComponentId{2n},draw,None{},Some{decline},clear,None{},False{}},onMouse))
    lines : List<&2,String> <- Region.render(active,7n)
    width : Nat <- Ref.read(Nat,lastWidth)
    Region.invalidate(idle)
    cleared : Nat <- Ref.read(Nat,invalidations)
    child : Maybe<&2,C.MouseResponse> <- Region.handleMouse(active,event())
    before : Nat <- Ref.read(Nat,count)
    local : Maybe<&2,C.MouseResponse> <- Region.handleMouse(idle,event())
    after : Nat <- Ref.read(Nat,count)
    report(checkLines(lines) && Nat.is_eq(width,7n) && Nat.is_eq(cleared,1n) && checkChild(child) && Nat.is_eq(before,0n) && checkFallback(local) && Nat.is_eq(after,1n))
    Callback.dispose(Nat,List<&2,String>,draw)
    Callback.dispose(Unit,Unit,clear)
    Callback.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse>,accept)
    Callback.dispose(T.TuiMouseEvent,Maybe<&2,C.MouseResponse>,decline)
    Callback.dispose(T.TuiMouseEvent,Maybe<&2,T.TuiMouseEventResult>,onMouse)
    oldCount : Nat <- Ref.dispose(Nat,count)
    oldWidth : Nat <- Ref.dispose(Nat,lastWidth)
    oldInvalidations : Nat <- Ref.dispose(Nat,invalidations)
    return Unit{}
