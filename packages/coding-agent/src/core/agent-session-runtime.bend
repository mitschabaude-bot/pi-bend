import Base
import ./agent-session.bend as Session
import ./session-persistence.bend as Sessions
import ./session-cwd.bend as SessionCwd
import ./session-manager.bend as SM
import ./tools/index.bend as Tools
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/ref.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/utf8.bend as Utf8

# upstream AgentSessionRuntime: owns the current AgentSession and the services
# it was created with. Replacing the session tears the current one down first
# (abort, then dispose), creates the next one through the factory the initial
# runtime was created with, and then calls the host's rebind hook so its mode
# follows the new session. Extension events (session_before_switch,
# session_shutdown, session_start) are not ported; replacement is never
# cancelled.

type StartReason is Data:
  NewStart{}
  ResumeStart{}
  ForkStart{}

type SessionStart is Data:
  SessionStart{reason: StartReason, previousSessionFile: Maybe<&2, String>}

# What the factory creates a runtime for: the target cwd, its session and how
# the session started (None for the initial runtime).
type Request is Data:
  Request{cwd: String, session: Session.Session(), start: Maybe<&2, SessionStart>}

type Created<-S: Type> is Type:
  Created{services: S, session: Session.AgentSession}

def Factory(-S: Type) -> Data: C.Callback<Request, Result<&1, &1, String, Created<S>>>
def Rebind() -> Data: C.Callback<Session.AgentSession, Unit>

type Current<-S: Type> is Type:
  Active{services: S, session: Session.AgentSession, cwd: String}
  Released{}

# A replaced session stops at teardown but is released one replacement later
# (or with the runtime): concurrent readers, such as interactive frames, may
# still hold it until they observe its successor.
type Retiring<-S: Type> is Type:
  Retiring{services: S, session: Session.AgentSession}
  NothingRetiring{}

type AgentSessionRuntime<-S: Type> is Data:
  AgentSessionRuntime{current: R.Ref<Current<S>>, factory: Factory(S), release: C.Callback<S, Unit>, agentDir: String, rebind: R.Ref<Maybe<&2, Rebind()>>, retiring: R.Ref<Retiring<S>>}

def installed(-S: Type, +factory: Factory(S), +release: C.Callback<S, Unit>, +agentDir: String, +directory: String, result: Result<&1, &1, String, Created<S>>) -> IO(Result<&2, &2, String, AgentSessionRuntime<S>>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, AgentSessionRuntime<S>>, Fail{error})
    case Done{Created{services, live}}:
      do IO<Result<&2, &2, String, AgentSessionRuntime<S>>>:
        current : R.Ref<Current<S>> <- R.new(Current<S>, Active{services, live, directory})
        rebind : R.Ref<Maybe<&2, Rebind()>> <- R.new(Maybe<&2, Rebind()>, None{})
        retiring : R.Ref<Retiring<S>> <- R.new(Retiring<S>, NothingRetiring{})
        return Done{AgentSessionRuntime{current, factory, release, agentDir, rebind, retiring}}

def createChecked(-S: Type, +factory: Factory(S), +release: C.Callback<S, Unit>, +agentDir: String, +directory: String, live: Session.Session(), checked: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, AgentSessionRuntime<S>>):
  match checked:
    case Fail{error}: IO.pure(Result<&2, &2, String, AgentSessionRuntime<S>>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, String, AgentSessionRuntime<S>>>:
        result : Result<&1, &1, String, Created<S>> <- C.call(Request, Result<&1, &1, String, Created<S>>, factory, Request{directory, live, None{}})
        installed(S, factory, release, agentDir, directory, result)

# upstream createAgentSessionRuntime: the initial runtime for a session whose
# stored cwd exists; release disposes the services of a replaced runtime.
def create(-S: Type, +factory: Factory(S), +release: C.Callback<S, Unit>, +agentDir: String, +directory: String, +live: Session.Session()) -> IO(Result<&2, &2, String, AgentSessionRuntime<S>>):
  do IO<Result<&2, &2, String, AgentSessionRuntime<S>>>:
    checked : Result<&2, &2, String, Unit> <- SessionCwd.assertSessionCwdExists(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, live), Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, live), directory)
    createChecked(S, factory, release, agentDir, directory, live, checked)

def sessionIn(-S: Type, current: Current<S>) -> Current<S> & Maybe<&2, Session.AgentSession>:
  match current:
    case Active{services, +live, directory}: (Active{services, live, directory}, Some{live})
    case Released{}: (Released{}, None{})

# The current session; None only after a failed replacement or dispose.
def session(-S: Type, runtime: AgentSessionRuntime<S>) -> IO(Maybe<&2, Session.AgentSession>):
  match runtime:
    case AgentSessionRuntime{current, _, _, _, _, _}: R.modify(Current<S>, Maybe<&2, Session.AgentSession>, current, value => sessionIn(S, value))

def cwdIn(-S: Type, current: Current<S>) -> Current<S> & Maybe<&2, String>:
  match current:
    case Active{services, live, +directory}: (Active{services, live, directory}, Some{directory})
    case Released{}: (Released{}, None{})

def cwd(-S: Type, runtime: AgentSessionRuntime<S>) -> IO(Maybe<&2, String>):
  match runtime:
    case AgentSessionRuntime{current, _, _, _, _, _}: R.modify(Current<S>, Maybe<&2, String>, current, value => cwdIn(S, value))

def restored(-S: Type, -A: Type, current: R.Ref<Current<S>>, +live: Session.AgentSession, +directory: String, pair: S & A) -> IO(A):
  match pair:
    case (services, value):
      do IO<A>:
        R.modify(Current<S>, Unit, current, released => (Active{services, live, directory}, Unit{}))
        return value

def servicesAction(-S: Type, -A: Type, current: R.Ref<Current<S>>, action: S -> IO(S & A), fallback: A, taken: Current<S>) -> IO(A):
  match taken:
    case Released{}: IO.pure(A, fallback)
    case Active{services, live, directory}:
      do IO<A>:
        pair : S & A <- action(services)
        restored(S, A, current, live, directory, pair)

# Run an action on the current services (for example to read the model
# catalog) without releasing them.
def withServices(-S: Type, -A: Type, runtime: AgentSessionRuntime<S>, action: S -> IO(S & A), fallback: A) -> IO(A):
  match runtime:
    case AgentSessionRuntime{+current, _, _, _, _, _}:
      do IO<A>:
        taken : Current<S> <- R.modify(Current<S>, Current<S>, current, value => (Released{}, value))
        servicesAction(S, A, current, action, fallback, taken)

# upstream setRebindSession: called with the new session after each
# replacement.
def setRebindSession(-S: Type, runtime: AgentSessionRuntime<S>, rebind: Maybe<&2, Rebind()>) -> IO(Unit):
  match runtime:
    case AgentSessionRuntime{_, _, _, _, hook, _}: R.modify(Maybe<&2, Rebind()>, Unit, hook, previous => (rebind, Unit{}))

def finishRetiring(-S: Type, release: C.Callback<S, Unit>, retired: Retiring<S>) -> IO(Unit):
  match retired:
    case NothingRetiring{}: IO.pure(Unit, Unit{})
    case Retiring{services, live}:
      do IO<Unit>:
        Session.retire(live)
        C.call(S, Unit, release, services)

def released(-S: Type, +release: C.Callback<S, Unit>, retiring: R.Ref<Retiring<S>>, taken: Current<S>) -> IO(Maybe<&2, Session.Session()>):
  match taken:
    case Released{}: IO.pure(Maybe<&2, Session.Session()>, None{})
    case Active{services, +live, _}:
      do IO<Maybe<&2, Session.Session()>>:
        Session.abort(live)
        outgoing : Session.Session() <- Session.sessionOf(live)
        Session.shutdown(live)
        previous : Retiring<S> <- R.modify(Retiring<S>, Retiring<S>, retiring, value => (Retiring{services, live}, value))
        finishRetiring(S, release, previous)
        return Some{outgoing}

# upstream teardownCurrent: settle an active response so the aborted turn is
# persisted to the outgoing session, then dispose it and its services. The
# outgoing session record is returned.
def teardownCurrent(-S: Type, runtime: AgentSessionRuntime<S>) -> IO(Maybe<&2, Session.Session()>):
  match runtime:
    case AgentSessionRuntime{current, _, release, _, _, retiring}:
      do IO<Maybe<&2, Session.Session()>>:
        taken : Current<S> <- R.modify(Current<S>, Current<S>, current, value => (Released{}, value))
        released(S, release, retiring, taken)

def rebound(hook: Maybe<&2, Rebind()>, live: Session.AgentSession) -> IO(Unit):
  match hook:
    case None{}: IO.pure(Unit, Unit{})
    case Some{callback}: C.call(Session.AgentSession, Unit, callback, live)

def applied(-S: Type, runtime: AgentSessionRuntime<S>, +directory: String, result: Result<&1, &1, String, Created<S>>) -> IO(Result<&2, &2, String, Unit>):
  match runtime result:
    case _ Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case AgentSessionRuntime{current, _, _, _, hook, _} Done{Created{services, +live}}:
      do IO<Result<&2, &2, String, Unit>>:
        R.modify(Current<S>, Unit, current, previous => (Active{services, live, directory}, Unit{}))
        rebind : Maybe<&2, Rebind()> <- R.read(Maybe<&2, Rebind()>, hook)
        rebound(rebind, live)
        return Done{Unit{}}

def createNext(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, next: Session.Session(), start: SessionStart) -> IO(Result<&2, &2, String, Unit>):
  match runtime:
    case AgentSessionRuntime{_, factory, _, _, _, _}:
      do IO<Result<&2, &2, String, Unit>>:
        result : Result<&1, &1, String, Created<S>> <- C.call(Request, Result<&1, &1, String, Created<S>>, factory, Request{directory, next, Some{start}})
        applied(S, runtime, directory, result)

# Tear down, create the runtime for the next session and rebind.
def replaced(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, next: Session.Session(), start: SessionStart) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    outgoing : Maybe<&2, Session.Session()> <- teardownCurrent(S, runtime)
    createNext(S, runtime, directory, next, start)

type Snapshot is Data:
  Snapshot{cwd: String, session: Session.Session()}

def snapshotOf(live: Maybe<&2, Session.AgentSession>, directory: Maybe<&2, String>) -> IO(Maybe<&2, Snapshot>):
  match live directory:
    case Some{live} Some{directory}:
      do IO<Maybe<&2, Snapshot>>:
        stored : Session.Session() <- Session.sessionOf(live)
        return Some{Snapshot{directory, stored}}
    case _ _: IO.pure(Maybe<&2, Snapshot>, None{})

def snapshot(-S: Type, +runtime: AgentSessionRuntime<S>) -> IO(Maybe<&2, Snapshot>):
  do IO<Maybe<&2, Snapshot>>:
    current : Maybe<&2, Session.AgentSession> <- session(S, runtime)
    directory : Maybe<&2, String> <- cwd(S, runtime)
    snapshotOf(current, directory)

def noSession() -> String: "No active live"

def createdNext(+directory: String, persisted: Bool, sessionDir: String, agentDir: String, options: Sessions.NewSessionOptions) -> IO(Sessions.Outcome(Session.Session())):
  match persisted:
    case True{}: Session.createSession(directory, Some{sessionDir}, agentDir, options)
    case False{}: Session.memorySession(directory, options)

def replacedWith(-S: Type, runtime: AgentSessionRuntime<S>, +directory: String, start: SessionStart, next: Sessions.Outcome(Session.Session())) -> IO(Result<&2, &2, String, Unit>):
  match next:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{Sessions.message(error)})
    case Done{live}: replaced(S, runtime, directory, live, start)

def newFrom(-S: Type, +runtime: AgentSessionRuntime<S>, parentSession: Maybe<&2, String>, found: Maybe<&2, Snapshot>) -> IO(Result<&2, &2, String, Unit>):
  match runtime found:
    case _ None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{noSession()})
    case AgentSessionRuntime{_, _, _, agentDir, _, _} Some{Snapshot{+directory, +stored}}:
      do IO<Result<&2, &2, String, Unit>>:
        next : Sessions.Outcome(Session.Session()) <- createdNext(directory, Sessions.isPersisted(Unit, Tools.ToolDetails, V.Value, stored), Sessions.getSessionDir(Unit, Tools.ToolDetails, V.Value, stored), agentDir, Sessions.NewSessionOptions{None{}, parentSession})
        replacedWith(S, runtime, directory, SessionStart{NewStart{}, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)}, next)

# upstream newSession: a new session in the current cwd, persisted in the
# current session cwd unless the current session is in memory.
def newSession(-S: Type, +runtime: AgentSessionRuntime<S>, parentSession: Maybe<&2, String>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    found : Maybe<&2, Snapshot> <- snapshot(S, runtime)
    newFrom(S, runtime, parentSession, found)

def switchChecked(-S: Type, runtime: AgentSessionRuntime<S>, previous: Maybe<&2, String>, +next: Session.Session(), checked: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match checked:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{_}: replaced(S, runtime, Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, next), next, SessionStart{ResumeStart{}, previous})

def switchOpened(-S: Type, +runtime: AgentSessionRuntime<S>, previous: Maybe<&2, String>, fallbackCwd: String, opened: Sessions.Outcome(Session.Session())) -> IO(Result<&2, &2, String, Unit>):
  match opened:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{Sessions.message(error)})
    case Done{+next}:
      do IO<Result<&2, &2, String, Unit>>:
        checked : Result<&2, &2, String, Unit> <- SessionCwd.assertSessionCwdExists(Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, next), Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, next), fallbackCwd)
        switchChecked(S, runtime, previous, next, checked)

def switchFrom(-S: Type, +runtime: AgentSessionRuntime<S>, +sessionPath: String, cwdOverride: Maybe<&2, String>, found: Maybe<&2, Snapshot>) -> IO(Result<&2, &2, String, Unit>):
  match found:
    case None{}: IO.pure(Result<&2, &2, String, Unit>, Fail{noSession()})
    case Some{Snapshot{+directory, stored}}:
      do IO<Result<&2, &2, String, Unit>>:
        opened : Sessions.Outcome(Session.Session()) <- Sessions.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~Session.unitValue, ~Tools.detailsValue, ~Session.rawValue, ~Session.readUnit, ~Session.readDetails, ~Session.readRaw, sessionPath, None{}, cwdOverride, directory)
        switchOpened(S, runtime, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored), directory, opened)

# upstream switchSession: resume a stored session in its own cwd.
def switchSession(-S: Type, +runtime: AgentSessionRuntime<S>, sessionPath: String, cwdOverride: Maybe<&2, String>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    found : Maybe<&2, Snapshot> <- snapshot(S, runtime)
    switchFrom(S, runtime, sessionPath, cwdOverride, found)

type ResumeOutcome is Data:
  Resumed{}
  ResumeNeedsCwd{issue: SessionCwd.SessionCwdIssue}
  ResumeFailed{message: String}
def matchResumeResult(result: Result<&2,&2,String,Unit>) -> IO(ResumeOutcome):
  match result:
    case Done{_}: IO.pure(ResumeOutcome,Resumed{})
    case Fail{message}: IO.pure(ResumeOutcome,ResumeFailed{message})
def resumeChecked(-S: Type,runtime: AgentSessionRuntime<S>,previous: Maybe<&2,String>,+next: Session.Session(),issue: Maybe<&2,SessionCwd.SessionCwdIssue>) -> IO(ResumeOutcome):
  match issue:
    case Some{found}: IO.pure(ResumeOutcome,ResumeNeedsCwd{found})
    case None{}:
      do IO<ResumeOutcome>:
        result : Result<&2,&2,String,Unit> <- replaced(S,runtime,Sessions.getCwd(Unit,Tools.ToolDetails,V.Value,next),next,SessionStart{ResumeStart{},previous})
        matchResumeResult(result)
def resumeOpened(-S: Type,runtime: AgentSessionRuntime<S>,previous: Maybe<&2,String>,fallbackCwd: String,opened: Sessions.Outcome(Session.Session())) -> IO(ResumeOutcome):
  match opened:
    case Fail{error}: IO.pure(ResumeOutcome,ResumeFailed{Sessions.message(error)})
    case Done{+next}:
      do IO<ResumeOutcome>:
        issue : Maybe<&2,SessionCwd.SessionCwdIssue> <- SessionCwd.getMissingSessionCwdIssue(Sessions.getSessionFile(Unit,Tools.ToolDetails,V.Value,next),Sessions.getCwd(Unit,Tools.ToolDetails,V.Value,next),fallbackCwd)
        resumeChecked(S,runtime,previous,next,issue)
def resumeFrom(-S: Type,runtime: AgentSessionRuntime<S>,sessionPath: String,cwdOverride: Maybe<&2,String>,found: Maybe<&2,Snapshot>) -> IO(ResumeOutcome):
  match found:
    case None{}: IO.pure(ResumeOutcome,ResumeFailed{noSession()})
    case Some{Snapshot{+directory,stored}}:
      do IO<ResumeOutcome>:
        opened : Sessions.Outcome(Session.Session()) <- Sessions.open(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,~Session.readUnit,~Session.readDetails,~Session.readRaw,sessionPath,None{},cwdOverride,directory)
        resumeOpened(S,runtime,Sessions.getSessionFile(Unit,Tools.ToolDetails,V.Value,stored),directory,opened)
def resumeSession(-S: Type,+runtime: AgentSessionRuntime<S>,sessionPath: String,cwdOverride: Maybe<&2,String>) -> IO(ResumeOutcome):
  do IO<ResumeOutcome>:
    found : Maybe<&2,Snapshot> <- snapshot(S,runtime)
    resumeFrom(S,runtime,sessionPath,cwdOverride,found)

type ImportOutcome is Data:
  Imported{path: String}
  ImportNeedsCwd{issue: SessionCwd.SessionCwdIssue}
  ImportFailed{message: String}

def importSwitched(path: String,result: Result<&2,&2,String,Unit>) -> ImportOutcome:
  match result:
    case Done{_}: Imported{path}
    case Fail{message}: ImportFailed{message}
def importSelected(-S: Type,runtime: AgentSessionRuntime<S>,+path: String,cwdOverride: Maybe<&2,String>) -> IO(ImportOutcome):
  do IO<ImportOutcome>:
    result : Result<&2,&2,String,Unit> <- switchSession(S,runtime,path,cwdOverride)
    return importSwitched(path,result)
def importName(+base: String,+suffix: Nat) -> String:
  Bool.pick(String,String.ends_with(base,".jsonl"),String.take(base,String.length(base) - 6n) ++ "-" ++ Nat.show(suffix) ++ ".jsonl",base ++ "-" ++ Nat.show(suffix))
@unsafe def importTarget(+directory: String,+base: String,+suffix: Nat) -> IO(String):
  +candidate = Path.join(directory,Bool.pick(String,Nat.is_eq(suffix,0n),base,importName(base,suffix)))
  do IO<String>:
    exists : Bool <- FS.accessible(candidate,0)
    Bool.pick(Unit -> IO(String),exists,_ => importTarget(directory,base,suffix + 1n),_ => IO.pure(String,candidate))(Unit{})
def importedCopy(-S: Type,runtime: AgentSessionRuntime<S>,target: String,cwdOverride: Maybe<&2,String>,written: Result<&2,&2,FS.Error,Unit>) -> IO(ImportOutcome):
  match written:
    case Fail{error}: IO.pure(ImportOutcome,ImportFailed{FS.errorMessage(error)})
    case Done{_}: importSelected(S,runtime,target,cwdOverride)
def importCopied(-S: Type,runtime: AgentSessionRuntime<S>,+target: String,cwdOverride: Maybe<&2,String>,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> IO(ImportOutcome):
  match read:
    case Fail{error}: IO.pure(ImportOutcome,ImportFailed{FS.errorMessage(error)})
    case Done{bytes}:
      do IO<ImportOutcome>:
        written : Result<&2,&2,FS.Error,Unit> <- FS.writeFileExclusive(target,Utf8.decodeBytes(bytes))
        importedCopy(S,runtime,target,cwdOverride,written)
def importLocated(-S: Type,+runtime: AgentSessionRuntime<S>,+source: String,directory: String,cwdOverride: Maybe<&2,String>,alreadyStored: Bool) -> IO(ImportOutcome):
  match alreadyStored:
    case True{}: importSelected(S,runtime,source,cwdOverride)
    case False{}:
      do IO<ImportOutcome>:
        target : String <- importTarget(directory,Path.basename(source),0n)
        read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(source)
        importCopied(S,runtime,target,cwdOverride,read)
def importDestination(-S: Type,+runtime: AgentSessionRuntime<S>,+source: String,+directory: String,cwdOverride: Maybe<&2,String>,created: Result<&2,&2,FS.Error,Unit>) -> IO(ImportOutcome):
  match created:
    case Fail{error}: IO.pure(ImportOutcome,ImportFailed{FS.errorMessage(error)})
    case Done{_}:
      do IO<ImportOutcome>:
        importLocated(S,runtime,source,directory,cwdOverride,String.eq(Path.join(directory,Path.basename(source)),source))
def importCwdChecked(-S: Type,runtime: AgentSessionRuntime<S>,source: String,+directory: String,cwdOverride: Maybe<&2,String>,issue: Maybe<&2,SessionCwd.SessionCwdIssue>) -> IO(ImportOutcome):
  match issue:
    case Some{found}: IO.pure(ImportOutcome,ImportNeedsCwd{found})
    case None{}:
      do IO<ImportOutcome>:
        created : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(directory)
        importDestination(S,runtime,source,directory,cwdOverride,created)
def importOpened(-S: Type,runtime: AgentSessionRuntime<S>,+source: String,directory: String,fallbackCwd: String,cwdOverride: Maybe<&2,String>,opened: Sessions.Outcome(Session.Session())) -> IO(ImportOutcome):
  match opened:
    case Fail{error}: IO.pure(ImportOutcome,ImportFailed{Sessions.message(error)})
    case Done{stored}:
      do IO<ImportOutcome>:
        issue : Maybe<&2,SessionCwd.SessionCwdIssue> <- SessionCwd.getMissingSessionCwdIssue(Some{source},Sessions.getCwd(Unit,Tools.ToolDetails,V.Value,stored),fallbackCwd)
        importCwdChecked(S,runtime,source,directory,cwdOverride,issue)
def importFromSnapshot(-S: Type,runtime: AgentSessionRuntime<S>,+source: String,+cwdOverride: Maybe<&2,String>,found: Maybe<&2,Snapshot>) -> IO(ImportOutcome):
  match found:
    case None{}: IO.pure(ImportOutcome,ImportFailed{noSession()})
    case Some{Snapshot{+directory,stored}}:
      do IO<ImportOutcome>:
        +sessionDir : String <- IO.pure(String,Sessions.getSessionDir(Unit,Tools.ToolDetails,V.Value,stored))
        opened : Sessions.Outcome(Session.Session()) <- Sessions.open(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,~Session.readUnit,~Session.readDetails,~Session.readRaw,source,Some{sessionDir},cwdOverride,directory)
        importOpened(S,runtime,source,sessionDir,directory,cwdOverride,opened)
def importSourceError(path: String,error: FS.Error) -> String:
  match error:
    case FS.System{2,_}: "File not found: " ++ path
    case other: FS.errorMessage(other)
def importResolved(-S: Type,+runtime: AgentSessionRuntime<S>,inputPath: String,cwdOverride: Maybe<&2,String>,found: Result<&2,&2,FS.Error,String>) -> IO(ImportOutcome):
  match found:
    case Fail{error}: IO.pure(ImportOutcome,ImportFailed{importSourceError(inputPath,error)})
    case Done{source}:
      do IO<ImportOutcome>:
        current : Maybe<&2,Snapshot> <- snapshot(S,runtime)
        importFromSnapshot(S,runtime,source,cwdOverride,current)
def importFromJsonl(-S: Type,runtime: AgentSessionRuntime<S>,+inputPath: String,cwdOverride: Maybe<&2,String>) -> IO(ImportOutcome):
  do IO<ImportOutcome>:
    found : Result<&2,&2,FS.Error,String> <- FS.realpath(inputPath)
    importResolved(S,runtime,inputPath,cwdOverride,found)


# Fork
# ----

def agentDirOf(-S: Type, runtime: AgentSessionRuntime<S>) -> String:
  match runtime:
    case AgentSessionRuntime{_, _, _, agentDir, _, _}: agentDir

type ForkPosition is Data:
  ForkBefore{}
  ForkAt{}

# A fork as the modes request it: the entry and where to fork relative to it.
type ForkRequest is Data:
  ForkRequest{entryId: String, position: ForkPosition}

type ForkTarget is Data:
  ForkTarget{leafId: Maybe<&2, String>, selectedText: Maybe<&2, String>}

def invalidEntry() -> String: "Invalid entry ID for forking"

def beforeTarget(found: Maybe<&2, Session.Navigation>) -> Result<&2, &2, String, ForkTarget>:
  match found:
    case Some{Session.Navigation{Some{text}, leaf}}: Done{ForkTarget{leaf, Some{text}}}
    case _: Fail{invalidEntry()}

def forkTargetOf(+entryId: String, position: ForkPosition, found: Maybe<&2, Session.Entry()>) -> Result<&2, &2, String, ForkTarget>:
  match position found:
    case _ None{}: Fail{invalidEntry()}
    case ForkAt{} Some{_}: Done{ForkTarget{Some{entryId}, None{}}}
    case ForkBefore{} Some{entry}: beforeTarget(Session.forkTarget(entry))

def selected(text: Maybe<&2, String>, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{_}: Done{text}

def forked(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, previous: Maybe<&2, String>, text: Maybe<&2, String>, next: Sessions.Outcome(Session.Session())) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match next:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{Sessions.message(error)})
    case Done{branch}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        result : Result<&2, &2, String, Unit> <- replaced(S, runtime, directory, branch, SessionStart{ForkStart{}, previous})
        return selected(text, result)

def fileExists(path: String) -> IO(Bool):
  do IO<Bool>:
    result : Result<&1, &1, U32 & String, Unit> <- File.access(path, 0)
    return Result.is_done(&1, &1, U32 & String, Unit, result)

def branchSaved(-S: Type, +runtime: AgentSessionRuntime<S>, +stored: Session.Session(), file: String, leaf: String, text: Maybe<&2, String>, saved: Bool) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match saved:
    case False{}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{"This session has not been saved yet. Wait for the first assistant response before cloning or forking it."})
    case True{}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        next : Sessions.Outcome(Session.Session()) <- Sessions.createBranchedSession(~Unit, ~Tools.ToolDetails, ~V.Value, ~Session.unitValue, ~Tools.detailsValue, ~Session.rawValue, stored, leaf)
        forked(S, runtime, Sessions.getCwd(Unit, Tools.ToolDetails, V.Value, stored), Some{file}, text, next)

def forkPersistedFile(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, +stored: Session.Session(), leaf: Maybe<&2, String>, text: Maybe<&2, String>, file: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match leaf file:
    case _ None{}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{"Persisted session is missing a session file"})
    case None{} Some{+path}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        next : Sessions.Outcome(Session.Session()) <- Session.createSession(directory, Some{Sessions.getSessionDir(Unit, Tools.ToolDetails, V.Value, stored)}, agentDirOf(S, runtime), Sessions.NewSessionOptions{None{}, Some{path}})
        forked(S, runtime, directory, Some{path}, text, next)
    case Some{id} Some{+path}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        saved : Bool <- fileExists(path)
        branchSaved(S, runtime, stored, path, id, text, saved)

def outgoingNext(+stored: Session.Session(), leaf: Maybe<&2, String>) -> IO(Sessions.Outcome(Session.Session())):
  match leaf:
    case None{}: Sessions.newSession(Unit, Tools.ToolDetails, V.Value, stored, Sessions.NewSessionOptions{None{}, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)})
    case Some{id}: Sessions.createBranchedSession(~Unit, ~Tools.ToolDetails, ~V.Value, ~Session.unitValue, ~Tools.detailsValue, ~Session.rawValue, stored, id)

def forkedAfterTeardown(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, previous: Maybe<&2, String>, text: Maybe<&2, String>, next: Sessions.Outcome(Session.Session())) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match next:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{Sessions.message(error)})
    case Done{branch}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        result : Result<&2, &2, String, Unit> <- createNext(S, runtime, directory, branch, SessionStart{ForkStart{}, previous})
        return selected(text, result)

def forkOutgoing(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, leaf: Maybe<&2, String>, text: Maybe<&2, String>, outgoing: Maybe<&2, Session.Session()>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match outgoing:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{noSession()})
    case Some{+stored}:
      do IO<Result<&2, &2, String, Maybe<&2, String>>>:
        next : Sessions.Outcome(Session.Session()) <- outgoingNext(stored, leaf)
        forkedAfterTeardown(S, runtime, directory, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored), text, next)

# An in-memory session forks from its state after teardown.
def forkInMemory(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, leaf: Maybe<&2, String>, text: Maybe<&2, String>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    outgoing : Maybe<&2, Session.Session()> <- teardownCurrent(S, runtime)
    forkOutgoing(S, runtime, directory, leaf, text, outgoing)

def forkTargeted(-S: Type, +runtime: AgentSessionRuntime<S>, +directory: String, +stored: Session.Session(), target: Result<&2, &2, String, ForkTarget>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match target:
    case Fail{error}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{error})
    case Done{ForkTarget{+leaf, +text}}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, Maybe<&2, String>>), Sessions.isPersisted(Unit, Tools.ToolDetails, V.Value, stored),
        _ => forkPersistedFile(S, runtime, directory, stored, leaf, text, Sessions.getSessionFile(Unit, Tools.ToolDetails, V.Value, stored)),
        _ => forkInMemory(S, runtime, directory, leaf, text))(Unit{})

def forkFrom(-S: Type, +runtime: AgentSessionRuntime<S>, +entryId: String, position: ForkPosition, found: Maybe<&2, Snapshot>) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  match found:
    case None{}: IO.pure(Result<&2, &2, String, Maybe<&2, String>>, Fail{noSession()})
    case Some{Snapshot{+directory, +stored}}: forkTargeted(S, runtime, directory, stored, forkTargetOf(entryId, position, SM.getEntry(Unit, Tools.ToolDetails, V.Value, Session.stateOf(stored), entryId)))

# upstream fork: before a user message (its text returned for the editor) or
# at any entry (clone), into a new session; a persisted session branches into
# a new file, an in-memory one in place.
def fork(-S: Type, +runtime: AgentSessionRuntime<S>, entryId: String, position: ForkPosition) -> IO(Result<&2, &2, String, Maybe<&2, String>>):
  do IO<Result<&2, &2, String, Maybe<&2, String>>>:
    found : Maybe<&2, Snapshot> <- snapshot(S, runtime)
    forkFrom(S, runtime, entryId, position, found)

def disposed(-S: Type, release: C.Callback<S, Unit>, taken: Current<S>) -> IO(Unit):
  match taken:
    case Released{}: IO.pure(Unit, Unit{})
    case Active{services, live, _}:
      do IO<Unit>:
        Session.dispose(live)
        C.call(S, Unit, release, services)

# upstream dispose: the session and its services end with the host.
def dispose(-S: Type, runtime: AgentSessionRuntime<S>) -> IO(Unit):
  match runtime:
    case AgentSessionRuntime{current, _, +release, _, hook, retiring}:
      do IO<Unit>:
        last : Current<S> <- R.dispose(Current<S>, current)
        disposed(S, release, last)
        retired : Retiring<S> <- R.dispose(Retiring<S>, retiring)
        finishRetiring(S, release, retired)
        rebind : Maybe<&2, Rebind()> <- R.dispose(Maybe<&2, Rebind()>, hook)
        return Unit{}
