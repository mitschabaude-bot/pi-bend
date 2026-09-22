import Base
import ../types.bend as T
import ../../../runtime/src/http-message.bend as H
import ../../../runtime/src/http-message.bend as Field
import ../../../runtime/src/record.bend as R

# pi `headers.ts` plus the provider-header overlays from `types.ts`: provider
# configuration keeps its spelling until the HTTP boundary, and null is an
# explicit removal instruction rather than an absent key.

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

# Fetch iteration exposes separate Set-Cookie entries. As in pi, projecting
# into a single-value record retains the last value for that name.
def collect(entries: List<&2, Field.Header>, record: R.Record<String>) -> R.Record<String>:
  match entries:
    case Nil{}: record
    case Field.Header{name, value} <> rest: collect(rest, R.set(String, record, name, value))

def headersToRecord(headers: H.Headers) -> R.Record<String>:
  collect(H.entries(headers), R.new(String))

# Overlays: later layers replace earlier entries, matching pi's spread order.
def overlayEntries(entries: List<&2, R.Property<T.Nullable<String>>>, target: T.ProviderHeaders()) -> T.ProviderHeaders():
  match entries:
    case Nil{}: target
    case R.Property{name, value} <> rest: overlayEntries(rest, R.set(T.Nullable<String>, target, name, value))

def overlay(target: T.ProviderHeaders(), source: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  match source:
    case None{}: target
    case Some{R.Record{entries}}: overlayEntries(entries, target)

def presentEntries(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<T.Nullable<String>>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, T.PresentValue{value}} <> presentEntries(rest)

def fromRecord(record: R.Record<String>) -> T.ProviderHeaders():
  R.Record{presentEntries(R.entries(String, record))}

def overlayStrings(target: T.ProviderHeaders(), source: Maybe<&2, R.Record<String>>) -> T.ProviderHeaders():
  match source:
    case None{}: target
    case Some{record}: overlay(target, Some{fromRecord(record)})

# Configuration values replace earlier HTTP values case-insensitively. Null
# removes an inherited header; empty strings are replacements, not removals.
def applyValue(headers: H.Headers, name: String, value: T.Nullable<String>) -> Result<&2, &2, Field.HeaderHeaderError, H.Headers>:
  match value:
    case T.NullValue{}: H.delete(headers, name)
    case T.PresentValue{text}: H.set(headers, name, text)

def applyEntries(entries: List<&2, R.Property<T.Nullable<String>>>, result: Result<&2, &2, Field.HeaderHeaderError, H.Headers>) -> Result<&2, &2, Field.HeaderHeaderError, H.Headers>:
  match entries result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{headers}: Done{headers}
    case R.Property{name, value} <> rest Done{headers}: applyEntries(rest, applyValue(headers, name, value))

def apply(headers: H.Headers, configuration: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, Field.HeaderHeaderError, H.Headers>:
  match configuration:
    case None{}: Done{headers}
    case Some{R.Record{entries}}: applyEntries(entries, Done{headers})
