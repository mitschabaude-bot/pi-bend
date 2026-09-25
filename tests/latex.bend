import Base
import ../packages/tui/src/latex.bend as L
import ../packages/tui/src/components/markdown.bend as M
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# pi's terminal LaTeX rendering against upstream latex.ts and the Markdown
# component (tests/latex_reference.ts): each line of build/latex/cases.jsonl
# is one case, printed as one JSON value per line.
#   {"kind":"latex","source":…,"display":bool} → the rendered string or null
#   {"kind":"markdown","text":…,"width":"80","renderLatex":bool} → the lines

def plain(_: Unit,value: String) -> IO(String): IO.pure(String,value)
def theme(+style: C.Callback<String,String>) -> M.MarkdownTheme:
  M.MarkdownTheme{style,style,style,style,style,style,style,style,style,style,style,style,style,style,None{},None{},M.newParser()}
def maybeText(value: Maybe<&2,String>) -> String:
  match value:
    case Some{text}: Json.quote(text)
    case None{}: "null"
def quotedLines(lines: List<&2,String>,reversed: List<&2,String>) -> String:
  match lines:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case line <> rest: quotedLines(rest,Json.quote(line) <> reversed)
def textOf(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""
def flag(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{enabled}}: enabled
    case _: False{}

type Case is Data:
  LatexCase{source: String,display: Bool}
  MarkdownCase{text: String,width: Nat,renderLatex: Bool}
  Skip{}
def caseFrom(kind: String,+fields: R.Record<V.Value>) -> Case:
  match kind:
    case "latex": LatexCase{textOf(R.get(V.Value,fields,"source")),flag(R.get(V.Value,fields,"display"))}
    case "markdown": MarkdownCase{textOf(R.get(V.Value,fields,"text")),Maybe.default(&2,Nat,Nat.read(textOf(R.get(V.Value,fields,"width"))),80n),flag(R.get(V.Value,fields,"renderLatex"))}
    case _: Skip{}
def caseOf(value: Result<&2,&2,Json.ParseError,V.Value>) -> Case:
  match value:
    case Done{V.ObjectValue{+fields}}: caseFrom(textOf(R.get(V.Value,fields,"kind")),fields)
    case _: Skip{}
def markdownLines(pair: M.Markdown & List<&2,String>) -> String:
  match pair:
    case (_,lines): quotedLines(lines,Nil{})
def ran(+markdownTheme: M.MarkdownTheme,item: Case) -> IO(Unit):
  match item:
    case LatexCase{source,display}: IO.print(maybeText(L.renderLatex(source,L.RenderLatexOptions{display})))
    case MarkdownCase{text,width,enabled}:
      do IO<Unit>:
        pair : M.Markdown & List<&2,String> <- M.render(M.new(text,0n,0n,markdownTheme,None{},Some{M.MarkdownOptions{False{},False{},None{},enabled,False{}}}),width)
        IO.print(markdownLines(pair))
    case Skip{}: IO.pure(Unit,Unit{})
def splitLines(text: String,+current: String,+parts: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> parts)
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> List<&2,String>,U32.is_eq(code,10),_ => splitLines(rest,"",String.reverse(current) <> parts),_ => splitLines(rest,SCon{Chr{code},current},parts))(Unit{})
def runAll(+markdownTheme: M.MarkdownTheme,lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: runAll(markdownTheme,rest)
    case line <> rest:
      do IO<Unit>:
        ran(markdownTheme,caseOf(Json.parse(line)))
        runAll(markdownTheme,rest)
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("build/latex/cases.jsonl")
    +callback : C.Callback<String,String> <- C.create(~Unit,~String,~String,~plain,Unit{})
    runAll(theme(callback),splitLines(Utf8.decodeBytes(Result.default(&2,&2,FS.Error,List<&2,U32>,bytes,Nil{})),"",Nil{}))
    C.dispose(String,String,callback)
