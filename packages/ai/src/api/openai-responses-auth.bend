import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/http-header.bend as Header
import ../../../runtime/src/text-space.bend as Space

type CredentialError is Data:
  MissingApiKey{provider: String}

def errorMessage(error: CredentialError) -> String:
  match error:
    case MissingApiKey{provider}: "No API key for provider: " ++ provider

def nonblank(value: T.Nullable<String>) -> Bool:
  match value:
    case T.NullValue{}: False{}
    case T.PresentValue{text}: Bool.not(Space.blank(text))

# HTTP names are ASCII. Configuration values remain unnormalized here: this
# credential check precedes the transport's header validation.
def matchingHeader(entries: List<&2, R.Property<T.Nullable<String>>>, +name: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case R.Property{key, value} <> rest:
      (String.eq(Header.lowercase(key), name) && nonblank(value)) || matchingHeader(rest, name)

def hasHeader(headers: Maybe<&2, T.ProviderHeaders()>, name: String) -> Bool:
  match headers:
    case None{}: False{}
    case Some{R.Record{entries}}: matchingHeader(entries, Header.lowercase(name))

def headerCredential(provider: String, +headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, CredentialError, String>:
  authorized = hasHeader(headers, "authorization") || hasHeader(headers, "cf-aig-authorization")
  Bool.pick(Result<&2, &2, CredentialError, String>, authorized, Done{"unused"}, Fail{MissingApiKey{provider}})

def getClientApiKey(provider: String, apiKey: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>) -> Result<&2, &2, CredentialError, String>:
  match apiKey:
    case None{}: headerCredential(provider, headers)
    case Some{SNil{}}: headerCredential(provider, headers)
    case Some{text}: Done{text}
