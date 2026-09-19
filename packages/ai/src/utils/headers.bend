import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R

# Provider configuration is not yet a Fetch header list. Keep spelling and
# string values intact here; null requests removal and is omitted by this view.
def present(properties: List<&2, R.Property<T.Nullable<String>>>) -> List<&2, R.Property<String>>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{_, T.NullValue{}} <> rest: present(rest)
    case R.Property{name, T.PresentValue{value}} <> rest: R.Property{name, value} <> present(rest)

def nonempty(properties: List<&2, R.Property<String>>) -> Maybe<&2, R.Record<String>>:
  match properties:
    case Nil{}: None{}
    case head <> rest: Some{R.Record{head <> rest}}

def providerHeadersToRecord(headers: Maybe<&2, T.ProviderHeaders()>) -> Maybe<&2, R.Record<String>>:
  match headers:
    case None{}: None{}
    case Some{R.Record{properties}}: nonempty(present(properties))
