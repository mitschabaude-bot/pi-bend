import Base
import ./http-header.bend as H
import ./record.bend as R

# Persistent server-side HTTP headers. Values retain append order; public
# iteration sorts names and coalesces values except for Set-Cookie.
type Headers is Data:
  Headers{fields: R.Record<List<&2, String>>}

def new() -> Headers: Headers{R.new(List<&2, String>)}

def extended(previous: Maybe<&2, List<&2, String>>, value: String) -> List<&2, String>:
  match previous:
    case None{}: value <> Nil{}
    case Some{values}: List.append(&2, String, values, value <> Nil{})

def appendChecked(headers: Headers, field: Result<&2, &2, H.HeaderError, H.Header>) -> Result<&2, &2, H.HeaderError, Headers>:
  match headers field:
    case Headers{+fields} Done{H.Header{+name, value}}:
      Done{Headers{R.set(List<&2, String>, fields, name, extended(R.get(List<&2, String>, fields, name), value))}}
    case _ Fail{error}: Fail{error}

def append(headers: Headers, name: String, value: String) -> Result<&2, &2, H.HeaderError, Headers>:
  appendChecked(headers, H.normalize(name, value))

def setChecked(headers: Headers, field: Result<&2, &2, H.HeaderError, H.Header>) -> Result<&2, &2, H.HeaderError, Headers>:
  match headers field:
    case Headers{fields} Done{H.Header{name, value}}:
      Done{Headers{R.set(List<&2, String>, fields, name, value <> Nil{})}}
    case _ Fail{error}: Fail{error}

def set(headers: Headers, name: String, value: String) -> Result<&2, &2, H.HeaderError, Headers>:
  setChecked(headers, H.normalize(name, value))

def deleteChecked(headers: Headers, name: Result<&2, &2, H.HeaderError, String>) -> Result<&2, &2, H.HeaderError, Headers>:
  match headers name:
    case Headers{fields} Done{key}: Done{Headers{R.remove(List<&2, String>, fields, key)}}
    case _ Fail{error}: Fail{error}

def delete(headers: Headers, name: String) -> Result<&2, &2, H.HeaderError, Headers>:
  deleteChecked(headers, H.normalizeName(name))

def joined(values: Maybe<&2, List<&2, String>>) -> Maybe<&2, String>:
  match values:
    case None{}: None{}
    case Some{items}: Some{String.join(items, ", ")}

def getChecked(headers: Headers, name: Result<&2, &2, H.HeaderError, String>) -> Result<&2, &2, H.HeaderError, Maybe<&2, String>>:
  match headers name:
    case Headers{fields} Done{key}: Done{joined(R.get(List<&2, String>, fields, key))}
    case _ Fail{error}: Fail{error}

def get(headers: Headers, name: String) -> Result<&2, &2, H.HeaderError, Maybe<&2, String>>:
  getChecked(headers, H.normalizeName(name))

def found(result: Result<&2, &2, H.HeaderError, Maybe<&2, String>>) -> Result<&2, &2, H.HeaderError, Bool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{False{}}
    case Done{Some{_}}: Done{True{}}

def has(headers: Headers, name: String) -> Result<&2, &2, H.HeaderError, Bool>:
  found(get(headers, name))

def valuesOrEmpty(values: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match values:
    case None{}: Nil{}
    case Some{items}: items

def getSetCookie(headers: Headers) -> List<&2, String>:
  match headers:
    case Headers{fields}: valuesOrEmpty(R.get(List<&2, String>, fields, "set-cookie"))

def ordered(result: (String & String) & Cmp) -> Bool:
  match result:
    case (_, order): Bool.not(Cmp.is_gt(order))

def nameOrder(left: R.Property<List<&2, String>>, right: R.Property<List<&2, String>>) -> Bool:
  match left right:
    case R.Property{a, _} R.Property{b, _}:
      ordered(String.cmp(a, b))

def cookieEntries(values: List<&2, String>) -> List<&2, H.Header>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: H.Header{"set-cookie", value} <> cookieEntries(rest)

def fieldEntries(cookie: Bool, name: String, values: List<&2, String>) -> List<&2, H.Header>:
  match cookie:
    case True{}: cookieEntries(values)
    case False{}: H.Header{name, String.join(values, ", ")} <> Nil{}

def combined(fields: List<&2, R.Property<List<&2, String>>>) -> List<&2, H.Header>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+name, values} <> rest:
      List.append(&2, H.Header, fieldEntries(String.eq(name, "set-cookie"), name, values), combined(rest))

def entries(headers: Headers) -> List<&2, H.Header>:
  match headers:
    case Headers{fields}: combined(List.sort(~R.Property<List<&2, String>>, ~nameOrder, R.entries(List<&2, String>, fields)))
