import Base
import ../src/api/google-shared.bend as Shared
import ../src/types.bend as T
import ./anthropic-harness.bend as A
import ./google-harness.bend as H
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V

# Helpers for the google-shared convertMessages suites.
def Message() -> Data: T.Message<V.Value, V.Value, Unit, Unit>

def apiName(api: T.ModelApi) -> String:
  match api:
    case T.GoogleVertexApi{}: "google-vertex"
    case _: "google-generative-ai"

def assistant(content: List<&2, T.AssistantContent<V.Value>>, api: String, provider: String, model: String) -> Message():
  T.Assistant{T.AssistantMessage{content, api, provider, model, None{}, None{}, None{}, None{}, A.usage(), T.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(1)}}

def call(id: String, name: String, arguments: String, signature: Maybe<&2, String>) -> T.AssistantContent<V.Value>:
  T.AssistantToolCall{T.ToolCall{id, name, A.schema(arguments), signature, None{}}}

def result(id: String, name: String, content: List<&2, T.TextImageContent>) -> Message():
  T.ToolResult{T.ToolResultMessage{id, name, content, None{}, None{}, False{}, F.fromU32(1)}}

def text(value: String) -> T.TextImageContent: T.TextImageText{T.TextContent{value, None{}}}

def image(data: String, mime: String) -> T.TextImageContent: T.TextImageImage{T.ImageContent{data, mime}}

def convert(+model: T.Model<T.JsonValue>, context: H.Context()) -> IO(List<&2, T.JsonValue>):
  Shared.convertMessages(~Unit, ~Unit, model, context)

def partsOf(content: T.JsonValue) -> List<&2, T.JsonValue>: A.elements(A.fieldOf(Some{content}, "parts"))

def allParts(contents: List<&2, T.JsonValue>) -> List<&2, T.JsonValue>:
  match contents:
    case Nil{}: Nil{}
    case content <> rest: List.append(&2, T.JsonValue, partsOf(content), allParts(rest))

def withField(parts: List<&2, T.JsonValue>, +name: String) -> List<&2, T.JsonValue>:
  match parts:
    case Nil{}: Nil{}
    case +part <> rest:
      +tail = withField(rest, name)
      Bool.pick(List<&2, T.JsonValue>, Maybe.is_some(&2, T.JsonValue, A.fieldOf(Some{part}, name)), part <> tail, tail)

def prependSome(value: Maybe<&2, T.JsonValue>, rest: List<&2, T.JsonValue>) -> List<&2, T.JsonValue>:
  match value:
    case Some{item}: item <> rest
    case None{}: rest

def ids(parts: List<&2, T.JsonValue>, +field: String) -> List<&2, T.JsonValue>:
  match parts:
    case Nil{}: Nil{}
    case +part <> rest: prependSome(A.pathOf(field <> "id" <> Nil{}, Some{part}), ids(rest, field))

def modelTurn(contents: List<&2, T.JsonValue>) -> Maybe<&2, T.JsonValue>: A.findRole(contents, "model")

def count(-X: Data, values: List<&2, X>) -> Nat: List.length(&2, X, values)
