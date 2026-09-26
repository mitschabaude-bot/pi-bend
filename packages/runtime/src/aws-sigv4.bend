import Base
import ./hmac-sha256.bend as HMAC
import ./sha256.bend as SHA
import ./utf8.bend as Utf8
import ./text.bend as Space

# AWS Signature Version 4 request signing, as @smithy/signature-v4 5.7
# signRequest computes it: x-amz-date, the session token, the payload hash
# header, the canonical request over the signable headers and the
# Authorization header.

type Credentials is Data:
  Credentials{accessKeyId: String, secretAccessKey: String, sessionToken: Maybe<&2, String>}

type Field is Data:
  Field{name: String, value: String}

# The request as sent: the path is already percent-encoded.
type Request is Data:
  Request{method: String, path: String, query: List<&2, Field>, headers: List<&2, Field>, body: List<&2, U32>}

def hexDigit(+value: U32) -> Char:
  Bool.pick(Char, U32.is_lt(value, 10), Chr{(48 + value : U32)}, Chr{(87 + value : U32)})

def hexBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest: SCon{hexDigit(U32.shrn(byte, 4n)), SCon{hexDigit(U32.and(byte, 15)), hexBytes(rest)}}

def upperHex(+value: U32) -> Char:
  Bool.pick(Char, U32.is_lt(value, 10), Chr{(48 + value : U32)}, Chr{(55 + value : U32)})

def unreserved(+byte: U32) -> Bool:
  (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122)) || (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || U32.is_eq(byte, 45) || U32.is_eq(byte, 95) || U32.is_eq(byte, 46) || U32.is_eq(byte, 126)

def escapedBytes(bytes: List<&2, U32>) -> String:
  match bytes:
    case Nil{}: ""
    case +byte <> rest:
      +tail = escapedBytes(rest)
      Bool.pick(String, unreserved(byte), SCon{Chr{byte}, tail}, SCon{'%', SCon{upperHex(U32.shrn(byte, 4n)), SCon{upperHex(U32.and(byte, 15)), tail}}})

# @smithy/util-uri-escape escapeUri: encodeURIComponent, also escaping !'()*.
def escapeUri(text: String) -> String: escapedBytes(Utf8.encode(text))

def digestHex(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> String:
  match result:
    case Done{digest}: hexBytes(SHA.toBytes(digest))
    case Fail{_}: ""

def digestBytes(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> List<&2, U32>:
  match result:
    case Done{digest}: SHA.toBytes(digest)
    case Fail{_}: Nil{}

def sha256Hex(bytes: List<&2, U32>) -> String: digestHex(SHA.digest(bytes))

def hmac(key: List<&2, U32>, text: String) -> List<&2, U32>: digestBytes(HMAC.digest(key, Utf8.encode(text)))

# getCanonicalPath with uriEscapePath: empty and "." segments dropped, ".."
# pops, then the (already encoded) path is escaped again, keeping slashes.
def segments(parts: List<&2, String>, kept: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: List.reverse(&2, String, kept)
    case SNil{} <> rest: segments(rest, kept)
    case "." <> rest: segments(rest, kept)
    case ".." <> rest: segments(rest, List.drop(&2, String, kept, 1n))
    case part <> rest: segments(rest, part <> kept)

def slashesKept(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'%', SCon{'2', SCon{'F', rest}}}: SCon{'/', slashesKept(rest)}
    case SCon{c, rest}: SCon{c, slashesKept(rest)}

def canonicalPath(+path: String) -> String:
  +kept = segments(String.split(path, '/'), Nil{})
  +leading = Bool.pick(String, String.starts_with(path, "/"), "/", "")
  +trailing = Bool.pick(String, Bool.not(List.is_empty(&2, String, kept)) && String.ends_with(path, "/"), "/", "")
  slashesKept(escapeUri(leading ++ String.join(kept, "/") ++ trailing))

def insertSorted(+item: String, sorted: List<&2, String>) -> List<&2, String>:
  match sorted:
    case Nil{}: item <> Nil{}
    case +head <> +rest: Bool.pick(List<&2, String>, String.is_lt(item, head) || String.eq(item, head), item <> head <> rest, head <> insertSorted(item, rest))

def sortStrings(items: List<&2, String>, sorted: List<&2, String>) -> List<&2, String>:
  match items:
    case Nil{}: sorted
    case item <> rest: sortStrings(rest, insertSorted(item, sorted))

def queryPairs(fields: List<&2, Field>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case Field{name, value} <> rest: (escapeUri(name) ++ "=" ++ escapeUri(value)) <> queryPairs(rest)

# getCanonicalQuery for single-valued parameters: escaped pairs, sorted.
def canonicalQuery(fields: List<&2, Field>) -> String: String.join(sortStrings(queryPairs(fields), Nil{}), "&")

def unsignable(+name: String) -> Bool:
  match name:
    case "authorization": True{}
    case "cache-control": True{}
    case "connection": True{}
    case "expect": True{}
    case "from": True{}
    case "keep-alive": True{}
    case "max-forwards": True{}
    case "pragma": True{}
    case "referer": True{}
    case "te": True{}
    case "trailer": True{}
    case "transfer-encoding": True{}
    case "upgrade": True{}
    case "user-agent": True{}
    case "x-amzn-trace-id": True{}
    case other: String.starts_with(other, "proxy-") || String.starts_with(other, "sec-")

# Whitespace runs become one space (`replace(/\s+/g, " ")`); each character
# chooses its branch lazily.
def collapsed(text: String, space: Bool) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> String, Space.whitespace(code), _ => Bool.pick(String, space, "", " ") ++ collapsed(rest, True{}), _ => SCon{Chr{code}, collapsed(rest, False{})})(Unit{})

def withoutName(fields: List<&2, Field>, +name: String) -> List<&2, Field>:
  match fields:
    case Nil{}: Nil{}
    case Field{+key, value} <> rest:
      +tail = withoutName(rest, name)
      Bool.pick(List<&2, Field>, String.eq(key, name), tail, Field{key, value} <> tail)

# getCanonicalHeaders: lower-cased names of the signable headers with their
# values trimmed and inner whitespace collapsed; later duplicates win.
def canonicalHeaders(fields: List<&2, Field>) -> List<&2, Field>:
  match fields:
    case Nil{}: Nil{}
    case Field{name, value} <> rest:
      +lower = String.to_lower(name)
      +tail = withoutName(canonicalHeaders(rest), lower)
      Bool.pick(List<&2, Field>, unsignable(lower), tail, Field{lower, collapsed(Space.trim(value), False{})} <> tail)

def insertField(+field: Field, sorted: List<&2, Field>) -> List<&2, Field>:
  match field sorted:
    case _ Nil{}: field <> Nil{}
    case Field{+name, +value} Field{+other, +otherValue} <> +rest: Bool.pick(List<&2, Field>, String.is_lt(name, other), Field{name, value} <> Field{other, otherValue} <> rest, Field{other, otherValue} <> insertField(Field{name, value}, rest))

def sortFields(fields: List<&2, Field>, sorted: List<&2, Field>) -> List<&2, Field>:
  match fields:
    case Nil{}: sorted
    case field <> rest: sortFields(rest, insertField(field, sorted))

def headerLines(fields: List<&2, Field>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case Field{name, value} <> rest: (name ++ ":" ++ value) <> headerLines(rest)

def headerNames(fields: List<&2, Field>) -> List<&2, String>:
  match fields:
    case Nil{}: Nil{}
    case Field{name, _} <> rest: name <> headerNames(rest)

def hasHeader(fields: List<&2, Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Field{key, _} <> rest: String.eq(String.to_lower(key), name) || hasHeader(rest, name)

def headerValue(fields: List<&2, Field>, +name: String) -> Maybe<&2, String>:
  match fields:
    case Nil{}: None{}
    case Field{+key, +value} <> rest: Bool.pick(Maybe<&2, String>, String.eq(String.to_lower(key), name), Some{value}, headerValue(rest, name))

def appendField(fields: List<&2, Field>, name: String, value: String) -> List<&2, Field>:
  List.append(&2, Field, fields, Field{name, value} <> Nil{})

def signingKey(secret: String, +shortDate: String, +region: String, +service: String) -> List<&2, U32>:
  hmac(hmac(hmac(hmac(Utf8.encode("AWS4" ++ secret), shortDate), region), service), "aws4_request")

type Signed is Data:
  Signed{headers: List<&2, Field>, canonicalRequest: String, stringToSign: String}

def compact(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'-', rest}: compact(rest)
    case SCon{':', rest}: compact(rest)
    case SCon{'.', SCon{_, SCon{_, SCon{_, rest}}}}: compact(rest)
    case SCon{c, rest}: SCon{c, compact(rest)}

# formatDate: the ISO timestamp without separators or milliseconds.
def amzDate(iso: String) -> String: compact(iso)

def signedWith(credentials: Credentials, +region: String, +service: String, +date: String, method: String, path: String, query: List<&2, Field>, +headers: List<&2, Field>, +payloadHash: String) -> Signed:
  match credentials:
    case Credentials{+accessKeyId, secret, _}:
      +shortDate = String.take(date, 8n)
      +scope = shortDate ++ "/" ++ region ++ "/" ++ service ++ "/aws4_request"
      +canonical = sortFields(canonicalHeaders(headers), Nil{})
      +signedNames = String.join(headerNames(canonical), ";")
      +canonicalRequest = method ++ "\n" ++ canonicalPath(path) ++ "\n" ++ canonicalQuery(query) ++ "\n" ++ String.join(headerLines(canonical), "\n") ++ "\n\n" ++ signedNames ++ "\n" ++ payloadHash
      +stringToSign = "AWS4-HMAC-SHA256\n" ++ date ++ "\n" ++ scope ++ "\n" ++ sha256Hex(Utf8.encode(canonicalRequest))
      +signature = hexBytes(hmac(signingKey(secret, shortDate, region, service), stringToSign))
      Signed{appendField(headers, "authorization", "AWS4-HMAC-SHA256 Credential=" ++ accessKeyId ++ "/" ++ scope ++ ", SignedHeaders=" ++ signedNames ++ ", Signature=" ++ signature), canonicalRequest, stringToSign}

def withToken(fields: List<&2, Field>, token: Maybe<&2, String>) -> List<&2, Field>:
  match token:
    case None{}: fields
    case Some{SNil{}}: fields
    case Some{value}: appendField(fields, "x-amz-security-token", value)

def tokenOf(credentials: Credentials) -> Maybe<&2, String>:
  match credentials:
    case Credentials{_, _, token}: token

# signRequest: `date` is the signing time as YYYYMMDDTHHMMSSZ.
def sign(+credentials: Credentials, region: String, service: String, +date: String, request: Request) -> Signed:
  match request:
    case Request{method, path, query, headers, body}:
      +dated = withToken(appendField(headers, "x-amz-date", date), tokenOf(credentials))
      +payloadHash = Maybe.default(&2, String, headerValue(dated, "x-amz-content-sha256"), sha256Hex(body))
      +hashed = Bool.pick(List<&2, Field>, hasHeader(dated, "x-amz-content-sha256"), dated, appendField(dated, "x-amz-content-sha256", payloadHash))
      signedWith(credentials, region, service, date, method, path, query, hashed, payloadHash)
