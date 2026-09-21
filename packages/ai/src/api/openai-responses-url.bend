import Base
import ../../../runtime/src/url-absolute.bend as Absolute
import ../../../runtime/src/url-record.bend as URL
import ../../../runtime/src/url-form.bend as Form
import ../../../runtime/src/url-form-strict.bend as Strict
import ../../../runtime/src/url-query-encode.bend as Encode
import ../../../runtime/src/record.bend as R

type Error is Data:
  InvalidURL{cause: Absolute.Error}
  InvalidQuery{cause: Strict.Error}

# Responses uses a fixed SDK resource path, not general relative resolution.
def suffix(base: String, reversed: String) -> String:
  match reversed:
    case SCon{'/', _}: base ++ "responses"
    case _: base ++ "/responses"

def address(+base: String) -> String: suffix(base, String.reverse(base))

# The SDK's query dictionary retains the last value of a repeated name.
# Persistent records retain ordinary insertion order, including numeric names.
def collect(tuples: List<&2, Form.Entry>, fields: R.Record<String>) -> R.Record<String>:
  match tuples:
    case Nil{}: fields
    case Form.Entry{name, value} <> rest: collect(rest, R.set(String, fields, name, value))

def encoded(properties: List<&2, R.Property<String>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: (Encode.encode(name) ++ "=" ++ Encode.encode(value)) <> encoded(rest)

def serialize(fields: R.Record<String>) -> String:
  String.join(encoded(R.entries(String, fields)), "&")

def withQuery(url: URL.URL, query: Maybe<&2, String>) -> URL.URL:
  match url:
    case URL.URL{scheme, username, password, host, port, path, _, fragment}: URL.URL{scheme, username, password, host, port, path, query, fragment}

def normalized(url: URL.URL, parsed: Result<&2, &2, Strict.Error, List<&2, Form.Entry>>) -> Result<&2, &2, Error, URL.URL>:
  match parsed:
    case Fail{cause}: Fail{InvalidQuery{cause}}
    case Done{Nil{}}: Done{url}
    case Done{tuples}: Done{withQuery(url, Some{serialize(collect(tuples, R.new(String)))})}

def queried(url: URL.URL, query: Maybe<&2, String>) -> Result<&2, &2, Error, URL.URL>:
  match query:
    case None{}: Done{url}
    case Some{text}: normalized(url, Strict.parse(text))

def parsed(result: Result<&2, &2, Absolute.Error, URL.URL>) -> Result<&2, &2, Error, URL.URL>:
  match result:
    case Fail{cause}: Fail{InvalidURL{cause}}
    case Done{URL.URL{scheme, username, password, host, port, path, +query, fragment}}:
      queried(URL.URL{scheme, username, password, host, port, path, query, fragment}, query)

# The URL parser receives its immutable Unicode/IDNA tables from the caller.
# Scheme/credentials/HTTP endpoint validation belongs to http-url.prepare.
def prepare(context: Absolute.Context, base: String) -> Result<&2, &2, Error, URL.URL>:
  parsed(Absolute.parse(context, address(base)))
