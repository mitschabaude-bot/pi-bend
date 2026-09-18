import Base
import ../utils/hash.bend as Hash
import ../types.bend as T
import ./transform-messages.bend as Transform

# Provider IDs use an ASCII wire alphabet. A supplementary scalar occupies two
# UTF-16 units, so it replaces two disallowed units before the 64-unit cap.
def allowed(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 95) || U32.is_eq(code, 45)

def replacement(+code: U32) -> String:
  Bool.pick(String, allowed(code), SCon{Chr{code}, SNil{}}, Bool.pick(String, U32.is_gt(code, 65535), "__", "_"))

def sanitize(part: String) -> String:
  match part:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: replacement(code) ++ sanitize(rest)

def dropUnderscores(text: String) -> String:
  match text:
    case SCon{'_', rest}: dropUnderscores(rest)
    case other: other

def normalizeIdPart(part: String) -> String:
  String.reverse(dropUnderscores(String.reverse(String.take(sanitize(part), 64n))))

def buildForeignResponsesItemId(itemId: String) -> String:
  "fc_" ++ Hash.shortHash(itemId)

def firstPart(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'|', _}: String.reverse(reversed)
    case SCon{char, rest}: firstPart(rest, SCon{char, reversed})

type IdParts is Data:
  IdParts{call: String, item: String}

def splitId(text: String, reversed: String) -> Maybe<&2, IdParts>:
  match text:
    case SNil{}: None{}
    case SCon{'|', rest}: Some{IdParts{String.reverse(reversed), firstPart(rest, "")}}
    case SCon{char, rest}: splitId(rest, SCon{char, reversed})

def fcPrefix(text: String) -> Bool:
  match text:
    case SCon{'f', SCon{'c', SCon{'_', _}}}: True{}
    case _: False{}

def normalizedItem(foreign: Bool, item: String) -> String:
  match foreign:
    case True{}: buildForeignResponsesItemId(item)
    case False{}: normalizeIdPart(item)

def withPrefix(+item: String) -> String:
  Bool.pick(String, fcPrefix(item), item, normalizeIdPart("fc_" ++ item))

def normalizeSplit(split: Maybe<&2, IdParts>, original: String, foreign: Bool) -> String:
  match split:
    case None{}: normalizeIdPart(original)
    case Some{IdParts{call, item}}: normalizeIdPart(call) ++ "|" ++ withPrefix(normalizedItem(foreign, item))

def contains(providers: List<&2, String>, +provider: String) -> Bool:
  match providers:
    case Nil{}: False{}
    case head <> rest: String.eq(head, provider) || contains(rest, provider)

def normalizeAllowed(keepComposite: Bool, +id: String, foreign: Bool) -> String:
  match keepComposite:
    case False{}: normalizeIdPart(id)
    case True{}: normalizeSplit(splitId(id, ""), id, foreign)

def normalizeFor(id: String, +targetProvider: String, targetApi: String, sourceProvider: String, sourceApi: String, allowedProviders: List<&2, String>) -> String:
  normalizeAllowed(contains(allowedProviders, targetProvider), id, Bool.not(String.eq(targetProvider, sourceProvider) && String.eq(targetApi, sourceApi)))

def normalizeToolCallId(-A: Data, -G: Data, id: String, target: Transform.Target, source: T.AssistantMessage<A, G>, allowedProviders: List<&2, String>) -> String:
  match target source:
    case Transform.Target{api, provider, _} T.AssistantMessage{_, sourceApi, sourceProvider, _, _, _, _, _, _, _, _, _, _, _, _}: normalizeFor(id, provider, api, sourceProvider, sourceApi, allowedProviders)
