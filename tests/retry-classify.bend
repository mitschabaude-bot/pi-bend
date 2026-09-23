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

# Classifies one assistant message per JSON line of the cases file (retryable
# error, context overflow, recoverable length stop, agent retry delay) so
# tests/retry_classify_check.py can compare against upstream's classifiers.

type Case is Data:
  Case{errorMessage: Maybe<&2, String>, stopReason: Ai.StopReason, input: F64, cacheRead: F64, output: F64, contextWindow: F64, desiredMaxOutput: F64, baseDelayMs: F64, maxAgentDelayMs: Maybe<&2, F64>, attempt: Nat}

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
    return Case{errorMessage, stopReasonOf(stopReason), input, cacheRead, output, contextWindow, desiredMaxOutput, baseDelayMs, maxAgentDelayMs, attempt}

def message(errorMessage: Maybe<&2, String>, stopReason: Ai.StopReason, +input: F64, +cacheRead: F64, +output: F64) -> Ai.AssistantMessage<V.Value, Unit>:
  Ai.AssistantMessage{Nil{}, "openai-completions", "faux", "faux-model", None{}, None{}, None{}, None{}, Ai.Usage{input, output, cacheRead, F.fromU32(0), None{}, None{}, F.add(F.add(input, cacheRead), output), Ai.UsageCost{F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0), F.fromU32(0)}}, stopReason, None{}, errorMessage, None{}, None{}, F.fromU32(0)}

def flag(value: Bool) -> String: Bool.pick(String, value, "true", "false")

def classified(value: Case) -> String:
  match value:
    case Case{errorMessage, stopReason, input, cacheRead, output, contextWindow, desiredMaxOutput, baseDelayMs, maxAgentDelayMs, attempt}:
      +assistant = message(errorMessage, stopReason, input, cacheRead, output)
      "{\"retryable\":" ++ flag(Retry.isRetryableAssistantError(V.Value, Unit, assistant)) ++ ",\"overflow\":" ++ flag(Overflow.isContextOverflow(V.Value, Unit, assistant, contextWindow)) ++ ",\"recoverable\":" ++ flag(Overflow.isRecoverableLength(V.Value, Unit, assistant, desiredMaxOutput)) ++ ",\"delayMs\":" ++ Maybe.default(&2, String, F.toJsonNumber(Retry.retryDelayMs(baseDelayMs, maxAgentDelayMs, attempt)), "null") ++ "}"

def answer(parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> String:
  match parsed:
    case Fail{_}: "{\"error\":\"unparsable case\"}"
    case Done{value}: Result.default(&2, &2, Decode.Error, String, Result.map(&2, &2, Decode.Error, Case, String, classified, decodeCase(value)), "{\"error\":\"undecodable case\"}")

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
