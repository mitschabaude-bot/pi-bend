import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json-string.bend as S
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/f64-decimal.bend as Number

# Provider JSON serialization consumes an immutable data tree.
type Task is Data:
  RenderValue{value: T.JsonValue}
  RenderArray{values: List<&2, T.JsonValue>, first: Bool}
  RenderObject{fields: List<&2, R.Property<T.JsonValue>>, first: Bool}
  EmitFragment{text: String}
  PrettyValue{value: T.JsonValue, indent: String}
  PrettyArray{values: List<&2, T.JsonValue>, indent: String, first: Bool}
  PrettyObject{fields: List<&2, R.Property<T.JsonValue>>, indent: String, first: Bool}

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
    case PrettyValue{T.JsonArray{Nil{}}, _} <> rest Some{fragments}: encode(rest, Some{"[]" <> fragments})
    case PrettyValue{T.JsonArray{values}, +indent} <> rest Some{fragments}: encode(PrettyArray{values, indent ++ "  ", True{}} <> EmitFragment{"\n" ++ indent ++ "]"} <> rest, Some{"[" <> fragments})
    case PrettyValue{T.JsonObject{R.Record{Nil{}}}, _} <> rest Some{fragments}: encode(rest, Some{"{}" <> fragments})
    case PrettyValue{T.JsonObject{fields}, +indent} <> rest Some{fragments}: encode(PrettyObject{R.entries(T.JsonValue, fields), indent ++ "  ", True{}} <> EmitFragment{"\n" ++ indent ++ "}"} <> rest, Some{"{" <> fragments})
    case PrettyValue{value, _} <> rest Some{fragments}: encode(RenderValue{value} <> rest, Some{fragments})
    case PrettyArray{Nil{}, _, _} <> rest Some{fragments}: encode(rest, Some{fragments})
    case PrettyArray{head <> tail, +indent, first} <> rest Some{fragments}: encode(PrettyValue{head, indent} <> PrettyArray{tail, indent, False{}} <> rest, Some{(Bool.pick(String, first, "\n", ",\n") ++ indent) <> fragments})
    case PrettyObject{Nil{}, _, _} <> rest Some{fragments}: encode(rest, Some{fragments})
    case PrettyObject{R.Property{key, value} <> tail, +indent, first} <> rest Some{fragments}: encode(PrettyValue{value, indent} <> PrettyObject{tail, indent, False{}} <> rest, Some{(Bool.pick(String, first, "\n", ",\n") ++ indent ++ S.quote(key) ++ ": ") <> fragments})
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

# Fixed two-space rendering for diagnostics; no JavaScript replacer/hooks or
# arbitrary indentation coercion is part of the native codec.
def stringifyPretty(value: T.JsonValue) -> Maybe<&2, String>:
  encode(PrettyValue{value, ""} <> Nil{}, Some{Nil{}})

# Numeric leaves must be finite before serialization (JSON.stringify emits
# null for NaN/Infinity; the provider rejects the payload instead). A lazily
# selected continuation keeps the array/object tail a tail call.
def finiteNumber(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def finite(value: T.JsonValue) -> Bool:
  match value:
    case T.JsonNumber{value}: finiteNumber(F.decode(value))
    case T.JsonArray{Nil{}}: True{}
    case T.JsonArray{head <> rest}: Bool.pick(Unit -> Bool, finite(head), unused => finite(T.JsonArray{rest}), unused => False{})(Unit{})
    case T.JsonObject{R.Record{Nil{}}}: True{}
    case T.JsonObject{R.Record{R.Property{_, value} <> rest}}: Bool.pick(Unit -> Bool, finite(value), unused => finite(T.JsonObject{R.Record{rest}}), unused => False{})(Unit{})
    case _: True{}
