import Base
import ../src/api/openai-responses-stream.bend as D
import ../src/api/openai-responses-stream-state.bend as S
import ../src/api/openai-responses-stream-content.bend as C
import ../src/api/openai-responses-terminal.bend as Terminal
import ../src/types.bend as T
import ./api/responses-stream.bend as Harness
import ./api/responses-stream-state.bend as State
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as F
import ../../runtime/test/schema.bend as A

# Original source fixtures at 46c9de402. Timestamp is fixed because the tests
# do not inspect wall time. The provider-wrapper case remains unported.
def createModel() -> T.Model<Unit>:
  +zero = F.fromU32(0)
  T.Model{"gpt-5-mini", "GPT-5 Mini", T.OpenAIResponsesApi{}, "openai", "https://api.openai.com/v1", True{}, None{}, T.InputText{} <> Nil{}, T.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(400000), F.fromU32(128000), None{}, None{}, None{}}

def createOutput() -> T.AssistantMessage<V.Value, Unit>:
  +zero = F.fromU32(0)
  T.AssistantMessage{Nil{}, "openai-responses", "openai", "gpt-5-mini", None{}, None{}, None{}, None{}, T.Usage{zero, zero, zero, zero, None{}, None{}, zero, T.UsageCost{zero, zero, zero, zero, zero}}, T.Pending{}, None{}, None{}, None{}, None{}, zero}

def execute(events: List<&2, D.ResponseStreamEvent>) -> IO(Harness.Execution):
  Harness.execute(events, Harness.NoHooks{}, None{}, createOutput(), createModel())

def earlyEvents() -> List<&2, D.ResponseStreamEvent>:
  D.ResponseCreated{"resp_early_eof"} <>
  D.ContentEvent{S.Added{F.fromU32(0), C.ReasoningItem{R.Record{R.Property{"type", V.Text{"reasoning"}} <> R.Property{"id", V.Text{"rs_early_eof"}} <> R.Property{"summary", V.ArrayValue{Nil{}}} <> Nil{}}}}} <>
  D.ContentEvent{S.Changed{F.fromU32(0), C.ThinkingDelta{"partial reasoning before the stream ends"}}} <> Nil{}

def completedEvents() -> List<&2, D.ResponseStreamEvent>:
  D.ResponseCompleted{Terminal.Response{Some{"resp_completed"}, Some{"completed"}, None{}, Nil{}, Some{Terminal.ResponseUsage{Some{F.fromU32(20)}, Some{F.fromU32(7)}, Some{F.fromU32(2)}, Some{F.fromU32(3)}, None{}, Some{F.fromU32(27)}}}, None{}}} <> Nil{}

def incompleteEvents(reason: String) -> List<&2, D.ResponseStreamEvent>:
  D.ResponseIncomplete{Terminal.Response{Some{"resp_incomplete"}, Some{"incomplete"}, Some{reason}, Nil{}, Some{Terminal.ResponseUsage{Some{F.fromU32(30)}, Some{F.fromU32(12)}, Some{F.fromU32(5)}, None{}, None{}, Some{F.fromU32(42)}}}, None{}}} <> Nil{}

def phaseTerminal(incomplete: Bool) -> D.ResponseStreamEvent:
  match incomplete:
    case True{}: D.ResponseIncomplete{Terminal.Response{Some{"resp_phase"}, Some{"incomplete"}, Some{"max_output_tokens"}, Nil{}, None{}, None{}}}
    case False{}: D.ResponseCompleted{Terminal.Response{Some{"resp_phase"}, Some{"completed"}, None{}, Nil{}, None{}, None{}}}

def phaseEvents(first: T.TextSignaturePhase, last: T.TextSignaturePhase, incomplete: Bool) -> List<&2, D.ResponseStreamEvent>:
  D.ContentEvent{S.Added{F.fromU32(0), C.MessageItem{"msg_phase", Some{first}, Nil{}}}} <>
  D.ContentEvent{S.Changed{F.fromU32(0), C.ItemDone{C.MessageItem{"msg_phase", Some{last}, "answer" <> Nil{}}}}} <> phaseTerminal(incomplete) <> Nil{}

def errorIs(execution: Harness.Execution, expected: String) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{_, Some{error}}, _}: String.eq(Harness.errorText(error), expected)
    case _: False{}

def equalComparison(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def sameNumber(value: F.F64, expected: U32) -> Bool:
  equalComparison(F.compare(value, F.fromU32(expected)))

def usageIs(usage: T.Usage, input: U32, output: U32, read: U32, write: U32, total: U32) -> Bool:
  match usage:
    case T.Usage{a, b, c, d, _, _, e, _}: sameNumber(a, input) && sameNumber(b, output) && sameNumber(c, read) && sameNumber(d, write) && sameNumber(e, total)

def optionalIs(value: Maybe<&2, String>, expected: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: String.eq(text, expected)

def completedResult(execution: Harness.Execution) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{T.AssistantMessage{_, _, _, _, _, id, _, _, usage, T.Stop{}, _, _, raw, _, _}, None{}}, _}: optionalIs(id, "resp_completed") && optionalIs(raw, "completed") && usageIs(usage, 15, 7, 2, 3, 27)
    case _: False{}

def lengthResult(execution: Harness.Execution) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{T.AssistantMessage{_, _, _, _, _, id, _, _, usage, T.Length{}, _, _, raw, _, _}, None{}}, _}: optionalIs(id, "resp_incomplete") && optionalIs(raw, "incomplete.max_output_tokens") && usageIs(usage, 25, 12, 5, 0, 42)
    case _: False{}

def filteredResult(execution: Harness.Execution, +reason: String) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{T.AssistantMessage{_, _, _, _, _, _, _, _, _, T.Error{}, _, error, raw, _, _}, None{}}, _}: optionalIs(raw, "incomplete." ++ reason) && optionalIs(error, "Response incomplete: " ++ reason)
    case _: False{}

def failedResult(execution: Harness.Execution) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{T.AssistantMessage{_, _, _, _, _, _, _, _, _, _, _, _, raw, _, _}, Some{error}}, _}: String.eq(Harness.errorText(error), "server_error: boom") && optionalIs(raw, "failed")
    case _: False{}

def field(value: Maybe<&2, V.Value>, key: String) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.ObjectValue{fields}}: R.get(V.Value, fields, key)
    case _: None{}

def prependPhase(value: Maybe<&2, V.Value>, rest: List<&2, String>) -> List<&2, String>:
  match value:
    case Some{V.Text{text}}: text <> rest
    case _: rest

def phases(trace: List<&2, V.Value>) -> List<&2, String>:
  match trace:
    case Nil{}: Nil{}
    case head <> rest: prependPhase(field(field(field(Some{head}, "emit"), "partial"), "stopReason"), phases(rest))

def phaseResult(execution: Harness.Execution, expected: String, finalStop: String) -> Bool:
  match execution:
    case Harness.Execution{D.RunResult{T.AssistantMessage{_, _, _, _, _, _, _, _, _, stop, _, _, _, _, _}, None{}}, Harness.Capture{_, _, _, trace}}:
      String.eq(String.join(phases(List.reverse(&2, V.Value, trace)), ","), expected) && String.eq(State.reason(stop), finalStop)
    case _: False{}

def rejectsEarlyEof() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(earlyEvents())
    A.assertion(errorIs(result, "OpenAI Responses stream ended before a terminal response event"), "early EOF rejection")
    IO.print("PASS rejects streams that end before a terminal response event")

def tracksPhases() -> IO(Unit):
  do IO<Unit>:
    commentary : Harness.Execution <- execute(phaseEvents(T.Commentary{}, T.Commentary{}, False{}))
    A.assertion(phaseResult(commentary, "pending,pending", "stop"), "commentary/commentary phases")
    final : Harness.Execution <- execute(phaseEvents(T.FinalAnswer{}, T.FinalAnswer{}, False{}))
    A.assertion(phaseResult(final, "stop,stop", "stop"), "final_answer/final_answer phases")
    transition : Harness.Execution <- execute(phaseEvents(T.Commentary{}, T.FinalAnswer{}, False{}))
    A.assertion(phaseResult(transition, "pending,stop", "stop"), "commentary/final_answer phases")
    IO.print("PASS tracks message phases $phases (all three rows)")

def replacesProvisionalStop() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(phaseEvents(T.FinalAnswer{}, T.FinalAnswer{}, True{}))
    A.assertion(phaseResult(result, "stop,stop", "length"), "terminal reason overrides provisional stop")
    IO.print("PASS replaces a provisional final-answer stop with an incomplete terminal reason")

def completed() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(completedEvents())
    A.assertion(completedResult(result), "completed response ID, raw reason and usage")
    IO.print("PASS finalizes completed terminal events as stop")

def incomplete() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(incompleteEvents("max_output_tokens"))
    A.assertion(lengthResult(result), "incomplete response ID, raw reason and usage")
    IO.print("PASS finalizes incomplete terminal events as length stops")

def filtered() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(incompleteEvents("content_filter"))
    A.assertion(filteredResult(result, "content_filter"), "content-filtered response")
    IO.print("PASS finalizes content-filtered incomplete responses as non-retryable errors")

def unknownReason() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(incompleteEvents("max_time_limit"))
    A.assertion(filteredResult(result, "max_time_limit"), "unknown incomplete reason")
    IO.print("PASS preserves unknown provider incomplete reasons as non-retryable errors")

def failed() -> IO(Unit):
  do IO<Unit>:
    result : Harness.Execution <- execute(D.ResponseFailed{Some{"failed"}, Some{Terminal.ProviderError{Some{"server_error"}, Some{"boom"}}}, None{}} <> Nil{})
    A.assertion(failedResult(result), "failed response provider error and raw status")
    IO.print("PASS rejects failed terminal events with the provider error")

def run() -> IO(Unit):
  do IO<Unit>:
    rejectsEarlyEof()
    tracksPhases()
    replacesProvisionalStop()
    completed()
    incomplete()
    filtered()
    unknownReason()
    failed()
