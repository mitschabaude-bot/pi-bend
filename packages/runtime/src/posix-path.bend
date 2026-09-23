import Base
import ./string.bend as Strings

# Lexical POSIX resolution, independent of filesystem symlinks. A caller must
# supply an absolute cwd; None rejects an invalid base for a relative input.
def isAbsolute(path: String) -> Bool:
  match path:
    case SCon{'/', _}: True{}
    case _: False{}

def components(parts: List<&2, String>, reversed: List<&2, String>, +root: Bool) -> List<&2, String>:
  match parts reversed:
    case Nil{} previous: previous
    case "" <> rest previous: components(rest, previous, root)
    case "." <> rest previous: components(rest, previous, root)
    case ".." <> rest Nil{}: components(rest, Bool.pick(List<&2, String>, root, Nil{}, ".." <> Nil{}), root)
    case ".." <> rest ".." <> previous: components(rest, ".." <> ".." <> previous, root)
    case ".." <> rest _ <> previous: components(rest, previous, root)
    case name <> rest previous: components(rest, name <> previous, root)

def absolute(parts: List<&2, String>) -> String:
  "/" ++ String.join(List.reverse(&2, String, components(parts, Nil{}, True{})), "/")

def under(base: String, path: String) -> Maybe<&2, String>:
  match base:
    case SCon{'/', rest}: Some{absolute(Strings.split(rest ++ "/" ++ path, '/'))}
    case _: None{}

def resolve(base: String, path: String) -> Maybe<&2, String>:
  match path:
    case SCon{'/', rest}: Some{absolute(Strings.split(rest, '/'))}
    case value: under(base, value)

def common(a: List<&2, String>, b: List<&2, String>) -> List<&2, String> & List<&2, String>:
  match a b:
    case +first <> +restA +second <> +restB:
      Bool.pick(Unit -> List<&2, String> & List<&2, String>, Strings.equal(first, second), _ => common(restA, restB), _ => (first <> restA, second <> restB))(Unit{})
    case a b: (a, b)

def parents(parts: List<&2, String>, tail: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: tail
    case _ <> rest: parents(rest, ".." <> tail)

def relativeParts(pair: List<&2, String> & List<&2, String>) -> String:
  match pair:
    case (left, right): String.join(parents(left, right), "/")

# Node's path.relative for absolute paths: the way from one to the other.
def relative(+from: String, +to: String) -> String:
  relativeParts(common(List.reverse(&2, String, components(Strings.split(from, '/'), Nil{}, True{})), List.reverse(&2, String, components(Strings.split(to, '/'), Nil{}, True{}))))

# POSIX normalize/join retain relative parent components and trailing slashes.
def rendered(parts: List<&2, String>, root: Bool, trailing: Bool) -> String:
  match parts root:
    case Nil{} True{}: "/"
    case Nil{} False{}: Bool.pick(String, trailing, "./", ".")
    case values absolutePath: Bool.pick(String, absolutePath, "/", "") ++ String.join(values, "/") ++ Bool.pick(String, trailing, "/", "")

def normalize(+path: String) -> String:
  rendered(List.reverse(&2, String, components(Strings.split(path, '/'), Nil{}, isAbsolute(path))), isAbsolute(path), String.ends_with(path, "/"))

def join(left: String, right: String) -> String:
  match left right:
    case "" value: normalize(value)
    case value "": normalize(value)
    case a b: normalize(a ++ "/" ++ b)
