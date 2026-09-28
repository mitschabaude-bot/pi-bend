import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../render-utils.bend as Render
import ../index.bend as Tools
import ../read.bend as Read
import ../truncate.bend as Truncate
import ../../../utils/paths.bend as Paths
import ../../../../../runtime/src/posix-path.bend as Path
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../runtime/src/callback.bend as C

# Read presentation uses the typed tool result; the collapsed success view is
# intentionally just its path and optional line range.
def natural(value: Maybe<&2,Value.Value>) -> Maybe<&2,Nat>:
  match value:
    case Some{Value.Number{number}}: Some{U32.to_nat(F64.to_u32(number))}
    case _: None{}
def range(theme: Theme.Theme,offset: Maybe<&2,Nat>,limit: Maybe<&2,Nat>) -> IO(String):
  match offset limit:
    case None{} None{}: IO.pure(String,"")
    case Some{start} None{}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start))
    case None{} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ "1" ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(count)))
    case Some{+start} Some{+count}: Messages.foregroundText(theme,"warning",":" ++ Nat.show(start) ++ Bool.pick(String,Nat.is_eq(count,0n),"","-" ++ Nat.show(start + count - 1n)))
def renderCall(+args: Value.Value,+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    title : String <- Render.pathCall(theme,"read",args)
    lines : String <- range(theme,natural(Render.field(args,"offset")),natural(Render.field(args,"limit")))
    return title ++ lines

# Ambient renderer inputs are explicit and reused by mounted components.
type Context is Data: Context{paths: Paths.Environment,packageRoot: String,expandKey: String}
type CompactKind is Data: Skill{} Docs{} Resource{}
type Classification is Data: Classification{kind: CompactKind,label: String}
def resourceName(+name: String) -> Bool:
  String.eq(name,"AGENTS.override.md") || String.eq(name,"AGENTS.md") || String.eq(name,"AGENTS.MD") || String.eq(name,"CLAUDE.md") || String.eq(name,"CLAUDE.MD")
def docsLabel(+relative: String) -> Maybe<&2,Classification>:
  Bool.pick(Maybe<&2,Classification>,String.eq(relative,"README.md") || String.starts_with(relative,"docs/") || String.starts_with(relative,"examples/"),Some{Classification{Docs{},relative}},None{})
def resourceLabel(context: Context,+cwd: String,+absolute: String,docs: Maybe<&2,Classification>) -> Maybe<&2,Classification>:
  match docs context:
    case Some{value} _: Some{value}
    case None{} Context{paths,_,_}:
      Bool.pick(Maybe<&2,Classification>,resourceName(Path.basename(absolute)),Some{Classification{Resource{},Result.default(&2,&2,Paths.Error,String,Paths.formatPathRelativeToCwdOrAbsolute(paths,absolute,cwd),absolute)}},None{})
def classifiedPath(+context: Context,+cwd: String,+absolute: String) -> Maybe<&2,Classification>:
  match context:
    case Context{_,root,_}:
      +name = Path.basename(absolute)
      +parent = Path.basename(Path.normalize(absolute ++ "/.."))
      Bool.pick(Unit -> Maybe<&2,Classification>,String.eq(name,"SKILL.md"),
        _ => Some{Classification{Skill{},Bool.pick(String,String.eq(parent,""),name,parent)}},
        _ => resourceLabel(context,cwd,absolute,docsLabel(Path.relative(Maybe.default(&2,String,Path.resolve(cwd,root),root),absolute))))(Unit{})
def resolvedClassification(context: Context,cwd: String,resolved: Result<&2,&2,Paths.Error,String>) -> Maybe<&2,Classification>:
  match resolved:
    case Done{path}: classifiedPath(context,cwd,path)
    case Fail{_}: None{}
def classify(context: Context,+cwd: String,path: Maybe<&2,String>) -> Maybe<&2,Classification>:
  match context path:
    case Context{+paths,+root,+key} Some{SCon{first,rest}}:
      resolvedClassification(Context{paths,root,key},cwd,Paths.resolveToCwd(paths,SCon{first,rest},cwd))
    case _ _: None{}
def isSkill(kind: CompactKind) -> Bool:
  match kind: case Skill{}: True{} case _: False{}
def isDocs(kind: CompactKind) -> Bool:
  match kind: case Docs{}: True{} case _: False{}
def compactCall(classification: Classification,+args: Value.Value,+theme: Theme.Theme,key: String) -> IO(String):
  match classification:
    case Classification{+kind,label}:
      do IO<String>:
        title : String <- Bool.pick(Unit -> IO(String),isSkill(kind),
          _ => Messages.foregroundText(theme,"customMessageLabel","\u{1b}[1m[skill]\u{1b}[22m "),
          _ => do IO<String>:
            title : String <- Render.title(theme,Bool.pick(String,isDocs(kind),"read docs","read resource"))
            return title ++ " ")(Unit{})
        name : String <- Messages.foregroundText(theme,Bool.pick(String,isSkill(kind),"customMessageText","accent"),label)
        lines : String <- range(theme,natural(Render.field(args,"offset")),natural(Render.field(args,"limit")))
        hint : String <- Messages.foregroundText(theme,"dim"," (" ++ key ++ " to expand)")
        return title ++ name ++ lines ++ hint

def classifiedCall(classification: Maybe<&2,Classification>,args: Value.Value,theme: Theme.Theme,key: String) -> IO(String):
  match classification:
    case None{}: renderCall(args,theme)
    case Some{value}: compactCall(value,args,theme,key)
def renderCallWithContext(+args: Value.Value,theme: Theme.Theme,expanded: Bool,context: Maybe<&2,Context>,cwd: String) -> IO(String):
  match context expanded:
    case Some{Context{+paths,+root,+key}} False{}: classifiedCall(classify(Context{paths,root,key},cwd,Render.path(args)),args,theme,key)
    case _ _: renderCall(args,theme)

def trimmedReverse(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case "" <> rest: trimmedReverse(rest)
    case _: List.reverse(&2,String,lines)
def contentLines(text: String) -> List<&2,String>:
  trimmedReverse(List.reverse(&2,String,String.split(String.join(String.split(text,'\t'),"   "),'\n')))
def colored(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        value : String <- Messages.foregroundText(theme,"toolOutput",line)
        colored(rest,theme,value <> reversed)
def notice(details: Maybe<&2,Tools.ToolDetails>) -> String:
  match details:
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},_,totalLines,_,outputLines,_,_,True{},_,maxBytes}}}}:
      "[First line exceeds " ++ Truncate.formatSize(maxBytes) ++ " limit]"
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},Some{Truncate.Lines{}},totalLines,_,outputLines,_,_,False{},maxLines,_}}}}:
      "[Truncated: showing " ++ Nat.show(outputLines) ++ " of " ++ Nat.show(totalLines) ++ " lines (" ++ Nat.show(maxLines) ++ " line limit)]"
    case Some{Tools.ReadDetails{Read.ReadToolDetails{Truncate.TruncationResult{_,True{},_,_,_,outputLines,_,_,False{},_,maxBytes}}}}:
      "[Truncated: " ++ Nat.show(outputLines) ++ " lines shown (" ++ Truncate.formatSize(maxBytes) ++ " limit)]"
    case _: ""
def warning(theme: Theme.Theme,text: String) -> IO(String):
  match text:
    case "": IO.pure(String,"")
    case value:
      do IO<String>:
        colored : String <- Messages.foregroundText(theme,"warning",value)
        return "\n" ++ colored
# Syntax highlighting (upstream formatReadResult): the output of a file whose
# path names a language is highlighted as a whole, after tab expansion, and
# shown as highlighted instead of in the tool output colour.
def readLanguage(isError: Bool,path: Maybe<&2,String>) -> Maybe<&2,String>:
  match isError path:
    case False{} Some{""}: None{}
    case False{} Some{file}: Theme.getLanguageFromPath(file)
    case _ _: None{}
def highlightedOutput(highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,language: Maybe<&2,String>,output: String) -> IO(Maybe<&2,List<&2,String>>):
  match highlight language:
    case Some{callback} Some{lang}:
      do IO<Maybe<&2,List<&2,String>>>:
        lines : List<&2,String> <- C.call(Markdown.HighlightInput,List<&2,String>,callback,Markdown.HighlightInput{String.join(String.split(output,'\t'),"   "),Some{lang}})
        return Some{trimmedReverse(List.reverse(&2,String,lines))}
    case _ _: IO.pure(Maybe<&2,List<&2,String>>,None{})
def sourceLines(highlighted: Maybe<&2,List<&2,String>>,output: String) -> List<&2,String>:
  match highlighted:
    case Some{lines}: lines
    case None{}: contentLines(output)
def displayed(highlighted: Maybe<&2,List<&2,String>>,shown: List<&2,String>,+theme: Theme.Theme) -> IO(List<&2,String>):
  match highlighted:
    case Some{_}: IO.pure(List<&2,String>,shown)
    case None{}: colored(shown,theme,Nil{})
def expandHint(+theme: Theme.Theme,remaining: Nat) -> IO(String):
  match remaining:
    case Zero{}: IO.pure(String,"")
    case count:
      do IO<String>:
        start : String <- Messages.foregroundText(theme,"muted","\n... (" ++ Nat.show(count) ++ " more lines,")
        key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
        end : String <- Messages.foregroundText(theme,"muted"," to expand")
        close : String <- Messages.foregroundText(theme,"muted",")")
        return start ++ " " ++ key ++ end ++ close
def renderResult(+args: Value.Value,highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,+output: String,details: Maybe<&2,Tools.ToolDetails>,expanded: Bool,isError: Bool,+theme: Theme.Theme) -> IO(String):
  match expanded isError:
    case False{} False{}: IO.pure(String,"")
    case _ _:
      do IO<String>:
        +highlighted : Maybe<&2,List<&2,String>> <- highlightedOutput(highlight,readLanguage(isError,Render.path(args)),output)
        +lines : List<&2,String> <- IO.pure(List<&2,String>,sourceLines(highlighted,output))
        +shown : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,lines,List.take(&2,String,lines,10n)))
        rendered : List<&2,String> <- displayed(highlighted,shown,theme)
        hint : String <- expandHint(theme,List.length(&2,String,lines) - List.length(&2,String,shown))
        truncated : String <- warning(theme,notice(details))
        return "\n\n" ++ String.join(rendered,"\n") ++ hint ++ truncated
