import Base
import ../src/models.bend as Models
import ../src/providers/github-copilot.models.bend as Copilot
import ../src/types.bend as T
import ../src/utils/thinking-levels.bend as Levels
import ./anthropic-harness.bend as H
import ../../runtime/src/f64.bend as F

# pi-mono f07218c4d packages/ai/test/github-copilot-anthropic.test.ts. upstream
# mocks the Anthropic SDK; natively onPayload captures the params and the
# recording fetch the request's headers.
def levelNames(values: List<&2, T.ModelThinkingLevel>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case level <> rest: Levels.name(level) <> levelNames(rest)

def supported(model: T.Model<T.JsonValue>) -> List<&2, String>: levelNames(Models.getSupportedThinkingLevels(T.JsonValue, model))

def has(values: List<&2, String>, +name: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value, name) || has(rest, name)

def presentIs(value: Maybe<&2, T.Nullable<String>>, want: String) -> Bool:
  match value:
    case Some{T.PresentValue{text}}: String.eq(text, want)
    case _: False{}

def mapped(model: T.Model<T.JsonValue>, level: T.ThinkingLevel, +want: String) -> Bool:
  match model:
    case T.Model{_, _, _, _, _, _, levels, _, _, _, _, _, _, _, _, _}: presentIs(Levels.mapped(levels, T.Thinking{level}), want)

def anthropicApi(model: T.Model<T.JsonValue>) -> Bool:
  match model:
    case T.Model{_, _, T.AnthropicMessagesApi{}, _, _, _, _, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def overrides() -> IO(Unit):
  +name = {"applies Copilot-specific adaptive thinking effort overrides" : String}
  +opus47 = Copilot.model_claude_opus_4_7()
  +opus5 = Copilot.model_claude_opus_5()
  +opus55 = Copilot.model_claude_opus_5_5()
  +sonnet46 = Copilot.model_claude_sonnet_4_6()
  do IO<Unit>:
    H.check(mapped(opus47, T.Minimal{}, "low") && mapped(opus47, T.XHigh{}, "xhigh") && mapped(opus47, T.Max{}, "max"), name ++ ": opus 4.7 map")
    H.check(has(supported(opus47), "xhigh") && has(supported(opus47), "max"), name ++ ": opus 4.7 levels")
    H.check(anthropicApi(opus5) && F.isEqual(F.compare(T.modelContextWindow(opus5), U32.to_f64(1000000))), name ++ ": opus 5 api and window")
    H.check(mapped(opus5, T.Minimal{}, "low") && mapped(opus5, T.XHigh{}, "xhigh") && mapped(opus5, T.Max{}, "max"), name ++ ": opus 5 map")
    H.check(has(supported(opus5), "xhigh") && has(supported(opus5), "max"), name ++ ": opus 5 levels")
    H.check(anthropicApi(opus55) && F.isEqual(F.compare(T.modelContextWindow(opus55), U32.to_f64(1000000))), name ++ ": opus 5.5 api and window")
    H.equalText(Some{String.join(supported(opus55), ",")}, Some{"low,medium,high,xhigh,max"}, name ++ ": opus 5.5 levels")
    H.check(mapped(sonnet46, T.Minimal{}, "low") && mapped(sonnet46, T.Max{}, "max"), name ++ ": sonnet 4.6 map")
    H.check(has(supported(sonnet46), "max") && Bool.not(has(supported(sonnet46), "xhigh")), name ++ ": sonnet 4.6 levels")
    H.pass(name)

def context() -> H.Context(): H.contextWith(Some{"You are a helpful assistant."}, H.user("Hello", 1) <> Nil{}, None{})

def copilotOptions() -> H.Options(): H.direct(H.streamOptions(Some{"tid_copilot_session_test_token"}, None{}, None{}), None{}, None{})

def maxTokens(value: Maybe<&2, T.JsonValue>, +want: F64) -> Bool:
  match value:
    case Some{T.JsonNumber{number}}: F.isEqual(F.compare(number, want))
    case _: False{}

def isArray(value: Maybe<&2, T.JsonValue>) -> Bool:
  match value:
    case Some{T.JsonArray{_}}: True{}
    case _: False{}

def bearer() -> IO(Unit):
  +name = {"uses Bearer auth, Copilot headers, and valid Anthropic Messages payload" : String}
  +model = Copilot.model_claude_sonnet_4_6()
  do IO<Unit>:
    H.check(anthropicApi(model), name ++ ": api")
    +sent : H.Outcome <- H.run(model, context(), copilotOptions(), H.Send{})
    H.equalText(H.header(H.requestOf(sent), "x-api-key"), None{}, name ++ ": apiKey")
    H.equalText(H.header(H.requestOf(sent), "authorization"), Some{"Bearer tid_copilot_session_test_token"}, name ++ ": authToken")
    H.check(H.contains(H.header(H.requestOf(sent), "user-agent"), "GitHubCopilotChat"), name ++ ": User-Agent")
    H.equalText(H.header(H.requestOf(sent), "copilot-integration-id"), Some{"vscode-chat"}, name ++ ": Copilot-Integration-Id")
    H.equalText(H.header(H.requestOf(sent), "x-initiator"), Some{"user"}, name ++ ": X-Initiator")
    H.equalText(H.header(H.requestOf(sent), "openai-intent"), Some{"conversation-edits"}, name ++ ": Openai-Intent")
    +captured : H.Outcome <- H.run(model, context(), copilotOptions(), H.Capture{})
    +params : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, H.payloadOf(captured))
    H.check(Bool.not(H.containsString(H.elements(H.fieldOf(params, "betas")), "fine-grained-tool-streaming-2025-05-14")), name ++ ": betas")
    H.equalJson(H.fieldOf(params, "model"), "\"claude-sonnet-4.6\"", name ++ ": model")
    H.equalJson(H.fieldOf(params, "stream"), "true", name ++ ": stream")
    H.check(maxTokens(H.fieldOf(params, "max_tokens"), T.modelMaxTokens(model)), name ++ ": max_tokens")
    H.check(isArray(H.fieldOf(params, "messages")), name ++ ": messages")
    H.pass(name)

def interleaved() -> IO(Unit):
  +name = {"omits interleaved-thinking beta for adaptive-thinking models" : String}
  do IO<Unit>:
    +captured : H.Outcome <- H.run(Copilot.model_claude_sonnet_4_6(), context(), H.withInterleaved(copilotOptions(), Some{True{}}), H.Capture{})
    H.check(Maybe.is_some(&2, T.JsonValue, H.payloadOf(captured)), name ++ ": payload captured")
    H.check(Bool.not(H.containsString(H.elements(H.fieldOf(H.payloadOf(captured), "betas")), "interleaved-thinking-2025-05-14")), name)
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    overrides()
    bearer()
    interleaved()
