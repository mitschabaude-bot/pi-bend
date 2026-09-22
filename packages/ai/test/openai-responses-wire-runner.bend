import Base
import ../src/api/openai-responses-stream.bend as Stream
import ../src/api/openai-sse.bend as Sse
import ../src/types.bend as Ai
import ../../runtime/src/json-decode.bend as D
import ../../runtime/src/json-parse.bend as Parse
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/f64.bend as F
import ../../runtime/test/utf8-runner.bend as H

def optionalText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}

def optionalNumber(value: Maybe<&2, F.F64>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{number}: V.Number{number}

def phase(value: Maybe<&2, Ai.TextSignaturePhase>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Ai.Commentary{}}: V.Text{"commentary"}
    case Some{Ai.FinalAnswer{}}: V.Text{"final_answer"}

def strings(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: V.Text{head} <> strings(rest)

def item(value: Stream.OutputItem) -> V.Value:
  match value:
    case Stream.ReasoningItem{fields}: V.ArrayValue{V.Text{"reasoning"} <> V.ObjectValue{fields} <> Nil{}}
    case Stream.MessageItem{id, role, content}: V.ArrayValue{V.Text{"message"} <> V.Text{id} <> phase(role) <> V.ArrayValue{strings(content)} <> Nil{}}
    case Stream.FunctionItem{id, callId, name, arguments, namespace}: V.ArrayValue{V.Text{"function_call"} <> V.Text{id} <> V.Text{callId} <> V.Text{name} <> V.Text{arguments} <> optionalText(namespace) <> Nil{}}
    case Stream.CustomItem{id, callId, name, input, namespace}: V.ArrayValue{V.Text{"custom_tool_call"} <> V.Text{id} <> V.Text{callId} <> V.Text{name} <> optionalText(input) <> optionalText(namespace) <> Nil{}}
    case Stream.OtherItem{}: V.ArrayValue{V.Text{"other"} <> Nil{}}

def items(values: List<&2, Stream.OutputItem>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case head <> rest: item(head) <> items(rest)

def usage(value: Maybe<&2, Stream.ResponseUsage>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{Stream.ResponseUsage{input, output, cached, written, reasoning, total}}:
      V.ArrayValue{optionalNumber(input) <> optionalNumber(output) <> optionalNumber(cached) <> optionalNumber(written) <> optionalNumber(reasoning) <> optionalNumber(total) <> Nil{}}

def response(value: Stream.Response) -> V.Value:
  match value:
    case Stream.Response{id, status, reason, output, accounting, tier}:
      V.ArrayValue{optionalText(id) <> optionalText(status) <> optionalText(reason) <> V.ArrayValue{items(output)} <> usage(accounting) <> optionalText(tier) <> Nil{}}

def providerError(value: Stream.ProviderError) -> V.Value:
  match value:
    case Stream.ProviderError{code, message}: V.ArrayValue{optionalText(code) <> optionalText(message) <> Nil{}}

def optionalError(value: Maybe<&2, Stream.ProviderError>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: providerError(value)

def input(value: Stream.Input) -> V.Value:
  match value:
    case Stream.ThinkingDelta{text}: V.ArrayValue{V.Text{"thinking"} <> V.Text{text} <> Nil{}}
    case Stream.SummaryPartDone{}: V.ArrayValue{V.Text{"summary_done"} <> Nil{}}
    case Stream.TextDelta{text}: V.ArrayValue{V.Text{"text"} <> V.Text{text} <> Nil{}}
    case Stream.FunctionDelta{text}: V.ArrayValue{V.Text{"function_delta"} <> V.Text{text} <> Nil{}}
    case Stream.FunctionDone{text}: V.ArrayValue{V.Text{"function_done"} <> V.Text{text} <> Nil{}}
    case Stream.CustomDelta{text}: V.ArrayValue{V.Text{"custom_delta"} <> V.Text{text} <> Nil{}}
    case Stream.CustomDone{text}: V.ArrayValue{V.Text{"custom_done"} <> V.Text{text} <> Nil{}}
    case Stream.ItemDone{value}: V.ArrayValue{V.Text{"item_done"} <> item(value) <> Nil{}}

def event(value: Stream.ResponseStreamEvent) -> V.Value:
  match value:
    case Stream.ContentEvent{Stream.Added{index, value}}: V.ArrayValue{V.Text{"added"} <> V.Number{index} <> item(value) <> Nil{}}
    case Stream.ContentEvent{Stream.Changed{index, value}}: V.ArrayValue{V.Text{"changed"} <> V.Number{index} <> input(value) <> Nil{}}
    case Stream.ResponseCreated{id}: V.ArrayValue{V.Text{"created"} <> V.Text{id} <> Nil{}}
    case Stream.ResponseCompleted{value}: V.ArrayValue{V.Text{"completed"} <> response(value) <> Nil{}}
    case Stream.ResponseIncomplete{value}: V.ArrayValue{V.Text{"incomplete"} <> response(value) <> Nil{}}
    case Stream.ResponseFailed{status, cause, reason}: V.ArrayValue{V.Text{"failed"} <> optionalText(status) <> optionalError(cause) <> optionalText(reason) <> Nil{}}
    case Stream.ResponseError{code, message}: V.ArrayValue{V.Text{"error"} <> optionalText(code) <> V.Text{message} <> Nil{}}
    case Stream.IgnoredEvent{}: V.ArrayValue{V.Text{"ignored"} <> Nil{}}

def decode(mode: String, value: V.Value) -> Result<&2, &2, D.Error, V.Value>:
  match mode:
    case "d": Result.map(&2, &2, D.Error, Stream.ResponseStreamEvent, V.Value, event, Stream.decodeEvent(value))
    case "j": Result.map(&2, &2, D.Error, Stream.ResponseStreamEvent, V.Value, event, Stream.fromMessage(Sse.JsonMessage{value}))
    case "s": Result.map(&2, &2, D.Error, Stream.ResponseStreamEvent, V.Value, event, Stream.fromMessage(Sse.EventMessage{Some{"thread.run"}, value}))
    case "i": Result.map(&2, &2, D.Error, Stream.OutputItem, V.Value, item, Stream.decodeItem(value))
    case "r": Result.map(&2, &2, D.Error, Stream.Response, V.Value, response, Stream.decodeResponse(value))
    case _: Result.map(&2, &2, D.Error, Stream.ProviderError, V.Value, providerError, Stream.decodeProviderError(value))

def path(segments: List<&2, D.Segment>) -> String:
  match segments:
    case Nil{}: ""
    case D.Field{name} <> rest: "/" ++ name ++ path(rest)
    case D.Index{index} <> rest: "/" ++ U32.show(U32.from_nat(index)) ++ path(rest)

def error(value: D.Error) -> String:
  match value:
    case D.MissingField{segments}: "missing:" ++ path(segments)
    case D.WrongType{segments, expected}: "type:" ++ path(segments) ++ ":" ++ expected
    case D.InvalidValue{segments, expected}: "value:" ++ path(segments) ++ ":" ++ expected

def equal(value: V.Value, expected: Result<&2, &2, Parse.Error, V.Value>) -> Bool:
  match expected:
    case Fail{_}: False{}
    case Done{expected}: V.equal(value, expected)

def check(result: Result<&2, &2, D.Error, V.Value>, expected: String) -> String:
  match result:
    case Done{value}: Bool.pick(String, equal(value, Parse.parse(expected)), "pass", "FAIL value")
    case Fail{+cause}: Bool.pick(String, String.eq(error(cause), expected), "pass", "FAIL " ++ error(cause))

def parsed(mode: String, result: Result<&2, &2, Parse.Error, V.Value>, expected: String) -> String:
  match result:
    case Fail{_}: "FAIL input JSON"
    case Done{value}: check(decode(mode, value), expected)

def text(value: String) -> String:
  H.fromScalars(H.parseNumbers(value))

def execute(parts: List<&2, String>) -> String:
  match parts:
    case mode <> source <> expected <> Nil{}: parsed(mode, Parse.parse(text(source)), text(expected))
    case _: "FAIL arguments"

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
