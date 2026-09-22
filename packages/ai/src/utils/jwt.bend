import Base
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/string.bend as Strings

# Unverified JWT payload reading, as upstream's decodeJwt/extractAccountId:
# the middle base64url segment parsed as JSON. No signature is checked; the
# token is only inspected for the account claim the Codex API needs.

def JWT_CLAIM_PATH() -> String: "https://api.openai.com/auth"

# JWT segments are base64url without padding; the decoder expects the
# standard alphabet.
def standardAlphabet(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{'-', rest}: SCon{'+', standardAlphabet(rest)}
    case SCon{'_', rest}: SCon{'/', standardAlphabet(rest)}
    case SCon{c, rest}: SCon{c, standardAlphabet(rest)}

def padding(remainder: Nat) -> String:
  match remainder:
    case 2n: "=="
    case 3n: "="
    case _: ""

def padded(+text: String) -> String:
  text ++ padding(Nat.mod(String.length(text), 4n))

def parsedJson(text: Result<&2, &2, Utf8.Error, String>) -> Maybe<&2, V.Value>:
  match text:
    case Fail{_}: None{}
    case Done{value}: Result.default(&2, &2, Json.ParseError, Maybe<&2, V.Value>, Result.map(&2, &2, Json.ParseError, V.Value, Maybe<&2, V.Value>, parsed => Some{parsed}, Json.parse(value)), None{})

def decodedJson(bytes: Result<&2, &2, Base64.Error, List<&2, U32>>) -> Maybe<&2, V.Value>:
  match bytes:
    case Fail{_}: None{}
    case Done{octets}: parsedJson(Utf8.decodeStrict(octets))

def payloadSegment(segments: List<&2, String>) -> Maybe<&2, String>:
  match segments:
    case _ <> payload <> _ <> Nil{}: Some{payload}
    case _: None{}

def decodeSegment(segment: Maybe<&2, String>) -> Maybe<&2, V.Value>:
  match segment:
    case None{}: None{}
    case Some{payload}: decodedJson(Base64.decode(padded(standardAlphabet(payload))))

def decode(token: String) -> Maybe<&2, V.Value>:
  decodeSegment(payloadSegment(Strings.split(token, '.')))

def nonemptyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{first, rest}}}: Some{SCon{first, rest}}
    case _: None{}

def claimField(claims: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match claims:
    case Some{V.ObjectValue{fields}}: nonemptyText(R.get(V.Value, fields, "chatgpt_account_id"))
    case _: None{}

def accountClaim(payload: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match payload:
    case Some{V.ObjectValue{fields}}: claimField(R.get(V.Value, fields, JWT_CLAIM_PATH()))
    case _: None{}

# The ChatGPT account id carried by an OpenAI Codex access token.
def chatgptAccountId(token: String) -> Maybe<&2, String>:
  accountClaim(decode(token))
