import Base
import ../../../runtime/src/yaml.bend as Yaml
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Space

type Frontmatter is Data:
  Frontmatter{frontmatter: R.Record<Yaml.Value>,body: String}
type Extracted is Data:
  Extracted{yaml: Maybe<&2,String>,body: String}
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
def withoutFirst(value: String) -> String:
  match value:
    case SCon{_,rest}: rest
    case SNil{}: ""

def yamlOf(value: String) -> Maybe<&2,String>:
  match value:
    case SNil{}: None{}
    case other: Some{other}

# upstream extractFrontmatter: after a leading "---", the YAML runs from
# offset 4 to the next "\n---" found from offset 3; the body is what follows
# that marker, trimmed. An empty YAML block counts as none.
def closing(+value: String,+before: String,original: String) -> Extracted:
  match value:
    case SNil{}: Extracted{None{},original}
    case SCon{char,rest}:
      Bool.pick(Unit -> Extracted,String.starts_with(value,"\n---"),
        _ => Extracted{yamlOf(withoutFirst(String.reverse(before))),Space.trim(String.drop(value,4n))},
        _ => closing(rest,SCon{char,before},original))(Unit{})
def opening(+value: String) -> Extracted:
  Bool.pick(Unit -> Extracted,String.starts_with(value,"---"),_ => closing(String.drop(value,3n),"",value),_ => Extracted{None{},value})(Unit{})
def extractFrontmatter(+content: String) -> Extracted: opening(normalized(content))
# upstream casts any parsed YAML to the frontmatter object; a scalar or
# sequence has none of the keys consumers read, so it acts as an empty mapping.
def parsed(result: Yaml.ResultOf(Yaml.Value),body: String) -> Yaml.ResultOf(Frontmatter):
  match result:
    case Fail{cause}: Fail{cause}
    case Done{Yaml.Null{}}: Done{Frontmatter{R.new(Yaml.Value),body}}
    case Done{Yaml.Mapping{fields}}: Done{Frontmatter{fields,body}}
    case Done{_}: Done{Frontmatter{R.new(Yaml.Value),body}}
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
