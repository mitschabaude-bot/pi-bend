import Base
import ../../../../runtime/src/child-process.bend as Child
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/utf8.bend as UTF8

type ExternalEditorOptions is Data:
  ExternalEditorOptions{command: String,content: String}

type ExternalEditorResult is Data:
  Complete{content: String}
  Failed{}

def removeFinalNewline(reversed: String) -> String:
  match reversed:
    case SCon{'\n',rest}: String.reverse(rest)
    case text: String.reverse(text)

def editedText(text: String) -> String:
  match text:
    case SCon{Chr{65279},rest}: removeFinalNewline(String.reverse(rest))
    case text: removeFinalNewline(String.reverse(text))

def decoded(result: Result<&2,&2,UTF8.Error,String>) -> ExternalEditorResult:
  match result:
    case Fail{_}: Failed{}
    case Done{text}: Complete{editedText(text)}

def readResult(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> ExternalEditorResult:
  match result:
    case Fail{_}: Failed{}
    case Done{bytes}: decoded(UTF8.decodeWith(UTF8.Preserve{},bytes))

def finished(file: String,result: Result<&1,&1,U32 & String,ProcessStatus>,closed: Result<&1,&1,U32 & String,Unit>) -> IO(ExternalEditorResult):
  match result closed:
    case Done{ProcessExited{0}} Done{_}:
      do IO<ExternalEditorResult>:
        bytes : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(file)
        return readResult(bytes)
    case _ _: IO.pure(ExternalEditorResult,Failed{})

def waited(file: String,pair: Process & Result<&1,&1,U32 & String,ProcessStatus>) -> IO(ExternalEditorResult):
  match pair:
    case (owner,result):
      do IO<ExternalEditorResult>:
        closed : Result<&1,&1,U32 & String,Unit> <- Process.close_checked(owner)
        finished(file,result,closed)

def spawned(file: String,result: Result<&1,&1,U32 & String,Process>) -> IO(ExternalEditorResult):
  match result:
    case Fail{_}: IO.pure(ExternalEditorResult,Failed{})
    case Done{owner}:
      do IO<ExternalEditorResult>:
        result : Process & Result<&1,&1,U32 & String,ProcessStatus> <- Process.wait(owner)
        waited(file,result)

def launch(file: String,args: List<String>,cwd: String,env: List<String>,path: Maybe<&2,String>) -> IO(ExternalEditorResult):
  match path:
    case None{}: IO.pure(ExternalEditorResult,Failed{})
    case Some{program}:
      do IO<ExternalEditorResult>:
        result : Result<&1,&1,U32 & String,Process> <- Process.spawn_inherit(program,args,cwd,env)
        spawned(file,result)

def searched(file: String,command: String,args: List<String>,cwd: String,environment: String & List<String>) -> IO(ExternalEditorResult):
  match environment:
    case (path,env):
      do IO<ExternalEditorResult>:
        resolved : Maybe<&2,String> <- Child.resolveCommand(command,path)
        launch(file,args,cwd,env,resolved)

def editorArgs(args: List<&2,String>,file: String) -> List<String>:
  match args:
    case Nil{}: [file]
    case arg <> rest: arg <> editorArgs(rest,file)

def runCommand(+file: String,command: List<&2,String>,cwd: String) -> IO(ExternalEditorResult):
  match command:
    case Nil{}: IO.pure(ExternalEditorResult,Failed{})
    case program <> args:
      do IO<ExternalEditorResult>:
        environment : List<String> <- IO.environment()
        searched(file,program,editorArgs(args,file),cwd,Child.withSearchPath(environment,None{}))

def written(file: String,+command: String,cwd: String,result: Result<&2,&2,FS.Error,Unit>) -> IO(ExternalEditorResult):
  match result:
    case Fail{_}: IO.pure(ExternalEditorResult,Failed{})
    case Done{_}:
      do IO<ExternalEditorResult>:
        IO.print("Launching external editor: " ++ command ++ "\nPi will resume when the editor exits.")
        runCommand(file,Strings.split(command,' '),cwd)

def prepared(options: ExternalEditorOptions,cwd: String,result: Result<&1,&1,U32 & String,String>) -> IO(ExternalEditorResult):
  match options result:
    case _ Fail{_}: IO.pure(ExternalEditorResult,Failed{})
    case ExternalEditorOptions{command,content} Done{+directory}:
      +file = FS.child(directory,"prompt.md")
      do IO<ExternalEditorResult>:
        write : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(file,content)
        result : ExternalEditorResult <- written(file,command,cwd,write)
        removed : Result<&2,&2,FS.Error,Unit> <- FS.remove(directory,True{},True{})
        return result

def currentDirectory(options: ExternalEditorOptions,result: Result<&2,&2,FS.Error,String>) -> IO(ExternalEditorResult):
  match result:
    case Fail{_}: IO.pure(ExternalEditorResult,Failed{})
    case Done{cwd}:
      do IO<ExternalEditorResult>:
        temporary : Result<&1,&1,U32 & String,String> <- IO.get_env("TMPDIR")
        directory : Result<&1,&1,U32 & String,String> <- Directory.mkdtemp(FS.child(Result.default(&1,&1,U32 & String,String,temporary,"/tmp"),"pi-editor-XXXXXX"))
        prepared(options,cwd,directory)

# The caller suspends terminal input/rendering before calling, then resumes on
# either result. The child inherits all three stdio descriptors and stays in the
# foreground process group; no shell interprets the configured arguments.
def editInExternalEditor(options: ExternalEditorOptions) -> IO(ExternalEditorResult):
  do IO<ExternalEditorResult>:
    cwd : Result<&2,&2,FS.Error,String> <- FS.cwd()
    currentDirectory(options,cwd)
