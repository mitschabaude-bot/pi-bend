import Base
import ./schema-value.bend as V
import ./record.bend as R
import ./uri-component.bend as Uri

# A pointer is a value: its decoded segments retain empty names and literal
# slashes. Reading traverses only explicit dictionary fields and list elements.
type Pointer is Data:
  Pointer{segments: List<&2, String>}

def unescape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{126}, SCon{Chr{49}, rest}}: SCon{Chr{47}, unescape(rest)}
    case SCon{Chr{126}, SCon{Chr{48}, rest}}: SCon{Chr{126}, unescape(rest)}
    case SCon{char, rest}: SCon{char, unescape(rest)}

def segments(text: String, current: String, reversed: List<&2, String>) -> List<&2, String>:
  match text:
    case SNil{}: List.reverse(&2, String, unescape(String.reverse(current)) <> reversed)
    case SCon{Chr{47}, rest}: segments(rest, "", unescape(String.reverse(current)) <> reversed)
    case SCon{char, rest}: segments(rest, SCon{char, current}, reversed)

def parse(text: String) -> Maybe<&2, Pointer>:
  match text:
    case SNil{}: Some{Pointer{Nil{}}}
    case SCon{Chr{47}, rest}: Some{Pointer{segments(rest, "", Nil{})}}
    case _: None{}

def decodedFragment(value: Maybe<&2, String>) -> Maybe<&2, Pointer>:
  match value:
    case None{}: None{}
    case Some{text}: parse(text)

# This accepts only local root/pointer fragments. Named anchors and external
# references require the schema resource resolver, not pointer traversal.
def parseFragment(text: String) -> Maybe<&2, Pointer>:
  match text:
    case SCon{Chr{35}, rest}: decodedFragment(Uri.decode(rest))
    case _: None{}

def arrayAt(values: List<&2, V.Value>, +key: String, +index: Nat) -> Maybe<&2, V.Value>:
  match values:
    case Nil{}: None{}
    case head <> rest:
      Bool.pick(Unit -> Maybe<&2, V.Value>, String.eq(key, Nat.show(index)),
        _ => Some{head}, _ => arrayAt(rest, key, index + 1n))(Unit{})

def field(value: V.Value, key: String) -> Maybe<&2, V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value, fields, key)
    case V.ArrayValue{values}: arrayAt(values, key, 0n)
    case _: None{}

def traverse(path: List<&2, String>, value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match path value:
    case _ None{}: None{}
    case Nil{} value: value
    case key <> rest Some{value}: traverse(rest, field(value, key))

def get(value: V.Value, pointer: Pointer) -> Maybe<&2, V.Value>:
  match pointer:
    case Pointer{path}: traverse(path, Some{value})

def escape(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{126}, rest}: "~0" ++ escape(rest)
    case SCon{Chr{47}, rest}: "~1" ++ escape(rest)
    case SCon{char, rest}: SCon{char, escape(rest)}

def renderedSegments(path: List<&2, String>) -> String:
  match path:
    case Nil{}: ""
    case head <> rest: "/" ++ escape(head) ++ renderedSegments(rest)

def render(pointer: Pointer) -> String:
  match pointer:
    case Pointer{path}: renderedSegments(path)
