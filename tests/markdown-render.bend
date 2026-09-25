import Base
import ../packages/tui/src/components/markdown.bend as M
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/string.bend as Strings

# pi's Markdown component against upstream (tests/markdown_render_check.py):
# each line of build/markdown-render/cases.jsonl names a source, width,
# theme, default text style, padding and options; the rendered lines print
# as one JSON array per line.

type Affix is Data: Affix{open: String,close: String}
def decorate(style: Affix,value: String) -> IO(String):
  match style: case Affix{open,close}: IO.pure(String,open ++ value ++ close)
def makeStyle(open: String,close: String) -> IO(C.Callback<String,String>):
  C.create(~Affix,~String,~String,~decorate,Affix{open,close})
def plainStyle(_: Unit,value: String) -> IO(String): IO.pure(String,value)
def prefixed(+prefix: String,lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: (prefix ++ line) <> prefixed(prefix,rest)
def highlighted(_: Unit,input: M.HighlightInput) -> IO(List<&2,String>):
  match input: case M.HighlightInput{code,lang}: IO.pure(List<&2,String>,prefixed("<" ++ Maybe.default(&2,String,lang,"?") ++ ">",Strings.split(code,'\n')))

type Styles is Data: Styles{grayItalic: M.DefaultTextStyle,allFlags: M.DefaultTextStyle,background: M.DefaultTextStyle}
type Themes is Data: Themes{plain: M.MarkdownTheme,marker: M.MarkdownTheme,ansi: M.MarkdownTheme,highlight: M.MarkdownTheme,styles: Styles}
def themes() -> IO(Themes):
  do IO<Themes>:
    +plain : C.Callback<String,String> <- C.create(~Unit,~String,~String,~plainStyle,Unit{})
    +h : C.Callback<String,String> <- makeStyle("{H:",":H}")
    +l : C.Callback<String,String> <- makeStyle("{L:",":L}")
    +u : C.Callback<String,String> <- makeStyle("{U:",":U}")
    +c : C.Callback<String,String> <- makeStyle("{C:",":C}")
    +k : C.Callback<String,String> <- makeStyle("{K:",":K}")
    +f : C.Callback<String,String> <- makeStyle("{F:",":F}")
    +q : C.Callback<String,String> <- makeStyle("{Q:",":Q}")
    +qb : C.Callback<String,String> <- makeStyle("{q:",":q}")
    +r : C.Callback<String,String> <- makeStyle("{R:",":R}")
    +b : C.Callback<String,String> <- makeStyle("{B:",":B}")
    +bold : C.Callback<String,String> <- makeStyle("{b:",":b}")
    +italic : C.Callback<String,String> <- makeStyle("{i:",":i}")
    +strike : C.Callback<String,String> <- makeStyle("{s:",":s}")
    +under : C.Callback<String,String> <- makeStyle("{u:",":u}")
    +ah : C.Callback<String,String> <- makeStyle("\u{1b}[36m","\u{1b}[39m")
    +al : C.Callback<String,String> <- makeStyle("\u{1b}[34m","\u{1b}[39m")
    +gray : C.Callback<String,String> <- makeStyle("\u{1b}[90m","\u{1b}[39m")
    +ac : C.Callback<String,String> <- makeStyle("\u{1b}[33m","\u{1b}[0m")
    +ak : C.Callback<String,String> <- makeStyle("\u{1b}[32m","\u{1b}[39m")
    +aq : C.Callback<String,String> <- makeStyle("\u{1b}[35m","\u{1b}[39m")
    +abold : C.Callback<String,String> <- makeStyle("\u{1b}[1m","\u{1b}[22m")
    +aitalic : C.Callback<String,String> <- makeStyle("\u{1b}[3m","\u{1b}[23m")
    +astrike : C.Callback<String,String> <- makeStyle("\u{1b}[9m","\u{1b}[29m")
    +aunder : C.Callback<String,String> <- makeStyle("\u{1b}[4m","\u{1b}[24m")
    +g : C.Callback<String,String> <- makeStyle("{g:",":g}")
    +cc : C.Callback<String,String> <- makeStyle("{c:",":c}")
    +bg : C.Callback<String,String> <- makeStyle("{bg:",":bg}")
    +white : C.Callback<String,String> <- makeStyle("\u{1b}[37m","\u{1b}[39m")
    +highlight : C.Callback<M.HighlightInput,List<&2,String>> <- C.create(~Unit,~M.HighlightInput,~List<&2,String>,~highlighted,Unit{})
    return Themes{
      M.MarkdownTheme{plain,plain,plain,plain,plain,plain,plain,plain,plain,plain,plain,plain,plain,plain,None{},None{}},
      M.MarkdownTheme{h,l,u,c,k,f,q,qb,r,b,bold,italic,strike,under,None{},None{}},
      M.MarkdownTheme{ah,al,gray,ac,ak,gray,aq,gray,gray,ah,abold,aitalic,astrike,aunder,None{},None{}},
      M.MarkdownTheme{h,l,u,c,k,f,q,qb,r,b,bold,italic,strike,under,Some{highlight},Some{"| "}},
      Styles{M.DefaultTextStyle{Some{g},None{},False{},True{},False{},False{}},M.DefaultTextStyle{Some{cc},None{},True{},True{},True{},True{}},M.DefaultTextStyle{Some{white},Some{bg},False{},False{},False{},False{}}}}

def textOf(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{found}}: found
    case _: ""
def flagOf(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.Boolean{found}}: found
    case _: False{}
def natOf(value: Maybe<&2,V.Value>) -> Nat:
  match value:
    case Some{V.Number{found}}: U32.to_nat(F64.to_u32(found))
    case _: 0n
def themeOf(+themes: Themes,name: String) -> M.MarkdownTheme:
  match themes name:
    case Themes{_,marker,_,_,_} "marker": marker
    case Themes{_,_,ansi,_,_} "ansi": ansi
    case Themes{_,_,_,highlight,_} "highlight": highlight
    case Themes{plain,_,_,_,_} _: plain
def styleOf(+themes: Themes,name: String) -> Maybe<&2,M.DefaultTextStyle>:
  match themes name:
    case Themes{_,_,_,_,Styles{style,_,_}} "grayItalic": Some{style}
    case Themes{_,_,_,_,Styles{_,style,_}} "allFlags": Some{style}
    case Themes{_,_,_,_,Styles{_,_,style}} "background": Some{style}
    case _ _: None{}
def quoted(lines: List<&2,String>,reversed: List<&2,String>) -> String:
  match lines:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case line <> rest: quoted(rest,Json.quote(line) <> reversed)
def linesOf(pair: M.Markdown & List<&2,String>) -> String:
  match pair:
    case (_,lines): quoted(lines,Nil{})
def ran(+themes: Themes,+fields: R.Record<V.Value>) -> IO(Unit):
  do IO<Unit>:
    pair : M.Markdown & List<&2,String> <- M.render(M.new(textOf(R.get(V.Value,fields,"text")),natOf(R.get(V.Value,fields,"paddingX")),natOf(R.get(V.Value,fields,"paddingY")),themeOf(themes,textOf(R.get(V.Value,fields,"theme"))),styleOf(themes,textOf(R.get(V.Value,fields,"style"))),Some{M.MarkdownOptions{flagOf(R.get(V.Value,fields,"preserveOrderedListMarkers")),flagOf(R.get(V.Value,fields,"preserveBackslashEscapes")),None{},flagOf(R.get(V.Value,fields,"renderLatex")),flagOf(R.get(V.Value,fields,"hyperlinks"))}}),natOf(R.get(V.Value,fields,"width")))
    IO.print(linesOf(pair))
def caseOf(+themes: Themes,value: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ObjectValue{fields}}: ran(themes,fields)
    case _: IO.print("null")
def splitLines(text: String,+current: String,+parts: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> parts)
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> List<&2,String>,U32.is_eq(code,10),_ => splitLines(rest,"",String.reverse(current) <> parts),_ => splitLines(rest,SCon{Chr{code},current},parts))(Unit{})
def runAll(+themes: Themes,lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: runAll(themes,rest)
    case line <> rest:
      do IO<Unit>:
        caseOf(themes,Json.parse(line))
        runAll(themes,rest)
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("build/markdown-render/cases.jsonl")
    +all : Themes <- themes()
    runAll(all,splitLines(Utf8.decodeBytes(Result.default(&2,&2,FS.Error,List<&2,U32>,bytes,Nil{})),"",Nil{}))
