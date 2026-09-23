import Base
import ./color.bend as C
import ../../../../../runtime/src/json.bend as Json
import ../../../../../runtime/src/schema-value.bend as V
import ../../../../../runtime/src/record.bend as R
import ../../../../../runtime/src/f64.bend as F
import ../../../../../runtime/src/filesystem.bend as FS
import ../../../../../runtime/src/utf8.bend as Utf8
import ../../../../../runtime/src/posix-path.bend as Path

# Theme documents are immutable data. Variables are resolved once when a theme
# is loaded, so rendering never depends on JSON or mutable global state.
type Token is Data: Literal{color: C.Color} Reference{name: String}
type Theme is Data: Theme{name: String,mode: C.Mode,foreground: R.Record<C.Color>,background: R.Record<C.Color>}
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
      bind(R.Record<C.Color>,Theme,resolveOne(R.entries(Token,fallbacks(colors)),vars,True{},R.new(C.Color)),bg => Done{Theme{name,mode,fg,bg}})))
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

def wrapped(found: Maybe<&2,C.Color>,+mode: C.Mode,key: String,+text: String,bg: Bool) -> Result<&2,&2,Error,String>:
  match found:
    case None{}: Fail{MissingColor{key}}
    case Some{+color}:
      Bool.pick(Unit -> Result<&2,&2,Error,String>,bg,
        _ => Done{C.background(color,mode) ++ text ++ "\u{1b}[49m"},
        _ => Done{C.foreground(color,mode) ++ text ++ "\u{1b}[39m"})(Unit{})

def foreground(theme: Theme,+key: String,text: String) -> Result<&2,&2,Error,String>:
  match theme:
    case Theme{_,mode,colors,_}: wrapped(R.get(C.Color,colors,key),mode,key,text,False{})
def background(theme: Theme,+key: String,text: String) -> Result<&2,&2,Error,String>:
  match theme:
    case Theme{_,mode,_,colors}: wrapped(R.get(C.Color,colors,key),mode,key,text,True{})

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
def customTheme(+path: String,themeName: String,mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  do IO<Result<&2,&2,LoadError,Theme>>:
    present : Bool <- FS.accessible(path,0)
    Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),present,
      _ => loadFromPath(path,mode),
      _ => IO.pure(Result<&2,&2,LoadError,Theme>,Fail{NotFound{themeName}}))(Unit{})
def loadByName(+themeName: String,builtinDir: String,customDir: String,+mode: C.Mode) -> IO(Result<&2,&2,LoadError,Theme>):
  Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),String.contains(themeName,"/"),
    _ => IO.pure(Result<&2,&2,LoadError,Theme>,Fail{Invalid{InvalidName{themeName}}}),
    _ => Bool.pick(Unit -> IO(Result<&2,&2,LoadError,Theme>),String.eq(themeName,"dark") || String.eq(themeName,"light"),
      _ => loadFromPath(Path.join(builtinDir,themeName ++ ".json"),mode),
      _ => customTheme(Path.join(customDir,themeName ++ ".json"),themeName,mode))(Unit{}))(Unit{})
