import Base
import ../../src/api/transform-tool-results.bend as Repair
import ../../src/types.bend as Ai
import ../../src/utils/diagnostics.bend as Diagnostics
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/u64.bend as W
import ../../../runtime/test/schema.bend as T
import ./transform-replay.bend as Replay
import ./transform-images.bend as Images

def Messages() -> Data: Repair.Messages(Unit, String, Unit, String)
def call(+id: String) -> Ai.AssistantContent<String>:
  Ai.AssistantToolCall{Ai.ToolCall{id, "tool-" ++ id, "args", Some{"thought"}, Some{"ns"}}}
def calls(tag: String) -> List<&2, Ai.AssistantContent<String>>:
  match tag:
    case "a1": call("1") <> Nil{}
    case "a2": call("2") <> Nil{}
    case "a12": call("1") <> call("2") <> Nil{}
    case "a11": call("1") <> call("1") <> Nil{}
    case "error": call("1") <> Nil{}
    case "aborted": call("2") <> Nil{}
    case _: Nil{}
def assistantContent(+tag: String) -> List<&2, Ai.AssistantContent<String>>:
  Ai.AssistantText{Ai.TextContent{tag, Some{"text-signature"}}} <> calls(tag)
def reason(tag: String) -> Ai.StopReason:
  match tag:
    case "error": Ai.Error{}
    case "aborted": Ai.Aborted{}
    case _: Ai.Stop{}
def assistant(+tag: String) -> Ai.AssistantMessage<String, Unit>:
  +zero = F.fromU32(0)
  Ai.AssistantMessage{assistantContent(tag), "openai-responses", "test-provider", "test", Some{"response-model"}, Some{"response-id"}, Some{"high"}, None{}, Ai.Usage{zero, zero, zero, zero, None{}, None{}, F.fromU32(42), Ai.UsageCost{zero, zero, zero, zero, zero}}, reason(tag), None{}, Some{"metadata"}, Some{"raw"}, Some{False{}}, F.fromU32(17)}
def originalResult(+id: String) -> Ai.Message<Unit, String, Unit, String>:
  Ai.ToolResult{Ai.ToolResultMessage{id, "tool-" ++ id, Ai.TextImageText{Ai.TextContent{"ok", Some{"result-signature"}}} <> Nil{}, Some{"original"}, None{}, False{}, F.fromU32(44)}}
def fixtureMessage(tag: String) -> Ai.Message<Unit, String, Unit, String>:
  match tag:
    case "u": Ai.User{Ai.UserMessage{Ai.UserText{"user"}, F.fromU32(43)}}
    case "s": Ai.System{Ai.SystemMessage{Ai.SystemText{"system"}, None{}, None{}, None{}, F.fromU32(45)}}
    case "r1": originalResult("1")
    case "r2": originalResult("2")
    case "rx": originalResult("x")
    case other: Ai.Assistant{assistant(other)}
def messages(tags: List<&2, String>) -> Messages():
  match tags:
    case Nil{}: Nil{}
    case tag <> rest: fixtureMessage(tag) <> messages(rest)
def time(value: F64, expected: U32) -> Bool:
  W.equal(F.toBits(value), F.toBits(F.fromU32(expected)))
def validTag(ok: Bool, tag: String) -> String: Bool.pick(String, ok, tag, "INVALID")
def none(-A: Data, value: Maybe<&2, A>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}
def stopped(value: Ai.StopReason) -> Bool:
  match value:
    case Ai.Stop{}: True{}
    case _: False{}
def usageOk(usage: Ai.Usage) -> Bool:
  match usage:
    case Ai.Usage{_, _, _, _, h, r, total, _}: none(F64, h) && none(F64, r) && time(total, 42)
def contentTag(content: List<&2, Ai.AssistantContent<String>>) -> String:
  match content:
    case Ai.AssistantText{Ai.TextContent{+tag, signature}} <> rest:
      validTag(Images.sameOptional(signature, Some{"text-signature"}) && Replay.sameContent(rest, calls(tag)), tag)
    case _: "INVALID"
def assistantTag(source: Ai.AssistantMessage<String, Unit>) -> String:
  match source:
    case Ai.AssistantMessage{content, api, provider, model, responseModel, responseId, thinkingLevel, diagnostics, usage, stop, deferred, error, raw, endTurn, timestamp}:
      validTag(String.eq(api, "openai-responses") && String.eq(provider, "test-provider") && String.eq(model, "test") && Images.sameOptional(responseModel, Some{"response-model"}) && Images.sameOptional(responseId, Some{"response-id"}) && Images.sameOptional(thinkingLevel, Some{"high"}) && none(List<&2, Diagnostics.AssistantMessageDiagnostic<Unit>>, diagnostics) && none(Ai.DeferredHandle, deferred) && usageOk(usage) && stopped(stop) && Images.sameOptional(error, Some{"metadata"}) && Images.sameOptional(raw, Some{"raw"}) && Replay.sameBool(endTurn, Some{False{}}) && time(timestamp, 17), contentTag(content))
def userTag(user: Ai.UserMessage) -> String:
  match user:
    case Ai.UserMessage{Ai.UserText{text}, timestamp}: validTag(String.eq(text, "user") && time(timestamp, 43), "u")
    case _: "INVALID"
def systemTag(system: Ai.SystemMessage<Unit>) -> String:
  match system:
    case Ai.SystemMessage{Ai.SystemText{text}, None{}, None{}, None{}, timestamp}: validTag(String.eq(text, "system") && time(timestamp, 45), "s")
    case _: "INVALID"
def resultContent(error: Bool, content: List<&2, Ai.TextImageContent>, details: Maybe<&2, String>, timestamp: F64) -> Bool:
  match error:
    case True{}: Images.sameContent(content, Ai.TextImageText{Ai.TextContent{"No result provided", None{}}} <> Nil{}) && none(String, details) && time(timestamp, 1000)
    case False{}: Images.sameContent(content, Ai.TextImageText{Ai.TextContent{"ok", Some{"result-signature"}}} <> Nil{}) && Images.sameOptional(details, Some{"original"}) && time(timestamp, 44)
def resultTag(result: Ai.ToolResultMessage<String>) -> String:
  match result:
    case Ai.ToolResultMessage{+id, name, content, details, usage, +error, timestamp}:
      validTag(String.eq(name, "tool-" ++ id) && none(Ai.Usage, usage) && resultContent(error, content, details, timestamp), Bool.pick(String, error, "m", "r") ++ id)
def describeMessage(message: Ai.Message<Unit, String, Unit, String>) -> String:
  match message:
    case Ai.User{user}: userTag(user)
    case Ai.System{system}: systemTag(system)
    case Ai.Assistant{source}: assistantTag(source)
    case Ai.ToolResult{result}: resultTag(result)
def describe(messages: Messages()) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: describeMessage(message) <> describe(rest)
def equal(actual: List<&2, String>, expected: List<&2, String>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: String.eq(a, b) && equal(xs, ys)
    case _ _: False{}
def clock(unused: Unit) -> IO(F64): IO.pure(F64, F.fromU32(1000))
def check(input: List<&2, String>, expected: List<&2, String>, label: String) -> IO(Unit):
  do IO<Unit>:
    result : Messages() <- Repair.repairWith(~Unit, ~String, ~Unit, ~String, ~clock, messages(input))
    T.assertion(equal(describe(result), expected), label)
