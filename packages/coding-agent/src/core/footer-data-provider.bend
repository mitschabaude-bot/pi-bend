import Base
import ../../../runtime/src/text.bend as Text
import ../utils/paths.bend as Paths
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/utf8.bend as Utf8

# Git metadata discovery only. Branch state, watchers and footer subscriptions
# remain separate, unported responsibilities of the upstream provider.
type GitPaths is Data:
  GitPaths{repoDir: String,commonGitDir: String,headPath: String}
type Probe is Data:
  Continue{}
  Found{paths: Maybe<&2,GitPaths>}
def parent(path: String) -> String:
  Maybe.default(&2,String,Path.resolve(path,".."),"/")
def exists(result: Result<&2,&2,FS.Error,FS.FileKind>) -> Bool:
  match result:
    case Done{_}: True{}
    case Fail{_}: False{}
def decoded(value: Result<&2,&2,Utf8.Error,String>) -> Maybe<&2,String>:
  match value:
    case Done{content}: Some{content}
    case Fail{_}: None{}
def text(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> Maybe<&2,String>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: decoded(Utf8.decodeWith(Utf8.Preserve{},bytes))
def readText(path: String) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return text(result)
def commonText(value: Maybe<&2,String>,repo: String,+gitDir: String,head: String) -> Probe:
  match value:
    case None{}: Found{None{}}
    case Some{value}: Found{Some{GitPaths{repo,Maybe.default(&2,String,Path.resolve(gitDir,Text.trim(value)),gitDir),head}}}
def commonKind(kind: Result<&2,&2,FS.Error,FS.FileKind>,repo: String,+gitDir: String,head: String) -> IO(Probe):
  match kind:
    case Fail{_}: IO.pure(Probe,Found{Some{GitPaths{repo,gitDir,head}}})
    case Done{_}:
      do IO<Probe>:
        value : Maybe<&2,String> <- readText(Path.join(gitDir,"commondir"))
        return commonText(value,repo,gitDir,head)
def linkedHead(present: Bool,repo: String,+gitDir: String,head: String) -> IO(Probe):
  match present:
    case False{}: IO.pure(Probe,Found{None{}})
    case True{}:
      do IO<Probe>:
        kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(Path.join(gitDir,"commondir"))
        commonKind(kind,repo,gitDir,head)
def linkedTarget(repo: String,+gitDir: String) -> IO(Probe):
  do IO<Probe>:
    +head : String = Path.join(gitDir,"HEAD")
    kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(head)
    linkedHead(exists(kind),repo,gitDir,head)
def gitFile(value: Maybe<&2,String>,+repo: String) -> IO(Probe):
  match value:
    case None{}: IO.pure(Probe,Found{None{}})
    case Some{value}:
      +content = Text.trim(value)
      Bool.pick(Unit -> IO(Probe),String.starts_with(content,"gitdir: "),_ => linkedTarget(repo,Maybe.default(&2,String,Path.resolve(repo,Text.trim(String.drop(content,8n))),repo)),_ => IO.pure(Probe,Continue{}))(Unit{})
def regularHead(kind: Result<&2,&2,FS.Error,FS.FileKind>,repo: String,gitDir: String,head: String) -> Probe:
  Bool.pick(Probe,exists(kind),Found{Some{GitPaths{repo,gitDir,head}}},Found{None{}})
def gitKind(kind: Result<&2,&2,FS.Error,FS.FileKind>,+repo: String,+gitPath: String) -> IO(Probe):
  match kind:
    case Done{FS.RegularFile{}}:
      do IO<Probe>:
        content : Maybe<&2,String> <- readText(gitPath)
        gitFile(content,repo)
    case Done{FS.Directory{}}:
      do IO<Probe>:
        +head : String = Path.join(gitPath,"HEAD")
        value : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(head)
        return regularHead(value,repo,gitPath,head)
    case _: IO.pure(Probe,Continue{})
def probe(+directory: String) -> IO(Probe):
  do IO<Probe>:
    +gitPath : String = Path.join(directory,".git")
    kind : Result<&2,&2,FS.Error,FS.FileKind> <- FS.fileKind(gitPath)
    gitKind(kind,directory,gitPath)
def probePaths(result: Probe) -> Maybe<&2,GitPaths>:
  match result:
    case Continue{}: None{}
    case Found{paths}: paths
def finished(result: Probe) -> Bool:
  match result:
    case Continue{}: False{}
    case Found{_}: True{}
# cwd is an absolute lexical path; each unsuccessful step removes one component.
@unsafe def findGitPaths(+cwd: String) -> IO(Maybe<&2,GitPaths>):
  do IO<Maybe<&2,GitPaths>>:
    +result : Probe <- probe(cwd)
    +next : String = parent(cwd)
    Bool.pick(Unit -> IO(Maybe<&2,GitPaths>),finished(result) || Strings.equal(cwd,next),_ => IO.pure(Maybe<&2,GitPaths>,probePaths(result)),_ => findGitPaths(next))(Unit{})
