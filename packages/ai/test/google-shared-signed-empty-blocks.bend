import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ./google-shared-support.bend as S
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/google-shared-signed-empty-blocks.test.ts.
def validSig() -> String: "AAAAAAAAAAAAAAAAAAAAAA=="

def makeModel() -> T.Model<T.JsonValue>:
  H.model(T.GoogleGenerativeAiApi{}, "gemini-3-pro-preview", "gemini-3-pro-preview", "google", "https://example.com", False{}, 8192, 128000, None{})

def makeContext(id: String, content: List<&2, T.AssistantContent<V.Value>>) -> H.Context():
  H.context(H.user("Hi") <> S.assistant(content, "google-generative-ai", "google", id) <> Nil{})

def thinking(value: String, signature: Maybe<&2, String>) -> T.AssistantContent<V.Value>: T.AssistantThinking{T.ThinkingContent{value, signature, None{}}}

def text(value: String, signature: Maybe<&2, String>) -> T.AssistantContent<V.Value>: T.AssistantText{T.TextContent{value, signature}}

def bash() -> T.AssistantContent<V.Value>: S.call("call_1", "bash", "{\"command\":\"ls\"}", None{})

def signedParts(parts: List<&2, T.JsonValue>) -> List<&2, T.JsonValue>:
  match parts:
    case Nil{}: Nil{}
    case +part <> rest:
      +tail = signedParts(rest)
      Bool.pick(List<&2, T.JsonValue>, A.sameText(A.textOf2(A.fieldOf(Some{part}, "thoughtSignature")), Some{validSig()}), part <> tail, tail)

def modelParts(id: String, content: List<&2, T.AssistantContent<V.Value>>) -> IO(List<&2, T.JsonValue>):
  do IO<List<&2, T.JsonValue>>:
    contents : List<&2, T.JsonValue> <- S.convert(makeModel(), makeContext(id, content))
    return A.elements(A.fieldOf(S.modelTurn(contents), "parts"))

def run() -> IO(Unit):
  do IO<Unit>:
    +thinkingParts : List<&2, T.JsonValue> <- modelParts("gemini-3-pro-preview", thinking("", Some{validSig()}) <> bash() <> Nil{})
    A.check(Nat.is_eq(S.count(T.JsonValue, signedParts(thinkingParts)), 1n), "one signed thinking part")
    A.equalJson(A.fieldOf(List.head(&2, T.JsonValue, signedParts(thinkingParts)), "thought"), "true", "thought flag")
    A.pass("keeps a signed empty thinking block so its signature is echoed back")
    +textParts : List<&2, T.JsonValue> <- modelParts("gemini-3-pro-preview", text("", Some{validSig()}) <> bash() <> Nil{})
    A.check(Nat.is_eq(S.count(T.JsonValue, signedParts(textParts)), 1n), "one signed text part")
    A.pass("keeps a signed empty text block the same way")
    +unsigned : List<&2, T.JsonValue> <- modelParts("gemini-3-pro-preview", thinking("", None{}) <> text("   ", None{}) <> bash() <> Nil{})
    A.check(Nat.is_eq(S.count(T.JsonValue, unsigned), 1n), "only the call remains")
    A.check(Maybe.is_some(&2, T.JsonValue, A.fieldOf(List.head(&2, T.JsonValue, unsigned), "functionCall")), "function call")
    A.pass("still drops unsigned empty blocks")
    +foreign : List<&2, T.JsonValue> <- modelParts("other-model", thinking("", Some{validSig()}) <> text("", Some{validSig()}) <> bash() <> Nil{})
    A.check(Nat.is_eq(S.count(T.JsonValue, foreign), 1n), "only the call remains for another model")
    A.check(Maybe.is_some(&2, T.JsonValue, A.fieldOf(List.head(&2, T.JsonValue, foreign), "functionCall")), "function call for another model")
    A.check(Bool.not(String.contains(A.showJson(Some{T.JsonArray{foreign}}), validSig())), "signature dropped")
    A.pass("still drops signed empty blocks from a different provider/model (signature unusable)")
