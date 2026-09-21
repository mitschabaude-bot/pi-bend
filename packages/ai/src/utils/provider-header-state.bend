import Base
import ../types.bend as T
import ../../../runtime/src/http-header.bend as H
import ../../../runtime/src/headers.bend as Headers
import ../../../runtime/src/record.bend as R

# Canonical names and normalized values; null is an explicit removal command.
# A single immutable record retains provenance without synchronizing a separate
# header collection and deletion set. Construct through apply/build at inputs.
type State is Data:
  State{fields: T.ProviderHeaders()}

def empty() -> State: State{R.new(T.Nullable<String>)}

def put(state: State, name: String, value: T.Nullable<String>) -> State:
  match state:
    case State{fields}: State{R.set(T.Nullable<String>, fields, name, value)}

def lookup(state: State, name: String) -> Maybe<&2, T.Nullable<String>>:
  match state:
    case State{fields}: R.get(T.Nullable<String>, fields, name)

def removed(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: True{}
    case _: False{}

def nonempty(value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.PresentValue{SCon{_, _}}}: True{}
    case _: False{}

def deleted(state: State, result: Result<&2, &2, H.HeaderError, String>) -> Result<&2, &2, H.HeaderError, State>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{name}: Done{put(state, name, T.NullValue{})}

def assigned(state: State, result: Result<&2, &2, H.HeaderError, H.Header>) -> Result<&2, &2, H.HeaderError, State>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{H.Header{name, value}}: Done{put(state, name, T.PresentValue{value})}

def field(state: State, name: String, value: T.Nullable<String>) -> Result<&2, &2, H.HeaderError, State>:
  match value:
    case T.NullValue{}: deleted(state, H.normalizeName(name))
    case T.PresentValue{text}: assigned(state, H.normalize(name, text))

def entries(values: List<&2, R.Property<T.Nullable<String>>>, result: Result<&2, &2, H.HeaderError, State>) -> Result<&2, &2, H.HeaderError, State>:
  match values result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{state}: Done{state}
    case R.Property{name, value} <> rest Done{state}: entries(rest, field(state, name, value))

def apply(layer: Maybe<&2, T.ProviderHeaders()>, result: Result<&2, &2, H.HeaderError, State>) -> Result<&2, &2, H.HeaderError, State>:
  match layer:
    case None{}: result
    case Some{R.Record{values}}: entries(values, result)

def layers(values: List<&2, Maybe<&2, T.ProviderHeaders()>>, result: Result<&2, &2, H.HeaderError, State>) -> Result<&2, &2, H.HeaderError, State>:
  match values:
    case Nil{}: result
    case head <> rest: layers(rest, apply(head, result))

def build(values: List<&2, Maybe<&2, T.ProviderHeaders()>>) -> Result<&2, &2, H.HeaderError, State>:
  layers(values, Done{empty()})

# Materialization drops removal commands only after all policy decisions have
# seen them. Values are already normalized; no second validation is necessary.
def materialize(values: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<List<&2, String>>>:
  match values:
    case Nil{}: Nil{}
    case R.Property{_, T.NullValue{}} <> rest: materialize(rest)
    case R.Property{name, T.PresentValue{text}} <> rest: R.Property{name, text <> Nil{}} <> materialize(rest)

def headers(state: State) -> Headers.Headers:
  match state:
    case State{R.Record{values}}: Headers.Headers{R.Record{materialize(values)}}
