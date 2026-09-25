import Base
import ../../../modes/interactive/components/messages.bend as Messages
import ../../../modes/interactive/theme/theme.bend as Theme
import ../../../../../runtime/src/schema-value.bend as Value
import ../render-utils.bend as Render
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../runtime/src/callback.bend as C

# The call previews the content being written; successful results need no
# second body because the call already shows it.
def trimmedReverse(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case "" <> rest: trimmedReverse(rest)
    case _: List.reverse(&2,String,lines)
def contentLines(content: String) -> List<&2,String>:
  trimmedReverse(List.reverse(&2,String,String.split(String.join(String.split(String.join(String.split(content,'\r'),""),'\t'),"   "),'\n')))
def coloredLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        colored : String <- Messages.foregroundText(theme,"toolOutput",line)
        coloredLines(rest,theme,colored <> reversed)
def expandHint(+theme: Theme.Theme,remaining: Nat,total: Nat) -> IO(String):
  do IO<String>:
    start : String <- Messages.foregroundText(theme,"muted","\n... (" ++ Nat.show(remaining) ++ " more lines, " ++ Nat.show(total) ++ " total,")
    key : String <- Messages.foregroundText(theme,"dim",Messages.expandKeys())
    rest : String <- Messages.foregroundText(theme,"muted"," to expand)")
    return start ++ " " ++ key ++ rest
# Syntax highlighting (upstream formatWriteCall): content of a file whose path
# names a language is highlighted instead of coloured as tool output.
def writeLanguage(path: Maybe<&2,String>) -> Maybe<&2,String>:
  match path:
    case Some{""}: None{}
    case Some{file}: Theme.getLanguageFromPath(file)
    case None{}: None{}
def trimmedLines(lines: List<&2,String>) -> List<&2,String>: trimmedReverse(List.reverse(&2,String,lines))
# normalizeDisplayText then replaceTabs.
def normalized(text: String) -> String: String.join(String.split(String.join(String.split(text,'\r'),""),'\t'),"   ")
def highlightLines(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,code: String,lang: String) -> IO(List<&2,String>):
  C.call(Markdown.HighlightInput,List<&2,String>,highlight,Markdown.HighlightInput{code,Some{lang}})

# upstream WriteHighlightCache: while arguments stream, new lines are
# highlighted one at a time and only the first 50 lines together, so a long
# preview is not highlighted again as a whole on every delta. Complete
# arguments are highlighted as a whole.
type WriteHighlightCache is Data:
  WriteHighlightCache{rawPath: Maybe<&2,String>,lang: String,rawContent: String,normalizedLines: List<&2,String>,highlightedLines: List<&2,String>}
def WRITE_PARTIAL_FULL_HIGHLIGHT_LINES() -> Nat: 50n
def firstLine(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> _: line
def highlightSingleLine(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,line: String,lang: String) -> IO(String):
  do IO<String>:
    lines : List<&2,String> <- highlightLines(highlight,line,lang)
    return firstLine(lines)
def singles(+highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,lines: List<&2,String>,+lang: String) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case line <> rest:
      do IO<List<&2,String>>:
        first : String <- highlightSingleLine(highlight,line,lang)
        others : List<&2,String> <- singles(highlight,rest,lang)
        return first <> others
# The prefix's joint highlighting, each missing line highlighted alone.
def prefixLines(+highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,sources: List<&2,String>,joint: List<&2,String>,+lang: String) -> IO(List<&2,String>):
  match sources joint:
    case Nil{} _: IO.pure(List<&2,String>,Nil{})
    case source <> rest Nil{}: singles(highlight,source <> rest,lang)
    case _ <> rest line <> more:
      do IO<List<&2,String>>:
        others : List<&2,String> <- prefixLines(highlight,rest,more,lang)
        return line <> others
def refreshWriteHighlightPrefix(+highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,cache: WriteHighlightCache) -> IO(WriteHighlightCache):
  match cache:
    case WriteHighlightCache{path,+lang,raw,+lines,highlighted}:
      +prefix = List.take(&2,String,lines,WRITE_PARTIAL_FULL_HIGHLIGHT_LINES())
      do IO<WriteHighlightCache>:
        joint : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,String,prefix),_ => IO.pure(List<&2,String>,Nil{}),_ => highlightLines(highlight,String.join(prefix,"\n"),lang))(Unit{})
        +head : List<&2,String> <- prefixLines(highlight,prefix,joint,lang)
        return WriteHighlightCache{path,lang,raw,lines,List.append(&2,String,head,List.drop(&2,String,highlighted,List.length(&2,String,head)))}
def rebuiltFor(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,language: Maybe<&2,String>,rawPath: Maybe<&2,String>,+fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  match language:
    case None{}: IO.pure(Maybe<&2,WriteHighlightCache>,None{})
    case Some{+lang}:
      +text = normalized(fileContent)
      do IO<Maybe<&2,WriteHighlightCache>>:
        highlighted : List<&2,String> <- highlightLines(highlight,text,lang)
        return Some{WriteHighlightCache{rawPath,lang,fileContent,String.split(text,'\n'),highlighted}}
def rebuildWriteHighlightCacheFull(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,+rawPath: Maybe<&2,String>,fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  rebuiltFor(highlight,writeLanguage(rawPath),rawPath,fileContent)
def samePath(left: Maybe<&2,String>,right: Maybe<&2,String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a,b)
    case _ _: False{}
def extendLast(lines: List<&2,String>,+tail: String) -> List<&2,String>:
  match lines:
    case Nil{}: [tail]
    case line <> Nil{}: [line ++ tail]
    case line <> rest: line <> extendLast(rest,tail)
def lastLine(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case line <> Nil{}: line
    case _ <> rest: lastLine(rest)
def withoutLast(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case _ <> Nil{}: Nil{}
    case line <> rest: line <> withoutLast(rest)
def restSegments(segments: List<&2,String>) -> List<&2,String>:
  match segments:
    case Nil{}: Nil{}
    case _ <> rest: rest
def appended(+highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,cache: WriteHighlightCache,+fileContent: String) -> IO(WriteHighlightCache):
  match cache:
    case WriteHighlightCache{path,+lang,+raw,+lines,+highlighted}:
      +segments = String.split(normalized(String.drop(fileContent,String.length(raw))),'\n')
      +grown = extendLast(Bool.pick(List<&2,String>,List.is_empty(&2,String,lines),[""],lines),firstLine(segments))
      do IO<WriteHighlightCache>:
        last : String <- highlightSingleLine(highlight,lastLine(grown),lang)
        +added : List<&2,String> <- IO.pure(List<&2,String>,restSegments(segments))
        more : List<&2,String> <- singles(highlight,added,lang)
        +kept : List<&2,String> <- IO.pure(List<&2,String>,withoutLast(Bool.pick(List<&2,String>,List.is_empty(&2,String,highlighted),[""],highlighted)))
        refreshWriteHighlightPrefix(highlight,WriteHighlightCache{path,lang,fileContent,List.append(&2,String,grown,added),List.append(&2,String,kept,last <> more)})
def incrementalStep(rebuild: Bool,same: Bool,highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,cache: WriteHighlightCache,rawPath: Maybe<&2,String>,fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  match rebuild same:
    case True{} _: rebuildWriteHighlightCacheFull(highlight,rawPath,fileContent)
    case False{} True{}: IO.pure(Maybe<&2,WriteHighlightCache>,Some{cache})
    case False{} False{}:
      do IO<Maybe<&2,WriteHighlightCache>>:
        next : WriteHighlightCache <- appended(highlight,cache,fileContent)
        return Some{next}
def incremental(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,cache: WriteHighlightCache,+rawPath: Maybe<&2,String>,+lang: String,+fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  match cache:
    case WriteHighlightCache{+path,+cached,+raw,lines,highlighted}:
      +rebuild = Bool.not(String.eq(cached,lang)) || Bool.not(samePath(path,rawPath)) || Bool.not(String.starts_with(fileContent,raw))
      incrementalStep(rebuild,Nat.is_eq(String.length(fileContent),String.length(raw)),highlight,WriteHighlightCache{path,cached,raw,lines,highlighted},rawPath,fileContent)
def updatedFor(+highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,language: Maybe<&2,String>,cache: Maybe<&2,WriteHighlightCache>,+rawPath: Maybe<&2,String>,+fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  match language cache:
    case None{} _: IO.pure(Maybe<&2,WriteHighlightCache>,None{})
    case Some{_} None{}: rebuildWriteHighlightCacheFull(highlight,rawPath,fileContent)
    case Some{lang} Some{current}: incremental(highlight,current,rawPath,lang,fileContent)
def updateWriteHighlightCacheIncremental(highlight: C.Callback<Markdown.HighlightInput,List<&2,String>>,cache: Maybe<&2,WriteHighlightCache>,+rawPath: Maybe<&2,String>,fileContent: String) -> IO(Maybe<&2,WriteHighlightCache>):
  updatedFor(highlight,writeLanguage(rawPath),cache,rawPath,fileContent)
# upstream writeRenderers.renderCall: complete arguments rebuild the cache,
# streamed ones extend it; without string content there is no cache.
def refreshedFor(highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,contentArg: Maybe<&2,String>,path: Maybe<&2,String>,argsComplete: Bool,cache: Maybe<&2,WriteHighlightCache>) -> IO(Maybe<&2,WriteHighlightCache>):
  match highlight contentArg argsComplete:
    case Some{callback} Some{fileContent} True{}: rebuildWriteHighlightCacheFull(callback,path,fileContent)
    case Some{callback} Some{fileContent} False{}: updateWriteHighlightCacheIncremental(callback,cache,path,fileContent)
    case _ _ _: IO.pure(Maybe<&2,WriteHighlightCache>,None{})
def refreshCache(highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,+args: Value.Value,argsComplete: Bool,cache: Maybe<&2,WriteHighlightCache>) -> IO(Maybe<&2,WriteHighlightCache>):
  refreshedFor(highlight,Render.argument(args,"content"),Render.path(args),argsComplete,cache)
def previewLines(highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,language: Maybe<&2,String>,cache: Maybe<&2,WriteHighlightCache>,body: String) -> IO(Maybe<&2,List<&2,String>>):
  match highlight language cache:
    case _ Some{_} Some{WriteHighlightCache{_,_,_,_,highlighted}}: IO.pure(Maybe<&2,List<&2,String>>,Some{trimmedLines(highlighted)})
    case Some{callback} Some{lang} None{}:
      do IO<Maybe<&2,List<&2,String>>>:
        lines : List<&2,String> <- highlightLines(callback,normalized(body),lang)
        return Some{trimmedLines(lines)}
    case _ _ _: IO.pure(Maybe<&2,List<&2,String>>,None{})
def previewAll(highlighted: Maybe<&2,List<&2,String>>,body: String) -> List<&2,String>:
  match highlighted:
    case Some{lines}: lines
    case None{}: contentLines(body)
def previewShown(highlighted: Maybe<&2,List<&2,String>>,display: List<&2,String>,+theme: Theme.Theme) -> IO(List<&2,String>):
  match highlighted:
    case Some{_}: IO.pure(List<&2,String>,display)
    case None{}: coloredLines(display,theme,Nil{})
def content(+theme: Theme.Theme,header: String,expanded: Bool,contentArg: Maybe<&2,String>,highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,cache: Maybe<&2,WriteHighlightCache>,language: Maybe<&2,String>) -> IO(String):
  match contentArg:
    case None{}:
      do IO<String>:
        invalid : String <- Messages.foregroundText(theme,"error","[invalid content arg - expected string]")
        return header ++ "\n\n" ++ invalid
    case Some{""}: IO.pure(String,header)
    case Some{+body}:
      do IO<String>:
        +highlighted : Maybe<&2,List<&2,String>> <- previewLines(highlight,language,cache,body)
        +all : List<&2,String> <- IO.pure(List<&2,String>,previewAll(highlighted,body))
        +display : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,expanded,all,List.take(&2,String,all,10n)))
        shown : List<&2,String> <- previewShown(highlighted,display,theme)
        +remaining : Nat <- IO.pure(Nat,List.length(&2,String,all) - List.length(&2,String,display))
        +preview : String <- IO.pure(String,header ++ "\n\n" ++ String.join(shown,"\n"))
        Bool.pick(Unit -> IO(String),Nat.is_eq(remaining,0n),_ => IO.pure(String,preview),
          _ => do IO<String>:
            hint : String <- expandHint(theme,remaining,List.length(&2,String,all))
            return preview ++ hint)(Unit{})
def renderCall(+args: Value.Value,highlight: Maybe<&2,C.Callback<Markdown.HighlightInput,List<&2,String>>>,cache: Maybe<&2,WriteHighlightCache>,+theme: Theme.Theme,expanded: Bool) -> IO(String):
  do IO<String>:
    header : String <- Render.pathCall(theme,"write",args)
    content(theme,header,expanded,Render.argument(args,"content"),highlight,cache,writeLanguage(Render.path(args)))
def renderError(output: String,theme: Theme.Theme) -> IO(String):
  match output:
    case SCon{_,_}:
      do IO<String>:
        colored : String <- Messages.foregroundText(theme,"error",output)
        return "\n" ++ colored
    case _: IO.pure(String,"")
def renderResult(output: String,isError: Bool,theme: Theme.Theme) -> IO(String):
  match isError:
    case True{}: renderError(output,theme)
    case False{}: IO.pure(String,"")
