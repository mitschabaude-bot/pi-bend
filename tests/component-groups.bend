import Base
import ../packages/tui/src/tui.bend as T
import ../packages/tui/src/component.bend as C
import ../packages/tui/src/tui-base.bend as B
import ../packages/tui/src/overlays.bend as O
import ../packages/runtime/src/callback.bend as K
import ../packages/runtime/src/ref.bend as Ref

type Tree is Data: Tree{children: Ref.Ref<List<&2,C.Component>>,reads: Ref.Ref<Nat>}
def check(value: Bool,message: String) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)
def children(tree: Tree,_: Unit) -> IO(List<&2,C.Component>):
  match tree:
    case Tree{children,reads}:
      do IO<List<&2,C.Component>>:
        Ref.modify(Nat,Unit,reads,count => (count + 1n,Unit{}))
        Ref.read(List<&2,C.Component>,children)
def render(_: Unit,width: Nat) -> IO(List<&2,String>): IO.pure(List<&2,String>,"control" <> Nil{})
def invalidate(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def input(journal: Ref.Ref<String>,data: String) -> IO(Unit):
  Ref.modify(String,Unit,journal,old => (old ++ data,Unit{}))
def focused(journal: Ref.Ref<String>,value: Bool) -> IO(Unit):
  Ref.modify(String,Unit,journal,old => (old ++ Bool.pick(String,value,"+","-"),Unit{}))
def leaf(+id: Nat,+journal: Ref.Ref<String>) -> IO(C.Component):
  do IO<C.Component>:
    render : K.Callback<Nat,List<&2,String>> <- K.create(~Unit,~Nat,~List<&2,String>,~render,Unit{})
    invalidate : K.Callback<Unit,Unit> <- K.create(~Unit,~Unit,~Unit,~invalidate,Unit{})
    input : K.Callback<String,Unit> <- K.create(~Ref.Ref<String>,~String,~Unit,~input,journal)
    focused : K.Callback<Bool,Unit> <- K.create(~Ref.Ref<String>,~Bool,~Unit,~focused,journal)
    return C.Component{C.ComponentId{id},render,Some{input},None{},invalidate,Some{focused},False{}}
def dispose(component: C.Component) -> IO(Unit):
  match component:
    case C.Component{_,r,Some{i},_,v,Some{f},_}:
      do IO<Unit>:
        K.dispose(Nat,List<&2,String>,r)
        K.dispose(String,Unit,i)
        K.dispose(Unit,Unit,v)
        K.dispose(Bool,Unit,f)
    case _: IO.die(Unit,1,"unexpected fixture component")
def found(value: Maybe<&2,C.Component>,wanted: Nat) -> Bool:
  match value:
    case Some{component}: C.same(C.id(component),C.ComponentId{wanted})
    case None{}: False{}
def focusedState(result: B.ResultOf(B.TuiBase)) -> IO(B.TuiBase):
  match result:
    case Done{base}: IO.pure(B.TuiBase,base)
    case Fail{_}: IO.die(B.TuiBase,1,"nested focus was rejected")
def delivered(result: B.ResultOf(B.InputResult)) -> IO(Unit):
  match result:
    case Done{B.InputResult{_,handled,immediate}}: check(handled && immediate,"nested input was not delivered")
    case Fail{_}: IO.die(Unit,1,"nested input failed")
def retireShared(component: C.Component,journal: Ref.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    dispose(component)
    Ref.modify(String,Unit,journal,old => (old ++ "closed",Unit{}))
def sharedLifetime(owner: C.Owner,+component: C.Component,+journal: Ref.Ref<String>) -> IO(Unit):
  do IO<Unit>:
    +event : T.TuiMouseEvent = T.TuiMouseEvent{T.MousePress{},T.MouseLeft{},T.Forward{0n},T.Forward{0n},T.Forward{0n},T.Forward{0n},80n,1n,False{},False{},False{},None{},None{}}
    +borrowed : C.TuiMouseDispatchTarget() = C.target(component,event)
    +first : C.TuiMouseDispatchTarget() <- C.retainTarget(borrowed)
    +second : C.TuiMouseDispatchTarget() <- C.retainTarget(borrowed)
    C.dispose(owner)
    alive : String <- Ref.read(String,journal)
    check(String.eq(alive,""),"primary retirement ignored captured holders")
    C.handleInput(component,"a")
    C.releaseTarget(first,None{})
    one : String <- Ref.read(String,journal)
    check(String.eq(one,"a"),"first capture retired the remaining holder")
    C.handleInput(component,"b")
    C.releaseTarget(second,None{})
    final : String <- Ref.read(String,journal)
    check(String.eq(final,"abclosed"),"last capture failed to retire callbacks exactly once")
def sharedBorrow(pair: C.Owner & C.Component,journal: Ref.Ref<String>) -> IO(Unit):
  match pair:
    case (owner,component): sharedLifetime(owner,component,journal)
def sharedCase() -> IO(Unit):
  do IO<Unit>:
    +journal : Ref.Ref<String> <- Ref.new(String,"")
    +component : C.Component <- leaf(10n,journal)
    owner : C.Owner <- C.shared(C.Owner{component,_ => retireShared(component,journal)})
    sharedBorrow(C.borrow(owner),journal)
    old : String <- Ref.dispose(String,journal)
    return Unit{}
def run() -> IO(Unit):
  do IO<Unit>:
    +journal : Ref.Ref<String> <- Ref.new(String,"")
    +reads : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +root : C.Component <- leaf(1n,journal)
    +middle : C.Component <- leaf(2n,journal)
    +child : C.Component <- leaf(3n,journal)
    +direct : C.Component <- leaf(4n,journal)
    +inner : Ref.Ref<List<&2,C.Component>> <- Ref.new(List<&2,C.Component>,child <> Nil{})
    +innerCallback : K.Callback<Unit,List<&2,C.Component>> <- K.create(~Tree,~Unit,~List<&2,C.Component>,~children,Tree{inner,reads})
    +outer : Ref.Ref<List<&2,C.Component>> <- Ref.new(List<&2,C.Component>,C.Group{middle,innerCallback} <> Nil{})
    +outerCallback : K.Callback<Unit,List<&2,C.Component>> <- K.create(~Tree,~Unit,~List<&2,C.Component>,~children,Tree{outer,reads})
    +roots : List<&2,C.Component> = C.Group{root,outerCallback} <> direct <> Nil{}
    directResult : Maybe<&2,C.Component> <- C.lookup(roots,C.ComponentId{4n})
    check(found(directResult,4n),"direct root was not found")
    readCount : Nat <- Ref.read(Nat,reads)
    check(Nat.is_eq(readCount,0n),"direct-root input needlessly traversed descendants")
    nested : Maybe<&2,C.Component> <- C.lookup(roots,C.ComponentId{3n})
    check(found(nested,3n),"deep descendant was not found")
    +base : B.TuiBase = B.newTui()
    transition : B.ResultOf(B.TuiBase) <- B.setFocus(base,roots,C.ComponentId{1n} <> C.ComponentId{4n} <> Nil{},Some{C.ComponentId{3n}})
    +focused : B.TuiBase <- focusedState(transition)
    result : B.ResultOf(B.InputResult) <- B.dispatchInput(focused,roots,C.ComponentId{1n} <> C.ComponentId{4n} <> Nil{},"typed")
    delivered(result)
    entries : String <- Ref.read(String,journal)
    check(String.eq(entries,"+typed"),"nested focus/input event ordering differs")
    Ref.write(List<&2,C.Component>,inner,Nil{})
    removed : Maybe<&2,C.Component> <- C.lookup(roots,C.ComponentId{3n})
    check(Maybe.is_none(&2,C.Component,removed),"removed descendant remains discoverable")
    missing : Maybe<&2,C.Component> <- C.lookup(roots,C.ComponentId{99n})
    check(Maybe.is_none(&2,C.Component,missing),"missing component was reported mounted")
    K.dispose(Unit,List<&2,C.Component>,outerCallback)
    K.dispose(Unit,List<&2,C.Component>,innerCallback)
    oldOuter : List<&2,C.Component> <- Ref.dispose(List<&2,C.Component>,outer)
    oldInner : List<&2,C.Component> <- Ref.dispose(List<&2,C.Component>,inner)
    dispose(root)
    dispose(middle)
    dispose(child)
    dispose(direct)
    oldJournal : String <- Ref.dispose(String,journal)
    oldReads : Nat <- Ref.dispose(Nat,reads)
    sharedCase()
    IO.print("nested component discovery, focus/input and shared lifetime pass")
def main() -> IO(Unit): run()
