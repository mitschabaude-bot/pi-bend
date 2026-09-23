import Base

# upstream session-cwd.ts: a stored session whose working directory no longer
# exists cannot be resumed without a cwd override.

type SessionCwdIssue is Data:
  SessionCwdIssue{sessionFile: Maybe<&2, String>, sessionCwd: String, fallbackCwd: String}

def directoryExists(path: String) -> IO(Bool):
  do IO<Bool>:
    result : Result<&1, &1, U32 & String, Unit> <- File.access(path, 0)
    return Result.is_done(&1, &1, U32 & String, Unit, result)

def missingIssue(+sessionFile: String, +sessionCwd: String, fallbackCwd: String) -> IO(Maybe<&2, SessionCwdIssue>):
  do IO<Maybe<&2, SessionCwdIssue>>:
    present : Bool <- directoryExists(sessionCwd)
    return Bool.pick(Maybe<&2, SessionCwdIssue>, String.is_empty(sessionCwd) || present, None{}, Some{SessionCwdIssue{Some{sessionFile}, sessionCwd, fallbackCwd}})

def getMissingSessionCwdIssue(sessionFile: Maybe<&2, String>, sessionCwd: String, fallbackCwd: String) -> IO(Maybe<&2, SessionCwdIssue>):
  match sessionFile:
    case None{}: IO.pure(Maybe<&2, SessionCwdIssue>, None{})
    case Some{file}: missingIssue(file, sessionCwd, fallbackCwd)

def sessionFileLine(sessionFile: Maybe<&2, String>) -> String:
  match sessionFile:
    case None{}: ""
    case Some{file}: "\nSession file: " ++ file

def formatMissingSessionCwdError(issue: SessionCwdIssue) -> String:
  match issue:
    case SessionCwdIssue{sessionFile, sessionCwd, fallbackCwd}: "Stored session working directory does not exist: " ++ sessionCwd ++ sessionFileLine(sessionFile) ++ "\nCurrent working directory: " ++ fallbackCwd

def formatMissingSessionCwdPrompt(issue: SessionCwdIssue) -> String:
  match issue:
    case SessionCwdIssue{_, sessionCwd, fallbackCwd}: "cwd from session file does not exist\n" ++ sessionCwd ++ "\n\ncontinue in current cwd\n" ++ fallbackCwd

def issueError(issue: Maybe<&2, SessionCwdIssue>) -> Result<&2, &2, String, Unit>:
  match issue:
    case None{}: Done{Unit{}}
    case Some{found}: Fail{formatMissingSessionCwdError(found)}

# upstream assertSessionCwdExists: the MissingSessionCwdError message.
def assertSessionCwdExists(sessionFile: Maybe<&2, String>, sessionCwd: String, fallbackCwd: String) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    issue : Maybe<&2, SessionCwdIssue> <- getMissingSessionCwdIssue(sessionFile, sessionCwd, fallbackCwd)
    return issueError(issue)
