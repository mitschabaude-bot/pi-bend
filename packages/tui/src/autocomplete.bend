import Base
import ./fuzzy.bend as Fuzzy
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/posix-path.bend as Path
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/text.bend as Text
import ../../runtime/src/case-fold.bend as Fold
import ../../runtime/src/stable-sort.bend as Sort
import ../../runtime/src/file-search.bend as Search
import ../../runtime/src/regex.bend as Regex

type AutocompleteItem is Data:
  AutocompleteItem{value: String,label: String,description: Maybe<&2,String>}
type AutocompleteSuggestions is Data:
  AutocompleteSuggestions{items: List<&2,AutocompleteItem>,prefix: String}
type Error is Data:
  InvalidCursor{} InvalidPrefix{} InvalidBasePath{}
  Filesystem{cause: FS.Error}
  Operation{message: String}
  SearchFailure{cause: Search.Error}
  InvalidQuery{cause: Regex.Error}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
type SlashCommand is Data:
  SlashCommand{name: String,description: Maybe<&2,String>,argumentHint: Maybe<&2,String>,getArgumentCompletions: Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)>>}
type Command is Data:
  Slash{command: SlashCommand}
  Item{item: AutocompleteItem}
# Explicit policy: locale collation is pending, not silently replaced by either.
type SortPolicy is Data: ScalarOrder{} FoldedScalarOrder{}
type CombinedAutocompleteProvider is Data:
  CombinedAutocompleteProvider{commands: List<&2,Command>,basePath: String,homePath: String,sortPolicy: SortPolicy,recursiveFiles: Bool}
type Options is Data:
  Options{signal: Maybe<&2,Abort.AbortSignal<Unit>>,force: Bool}
type Completion is Data:
  Completion{lines: List<&2,String>,cursorLine: Nat,cursorCol: Nat}
type LineParts is Data: LineParts{before: String,after: String}
type PathPrefix is Data: PathPrefix{rawPrefix: String,isAtPrefix: Bool,isQuotedPrefix: Bool}

# Cursor offsets count native Unicode scalars. Invalid coordinates are explicit.
def splitAt(text: String,count: Nat,reversed: String) -> Maybe<&2,LineParts>:
  match text count:
    case text Zero{}: Some{LineParts{String.reverse(reversed),text}}
    case SCon{char,rest} Succ{left}: splitAt(rest,left,SCon{char,reversed})
    case SNil{} Succ{_}: None{}
def lineAt(lines: List<&2,String>,index: Nat) -> Maybe<&2,String>:
  match lines index:
    case text <> _ Zero{}: Some{text}
    case _ <> rest Succ{left}: lineAt(rest,left)
    case Nil{} _: None{}
def checkedLine(line: Maybe<&2,String>,column: Nat) -> ResultOf(LineParts):
  match line:
    case None{}: Fail{InvalidCursor{}}
    case Some{text}: Maybe.default(&2,ResultOf(LineParts),Maybe.map(&2,LineParts,ResultOf(LineParts),parts => Done{parts},splitAt(text,column,"")),Fail{InvalidCursor{}})
def view(lines: List<&2,String>,line: Nat,column: Nat) -> ResultOf(LineParts): checkedLine(lineAt(lines,line),column)
def replaceLine(lines: List<&2,String>,index: Nat,value: String,reversed: List<&2,String>) -> List<&2,String>:
  match lines index:
    case _ <> rest Zero{}: List.reverse.go(&2,String,reversed,value <> rest)
    case head <> rest Succ{left}: replaceLine(rest,left,value,head <> reversed)
    case Nil{} _: Nil{}
def delimiter(+char: Char) -> Bool:
  Char.is_eq(char,' ') || Char.is_eq(char,'\t') || Char.is_eq(char,'"') || Char.is_eq(char,'\'') || Char.is_eq(char,'=')
def trimStart(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{+char,+rest}: Bool.pick(Unit -> String,Text.whitespace(Char.to_u32(char)),_ => trimStart(rest),_ => SCon{char,rest})(Unit{})
def blank(text: String) -> Bool: String.is_empty(trimStart(text))
def starts(text: String,prefix: String) -> Bool:
  match text prefix:
    case _ SNil{}: True{}
    case SCon{a,+restA} SCon{b,+restB}: Bool.pick(Unit -> Bool,Char.is_eq(a,b),_ => starts(restA,restB),_ => False{})(Unit{})
    case _ _: False{}
def last(text: String,previous: Maybe<&2,Char>) -> Maybe<&2,Char>:
  match text:
    case SNil{}: previous
    case SCon{char,rest}: last(rest,Some{char})
def ends(text: String,wanted: Char) -> Bool:
  Maybe.default(&2,Bool,Maybe.map(&2,Char,Bool,char => Char.is_eq(char,wanted),last(text,None{})),False{})
def contains(text: String,+wanted: Char) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,+rest}: Bool.pick(Unit -> Bool,Char.is_eq(char,wanted),_ => True{},_ => contains(rest,wanted))(Unit{})

# Retain suffix pointers while scanning. Quoted tokens may include delimiters;
# only quotes at token boundaries (optionally after @) start path completion.
type PrefixScan is Data:
  PrefixScan{token: String,quoted: Maybe<&2,String>,inside: Bool,boundary: Bool,atStart: Maybe<&2,String>}
def quotePrefix(text: String,at: Maybe<&2,String>,boundary: Bool) -> Maybe<&2,String>:
  match at:
    case Some{prefix}: Some{prefix}
    case None{}: Bool.pick(Maybe<&2,String>,boundary,Some{text},None{})
def scanPrefix(text: String,state: PrefixScan) -> PrefixScan:
  match text state:
    case SNil{} state: state
    case SCon{+char,+rest} PrefixScan{+token,+quoted,+inside,+boundary,at}:
      +full = {SCon{char,rest}: String}
      +quote = Char.is_eq(char,'"')
      +separates = delimiter(char)
      scanPrefix(rest,PrefixScan{
        Bool.pick(String,separates,rest,token),
        Bool.pick(Maybe<&2,String>,quote,Bool.pick(Maybe<&2,String>,inside,None{},quotePrefix(full,at,boundary)),quoted),
        Bool.pick(Bool,quote,Bool.not(inside),inside),separates,
        Bool.pick(Maybe<&2,String>,boundary && Char.is_eq(char,'@'),Some{full},None{})})
def prefixes(+text: String) -> PrefixScan: scanPrefix(text,PrefixScan{text,None{},False{},True{},None{}})
def atFrom(value: PrefixScan) -> Maybe<&2,String>:
  match value:
    case PrefixScan{+token,Some{+quoted},_,_,_}:
      Bool.pick(Maybe<&2,String>,starts(quoted,"@\""),Some{quoted},Bool.pick(Maybe<&2,String>,starts(token,"@"),Some{token},None{}))
    case PrefixScan{+token,_,_,_,_}: Bool.pick(Maybe<&2,String>,starts(token,"@"),Some{token},None{})
def extractAtPrefix(text: String) -> Maybe<&2,String>: atFrom(prefixes(text))
def pathFrom(text: String,force: Bool,value: PrefixScan) -> Maybe<&2,String>:
  match value:
    case PrefixScan{_,Some{quoted},_,_,_}: Some{quoted}
    case PrefixScan{+token,_,_,_,_}:
      Bool.pick(Maybe<&2,String>,force || contains(token,'/') || starts(token,".") || (String.is_empty(token) && ends(text,' ')),Some{token},None{})
def extractPathPrefix(+text: String,force: Bool) -> Maybe<&2,String>: pathFrom(text,force,prefixes(text))
def parsePathPrefix(prefix: String) -> PathPrefix:
  match prefix:
    case SCon{'@',SCon{'"',rest}}: PathPrefix{rest,True{},True{}}
    case SCon{'"',rest}: PathPrefix{rest,False{},True{}}
    case SCon{'@',rest}: PathPrefix{rest,True{},False{}}
    case text: PathPrefix{text,False{},False{}}
def buildCompletionValue(+path: String,at: Bool,quoted: Bool) -> String:
  Bool.pick(String,at,"@","") ++ Bool.pick(String,quoted || contains(path,' '),"\"" ++ path ++ "\"",path)

def shouldTrigger(parts: ResultOf(LineParts)) -> ResultOf(Bool):
  match parts:
    case Fail{error}: Fail{error}
    case Done{LineParts{before,_}}:
      +text = trimStart(before)
      Done{Bool.not(starts(text,"/") && Bool.not(contains(text,' ')))}
def shouldTriggerFileCompletion(lines: List<&2,String>,cursorLine: Nat,cursorCol: Nat) -> ResultOf(Bool):
  shouldTrigger(view(lines,cursorLine,cursorCol))

def applied(+lines: List<&2,String>,+line: Nat,item: AutocompleteItem,+prefix: String,+after: String,value: Maybe<&2,LineParts>) -> ResultOf(Completion):
  match item value:
    case _ None{}: Fail{InvalidPrefix{}}
    case AutocompleteItem{+value,label,_} Some{LineParts{+before,+actual}}:
      +quoted = starts(prefix,"\"") || starts(prefix,"@\"")
      +tail = Bool.pick(String,quoted && ends(value,'"') && starts(after,"\""),String.drop(after,1n),after)
      +command = starts(prefix,"/") && blank(before) && Bool.not(contains(String.drop(prefix,1n),'/'))
      +directory = ends(label,'/')
      +attachment = starts(prefix,"@")
      +suffix = Bool.pick(String,command || (attachment && Bool.not(directory))," ","")
      +inserted = Bool.pick(String,command,"/","") ++ value ++ suffix
      offset = String.length(inserted) - Bool.pick(Nat,Bool.not(command) && directory && ends(value,'"'),1n,0n)
      Bool.pick(ResultOf(Completion),Strings.equal(actual,prefix),Done{Completion{replaceLine(lines,line,before ++ inserted ++ tail,Nil{}),line,String.length(before) + offset}},Fail{InvalidPrefix{}})
def applyView(lines: List<&2,String>,line: Nat,item: AutocompleteItem,+prefix: String,parts: ResultOf(LineParts)) -> ResultOf(Completion):
  match parts:
    case Fail{error}: Fail{error}
    case Done{LineParts{+before,after}}:
      Bool.pick(Unit -> ResultOf(Completion),Nat.is_ge(String.length(before),String.length(prefix)),
        _ => applied(lines,line,item,prefix,after,splitAt(before,String.length(before) - String.length(prefix),"")),
        _ => Fail{InvalidPrefix{}})(Unit{})
def applyCompletion(+lines: List<&2,String>,+cursorLine: Nat,cursorCol: Nat,item: AutocompleteItem,prefix: String) -> ResultOf(Completion):
  applyView(lines,cursorLine,item,prefix,view(lines,cursorLine,cursorCol))

def commandName(value: Command) -> String:
  match value:
    case Slash{SlashCommand{name,_,_,_}}: name
    case Item{AutocompleteItem{value,_,_}}: value
def description(description: Maybe<&2,String>,hint: Maybe<&2,String>) -> Maybe<&2,String>:
  +text = Maybe.default(&2,String,description,"")
  +argument = Maybe.default(&2,String,hint,"")
  +joined = Bool.pick(String,String.is_empty(argument),text,argument ++ Bool.pick(String,String.is_empty(text),""," — " ++ text))
  Bool.pick(Maybe<&2,String>,String.is_empty(joined),None{},Some{joined})
def commandItem(value: Command) -> AutocompleteItem:
  match value:
    case Slash{SlashCommand{+name,desc,hint,_}}: AutocompleteItem{name,name,description(desc,hint)}
    case Item{AutocompleteItem{+value,_,desc}}: AutocompleteItem{value,value,description(desc,None{})}
def itemText(value: AutocompleteItem) -> String:
  match value:
    case AutocompleteItem{text,_,_}: text
def suggestions(prefix: String,items: List<&2,AutocompleteItem>) -> Maybe<&2,AutocompleteSuggestions>:
  match items:
    case Nil{}: None{}
    case values: Some{AutocompleteSuggestions{values,prefix}}
def commandItems(values: List<&2,Command>,reversed: List<&2,AutocompleteItem>) -> List<&2,AutocompleteItem>:
  match values:
    case Nil{}: List.reverse(&2,AutocompleteItem,reversed)
    case command <> rest: commandItems(rest,commandItem(command) <> reversed)
def commandSuggestions(commands: List<&2,Command>,+prefix: String) -> Maybe<&2,AutocompleteSuggestions>:
  suggestions(prefix,Fuzzy.fuzzyFilter(~AutocompleteItem,~itemText,commandItems(commands,Nil{}),String.drop(prefix,1n)))

def foldedStarts(text: String,prefix: String) -> Bool:
  match text prefix:
    case _ SNil{}: True{}
    case SCon{a,+restA} SCon{b,+restB}: Bool.pick(Unit -> Bool,Fold.equal(a,b),_ => foldedStarts(restA,restB),_ => False{})(Unit{})
    case _ _: False{}
def minimumCode(values: List<&2,Char>,+minimum: U32) -> U32:
  match values:
    case Nil{}: minimum
    case Chr{+code} <> rest: minimumCode(rest,Bool.pick(U32,U32.is_lt(code,minimum),code,minimum))
def scalarCompare(left: String,right: String) -> Cmp:
  match left right:
    case SNil{} SNil{}: EQ{}
    case SNil{} _: LT{}
    case _ SNil{}: GT{}
    case SCon{Chr{+a},+restA} SCon{Chr{+b},+restB}:
      Bool.pick(Unit -> Cmp,U32.is_eq(a,b),_ => scalarCompare(restA,restB),_ => Bool.pick(Cmp,U32.is_lt(a,b),LT{},GT{}))(Unit{})
def foldedCompare(left: String,right: String) -> Cmp:
  match left right:
    case SNil{} SNil{}: EQ{}
    case SNil{} _: LT{}
    case _ SNil{}: GT{}
    case SCon{+a,+restA} SCon{+b,+restB}:
      +first = minimumCode(Fold.variants(a),Char.to_u32(a))
      +second = minimumCode(Fold.variants(b),Char.to_u32(b))
      Bool.pick(Unit -> Cmp,U32.is_eq(first,second),_ => foldedCompare(restA,restB),_ => Bool.pick(Cmp,U32.is_lt(first,second),LT{},GT{}))(Unit{})
def lessEqual(value: Cmp) -> Bool:
  match value:
    case GT{}: False{}
    case _: True{}
def directoryOrder(a: AutocompleteItem,b: AutocompleteItem) -> Maybe<&2,Bool>:
  match a b:
    case AutocompleteItem{_,+a,_} AutocompleteItem{_,+b,_}:
      +aDir = ends(a,'/')
      +bDir = ends(b,'/')
      Bool.pick(Maybe<&2,Bool>,(aDir && bDir) || (Bool.not(aDir) && Bool.not(bDir)),None{},Some{aDir})
def scalarItemBefore(+a: AutocompleteItem,+b: AutocompleteItem) -> Bool:
  match a b:
    case AutocompleteItem{_,aLabel,_} AutocompleteItem{_,bLabel,_}: Maybe.default(&2,Bool,directoryOrder(a,b),lessEqual(scalarCompare(aLabel,bLabel)))
def foldedItemBefore(+a: AutocompleteItem,+b: AutocompleteItem) -> Bool:
  match a b:
    case AutocompleteItem{_,aLabel,_} AutocompleteItem{_,bLabel,_}: Maybe.default(&2,Bool,directoryOrder(a,b),lessEqual(foldedCompare(aLabel,bLabel)))
def sortItems(policy: SortPolicy,items: List<&2,AutocompleteItem>) -> List<&2,AutocompleteItem>:
  match policy:
    case ScalarOrder{}: Sort.sort(~AutocompleteItem,~(a => b => scalarItemBefore(a,b)),items)
    case FoldedScalarOrder{}: Sort.sort(~AutocompleteItem,~(a => b => foldedItemBefore(a,b)),items)

# POSIX lexical path components. Backslashes remain literal filename characters.
def skipSlashes(text: String) -> String:
  match text:
    case SCon{'/',rest}: skipSlashes(rest)
    case value: value
def basenameReversed(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{'/',_}: reversed
    case SCon{char,rest}: basenameReversed(rest,SCon{char,reversed})
def basename(path: String) -> String: basenameReversed(skipSlashes(String.reverse(path)),"")
def dirnameReversed(text: String,root: Bool) -> String:
  match text:
    case SNil{}: Bool.pick(String,root,"/",".")
    case SCon{'/',+rest}: Bool.pick(String,String.is_empty(rest),"/",String.reverse(rest))
    case SCon{_,rest}: dirnameReversed(rest,root)
def dirname(+path: String) -> String: dirnameReversed(skipSlashes(String.reverse(path)),Path.isAbsolute(path))
def expandHome(home: String,path: String) -> String:
  match path:
    case "~": home
    case SCon{'~',SCon{'/',rest}}: Path.join(home,rest)
    case path: path
def searchPath(base: String,+raw: String,+expanded: String) -> String:
  Bool.pick(String,Strings.equal(raw,"~") || starts(raw,"~/") || Path.isAbsolute(expanded),expanded,Path.join(base,expanded))
type FileQuery is Data:
  FileQuery{directory: String,searchPrefix: String,display: PathPrefix}
def fileQueryParsed(base: String,home: String,+display: PathPrefix) -> FileQuery:
  match display:
    case PathPrefix{+raw,_,_}:
      +expanded = expandHome(home,raw)
      +root = String.is_empty(raw) || Strings.equal(raw,"~") || ends(raw,'/')
      FileQuery{searchPath(base,raw,Bool.pick(String,root,expanded,dirname(expanded))),Bool.pick(String,root,"",basename(expanded)),display}
def fileQuery(provider: CombinedAutocompleteProvider,prefix: String) -> FileQuery:
  match provider:
    case CombinedAutocompleteProvider{_,base,home,_,_}: fileQueryParsed(base,home,parsePathPrefix(prefix))
def displayPath(+raw: String,+name: String) -> String:
  Bool.pick(Unit -> String,ends(raw,'/'),_ => raw ++ name,
    _ => Bool.pick(Unit -> String,contains(raw,'/'),
      _ => Bool.pick(Unit -> String,starts(raw,"~/"),
        _ => "~/" ++ Path.join(dirname(String.drop(raw,2n)),name),
        _ => Bool.pick(String,starts(raw,"./"),"./","") ++ Path.join(dirname(raw),name))(Unit{}),
      _ => Bool.pick(String,Strings.equal(raw,"~"),"~/","") ++ name)(Unit{}))(Unit{})
def fileItem(display: PathPrefix,+name: String,+directory: Bool) -> AutocompleteItem:
  match display:
    case PathPrefix{raw,at,quoted}:
      AutocompleteItem{buildCompletionValue(displayPath(raw,name) ++ Bool.pick(String,directory,"/",""),at,quoted),name ++ Bool.pick(String,directory,"/",""),None{}}
def directoryKind(value: Result<&2,&2,FS.Error,FS.FileKind>) -> Bool:
  match value:
    case Done{FS.Directory{}}: True{}
    case _: False{}
def entryDirectory(parent: String,name: String,kind: FS.FileKind) -> IO(Bool):
  match kind:
    case FS.Directory{}: IO.pure(Bool,True{})
    case FS.SymbolicLink{}:
      do IO<Bool>:
        value : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(Path.join(parent,name))
        return directoryKind(value)
    case _: IO.pure(Bool,False{})
def directoryItems(entries: List<&2,FS.DirectoryEntry>,+query: FileQuery,+reversed: List<&2,AutocompleteItem>) -> IO(List<&2,AutocompleteItem>):
  match entries query:
    case Nil{} _: IO.pure(List<&2,AutocompleteItem>,List.reverse(&2,AutocompleteItem,reversed))
    case FS.DirectoryEntry{+name,kind} <> +rest FileQuery{directory,prefix,display}:
      Bool.pick(Unit -> IO(List<&2,AutocompleteItem>),foldedStarts(name,prefix),
        _ => do IO<List<&2,AutocompleteItem>>:
          directory : Bool <- entryDirectory(directory,name,kind)
          directoryItems(rest,query,fileItem(display,name,directory) <> reversed),
        _ => directoryItems(rest,query,reversed))(Unit{})
def fileSuggestionsResult(query: FileQuery,policy: SortPolicy,result: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> IO(ResultOf(List<&2,AutocompleteItem>)):
  match result:
    case Fail{FS.System{_,_}}: IO.pure(ResultOf(List<&2,AutocompleteItem>),Done{Nil{}})
    case Fail{cause}: IO.pure(ResultOf(List<&2,AutocompleteItem>),Fail{Filesystem{cause}})
    case Done{entries}:
      do IO<ResultOf(List<&2,AutocompleteItem>)>:
        items : List<&2,AutocompleteItem> <- directoryItems(entries,query,Nil{})
        return Done{sortItems(policy,items)}
def readSuggestions(+query: FileQuery,policy: SortPolicy) -> IO(ResultOf(List<&2,AutocompleteItem>)):
  match query:
    case FileQuery{directory,_,_}:
      do IO<ResultOf(List<&2,AutocompleteItem>)>:
        entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(directory)
        fileSuggestionsResult(query,policy,entries)
def getFileSuggestions(+provider: CombinedAutocompleteProvider,prefix: String) -> IO(ResultOf(List<&2,AutocompleteItem>)):
  match provider:
    case CombinedAutocompleteProvider{_,_,_,policy,_}: readSuggestions(fileQuery(provider,prefix),policy)

# Command callbacks are caller-owned; the provider does not retain an execution
# after getSuggestions returns. They run outside any lock and may re-enter it.
def commandArguments(text: String,reversed: String) -> Maybe<&2,LineParts>:
  match text:
    case SNil{}: None{}
    case SCon{' ',rest}: Some{LineParts{String.reverse(reversed),rest}}
    case SCon{char,rest}: commandArguments(rest,SCon{char,reversed})
def callbackFor(commands: List<&2,Command>,+name: String) -> Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)>>:
  match commands:
    case Nil{}: None{}
    case Slash{SlashCommand{command,_,_,+callback}} <> +rest:
      Bool.pick(Unit -> Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)>>,Strings.equal(command,name),_ => callback,_ => callbackFor(rest,name))(Unit{})
    case Item{AutocompleteItem{value,_,_}} <> +rest:
      Bool.pick(Unit -> Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)>>,Strings.equal(value,name),_ => None{},_ => callbackFor(rest,name))(Unit{})
def argumentResult(prefix: String,value: ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)) -> ResultOf(Maybe<&2,AutocompleteSuggestions>):
  match value:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{None{}}
    case Done{Some{items}}: Done{suggestions(prefix,items)}
def argumentsFrom(callback: Maybe<&2,Callback.Callback<String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>)>>,+prefix: String) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  match callback:
    case None{}: IO.pure(ResultOf(Maybe<&2,AutocompleteSuggestions>),Done{None{}})
    case Some{callback}:
      do IO<ResultOf(Maybe<&2,AutocompleteSuggestions>)>:
        value : ResultOf(Maybe<&2,List<&2,AutocompleteItem>>) <- Callback.call(String,ResultOf(Maybe<&2,List<&2,AutocompleteItem>>),callback,prefix)
        return argumentResult(prefix,value)
def slashSuggestions(commands: List<&2,Command>,+before: String,arguments: Maybe<&2,LineParts>) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  match arguments:
    case None{}: IO.pure(ResultOf(Maybe<&2,AutocompleteSuggestions>),Done{commandSuggestions(commands,before)})
    case Some{LineParts{name,prefix}}: argumentsFrom(callbackFor(commands,String.drop(name,1n)),prefix)
def pathSuggestions(provider: CombinedAutocompleteProvider,prefix: Maybe<&2,String>) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  match prefix:
    case None{}: IO.pure(ResultOf(Maybe<&2,AutocompleteSuggestions>),Done{None{}})
    case Some{+prefix}:
      do IO<ResultOf(Maybe<&2,AutocompleteSuggestions>)>:
        value : ResultOf(List<&2,AutocompleteItem>) <- getFileSuggestions(provider,prefix)
        return Result.map(&2,&2,Error,List<&2,AutocompleteItem>,Maybe<&2,AutocompleteSuggestions>,items => suggestions(prefix,items),value)
def create(commands: List<&2,Command>,+basePath: String,+homePath: String,policy: SortPolicy,recursiveFiles: Bool) -> ResultOf(CombinedAutocompleteProvider):
  Bool.pick(ResultOf(CombinedAutocompleteProvider),starts(basePath,"/") && starts(homePath,"/"),Done{CombinedAutocompleteProvider{commands,basePath,homePath,policy,recursiveFiles}},Fail{InvalidBasePath{}})

# Recursive attachment completion shares runtime ignore traversal with Find and
# Grep. Each pass retains at most 100 literal matches; direct children get an
# independent shallow pass so deep matches cannot crowd them out.
type SearchScope is Data: SearchScope{root: String,query: String,displayBase: String}
type Candidate is Data:
  Candidate{path: String,name: String,directory: Bool,score: Nat,depth: Nat,length: Nat,order: String}
def lastSlash(text: String,+index: Nat,+found: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: found
    case SCon{char,rest}: lastSlash(rest,index + 1n,Bool.pick(Maybe<&2,Nat>,Char.is_eq(char,'/'),Some{index},found))
def scopedParts(text: String,index: Maybe<&2,Nat>) -> Maybe<&2,LineParts>:
  match index:
    case None{}: None{}
    case Some{index}: splitAt(text,index + 1n,"")
def scopeResult(+fallback: SearchScope,root: String,query: String,display: String,value: Result<&2,&2,FS.Error,FS.FileKind>) -> SearchScope:
  match value:
    case Done{FS.Directory{}}: SearchScope{root,query,display}
    case _: fallback
def resolveScope(+provider: CombinedAutocompleteProvider,+query: String,parts: Maybe<&2,LineParts>) -> IO(SearchScope):
  match provider parts:
    case CombinedAutocompleteProvider{_,base,_,_,_} None{}: IO.pure(SearchScope,SearchScope{base,query,""})
    case CombinedAutocompleteProvider{_,+base,home,_,_} Some{LineParts{+display,tail}}:
      +root = searchPath(base,display,expandHome(home,display))
      do IO<SearchScope>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(root)
        return scopeResult(SearchScope{base,query,""},root,tail,display,kind)
def foldedText(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}: foldedText(rest,SCon{Chr{minimumCode(Fold.variants(char),Char.to_u32(char))},reversed})
def orderKey(policy: SortPolicy,text: String) -> String:
  match policy:
    case ScalarOrder{}: text
    case FoldedScalarOrder{}: foldedText(text,"")
def pathDepth(text: String,inside: Bool,count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{'/',rest}: pathDepth(rest,False{},count)
    case SCon{_,rest}: pathDepth(rest,True{},count + Bool.pick(Nat,inside,0n,1n))
def matchScore(+query: String,+pattern: Regex.Regex,+path: String,+name: String,directory: Bool) -> Nat:
  +score = Bool.pick(Unit -> Nat,lessEqual(foldedCompare(name,query)) && lessEqual(foldedCompare(query,name)),_ => 100n,
    _ => Bool.pick(Unit -> Nat,foldedStarts(name,query),_ => 80n,
      _ => Bool.pick(Unit -> Nat,Regex.isMatch(pattern,name),_ => 50n,_ => Bool.pick(Nat,Regex.isMatch(pattern,path),30n,0n))(Unit{}))(Unit{}))(Unit{})
  Bool.pick(Nat,String.is_empty(query),1n,score + Bool.pick(Nat,directory && Nat.is_gt(score,0n),10n,0n))
def candidateBefore(a: Candidate,b: Candidate) -> Bool:
  match a b:
    case Candidate{_,_,_,+ascore,+adepth,+alen,akey} Candidate{_,_,_,+bscore,+bdepth,+blen,bkey}:
      Bool.pick(Unit -> Bool,Nat.is_eq(ascore,bscore),
        _ => Bool.pick(Unit -> Bool,Nat.is_eq(adepth,bdepth),
          _ => Bool.pick(Unit -> Bool,Nat.is_eq(alen,blen),_ => lessEqual(scalarCompare(akey,bkey)),_ => Nat.is_lt(alen,blen))(Unit{}),
          _ => Nat.is_lt(adepth,bdepth))(Unit{}),
        _ => Nat.is_gt(ascore,bscore))(Unit{})
def supportedKind(kind: FS.FileKind) -> Bool:
  match kind:
    case FS.Directory{}: True{}
    case FS.RegularFile{}: True{}
    case _: False{}
def scoredEntry(scope: SearchScope,+query: String,+pattern: Regex.Regex,policy: SortPolicy,entry: Search.Entry) -> Maybe<&2,Candidate>:
  match scope entry:
    case SearchScope{root,_,_} Search.Entry{absolute,+name,+kind}:
      +directory = Search.isDirectory(kind)
      +relativePath = Search.relative(root,absolute)
      +path = relativePath ++ Bool.pick(String,directory,"/","")
      +matched = supportedKind(kind) && Regex.isMatch(pattern,Bool.pick(String,contains(query,'/'),relativePath,name))
      Bool.pick(Maybe<&2,Candidate>,matched,Some{Candidate{path,name,directory,matchScore(query,pattern,path,name,directory),pathDepth(path,False{},0n),String.length(path),orderKey(policy,path)}},None{})
def addCandidate(value: Maybe<&2,Candidate>,+entries: List<&2,Candidate>) -> List<&2,Candidate>:
  match value:
    case None{}: entries
    case Some{entry}: entry <> entries
type Scan is Data:
  Scan{scope: SearchScope,pattern: Regex.Regex,policy: SortPolicy,count: Nat,reversed: List<&2,Candidate>}
def scopeQuery(scope: SearchScope) -> String:
  match scope:
    case SearchScope{_,query,_}: query
def collected(resume: Search.Cursor -> Scan -> IO(Search.ResultOf(List<&2,Candidate>)),state: Scan,step: Search.Step) -> IO(Search.ResultOf(List<&2,Candidate>)):
  match state step:
    case Scan{_,_,_,_,reversed} Search.End{}: IO.pure(Search.ResultOf(List<&2,Candidate>),Done{List.reverse(&2,Candidate,reversed)})
    case Scan{+scope,+pattern,+policy,count,reversed} Search.Yield{entry,cursor}:
      +candidate = scoredEntry(scope,scopeQuery(scope),pattern,policy,entry)
      resume(cursor,Scan{scope,pattern,policy,count + Bool.pick(Nat,Maybe.is_none(&2,Candidate,candidate),0n,1n),addCandidate(candidate,reversed)})
@unsafe def collect(cursor: Search.Cursor,+state: Scan) -> IO(Search.ResultOf(List<&2,Candidate>)):
  match state:
    case Scan{_,_,_,count,reversed}:
      Bool.pick(Unit -> IO(Search.ResultOf(List<&2,Candidate>)),Nat.is_ge(count,100n),
        _ => IO.pure(Search.ResultOf(List<&2,Candidate>),Done{List.reverse(&2,Candidate,reversed)}),
        _ => Search.then(Search.Step,List<&2,Candidate>,Search.next(cursor),step => collected(cursor => state => collect(cursor,state),state,step)))(Unit{})
def candidateSeen(entries: List<&2,Candidate>,+path: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Candidate{first,_,_,_,_,_,_} <> +rest: Bool.pick(Unit -> Bool,Strings.equal(first,path),_ => True{},_ => candidateSeen(rest,path))(Unit{})
def candidatePath(entry: Candidate) -> String:
  match entry:
    case Candidate{path,_,_,_,_,_,_}: path
def mergeCandidates(entries: List<&2,Candidate>,+reversed: List<&2,Candidate>) -> List<&2,Candidate>:
  match entries:
    case Nil{}: List.reverse(&2,Candidate,reversed)
    case +entry <> rest: mergeCandidates(rest,Bool.pick(List<&2,Candidate>,candidateSeen(reversed,candidatePath(entry)),reversed,entry <> reversed))
def attachmentItem(display: String,quoted: Bool,entry: Candidate) -> AutocompleteItem:
  match entry:
    case Candidate{+path,+name,+directory,_,_,_,_}:
      +text = display ++ Bool.pick(String,directory,String.reverse(String.drop(String.reverse(path),1n)),path)
      AutocompleteItem{buildCompletionValue(text ++ Bool.pick(String,directory,"/",""),True{},quoted),name ++ Bool.pick(String,directory,"/",""),Some{text}}
def attachmentItems(entries: List<&2,Candidate>,+display: String,+quoted: Bool,limit: Nat,reversed: List<&2,AutocompleteItem>) -> List<&2,AutocompleteItem>:
  match entries limit:
    case _ Zero{}: List.reverse(&2,AutocompleteItem,reversed)
    case Nil{} _: List.reverse(&2,AutocompleteItem,reversed)
    case entry <> rest Succ{left}: attachmentItems(rest,display,quoted,left,attachmentItem(display,quoted,entry) <> reversed)
def combinedAttachments(scope: SearchScope,quoted: Bool,shallow: List<&2,Candidate>,recursive: List<&2,Candidate>) -> List<&2,AutocompleteItem>:
  match scope:
    case SearchScope{_,_,display}: attachmentItems(Sort.sort(~Candidate,~candidateBefore,mergeCandidates(recursive,List.reverse(&2,Candidate,shallow))),display,quoted,20n,Nil{})
def collectPasses(+cursor: Search.Cursor,+scope: SearchScope,pattern: Regex.Regex,policy: SortPolicy,quoted: Bool,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Search.ResultOf(List<&2,AutocompleteItem>)):
  +scan = {Scan{scope,pattern,policy,0n,Nil{}}: Scan}
  Search.then(List<&2,Candidate>,List<&2,AutocompleteItem>,collect(Search.withPolicy(cursor,Search.WalkPolicy{True{},Some{1n},True{}}),scan),shallow =>
    Search.then(List<&2,Candidate>,List<&2,AutocompleteItem>,collect(Search.withPolicy(cursor,Search.WalkPolicy{True{},None{},True{}}),scan),recursive =>
      Search.then(Unit,List<&2,AutocompleteItem>,Search.check(signal),_ => IO.pure(Search.ResultOf(List<&2,AutocompleteItem>),Done{combinedAttachments(scope,quoted,shallow,recursive)}))))
def searchResult(value: Search.ResultOf(List<&2,AutocompleteItem>)) -> ResultOf(List<&2,AutocompleteItem>):
  match value:
    case Done{items}: Done{items}
    case Fail{Search.Aborted{}}: Done{Nil{}}
    case Fail{Search.Filesystem{FS.System{_,_}}}: Done{Nil{}}
    case Fail{cause}: Fail{SearchFailure{cause}}
def preparedSearch(+provider: CombinedAutocompleteProvider,+scope: SearchScope,quoted: Bool,+signal: Maybe<&2,Abort.AbortSignal<Unit>>,compiled: Result<&2,&2,Regex.Error,Regex.Regex>) -> IO(ResultOf(List<&2,AutocompleteItem>)):
  match provider scope compiled:
    case _ _ Fail{cause}: IO.pure(ResultOf(List<&2,AutocompleteItem>),Fail{InvalidQuery{cause}})
    case CombinedAutocompleteProvider{_,_,+home,policy,_} SearchScope{root,_,_} Done{pattern}:
      do IO<ResultOf(List<&2,AutocompleteItem>)>:
        xdg : Result<&1,&1,U32 & String,String> <- IO.get_env("XDG_CONFIG_HOME")
        value : Search.ResultOf(List<&2,AutocompleteItem>) <- Search.then(Unit,List<&2,AutocompleteItem>,Search.check(signal),_ =>
          Search.then(Search.Cursor,List<&2,AutocompleteItem>,Search.create(root,home,Search.nonempty(Search.optionalEnvironment(xdg),Path.join(home,".config")),True{},Search.Completion{},signal),cursor => collectPasses(cursor,scope,pattern,policy,quoted,signal)))
        return searchResult(value)
def isAborted(signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool,False{})
    case Some{signal}: Abort.aborted(Unit,signal)
def fuzzySuggestions(+provider: CombinedAutocompleteProvider,prefix: PathPrefix,+signal: Maybe<&2,Abort.AbortSignal<Unit>>) -> IO(ResultOf(List<&2,AutocompleteItem>)):
  match provider prefix:
    case CombinedAutocompleteProvider{_,_,_,_,False{}} _: IO.pure(ResultOf(List<&2,AutocompleteItem>),Done{Nil{}})
    case _ PathPrefix{+query,_,quoted}:
      do IO<ResultOf(List<&2,AutocompleteItem>)>:
        cancelled : Bool <- isAborted(signal)
        Bool.pick(Unit -> IO(ResultOf(List<&2,AutocompleteItem>)),cancelled,
          _ => IO.pure(ResultOf(List<&2,AutocompleteItem>),Done{Nil{}}),
          _ => do IO<ResultOf(List<&2,AutocompleteItem>)>:
            +scope : SearchScope <- resolveScope(provider,query,scopedParts(query,lastSlash(query,0n,None{})))
            preparedSearch(provider,scope,quoted,signal,Regex.compileLiteral(scopeQuery(scope),True{})))(Unit{})
def suggestionsBefore(+provider: CombinedAutocompleteProvider,+before: String,options: Options,prefix: Maybe<&2,String>) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  match provider options prefix:
    case _ Options{signal,_} Some{+prefix}:
      do IO<ResultOf(Maybe<&2,AutocompleteSuggestions>)>:
        value : ResultOf(List<&2,AutocompleteItem>) <- fuzzySuggestions(provider,parsePathPrefix(prefix),signal)
        return Result.map(&2,&2,Error,List<&2,AutocompleteItem>,Maybe<&2,AutocompleteSuggestions>,items => suggestions(prefix,items),value)
    case CombinedAutocompleteProvider{commands,_,_,_,_} Options{_,+force} None{}:
      Bool.pick(Unit -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)),Bool.not(force) && starts(before,"/"),
        _ => slashSuggestions(commands,before,commandArguments(before,"")),
        _ => pathSuggestions(provider,extractPathPrefix(before,force)))(Unit{})
def suggestionsView(provider: CombinedAutocompleteProvider,options: Options,parts: ResultOf(LineParts)) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  match parts:
    case Fail{error}: IO.pure(ResultOf(Maybe<&2,AutocompleteSuggestions>),Fail{error})
    case Done{LineParts{+before,_}}: suggestionsBefore(provider,before,options,extractAtPrefix(before))
def getSuggestions(provider: CombinedAutocompleteProvider,lines: List<&2,String>,cursorLine: Nat,cursorCol: Nat,options: Options) -> IO(ResultOf(Maybe<&2,AutocompleteSuggestions>)):
  suggestionsView(provider,options,view(lines,cursorLine,cursorCol))
