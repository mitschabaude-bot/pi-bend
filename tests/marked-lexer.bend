import Base
import ../packages/runtime/src/marked/tokens.bend as T
import ../packages/runtime/src/marked/lexer.bend as Lexer
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R

# The marked port's tokens against marked 18.0.11's Lexer
# (tests/marked_lexer_check.py): each line of build/marked-lexer/cases.jsonl
# holds a Markdown source; its tokens print as one JSON array per line with
# the fields of tokens.bend (absent optional fields as null).

def str(value: String) -> String: Json.quote(value)
def optional(value: Maybe<&2,String>) -> String:
  match value:
    case Some{found}: Json.quote(found)
    case None{}: "null"
def flag(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"
def optionalFlag(value: Maybe<&2,Bool>) -> String:
  match value:
    case Some{found}: flag(found)
    case None{}: "null"
def optionalNat(value: Maybe<&2,Nat>) -> String:
  match value:
    case Some{found}: Nat.show(found)
    case None{}: "null"
def align(value: Maybe<&2,T.Align>) -> String:
  match value:
    case Some{T.AlignLeft{}}: "\"left\""
    case Some{T.AlignCenter{}}: "\"center\""
    case Some{T.AlignRight{}}: "\"right\""
    case None{}: "null"
def aligns(values: List<&2,Maybe<&2,T.Align>>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: align(value) <> aligns(rest)
def object(fields: List<&2,String>) -> String: "{" ++ String.join(fields,",") ++ "}"
def field(name: String,value: String) -> String: Json.quote(name) ++ ":" ++ value
def array(items: List<&2,String>) -> String: "[" ++ String.join(items,",") ++ "]"
def kind(name: String) -> String: field("type",Json.quote(name))
def rowLengths(rows: List<&2,List<&2,T.Token<Unit>>>) -> List<&2,Nat>:
  match rows:
    case Nil{}: Nil{}
    case row <> rest: List.length(&2,T.Token<Unit>,row) <> rowLengths(rest)
def rowArrays(lengths: List<&2,Nat>,+cells: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match lengths:
    case Nil{}: List.reverse(&2,String,reversed)
    case +length <> rest: rowArrays(rest,List.drop(&2,String,cells,length),array(List.take(&2,String,cells,length)) <> reversed)
# Tokens as JSON; table rows are arrays of cell tokens.
@unsafe def dump(tokens: List<&2,T.Token<Unit>>) -> List<&2,String>:
  match tokens:
    case Nil{}: Nil{}
    case T.Blockquote{raw,body,inner} <> rest: object([kind("blockquote"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Br{raw} <> rest: object([kind("br"),field("raw",str(raw))]) <> dump(rest)
    case T.Checkbox{raw,checked} <> rest: object([kind("checkbox"),field("raw",str(raw)),field("checked",flag(checked))]) <> dump(rest)
    case T.Code{raw,style,lang,body} <> rest: object([kind("code"),field("raw",str(raw)),field("codeBlockStyle",optional(style)),field("lang",optional(lang)),field("text",str(body))]) <> dump(rest)
    case T.Codespan{raw,body} <> rest: object([kind("codespan"),field("raw",str(raw)),field("text",str(body))]) <> dump(rest)
    case T.Def{raw,tag,href,title} <> rest: object([kind("def"),field("raw",str(raw)),field("tag",str(tag)),field("href",str(href)),field("title",optional(title))]) <> dump(rest)
    case T.Del{raw,body,inner} <> rest: object([kind("del"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Em{raw,body,inner} <> rest: object([kind("em"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Escape{raw,body} <> rest: object([kind("escape"),field("raw",str(raw)),field("text",str(body))]) <> dump(rest)
    case T.Heading{raw,depth,body,inner} <> rest: object([kind("heading"),field("raw",str(raw)),field("depth",Nat.show(depth)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Hr{raw} <> rest: object([kind("hr"),field("raw",str(raw))]) <> dump(rest)
    case T.HTML{raw,pre,body,block} <> rest: object([kind("html"),field("raw",str(raw)),field("pre",flag(pre)),field("text",str(body)),field("block",flag(block))]) <> dump(rest)
    case T.Image{raw,href,title,body,inner} <> rest: object([kind("image"),field("raw",str(raw)),field("href",str(href)),field("title",optional(title)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Link{raw,href,title,body,inner} <> rest: object([kind("link"),field("raw",str(raw)),field("href",str(href)),field("title",optional(title)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.ListToken{raw,ordered,start,loose,items} <> rest: object([kind("list"),field("raw",str(raw)),field("ordered",flag(ordered)),field("start",optionalNat(start)),field("loose",flag(loose)),field("items",array(dump(items)))]) <> dump(rest)
    case T.ListItem{raw,task,checked,loose,body,inner} <> rest: object([kind("list_item"),field("raw",str(raw)),field("task",flag(task)),field("checked",optionalFlag(checked)),field("loose",flag(loose)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Paragraph{raw,body,inner} <> rest: object([kind("paragraph"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Space{raw} <> rest: object([kind("space"),field("raw",str(raw))]) <> dump(rest)
    case T.Strong{raw,body,inner} <> rest: object([kind("strong"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner)))]) <> dump(rest)
    case T.Table{raw,columns,header,+rows} <> rest: object([kind("table"),field("raw",str(raw)),field("align",array(aligns(columns))),field("header",array(dump(header))),field("rows",array(rowArrays(rowLengths(rows),dump(List.concat(&2,T.Token<Unit>,rows)),Nil{})))]) <> dump(rest)
    case T.TableCell{body,inner,header,column} <> rest: object([field("text",str(body)),field("tokens",array(dump(inner))),field("header",flag(header)),field("align",align(column))]) <> dump(rest)
    case T.Tag{raw,inLink,inRawBlock,body,block} <> rest: object([kind("html"),field("raw",str(raw)),field("inLink",flag(inLink)),field("inRawBlock",flag(inRawBlock)),field("text",str(body)),field("block",flag(block))]) <> dump(rest)
    case T.Text{raw,body,inner,escaped} <> rest: object([kind("text"),field("raw",str(raw)),field("text",str(body)),field("tokens",array(dump(inner))),field("escaped",flag(escaped))]) <> dump(rest)
    case T.Generic{name,raw,_} <> rest: object([kind(name),field("raw",str(raw))]) <> dump(rest)
    case T.Queued{index} <> rest: object([kind("queued"),field("index",Nat.show(index))]) <> dump(rest)
def extensions() -> Lexer.Extensions<Unit>: Lexer.Extensions{Lexer.noToken(Unit),Lexer.noStart,Lexer.noToken(Unit),Lexer.noStart,Lexer.defaultDel}
def textOf(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{found}}: found
    case _: ""
def flagOf(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{found}}: found
    case _: False{}
def titleOf(value: V.Value) -> Maybe<&2,String>:
  match value:
    case V.Text{found}: Some{found}
    case _: None{}
def definitionsOf(values: List<&2,V.Value>) -> List<&2,T.LinkDefinition>:
  match values:
    case Nil{}: Nil{}
    case V.ArrayValue{[V.Text{tag},V.Text{href},title]} <> rest: T.LinkDefinition{tag,href,titleOf(title)} <> definitionsOf(rest)
    case _ <> rest: definitionsOf(rest)
def linksOf(value: Maybe<&2,V.Value>) -> List<&2,T.LinkDefinition>:
  match value:
    case Some{V.ArrayValue{values}}: definitionsOf(values)
    case _: Nil{}
def linksJson(links: List<&2,T.LinkDefinition>) -> List<&2,String>:
  match links:
    case Nil{}: Nil{}
    case T.LinkDefinition{tag,href,title} <> rest: field(tag,object([field("href",str(href)),field("title",optional(title))])) <> linksJson(rest)
def blocksJson(lexed: Lexer.TokensList<Unit>) -> String:
  match lexed: case Lexer.TokensList{tokens,links}: object([field("tokens",array(dump(tokens))),field("links",object(linksJson(links)))])
def ran(+marked: Lexer.Marked,+breaks: Lexer.Marked,+fields: R.Record<V.Value>) -> String:
  +source = textOf(R.get(V.Value,fields,"text"))
  +instance = Bool.pick(Lexer.Marked,flagOf(R.get(V.Value,fields,"breaks")),breaks,marked)
  Bool.pick(Unit -> String,flagOf(R.get(V.Value,fields,"inline")),
    _ => object([field("tokens",array(dump(Lexer.lexInline(~Unit,~extensions(),instance,linksOf(R.get(V.Value,fields,"links")),source))))]),
    _ => blocksJson(Lexer.lex(~Unit,~extensions(),instance,source)))(Unit{})
def caseOf(+marked: Lexer.Marked,+breaks: Lexer.Marked,value: Result<&2,&2,Json.ParseError,V.Value>) -> String:
  match value:
    case Done{V.ObjectValue{fields}}: ran(marked,breaks,fields)
    case _: "null"
def splitLines(text: String,+current: String,+parts: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> parts)
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> List<&2,String>,U32.is_eq(code,10),_ => splitLines(rest,"",String.reverse(current) <> parts),_ => splitLines(rest,SCon{Chr{code},current},parts))(Unit{})
def runAll(+marked: Lexer.Marked,+breaks: Lexer.Marked,lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: runAll(marked,breaks,rest)
    case line <> rest:
      do IO<Unit>:
        IO.print(caseOf(marked,breaks,Json.parse(line)))
        runAll(marked,breaks,rest)
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("build/marked-lexer/cases.jsonl")
    runAll(Lexer.new(),Lexer.withOptions(Lexer.MarkedOptions{True{}}),splitLines(Utf8.decodeBytes(Result.default(&2,&2,FS.Error,List<&2,U32>,bytes,Nil{})),"",Nil{}))
