import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/headers.bend as H
import ../../../runtime/src/http-header.bend as Field

# Provider configuration overlays preserve spelling until the HTTP boundary.
# This matches pi's precedence without introducing JavaScript object behavior.
def overlayEntries(entries: List<&2, R.Property<T.Nullable<String>>>, target: T.ProviderHeaders()) -> T.ProviderHeaders():
  match entries:
    case Nil{}: target
    case R.Property{name, value} <> rest:
      overlayEntries(rest, R.set(T.Nullable<String>, target, name, value))

def overlay(target: T.ProviderHeaders(), source: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  match source:
    case None{}: target
    case Some{R.Record{entries}}: overlayEntries(entries, target)

def presentEntries(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest:
      R.Property{name, T.PresentValue{value}} <> presentEntries(rest)

def present(record: R.Record<String>) -> T.ProviderHeaders():
  R.Record{presentEntries(R.entries(String, record))}

def overlayStrings(target: T.ProviderHeaders(), source: Maybe<&2, R.Record<String>>) -> T.ProviderHeaders():
  match source:
    case None{}: target
    case Some{record}: overlay(target, Some{present(record)})

# Configuration values replace earlier HTTP values case-insensitively. Null
# removes an inherited header; dropping null before this step would lose that
# instruction. Empty strings are valid replacements, not removals.
def applyValue(headers: H.Headers, name: String, value: T.Nullable<String>) -> Result<&2, &2, Field.HeaderError, H.Headers>:
  match value:
    case T.NullValue{}: H.delete(headers, name)
    case T.PresentValue{text}: H.set(headers, name, text)

def applyEntries(entries: List<&2, R.Property<T.Nullable<String>>>, result: Result<&2, &2, Field.HeaderError, H.Headers>) -> Result<&2, &2, Field.HeaderError, H.Headers>:
  match entries result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{headers}: Done{headers}
    case R.Property{name, value} <> rest Done{headers}:
      applyEntries(rest, applyValue(headers, name, value))

def apply(headers: H.Headers, configuration: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Field.HeaderError, H.Headers>:
  match configuration:
    case None{}: Done{headers}
    case Some{R.Record{entries}}: applyEntries(entries, Done{headers})
