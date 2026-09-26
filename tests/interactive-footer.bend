import Base
import ../packages/agent/src/types.bend as Agent
import ../packages/ai/src/types.bend as Ai
import ../packages/coding-agent/src/core/agent-session.bend as Session
import ../packages/coding-agent/src/core/session-stats.bend as Stats
import ../packages/coding-agent/src/modes/interactive/components/footer.bend as Footer
import ../packages/coding-agent/src/modes/interactive/run.bend as Run
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/schema-value.bend as Schema

# The rendered footer reads totals across all stored entries and context from
# the session; an assistant event only changes its latest-response cache rate.
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
def hasUnknownContext(state: Footer.State) -> Bool:
  match state:
    case Footer.State{_,_,_,_,_,_,Footer.Usage{100n,20n,30n,0n,_},_,None{},Some{1000n},_,_,_,_,_}: True{}
    case _: False{}
def totals(context: Stats.ContextUsage) -> Stats.Stats:
  Stats.Stats{None{},"session",Stats.Totals{0n,0n,0n,0n,0n,F.fromNat(100n),F.fromNat(20n),F.fromNat(30n),F.fromNat(0n),F.fromNat(1n)},Some{context}}
def hasStatus(state: Footer.State) -> Bool:
  match state:
    case Footer.State{_,_,_,Some{"demo"},_,"high",_,_,_,_,_,_,_,_,Footer.Status{"agent","Working"} <> Nil{}}: True{}
    case _: False{}
def require(ok: Bool,reason: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,reason))(Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    +eventState : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(initial(),Session.AgentEvent{Agent.MessageEnd{Agent.LlmMessage{Ai.Assistant{answer()}}}})))
    +state : Footer.State <- IO.pure(Footer.State,Run.withStats(eventState,totals(Stats.ContextUsage{Some{F.fromNat(130n)},F.fromNat(1000n),Some{F.fromNat(13n)}})))
    require(hasUsage(state),"footer stored usage/context/model")
    require(hasUnknownContext(Run.withStats(state,totals(Stats.ContextUsage{None{},F.fromNat(1000n),None{}}))),"compaction should make context unknown without dropping billed totals")
    +named : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(state,Session.SessionInfoChanged{Some{"demo"}})))
    +thinking : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(named,Session.ThinkingLevelChanged{Ai.Thinking{Ai.High{}}})))
    +working : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(Run.withStatus(thinking,[Footer.Status{"agent","Working"}]),Session.AgentEvent{Agent.AgentStart{}})))
    require(hasStatus(working),"footer status/name/thinking")
    +done : Footer.State <- IO.pure(Footer.State,after(Run.footerEvent(working,Session.AgentSettled{})))
    require(hasStatus(done),"agent settlement preserves extension footer status")
    IO.print("interactive footer events passed")
