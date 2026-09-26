import Base
import ../src/api/google-shared.bend as Shared
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ./google-shared-support.bend as S
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts.
def makeGemini3Model(api: T.ModelApi, provider: String, id: String) -> T.Model<T.JsonValue>:
  H.model(api, id, "Gemini 3 Pro Preview", provider, "https://example.com", False{}, 8192, 128000, None{})

def makeContext(api: String, provider: String, id: String, signature: Maybe<&2, String>) -> H.Context():
  H.context(H.user("Hi") <> S.assistant(S.call("call_1", "bash", "{\"command\":\"echo hi\"}", signature) <> S.call("call_2", "bash", "{\"command\":\"ls -la\"}", None{}) <> Nil{}, api, provider, id) <> S.result("call_1", "bash", S.text("hi") <> Nil{}) <> S.result("call_2", "bash", S.text("files") <> Nil{}) <> Nil{})

def preserved(+api: T.ModelApi, +provider: String, +id: String) -> IO(Unit):
  +name = {"preserves tool call IDs for " ++ id ++ " via " ++ S.apiName(api) ++ " history" : String}
  +model = makeGemini3Model(api, provider, id)
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(model, makeContext(S.apiName(api), provider, id, None{}))
    A.equalJson(Some{T.JsonArray{S.ids(S.allParts(contents), "functionCall")}}, "[\"call_1\",\"call_2\"]", name ++ ": calls")
    A.equalJson(Some{T.JsonArray{S.ids(S.allParts(contents), "functionResponse")}}, "[\"call_1\",\"call_2\"]", name ++ ": responses")
    A.pass(name)

def unsignedCalls(+name: String, +api: T.ModelApi, +provider: String, +history: String) -> IO(Unit):
  +model = makeGemini3Model(api, provider, "gemini-3-pro-preview")
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(model, makeContext(S.apiName(api), provider, history, None{}))
    +turn : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, S.modelTurn(contents))
    A.check(Maybe.is_some(&2, T.JsonValue, turn), name ++ ": model turn")
    +calls : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, S.withField(A.elements(A.fieldOf(turn, "parts")), "functionCall"))
    A.check(Nat.is_eq(S.count(T.JsonValue, calls), 2n), name ++ ": two calls")
    A.check(Nat.is_eq(S.count(T.JsonValue, S.withField(calls, "thoughtSignature")), 0n), name ++ ": no signatures")
    A.check(Bool.not(String.contains(A.showJson(turn), "skip_thought_signature_validator")), name ++ ": no validator skip")
    A.check(Bool.not(String.contains(A.showJson(turn), "Historical context")), name ++ ": no historical text")
    A.pass(name)

def validSignature() -> IO(Unit):
  +name = {"preserves valid thoughtSignature when present for the same provider and model" : String}
  +model = makeGemini3Model(T.GoogleGenerativeAiApi{}, "google", "gemini-3-pro-preview")
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(model, makeContext("google-generative-ai", "google", "gemini-3-pro-preview", Some{"AAAAAAAAAAAAAAAAAAAAAA=="}))
    +calls : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, S.withField(A.elements(A.fieldOf(S.modelTurn(contents), "parts")), "functionCall"))
    A.check(Nat.is_eq(S.count(T.JsonValue, calls), 2n), name ++ ": two calls")
    A.equalJson(A.fieldOf(List.head(&2, T.JsonValue, calls), "thoughtSignature"), "\"AAAAAAAAAAAAAAAAAAAAAA==\"", name ++ ": first")
    A.absent(A.fieldOf(List.last(&2, T.JsonValue, calls), "thoughtSignature"), name ++ ": second")
    A.pass(name)

def nonGemini3() -> IO(Unit):
  +name = {"does not add a thoughtSignature for non-Gemini-3 models" : String}
  +model = makeGemini3Model(T.GoogleGenerativeAiApi{}, "google", "gemini-2.5-flash")
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(model, makeContext("google-generative-ai", "google", "other-model", None{}))
    +calls : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, S.withField(A.elements(A.fieldOf(S.modelTurn(contents), "parts")), "functionCall"))
    +responses : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, S.withField(S.allParts(contents), "functionResponse"))
    A.check(Nat.is_eq(S.count(T.JsonValue, calls), 2n), name ++ ": two calls")
    A.check(List.is_empty(&2, T.JsonValue, S.ids(calls, "functionCall")), name ++ ": no call ids")
    A.check(List.is_empty(&2, T.JsonValue, S.withField(calls, "thoughtSignature")), name ++ ": no signatures")
    A.check(Nat.is_eq(S.count(T.JsonValue, responses), 2n), name ++ ": two responses")
    A.check(List.is_empty(&2, T.JsonValue, S.ids(responses, "functionResponse")), name ++ ": no response ids")
    A.pass(name)

def sameBool(a: Bool, b: Bool) -> Bool:
  match a b:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def requires(+expected: Bool, +id: String) -> IO(Unit):
  +name = {"returns " ++ Bool.pick(String, expected, "true", "false") ++ " for " ++ id : String}
  do IO<Unit>:
    A.check(sameBool(Shared.requiresToolCallId(id), expected), name)
    A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    preserved(T.GoogleGenerativeAiApi{}, "google", "gemini-3-pro-preview")
    preserved(T.GoogleGenerativeAiApi{}, "google", "gemini-3.6-flash")
    preserved(T.GoogleVertexApi{}, "google-vertex", "gemini-3-pro-preview")
    unsignedCalls("does not add skip_thought_signature_validator for unsigned Google Gen AI tool calls", T.GoogleGenerativeAiApi{}, "google", "other-model")
    unsignedCalls("does not add skip_thought_signature_validator for unsigned Vertex tool calls", T.GoogleVertexApi{}, "google-vertex", "gemini-3-pro-preview")
    validSignature()
    nonGemini3()
    requires(False{}, "gemini-2.5-flash")
    requires(True{}, "gemini-3.6-flash")
    requires(True{}, "claude-sonnet-4-5")
    requires(True{}, "gpt-oss-120b")
