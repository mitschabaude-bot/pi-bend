import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/utils/event-stream.bend as S
import ./context.bend as H
import ./message-events.bend as Test

def EventValue() -> Data: T.AgentEvent<Unit, String, Unit, String, String, Unit, Unit>
def StreamValue() -> Data: Loop.AgentEventStream(Unit, String, Unit, String, String, Unit, Unit)

def event(value: S.Iteration<EventValue()>, expected: String) -> IO(Unit):
  match value:
    case S.Yield{value}: Test.assertion(String.eq(T.eventType(Unit, String, Unit, String, String, Unit, Unit, value), expected), "agent stream event order")
    case S.End{}: Test.assertion(String.eq(expected, "end"), "agent stream ended early")

def messages(values: H.Messages(), expected: Bool) -> IO(Unit):
  match values:
    case Nil{}: Test.assertion(Bool.not(expected), "agent stream lost final messages")
    case T.CustomMessage{text} <> Nil{}: Test.assertion(expected && String.eq(text, "completed"), "agent stream final messages changed")
    case _: Test.assertion(False{}, "unexpected agent result shape")

def history(present: Bool) -> H.Messages():
  match present:
    case True{}: T.CustomMessage{"completed"} <> Nil{}
    case False{}: Nil{}

def scenario(+present: Bool) -> IO(Unit):
  do IO<Unit>:
    +stream : StreamValue() <- Loop.createAgentStream(~Unit, ~String, ~Unit, ~String, ~String, ~Unit, ~Unit)
    +iterator : S.Iterator<EventValue(), H.Messages()> <- S.iterator(EventValue(), H.Messages(), stream)
    S.push(EventValue(), H.Messages(), stream, T.AgentStart{})
    S.push(EventValue(), H.Messages(), stream, T.TurnStart{})
    S.push(EventValue(), H.Messages(), stream, T.AgentEnd{history(present)})
    # Result settlement must not require draining buffered events.
    result : H.Messages() <- S.resultValue(EventValue(), H.Messages(), stream)
    messages(result, present)
    S.push(EventValue(), H.Messages(), stream, T.TurnStart{})
    first : S.Iteration<EventValue()> <- S.nextValue(EventValue(), H.Messages(), iterator)
    event(first, "agent_start")
    second : S.Iteration<EventValue()> <- S.nextValue(EventValue(), H.Messages(), iterator)
    event(second, "turn_start")
    last : S.Iteration<EventValue()> <- S.nextValue(EventValue(), H.Messages(), iterator)
    event(last, "agent_end")
    ended : S.Iteration<EventValue()> <- S.nextValue(EventValue(), H.Messages(), iterator)
    event(ended, "end")
    S.disposeIterator(EventValue(), H.Messages(), iterator)
    Loop.disposeAgentStream(Unit, String, Unit, String, String, Unit, Unit, stream)

def main() -> IO(Unit):
  do IO<Unit>:
    scenario(True{})
    scenario(False{})
    IO.print("PASS agent-end result settlement, buffered event order, empty histories and ignored late pushes")
