import Base
import ./schema-value.bend as V
import ./record.bend as R
import ./f64.bend as F

# Paths carry literal field names, not dot-separated strings or JS properties.
type Segment is Data:
  Field{name: String}
  Index{index: Nat}

type Error is Data:
  MissingField{path: List<&2, Segment>}
  WrongType{path: List<&2, Segment>, expected: String}
  InvalidValue{path: List<&2, Segment>, expected: String}

def at(error: Error, segment: Segment) -> Error:
  match error:
    case MissingField{path}: MissingField{segment <> path}
    case WrongType{path, expected}: WrongType{segment <> path, expected}
    case InvalidValue{path, expected}: InvalidValue{segment <> path, expected}

def located(-A: Data, result: Result<&2, &2, Error, A>, segment: Segment) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{error}: Fail{at(error, segment)}

def object(value: V.Value) -> Result<&2, &2, Error, R.Record<V.Value>>:
  match value:
    case V.ObjectValue{fields}: Done{fields}
    case _: Fail{WrongType{Nil{}, "object"}}

def string(value: V.Value) -> Result<&2, &2, Error, String>:
  match value:
    case V.Text{text}: Done{text}
    case _: Fail{WrongType{Nil{}, "string"}}

def number(value: V.Value) -> Result<&2, &2, Error, F.F64>:
  match value:
    case V.Number{scalar}: Done{scalar}
    case _: Fail{WrongType{Nil{}, "number"}}

def array(value: V.Value) -> Result<&2, &2, Error, List<&2, V.Value>>:
  match value:
    case V.ArrayValue{values}: Done{values}
    case _: Fail{WrongType{Nil{}, "array"}}

def requiredValue(value: Maybe<&2, V.Value>) -> Result<&2, &2, Error, V.Value>:
  match value:
    case None{}: Fail{MissingField{Nil{}}}
    case Some{value}: Done{value}

def required(-A: Data, fields: R.Record<V.Value>, +key: String, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, A>:
  located(A, Result.bind(&2, &2, Error, V.Value, A, requiredValue(R.get(V.Value, fields, key)), decode), Field{key})

# Nullable protocol fields use Maybe; a wrong non-null type remains an error.
def optionalValue(-A: Data, value: Maybe<&2, V.Value>, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, Maybe<&2, A>>:
  match value:
    case None{}: Done{None{}}
    case Some{V.Null{}}: Done{None{}}
    case Some{value}: Result.map(&2, &2, Error, A, Maybe<&2, A>, item => Some{item}, decode(value))

def optional(-A: Data, fields: R.Record<V.Value>, +key: String, decode: V.Value -> Result<&2, &2, Error, A>) -> Result<&2, &2, Error, Maybe<&2, A>>:
  located(Maybe<&2, A>, optionalValue(A, R.get(V.Value, fields, key), decode), Field{key})

def items(~A: Data, ~decode: V.Value -> Result<&2, &2, Error, A>, values: List<&2, V.Value>, +index: Nat) -> Result<&2, &2, Error, List<&2, A>>:
  match values:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, Error, List<&2, A>>:
        value : A <- located(A, decode(head), Index{index})
        rest : List<&2, A> <- items(~A, ~decode, tail, index + 1n)
        return value <> rest

def list(~A: Data, ~decode: V.Value -> Result<&2, &2, Error, A>, value: V.Value) -> Result<&2, &2, Error, List<&2, A>>:
  do Result<&2, &2, Error, List<&2, A>>:
    values : List<&2, V.Value> <- array(value)
    items(~A, ~decode, values, 0n)
