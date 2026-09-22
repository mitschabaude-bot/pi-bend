import Base
import ./string.bend as Strings

# Lexical POSIX resolution, independent of filesystem symlinks. A caller must
# supply an absolute cwd; None rejects an invalid base for a relative input.
def isAbsolute(path: String) -> Bool:
  match path:
    case SCon{'/',_}: True{}
    case _: False{}

def components(parts: List<&2,String>, reversed: List<&2,String>) -> List<&2,String>:
  match parts reversed:
    case Nil{} previous: previous
    case "" <> rest previous: components(rest,previous)
    case "." <> rest previous: components(rest,previous)
    case ".." <> rest Nil{}: components(rest,Nil{})
    case ".." <> rest _ <> previous: components(rest,previous)
    case name <> rest previous: components(rest,name <> previous)

def absolute(parts: List<&2,String>) -> String:
  "/" ++ String.join(List.reverse(&2,String,components(parts,Nil{})),"/")

def relative(base: String, path: String) -> Maybe<&2,String>:
  match base:
    case SCon{'/',rest}: Some{absolute(Strings.split(rest ++ "/" ++ path,'/'))}
    case _: None{}

def resolve(base: String, path: String) -> Maybe<&2,String>:
  match path:
    case SCon{'/',rest}: Some{absolute(Strings.split(rest,'/'))}
    case value: relative(base,value)
