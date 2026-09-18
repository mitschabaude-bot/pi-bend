import Base
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
