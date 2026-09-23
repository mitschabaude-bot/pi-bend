import Base
import ./stack.bend as S
import ../component.bend as C
import ../utils.bend as U
import ../tui.bend as T

type Child is Data: Child{width: Nat,lines: List<&2,String>}
def new(gap: Nat,align: S.Align) -> S.Stack: S.new(S.Horizontal{},gap,align)
def lineWidth(lines: List<&2,String>) -> Nat:
  match lines:
    case Nil{}: 0n
    case line <> rest: Nat.max(U.visibleWidth(line),lineWidth(rest))
def intrinsic(entries: List<&2,S.StackEntry>,+width: Nat,reversed: List<&2,Nat>) -> IO(List<&2,Nat>):
  match entries:
    case Nil{}: IO.pure(List<&2,Nat>,List.reverse(&2,Nat,reversed))
    case S.StackEntry{component,_,_} <> rest:
      do IO<List<&2,Nat>>:
        lines : List<&2,String> <- C.render(component,width)
        intrinsic(rest,width,lineWidth(lines) <> reversed)
def rendered(entries: List<&2,S.StackEntry>,widths: List<&2,Nat>,+reversed: List<&2,Child>) -> IO(List<&2,Child>):
  match entries widths:
    case Nil{} _: IO.pure(List<&2,Child>,List.reverse(&2,Child,reversed))
    case S.StackEntry{component,_,_} <> +rest +width <> +more:
      Bool.pick(Unit -> IO(List<&2,Child>),Nat.is_eq(width,0n),
        _ => rendered(rest,more,Child{width,Nil{}} <> reversed),
        _ => do IO<List<&2,Child>>:
          lines : List<&2,String> <- C.render(component,width)
          rendered(rest,more,Child{width,lines} <> reversed))(Unit{})
    case _ _: IO.pure(List<&2,Child>,List.reverse(&2,Child,reversed))
def height(children: List<&2,Child>) -> Nat:
  match children:
    case Nil{}: 0n
    case Child{_,lines} <> rest: Nat.max(List.length(&2,String,lines),height(rest))
def blanks(count: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match count:
    case Zero{}: List.reverse(&2,String,reversed)
    case Succ{rest}: blanks(rest,"" <> reversed)
def offset(align: S.Align,outer: Nat,inner: Nat) -> Nat:
  match align:
    case S.Center{}: (outer - inner) / 2n
    case S.End{}: outer - inner
    case _: 0n
def paint(rows: List<&2,String>,child: List<&2,String>,+x: Nat,+childWidth: Nat,+totalWidth: Nat) -> List<&2,String>:
  match rows child:
    case Nil{} _: Nil{}
    case row <> rest Nil{}: row <> rest
    case row <> rest line <> more: T.compositeTuiLine(row,line,x,childWidth,totalWidth) <> paint(rest,more,x,childWidth,totalWidth)
def aligned(+lines: List<&2,String>,align: S.Align,outer: Nat) -> List<&2,String>:
  List.append(&2,String,blanks(offset(align,outer,List.length(&2,String,lines)),Nil{}),lines)
def compose(children: List<&2,Child>,rows: List<&2,String>,+x: Nat,+gap: Nat,+totalWidth: Nat,+align: S.Align,+outerHeight: Nat) -> List<&2,String>:
  match children:
    case Nil{}: rows
    case Child{+width,lines} <> rest:
      +next = paint(rows,aligned(lines,align,outerHeight),x,width,totalWidth)
      compose(rest,next,x + width + gap,gap,totalWidth,align,outerHeight)
def finish(+children: List<&2,Child>,width: Nat,gap: Nat,align: S.Align) -> List<&2,String>:
  +outer = height(children)
  compose(children,blanks(outer,Nil{}),0n,gap,width,align,outer)
def render(stack: S.Stack,width: Nat) -> IO(List<&2,String>):
  match stack:
    case S.Stack{entries,+gap,align,_}:
      do IO<List<&2,String>>:
        +safeWidth : Nat <- IO.pure(Nat,Nat.max(1n,width))
        +visible : List<&2,S.StackEntry> <- S.visibleStackEntries(entries,S.LayoutViewport{safeWidth,4294967295n})
        natural : List<&2,Nat> <- intrinsic(visible,safeWidth,Nil{})
        +widths : List<&2,Nat> <- IO.pure(List<&2,Nat>,S.allocateStackSizes(S.sizeOptions(visible),natural,Some{safeWidth},gap))
        children : List<&2,Child> <- rendered(visible,widths,Nil{})
        return finish(children,safeWidth,gap,align)
