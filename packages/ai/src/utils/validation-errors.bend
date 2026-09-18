import Base
import ../../../runtime/src/schema.bend as Schema
import ../../../runtime/src/schema-errors.bend as Native
import ../../../runtime/src/big-nat.bend as B
import ../../../runtime/src/f64-decimal.bend as Decimal
import ../../../runtime/src/number-string.bend as NumberString
import ./json.bend as Json
import ./schema-json.bend as SchemaJson
import ../../../runtime/src/schema-value.bend as V

# Only required-property failures alter pi's displayed instance path. Keep that
# distinction typed, rather than probing an arbitrary error-parameters object.
type Location is Data:
  Instance{path: String}
  Required{path: String, missing: List<&2, String>}

type Issue is Data:
  Issue{location: Location, message: String}

def trimLeadingSlash(path: String) -> String:
  match path:
    case SCon{Chr{47}, rest}: rest
    case other: other

def dotted(path: String) -> String:
  match path:
    case SNil{}: SNil{}
    case SCon{Chr{47}, rest}: SCon{Chr{46}, dotted(rest)}
    case SCon{head, rest}: SCon{head, dotted(rest)}

def rootPath(+path: String) -> String:
  Bool.pick(String, String.is_empty(path), "root", path)

def requiredPath(+path: String, missing: List<&2, String>) -> String:
  match missing:
    case Nil{}: rootPath(path)
    case +key <> _: Bool.pick(String, String.is_empty(key), rootPath(path), Bool.pick(String, String.is_empty(path), key, path ++ "." ++ key))

def formatValidationPath(location: Location) -> String:
  match location:
    case Instance{path}: rootPath(dotted(trimLeadingSlash(path)))
    case Required{path, missing}: requiredPath(dotted(trimLeadingSlash(path)), missing)

def lines(issues: List<&2, Issue>) -> List<&2, String>:
  match issues:
    case Nil{}: Nil{}
    case Issue{location, message} <> rest: ("  - " ++ formatValidationPath(location) ++ ": " ++ message) <> lines(rest)

def errorList(issues: List<&2, Issue>) -> String:
  match issues:
    case Nil{}: "Unknown validation error"
    case head <> rest: String.join(lines(head <> rest), "\n")

def rendered(name: String, issues: List<&2, Issue>, received: Maybe<&2, String>) -> Maybe<&2, String>:
  match received:
    case None{}: None{}
    case Some{json}: Some{"Validation failed for tool \"" ++ name ++ "\":\n" ++ errorList(issues) ++ "\n\nReceived arguments:\n" ++ json}

# Diagnostic rendering is separate from issue collection. The original call
# arguments, not their coerced replacement, belong in this message.
def formatValidationFailure(name: String, received: V.Value, issues: List<&2, Issue>) -> Maybe<&2, String>:
  rendered(name, issues, Json.stringifyPretty(SchemaJson.toJson(received)))

def formatToolNotFound(name: String) -> String:
  "Tool \"" ++ name ++ "\" not found"

# Native schema reasons are translated here, at the AI library boundary. The
# runtime checker has no dependency on English text or tool-call formatting.
def typeName(kind: Schema.JsonType) -> String:
  match kind:
    case Schema.NullType{}: "null"
    case Schema.BooleanType{}: "boolean"
    case Schema.NumberType{}: "number"
    case Schema.IntegerType{}: "integer"
    case Schema.StringType{}: "string"
    case Schema.ArrayType{}: "array"
    case Schema.ObjectType{}: "object"

def typeNames(kinds: List<&2, Schema.JsonType>) -> List<&2, String>:
  match kinds:
    case Nil{}: Nil{}
    case kind <> rest: typeName(kind) <> typeNames(rest)

def instancePath(segments: List<&2, String>) -> String:
  match segments:
    case Nil{}: ""
    case first <> rest: "/" ++ String.join(first <> rest, "/")

def simple(path: String, message: String) -> Maybe<&2, List<&2, Issue>>:
  Some{Issue{Instance{path}, message} <> Nil{}}

def numericText(path: String, prefix: String, suffix: String, rendered: Maybe<&2, String>) -> Maybe<&2, List<&2, Issue>>:
  match rendered:
    case None{}: None{}
    case Some{number}: simple(path, prefix ++ number ++ suffix)

def combine(left: Maybe<&2, List<&2, Issue>>, right: Maybe<&2, List<&2, Issue>>) -> Maybe<&2, List<&2, Issue>>:
  match left right:
    case Some{a} Some{b}: Some{List.append(&2, Issue, a, b)}
    case _ _: None{}

def countBound(valid: Bool, path: String, prefix: String, limit: B.BigNat, suffix: String) -> Maybe<&2, List<&2, Issue>>:
  match valid:
    case True{}: Some{Nil{}}
    case False{}: numericText(path, prefix, suffix, Decimal.toDecimal(NumberString.toNumber(B.toDecimal(limit))))

def maximumCount(actual: B.BigNat, maximum: Maybe<&2, B.BigNat>, path: String, suffix: String) -> Maybe<&2, List<&2, Issue>>:
  match maximum:
    case None{}: Some{Nil{}}
    case Some{+limit}: countBound(Cmp.is_le(B.compare(actual, limit)), path, "must not have more than ", limit, suffix)

def countIssues(+array: Bool, +actual: B.BigNat, bounds: Schema.CountBounds, +path: String) -> Maybe<&2, List<&2, Issue>>:
  match bounds:
    case Schema.CountBounds{+minimum, maximum}:
      +suffix = Bool.pick(String, array, " items", " properties")
      +low = countBound(Cmp.is_ge(B.compare(actual, minimum)), path, "must not have fewer than ", minimum, suffix)
      +high = maximumCount(actual, maximum, path, suffix)
      Bool.pick(Maybe<&2, List<&2, Issue>>, array, combine(high, low), combine(low, high))

def nativeIssue(path: String, reason: Native.Reason) -> Maybe<&2, List<&2, Issue>>:
  match reason:
    case Native.Rejected{}: simple(path, "schema is false")
    case Native.ExpectedType{expected}: simple(path, "must be " ++ typeName(expected))
    case Native.ExpectedTypes{expected}: simple(path, "must be either " ++ String.join(typeNames(expected), " or "))
    case Native.ExpectedConstant{_}: simple(path, "must be equal to constant")
    case Native.ExpectedEnumeration{_}: simple(path, "must be equal to one of the allowed values")
    case Native.MissingFields{+keys}: Some{Issue{Required{path, keys}, "must have required properties " ++ String.join(keys, ", ")} <> Nil{}}
    case Native.AdditionalFields{_}: simple(path, "must not have additional properties")
    case Native.NumericMinimum{limit, inclusive}: numericText(path, Bool.pick(String, inclusive, "must be >= ", "must be > "), "", Decimal.toDecimal(limit))
    case Native.NumericMaximum{limit, inclusive}: numericText(path, Bool.pick(String, inclusive, "must be <= ", "must be < "), "", Decimal.toDecimal(limit))
    case Native.ItemCount{actual, bounds}: countIssues(True{}, actual, bounds, path)
    case Native.PropertyCount{actual, bounds}: countIssues(False{}, actual, bounds, path)
    # This is the pinned dependency's literal message for each contains keyword,
    # including explicit min/max bounds. Preserve the public diagnostic text.
    case Native.ContainsCount{_, _}: simple(path, "must contain at least 1 valid item")
    case Native.NoAlternative{}: simple(path, "must match a schema in anyOf")
    case Native.ExclusiveAlternatives{_}: simple(path, "must match exactly one schema in oneOf")
    case Native.NegatedSchema{}: simple(path, "must not be valid")

def fromNative(issues: List<&2, Native.Issue>) -> Maybe<&2, List<&2, Issue>>:
  match issues:
    case Nil{}: Some{Nil{}}
    case Native.Issue{path, reason} <> rest: combine(nativeIssue(instancePath(path), reason), fromNative(rest))

# Pi uses TypeBox's default error-context capacity. Keep that presentation
# policy out of the reusable runtime checker.
def issueLimit() -> Nat: 8n

def firstIssues(issues: List<&2, Issue>, limit: Nat) -> List<&2, Issue>:
  match issues limit:
    case _ Zero{}: Nil{}
    case Nil{} _: Nil{}
    case head <> rest Succ{limit}: head <> firstIssues(rest, limit)

def renderedNative(name: String, received: V.Value, issues: Maybe<&2, List<&2, Issue>>) -> Maybe<&2, String>:
  match issues:
    case None{}: None{}
    case Some{issues}: formatValidationFailure(name, received, firstIssues(issues, issueLimit()))

def formatNativeValidationFailure(name: String, received: V.Value, issues: List<&2, Native.Issue>) -> Maybe<&2, String>:
  renderedNative(name, received, fromNative(issues))
