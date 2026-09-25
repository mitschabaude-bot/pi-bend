import Base
import ../packages/tui/src/components/markdown.bend as M
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/json.bend as Json
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/string.bend as Strings

# pi's packages/tui/test/markdown.test.ts (tests/markdown_test_check.py):
# each line of build/markdown-test/cases.jsonl is a Markdown one of its
# tests created, with its theme and default style described as chalk style
# chains or plain wrappers, its options and its setText/invalidate/render
# calls. The renders' lines and the transform option's calls print as one
# JSON object per line.

# chalk
# -----
# A chalk style chain applied as chalk 6 does: nothing for empty text; each
# style's close inside the text reopens it (innermost style first); each
# line break closes and reopens all styles.
type Sgr is Data: Sgr{open: String,close: String}
type Styler is Data:
  Chalk{styles: List<&2,Sgr>}
  Wrap{open: String,close: String}
def reopened(styles: List<&2,Sgr>,text: String) -> String:
  match styles:
    case Nil{}: text
    case Sgr{+open,+close} <> rest: reopened(rest,Strings.replaceAll(text,close,close ++ open))
def opens(styles: List<&2,Sgr>) -> String:
  match styles:
    case Nil{}: ""
    case Sgr{open,_} <> rest: open ++ opens(rest)
def closes(styles: List<&2,Sgr>) -> String:
  match styles:
    case Nil{}: ""
    case Sgr{_,close} <> rest: closes(rest) ++ close
def lineBreaks(text: String,+openAll: String,+closeAll: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',SCon{'\n',rest}}: lineBreaks(rest,openAll,closeAll,String.reverse(closeAll ++ "\r\n" ++ openAll) ++ reversed)
    case SCon{'\n',rest}: lineBreaks(rest,openAll,closeAll,String.reverse(closeAll ++ "\n" ++ openAll) ++ reversed)
    case SCon{char,rest}: lineBreaks(rest,openAll,closeAll,SCon{char,reversed})
def chalked(+styles: List<&2,Sgr>,+text: String) -> String:
  +escaped = Bool.pick(Unit -> String,String.contains(text,"\u{1b}"),_ => reopened(List.reverse(&2,Sgr,styles),text),_ => text)(Unit{})
  +broken = Bool.pick(Unit -> String,String.contains(escaped,"\n"),_ => lineBreaks(escaped,opens(styles),closes(styles),""),_ => escaped)(Unit{})
  Bool.pick(Unit -> String,String.is_empty(text),_ => "",_ => opens(styles) ++ broken ++ closes(styles))(Unit{})
def styled(styler: Styler,text: String) -> IO(String):
  match styler:
    case Chalk{styles}: IO.pure(String,chalked(styles,text))
    case Wrap{open,close}: IO.pure(String,open ++ text ++ close)
def styleOf(styler: Styler) -> IO(C.Callback<String,String>): C.create(~Styler,~String,~String,~styled,styler)

# Descriptions
# ------------

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
def sgrs(values: List<&2,V.Value>) -> List<&2,Sgr>:
  match values:
    case Nil{}: Nil{}
    case V.ArrayValue{[V.Text{open},V.Text{close}]} <> rest: Sgr{open,close} <> sgrs(rest)
    case _ <> rest: sgrs(rest)
def wrapFrom(value: Maybe<&2,V.Value>) -> Maybe<&2,Styler>:
  match value:
    case Some{V.ArrayValue{[V.Text{open},V.Text{close}]}}: Some{Wrap{open,close}}
    case _: None{}
def chalkFrom(value: Maybe<&2,V.Value>,wrap: Maybe<&2,V.Value>) -> Maybe<&2,Styler>:
  match value:
    case Some{V.ArrayValue{values}}: Some{Chalk{sgrs(values)}}
    case _: wrapFrom(wrap)
def stylerFrom(+fields: R.Record<V.Value>) -> Maybe<&2,Styler>: chalkFrom(R.get(V.Value,fields,"chalk"),R.get(V.Value,fields,"wrap"))
def stylerOf(value: V.Value) -> Maybe<&2,Styler>:
  match value:
    case V.ObjectValue{fields}: stylerFrom(fields)
    case _: None{}
def optionalStyle(value: Maybe<&2,Styler>) -> IO(Maybe<&2,C.Callback<String,String>>):
  match value:
    case Some{styler}:
      do IO<Maybe<&2,C.Callback<String,String>>>:
        style : C.Callback<String,String> <- styleOf(styler)
        return Some{style}
    case None{}: IO.pure(Maybe<&2,C.Callback<String,String>>,None{})
def maybeStyler(value: Maybe<&2,V.Value>) -> Maybe<&2,Styler>:
  match value:
    case Some{found}: stylerOf(found)
    case None{}: None{}
def plainStyle(_: Unit,value: String) -> IO(String): IO.pure(String,value)
def stylesOf(values: List<&2,V.Value>,reversed: List<&2,C.Callback<String,String>>) -> IO(List<&2,C.Callback<String,String>>):
  match values:
    case Nil{}: IO.pure(List<&2,C.Callback<String,String>>,List.reverse(&2,C.Callback<String,String>,reversed))
    case value <> rest:
      do IO<List<&2,C.Callback<String,String>>>:
        style : Maybe<&2,C.Callback<String,String>> <- optionalStyle(stylerOf(value))
        plain : C.Callback<String,String> <- C.create(~Unit,~String,~String,~plainStyle,Unit{})
        stylesOf(rest,Maybe.default(&2,C.Callback<String,String>,style,plain) <> reversed)
def themeFrom(styles: List<&2,C.Callback<String,String>>,indent: Maybe<&2,String>) -> Maybe<&2,M.MarkdownTheme>:
  match styles:
    case [heading,link,linkUrl,code,codeBlock,codeBlockBorder,quote,quoteBorder,hr,listBullet,bold,italic,strike,underline]:
      Some{M.MarkdownTheme{heading,link,linkUrl,code,codeBlock,codeBlockBorder,quote,quoteBorder,hr,listBullet,bold,italic,strike,underline,None{},indent,M.newParser()}}
    case _: None{}
def indentOf(value: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match value:
    case Some{V.Text{found}}: Some{found}
    case _: None{}
def arrayOf(value: Maybe<&2,V.Value>) -> List<&2,V.Value>:
  match value:
    case Some{V.ArrayValue{values}}: values
    case _: Nil{}
def fieldsOf(value: Maybe<&2,V.Value>) -> Maybe<&2,R.Record<V.Value>>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{fields}
    case _: None{}
def themeOf(+fields: R.Record<V.Value>) -> IO(Maybe<&2,M.MarkdownTheme>):
  do IO<Maybe<&2,M.MarkdownTheme>>:
    styles : List<&2,C.Callback<String,String>> <- stylesOf(arrayOf(R.get(V.Value,fields,"styles")),Nil{})
    return themeFrom(styles,indentOf(R.get(V.Value,fields,"codeBlockIndent")))
def defaultStyleFrom(+fields: R.Record<V.Value>) -> IO(M.DefaultTextStyle):
  do IO<M.DefaultTextStyle>:
    color : Maybe<&2,C.Callback<String,String>> <- optionalStyle(maybeStyler(R.get(V.Value,fields,"color")))
    background : Maybe<&2,C.Callback<String,String>> <- optionalStyle(maybeStyler(R.get(V.Value,fields,"bgColor")))
    return M.DefaultTextStyle{color,background,flagOf(R.get(V.Value,fields,"bold")),flagOf(R.get(V.Value,fields,"italic")),flagOf(R.get(V.Value,fields,"strikethrough")),flagOf(R.get(V.Value,fields,"underline"))}
def defaultStyleOf(value: Maybe<&2,R.Record<V.Value>>) -> IO(Maybe<&2,M.DefaultTextStyle>):
  match value:
    case Some{fields}:
      do IO<Maybe<&2,M.DefaultTextStyle>>:
        style : M.DefaultTextStyle <- defaultStyleFrom(fields)
        return Some{style}
    case None{}: IO.pure(Maybe<&2,M.DefaultTextStyle>,None{})

# The transform upstream's tests use appends the width; its calls are kept.
type Call is Data: Call{source: String,width: Nat}
def appendWidth(calls: Ref.Ref<List<&2,Call>>,input: String & Nat) -> IO(String):
  match input:
    case (+source,+width):
      do IO<String>:
        Ref.modify(List<&2,Call>,Unit,calls,recorded => (Call{source,width} <> recorded,Unit{}))
        return source ++ " " ++ Nat.show(width)
def transformOf(enabled: Bool,calls: Ref.Ref<List<&2,Call>>) -> IO(Maybe<&2,C.Callback<(String & Nat),String>>):
  match enabled:
    case True{}:
      do IO<Maybe<&2,C.Callback<(String & Nat),String>>>:
        callback : C.Callback<(String & Nat),String> <- C.create(~Ref.Ref<List<&2,Call>>,~(String & Nat),~String,~appendWidth,calls)
        return Some{callback}
    case False{}: IO.pure(Maybe<&2,C.Callback<(String & Nat),String>>,None{})

# Replaying the calls
# -------------------

def quoted(lines: List<&2,String>,reversed: List<&2,String>) -> String:
  match lines:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case line <> rest: quoted(rest,Json.quote(line) <> reversed)
# getCapabilities().hyperlinks at the render; the cache stays.
def withHyperlinks(state: M.Markdown,enabled: Bool) -> M.Markdown:
  match state:
    case M.Markdown{text,x,y,theme,style,M.MarkdownOptions{preserve,escapes,transform,latex,_},cache}: M.Markdown{text,x,y,theme,style,M.MarkdownOptions{preserve,escapes,transform,latex,enabled},cache}
type Replay is Data: Replay{state: M.Markdown,renders: List<&2,String>}
def rendered(pair: M.Markdown & List<&2,String>,renders: List<&2,String>) -> Replay:
  match pair: case (state,lines): Replay{state,quoted(lines,Nil{}) <> renders}
@unsafe def replay(events: List<&2,V.Value>,current: Replay) -> IO(Replay):
  match events current:
    case Nil{} current: IO.pure(Replay,current)
    case V.ObjectValue{+fields} <> +rest Replay{+state,+renders}:
      Bool.pick(Unit -> IO(Replay),Maybe.is_some(&2,V.Value,R.get(V.Value,fields,"setText")),_ => replay(rest,Replay{M.setText(state,textOf(R.get(V.Value,fields,"setText"))),renders}),
        _ => Bool.pick(Unit -> IO(Replay),Maybe.is_some(&2,V.Value,R.get(V.Value,fields,"invalidate")),_ => replay(rest,Replay{M.invalidate(state),renders}),
          _ => do IO<Replay>:
            pair : M.Markdown & List<&2,String> <- M.render(withHyperlinks(state,flagOf(R.get(V.Value,fields,"hyperlinks"))),natOf(R.get(V.Value,fields,"render")))
            replay(rest,rendered(pair,renders)))(Unit{}))(Unit{})
    case _ <> rest current: replay(rest,current)
def callsJson(calls: List<&2,Call>,reversed: List<&2,String>) -> String:
  match calls:
    case Nil{}: "[" ++ String.join(List.reverse(&2,String,reversed),",") ++ "]"
    case Call{source,width} <> rest: callsJson(rest,("[" ++ Json.quote(source) ++ "," ++ Nat.show(width) ++ "]") <> reversed)
def output(done: Replay,calls: List<&2,Call>) -> String:
  match done: case Replay{_,renders}: "{\"renders\":[" ++ String.join(List.reverse(&2,String,renders),",") ++ "],\"calls\":" ++ callsJson(calls,Nil{}) ++ "}"
def optionsFrom(+fields: R.Record<V.Value>,transform: Maybe<&2,C.Callback<(String & Nat),String>>) -> M.MarkdownOptions:
  M.MarkdownOptions{flagOf(R.get(V.Value,fields,"preserveOrderedListMarkers")),flagOf(R.get(V.Value,fields,"preserveBackslashEscapes")),transform,flagOf(R.get(V.Value,fields,"renderLatex")),False{}}
def optionsOf(value: Maybe<&2,V.Value>,transform: Maybe<&2,C.Callback<(String & Nat),String>>) -> M.MarkdownOptions:
  match value:
    case Some{V.ObjectValue{fields}}: optionsFrom(fields,transform)
    case _: M.MarkdownOptions{False{},False{},transform,True{},False{}}
def started(+fields: R.Record<V.Value>,theme: Maybe<&2,M.MarkdownTheme>,style: Maybe<&2,M.DefaultTextStyle>,transform: Maybe<&2,C.Callback<(String & Nat),String>>) -> Maybe<&2,M.Markdown>:
  match theme:
    case Some{found}: Some{M.new(textOf(R.get(V.Value,fields,"text")),natOf(R.get(V.Value,fields,"paddingX")),natOf(R.get(V.Value,fields,"paddingY")),found,style,Some{optionsOf(R.get(V.Value,fields,"options"),transform)})}
    case None{}: None{}
def transformWanted(value: Maybe<&2,V.Value>) -> Bool:
  match value:
    case Some{V.ObjectValue{fields}}: flagOf(R.get(V.Value,fields,"transform"))
    case _: False{}
def replayedFrom(+fields: R.Record<V.Value>,+calls: Ref.Ref<List<&2,Call>>,markdown: Maybe<&2,M.Markdown>) -> IO(String):
  match markdown:
    case None{}: IO.pure(String,"null")
    case Some{state}:
      do IO<String>:
        done : Replay <- replay(arrayOf(R.get(V.Value,fields,"events")),Replay{state,Nil{}})
        recorded : List<&2,Call> <- Ref.read(List<&2,Call>,calls)
        return output(done,List.reverse(&2,Call,recorded))
def themeFromValue(value: Maybe<&2,R.Record<V.Value>>) -> IO(Maybe<&2,M.MarkdownTheme>):
  match value:
    case Some{fields}: themeOf(fields)
    case None{}: IO.pure(Maybe<&2,M.MarkdownTheme>,None{})
def ran(+fields: R.Record<V.Value>) -> IO(Unit):
  do IO<Unit>:
    +calls : Ref.Ref<List<&2,Call>> <- Ref.new(List<&2,Call>,Nil{})
    theme : Maybe<&2,M.MarkdownTheme> <- themeFromValue(fieldsOf(R.get(V.Value,fields,"theme")))
    style : Maybe<&2,M.DefaultTextStyle> <- defaultStyleOf(fieldsOf(R.get(V.Value,fields,"style")))
    transform : Maybe<&2,C.Callback<(String & Nat),String>> <- transformOf(transformWanted(R.get(V.Value,fields,"options")),calls)
    line : String <- replayedFrom(fields,calls,started(fields,theme,style,transform))
    IO.print(line)
def caseOf(value: Result<&2,&2,Json.ParseError,V.Value>) -> IO(Unit):
  match value:
    case Done{V.ObjectValue{fields}}: ran(fields)
    case _: IO.print("null")
def splitLines(text: String,+current: String,+parts: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> parts)
    case SCon{Chr{+code},+rest}: Bool.pick(Unit -> List<&2,String>,U32.is_eq(code,10),_ => splitLines(rest,"",String.reverse(current) <> parts),_ => splitLines(rest,SCon{Chr{code},current},parts))(Unit{})
def runAll(lines: List<&2,String>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: runAll(rest)
    case line <> rest:
      do IO<Unit>:
        caseOf(Json.parse(line))
        runAll(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("build/markdown-test/cases.jsonl")
    runAll(splitLines(Utf8.decodeBytes(Result.default(&2,&2,FS.Error,List<&2,U32>,bytes,Nil{})),"",Nil{}))
