import Base
import ./skills.bend as Skills
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Text

import ./diagnostics.bend as Diagnostics
import ../utils/frontmatter.bend as Frontmatter
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/record.bend as Record
import ../../../runtime/src/stable-sort.bend as Sort
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/yaml.bend as Yaml

type PromptTemplate is Data:
  PromptTemplate{name: String, description: String, argumentHint: Maybe<&2,String>, content: String, sourceInfo: Skills.SourceInfo, filePath: String}

def pushArgument(current: String, reversed: List<&2,String>) -> List<&2,String>:
  match current:
    case SNil{}: reversed
    case value: String.reverse(value) <> reversed

# An unclosed quote runs to the end of the input, as upstream.
def parseArguments(text: String, quote: Maybe<&2,Char>, +current: String, +reversed: List<&2,String>) -> List<&2,String>:
  match text quote:
    case SNil{} _: List.reverse(&2,String,pushArgument(current,reversed))
    case SCon{char,rest} Some{value}:
      +char = {char : Char}
      +value = {value : Char}
      parseArguments(rest,Bool.pick(Maybe<&2,Char>,Char.is_eq(char,value),None{},Some{value}),Bool.pick(String,Char.is_eq(char,value),current,SCon{char,current}),reversed)
    case SCon{'"',rest} None{}: parseArguments(rest,Some{'"'},current,reversed)
    case SCon{'\'',rest} None{}: parseArguments(rest,Some{'\''},current,reversed)
    case SCon{Chr{+code},rest} None{}:
      +space = Text.whitespace(code)
      parseArguments(rest,None{},Bool.pick(String,space,"",SCon{Chr{code},current}),Bool.pick(List<&2,String>,space,pushArgument(current,reversed),reversed))

def parseCommandArgs(text: String) -> List<&2,String>:
  parseArguments(text,None{},"",Nil{})

def joinArguments(args: List<&2,String>, +reversed: String, separator: Bool) -> String:
  match args:
    case Nil{}: String.reverse(reversed)
    case value <> rest: joinArguments(rest,String.reverse.go(value,Bool.pick(String,separator,SCon{' ',reversed},reversed)),True{})

type Bindings is Data:
  Bindings{args: List<&2,String>, all: String, limit: Nat}
type Target is Data:
  All{}
  Position{index: Nat}

# Clamp decimal indices to one beyond the argument count. Every larger index
# has the same result, without machine-integer overflow or huge unary values.
def decimal(text: String, +limit: Nat, +value: Nat) -> Nat & String:
  match text:
    case SNil{}: (value,"")
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> Nat & String,U32.is_ge(code,48) && U32.is_le(code,57),
        _ => decimal(rest,limit,Nat.min(limit,Nat.add(Nat.mul(value,10n),U32.to_nat(U32.sub(code,48))))),
        _ => (value,SCon{Chr{code},rest}))(Unit{})

def numbered(value: Nat & String) -> Maybe<&1,Target & String>:
  match value:
    case Tuple{index,rest}: Some{(Position{index},rest)}

def target(text: String, limit: Nat) -> Maybe<&1,Target & String>:
  match text:
    case SNil{}: None{}
    case SCon{'@',rest}: Some{(All{},rest)}
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> Maybe<&1,Target & String>,U32.is_ge(code,48) && U32.is_le(code,57),
        _ => numbered(decimal(SCon{Chr{code},rest},limit,0n)),
        _ => Bool.pick(Unit -> Maybe<&1,Target & String>,String.starts_with(SCon{Chr{code},rest},"ARGUMENTS"),
          _ => Some{(All{},String.drop(SCon{Chr{code},rest},9n))},_ => None{})(Unit{}))(Unit{})

def positional(args: List<&2,String>, index: Nat) -> String:
  match args index:
    case _ 0n: ""
    case Nil{} _: ""
    case first <> _ 1n: first
    case _ <> rest 2n+remaining: positional(rest,1n + remaining)

def valueOf(bindings: Bindings, key: Target) -> String:
  match bindings key:
    case Bindings{_,all,_} All{}: all
    case Bindings{args,_,_} Position{index}: positional(args,index)

type Replacement is Data:
  Unrecognized{}
  MissingClose{}
  Replaced{value: String, rest: String}

def defaultBody(text: String, reversed: String) -> Replacement:
  match text:
    case SNil{}: MissingClose{}
    case SCon{'}',rest}: Replaced{String.reverse(reversed),rest}
    case SCon{char,rest}: defaultBody(rest,SCon{char,reversed})

def withDefault(value: String, parsed: Replacement) -> Replacement:
  match value parsed:
    case _ MissingClose{}: MissingClose{}
    case _ Unrecognized{}: Unrecognized{}
    case SNil{} Replaced{fallback,rest}: Replaced{fallback,rest}
    case text Replaced{_,rest}: Replaced{text,rest}

def sliceLength(args: List<&2,String>, parsed: Nat & String) -> Replacement:
  match parsed:
    case Tuple{length,SCon{'}',rest}}: Replaced{joinArguments(List.take(&2,String,args,length),"",False{}),rest}
    case _: Unrecognized{}

def sliceEnd(args: List<&2,String>, limit: Nat, rest: String) -> Replacement:
  match rest:
    case SCon{'}',tail}: Replaced{joinArguments(args,"",False{}),tail}
    case SCon{':',SCon{Chr{+code},+tail}}:
      Bool.pick(Unit -> Replacement,U32.is_ge(code,48) && U32.is_le(code,57),_ => sliceLength(args,decimal(SCon{Chr{code},tail},limit,0n)),_ => Unrecognized{})(Unit{})
    case _: Unrecognized{}

def sliceStart(args: List<&2,String>, limit: Nat, parsed: Nat & String) -> Replacement:
  match parsed:
    case Tuple{index,rest}: sliceEnd(List.drop(&2,String,args,Nat.sub(index,1n)),limit,rest)

def braced(defaults: Bool, bindings: Bindings, parsed: Maybe<&1,Target & String>) -> Replacement:
  match defaults bindings parsed:
    case _ _ None{}: Unrecognized{}
    case True{} context Some{Tuple{key,SCon{':',SCon{'-',rest}}}}: withDefault(valueOf(context,key),defaultBody(rest,""))
    case _ Bindings{args,_,+limit} Some{Tuple{All{},SCon{':',SCon{Chr{+code},+rest}}}}:
      Bool.pick(Unit -> Replacement,U32.is_ge(code,48) && U32.is_le(code,57),_ => sliceStart(args,limit,decimal(SCon{Chr{code},rest},limit,0n)),_ => Unrecognized{})(Unit{})
    case _ _ _: Unrecognized{}

def simple(bindings: Bindings, parsed: Maybe<&1,Target & String>) -> Replacement:
  match parsed:
    case None{}: Unrecognized{}
    case Some{Tuple{key,rest}}: Replaced{valueOf(bindings,key),rest}

def placeholder(defaults: Bool, +bindings: Bindings, text: String) -> Replacement:
  match bindings text:
    case Bindings{_,_,limit} SCon{'{',rest}: braced(defaults,bindings,target(rest,limit))
    case Bindings{_,_,limit} other: simple(bindings,target(other,limit))

# Replacement text never enters the input scanner. A failed default scan proves
# there is no closing brace in the remaining input; remember that fact so a
# string of unfinished defaults is processed linearly instead of rescanned.
type Substitution is Data:
  Substitution{remaining: String, reversed: String, defaults: Bool}

def substitutionStep(parsed: Replacement, rest: String, reversed: String, defaults: Bool) -> Substitution:
  match parsed:
    case Unrecognized{}: Substitution{rest,SCon{'$',reversed},defaults}
    case MissingClose{}: Substitution{rest,SCon{'$',reversed},False{}}
    case Replaced{replacement,tail}: Substitution{tail,String.reverse.go(replacement,reversed),defaults}

def substituteFrom(fuel: String, +bindings: Bindings, state: Substitution) -> String:
  match fuel state:
    case _ Substitution{SNil{},reversed,_}: String.reverse(reversed)
    case SNil{} Substitution{text,reversed,_}: String.reverse.go(reversed,text)
    case SCon{_,more} Substitution{SCon{'$',+rest},reversed,+defaults}: substituteFrom(more,bindings,substitutionStep(placeholder(defaults,bindings,rest),rest,reversed,defaults))
    case SCon{_,more} Substitution{SCon{char,rest},reversed,defaults}: substituteFrom(more,bindings,Substitution{rest,SCon{char,reversed},defaults})

def argumentCount(args: List<&2,String>, count: Nat) -> Nat:
  match args:
    case Nil{}: count
    case _ <> rest: argumentCount(rest,1n + count)

def substituteArgs(+content: String, +args: List<&2,String>) -> String:
  substituteFrom(content,Bindings{args,joinArguments(args,"",False{}),argumentCount(args,1n)},Substitution{content,"",True{}})

def commandName(text: String, +reversed: String) -> String & String:
  match text:
    case SNil{}: (String.reverse(reversed),"")
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> String & String,Text.whitespace(code),_ => (String.reverse(reversed),rest),_ => commandName(rest,SCon{Chr{code},reversed}))(Unit{})

def expandNamed(+name: String, +args: String, +original: String, templates: List<&2,PromptTemplate>) -> String:
  match templates:
    case Nil{}: original
    case PromptTemplate{key,_,_,content,_,_} <> rest:
      Bool.pick(Unit -> String,Strings.equal(name,key),
        _ => substituteArgs(content,parseCommandArgs(args)),
        _ => expandNamed(name,args,original,rest))(Unit{})

def expandCommand(original: String, templates: List<&2,PromptTemplate>, parsed: String & String) -> String:
  match parsed:
    case Tuple{SNil{},_}: original
    case Tuple{name,args}: expandNamed(name,args,original,templates)

def expandPromptTemplate(+text: String, templates: List<&2,PromptTemplate>) -> String:
  match text:
    case SCon{'/',rest}: expandCommand(text,templates,commandName(rest,""))
    case _: text

type LoadPromptTemplatesOptions is Data:
  LoadPromptTemplatesOptions{cwd: String, agentDir: String, promptPaths: List<&2,String>, includeDefaults: Bool}
type LoadResult is Data:
  LoadResult{templates: List<&2,PromptTemplate>, diagnostics: List<&2,Diagnostics.ResourceDiagnostic>}
type Roots is Data:
  Roots{global: String, project: String}

# During loading both lists are reversed; reverse only once at the boundary.
# Unreadable templates and paths are reported as warnings carrying Node's
# error message, as upstream's loader does.
def loadProblem(state: LoadResult, path: String, message: String) -> LoadResult:
  match state:
    case LoadResult{templates,diagnostics}: LoadResult{templates,Diagnostics.warning(message,path) <> diagnostics}

def fileProblem(state: LoadResult, +path: String, syscall: String, cause: FS.Error) -> LoadResult:
  match cause:
    case FS.System{code,_}: loadProblem(state,path,FS.nodeMessage(code,syscall,path))
    case FS.InvalidPathEncoding{_}: loadProblem(state,path,"Invalid UTF-8 path")
    case FS.ReadAndClose{code,_,_,_}: loadProblem(state,path,FS.nodeMessage(code,"read",path))
    case FS.WriteAndClose{code,_,_,_}: loadProblem(state,path,FS.nodeMessage(code,"write",path))

# Input paths are already absolute and normalized. This split does not resolve
# symlinks: resource names and scopes describe the selected lexical path.
def location(reversedPath: String, name: String) -> String & String:
  match reversedPath:
    case SNil{}: (name,"/")
    case SCon{'/',SNil{}}: (name,"/")
    case SCon{'/',rest}: (name,String.reverse(rest))
    case SCon{char,rest}: location(rest,SCon{char,name})

def stem(reversed: String) -> String:
  match reversed:
    case SCon{'d',SCon{'m',SCon{'.',rest}}}: String.reverse(rest)
    case other: String.reverse(other)

def under(+path: String, +root: String) -> Bool:
  Strings.equal(path,root) || String.starts_with(path,root ++ "/")

def sourceInfo(roots: Roots, +path: String, parent: String) -> Skills.SourceInfo:
  match roots:
    case Roots{+global,+project}:
      Bool.pick(Unit -> Skills.SourceInfo,under(path,global),
        _ => Skills.SourceInfo{path,"local",Skills.User{},Skills.TopLevel{},Some{global}},
        _ => Bool.pick(Skills.SourceInfo,under(path,project),Skills.SourceInfo{path,"local",Skills.Project{},Skills.TopLevel{},Some{project}},Skills.SourceInfo{path,"local",Skills.Temporary{},Skills.TopLevel{},Some{parent}}))(Unit{})

# A field counts only as a nonempty string; anything else is ignored.
def fieldText(value: Maybe<&2,Yaml.Value>) -> Maybe<&2,String>:
  match value:
    case Some{Yaml.Text{SCon{first,rest}}}: Some{SCon{first,rest}}
    case _: None{}

def descriptionCut(cut: Text.Cut) -> String:
  match cut:
    case Text.Cut{prefix,0n}: prefix
    case Text.Cut{prefix,_}: prefix ++ "..."

def firstDescription(lines: List<&2,String>) -> String:
  match lines:
    case Nil{}: ""
    case +line <> rest:
      Bool.pick(Unit -> String,String.is_empty(Text.trim(line)),_ => firstDescription(rest),_ => descriptionCut(Text.take(line,60n)))(Unit{})

def templateDescription(description: Maybe<&2,String>, body: String) -> String:
  match description:
    case Some{value}: value
    case None{}: firstDescription(Strings.split(body,'\n'))

def templateFields(+path: String, roots: Roots, state: LoadResult, +body: String, description: Maybe<&2,String>, hint: Maybe<&2,String>, place: String & String) -> LoadResult:
  match state place:
    case LoadResult{templates,diagnostics} Tuple{name,parent}:
      LoadResult{PromptTemplate{stem(String.reverse(name)),templateDescription(description,body),hint,body,sourceInfo(roots,path,parent),path} <> templates,diagnostics}

def parsedTemplate(+path: String, roots: Roots, state: LoadResult, parsed: Result<&2,&2,Yaml.Error,Frontmatter.Frontmatter>) -> LoadResult:
  match parsed:
    case Fail{cause}: loadProblem(state,path,Yaml.errorMessage(cause))
    case Done{Frontmatter.Frontmatter{+frontmatter,body}}:
      templateFields(path,roots,state,body,fieldText(Record.get(Yaml.Value,frontmatter,"description")),fieldText(Record.get(Yaml.Value,frontmatter,"argument-hint")),location(String.reverse(path),""))

# readFileSync(path, "utf-8") decodes with replacement.
def readTemplate(path: String, roots: Roots, state: LoadResult, result: Result<&2,&2,FS.Error,List<&2,U32>>) -> LoadResult:
  match result:
    case Fail{cause}: fileProblem(state,path,"open",cause)
    case Done{bytes}: parsedTemplate(path,roots,state,Frontmatter.parseFrontmatter(Utf8.decodeBuffer(bytes)))

def loadTemplateFromFile(+path: String, roots: Roots, state: LoadResult) -> IO(LoadResult):
  do IO<LoadResult>:
    result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return readTemplate(path,roots,state,result)

def entryOrder(left: FS.DirectoryEntry, right: FS.DirectoryEntry) -> Bool:
  match left right:
    case FS.DirectoryEntry{a,_} FS.DirectoryEntry{b,_}: String.is_le(a,b)

def loadLink(path: String, roots: Roots, state: LoadResult, kind: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(LoadResult):
  match kind:
    case Fail{_}: IO.pure(LoadResult,state)
    case Done{FS.RegularFile{}}: loadTemplateFromFile(path,roots,state)
    case _: IO.pure(LoadResult,state)

def loadEntry(+path: String, roots: Roots, state: LoadResult, kind: FS.FileKind) -> IO(LoadResult):
  match kind:
    case FS.RegularFile{}: loadTemplateFromFile(path,roots,state)
    case FS.SymbolicLink{}:
      do IO<LoadResult>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        loadLink(path,roots,state,kind)
    case _: IO.pure(LoadResult,state)

def loadEntries(entries: List<&2,FS.DirectoryEntry>, +directory: String, +roots: Roots, +state: LoadResult) -> IO(LoadResult):
  match entries:
    case Nil{}: IO.pure(LoadResult,state)
    case FS.DirectoryEntry{+name,kind} <> rest:
      do IO<LoadResult>:
        next : LoadResult <- Bool.pick(Unit -> IO(LoadResult),String.ends_with(name,".md"),_ => loadEntry(Path.join(directory,name),roots,state,kind),_ => IO.pure(LoadResult,state))(Unit{})
        loadEntries(rest,directory,roots,next)

def loadedDirectory(path: String, roots: Roots, state: LoadResult, entries: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> IO(LoadResult):
  match entries:
    case Fail{_}: IO.pure(LoadResult,state)
    case Done{values}: loadEntries(Sort.sort(~FS.DirectoryEntry,~entryOrder,values),path,roots,state)

def loadTemplatesFromDir(+directory: String, roots: Roots, state: LoadResult) -> IO(LoadResult):
  do IO<LoadResult>:
    entries : Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>> <- FS.readDirectory(directory)
    loadedDirectory(directory,roots,state,entries)

def loadPathKind(+path: String, roots: Roots, +state: LoadResult, kind: Result<&2,&2,FS.Error,FS.FileKind>) -> IO(LoadResult):
  match kind:
    case Fail{FS.System{2,_}}: IO.pure(LoadResult,state)
    case Fail{cause}: IO.pure(LoadResult,fileProblem(state,path,"stat",cause))
    case Done{FS.Directory{}}: loadTemplatesFromDir(path,roots,state)
    case Done{FS.RegularFile{}}: Bool.pick(Unit -> IO(LoadResult),String.ends_with(path,".md"),_ => loadTemplateFromFile(path,roots,state),_ => IO.pure(LoadResult,state))(Unit{})
    case _: IO.pure(LoadResult,state)

def loadResolvedPath(raw: String, roots: Roots, state: LoadResult, resolved: Result<&2,&2,Paths.Error,String>) -> IO(LoadResult):
  match resolved:
    case Fail{_}: IO.pure(LoadResult,loadProblem(state,raw,"Invalid prompt template path"))
    case Done{+path}:
      do IO<LoadResult>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        loadPathKind(path,roots,state,kind)

def loadExplicit(paths: List<&2,String>, +environment: Paths.Environment, +cwd: String, +roots: Roots, state: LoadResult) -> IO(LoadResult):
  match paths:
    case Nil{}: IO.pure(LoadResult,state)
    case +raw <> rest:
      do IO<LoadResult>:
        next : LoadResult <- loadResolvedPath(raw,roots,state,Paths.resolvePath(environment,raw,cwd,Paths.PathInputOptions{True{},True{},None{},False{},False{}}))
        loadExplicit(rest,environment,cwd,roots,next)

def finishLoad(state: LoadResult) -> LoadResult:
  match state:
    case LoadResult{templates,diagnostics}: LoadResult{List.reverse(&2,PromptTemplate,templates),List.reverse(&2,Diagnostics.ResourceDiagnostic,diagnostics)}

def loadDefaults(enabled: Bool, +roots: Roots) -> IO(LoadResult):
  match enabled roots:
    case False{} _: IO.pure(LoadResult,LoadResult{Nil{},Nil{}})
    case True{} Roots{global,project}:
      do IO<LoadResult>:
        globalState : LoadResult <- loadTemplatesFromDir(global,roots,LoadResult{Nil{},Nil{}})
        loadTemplatesFromDir(project,roots,globalState)

def loadAt(environment: Paths.Environment, +cwd: String, paths: List<&2,String>, defaults: Bool, +roots: Roots) -> IO(LoadResult):
  do IO<LoadResult>:
    state : LoadResult <- loadDefaults(defaults,roots)
    result : LoadResult <- loadExplicit(paths,environment,cwd,roots,state)
    return finishLoad(result)

def loadRoots(environment: Paths.Environment, configDirName: String, paths: List<&2,String>, defaults: Bool, cwd: Result<&2,&2,Paths.Error,String>, agentDir: Result<&2,&2,Paths.Error,String>) -> IO(Result<&2,&2,Paths.Error,LoadResult>):
  match cwd agentDir:
    case Fail{cause} _: IO.pure(Result<&2,&2,Paths.Error,LoadResult>,Fail{cause})
    case _ Fail{cause}: IO.pure(Result<&2,&2,Paths.Error,LoadResult>,Fail{cause})
    case Done{+directory} Done{agent}:
      do IO<Result<&2,&2,Paths.Error,LoadResult>>:
        result : LoadResult <- loadAt(environment,directory,paths,defaults,Roots{Path.join(agent,"prompts"),Path.join(Path.join(directory,configDirName),"prompts")})
        return Done{result}

# The host supplies package configuration and path-resolution context. Invalid
# files are reported individually; successfully loaded templates retain order
# and duplicates, as upstream does (expansion picks the first matching name).
def loadPromptTemplates(+environment: Paths.Environment, configDirName: String, options: LoadPromptTemplatesOptions) -> IO(Result<&2,&2,Paths.Error,LoadResult>):
  match options:
    case LoadPromptTemplatesOptions{cwd,agentDir,paths,defaults}:
      loadRoots(environment,configDirName,paths,defaults,Paths.resolvePath(environment,cwd,"",Paths.defaults()),Paths.resolvePath(environment,agentDir,"",Paths.defaults()))
