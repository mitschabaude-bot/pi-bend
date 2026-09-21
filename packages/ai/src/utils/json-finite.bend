import Base
import ../types.bend as T
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/record.bend as R

def number(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

# Validate numeric leaves before serializing. Select a continuation lazily so
# an array/object tail is a tail call, rather than an eager boolean argument.
def valid(value: T.JsonValue) -> Bool:
  match value:
    case T.JsonNumber{value}: number(F.decode(value))
    case T.JsonArray{Nil{}}: True{}
    case T.JsonArray{head <> rest}: Bool.pick(Unit -> Bool, valid(head), unused => valid(T.JsonArray{rest}), unused => False{})(Unit{})
    case T.JsonObject{R.Record{Nil{}}}: True{}
    case T.JsonObject{R.Record{R.Property{_, value} <> rest}}: Bool.pick(Unit -> Bool, valid(value), unused => valid(T.JsonObject{R.Record{rest}}), unused => False{})(Unit{})
    case _: True{}
