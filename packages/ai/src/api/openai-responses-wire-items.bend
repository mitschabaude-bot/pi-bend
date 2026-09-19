import Base
import ../types.bend as T
import ./openai-responses-stream-content.bend as Content
import ../../../runtime/src/json-decode.bend as D
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R

# Decode only fields consumed by pi. Opaque reasoning replay retains all fields.
def phase(value: V.Value) -> Result<&2, &2, D.Error, T.TextSignaturePhase>:
  match value:
    case V.Text{"commentary"}: Done{T.Commentary{}}
    case V.Text{"final_answer"}: Done{T.FinalAnswer{}}
    case _: Fail{D.InvalidValue{Nil{}, "commentary or final_answer"}}

def part(value: V.Value) -> Result<&2, &2, D.Error, String>:
  do Result<&2, &2, D.Error, String>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : String <- D.required(String, fields, "type", D.string)
    # The upstream joins text for output_text and refusal for other variants.
    text : Maybe<&2, String> <- D.optional(String, fields, Bool.pick(String, String.eq(kind, "output_text"), "text", "refusal"), D.string)
    return Maybe.default(&2, String, text, "")

def content(value: V.Value) -> Result<&2, &2, D.Error, List<&2, String>>:
  D.list(~String, ~part, value)

def message(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Content.OutputItem>:
  do Result<&2, &2, D.Error, Content.OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    phase : Maybe<&2, T.TextSignaturePhase> <- D.optional(T.TextSignaturePhase, fields, "phase", phase)
    content : Maybe<&2, List<&2, String>> <- D.optional(List<&2, String>, fields, "content", content)
    return Content.MessageItem{id, phase, Maybe.default(&2, List<&2, String>, content, Nil{})}

def function(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Content.OutputItem>:
  do Result<&2, &2, D.Error, Content.OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    callId : String <- D.required(String, fields, "call_id", D.string)
    name : String <- D.required(String, fields, "name", D.string)
    arguments : Maybe<&2, String> <- D.optional(String, fields, "arguments", D.string)
    namespace : Maybe<&2, String> <- D.optional(String, fields, "namespace", D.string)
    return Content.FunctionItem{id, callId, name, Maybe.default(&2, String, arguments, ""), namespace}

def custom(+fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Content.OutputItem>:
  do Result<&2, &2, D.Error, Content.OutputItem>:
    id : String <- D.required(String, fields, "id", D.string)
    callId : String <- D.required(String, fields, "call_id", D.string)
    name : String <- D.required(String, fields, "name", D.string)
    input : Maybe<&2, String> <- D.optional(String, fields, "input", D.string)
    namespace : Maybe<&2, String> <- D.optional(String, fields, "namespace", D.string)
    return Content.CustomItem{id, callId, name, input, namespace}

def tagged(kind: Maybe<&2, String>, fields: R.Record<V.Value>) -> Result<&2, &2, D.Error, Content.OutputItem>:
  match kind:
    case Some{"reasoning"}: Done{Content.ReasoningItem{fields}}
    case Some{"message"}: message(fields)
    case Some{"function_call"}: function(fields)
    case Some{"custom_tool_call"}: custom(fields)
    case _: Done{Content.OtherItem{}}

def decode(value: V.Value) -> Result<&2, &2, D.Error, Content.OutputItem>:
  do Result<&2, &2, D.Error, Content.OutputItem>:
    +fields : R.Record<V.Value> <- D.object(value)
    kind : Maybe<&2, String> <- D.optional(String, fields, "type", D.string)
    tagged(kind, fields)
