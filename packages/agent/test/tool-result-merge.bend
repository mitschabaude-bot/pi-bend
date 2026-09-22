import Base
import ../src/agent-loop.bend as Loop
import ../src/types.bend as T
import ../../ai/src/types.bend as Ai
import ../../ai/test/model-cost.bend as Cost
import ../../runtime/src/f64.bend as N
import ../../runtime/src/schema-value.bend as Schema

type Payload is Data:
  NullPayload{}
  FalsePayload{}
  ZeroPayload{}
  TextPayload{text: String}
  ObjectPayload{reference: String}

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def nullish(payload: Payload) -> Bool:
  match payload:
    case NullPayload{}: True{}
    case _: False{}

def details(index: U32, object: String) -> Maybe<&2, Payload>:
  match index:
    case 0: None{}
    case 1: None{}
    case 2: Some{FalsePayload{}}
    case 3: Some{ZeroPayload{}}
    case 4: Some{TextPayload{""}}
    case _: Some{ObjectPayload{object}}

def content(index: U32) -> Maybe<&2, List<&2, Ai.TextImageContent>>:
  match index:
    case 0: None{}
    case 1: Some{Nil{}}
    case _: Some{Ai.TextImageText{Ai.TextContent{"new", None{}}} <> Nil{}}

def terminate(flags: U32) -> Maybe<&2, Bool>:
  match flags:
    case 0: None{}
    case 4: None{}
    case 1: Some{True{}}
    case _: Some{False{}}

def originalTerminate(flags: U32) -> Maybe<&2, Bool>:
  match flags:
    case 0: None{}
    case 3: None{}
    case 2: Some{True{}}
    case 4: Some{True{}}
    case _: Some{False{}}

def error(flags: U32) -> Maybe<&2, Bool>:
  match flags:
    case 0: None{}
    case 4: None{}
    case 2: Some{True{}}
    case _: Some{False{}}

def usage(cost: Ai.UsageCost) -> Ai.Usage:
  +zero = N.fromU32(0)
  Ai.Usage{zero, zero, zero, zero, None{}, None{}, zero, cost}

def optionalUsage(flags: U32, value: Ai.Usage) -> Maybe<&2, Ai.Usage>:
  match flags:
    case 1: Some{value}
    case 3: Some{value}
    case 5: Some{value}
    case _: None{}

def checkDetails(payload: Payload, expected: U32, old: String, fresh: String) -> Bool:
  match payload expected:
    case FalsePayload{} 2: True{}
    case ZeroPayload{} 3: True{}
    case TextPayload{text} 4: String.eq(text, "")
    case ObjectPayload{ref} 5: String.eq(ref, fresh)
    case ObjectPayload{ref} 6: String.eq(ref, old)
    case _ _: False{}

def showContent(values: List<&2, Ai.TextImageContent>) -> String:
  match values:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, _}} <> Nil{}: text
    case _: "unexpected content"

def sameOptional(a: Maybe<&2, Bool>, b: Maybe<&2, Bool>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{True{}} Some{True{}}: True{}
    case Some{False{}} Some{False{}}: True{}
    case _ _: False{}

def sameUsage(value: Maybe<&2, Ai.Usage>, cost: Ai.UsageCost) -> Bool:
  match value:
    case Some{Ai.Usage{_, _, _, _, _, _, _, actual}}: Cost.sameCost(actual, cost)
    case _: False{}

def checkAbsent(original: T.AgentToolResult<Payload>, beforeError: Bool, outcome: Loop.ExecutedToolCallOutcome<Payload>) -> IO(Unit):
  match outcome:
    case Loop.ExecutedToolCallOutcome{result, isError}:
      assertion(sameOptional(Some{beforeError}, Some{isError}), "absent hook result must preserve error flag")

def checkRecord(value: T.AgentToolResult<Payload>, expectedDetails: U32, old: String, fresh: String, expectedContent: String, expectedCost: Ai.UsageCost, expectedTerminate: Maybe<&2, Bool>) -> IO(Unit):
  match value:
    case T.AgentToolResult{contentValue, detailValue, usageValue, terminateValue}:
      assertion(String.eq(showContent(contentValue), expectedContent) && checkDetails(detailValue, expectedDetails, old, fresh) && sameUsage(usageValue, expectedCost) && sameOptional(terminateValue, expectedTerminate), "hook override fields differ from upstream nullish merge")

def unchangedContent(value: T.AgentToolResult<Payload>) -> IO(Unit):
  match value:
    case T.AgentToolResult{contentValue, _, _, _}: assertion(String.eq(showContent(contentValue), "old"), "hook merge mutated the original result")

def checkPatched(+original: T.AgentToolResult<Payload>, outcome: Loop.ExecutedToolCallOutcome<Payload>, expectedDetails: U32, old: String, fresh: String, expectedContent: String, expectedCost: Ai.UsageCost, expectedTerminate: Maybe<&2, Bool>, expectedError: Bool) -> IO(Unit):
  match outcome:
    case Loop.ExecutedToolCallOutcome{+result, isError}:
      do IO<Unit>:
        assertion(sameOptional(Some{isError}, Some{expectedError}), "hook isError override differs from upstream")
        value : T.AgentToolResult<Payload> = result
        checkRecord(value, expectedDetails, old, fresh, expectedContent, expectedCost, expectedTerminate)
        oldValue : T.AgentToolResult<Payload> = original
        unchangedContent(oldValue)
        previous : T.AgentToolResult<Payload> = result
        return Unit{}

def run(contentIndex: U32, detailsIndex: U32, +flags: U32, expectedDetails: U32, expectedContent: String, newUsage: Bool, expectedTerminate: Maybe<&2, Bool>, expectedError: Bool) -> IO(Unit):
  do IO<Unit>:
    +zero : N.F64 = N.fromU32(0)
    +oldCost : Ai.UsageCost = Ai.UsageCost{zero, zero, zero, zero, zero}
    +newCost : Ai.UsageCost = Ai.UsageCost{zero, zero, zero, zero, zero}
    +oldDetails : String <- IO.pure(String, "old")
    +newDetails : String <- IO.pure(String, "new")
    +original : T.AgentToolResult<Payload> = T.AgentToolResult{Ai.TextImageText{Ai.TextContent{"old", None{}}} <> Nil{}, ObjectPayload{oldDetails}, Some{usage(oldCost)}, originalTerminate(flags)}
    +beforeError : Bool = U32.is_eq(flags, 0) || U32.is_eq(flags, 2) || U32.is_eq(flags, 4)
    unchanged : Loop.ExecutedToolCallOutcome<Payload> = Loop.applyAfterToolCallResult(Payload, Loop.ExecutedToolCallOutcome{original, beforeError}, None{})
    checkAbsent(original, beforeError, unchanged)
    patched : Loop.ExecutedToolCallOutcome<Payload> = Loop.applyAfterToolCallResult(Payload, Loop.ExecutedToolCallOutcome{original, beforeError}, Some{T.AfterToolCallResult{content(contentIndex), details(detailsIndex, newDetails), error(flags), optionalUsage(flags, usage(newCost)), terminate(flags)}})
    checkPatched(original, patched, expectedDetails, oldDetails, newDetails, expectedContent, Bool.pick(Ai.UsageCost, newUsage, newCost, oldCost), expectedTerminate, expectedError)
    oldResult : T.AgentToolResult<Payload> = original
    old : String <- IO.pure(String, oldDetails)
    fresh : String <- IO.pure(String, newDetails)
    cost1 : Ai.UsageCost = oldCost
    cost2 : Ai.UsageCost = newCost
    return Unit{}
