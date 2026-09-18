import Base
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/ref.bend as R
import ../../runtime/src/f64.bend as N

def EventValue() -> Data: T.AgentEvent<Unit, String, Unit, Unit, String, U32, Bool>
def MessageValue() -> Data: T.AgentMessage<Unit, String, Unit, Unit, String>

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def check(event: EventValue(), expected: String) -> IO(Unit):
  assertion(String.eq(T.eventType(Unit, String, Unit, Unit, String, U32, Bool, event), expected), "agent event discriminator differs from upstream")

def custom(message: MessageValue()) -> IO(String):
  match message:
    case T.CustomMessage{value}: R.read(String, value)
    case _: IO.die(String, 1, "custom message lost its variant")

def retained(event: EventValue()) -> IO(Unit):
  match event:
    case T.MessageEnd{message}:
      do IO<Unit>:
        value : String <- custom(message)
        assertion(String.eq(value, "after"), "retained custom message must observe mutation")
    case _: IO.die(Unit, 1, "message-end payload changed")

def assistant(cost: R.Ref<Ai.UsageCost>, reason: Ai.StopReason) -> Ai.AssistantMessage<String, Unit>:
  +zero = N.fromU32(0)
  Ai.AssistantMessage{Nil{}, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}, reason, None{}, None{}, None{}, None{}, zero}

def stopped(message: Ai.AssistantMessage<String, Unit>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Stop{}, _, _, _, _, _}: True{}
    case _: False{}

def updateIdentity(event: EventValue(), expected: R.Ref<Ai.AssistantMessage<String, Unit>>) -> IO(Unit):
  match event:
    case T.MessageUpdate{T.LlmMessage{Ai.Assistant{+message}}, Ai.Start{+partial}}:
      do IO<Unit>:
        assertion(R.same(Ai.AssistantMessage<String, Unit>, message, partial) && R.same(Ai.AssistantMessage<String, Unit>, partial, expected), "message update must retain the stream's original partial object")
        value : Ai.AssistantMessage<String, Unit> <- R.read(Ai.AssistantMessage<String, Unit>, message)
        assertion(stopped(value), "retained message update lost later assistant changes")
    case _: IO.die(Unit, 1, "message update changed its typed payload")

def partialPayload(event: EventValue()) -> Bool:
  match event:
    case T.ToolExecutionUpdate{id, name, args, partial}: String.eq(id, "id") && String.eq(name, "tool") && String.eq(args, "raw") && U32.is_eq(partial, 42)
    case _: False{}

def finalPayload(event: EventValue()) -> Bool:
  match event:
    case T.ToolExecutionEnd{id, name, result, isError}: String.eq(id, "id") && String.eq(name, "tool") && result && Bool.not(isError)
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : N.F64 = N.fromU32(0)
    +cost : R.Ref<Ai.UsageCost> <- R.new(Ai.UsageCost, Ai.UsageCost{zero, zero, zero, zero, zero})
    +partial : R.Ref<Ai.AssistantMessage<String, Unit>> <- R.new(Ai.AssistantMessage<String, Unit>, assistant(cost, Ai.Pending{}))
    +update : EventValue() = T.MessageUpdate{T.LlmMessage{Ai.Assistant{partial}}, Ai.Start{partial}}
    check(update, "message_update")
    R.write(Ai.AssistantMessage<String, Unit>, partial, assistant(cost, Ai.Stop{}))
    updateIdentity(update, partial)
    assertion(partialPayload(T.ToolExecutionUpdate{"id", "tool", "raw", 42}), "partial tool payload changed")
    assertion(finalPayload(T.ToolExecutionEnd{"id", "tool", True{}, False{}}), "final tool payload changed")
    oldMessage : Ai.AssistantMessage<String, Unit> <- R.dispose(Ai.AssistantMessage<String, Unit>, partial)
    oldCost : Ai.UsageCost <- R.dispose(Ai.UsageCost, cost)
    +value : R.Ref<String> <- R.new(String, "before")
    +message : MessageValue() = T.CustomMessage{value}
    check(T.AgentStart{}, "agent_start")
    check(T.AgentEnd{message <> Nil{}}, "agent_end")
    check(T.TurnStart{}, "turn_start")
    check(T.TurnEnd{message, Nil{}}, "turn_end")
    check(T.MessageStart{message}, "message_start")
    check(T.MessageEnd{message}, "message_end")
    check(T.ToolExecutionStart{"id", "name", "raw"}, "tool_execution_start")
    check(T.ToolExecutionUpdate{"id", "name", "raw", 42}, "tool_execution_update")
    check(T.ToolExecutionEnd{"id", "name", True{}, False{}}, "tool_execution_end")
    +event : EventValue() = T.MessageEnd{message}
    R.write(String, value, "after")
    retained(event)
    old : String <- R.dispose(String, value)
    IO.print("PASS all ten agent event variants, tool payloads and shared stream/custom-message identity")
