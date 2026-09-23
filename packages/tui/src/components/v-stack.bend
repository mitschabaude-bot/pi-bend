import Base
import ./stack.bend as S
import ../component.bend as C

def new(gap: Nat,align: S.Align) -> S.Stack: S.new(S.Vertical{},gap,align)
def rendered(entries: List<&2,S.StackEntry>,+width: Nat,reversed: List<&2,List<&2,String>>) -> IO(List<&2,List<&2,String>>):
  match entries:
    case Nil{}: IO.pure(List<&2,List<&2,String>>,List.reverse(&2,List<&2,String>,reversed))
    case S.StackEntry{component,_,_} <> rest:
      do IO<List<&2,List<&2,String>>>:
        lines : List<&2,String> <- C.render(component,width)
        rendered(rest,width,lines <> reversed)
def lengths(groups: List<&2,List<&2,String>>) -> List<&2,Nat>:
  match groups:
    case Nil{}: Nil{}
    case lines <> rest: List.length(&2,String,lines) <> lengths(rest)
def blank(count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}: blank(rest,"" <> reversed)
def pad(lines: List<&2,String>,+size: Nat) -> List<&2,String>:
  +used = List.take(&2,String,lines,size)
  List.append(&2,String,used,blank(size - List.length(&2,String,used),Nil{}))
def combine(groups: List<&2,List<&2,String>>,sizes: List<&2,Nat>,+gap: Nat,first: Bool) -> List<&2,String>:
  match groups sizes:
    case Nil{} _: Nil{}
    case lines <> rest size <> more:
      +prefix = Bool.pick(List<&2,String>,first,Nil{},blank(gap,Nil{}))
      List.append(&2,String,prefix,List.append(&2,String,pad(lines,size),combine(rest,more,gap,False{})))
    case _ _: Nil{}
def finish(+groups: List<&2,List<&2,String>>,entries: List<&2,S.StackEntry>,+gap: Nat) -> List<&2,String>:
  +sizes = S.allocateStackSizes(S.sizeOptions(entries),lengths(groups),None{},gap)
  combine(groups,sizes,gap,True{})
def render(stack: S.Stack,+width: Nat) -> IO(List<&2,String>):
  match stack:
    case S.Stack{entries,gap,_,_}:
      do IO<List<&2,String>>:
        +visible : List<&2,S.StackEntry> <- S.visibleStackEntries(entries,S.LayoutViewport{Nat.max(1n,width),4294967295n})
        groups : List<&2,List<&2,String>> <- rendered(visible,Nat.max(1n,width),Nil{})
        return finish(groups,visible,gap)
