import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json-string.bend as S
import ../../../runtime/src/f64-decimal.bend as Number

# This codec accepts the upstream JsonValue domain, not arbitrary extension
# values. Undefined, callbacks, symbol metadata and cyclic objects require a
# distinct dynamic-value/schema conversion layer; they are not silently erased.
type Task is Data:
  RenderValue{value: T.JsonValue}
  RenderArray{values: List<&2, T.JsonValue>, first: Bool}
  RenderObject{fields: List<&2, R.Property<T.JsonValue>>, first: Bool}
  EmitFragment{text: String}

def emitNumber(encoded: Maybe<&2, String>, fragments: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match encoded:
    case None{}: None{}
    case Some{text}: Some{text <> fragments}

# Explicit work stack avoids mutually recursive value/list/object encoders.
# The finite acyclic JsonValue tree bounds expansion; every frame visits one
# node, list item or closing delimiter. Bend's structural checker cannot express
# that measure over a work stack, so this one traversal is annotated unsafe.
@unsafe
def encode(tasks: List<&2, Task>, result: Maybe<&2, List<&2, String>>) -> Maybe<&2, String>:
  match tasks result:
    case _ None{}: None{}
    case Nil{} Some{fragments}: Some{String.join(List.reverse(&2, String, fragments), "")}
    case EmitFragment{text} <> rest Some{fragments}: encode(rest, Some{text <> fragments})
    case RenderValue{T.JsonNull{}} <> rest Some{fragments}: encode(rest, Some{"null" <> fragments})
    case RenderValue{T.JsonBoolean{value}} <> rest Some{fragments}: encode(rest, Some{Bool.pick(String, value, "true", "false") <> fragments})
    case RenderValue{T.JsonNumber{value}} <> rest Some{fragments}: encode(rest, emitNumber(Number.toJsonNumber(value), fragments))
    case RenderValue{T.JsonString{value}} <> rest Some{fragments}: encode(rest, Some{S.quote(value) <> fragments})
    case RenderValue{T.JsonArray{values}} <> rest Some{fragments}: encode(RenderArray{values, True{}} <> EmitFragment{"]"} <> rest, Some{"[" <> fragments})
    case RenderValue{T.JsonObject{fields}} <> rest Some{fragments}: encode(RenderObject{R.entries(T.JsonValue, fields), True{}} <> EmitFragment{"}"} <> rest, Some{"{" <> fragments})
    case RenderArray{Nil{}, _} <> rest Some{fragments}: encode(rest, Some{fragments})
    case RenderArray{head <> tail, first} <> rest Some{fragments}: encode(RenderValue{head} <> RenderArray{tail, False{}} <> rest, Some{Bool.pick(String, first, "", ",") <> fragments})
    case RenderObject{Nil{}, _} <> rest Some{fragments}: encode(rest, Some{fragments})
    case RenderObject{R.Property{key, value} <> tail, first} <> rest Some{fragments}: encode(RenderValue{value} <> RenderObject{tail, False{}} <> rest, Some{(Bool.pick(String, first, "", ",") ++ S.quote(key) ++ ":") <> fragments})

def stringify(value: T.JsonValue) -> Maybe<&2, String>:
  encode(RenderValue{value} <> Nil{}, Some{Nil{}})
