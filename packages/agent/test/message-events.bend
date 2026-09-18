import Base
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../runtime/src/f64.bend as N

def EventValue() -> Data: T.AgentEvent<Unit, String, Unit, Unit, String, U32, Bool>
def MessageValue() -> Data: T.AgentMessage<Unit, String, Unit, Unit, String>

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def check(event: EventValue(), expected: String) -> IO(Unit):
  assertion(String.eq(T.eventType(Unit, String, Unit, Unit, String, U32, Bool, event), expected), "agent event discriminator differs from upstream")

def usage(cost: Ai.UsageCost) -> Ai.Usage:
  +zero = N.fromU32(0)
  Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}

def assistant(content: List<&2, Ai.AssistantContent<String>>, usageValue: Ai.Usage, reason: Ai.StopReason) -> Ai.AssistantMessage<String, Unit>:
  +zero = N.fromU32(0)
  Ai.AssistantMessage{content, "custom-api", "custom-provider", "model", None{}, None{}, None{}, None{}, usageValue, reason, None{}, None{}, None{}, None{}, zero}

def stopped(message: Ai.AssistantMessage<String, Unit>) -> Bool:
  match message:
    case Ai.AssistantMessage{_, _, _, _, _, _, _, _, _, Ai.Stop{}, _, _, _, _, _}: True{}
    case _: False{}

def partialPayload(event: EventValue()) -> Bool:
  match event:
    case T.ToolExecutionUpdate{id, name, args, partial}: String.eq(id, "id") && String.eq(name, "tool") && String.eq(args, "raw") && U32.is_eq(partial, 42)
    case _: False{}

def finalPayload(event: EventValue()) -> Bool:
  match event:
    case T.ToolExecutionEnd{id, name, result, isError}: String.eq(id, "id") && String.eq(name, "tool") && result && Bool.not(isError)
    case _: False{}

def custom(message: MessageValue()) -> IO(String):
  match message:
    case T.CustomMessage{value}: IO.pure(String, value)
    case _: IO.die(String, 1, "custom message lost its variant")

def main() -> IO(Unit):
  do IO<Unit>:
    +zero : N.F64 = N.fromU32(0)
    +cost : Ai.UsageCost = Ai.UsageCost{zero, zero, zero, zero, zero}
    +partial : Ai.AssistantMessage<String, Unit> = assistant(Nil{}, usage(cost), Ai.Pending{})
    check(T.MessageUpdate{T.LlmMessage{Ai.Assistant{partial}}, Ai.Start{partial}}, "message_update")
    assertion(partialPayload(T.ToolExecutionUpdate{"id", "tool", "raw", 42}), "partial tool payload changed")
    assertion(finalPayload(T.ToolExecutionEnd{"id", "tool", True{}, False{}}), "final tool payload changed")
    +message : MessageValue() = T.CustomMessage{"before"}
    check(T.AgentStart{}, "agent_start")
    check(T.AgentEnd{message <> Nil{}}, "agent_end")
    check(T.TurnStart{}, "turn_start")
    check(T.TurnEnd{message, Nil{}}, "turn_end")
    check(T.MessageStart{message}, "message_start")
    check(T.MessageEnd{message}, "message_end")
    check(T.ToolExecutionStart{"id", "name", "raw"}, "tool_execution_start")
    check(T.ToolExecutionUpdate{"id", "name", "raw", 42}, "tool_execution_update")
    check(T.ToolExecutionEnd{"id", "name", True{}, False{}}, "tool_execution_end")
    IO.print("PASS all ten agent event variants and independently typed tool payloads")
