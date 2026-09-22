import Base
import ../../../runtime/src/yaml.bend as Yaml
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Space

type Frontmatter is Data:
  Frontmatter{frontmatter: R.Record<Yaml.Value>,body: String}
type Extracted is Data:
  Extracted{yaml: Maybe<&2,String>,body: String}
def trimStart(value: String) -> String:
  match value:
    case SNil{}: ""
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,Space.whitespace(Char.to_u32(char)),_ => trimStart(rest),_ => SCon{char,rest})(Unit{})
def trim(value: String) -> String: String.reverse(trimStart(String.reverse(trimStart(value))))
def newlines(value: String,reversed: String,afterCR: Bool) -> String:
  match value:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}:
      +reversed = reversed
      newlines(rest,Bool.pick(String,Char.is_eq(char,'\n') && afterCR,reversed,SCon{Bool.pick(Char,Char.is_eq(char,'\r'),'\n',char),reversed}),Char.is_eq(char,'\r'))
def normalized(value: String) -> String:
  match value:
    case SCon{Chr{65279},rest}: newlines(rest,"",False{})
    case other: newlines(other,"",False{})
def closing(lines: List<&2,String>,yaml: List<&2,String>,original: String) -> Extracted:
  match lines:
    case Nil{}: Extracted{None{},original}
    case "---" <> rest: Extracted{Some{String.join(List.reverse(&2,String,yaml),"\n")},trim(String.join(rest,"\n"))}
    case line <> rest: closing(rest,line <> yaml,original)
def opening(lines: List<&2,String>,original: String) -> Extracted:
  match lines:
    case "---" <> rest: closing(rest,Nil{},original)
    case _: Extracted{None{},original}
def extractFrontmatter(+content: String) -> Extracted:
  +value = normalized(content)
  opening(Strings.split(value,'\n'),value)
def parsed(result: Yaml.ResultOf(Yaml.Value),body: String) -> Yaml.ResultOf(Frontmatter):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Yaml.Null{}}: Done{Frontmatter{R.new(Yaml.Value),body}}
    case Done{Yaml.Mapping{fields}}: Done{Frontmatter{fields,body}}
    case Done{_}: Fail{Yaml.Error{1n,1n,"Frontmatter must be a mapping"}}
def fromExtracted(value: Extracted) -> Yaml.ResultOf(Frontmatter):
  match value:
    case Extracted{None{},body}: Done{Frontmatter{R.new(Yaml.Value),body}}
    case Extracted{Some{yaml},body}: parsed(Yaml.parse(yaml),body)
def parseFrontmatter(content: String) -> Yaml.ResultOf(Frontmatter): fromExtracted(extractFrontmatter(content))
def bodyOf(result: Yaml.ResultOf(Frontmatter)) -> Yaml.ResultOf(String):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Frontmatter{_,body}}: Done{body}
def stripFrontmatter(content: String) -> Yaml.ResultOf(String): bodyOf(parseFrontmatter(content))
