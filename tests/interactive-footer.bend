import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/modes/interactive/components/footer.bend as Footer
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Schema

# pi-mono footer.ts:87-108 counts completed assistant usage; the native event
# path must publish the same totals while replacing the active model/status.
def answer() -> Ai.AssistantMessage<Schema.Value,Unit>:
  Ai.AssistantMessage{Nil{},"openai-responses","faux","changed-model",None{},None{},None{},None{},
    Ai.Usage{F.fromNat(100n),F.fromNat(20n),F.fromNat(30n),F.fromNat(0n),None{},None{},F.fromNat(150n),Ai.UsageCost{F.fromNat(0n),F.fromNat(0n),F.fromNat(0n),F.fromNat(0n),F.fromNat(1n)}},
    Ai.Stop{},None{},None{},None{},None{},F.fromNat(0n)}
def initial() -> Footer.State:
  Footer.State{"/tmp",None{},None{},None{},Some{Footer.Model{"old-model","faux",False{},1000n}},"off",Footer.emptyUsage(),None{},None{},None{},1n,False{},False{},False{},Nil{}}
def after(pair: Footer.State & Bool) -> Footer.State:
  match pair: case (state,_): state
def hasUsage(state: Footer.State) -> Bool:
  match state:
    case Footer.State{_,_,_,_,Some{Footer.Model{"changed-model","faux",_,_}},_,Footer.Usage{100n,20n,30n,0n,_},Some{Footer.Usage{100n,20n,30n,0n,_}},Some{percent},_,_,_,_,_,_}: F.isEqual(F.compare(percent,F.fromNat(13n)))
    case _: False{}
def hasStatus(state: Footer.State) -> Bool:
  match state:
    case Footer.State{_,_,_,Some{"demo"},_,"high",_,_,_,_,_,_,_,_,Footer.Status{"agent","Working"} <> Nil{}}: True{}
    case _: False{}
def hasCleared(state: Footer.State) -> Bool:
  match state:
    case Footer.State{_,_,_,_,_,_,_,_,_,_,_,_,_,_,Nil{}}: True{}
    case _: False{}
def require(ok: Bool,reason: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,reason))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    +state : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(initial(),Session.AgentEvent{Agent.MessageEnd{Agent.LlmMessage{Ai.Assistant{answer()}}}})))
    require(hasUsage(state),"footer usage/model")
    +named : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(state,Session.SessionInfoChanged{Some{"demo"}})))
    +thinking : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(named,Session.ThinkingLevelChanged{Ai.Thinking{Ai.High{}}})))
    +working : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(thinking,Session.AgentEvent{Agent.AgentStart{}})))
    require(hasStatus(working),"footer status/name/thinking")
    +done : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(working,Session.AgentSettled{})))
    require(hasCleared(done),"footer status cleared")
    IO.print("interactive footer events passed")
