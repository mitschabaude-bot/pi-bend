import Base
import ../component.bend as C
import ../../../runtime/src/callback.bend as Callback

type LayoutViewport is Data: LayoutViewport{width: Nat,height: Nat}
type Align is Data: Stretch{} Start{} Center{} End{}
type Axis is Data: Vertical{} Horizontal{}
type StackEntryOptions is Data:
  StackEntryOptions{basis: Maybe<&2,Nat>,grow: Nat,shrink: Nat,minSize: Nat,maxSize: Nat}
type StackEntry is Data:
  StackEntry{component: C.Component,size: StackEntryOptions,visible: Maybe<&2,Callback.Callback<LayoutViewport,Bool>>}
type Stack is Data:
  Stack{entries: List<&2,StackEntry>,gap: Nat,align: Align,axis: Axis}
type Distribution is Data: Distribution{sizes: List<&2,Nat>,remaining: Nat,moved: Nat}

def defaultSize() -> StackEntryOptions: StackEntryOptions{None{},0n,1n,0n,4294967295n}
def sized(basis: Maybe<&2,Nat>,grow: Nat,shrink: Nat,+minSize: Nat,maxSize: Nat) -> StackEntryOptions:
  StackEntryOptions{basis,grow,shrink,minSize,Nat.max(minSize,maxSize)}
def entry(component: C.Component,size: StackEntryOptions,visible: Maybe<&2,Callback.Callback<LayoutViewport,Bool>>) -> StackEntry:
  StackEntry{component,size,visible}
def new(axis: Axis,gap: Nat,align: Align) -> Stack: Stack{Nil{},gap,align,axis}
def addChild(stack: Stack,child: StackEntry) -> Stack:
  match stack: case Stack{entries,gap,align,axis}: Stack{List.append(&2,StackEntry,entries,child <> Nil{}),gap,align,axis}
def removeFirst(entries: List<&2,StackEntry>,+identifier: C.ComponentId) -> List<&2,StackEntry>:
  match entries:
    case Nil{}: Nil{}
    case StackEntry{+component,size,visible} <> +rest:
      Bool.pick(Unit -> List<&2,StackEntry>,C.same(C.id(component),identifier),_ => rest,_ => StackEntry{component,size,visible} <> removeFirst(rest,identifier))(Unit{})
def removeChild(stack: Stack,identifier: C.ComponentId) -> Stack:
  match stack: case Stack{entries,gap,align,axis}: Stack{removeFirst(entries,identifier),gap,align,axis}
def clear(stack: Stack) -> Stack:
  match stack: case Stack{_,gap,align,axis}: Stack{Nil{},gap,align,axis}
def visibleStackEntries(entries: List<&2,StackEntry>,+viewport: LayoutViewport) -> IO(List<&2,StackEntry>):
  match entries:
    case Nil{}: IO.pure(List<&2,StackEntry>,Nil{})
    case item <> rest:
      match item:
        case StackEntry{_,_,None{}}:
          do IO<List<&2,StackEntry>>:
            +tail : List<&2,StackEntry> <- visibleStackEntries(rest,viewport)
            return item <> tail
        case StackEntry{component,size,Some{+predicate}}:
          do IO<List<&2,StackEntry>>:
            shown : Bool <- Callback.call(LayoutViewport,Bool,predicate,viewport)
            +tail : List<&2,StackEntry> <- visibleStackEntries(rest,viewport)
            return Bool.pick(Unit -> List<&2,StackEntry>,shown,_ => StackEntry{component,size,Some{predicate}} <> tail,_ => tail)(Unit{})
def sizeOptions(entries: List<&2,StackEntry>) -> List<&2,StackEntryOptions>:
  match entries:
    case Nil{}: Nil{}
    case StackEntry{_,size,_} <> rest: size <> sizeOptions(rest)
def clampSize(value: Nat,options: StackEntryOptions) -> Nat:
  match options: case StackEntryOptions{_,_,_,minimum,maximum}: Nat.max(minimum,Nat.min(maximum,value))
def chooseBase(basis: Maybe<&2,Nat>,intrinsic: Nat) -> Nat:
  match basis:
    case None{}: intrinsic
    case Some{value}: value
def bases(options: List<&2,StackEntryOptions>,intrinsic: List<&2,Nat>) -> List<&2,Nat>:
  match options:
    case Nil{}: Nil{}
    case StackEntryOptions{basis,grow,shrink,minimum,maximum} <> rest:
      match intrinsic:
        case Nil{}: clampSize(chooseBase(basis,0n),StackEntryOptions{None{},grow,shrink,minimum,maximum}) <> bases(rest,Nil{})
        case size <> next: clampSize(chooseBase(basis,size),StackEntryOptions{None{},grow,shrink,minimum,maximum}) <> bases(rest,next)
def total(sizes: List<&2,Nat>) -> Nat:
  match sizes:
    case Nil{}: 0n
    case size <> rest: size + total(rest)
def weight(+size: Nat,options: StackEntryOptions,growing: Bool) -> Nat:
  match options:
    case StackEntryOptions{_,grow,shrink,minimum,maximum}:
      Bool.pick(Nat,growing,Bool.pick(Nat,Nat.is_lt(size,maximum),grow,0n),Bool.pick(Nat,Nat.is_gt(size,minimum),shrink * Nat.max(1n,size),0n))
def weights(sizes: List<&2,Nat>,options: List<&2,StackEntryOptions>,+growing: Bool) -> Nat:
  match sizes options:
    case +size <> sizes option <> options: weight(size,option,growing) + weights(sizes,options,growing)
    case _ _: 0n
def apply(+size: Nat,option: StackEntryOptions,+growing: Bool,+remaining: Nat,+totalWeight: Nat) -> Nat:
  match option:
    case StackEntryOptions{_,grow,shrink,+minimum,+maximum}:
      +w = Bool.pick(Nat,growing,Bool.pick(Nat,Nat.is_lt(size,maximum),grow,0n),Bool.pick(Nat,Nat.is_gt(size,minimum),shrink * Nat.max(1n,size),0n))
      +capacity = Bool.pick(Nat,growing,maximum - size,size - minimum)
      +proposed = Bool.pick(Nat,Nat.is_eq(w,0n) || Nat.is_eq(totalWeight,0n),0n,Nat.max(1n,remaining * w / Nat.max(1n,totalWeight)))
      Nat.min(remaining,Nat.min(proposed,capacity))
def finishPass(updated: Nat,delta: Nat,result: Distribution) -> Distribution:
  match result: case Distribution{tail,left,moved}: Distribution{updated <> tail,left,moved + delta}
def distributePass(sizes: List<&2,Nat>,options: List<&2,StackEntryOptions>,+growing: Bool,+remaining: Nat,+totalWeight: Nat) -> Distribution:
  match sizes options:
    case +size <> sizes option <> options:
      +delta = apply(size,option,growing,remaining,totalWeight)
      +updated = Bool.pick(Nat,growing,size + delta,size - delta)
      finishPass(updated,delta,distributePass(sizes,options,growing,remaining - delta,totalWeight))
    case _ _: Distribution{Nil{},remaining,0n}
@unsafe def distributeLoop(+options: List<&2,StackEntryOptions>,+growing: Bool,state: Distribution) -> List<&2,Nat>:
  match state:
    case Distribution{+sizes,+remaining,moved}:
      +w = weights(sizes,options,growing)
      Bool.pick(Unit -> List<&2,Nat>,Nat.is_eq(remaining,0n) || Nat.is_eq(w,0n) || Nat.is_eq(moved,0n),_ => sizes,_ => distributeLoop(options,growing,distributePass(sizes,options,growing,remaining,w)))(Unit{})
def distribute(sizes: List<&2,Nat>,options: List<&2,StackEntryOptions>,growing: Bool,remaining: Nat) -> List<&2,Nat>:
  distributeLoop(options,growing,Distribution{sizes,remaining,1n})
def allocateFromBases(+sizes: List<&2,Nat>,+options: List<&2,StackEntryOptions>,available: Maybe<&2,Nat>,gap: Nat) -> List<&2,Nat>:
  match available:
    case None{}: sizes
    case Some{space}:
      +count = List.length(&2,StackEntryOptions,options)
      +content = space - (Nat.max(0n,count - 1n) * gap)
      +initial = total(sizes)
      Bool.pick(Unit -> List<&2,Nat>,Nat.is_lt(initial,content),_ => distribute(sizes,options,True{},content - initial),_ => distribute(sizes,options,False{},initial - content))(Unit{})
def allocateStackSizes(+options: List<&2,StackEntryOptions>,intrinsic: List<&2,Nat>,available: Maybe<&2,Nat>,gap: Nat) -> List<&2,Nat>:
  +sizes = bases(options,intrinsic)
  allocateFromBases(sizes,options,available,gap)
