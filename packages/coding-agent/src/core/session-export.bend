import Base
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/schema-value.bend as V
import ./session-manager.bend as S
import ./session-json.bend as Json
import ./session-persistence.bend as Persistence

# Export the selected conversation path, leaving the live session unchanged.
# Extra records are presentation metadata; they are never appended to the
# session itself. Their parent is the last conversation entry in the export.
def trailingLines(entries: List<&2,V.Value>) -> String:
  match entries:
    case Nil{}: ""
    case entry <> rest: Json.line(entry) ++ trailingLines(rest)

def appendTrailing(base: Persistence.Outcome(String), trailing: List<&2,V.Value>) -> Persistence.Outcome(String):
  match base:
    case Fail{error}: Fail{error}
    case Done{text}: Done{text ++ trailingLines(trailing)}

def serializeSessionBranch(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, +state: S.SessionManager<D,T,C>, +timestamp: String, createTrailingEntries: Maybe<&2,String> -> String -> List<&2,V.Value>) -> Persistence.Outcome(String):
  appendTrailing(Persistence.branchContent(~D,~T,~C,~diagnostic,~tool,~custom,state,timestamp),createTrailingEntries(S.getLeafId(D,T,C,state))(timestamp))

def written(path: String,result: Result<&2,&2,FS.Error,Unit>) -> Result<&2,&2,String,String>:
  match result:
    case Done{_}: Done{path}
    case Fail{error}: Fail{FS.errorMessage(error)}

def writeAfterDirectory(+path: String,text: String,result: Result<&2,&2,FS.Error,Unit>) -> IO(Result<&2,&2,String,String>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&2,String,String>,Fail{FS.errorMessage(error)})
    case Done{_}:
      do IO<Result<&2,&2,String,String>>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,text)
        return written(path,result)

def exportContent(+path: String,content: Persistence.Outcome(String)) -> IO(Result<&2,&2,String,String>):
  match content:
    case Fail{error}: IO.pure(Result<&2,&2,String,String>,Fail{Persistence.message(error)})
    case Done{text}:
      do IO<Result<&2,&2,String,String>>:
        directory : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(Path.join(path,".."))
        writeAfterDirectory(path,text,directory)

def exportResolved(resolved: Maybe<&2,String>,content: Persistence.Outcome(String)) -> IO(Result<&2,&2,String,String>):
  match resolved:
    case None{}: IO.pure(Result<&2,&2,String,String>,Fail{"Could not resolve export path"})
    case Some{target}: exportContent(target,content)

def outputPath(path: Maybe<&2,String>,timestamp: String) -> String:
  match path:
    case Some{given}: given
    case None{}: "session-" ++ Strings.replaceAll(Strings.replaceAll(timestamp,":","-"),".","-") ++ ".jsonl"

def exportSessionToJsonl(~D: Data, ~T: Data, ~C: Data, ~diagnostic: D -> V.Value, ~tool: T -> V.Value, ~custom: C -> V.Value, state: S.SessionManager<D,T,C>, cwd: String, path: Maybe<&2,String>, +timestamp: String, createTrailingEntries: Maybe<&2,String> -> String -> List<&2,V.Value>) -> IO(Result<&2,&2,String,String>):
  exportResolved(Path.resolve(cwd,outputPath(path,timestamp)),serializeSessionBranch(~D,~T,~C,~diagnostic,~tool,~custom,state,timestamp,createTrailingEntries))
