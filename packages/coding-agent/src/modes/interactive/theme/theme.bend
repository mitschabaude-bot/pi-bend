import Base
import ./color.bend as C
import ../../../../../runtime/src/json.bend as Json
import ../../../../../runtime/src/schema-value.bend as V
import ../../../../../runtime/src/record.bend as R
import ../../../../../runtime/src/f64.bend as F
import ../../../../../runtime/src/filesystem.bend as FS
import ../../../../../runtime/src/utf8.bend as Utf8
import ../../../../../runtime/src/posix-path.bend as Path
import ../../../../../runtime/src/stable-sort.bend as Sort
import ../../../../../runtime/src/case-map.bend as Case
import ../../../utils/syntax-highlight.bend as SyntaxHighlight

# Theme documents are immutable data. Variables are resolved once when a theme
# is loaded, so rendering never depends on JSON or mutable global state.
type Token is Data: Literal{color: C.Color} Reference{name: String}
# Like upstream's fgColors/bgColors maps, a theme keeps each color's escape
# sequence, computed once, beside the resolved colors.
type Theme is Data: Theme{name: String,mode: C.Mode,foreground: R.Record<C.Color>,background: R.Record<C.Color>,fgAnsi: Map<&2,String>,bgAnsi: Map<&2,String>}
def colorMode(theme: Theme) -> C.Mode:
  match theme: case Theme{_,mode,_,_,_,_}: mode
def escape(color: C.Color,mode: C.Mode,bg: Bool) -> String:
  match bg:
    case True{}: C.background(color,mode)
    case False{}: C.foreground(color,mode)
def escapes(colors: List<&2,R.Property<C.Color>>,+mode: C.Mode,+bg: Bool,codes: Map<&2,String>) -> Map<&2,String>:
  match colors:
    case Nil{}: codes
    case R.Property{key,color} <> rest: escapes(rest,mode,bg,Map.set(&2,String,codes,key,escape(color,mode,bg)))
def create(name: String,+mode: C.Mode,+fg: R.Record<C.Color>,+bg: R.Record<C.Color>) -> Theme:
  Theme{name,mode,fg,bg,escapes(R.entries(C.Color,fg),mode,False{},Map.new(&2,String)),escapes(R.entries(C.Color,bg),mode,True{},Map.new(&2,String))}

# Whether two themes render alike: the escape maps derive from the name's
# colors and the mode.
def sameColor(left: C.Color,right: C.Color) -> Bool:
  match left right:
    case C.Default{} C.Default{}: True{}
    case C.Indexed{a} C.Indexed{b}: Nat.is_eq(a,b)
    case C.RgbColor{C.Rgb{r1,g1,b1}} C.RgbColor{C.Rgb{r2,g2,b2}}: Nat.is_eq(r1,r2) && Nat.is_eq(g1,g2) && Nat.is_eq(b1,b2)
    case _ _: False{}
def sameColors(left: List<&2,R.Property<C.Color>>,right: List<&2,R.Property<C.Color>>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case R.Property{k1,c1} <> rest1 R.Property{k2,c2} <> rest2: String.eq(k1,k2) && sameColor(c1,c2) && sameColors(rest1,rest2)
    case _ _: False{}
def sameMode(left: C.Mode,right: C.Mode) -> Bool:
  match left right:
    case C.TrueColor{} C.TrueColor{}: True{}
    case C.Palette256{} C.Palette256{}: True{}
    case _ _: False{}
def same(left: Theme,right: Theme) -> Bool:
  match left right:
    case Theme{n1,m1,f1,b1,_,_} Theme{n2,m2,f2,b2,_,_}:
      String.eq(n1,n2) && sameMode(m1,m2) && sameColors(R.entries(C.Color,f1),R.entries(C.Color,f2)) && sameColors(R.entries(C.Color,b1),R.entries(C.Color,b2))

type Error is Data:
  InvalidJson{}
  InvalidDocument{}
  InvalidName{name: String}
  MissingColor{name: String}
  InvalidColor{name: String}
  MissingVariable{name: String}
  CircularVariable{name: String}
  InvalidHex{name: String}
type LoadError is Data:
  Read{cause: FS.Error}
  Decode{cause: Utf8.Error}
  Invalid{cause: Error}
  NotFound{name: String}

def bind(-A: Data,-B: Data,result: Result<&2,&2,Error,A>,next: A -> Result<&2,&2,Error,B>) -> Result<&2,&2,Error,B>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: next(value)

def string(value: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match value:
    case Some{V.Text{text}}: Some{text}
    case _: None{}
def object(value: Maybe<&2,V.Value>) -> Maybe<&2,R.Record<V.Value>>:
  match value:
    case Some{V.ObjectValue{fields}}: Some{fields}
    case _: None{}
def name(value: Maybe<&2,String>) -> Result<&2,&2,Error,String>:
  match value:
    case None{}: Fail{InvalidDocument{}}
    case Some{+text}:
      Bool.pick(Result<&2,&2,Error,String>,String.contains(text,"/"),Fail{InvalidName{text}},Done{text})

def hexToken(key: String,result: Result<&2,&2,C.Error,C.Rgb>) -> Result<&2,&2,Error,Token>:
  match result:
    case Fail{_}: Fail{InvalidHex{key}}
    case Done{rgb}: Done{Literal{C.RgbColor{rgb}}}

def token(key: String,value: V.Value) -> Result<&2,&2,Error,Token>:
  match value:
    case V.Text{""}: Done{Literal{C.Default{}}}
    case V.Text{text}:
      match text:
        case SCon{'#',_}:
          hexToken(key,C.parseHex(text))
        case _: Done{Reference{text}}
    case V.Number{+number}:
      Bool.pick(Result<&2,&2,Error,Token>,F.isInteger(number) && F.isAtLeast(F.compare(number,F.fromU32(0))) && F.isAtMost(F.compare(number,F.fromU32(255))),
        Done{Literal{C.Indexed{U32.to_nat(F64.to_u32(number))}}},Fail{InvalidColor{key}})
    case _: Fail{InvalidColor{key}}

def tokens(entries: List<&2,R.Property<V.Value>>,acc: R.Record<Token>) -> Result<&2,&2,Error,R.Record<Token>>:
  match entries:
    case Nil{}: Done{acc}
    case R.Property{+key,value} <> rest:
      bind(Token,R.Record<Token>,token(key,value),item => tokens(rest,R.set(Token,acc,key,item)))
def tokenMap(value: R.Record<V.Value>) -> Result<&2,&2,Error,R.Record<Token>>:
  tokens(R.entries(V.Value,value),R.new(Token))

def seenVariable(seen: List<&2,String>,+key: String) -> Bool:
  match seen:
    case Nil{}: False{}
    case item <> rest: String.eq(item,key) || seenVariable(rest,key)

@unsafe
def resolve(token: Token,+vars: R.Record<Token>,+seen: List<&2,String>) -> Result<&2,&2,Error,C.Color>:
  match token:
    case Literal{color}: Done{color}
    case Reference{+key}:
      Bool.pick(Unit -> Result<&2,&2,Error,C.Color>,seenVariable(seen,key),_ => Fail{CircularVariable{key}},
        _ => Maybe.default(&2,Result<&2,&2,Error,C.Color>,
          Maybe.map(&2,Token,Result<&2,&2,Error,C.Color>,item => resolve(item,vars,key <> seen),R.get(Token,vars,key)),
          Fail{MissingVariable{key}}))(Unit{})

def backgroundKey(+key: String) -> Bool:
  String.eq(key,"selectedBg") || String.eq(key,"searchMatchBg") || String.eq(key,"userMessageBg") || String.eq(key,"customMessageBg") || String.eq(key,"toolPendingBg") || String.eq(key,"toolSuccessBg") || String.eq(key,"toolErrorBg")
def resolveOne(entries: List<&2,R.Property<Token>>,+vars: R.Record<Token>,+bg: Bool,+acc: R.Record<C.Color>) -> Result<&2,&2,Error,R.Record<C.Color>>:
  match entries:
    case Nil{}: Done{acc}
    case R.Property{+key,item} <> +rest:
      Bool.pick(Unit -> Result<&2,&2,Error,R.Record<C.Color>>,Bool.pick(Bool,backgroundKey(key),bg,Bool.not(bg)),
        _ => bind(C.Color,R.Record<C.Color>,resolve(item,vars,Nil{}),color => resolveOne(rest,vars,bg,R.set(C.Color,acc,key,color))),
        _ => resolveOne(rest,vars,bg,acc))(Unit{})

def required() -> List<&2,String>:
  "accent" <> "border" <> "borderAccent" <> "borderMuted" <> "success" <> "error" <> "warning" <> "muted" <> "dim" <> "text" <> "thinkingText" <>
  "selectedBg" <> "userMessageBg" <> "userMessageText" <> "customMessageBg" <> "customMessageText" <> "customMessageLabel" <> "toolPendingBg" <> "toolSuccessBg" <> "toolErrorBg" <> "toolTitle" <> "toolOutput" <>
  "mdHeading" <> "mdLink" <> "mdLinkUrl" <> "mdCode" <> "mdCodeBlock" <> "mdCodeBlockBorder" <> "mdQuote" <> "mdQuoteBorder" <> "mdHr" <> "mdListBullet" <>
  "toolDiffAdded" <> "toolDiffRemoved" <> "toolDiffContext" <>
  "syntaxComment" <> "syntaxKeyword" <> "syntaxFunction" <> "syntaxVariable" <> "syntaxString" <> "syntaxNumber" <> "syntaxType" <> "syntaxOperator" <> "syntaxPunctuation" <>
  "thinkingOff" <> "thinkingMinimal" <> "thinkingLow" <> "thinkingMedium" <> "thinkingHigh" <> "thinkingXhigh" <> "bashMode" <> Nil{}
def checkRequired(names: List<&2,String>,+colors: R.Record<Token>) -> Result<&2,&2,Error,Unit>:
  match names:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      Bool.pick(Unit -> Result<&2,&2,Error,Unit>,Maybe.is_none(&2,Token,R.get(Token,colors,key)),
        _ => Fail{MissingColor{key}},_ => checkRequired(rest,colors))(Unit{})
def fallbackSource(replacement: Maybe<&2,Token>,colors: R.Record<Token>,key: String) -> R.Record<Token>:
  match replacement:
    case None{}: colors
    case Some{value}: R.set(Token,colors,key,value)
def fallbackFound(found: Maybe<&2,Token>,+colors: R.Record<Token>,key: String,source: String) -> R.Record<Token>:
  match found:
    case Some{_}: colors
    case None{}: fallbackSource(R.get(Token,colors,source),colors,key)
def fallback(+colors: R.Record<Token>,+key: String,source: String) -> R.Record<Token>:
  fallbackFound(R.get(Token,colors,key),colors,key,source)
def fallbacks(colors: R.Record<Token>) -> R.Record<Token>:
  fallback(fallback(fallback(fallback(fallback(colors,"scrollbarTrack","muted"),"scrollbarThumb","text"),"thinkingMax","thinkingXhigh"),"searchMatchText","text"),"searchMatchBg","selectedBg")

def assemble(name: String,mode: C.Mode,+vars: R.Record<Token>,+colors: R.Record<Token>) -> Result<&2,&2,Error,Theme>:
  bind(Unit,Theme,checkRequired(required(),colors),_ =>
    bind(R.Record<C.Color>,Theme,resolveOne(R.entries(Token,fallbacks(colors)),vars,False{},R.new(C.Color)),fg =>
      bind(R.Record<C.Color>,Theme,resolveOne(R.entries(Token,fallbacks(colors)),vars,True{},R.new(C.Color)),bg => Done{create(name,mode,fg,bg)})))
def fromColorsFields(themeName: String,mode: C.Mode,colors: R.Record<V.Value>,varsValue: Maybe<&2,V.Value>) -> Result<&2,&2,Error,Theme>:
  match varsValue:
    case Some{V.ObjectValue{vars}}: bind(R.Record<Token>,Theme,tokenMap(vars),resolvedVars => bind(R.Record<Token>,Theme,tokenMap(colors),values => assemble(themeName,mode,resolvedVars,values)))
    case None{}: bind(R.Record<Token>,Theme,tokenMap(colors),values => assemble(themeName,mode,R.new(Token),values))
    case _: Fail{InvalidDocument{}}
def fromNamedFields(themeName: String,mode: C.Mode,colorsValue: Maybe<&2,R.Record<V.Value>>,varsValue: Maybe<&2,V.Value>) -> Result<&2,&2,Error,Theme>:
  match colorsValue:
    case None{}: Fail{InvalidDocument{}}
    case Some{colors}: fromColorsFields(themeName,mode,colors,varsValue)
def fromFields(+fields: R.Record<V.Value>,mode: C.Mode) -> Result<&2,&2,Error,Theme>:
  bind(String,Theme,name(string(R.get(V.Value,fields,"name"))),themeName =>
    fromNamedFields(themeName,mode,object(R.get(V.Value,fields,"colors")),R.get(V.Value,fields,"vars")))
def parsed(result: Result<&2,&2,Json.ParseError,V.Value>,mode: C.Mode) -> Result<&2,&2,Error,Theme>:
  match result:
    case Fail{_}: Fail{InvalidJson{}}
    case Done{V.ObjectValue{fields}}: fromFields(fields,mode)
    case Done{_}: Fail{InvalidDocument{}}
def stripBom(content: String) -> String:
  match content:
    case SCon{Chr{65279},rest}: rest
    case other: other
def parse(content: String,mode: C.Mode) -> Result<&2,&2,Error,Theme>:
  parsed(Json.parse(stripBom(content)),mode)

# An escape sequence is never empty, so "" marks a missing color.
def wrapped(found: Map<&2,String> & String,key: String,text: String,reset: String) -> Result<&2,&2,Error,String>:
  match found:
    case (_,""): Fail{MissingColor{key}}
    case (_,code): Done{code ++ text ++ reset}

def foreground(theme: Theme,+key: String,text: String) -> Result<&2,&2,Error,String>:
  match theme:
    case Theme{_,_,_,_,codes,_}: wrapped(Map.get(String,"",codes,key),key,text,"\u{1b}[39m")
def background(theme: Theme,+key: String,text: String) -> Result<&2,&2,Error,String>:
  match theme:
    case Theme{_,_,_,_,_,codes}: wrapped(Map.get(String,"",codes,key),key,text,"\u{1b}[49m")

def loaded(result: Result<&2,&2,Error,Theme>) -> Result<&2,&2,LoadError,Theme>:
  match result:
    case Done{theme}: Done{theme}
    case Fail{cause}: Fail{Invalid{cause}}
def decoded(result: Result<&2,&2,Utf8.Error,String>,mode: C.Mode) -> Result<&2,&2,LoadError,Theme>:
  match result:
    case Done{content}: loaded(parse(content,mode))
    case Fail{cause}: Fail{Decode{cause}}
def read(result: Result<&2,&2,FS.Error,List<&2,U32>>,mode: C.Mode) -> Result<&2,&2,LoadError,Theme>:
  match result:
    case Done{bytes}: decoded(Utf8.decodeStrict(bytes),mode)
    case Fail{cause}: Fail{Read{cause}}
def loadFromPath(path: String,mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  do IO<Result<&2,&2,LoadError,Theme>>:
    bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return read(bytes,mode)
type ThemeInfo is Data: ThemeInfo{themeName: String,path: String}
def infoName(info: ThemeInfo) -> String:
  match info: case ThemeInfo{themeName,_}: themeName
def loadedInfo(path: String,result: Result<&2,&2,LoadError,Theme>) -> Maybe<&2,ThemeInfo>:
  match result:
    case Done{Theme{themeName,_,_,_,_,_}}: Some{ThemeInfo{themeName,path}}
    case Fail{_}: None{}
def maybeInfo(found: Maybe<&2,ThemeInfo>,rest: List<&2,ThemeInfo>) -> List<&2,ThemeInfo>:
  match found:
    case Some{info}: info <> rest
    case None{}: rest
def customInfos(entries: List<&2,FS.DirectoryEntry>,+directory: String,+mode: C.Mode) -> IO(List<&2,ThemeInfo>):
  match entries:
    case Nil{}: IO.pure(List<&2,ThemeInfo>,Nil{})
    case FS.DirectoryEntry{+fileName,_} <> +rest:
      Bool.pick(Unit -> IO(List<&2,ThemeInfo>),String.ends_with(fileName,".json"),
        _ => do IO<List<&2,ThemeInfo>>:
          +path : String <- IO.pure(String,Path.join(directory,fileName))
          found : Result<&2,&2,LoadError,Theme> <- loadFromPath(path,mode)
          tail : List<&2,ThemeInfo> <- customInfos(rest,directory,mode)
          return maybeInfo(loadedInfo(path,found),tail),
        _ => customInfos(rest,directory,mode))(Unit{})
def directoryInfos(result: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>,directory: String,mode: C.Mode) -> IO(Result<&2,&2,FS.Error,List<&2,ThemeInfo>>):
  match result:
    case Fail{FS.System{2,_}}: IO.pure(Result<&2,&2,FS.Error,List<&2,ThemeInfo>>,Done{Nil{}})
    case Fail{cause}: IO.pure(Result<&2,&2,FS.Error,List<&2,ThemeInfo>>,Fail{cause})
    case Done{entries}:
      do IO<Result<&2,&2,FS.Error,List<&2,ThemeInfo>>>:
        found : List<&2,ThemeInfo> <- customInfos(entries,directory,mode)
        return Done{found}
def containsInfo(items: List<&2,ThemeInfo>,+name: String) -> Bool:
  match items:
    case Nil{}: False{}
    case ThemeInfo{candidate,_} <> rest: String.eq(candidate,name) || containsInfo(rest,name)
def distinctInfos(items: List<&2,ThemeInfo>,+seen: List<&2,ThemeInfo>) -> List<&2,ThemeInfo>:
  match items:
    case Nil{}: Nil{}
    case +info <> +rest:
      Bool.pick(Unit -> List<&2,ThemeInfo>,containsInfo(seen,infoName(info)),
        _ => distinctInfos(rest,seen),
        _ => info <> distinctInfos(rest,info <> seen))(Unit{})
def infoBefore(left: ThemeInfo,right: ThemeInfo) -> Bool: String.is_le(infoName(left),infoName(right))
def catalog(+customDir: String,mode: C.Mode) -> IO(Result<&2,&2,FS.Error,List<&2,ThemeInfo>>):
  do IO<Result<&2,&2,FS.Error,List<&2,ThemeInfo>>>:
    entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(customDir)
    found : Result<&2,&2,FS.Error,List<&2,ThemeInfo>> <- directoryInfos(entries,customDir,mode)
    return Result.map(&2,&2,FS.Error,List<&2,ThemeInfo>,List<&2,ThemeInfo>,items => Sort.sort(~ThemeInfo,~infoBefore,distinctInfos(ThemeInfo{"dark",""} <> ThemeInfo{"light",""} <> items,Nil{})),found)
def names(items: List<&2,ThemeInfo>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case ThemeInfo{themeName,_} <> rest: themeName <> names(rest)
def findInfo(items: List<&2,ThemeInfo>,+wanted: String) -> Maybe<&2,ThemeInfo>:
  match items:
    case Nil{}: None{}
    case ThemeInfo{+themeName,path} <> rest:
      Bool.pick(Unit -> Maybe<&2,ThemeInfo>,String.eq(themeName,wanted),_ => Some{ThemeInfo{themeName,path}},_ => findInfo(rest,wanted))(Unit{})
def namedInfo(found: Maybe<&2,ThemeInfo>,wanted: String,mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  match found:
    case None{}: IO.pure(Result<&2,&2,LoadError,Theme>,Fail{NotFound{wanted}})
    case Some{ThemeInfo{_,path}}: loadFromPath(path,mode)
def namedCustom(result: Result<&2,&2,FS.Error,List<&2,ThemeInfo>>,+wanted: String,mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  match result:
    case Fail{cause}: IO.pure(Result<&2,&2,LoadError,Theme>,Fail{Read{cause}})
    case Done{items}: namedInfo(findInfo(items,wanted),wanted,mode)
def customTheme(+path: String,themeName: String,customDir: String,+mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  do IO<Result<&2,&2,LoadError,Theme>>:
    present : Bool <- FS.accessible(path,0)
    Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),present,
      _ => loadFromPath(path,mode),
      _ => do IO<Result<&2,&2,LoadError,Theme>>:
        found : Result<&2,&2,FS.Error,List<&2,ThemeInfo>> <- catalog(customDir,mode)
        namedCustom(found,themeName,mode))(Unit{})
def loadByName(+themeName: String,builtinDir: String,+customDir: String,+mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),String.contains(themeName,"/"),
    _ => IO.pure(Result<&2,&2,LoadError,Theme>,Fail{Invalid{InvalidName{themeName}}}),
    _ => Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),String.eq(themeName,"dark") || String.eq(themeName,"light"),
      _ => loadFromPath(Path.join(builtinDir,themeName ++ ".json"),mode),
      _ => customTheme(Path.join(customDir,themeName ++ ".json"),themeName,customDir,mode))(Unit{}))(Unit{})

# TUI helpers
# -----------

def bold(text: String) -> String: "\u{1b}[1m" ++ text ++ "\u{1b}[22m"
def italic(text: String) -> String: "\u{1b}[3m" ++ text ++ "\u{1b}[23m"
def underline(text: String) -> String: "\u{1b}[4m" ++ text ++ "\u{1b}[24m"
def fg(theme: Theme,+key: String,+text: String) -> String: Result.default(&2,&2,Error,String,foreground(theme,key,text),text)

# The formatters of the CLI highlight theme: a theme foreground or an effect.
type CliStyle is Data: CliColor{key: String} CliBold{} CliItalic{} CliUnderline{}
type CliFormatter is Data: CliFormatter{theme: Theme,style: CliStyle}
def cliFormat(formatter: CliFormatter,text: String) -> String:
  match formatter:
    case CliFormatter{theme,CliColor{key}}: fg(theme,key,text)
    case CliFormatter{_,CliBold{}}: bold(text)
    case CliFormatter{_,CliItalic{}}: italic(text)
    case CliFormatter{_,CliUnderline{}}: underline(text)
def cliEntries(+theme: Theme,styles: List<&2,R.Property<CliStyle>>,record: R.Record<CliFormatter>) -> R.Record<CliFormatter>:
  match styles:
    case Nil{}: record
    case R.Property{scope,style} <> rest: cliEntries(theme,rest,R.set(CliFormatter,record,scope,CliFormatter{theme,style}))
def buildCliHighlightTheme(theme: Theme) -> R.Record<CliFormatter>:
  cliEntries(theme,[
    R.Property{"keyword",CliColor{"syntaxKeyword"}},
    R.Property{"built_in",CliColor{"syntaxType"}},
    R.Property{"literal",CliColor{"syntaxNumber"}},
    R.Property{"number",CliColor{"syntaxNumber"}},
    R.Property{"regexp",CliColor{"syntaxString"}},
    R.Property{"string",CliColor{"syntaxString"}},
    R.Property{"comment",CliColor{"syntaxComment"}},
    R.Property{"doctag",CliColor{"syntaxComment"}},
    R.Property{"meta",CliColor{"muted"}},
    R.Property{"function",CliColor{"syntaxFunction"}},
    R.Property{"title",CliColor{"syntaxFunction"}},
    R.Property{"class",CliColor{"syntaxType"}},
    R.Property{"type",CliColor{"syntaxType"}},
    R.Property{"tag",CliColor{"syntaxPunctuation"}},
    R.Property{"name",CliColor{"syntaxKeyword"}},
    R.Property{"attr",CliColor{"syntaxVariable"}},
    R.Property{"variable",CliColor{"syntaxVariable"}},
    R.Property{"params",CliColor{"syntaxVariable"}},
    R.Property{"operator",CliColor{"syntaxOperator"}},
    R.Property{"punctuation",CliColor{"syntaxPunctuation"}},
    R.Property{"emphasis",CliItalic{}},
    R.Property{"strong",CliBold{}},
    R.Property{"link",CliUnderline{}},
    R.Property{"addition",CliColor{"toolDiffAdded"}},
    R.Property{"deletion",CliColor{"toolDiffRemoved"}}],R.new(CliFormatter))

# text.split("\n"), accumulating backwards (code can be long).
def splitLines(text: String,+current: String,+lines: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,String.reverse(current) <> lines)
    case SCon{Chr{10},rest}: splitLines(rest,"",String.reverse(current) <> lines)
    case SCon{char,rest}: splitLines(rest,SCon{char,current},lines)
def lines(text: String) -> List<&2,String>: splitLines(text,"",Nil{})
def colouredLines(+theme: Theme,+key: String,values: List<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: colouredLines(theme,key,rest,fg(theme,key,line) <> reversed)
def validLanguage(+highlighter: SyntaxHighlight.Highlighter,lang: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match lang:
    case None{}: IO.pure(Maybe<&2,String>,None{})
    case Some{""}: IO.pure(Maybe<&2,String>,None{})
    case Some{+language}:
      do IO<Maybe<&2,String>>:
        supported : Bool <- SyntaxHighlight.supportsLanguage(highlighter,language)
        return Bool.pick(Maybe<&2,String>,supported,Some{language},None{})
def highlightedLines(+theme: Theme,+code: String,result: Maybe<&2,String>,fallback: Bool) -> List<&2,String>:
  match result fallback:
    case Some{text} _: lines(text)
    case None{} True{}: colouredLines(theme,"mdCodeBlock",lines(code),Nil{})
    case None{} False{}: lines(code)
def highlightValid(highlighter: SyntaxHighlight.Highlighter,+theme: Theme,+code: String,valid: Maybe<&2,String>,fallback: Bool) -> IO(List<&2,String>):
  match valid:
    case None{}: IO.pure(List<&2,String>,colouredLines(theme,"mdCodeBlock",lines(code),Nil{}))
    case Some{language}:
      do IO<List<&2,String>>:
        result : Maybe<&2,String> <- SyntaxHighlight.highlight(~CliFormatter,~cliFormat,highlighter,code,SyntaxHighlight.HighlightOptions{Some{language},True{},None{}},buildCliHighlightTheme(theme))
        return highlightedLines(theme,code,result,fallback)
# highlightCode (and the Markdown theme's variant, whose failure fallback
# keeps the code-block colour): lines of `code` highlighted as `lang` when
# highlight.js knows it; unhighlighted mdCodeBlock lines otherwise, as
# auto-detection misreads prose.
def highlightLines(+highlighter: SyntaxHighlight.Highlighter,+theme: Theme,+code: String,lang: Maybe<&2,String>,fallback: Bool) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    valid : Maybe<&2,String> <- validLanguage(highlighter,lang)
    highlightValid(highlighter,theme,code,valid,fallback)
def highlightCode(highlighter: SyntaxHighlight.Highlighter,theme: Theme,code: String,lang: Maybe<&2,String>) -> IO(List<&2,String>):
  highlightLines(highlighter,theme,code,lang,False{})

# The language highlight.js knows a file by, from its extension.
def extensionLanguage(extension: String) -> Maybe<&2,String>:
  match extension:
    case "ts": Some{"typescript"}
    case "tsx": Some{"typescript"}
    case "js": Some{"javascript"}
    case "jsx": Some{"javascript"}
    case "mjs": Some{"javascript"}
    case "cjs": Some{"javascript"}
    case "py": Some{"python"}
    case "rb": Some{"ruby"}
    case "rs": Some{"rust"}
    case "go": Some{"go"}
    case "java": Some{"java"}
    case "kt": Some{"kotlin"}
    case "swift": Some{"swift"}
    case "c": Some{"c"}
    case "h": Some{"c"}
    case "cpp": Some{"cpp"}
    case "cc": Some{"cpp"}
    case "cxx": Some{"cpp"}
    case "hpp": Some{"cpp"}
    case "cs": Some{"csharp"}
    case "php": Some{"php"}
    case "sh": Some{"bash"}
    case "bash": Some{"bash"}
    case "zsh": Some{"bash"}
    case "fish": Some{"fish"}
    case "ps1": Some{"powershell"}
    case "sql": Some{"sql"}
    case "html": Some{"html"}
    case "htm": Some{"html"}
    case "css": Some{"css"}
    case "scss": Some{"scss"}
    case "sass": Some{"sass"}
    case "less": Some{"less"}
    case "json": Some{"json"}
    case "yaml": Some{"yaml"}
    case "yml": Some{"yaml"}
    case "toml": Some{"toml"}
    case "xml": Some{"xml"}
    case "md": Some{"markdown"}
    case "markdown": Some{"markdown"}
    case "dockerfile": Some{"dockerfile"}
    case "makefile": Some{"makefile"}
    case "cmake": Some{"cmake"}
    case "lua": Some{"lua"}
    case "perl": Some{"perl"}
    case "r": Some{"r"}
    case "scala": Some{"scala"}
    case "clj": Some{"clojure"}
    case "ex": Some{"elixir"}
    case "exs": Some{"elixir"}
    case "erl": Some{"erlang"}
    case "hs": Some{"haskell"}
    case "ml": Some{"ocaml"}
    case "vim": Some{"vim"}
    case "graphql": Some{"graphql"}
    case "proto": Some{"protobuf"}
    case "tf": Some{"hcl"}
    case "hcl": Some{"hcl"}
    case _: None{}
def lastSegment(parts: List<&2,String>) -> String:
  match parts:
    case Nil{}: ""
    case part <> Nil{}: part
    case _ <> rest: lastSegment(rest)
# filePath.split(".").pop(): the text after the last "." (the whole path
# without one).
def getLanguageFromPath(filePath: String) -> Maybe<&2,String>:
  extensionLanguage(Case.lower(lastSegment(String.split(filePath,'.'))))
