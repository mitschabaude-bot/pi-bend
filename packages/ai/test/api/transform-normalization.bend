import Base
import ../../src/api/transform-messages.bend as Transform
import ../../src/api/transform-tool-results.bend as Repair
import ../../src/types.bend as Ai
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/f64.bend as F
import ../../../runtime/test/schema.bend as T
import ./transform-tool-results.bend as Fixture

def Messages() -> Data: Repair.Messages(Unit, String, Unit, String)
def Input() -> Data: Transform.NormalizeToolCallIdInput<String, Unit, Unit>
def Output() -> Data: Result<&2, &2, String, String>
type Capture is Data:
  Capture{count: R.Ref<U32>, trace: R.Ref<String>, mode: U32}
def optional(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "-"
    case Some{text}: "=" ++ text

def blocks(content: List<&2, Ai.AssistantContent<String>>) -> String:
  match content:
    case Nil{}: ""
    case Ai.AssistantText{Ai.TextContent{text, signature}} <> rest: "t:" ++ text ++ ":" ++ optional(signature) ++ ";" ++ blocks(rest)
    case Ai.AssistantToolCall{Ai.ToolCall{id, name, args, signature, namespace}} <> rest: "c:" ++ id ++ ":" ++ name ++ ":" ++ args ++ ":" ++ optional(signature) ++ ":" ++ optional(namespace) ++ ";" ++ blocks(rest)
    case Ai.AssistantThinking{Ai.ThinkingContent{text, signature, _}} <> rest: "h:" ++ text ++ ":" ++ optional(signature) ++ ";" ++ blocks(rest)
def textBlocks(content: List<&2, Ai.TextImageContent>) -> String:
  match content:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text, signature}} <> rest: "t:" ++ text ++ ":" ++ optional(signature) ++ ";" ++ textBlocks(rest)
    case Ai.TextImageImage{Ai.ImageContent{data, mime}} <> rest: "i:" ++ data ++ ":" ++ mime ++ ";" ++ textBlocks(rest)
def userContent(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{content}: textBlocks(content)
def describe(messages: Messages()) -> String:
  match messages:
    case Nil{}: ""
    case Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}} <> rest: "a[" ++ blocks(content) ++ "]" ++ describe(rest)
    case Ai.ToolResult{Ai.ToolResultMessage{id, name, content, details, _, error, _}} <> rest: "r[" ++ id ++ ":" ++ name ++ ":" ++ Bool.pick(String, error, "error", "ok") ++ ":" ++ optional(details) ++ ":" ++ textBlocks(content) ++ "]" ++ describe(rest)
    case Ai.User{Ai.UserMessage{content, _}} <> rest: "u[" ++ userContent(content) ++ "]" ++ describe(rest)
    case Ai.System{_} <> rest: "s" ++ describe(rest)
def images() -> List<&2, Ai.TextImageContent>:
  Ai.TextImageImage{Ai.ImageContent{"data", "image/png"}} <> Ai.TextImageImage{Ai.ImageContent{"data", "image/png"}} <> Ai.TextImageText{Ai.TextContent{"between", Some{"image-text"}}} <> Ai.TextImageImage{Ai.ImageContent{"data", "image/png"}} <> Nil{}
def fixtureMessage(tag: String) -> Ai.Message<Unit, String, Unit, String>:
  match tag:
    case "i": Ai.User{Ai.UserMessage{Ai.UserBlocks{images()}, F.fromU32(1)}}
    case "ri": Ai.ToolResult{Ai.ToolResultMessage{"1", "tool-1", images(), Some{"images"}, None{}, False{}, F.fromU32(2)}}
    case other: Fixture.fixtureMessage(other)
def inputMessages(tags: List<&2, String>) -> Messages():
  match tags:
    case Nil{}: Nil{}
    case tag <> rest: fixtureMessage(tag) <> inputMessages(rest)
def target(same: Bool) -> Ai.Model<Unit>:
  +zero = F.fromU32(0)
  Ai.Model{Bool.pick(String, same, "test", "foreign"), "Test", Ai.OpenAIResponsesApi{}, "test-provider", "https://example.test", True{}, None{}, Ai.InputText{} <> Nil{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, F.fromU32(128000), F.fromU32(4096), None{}, None{}, None{}}
def firstText(content: List<&2, Ai.AssistantContent<String>>) -> String:
  match content:
    case Ai.AssistantText{Ai.TextContent{text, signature}} <> _:
      Bool.pick(String, String.eq(optional(signature), "=text-signature"), text, "INVALID")
    case _: "INVALID"
def sourceTag(source: Ai.AssistantMessage<String, Unit>) -> String:
  match source:
    case Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: firstText(content)
def targetId(model: Ai.Model<Unit>) -> String:
  match model:
    case Ai.Model{id, _, _, _, _, _, _, _, _, _, _, _, _, _}: id

def increment(+old: U32) -> U32 & U32: (U32.add(old, 1), old)
def decision(mode: U32, index: U32, +id: String) -> Output():
  match mode:
    case 1: Done{id}
    case 2: Done{Bool.pick(String, U32.is_eq(index, 0), "n-" ++ id, id)}
    case 3: Done{""}
    case 4: Bool.pick(Output(), U32.is_eq(index, 1), Fail{"normalization failed"}, Done{"n-" ++ id})
    case _: Done{"n-" ++ id}
def normalizeBody(capture: Capture, input: Input()) -> IO(Output()):
  match capture input:
    case Capture{count, trace, mode} Transform.NormalizeToolCallIdInput{+id, model, source}:
      do IO<Output()>:
        index : U32 <- R.modify(U32, U32, count, old => increment(old))
        +tag : String = sourceTag(source)
        T.assertion(String.eq(targetId(model), "foreign") && Bool.not(String.eq(tag, "INVALID")), "callback sees original assistant and target model")
        R.modify(String, Unit, trace, old => (old ++ id ++ "@" ++ tag ++ ";", Unit{}))
        return decision(mode, index, id)
def clock(unused: Unit) -> IO(F64): IO.pure(F64, F.fromU32(1000))
def forbiddenClock(unused: Unit) -> IO(F64): IO.die(F64, 1, "failed normalization must not begin repair")
def invoke(failure: Bool, messages: Messages(), model: Ai.Model<Unit>, callback: Maybe<&2, Transform.Normalizer(String, Unit, Unit, String)>) -> IO(Result<&2, &2, String, Messages()>):
  match failure:
    case True{}: Transform.transformMessagesWith(~Unit, ~String, ~Unit, ~String, ~Unit, ~String, ~forbiddenClock, messages, model, callback)
    case False{}: Transform.transformMessagesWith(~Unit, ~String, ~Unit, ~String, ~Unit, ~String, ~clock, messages, model, callback)
def checkResult(result: Result<&2, &2, String, Messages()>, expected: String, failure: Bool, label: String) -> IO(Unit):
  match result:
    case Fail{error}: T.assertion(failure && String.eq(error, "normalization failed"), label)
    case Done{messages}: T.assertion(Bool.not(failure) && String.eq(describe(messages), expected), label)
def check(+mode: U32, same: Bool, enabled: Bool, tags: List<&2, String>, expected: String, expectedTrace: String, +label: String) -> IO(Unit):
  do IO<Unit>:
    +count : R.Ref<U32> <- R.new(U32, 0)
    +trace : R.Ref<String> <- R.new(String, "")
    +normalizer : Transform.Normalizer(String, Unit, Unit, String) <- C.create(~Capture, ~Input(), ~Output(), ~normalizeBody, Capture{count, trace, mode})
    +failure : Bool = U32.is_eq(mode, 4)
    result : Result<&2, &2, String, Messages()> <- invoke(failure, inputMessages(tags), target(same), Bool.pick(Maybe<&2, Transform.Normalizer(String, Unit, Unit, String)>, enabled, Some{normalizer}, None{}))
    checkResult(result, expected, failure, label)
    actual : String <- R.read(String, trace)
    T.assertion(String.eq(actual, expectedTrace), "normalizer invocation order: " ++ label)
    # Callback ownership stays with the caller after either success or failure.
    probe : Output() <- C.call(Input(), Output(), normalizer, Transform.NormalizeToolCallIdInput{"probe", target(False{}), Fixture.assistant("a0")})
    C.dispose(Input(), Output(), normalizer)
    old : U32 <- R.dispose(U32, count)
    old : String <- R.dispose(String, trace)
    return Unit{}
