import Base
import ./output-accumulator.bend as Report
import ../packages/coding-agent/src/core/tools/output-accumulator.bend as Output
import ../packages/coding-agent/src/core/tools/truncate.bend as Truncate
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/string.bend as Strings

type UpdateEvent is Data: UpdateEvent{content: String, bytes: Nat, time: Nat}
type Context is Data:
  Context{events: Chan(UpdateEvent), count: Ref.Ref<Nat>, handle: Ref.Ref<Maybe<&2,Output.StreamHandle>>, delay: U32, reenter: Bool}

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def checkResult(value: Result<&2,&2,Output.Error,Unit>) -> IO(Unit):
  match value:
    case Done{Unit{}}: IO.pure(Unit,Unit{})
    case Fail{_}: IO.die(Unit,1,"append failed")

def closedTimer(value: Timer & Bool) -> IO(Unit):
  match value:
    case (owner,_): Timer.close(owner)

def sleeping(pair: Timer & TimerCancel) -> IO(Unit):
  match pair:
    case (owner,_):
      do IO<Unit>:
        value : Timer & Bool <- Timer.wait(owner)
        closedTimer(value)

def sleep(milliseconds: U32) -> IO(Unit):
  do IO<Unit>:
    pair : Timer & TimerCancel <- Timer.new(milliseconds)
    sleeping(pair)

def reenter(enabled: Bool, handle: Maybe<&2,Output.StreamHandle>) -> IO(Unit):
  match enabled handle:
    case True{} Some{handle}:
      do IO<Unit>:
        result : Result<&2,&2,Output.Error,Unit> <- Output.appendStream(handle,82 <> Nil{})
        checkResult(result)
    case _ _: IO.pure(Unit,Unit{})

def event(time: Nat, snapshot: Output.OutputSnapshot) -> UpdateEvent:
  match snapshot:
    case Output.OutputSnapshot{content,Truncate.TruncationResult{_,_,_,_,bytes,_,_,_,_,_,_},_}: UpdateEvent{content,bytes,time}

def observed(context: Context, snapshot: Output.OutputSnapshot) -> IO(Unit):
  match context:
    case Context{events,+count,handle,+delay,enabled}:
      do IO<Unit>:
        now : Nat <- IO.now()
        previous : Nat <- Ref.modify(Nat,Nat,count,+n => (n + 1n,n))
        current : Maybe<&2,Output.StreamHandle> <- Ref.read(Maybe<&2,Output.StreamHandle>,handle)
        reenter(enabled,current)
        sent : Bool <- Chan.send(UpdateEvent,events,event(now,snapshot))
        Bool.pick(Unit -> IO(Unit),U32.is_eq(delay,0),_ => IO.pure(Unit,Unit{}),_ => sleep(delay))(Unit{})
        completed : Nat <- Ref.modify(Nat,Nat,count,+n => (n + 1n,n))
        return Unit{}

def received(value: Maybe<&1,UpdateEvent>) -> IO(UpdateEvent):
  match value:
    case Some{event}: IO.pure(UpdateEvent,event)
    case None{}: IO.die(UpdateEvent,1,"events closed early")

def receive(events: Chan(UpdateEvent)) -> IO(UpdateEvent):
  IO.bind(Maybe<&1,UpdateEvent>,UpdateEvent,Chan.recv(UpdateEvent,events),received)

def callback(context: Context) -> IO(Callback.Callback<Output.OutputSnapshot,Unit>):
  Callback.create(~Context,~Output.OutputSnapshot,~Unit,~observed,context)

def countOf(context: Context) -> IO(Nat):
  match context:
    case Context{_,count,_,_,_}: Ref.read(Nat,count)

def cleanup(context: Context, observer: Callback.Callback<Output.OutputSnapshot,Unit>) -> IO(Unit):
  match context:
    case Context{events,count,handle,_,_}:
      do IO<Unit>:
        Callback.dispose(Output.OutputSnapshot,Unit,observer)
        oldCount : Nat <- Ref.dispose(Nat,count)
        oldHandle : Maybe<&2,Output.StreamHandle> <- Ref.dispose(Maybe<&2,Output.StreamHandle>,handle)
        Chan.close(UpdateEvent,events)

def context(delay: U32, enabled: Bool) -> IO(Context):
  do IO<Context>:
    events : Chan(UpdateEvent) <- Chan.new(UpdateEvent,512)
    count : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    handle : Ref.Ref<Maybe<&2,Output.StreamHandle>> <- Ref.new(Maybe<&2,Output.StreamHandle>,None{})
    return Context{events,count,handle,delay,enabled}

def bindHandle(context: Context, +handle: Output.StreamHandle) -> IO(Unit):
  match context:
    case Context{_,_,reference,_,_}: Ref.write(Maybe<&2,Output.StreamHandle>,reference,Some{handle})

def events(context: Context) -> Chan(UpdateEvent):
  match context:
    case Context{events,_,_,_,_}: events

def content(value: UpdateEvent) -> String:
  match value:
    case UpdateEvent{content,_,_}: content

def time(value: UpdateEvent) -> Nat:
  match value:
    case UpdateEvent{_,_,time}: time

def total(value: Output.OutputSnapshot) -> Nat:
  match value:
    case Output.OutputSnapshot{_,Truncate.TruncationResult{_,_,_,_,bytes,_,_,_,_,_,_},_}: bytes

def finalContent(expected: String, snapshot: Output.OutputSnapshot) -> IO(Unit):
  match snapshot:
    case Output.OutputSnapshot{content,_,_}: check(Strings.equal(expected,content),"final content")

def finished(expected: String, expectedBytes: Nat, expectedLast: Nat, value: Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat>) -> IO(Unit):
  match value:
    case Done{Tuple{+snapshot,last}}:
      do IO<Unit>:
        check(Nat.is_eq(total(snapshot),expectedBytes),"final byte count")
        check(Nat.is_eq(last,expectedLast),"last-line byte count")
        finalContent(expected,snapshot)
    case Fail{_}: IO.die(Unit,1,"finish failed")

def append(handle: Output.StreamHandle, byte: U32) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Output.Error,Unit> <- Output.appendStream(handle,byte <> Nil{})
    checkResult(result)

# First publication has no initial delay, later dirty snapshots are coalesced,
# and final dirty publication bypasses an outstanding cooldown.
def throttleCase(+ctx: Context, pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        start : Nat <- IO.now()
        append(handle,97)
        +first : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(first),"a"),"leading update")
        check(Nat.is_lt(time(first) - start,85n),"leading update delayed")
        append(handle,98)
        append(handle,99)
        +second : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(second),"abc"),"coalesced update")
        check(Nat.is_ge(time(second) - time(first),85n),"throttle too fast")
        append(handle,100)
        before : Nat <- IO.now()
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        after : Nat <- IO.now()
        finished("abcd",4n,4n,result)
        check(Nat.is_lt(after - before,85n),"finish did not cancel cooldown")
        final : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(final),"abcd"),"final dirty update")
        count : Nat <- countOf(ctx)
        check(Nat.is_eq(count,6n),"extra callback")

def reentryCase(+ctx: Context, pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        bindHandle(ctx,handle)
        append(handle,97)
        first : UpdateEvent <- receive(events(ctx))
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        finished("aR",2n,2n,result)
        final : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(final),"aR"),"closed acceptance reentry")
        count : Nat <- countOf(ctx)
        check(Nat.is_eq(count,4n),"reentry callback count")

def slowCase(+ctx: Context, pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        append(handle,97)
        first : UpdateEvent <- receive(events(ctx))
        append(handle,98)
        second : UpdateEvent <- receive(events(ctx))
        +elapsed : Nat <- IO.pure(Nat,time(second) - time(first))
        check(Nat.is_ge(elapsed,125n) && Nat.is_lt(elapsed,225n),"slow callback gained extra cooldown")
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        finished("ab",2n,2n,result)
        count : Nat <- countOf(ctx)
        check(Nat.is_eq(count,4n),"clean finish emitted again")

def observedCase(+mode: String) -> IO(Unit):
  +slow = Strings.equal(mode,"slow")
  +reentry = Strings.equal(mode,"reentry")
  do IO<Unit>:
    +ctx : Context <- context(Bool.pick(U32,slow,140,0),reentry)
    +observer : Callback.Callback<Output.OutputSnapshot,Unit> <- callback(ctx)
    owner : Output.StreamOwner <- Output.createStream(Output.defaults(),Some{observer})
    Bool.pick(Output.StreamOwner -> IO(Unit),slow,owner => slowCase(ctx,Output.borrowStream(owner)),
      owner => Bool.pick(Output.StreamOwner -> IO(Unit),reentry,owner => reentryCase(ctx,Output.borrowStream(owner)),owner => throttleCase(ctx,Output.borrowStream(owner)))(owner))(owner)
    cleanup(ctx,observer)
    IO.print(mode ++ ":ok")

def silentCase(pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        append(handle,97)
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        finished("a",1n,1n,result)

def producer(n: Nat, +handle: Output.StreamHandle) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+n:
      do IO<Unit>:
        append(handle,120)
        producer(n,handle)

def repeated(n: Nat, text: String) -> String:
  match n:
    case 0n: text
    case 1n+n: repeated(n,SCon{'x',text})

def concurrentCase(pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,+handle}:
      do IO<Unit>:
        first : Chan(Unit) <- IO.fork(Unit,producer(64n,handle))
        second : Chan(Unit) <- IO.fork(Unit,producer(64n,handle))
        third : Chan(Unit) <- IO.fork(Unit,producer(64n,handle))
        fourth : Chan(Unit) <- IO.fork(Unit,producer(64n,handle))
        IO.join(Unit,first)
        IO.join(Unit,second)
        IO.join(Unit,third)
        IO.join(Unit,fourth)
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        finished(repeated(256n,""),256n,256n,result)

def emptyObserved() -> IO(Unit):
  do IO<Unit>:
    +ctx : Context <- context(0,False{})
    +observer : Callback.Callback<Output.OutputSnapshot,Unit> <- callback(ctx)
    owner : Output.StreamOwner <- Output.createStream(Output.defaults(),Some{observer})
    result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
    finished("",0n,0n,result)
    count : Nat <- countOf(ctx)
    check(Nat.is_eq(count,0n),"empty stream published")
    cleanup(ctx,observer)

def incompleteCase(+ctx: Context, pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,handle}:
      do IO<Unit>:
        appended : Result<&2,&2,Output.Error,Unit> <- Output.appendStream(handle,240 <> 159 <> Nil{})
        checkResult(appended)
        first : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(first),""),"pending UTF8 emitted early")
        result : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        finished("\u{FFFD}",3n,3n,result)
        last : UpdateEvent <- receive(events(ctx))
        check(Strings.equal(content(last),"\u{FFFD}"),"finish UTF8 dirty update missing")

def incompleteObserved() -> IO(Unit):
  do IO<Unit>:
    +ctx : Context <- context(0,False{})
    +observer : Callback.Callback<Output.OutputSnapshot,Unit> <- callback(ctx)
    owner : Output.StreamOwner <- Output.createStream(Output.defaults(),Some{observer})
    incompleteCase(ctx,Output.borrowStream(owner))
    cleanup(ctx,observer)

def concurrentObserved() -> IO(Unit):
  do IO<Unit>:
    +ctx : Context <- context(0,False{})
    +observer : Callback.Callback<Output.OutputSnapshot,Unit> <- callback(ctx)
    owner : Output.StreamOwner <- Output.createStream(Output.defaults(),Some{observer})
    concurrentCase(Output.borrowStream(owner))
    calls : Nat <- countOf(ctx)
    check(Nat.is_ge(calls,2n),"concurrent output not published")
    cleanup(ctx,observer)

def scenarios() -> IO(Unit):
  do IO<Unit>:
    observedCase("throttle")
    observedCase("reentry")
    observedCase("slow")
    owner : Output.StreamOwner <- Output.createStream(Output.defaults(),None{})
    silentCase(Output.borrowStream(owner))
    IO.print("silent:ok")
    concurrent : Output.StreamOwner <- Output.createStream(Output.defaults(),None{})
    concurrentCase(Output.borrowStream(concurrent))
    IO.print("concurrent:ok")
    concurrentObserved()
    IO.print("concurrent-observed:ok")
    emptyObserved()
    IO.print("empty:ok")
    incompleteObserved()
    IO.print("incomplete:ok")


def finishedError(value: Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat>) -> String:
  match value:
    case Fail{cause}: Report.error(cause)
    case Done{_}: "ok"

def faultCase(pair: Output.StreamOwner & Output.StreamHandle) -> IO(Unit):
  match pair:
    case Tuple{owner,handle}:
      do IO<Unit>:
        result : Result<&2,&2,Output.Error,Unit> <- Output.appendStream(handle,97 <> 98 <> 99 <> Nil{})
        IO.print(Report.status(result))
        final : Result<&2,&1,Output.Error,Output.OutputSnapshot & Nat> <- Output.finishStream(owner)
        IO.print(finishedError(final))

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case "fault" <> Nil{}:
      do IO<Unit>:
        owner : Output.StreamOwner <- Output.createStream(Output.OutputAccumulatorOptions{Some{1n},Some{1n},Some{"pi-bend-output-test"}},None{})
        faultCase(Output.borrowStream(owner))
    case _: scenarios()

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
