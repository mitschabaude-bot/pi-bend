import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/schema-value.bend as V

# pi-mono f07218c4d packages/ai/test/anthropic-eager-tool-input-compat.test.ts.
# upstream captures the request at a local HTTP server; natively the fetch
# records the same request (headers and JSON body) before it would connect.
def createModel(eager: Maybe<&2, Bool>, strict: Maybe<&2, Bool>) -> T.Model<T.JsonValue>:
  H.custom("claude-opus-4-8", "Claude Opus 4.8", "test-anthropic", "http://127.0.0.1:9", 32000, 200000, None{}, Some{T.AnthropicMessagesCompat{eager, None{}, None{}, None{}, None{}, None{}, Some{True{}}, None{}, strict, None{}, None{}, None{}, None{}}})

def tool() -> T.Tool<V.Value>:
  T.Tool{"lookup", "Look up a value", H.schema("{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"]}"), None{}}

def schemaCompatibilityTool() -> T.Tool<V.Value>:
  T.Tool{"lookup", "Look up a value", H.schema("{\"additionalProperties\":false,\"title\":\"LookupInput\",\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"]}"), None{}}

def strictTool() -> T.Tool<V.Value>:
  T.Tool{"lookup", "Look up a value", H.schema("{\"title\":\"StrictLookupInput\",\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"},\"optional\":{\"type\":\"number\"}},\"required\":[\"value\"]}"), Some{T.SamplingConfigured{T.JsonSchemaSampling{T.Prefer{}}}}}

def createContext(tools: List<&2, T.Tool<V.Value>>) -> H.Context():
  H.contextWith(None{}, H.user("Use the tool", 1) <> Nil{}, Some{tools})

def captureRequest(+model: T.Model<T.JsonValue>, +context: H.Context()) -> IO(Maybe<&2, T.JsonValue> & Maybe<&2, String>):
  do IO<Maybe<&2, T.JsonValue> & Maybe<&2, String>>:
    +outcome : H.Outcome <- H.run(model, context, H.direct(H.streamOptions(Some{"test-key"}, Some{T.CacheNone{}}, None{}), None{}, None{}), H.Send{})
    return (H.requestBody(H.requestOf(outcome)), H.header(H.requestOf(outcome), "anthropic-beta"))

def checkedEager(request: Maybe<&2, T.JsonValue> & Maybe<&2, String>, +eager: String, +beta: Maybe<&2, String>, +name: String) -> IO(Unit):
  match request:
    case (+body, header):
      do IO<Unit>:
        H.check(Maybe.is_some(&2, T.JsonValue, body), name ++ ": request captured")
        H.equalJson(H.fieldOf(H.firstElement(H.fieldOf(body, "tools")), "eager_input_streaming"), eager, name)
        H.equalText(header, beta, name ++ ": anthropic-beta")
        H.pass(name)

def eagerDefault() -> IO(Unit):
  +name = {"sends per-tool eager_input_streaming by default" : String}
  do IO<Unit>:
    request : Maybe<&2, T.JsonValue> & Maybe<&2, String> <- captureRequest(createModel(None{}, None{}), createContext(tool() <> Nil{}))
    checkedEager(request, "true", None{}, name)

def checkedLegacy(request: Maybe<&2, T.JsonValue> & Maybe<&2, String>, +name: String) -> IO(Unit):
  match request:
    case (+body, header):
      do IO<Unit>:
        H.absent(H.fieldOf(H.firstElement(H.fieldOf(body, "tools")), "eager_input_streaming"), name)
        H.equalText(header, Some{"fine-grained-tool-streaming-2025-05-14"}, name ++ ": anthropic-beta")
        H.pass(name)

def checkedNoTools(request: Maybe<&2, T.JsonValue> & Maybe<&2, String>, +name: String) -> IO(Unit):
  match request:
    case (+body, header):
      do IO<Unit>:
        H.check(Maybe.is_some(&2, T.JsonValue, body), name ++ ": request captured")
        H.absent(H.fieldOf(body, "tools"), name)
        H.equalText(header, None{}, name ++ ": anthropic-beta")
        H.pass(name)

def firstTool(request: Maybe<&2, T.JsonValue> & Maybe<&2, String>) -> Maybe<&2, T.JsonValue>:
  match request:
    case (body, _): H.firstElement(H.fieldOf(body, "tools"))

def strictSchemas() -> IO(Unit):
  +name = {"only sends the full input schema for strict JSON-schema tools" : String}
  do IO<Unit>:
    legacy : Maybe<&2, T.JsonValue> & Maybe<&2, String> <- captureRequest(createModel(None{}, Some{True{}}), createContext(schemaCompatibilityTool() <> Nil{}))
    H.equalJson(H.fieldOf(firstTool(legacy), "input_schema"), "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"]}", name ++ ": legacy schema")
    strict : Maybe<&2, T.JsonValue> & Maybe<&2, String> <- captureRequest(createModel(None{}, Some{True{}}), createContext(strictTool() <> Nil{}))
    +selected : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, firstTool(strict))
    H.equalJson(H.fieldOf(selected, "strict"), "true", name ++ ": strict")
    H.equalJson(H.pathOf(["input_schema", "additionalProperties"], selected), "false", name ++ ": additionalProperties")
    H.equalJson(H.pathOf(["input_schema", "required"], selected), "[\"value\",\"optional\"]", name ++ ": required")
    H.equalJson(H.pathOf(["input_schema", "properties", "optional"], selected), "{\"anyOf\":[{\"type\":\"number\"},{\"type\":\"null\"}]}", name ++ ": optional")
    H.equalJson(H.pathOf(["input_schema", "title"], selected), "\"StrictLookupInput\"", name ++ ": title")
    H.pass(name)

def run() -> IO(Unit):
  do IO<Unit>:
    eagerDefault()
    legacy : Maybe<&2, T.JsonValue> & Maybe<&2, String> <- captureRequest(createModel(Some{False{}}, None{}), createContext(tool() <> Nil{}))
    checkedLegacy(legacy, "uses the legacy fine-grained tool streaming beta when eager tool input streaming is disabled")
    none : Maybe<&2, T.JsonValue> & Maybe<&2, String> <- captureRequest(createModel(Some{False{}}, None{}), createContext(Nil{}))
    checkedNoTools(none, "does not send the legacy fine-grained tool streaming beta when there are no tools")
    strictSchemas()
