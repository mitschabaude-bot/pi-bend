import Base
import ../src/api/anthropic-messages-stream.bend as Fold
import ../src/api/transform-messages.bend as Transform
import ../src/providers/anthropic.models.bend as Catalog
import ../src/providers/openrouter.models.bend as OpenRouter
import ../src/types.bend as T
import ../src/utils/diagnostics.bend as Diagnostics
import ../src/utils/transcript.bend as Transcript
import ./anthropic-harness.bend as H
import ./anthropic-sse-bodies.bend as Bodies
import ../../runtime/src/callback.bend as C
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/anthropic-sse-parsing.test.ts. The
# injected `client` returns the suite's SSE bodies through the real stream.
def respond(+model: T.Model<T.JsonValue>, +context: H.Context(), options: H.Options(), body: String) -> IO(H.Outcome):
  H.run(model, context, options, H.Respond{body <> Nil{}})

def plain() -> H.Options(): H.direct(H.streamOptions(None{}, None{}, None{}), None{}, None{})

def messagesOf(context: H.Context()) -> List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>:
  match context:
    case T.TranscriptContext{messages}: messages

def replayed(messages: List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>) -> Maybe<&2, T.AssistantMessage<V.Value, H.Diagnostics()>>:
  match messages:
    case Nil{}: None{}
    case T.Assistant{message} <> _: Some{message}
    case _ <> rest: replayed(rest)

def replayedContent(result: Result<&2, &2, Unit, List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>>) -> Maybe<&2, T.JsonValue>:
  match result:
    case Done{messages}: Maybe.bind(&2, T.AssistantMessage<V.Value, H.Diagnostics()>, T.JsonValue, replayed(messages), message => H.contentJson(H.Diagnostics(), message))
    case Fail{_}: None{}

def relabeled() -> IO(Unit):
  +name = {"keeps signed thinking replayable when a proxy relabels the model" : String}
  +model = Catalog.model_claude_opus_5()
  +initial = H.hello()
  do IO<Unit>:
    first : H.Outcome <- respond(model, initial, plain(), Bodies.relabel())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(first))
    H.equalText(Some{H.modelOf(message)}, Some{"claude-opus-5"}, name ++ ": model")
    H.equalText(H.responseModel(message), Some{"kimi-for-coding"}, name ++ ": responseModel")
    transformed : Result<&2, &2, Unit, List<&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>>> <- Transform.transformMessages(~V.Value, ~V.Value, ~H.Diagnostics(), ~Unit, ~T.JsonValue, ~Unit, List.append(&2, T.Message<V.Value, V.Value, H.Diagnostics(), Unit>, messagesOf(initial), T.Assistant{message} <> Nil{}), model, None{})
    H.equalJson(replayedContent(transformed), "[{\"type\":\"thinking\",\"thinking\":\"reasoning\",\"thinkingSignature\":\"signature\"}]", name)
    H.pass(name)

def fallbackCompat() -> T.AnthropicMessagesCompat:
  T.AnthropicMessagesCompat{None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{T.AnthropicAllowedFallbackModel{"anthropic", "fallback-model", T.ModelCost{F.fromU32(3), F.fromU32(5), F.fromU32(0), F.fromU32(0), None{}}} <> Nil{}}}

def costOf(usage: T.Usage) -> T.UsageCost:
  match usage:
    case T.Usage{_, _, _, _, _, _, _, cost}: cost

def costChecked(cost: T.UsageCost, +name: String) -> IO(Unit):
  match cost:
    case T.UsageCost{input, output, _, _, _}:
      do IO<Unit>:
        H.check(H.near(input, F.divide(F.fromU32(3), F.fromU32(10000)), F.divide(F.fromU32(1), F.fromU32(2000000000))), name ++ ": input cost")
        H.check(H.near(output, F.divide(F.fromU32(1), F.fromU32(10000)), F.divide(F.fromU32(1), F.fromU32(2000000000))), name ++ ": output cost")

def fallbackCost() -> IO(Unit):
  +name = {"uses a returned fallback model for cost attribution" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(H.withCompat(Catalog.model_claude_opus_5(), fallbackCompat()), H.hello(), plain(), Bodies.fallbackCost())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalText(Some{H.modelOf(message)}, Some{"claude-opus-5"}, name ++ ": model")
    H.equalText(H.responseModel(message), Some{"fallback-model"}, name ++ ": responseModel")
    costChecked(costOf(H.usageOf(message)), name)
    H.pass(name)

def lateFallback() -> IO(Unit):
  +name = {"fails safely when Anthropic falls back after output begins" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_opus_5(), H.hello(), plain(), Bodies.lateFallback())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "error")
    H.check(H.contains(H.errorMessage(message), "unsupported mid-output model fallback"), name ++ ": error message")
    H.pass(name)

def forcedStreaming() -> IO(Unit):
  +name = {"forces streaming after an onPayload replacement" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- H.run(Catalog.model_claude_fable_5_1(), H.hello(), plain(), H.Replace{Bodies.minimal() <> Nil{}})
    H.equalJson(H.fieldOf(H.sentOf(outcome), "stream"), "true", name)
    H.pass(name)

def betas(outcome: H.Outcome) -> List<&2, T.JsonValue>: H.elements(H.fieldOf(H.sentOf(outcome), "betas"))

def interleavedOmitted() -> IO(Unit):
  +name = {"omits the interleaved-thinking beta when thinking is disabled" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(OpenRouter.model_anthropic_claude_3_haiku(), H.hello(), H.direct(H.streamOptions(None{}, None{}, None{}), Some{False{}}, None{}), Bodies.minimal())
    H.check(Maybe.is_some(&2, T.JsonValue, H.sentOf(outcome)), name ++ ": request sent")
    H.check(Bool.not(H.containsString(betas(outcome), "interleaved-thinking-2025-05-14")), name)
    H.pass(name)

def managedBetas() -> IO(Unit):
  +name = {"passes managed beta features to injected clients" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_fable_5_1(), H.hello(), plain(), Bodies.minimal())
    H.equalStop(H.messageOf(outcome), "stop")
    H.check(H.containsString(betas(outcome), "mid-conversation-output-config-2026-07-01"), name ++ ": output config beta")
    H.check(H.containsString(betas(outcome), "thinking-binding-controls-2026-08-01"), name ++ ": binding beta")
    H.pass(name)

def transformationText(value: Maybe<&2, String>) -> String: Maybe.default(&2, String, value, "(undefined)")

def sameTransformation(value: Fold.InputTransformation, kind: String, path: String, reason: String) -> Bool:
  match value:
    case Fold.InputTransformation{Some{a}, Some{b}, Some{c}}: String.eq(a, kind) && String.eq(b, path) && String.eq(c, reason)
    case _: False{}

def finalTransformations(diagnostics: Maybe<&2, List<&2, Diagnostics.AssistantMessageDiagnostic<H.Diagnostics()>>>) -> Bool:
  match diagnostics:
    case Some{Diagnostics.AssistantMessageDiagnostic{"anthropic_input_transformations", _, None{}, Some{value <> Nil{}}} <> Nil{}}: sameTransformation(value, "thinking_dropped", "messages.3.content.0", "model_binding_mismatch")
    case _: False{}

def transformations() -> IO(Unit):
  +name = {"uses the serving model input transformations from the final stream event" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_fable_5_1(), H.hello(), plain(), Bodies.transformations())
    H.check(finalTransformations(H.diagnosticsOf(H.messageOf(outcome))), name)
    H.pass(name)

def editTool() -> T.Tool<V.Value>:
  T.Tool{"edit", "Edit a file.", V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{R.Property{"path", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> R.Property{"text", V.ObjectValue{R.Record{R.Property{"type", V.Text{"string"}} <> Nil{}}}} <> Nil{}}}} <> R.Property{"required", V.ArrayValue{V.Text{"path"} <> V.Text{"text"} <> Nil{}}} <> Nil{}}}, None{}}

def toolArguments(content: Maybe<&2, T.JsonValue>) -> Maybe<&2, T.JsonValue>:
  H.fieldOf(H.findString(H.elements(content), "type", "toolCall"), "arguments")

def repaired() -> IO(Unit):
  +name = {"repairs malformed SSE JSON and malformed streamed tool JSON" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_haiku_4_5(), H.contextWith(None{}, H.user("Use the edit tool.", 1) <> Nil{}, Some{editTool() <> Nil{}}), plain(), Bodies.malformed())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "toolUse")
    H.equalText(H.errorMessage(message), None{}, name ++ ": errorMessage")
    H.equalJson(toolArguments(H.contentJson(H.Diagnostics(), message)), "{\"path\":\"A\\\\H\",\"text\":\"col1\\tcol2\"}", name)
    H.pass(name)

def initialContent() -> IO(Unit):
  +name = {"preserves content from content_block_start events" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_haiku_4_5(), H.context(H.user("Say hello.", 1) <> Nil{}), plain(), Bodies.initialContent())
    H.equalJson(H.contentJson(H.Diagnostics(), H.messageOf(outcome)), "[{\"type\":\"text\",\"text\":\"Initial text plus delta\"},{\"type\":\"thinking\",\"thinking\":\"Initial thinking plus delta\",\"thinkingSignature\":\"initial signature plus delta\"}]", name)
    H.pass(name)

def refusal() -> IO(Unit):
  +name = {"preserves refusal stop details from message_delta" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_fable_5(), H.context(H.user("blocked request", 1) <> Nil{}), plain(), Bodies.refusal())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "error")
    H.equalText(H.rawStopReason(message), Some{"refusal"}, name ++ ": rawStopReason")
    H.equalText(H.errorMessage(message), Some{Bodies.explanation()}, name ++ ": errorMessage")
    H.pass(name)

def sensitive() -> IO(Unit):
  +name = {"preserves sensitive stop reasons with a descriptive error message" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_haiku_4_5(), H.context(H.user("blocked request", 1) <> Nil{}), plain(), Bodies.sensitive())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "error")
    H.equalText(H.rawStopReason(message), Some{"sensitive"}, name ++ ": rawStopReason")
    H.equalText(H.errorMessage(message), Some{"Provider stopped with: sensitive"}, name ++ ": errorMessage")
    H.pass(name)

def usageChecked(usage: T.Usage, +name: String) -> IO(Unit):
  match usage:
    case T.Usage{input, _, _, _, _, _, total, _}:
      do IO<Unit>:
        H.equalNumber(input, F.fromU32(12), name ++ ": usage.input")
        H.equalNumber(total, F.fromU32(12), name ++ ": usage.totalTokens")

def noUsage() -> IO(Unit):
  +name = {"treats message_delta without usage as a no-op for usage accumulation" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_haiku_4_5(), H.context(H.user("Say hello.", 1) <> Nil{}), plain(), Bodies.noUsage())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "stop")
    H.equalText(H.errorMessage(message), None{}, name ++ ": errorMessage")
    H.equalJson(H.contentJson(H.Diagnostics(), message), "[{\"type\":\"text\",\"text\":\"Hello\"}]", name)
    usageChecked(H.usageOf(message), name)
    H.pass(name)

def afterStop() -> IO(Unit):
  +name = {"ignores unknown SSE events after message_stop" : String}
  do IO<Unit>:
    +outcome : H.Outcome <- respond(Catalog.model_claude_haiku_4_5(), H.context(H.user("Say hello.", 1) <> Nil{}), plain(), Bodies.afterStop())
    +message : H.Message() <- IO.pure(H.Message(), H.messageOf(outcome))
    H.equalStop(message, "stop")
    H.equalText(H.errorMessage(message), None{}, name ++ ": errorMessage")
    H.equalJson(H.contentJson(H.Diagnostics(), message), "[{\"type\":\"text\",\"text\":\"Hello\"}]", name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    relabeled()
    fallbackCost()
    lateFallback()
    forcedStreaming()
    interleavedOmitted()
    managedBetas()
    transformations()
    repaired()
    initialContent()
    refusal()
    sensitive()
    noUsage()
    afterStop()
