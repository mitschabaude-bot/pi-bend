import Base
import ../packages/tui/src/components/alt-screen-flash.bend as Flash
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/timer.bend as Timer

def count(counter: Ref.Ref<Nat>,_: Unit) -> IO(Unit):
  do IO<Unit>:
    changed : Nat <- Ref.modify(Nat,Nat,counter,+old => (Succ{old},Succ{old}))
    return Unit{}
def joined(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: line
    case line <> rest: line ++ "|" ++ joined(rest)
def show(+lines: List<&2,String>) -> String:
  Nat.show(List.length(&2,String,lines)) ++ ":" ++ joined(lines)
def snapshot(pair: Flash.Owner & Flash.Handle,width: Nat) -> IO(Flash.Owner):
  match pair:
    case (owner,handle):
      do IO<Flash.Owner>:
        lines : List<&2,String> <- Flash.renderLive(handle,width)
        IO.print(show(lines))
        return owner
def capture(owner: Flash.Owner,width: Nat) -> IO(Flash.Owner):
  snapshot(Flash.borrow(owner),width)
def closeTimer(pair: Timer & Bool) -> IO(Unit):
  match pair: case (timer,_): Timer.close(timer)
def waitTimer(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (timer,_):
      do IO<Unit>:
        result : Timer & Bool <- Timer.wait(timer)
        closeTimer(result)
def pause(milliseconds: U32) -> IO(Unit):
  do IO<Unit>:
    pair : Timer & TimerCancel <- Timer.new(milliseconds)
    waitTimer(pair)
def taken(pair: Flash.AltScreenFlashContainer & (C.Callback<Unit,Unit> & Bool)) -> Flash.AltScreenFlashContainer:
  match pair: case (state,_): state
def tied(redraw: C.Callback<Unit,Unit>) -> IO(Unit):
  +first = Flash.append(Flash.initial(redraw),"one",10n)
  +second = Flash.append(first,"two",10n)
  do IO<Unit>:
    IO.print(show(Flash.render(second,10n)))
    +afterFirst : Flash.AltScreenFlashContainer <- IO.pure(Flash.AltScreenFlashContainer,taken(Flash.removed(second,10n)))
    IO.print(show(Flash.render(afterFirst,10n)))
    +afterSecond : Flash.AltScreenFlashContainer <- IO.pure(Flash.AltScreenFlashContainer,taken(Flash.removed(afterFirst,10n)))
    IO.print(show(Flash.render(afterSecond,10n)))
    return Unit{}
def main() -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +redraw : C.Callback<Unit,Unit> <- C.create(~Ref.Ref<Nat>,~Unit,~Unit,~count,counter)
    owner : Flash.Owner <- Flash.create(redraw)
    first : Flash.Owner <- Flash.flash(owner,"hi",Some{300})
    a : Flash.Owner <- capture(first,0n)
    b : Flash.Owner <- capture(a,1n)
    c : Flash.Owner <- capture(b,4n)
    d : Flash.Owner <- capture(c,10n)
    second : Flash.Owner <- Flash.flash(d,"wide 界",Some{50})
    e : Flash.Owner <- capture(second,6n)
    pause(100)
    f : Flash.Owner <- capture(e,10n)
    pause(250)
    g : Flash.Owner <- capture(f,10n)
    third : Flash.Owner <- Flash.flash(g,"dispose",Some{1000})
    h : Flash.Owner <- capture(third,10n)
    Flash.dispose(h)
    calls : Nat <- Ref.read(Nat,counter)
    IO.print(Nat.show(calls))
    tied(redraw)
    C.dispose(Unit,Unit,redraw)
    final : Nat <- Ref.dispose(Nat,counter)
    return Unit{}
