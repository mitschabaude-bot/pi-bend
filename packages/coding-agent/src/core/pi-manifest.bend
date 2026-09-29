import Base
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf8.bend as Utf8

# package.json's pi field is the package's declared resource list. A missing
# or malformed field is absent; an empty array is an explicit empty list.
type PiManifest is Data:
  PiManifest{extensions: Maybe<&2, List<&2, String>>, skills: Maybe<&2, List<&2, String>>, prompts: Maybe<&2, List<&2, String>>, themes: Maybe<&2, List<&2, String>>}

def stringTail(value: String, tail: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match tail:
    case Some{later}: Some{value <> later}
    case None{}: None{}
def strings(values: List<&2, V.Value>) -> Maybe<&2, List<&2, String>>:
  match values:
    case Nil{}: Some{Nil{}}
    case V.Text{value} <> rest: stringTail(value, strings(rest))
    case _: None{}
def fieldValue(found: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, String>>:
  match found:
    case Some{V.ArrayValue{values}}: strings(values)
    case _: None{}
def field(fields: R.Record<V.Value>, name: String) -> Maybe<&2, List<&2, String>>:
  fieldValue(R.get(V.Value, fields, name))
def manifestFields(+fields: R.Record<V.Value>) -> PiManifest:
  PiManifest{field(fields, "extensions"), field(fields, "skills"), field(fields, "prompts"), field(fields, "themes")}
def piValue(found: Maybe<&2, V.Value>) -> Maybe<&2, PiManifest>:
  match found:
    case Some{V.ObjectValue{fields}}: Some{manifestFields(fields)}
    case _: None{}
def manifest(value: V.Value) -> Maybe<&2, PiManifest>:
  match value:
    case V.ObjectValue{fields}: piValue(R.get(V.Value, fields, "pi"))
    case _: None{}
def parsed(result: Result<&2, &2, Json.ParseError, V.Value>) -> Maybe<&2, PiManifest>:
  match result:
    case Done{value}: manifest(value)
    case Fail{_}: None{}
def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{feff}', rest}: rest
    case other: other
def bytes(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, PiManifest>:
  match result:
    case Done{data}: parsed(Json.parse(stripBom(Utf8.decodeBuffer(data))))
    case Fail{_}: None{}
def readPiManifest(path: String) -> IO(Maybe<&2, PiManifest>):
  do IO<Maybe<&2, PiManifest>>:
    content : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return bytes(content)

def extensions(value: PiManifest) -> Maybe<&2, List<&2, String>>:
  match value:
    case PiManifest{extensions, _, _, _}: extensions
def skills(value: PiManifest) -> Maybe<&2, List<&2, String>>:
  match value:
    case PiManifest{_, skills, _, _}: skills
def prompts(value: PiManifest) -> Maybe<&2, List<&2, String>>:
  match value:
    case PiManifest{_, _, prompts, _}: prompts
def themes(value: PiManifest) -> Maybe<&2, List<&2, String>>:
  match value:
    case PiManifest{_, _, _, themes}: themes
