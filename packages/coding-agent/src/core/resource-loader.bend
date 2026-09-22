import Base
import ./diagnostics.bend as D
import ./footer-data-provider.bend as Git
import ./system-prompt.bend as Prompt
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/utf8.bend as Utf8

# Project context loading is the implemented portion of ResourceLoader.
# Extension, theme, package and reload orchestration are not stubbed here.
type Options is Data:
  Options{cwd: String,agentDir: String}
type ContextFiles is Data:
  ContextFiles{files: List<&2,Prompt.ContextFile>,diagnostics: List<&2,D.ResourceDiagnostic>}
type Candidate is Data:
  Candidate{file: Maybe<&2,Prompt.ContextFile>,diagnostics: List<&2,D.ResourceDiagnostic>}
def stripBom(content: String) -> String:
  match content:
    case SCon{Chr{65279},rest}: rest
    case other: other
def systemMessage(error: FS.Error) -> String:
  match error:
    case FS.System{_,message}: message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.WriteAndClose{_,write,_,close}: write ++ "; close: " ++ close
    case FS.ReadAndClose{_,read,_,close}: read ++ "; close: " ++ close
def decoded(value: Result<&2,&2,Utf8.Error,String>,path: String) -> Candidate:
  match value:
    case Fail{_}: Candidate{None{},D.warning("Invalid UTF-8 in context file",path) <> Nil{}}
    case Done{content}: Candidate{Some{Prompt.ContextFile{path,stripBom(content)}},Nil{}}
def readCandidate(value: Result<&2,&2,FS.Error,List<&2,U32>>,path: String) -> Candidate:
  match value:
    case Fail{cause}: Candidate{None{},D.warning(systemMessage(cause),path) <> Nil{}}
    case Done{bytes}: decoded(Utf8.decodeWith(Utf8.Preserve{},bytes),path)
def candidateKind(kind: Result<&2,&2,FS.Error,FS.FileKind>,+path: String) -> IO(Candidate):
  match kind:
    case Done{FS.RegularFile{}}:
      do IO<Candidate>:
        value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
        return readCandidate(value,path)
    case Fail{FS.System{2,_}}: IO.pure(Candidate,Candidate{None{},Nil{}})
    case Fail{cause}: IO.pure(Candidate,Candidate{None{},D.warning(systemMessage(cause),path) <> Nil{}})
    case _: IO.pure(Candidate,Candidate{None{},Nil{}})
def selected(candidate: Candidate) -> Bool:
  match candidate:
    case Candidate{Some{_},_}: True{}
    case _: False{}
def combined(candidate: Candidate,earlier: List<&2,D.ResourceDiagnostic>) -> Candidate:
  match candidate:
    case Candidate{file,issues}: Candidate{file,List.append(&2,D.ResourceDiagnostic,earlier,issues)}
def candidateIssues(value: Candidate) -> List<&2,D.ResourceDiagnostic>:
  match value:
    case Candidate{_,issues}: issues
def candidates(names: List<&2,String>,+directory: String,issues: List<&2,D.ResourceDiagnostic>) -> IO(Candidate):
  match names:
    case Nil{}: IO.pure(Candidate,Candidate{None{},issues})
    case name <> rest:
      do IO<Candidate>:
        +path : String = Path.join(directory,name)
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(path)
        +value : Candidate <- candidateKind(kind,path)
        +all : Candidate = combined(value,issues)
        Bool.pick(Unit -> IO(Candidate),selected(value),_ => IO.pure(Candidate,all),_ => candidates(rest,directory,candidateIssues(all)))(Unit{})
def loadContextFileFromDir(directory: String) -> IO(Candidate):
  candidates("AGENTS.override.md" <> "AGENTS.md" <> "AGENTS.MD" <> "CLAUDE.md" <> "CLAUDE.MD" <> Nil{},directory,Nil{})
def canonicalResult(value: Result<&2,&2,FS.Error,String>,fallback: String) -> String:
  match value:
    case Done{path}: path
    case Fail{_}: fallback
def canonicalize(+path: String) -> IO(String):
  do IO<String>:
    value : Result<&2,&2,FS.Error,String> <- FS.realpath(path)
    return canonicalResult(value,path)
def lastPart(parts: List<&2,String>,last: String) -> String:
  match parts:
    case Nil{}: last
    case "" <> rest: lastPart(rest,last)
    case first <> rest: lastPart(rest,first)
type Shadow is Data:
  Shadow{path: Maybe<&2,String>,diagnostics: List<&2,D.ResourceDiagnostic>}
def shadowCandidate(value: Candidate,mainRoot: String) -> Shadow:
  match value:
    case Candidate{None{},issues}: Shadow{None{},issues}
    case Candidate{Some{Prompt.ContextFile{path,_}},issues}: Shadow{Some{Path.join(mainRoot,lastPart(Strings.split(path,'/'),""))},issues}
def shadowRoot(sameRepo: Bool,worktree: String,mainRoot: String) -> IO(Shadow):
  match sameRepo:
    case False{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case True{}:
      do IO<Shadow>:
        value : Candidate <- loadContextFileFromDir(worktree)
        return shadowCandidate(value,mainRoot)
def shadowNested(nested: Bool,+common: String,+worktree: String,+mainRoot: String) -> IO(Shadow):
  match nested:
    case False{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case True{}:
      do IO<Shadow>:
        mainGit : String <- canonicalize(Path.join(mainRoot,".git"))
        shadowRoot(Strings.equal(mainGit,common),worktree,mainRoot)
def shadowPaths(paths: Maybe<&2,Git.GitPaths>) -> IO(Shadow):
  match paths:
    case None{}: IO.pure(Shadow,Shadow{None{},Nil{}})
    case Some{Git.GitPaths{repo,common,_}}:
      do IO<Shadow>:
        +common : String <- canonicalize(common)
        +worktree : String <- canonicalize(repo)
        +mainRoot : String = Git.parent(common)
        shadowNested(String.starts_with(worktree,mainRoot ++ "/"),common,worktree,mainRoot)
def findShadowedContextFile(cwd: String) -> IO(Shadow):
  do IO<Shadow>:
    paths : Maybe<&2,Git.GitPaths> <- Git.findGitPaths(cwd)
    shadowPaths(paths)

# Deduplication uses the reported lexical path, as upstream does. Canonical
# paths are used only to identify a nested worktree's same-filename shadow.
type Accumulator is Data:
  Accumulator{files: List<&2,Prompt.ContextFile>,seen: Strings.StringSet,diagnostics: List<&2,D.ResourceDiagnostic>}
def filePath(value: Prompt.ContextFile) -> String:
  match value:
    case Prompt.ContextFile{path,_}: path
def include(file: Maybe<&2,Prompt.ContextFile>,issues: List<&2,D.ResourceDiagnostic>,shadowed: Bool,state: Accumulator) -> Accumulator:
  match file state:
    case None{} Accumulator{files,seen,earlier}: Accumulator{files,seen,List.append(&2,D.ResourceDiagnostic,earlier,issues)}
    case Some{+file} Accumulator{+files,+seen,earlier}:
      +path = filePath(file)
      +skip = shadowed || Strings.contains(seen,path)
      Accumulator{Bool.pick(List<&2,Prompt.ContextFile>,skip,files,file <> files),Bool.pick(Strings.StringSet,skip,seen,Strings.insert(seen,path)),List.append(&2,D.ResourceDiagnostic,earlier,issues)}
def isShadow(file: Maybe<&2,Prompt.ContextFile>,shadow: Maybe<&2,String>) -> IO(Bool):
  match file shadow:
    case Some{Prompt.ContextFile{path,_}} Some{target}:
      do IO<Bool>:
        real : String <- canonicalize(path)
        return Strings.equal(real,target)
    case _ _: IO.pure(Bool,False{})
def collected(value: Candidate,shadowed: Bool,state: Accumulator) -> Accumulator:
  match value:
    case Candidate{file,issues}: include(file,issues,shadowed,state)
def candidateFile(value: Candidate) -> Maybe<&2,Prompt.ContextFile>:
  match value:
    case Candidate{file,_}: file
@unsafe def ancestors(+directory: String,+shadow: Maybe<&2,String>,state: Accumulator) -> IO(Accumulator):
  do IO<Accumulator>:
    +value : Candidate <- loadContextFileFromDir(directory)
    skip : Bool <- isShadow(candidateFile(value),shadow)
    +next : String = Git.parent(directory)
    +nextState : Accumulator = collected(value,skip,state)
    Bool.pick(Unit -> IO(Accumulator),Strings.equal(directory,next),_ => IO.pure(Accumulator,nextState),_ => ancestors(next,shadow,nextState))(Unit{})
def finished(global: List<&2,Prompt.ContextFile>,state: Accumulator) -> ContextFiles:
  match state:
    case Accumulator{files,_,issues}: ContextFiles{List.append(&2,Prompt.ContextFile,global,files),issues}
def inherited(global: Accumulator,shadow: Shadow,cwd: String) -> IO(ContextFiles):
  match global shadow:
    case Accumulator{files,seen,issues} Shadow{path,more}:
      do IO<ContextFiles>:
        result : Accumulator <- ancestors(cwd,path,Accumulator{Nil{},seen,List.append(&2,D.ResourceDiagnostic,issues,more)})
        return finished(files,result)
def locations(cwd: Result<&2,&2,Paths.Error,String>,agentDir: Result<&2,&2,Paths.Error,String>) -> IO(ContextFiles):
  match cwd agentDir:
    case Fail{_} _: IO.pure(ContextFiles,ContextFiles{Nil{},D.warning("Invalid context working directory","") <> Nil{}})
    case _ Fail{_}: IO.pure(ContextFiles,ContextFiles{Nil{},D.warning("Invalid context agent directory","") <> Nil{}})
    case Done{+cwd} Done{agentDir}:
      do IO<ContextFiles>:
        global : Candidate <- loadContextFileFromDir(agentDir)
        shadow : Shadow <- findShadowedContextFile(cwd)
        inherited(collected(global,False{},Accumulator{Nil{},Strings.empty(),Nil{}}),shadow,cwd)
def loadProjectContextFiles(+environment: Paths.Environment,options: Options) -> IO(ContextFiles):
  match options:
    case Options{cwd,agentDir}: locations(Paths.resolvePath(environment,cwd,"",Paths.defaults()),Paths.resolvePath(environment,agentDir,"",Paths.defaults()))
