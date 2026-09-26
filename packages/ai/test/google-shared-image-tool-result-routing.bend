import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ./google-shared-support.bend as S

# pi-mono f07218c4d packages/ai/test/google-shared-image-tool-result-routing.test.ts.
def makeModel(+id: String) -> T.Model<T.JsonValue>:
  H.model(T.GoogleGenerativeAiApi{}, id, id, "google", "https://example.com", True{}, 8192, 128000, None{})

def makeContext(id: String) -> H.Context():
  H.context(H.user("read the files") <> S.assistant(S.call("call_a", "read", "{\"path\":\"a.txt\"}", None{}) <> S.call("call_img", "read", "{\"path\":\"image.png\"}", None{}) <> S.call("call_b", "read", "{\"path\":\"b.txt\"}", None{}) <> Nil{}, "google-generative-ai", "google", id) <> S.result("call_a", "read", S.text("alpha text") <> Nil{}) <> S.result("call_img", "read", S.image("abc", "image/png") <> Nil{}) <> S.result("call_b", "read", S.text("beta text") <> Nil{}) <> Nil{})

def at(values: List<&2, T.JsonValue>, index: Nat) -> Maybe<&2, T.JsonValue>: List.get(&2, T.JsonValue, values, index)

def allResponses(parts: List<&2, T.JsonValue>) -> Bool:
  match parts:
    case Nil{}: True{}
    case +part <> rest: Maybe.is_some(&2, T.JsonValue, A.fieldOf(Some{part}, "functionResponse")) && allResponses(rest)

def separate() -> IO(Unit):
  +name = {"keeps separate synthetic image turn for Gemini 2.x Google API models" : String}
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(makeModel("gemini-2.5-flash"), makeContext("gemini-2.5-flash"))
    A.check(Nat.is_eq(S.count(T.JsonValue, contents), 5n), name ++ ": five contents")
    A.check(allResponses(A.elements(A.fieldOf(at(contents, 2n), "parts"))), name ++ ": responses")
    A.equalJson(A.fieldOf(A.firstElement(A.fieldOf(at(contents, 3n), "parts")), "text"), "\"Tool result image:\"", name ++ ": image turn")
    A.check(Maybe.is_some(&2, T.JsonValue, A.fieldOf(at(A.elements(A.fieldOf(at(contents, 3n), "parts")), 1n), "inlineData")), name ++ ": inline data")
    A.check(Maybe.is_some(&2, T.JsonValue, A.fieldOf(A.firstElement(A.fieldOf(at(contents, 4n), "parts")), "functionResponse")), name ++ ": later response")
    A.pass(name)

def nested() -> IO(Unit):
  +name = {"nests image tool results for Gemini 3 Google API models" : String}
  do IO<Unit>:
    +contents : List<&2, T.JsonValue> <- S.convert(makeModel("gemini-3-pro-preview"), makeContext("gemini-3-pro-preview"))
    A.check(Nat.is_eq(S.count(T.JsonValue, contents), 3n), name ++ ": three contents")
    +parts : List<&2, T.JsonValue> <- IO.pure(List<&2, T.JsonValue>, A.elements(A.fieldOf(at(contents, 2n), "parts")))
    A.check(Nat.is_eq(S.count(T.JsonValue, parts), 3n), name ++ ": three parts")
    +response : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, A.fieldOf(at(parts, 1n), "functionResponse"))
    A.check(Maybe.is_some(&2, T.JsonValue, response), name ++ ": image response")
    A.check(Nat.is_eq(S.count(T.JsonValue, A.elements(A.fieldOf(response, "parts"))), 1n), name ++ ": one nested part")
    A.check(Maybe.is_some(&2, T.JsonValue, A.fieldOf(A.firstElement(A.fieldOf(response, "parts")), "inlineData")), name ++ ": inline data")
    A.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    separate()
    nested()
