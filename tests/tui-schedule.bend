import Base
import ../packages/tui/src/tui-base.bend as B

# The queue models process.nextTick in FIFO order. Timer IDs remain in the
# production schedule state, so a cancelled callback can be tested explicitly.
type Sim is Data: Sim{state: B.RenderSchedule,queued: List<&2,B.RenderEvent>,output: String}
type Selected is Data: Selected{event: B.RenderEvent,state: B.RenderSchedule,queued: List<&2,B.RenderEvent>,output: String}
def flag(value: Bool) -> String: Bool.pick(String,value,"1","0")
def optional(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "-"
    case Some{id}: Nat.show(id)
def stateText(value: B.RenderSchedule) -> String:
  match value:
    case B.RenderSchedule{requested,immediate,timer,next,last,stopped}:
      flag(requested) ++ flag(immediate) ++ ":" ++ optional(timer) ++ ":" ++ Nat.show(next) ++ ":" ++ Nat.show(last) ++ ":" ++ flag(stopped)
def effectText(value: B.RenderEffect) -> String:
  match value:
    case B.QueueSchedule{}: "s"
    case B.QueueImmediate{}: "i"
    case B.CancelTimer{id}: "c" ++ Nat.show(id)
    case B.StartTimer{id,delayMs}: "t" ++ Nat.show(id) ++ "/" ++ Nat.show(delayMs)
    case B.ResetRenderState{}: "x"
    case B.DrawFrame{}: "d"
def queueEffects(effects: List<&2,B.RenderEffect>,queued: List<&2,B.RenderEvent>,+state: B.RenderSchedule,output: String,text: String) -> Sim:
  match effects:
    case Nil{}: Sim{state,queued,output ++ stateText(state) ++ "|" ++ text ++ "\n"}
    case B.QueueSchedule{} <> rest: queueEffects(rest,List.append(&2,B.RenderEvent,queued,B.ScheduleRender{} <> Nil{}),state,output,text ++ "s,")
    case B.QueueImmediate{} <> rest: queueEffects(rest,List.append(&2,B.RenderEvent,queued,B.ImmediateRender{} <> Nil{}),state,output,text ++ "i,")
    case effect <> rest: queueEffects(rest,queued,state,output,text ++ effectText(effect) ++ ",")
def activeTimer(value: B.RenderSchedule) -> Nat:
  match value:
    case B.RenderSchedule{_,_,None{},_,_,_}: 0n
    case B.RenderSchedule{_,_,Some{id},_,_,_}: id
def selectQueued(state: B.RenderSchedule,queued: List<&2,B.RenderEvent>,output: String) -> Selected:
  match queued:
    case Nil{}: Selected{B.ScheduleRender{},state,Nil{},output}
    case event <> rest: Selected{event,state,rest,output}
def eventFor(char: Char,sim: Sim) -> Selected:
  match char sim:
    case 'r' Sim{state,queued,output}: Selected{B.RequestRender{False{}},state,queued,output}
    case 'f' Sim{state,queued,output}: Selected{B.RequestRender{True{}},state,queued,output}
    case 'i' Sim{state,queued,output}: Selected{B.RequestImmediate{},state,queued,output}
    case 'q' Sim{state,queued,output}: selectQueued(state,queued,output)
    case 't' Sim{+state,queued,output}: Selected{B.TimerFired{activeTimer(state)},state,queued,output}
    case 'n' Sim{state,queued,output}: Selected{B.RenderNow{False{}},state,queued,output}
    case 'N' Sim{state,queued,output}: Selected{B.RenderNow{True{}},state,queued,output}
    case 'x' Sim{state,queued,output}: Selected{B.StopRendering{},state,queued,output}
    case 'b' Sim{state,queued,output}: Selected{B.StartRendering{},state,queued,output}
    case _ Sim{state,queued,output}: Selected{B.ScheduleRender{},state,queued,output}
def applied(scheduled: B.Scheduled,queued: List<&2,B.RenderEvent>,output: String) -> Sim:
  match scheduled:
    case B.Scheduled{next,effects}: queueEffects(effects,queued,next,output,"")
def applyChoice(choice: Selected,now: Nat) -> Sim:
  match choice:
    case Selected{event,state,queued,output}: applied(B.schedule(event,state,now),queued,output)
def step(char: Char,now: Nat,sim: Sim) -> Sim: applyChoice(eventFor(char,sim),now)
def run(chars: List<&2,Char>,+now: Nat,sim: Sim) -> Sim:
  match chars:
    case Nil{}: sim
    case char <> rest: run(rest,now + 5n,step(char,now,sim))
def result(sim: Sim) -> IO(Unit):
  match sim:
    case Sim{_,_,output}: IO.print(output)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    result(run(String.to_list(Maybe.default(&1,String,List.head(&1,String,args),"")),0n,Sim{B.newRenderSchedule(),Nil{},""}))
