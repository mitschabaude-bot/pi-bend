import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/retry.bend as Retry
import ../packages/ai/src/utils/overflow.bend as Overflow
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/abort.bend as Abort
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref

# Classifies one assistant message per JSON line of the cases file (retryable
# error, context overflow, recoverable length stop, agent retry delay) so
# tests/retry_classify_check.py can compare against upstream's classifiers.

type Case is Data:
  Case{provider: String, errorMessage: Maybe<&2, String>, stopReason: Ai.StopReason, input: F64, cacheRead: F64, output: F64, contextWindow: F64, desiredMaxOutput: F64, baseDelayMs: F64, maxAgentDelayMs: Maybe<&2, F64>, attempt: Nat}

def stopReasonOf(name: String) -> Ai.StopReason:
  match name:
    case "error": Ai.Error{}
    case "length": Ai.Length{}
    case "toolUse": Ai.ToolUse{}
    case "aborted": Ai.Aborted{}
    case _: Ai.Stop{}

def nullable(value: V.Value) -> Result<&2, &2, Decode.Error, Maybe<&2, String>>:
  match value:
    case V.Null{}: Done{None{}}
    case other: Result.map(&2, &2, Decode.Error, String, Maybe<&2, String>, text => Some{text}, Decode.string(other))

def nullableNumber(value: V.Value) -> Result<&2, &2, Decode.Error, Maybe<&2, F64>>:
  match value:
    case V.Null{}: Done{None{}}
    case other: Result.map(&2, &2, Decode.Error, F64, Maybe<&2, F64>, number => Some{number}, Decode.number(other))

def natural(value: V.Value) -> Result<&2, &2, Decode.Error, Nat>:
  do Result<&2, &2, Decode.Error, Nat>:
    number : F64 <- Decode.number(value)
    return Result.default(&2, &2, F.Error, Nat, F.convert(number), 0n)

def decodeCase(value: V.Value) -> Result<&2, &2, Decode.Error, Case>:
  do Result<&2, &2, Decode.Error, Case>:
    +fields : R.Record<V.Value> <- Decode.object(value)
    provider : String <- Decode.required(String, fields, "provider", Decode.string)
    errorMessage : Maybe<&2, String> <- Decode.required(Maybe<&2, String>, fields, "errorMessage", nullable)
    stopReason : String <- Decode.required(String, fields, "stopReason", Decode.string)
    input : F64 <- Decode.required(F64, fields, "input", Decode.number)
    cacheRead : F64 <- Decode.required(F64, fields, "cacheRead", Decode.number)
    output : F64 <- Decode.required(F64, fields, "output", Decode.number)
    contextWindow : F64 <- Decode.required(F64, fields, "contextWindow", Decode.number)
    desiredMaxOutput : F64 <- Decode.required(F64, fields, "desiredMaxOutput", Decode.number)
    baseDelayMs : F64 <- Decode.required(F64, fields, "baseDelayMs", Decode.number)
    maxAgentDelayMs : Maybe<&2, F64> <- Decode.required(Maybe<&2, F64>, fields, "maxAgentDelayMs", nullableNumber)
    attempt : Nat <- Decode.required(Nat, fields, "attempt", natural)
    return Case{provider, errorMessage, stopReasonOf(stopReason), input, cacheRead, output, contextWindow, desiredMaxOutput, baseDelayMs, maxAgentDelayMs, attempt}

def message(provider: String, errorMessage: Maybe<&2, String>, stopReason: Ai.StopReason, +input: F64, +cacheRead: F64, +output: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{Nil{}, "openai-completions", provider, "faux-model", None{}, None{}, None{}, None{}, Ai.Usage{input, output, cacheRead, F.fromU32(0), None{}, None{}, F.add(F.add(input, cacheRead), output), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, stopReason, None{}, errorMessage, None{}, None{}, F.fromU32(0)}

def flag(value: Bool) -> String: Bool.pick(String, value, "true", "false")

def classified(value: Case) -> String:
  match value:
    case Case{provider, errorMessage, stopReason, input, cacheRead, output, contextWindow, desiredMaxOutput, baseDelayMs, maxAgentDelayMs, attempt}:
      +assistant = message(provider, errorMessage, stopReason, input, cacheRead, output)
      "{\"retryable\":" ++ flag(Retry.isRetryableAssistantError(V.Value, Unit, assistant)) ++ ",\"overflow\":" ++ flag(Overflow.isContextOverflow(V.Value, Unit, assistant, contextWindow)) ++ ",\"recoverable\":" ++ flag(Overflow.isRecoverableLength(V.Value, Unit, assistant, desiredMaxOutput)) ++ ",\"delayMs\":" ++ Maybe.default(&2, String, F.toJsonNumber(Retry.retryDelayMs(baseDelayMs, maxAgentDelayMs, attempt)), "null") ++ "}"

def answer(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> String:
  match parsed:
    case Fail{_}: "{\"error\":\"unparsable case\"}"
    case Done{value}: Result.default(&2, &2, Decode.Error, String, Result.map(&2, &2, Decode.Error, Case, String, classified, decodeCase(value)), "{\"error\":\"undecodable case\"}")

# retryAssistantCall named contracts
# ----------------------------------

def RetryMessage() -> Data: Ai.AssistantMessage<V.Value, Unit>

def retryMessage(+text: String, stopReason: Ai.StopReason, errorMessage: Maybe<&2, String>) -> RetryMessage():
  Ai.AssistantMessage{Bool.pick(List<&2, Ai.AssistantContent<V.Value>>, String.is_empty(text), Nil{}, [Ai.AssistantText{Ai.TextContent{text, None{}}}]), "faux", "faux", "faux-1", None{}, None{}, None{}, None{}, Ai.Usage{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), None{}, None{}, F.fromU32(0), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, stopReason, None{}, errorMessage, None{}, None{}, F.fromU32(0)}

def ok(text: String) -> RetryMessage(): retryMessage(text, Ai.Stop{}, None{})
def failed(text: String) -> RetryMessage(): retryMessage("", Ai.Error{}, Some{text})
def aborted() -> RetryMessage(): retryMessage("", Ai.Aborted{}, None{})

type Script is Data:
  Script{responses: List<&2, RetryMessage()>, calls: Nat}

def advanced(script: Script) -> Script & RetryMessage():
  match script:
    case Script{response <> rest, calls}: (Script{rest, Nat.add(calls, 1n)}, response)
    case Script{Nil{}, calls}: (Script{Nil{}, Nat.add(calls, 1n)}, failed("script exhausted"))

def produce(script: Ref.Ref<Script>) -> IO(RetryMessage()): Ref.modify(Script, RetryMessage(), script, advanced)

def decimal(value: F64) -> String: Maybe.default(&2, String, F.toJsonNumber(value), "NaN")

def noticeDescription(notice: Retry.RetryNotice) -> String & Bool:
  match notice:
    case Retry.RetryScheduled{attempt, maximum, delay, error}: ("scheduled:" ++ Nat.show(attempt) ++ "/" ++ Nat.show(maximum) ++ ":" ++ decimal(delay) ++ ":" ++ error, True{})
    case Retry.RetryAttemptStart{}: ("attempt-start", False{})
    case Retry.RetryFinished{success, attempt, finalError}: ("finished:" ++ Bool.pick(String, success, "true", "false") ++ ":" ++ Nat.show(attempt) ++ ":" ++ Maybe.default(&2, String, finalError, "-"), False{})

type NoticeLog is Data:
  NoticeLog{entries: Ref.Ref<List<&2, String>>, controller: Abort.AbortController<Unit>, abortBackoff: Bool}

def recordNotice(log: NoticeLog, description: String, scheduled: Bool) -> IO(Unit):
  match log:
    case NoticeLog{entries, controller, abortBackoff}:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit), abortBackoff && scheduled, _ => do IO<Unit>:
          won : Bool <- Abort.abort(Unit, controller, None{})
          return Unit{}, _ => IO.pure(Unit, Unit{}))(Unit{})
        Ref.modify(List<&2, String>, Unit, entries, values => (List.append(&2, String, values, [description]), Unit{}))

def recordedDescription(log: NoticeLog, description: String & Bool) -> IO(Unit):
  match description:
    case (text, scheduled): recordNotice(log, text, scheduled)

def recordedNotice(log: NoticeLog, notice: Retry.RetryNotice) -> IO(Unit): recordedDescription(log, noticeDescription(notice))

type RetryResult is Data:
  RetryResult{message: RetryMessage(), calls: Nat, notices: List<&2, String>}

def finishedRun(message: RetryMessage(), notices: List<&2, String>, state: Script) -> RetryResult:
  match state:
    case Script{_, calls}: RetryResult{message, calls, notices}

def runRetry(responses: List<&2, RetryMessage()>, policy: Retry.RetryPolicy, abortBackoff: Bool) -> IO(RetryResult):
  do IO<RetryResult>:
    +script : Ref.Ref<Script> <- Ref.new(Script, Script{responses, 0n})
    +entries : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    +callback : Retry.RetryCallbacks() <- C.create(~NoticeLog, ~Retry.RetryNotice, ~Unit, ~recordedNotice, NoticeLog{entries, controller, abortBackoff})
    message : RetryMessage() <- Retry.retryAssistantCall(~V.Value, ~Unit, ~Ref.Ref<Script>, ~produce, script, Some{policy}, Some{Abort.signal(Unit, controller)}, Some{callback})
    C.dispose(Retry.RetryNotice, Unit, callback)
    state : Script <- Ref.dispose(Script, script)
    notices : List<&2, String> <- Ref.dispose(List<&2, String>, entries)
    Abort.dispose(Unit, controller)
    return finishedRun(message, notices, state)

def retryStopName(reason: Ai.StopReason) -> String:
  match reason:
    case Ai.Stop{}: "stop"
    case Ai.Aborted{}: "aborted"
    case Ai.Error{}: "error"
    case _: "other"

def retryContent(content: List<&2, Ai.AssistantContent<V.Value>>) -> String:
  match content:
    case Ai.AssistantText{Ai.TextContent{text, _}} <> _: text
    case _: ""

def messageSummary(message: RetryMessage()) -> String:
  match message:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, stopReason, _, errorMessage, _, _, _}:
      retryStopName(stopReason) ++ "|" ++ retryContent(content) ++ "|" ++ Maybe.default(&2, String, errorMessage, "-")

def retrySummary(result: RetryResult) -> String:
  match result:
    case RetryResult{message, calls, notices}: messageSummary(message) ++ "|" ++ Nat.show(calls) ++ "|" ++ String.join(notices, ",")

def checkedRetry(+name: String, responses: List<&2, RetryMessage()>, policy: Retry.RetryPolicy, abortBackoff: Bool, +expected: String) -> IO(Unit):
  do IO<Unit>:
    result : RetryResult <- runRetry(responses, policy, abortBackoff)
    +actual : String <- IO.pure(String, retrySummary(result))
    Bool.pick(Unit -> IO(Unit), String.eq(actual, expected), _ => IO.print("PASS " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name ++ "\n  expected " ++ expected ++ "\n  actual   " ++ actual))(Unit{})

def enabled(maxRetries: Nat, baseDelayMs: U32, cap: Maybe<&2, U32>) -> Retry.RetryPolicy:
  Retry.RetryPolicy{True{}, maxRetries, F.fromU32(baseDelayMs), Maybe.map(&2, U32, F64, F.fromU32, cap)}

def retryNamed() -> IO(Unit):
  do IO<Unit>:
    checkedRetry("returns a successful response immediately without retrying", [ok("ok")], enabled(3n, 0, None{}), False{}, "stop|ok|-|1|")
    checkedRetry("does not retry an aborted message", [aborted()], enabled(3n, 0, None{}), False{}, "aborted||-|1|")
    checkedRetry("does not retry a non-retryable error (quota/billing)", [failed("insufficient_quota")], enabled(3n, 0, None{}), False{}, "error||insufficient_quota|1|")
    checkedRetry("retries a transient error up to maxRetries then returns the final error", [failed("terminated"), failed("terminated"), failed("terminated"), failed("terminated")], enabled(3n, 0, None{}), False{}, "error||terminated|4|scheduled:1/3:0:terminated,attempt-start,scheduled:2/3:0:terminated,attempt-start,scheduled:3/3:0:terminated,attempt-start,finished:false:3:terminated")
    checkedRetry("reports capped retry delays", [failed("terminated"), failed("terminated"), failed("terminated"), failed("terminated"), ok("recovered")], enabled(4n, 10, Some{15}), False{}, "stop|recovered|-|5|scheduled:1/4:10:terminated,attempt-start,scheduled:2/4:15:terminated,attempt-start,scheduled:3/4:15:terminated,attempt-start,scheduled:4/4:15:terminated,attempt-start,finished:true:4:-")
    checkedRetry("stops retrying once a call succeeds", [failed("terminated"), failed("terminated"), ok("recovered")], enabled(3n, 0, None{}), False{}, "stop|recovered|-|3|scheduled:1/3:0:terminated,attempt-start,scheduled:2/3:0:terminated,attempt-start,finished:true:2:-")
    checkedRetry("reports an aborted retried call as unsuccessful", [failed("terminated"), aborted()], enabled(3n, 0, None{}), False{}, "aborted||-|2|scheduled:1/3:0:terminated,attempt-start,finished:false:1:-")
    checkedRetry("does not retry when policy is disabled", [failed("terminated")], Retry.RetryPolicy{False{}, 3n, F.fromU32(0), None{}}, False{}, "error||terminated|1|")
    checkedRetry("emits onRetryAttemptStart after backoff before each retried call", [failed("terminated"), failed("terminated"), ok("recovered")], enabled(3n, 0, None{}), False{}, "stop|recovered|-|3|scheduled:1/3:0:terminated,attempt-start,scheduled:2/3:0:terminated,attempt-start,finished:true:2:-")
    checkedRetry("aborts backoff sleep via signal, returns an aborted message, and emits onRetryFinished(false)", [failed("terminated")], enabled(5n, 10000, None{}), True{}, "aborted||-|1|scheduled:1/5:10000:terminated,finished:false:1:terminated")

def cases(rows: List<&2, String>) -> IO(Unit):
  match rows:
    case Nil{}: IO.pure(Unit, Unit{})
    case +row <> rest:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit), String.is_empty(String.trim(row)), _ => IO.pure(Unit, Unit{}), _ => IO.print(answer(Decode.parse(row))))(Unit{})
        cases(rest)

def scriptText(decoded: Result<&2, &2, Utf8.Error, String>) -> IO(List<&2, String>):
  match decoded:
    case Fail{_}: IO.die(List<&2, String>, 1, "cases file is not UTF-8")
    case Done{text}: IO.pure(List<&2, String>, String.split(text, '\n'))

def scriptBytes(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> IO(List<&2, String>):
  match bytes:
    case Fail{_}: IO.die(List<&2, String>, 1, "could not read the cases file")
    case Done{content}: scriptText(Utf8.decodeWith(Utf8.Preserve{}, content))

def run(args: List<String>) -> IO(Unit):
  match args:
    case "named" <> Nil{}: retryNamed()
    case path <> Nil{}:
      do IO<Unit>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
        rows : List<&2, String> <- scriptBytes(bytes)
        cases(rows)
    case _: IO.die(Unit, 1, "usage: retry-classify <cases.jsonl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
