import Base
import ../src/api/openai-sse.bend as Sse
import ../../runtime/src/json.bend as Json
import ../../runtime/src/sse.bend as SSE
import ../../runtime/src/schema-value.bend as V
import ../../runtime/test/utf8-runner.bend as H

def text(value: String) -> String:
  H.fromScalars(H.parseNumbers(value))

def compareValue(value: V.Value, expected: Result<&2, &2, Json.ParseError, V.Value>) -> Bool:
  match expected:
    case Fail{_}: False{}
    case Done{other}: V.equal(value, other)

def valueMatches(value: V.Value, expected: String) -> Bool:
  compareValue(value, Json.parse(expected))

def name(value: String) -> Maybe<&2, String>:
  match value:
    case "N": None{}
    case value: Some{text(value)}

def showName(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "N"
    case Some{value}: "S" ++ H.showText(value)

def showTarget(value: Sse.DiagnosticTarget) -> String:
  match value:
    case Sse.ClientLogger{}: "client"
    case Sse.ConsoleLogger{}: "console"

def matches(step: Sse.Step, expected: List<&2, String>) -> Bool:
  match step expected:
    case Sse.Skip{Sse.DoneMarker{}} "done" <> Nil{}: True{}
    case Sse.YieldMessage{Sse.JsonMessage{data}} "json" <> payload <> Nil{}: valueMatches(data, payload)
    case Sse.YieldMessage{Sse.EventMessage{event, data}} "event" <> eventText <> payload <> Nil{}:
      Bool.and(String.eq(showName(event), eventText), valueMatches(data, payload))
    case Sse.Reject{Sse.ApiErrorPayload{error}} "error" <> payload <> Nil{}: valueMatches(error, payload)
    case Sse.Reject{Sse.InvalidJson{_, data, raw, target}} "invalid" <> targetText <> dataText <> rawText <> Nil{}:
      Bool.and(String.eq(showTarget(target), targetText), Bool.and(String.eq(H.showText(data), dataText), String.eq(String.join(raw, "|"), rawText)))
    case _ _: False{}

def state(value: String) -> Sse.State:
  match value:
    case "1": Sse.DoneMarker{}
    case _: Sse.Receiving{}

def execute(parts: List<&2, String>) -> String:
  match parts:
    case done <> synthesize <> event <> data <> expected <> Nil{}:
      Bool.pick(String, matches(Sse.step(state(done), String.eq(synthesize, "1"), SSE.ServerSentEvent{name(event), text(data), "diagnostic" <> Nil{}}), String.split(text(expected), '/')), "pass", "FAIL")
    case _: "bad input"

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, value} <> rest:
      do IO<Unit>:
        IO.print(execute(String.split(value, '/')))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
