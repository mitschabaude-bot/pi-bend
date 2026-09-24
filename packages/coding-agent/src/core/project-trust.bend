import Base
import ../../../runtime/src/callback.bend as Callback
import ./settings-manager.bend as Settings
import ./trust-manager.bend as Trust

# upstream core/project-trust.ts resolveProjectTrusted. The port has no
# extension runtime, so the project_trust extension event does not apply.
# `select` is the startup selector (upstream ProjectTrustContext.ui.select);
# without one (print, JSON and RPC modes) an undecided project is untrusted.
type SelectRequest is Data: SelectRequest{title: String,options: List<&2,String>}
def Select() -> Data: Callback.Callback<SelectRequest,Maybe<&2,String>>
type ResolveProjectTrustedOptions is Data:
  ResolveProjectTrustedOptions{cwd: String,home: Maybe<&2,String>,trustStore: Trust.ProjectTrustStore,trustOverride: Maybe<&2,Bool>,defaultProjectTrust: Settings.DefaultProjectTrust}

def APP_NAME() -> String: "pi"
def formatProjectTrustPrompt(cwd: String) -> String:
  "Trust project folder?\n" ++ cwd ++ "\n\nThis allows " ++ APP_NAME() ++ " to load " ++ Trust.CONFIG_DIR_NAME() ++ " settings and resources, install missing project packages, and execute project extensions."

def optionLabels(options: List<&2,Trust.ProjectTrustOption>) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case Trust.ProjectTrustOption{label,_,_,_} <> rest: label <> optionLabels(rest)
def optionNamed(options: List<&2,Trust.ProjectTrustOption>,+label: String) -> Maybe<&2,Trust.ProjectTrustOption>:
  match options:
    case Nil{}: None{}
    case Trust.ProjectTrustOption{+name,trusted,updates,saved} <> rest:
      Bool.pick(Unit -> Maybe<&2,Trust.ProjectTrustOption>,String.eq(name,label),_ => Some{Trust.ProjectTrustOption{name,trusted,updates,saved}},_ => optionNamed(rest,label))(Unit{})
def chosenOption(options: List<&2,Trust.ProjectTrustOption>,selected: Maybe<&2,String>) -> Maybe<&2,Trust.ProjectTrustOption>:
  match selected:
    case None{}: None{}
    case Some{label}: optionNamed(options,label)

def writtenTrust(written: Result<&2,&2,Trust.Error,Unit>,trusted: Bool) -> Result<&2,&2,String,Bool>:
  match written:
    case Done{_}: Done{trusted}
    case Fail{Trust.Error{message}}: Fail{message}

# A chosen option saves its updates (none for "this session only").
def saved(store: Trust.ProjectTrustStore,option: Maybe<&2,Trust.ProjectTrustOption>) -> IO(Result<&2,&2,String,Bool>):
  match option:
    case None{}: IO.pure(Result<&2,&2,String,Bool>,Done{False{}})
    case Some{Trust.ProjectTrustOption{_,trusted,Nil{},_}}: IO.pure(Result<&2,&2,String,Bool>,Done{trusted})
    case Some{Trust.ProjectTrustOption{_,trusted,updates,_}}:
      do IO<Result<&2,&2,String,Bool>>:
        written : Result<&2,&2,Trust.Error,Unit> <- Trust.setMany(store,updates)
        return writtenTrust(written,trusted)
def prompted(+store: Trust.ProjectTrustStore,+cwd: String,select: Maybe<&2,Select()>) -> IO(Result<&2,&2,String,Bool>):
  match select:
    case None{}: IO.pure(Result<&2,&2,String,Bool>,Done{False{}})
    case Some{choose}:
      do IO<Result<&2,&2,String,Bool>>:
        +options : List<&2,Trust.ProjectTrustOption> <- Trust.getProjectTrustOptions(cwd,True{})
        selected : Maybe<&2,String> <- Callback.call(SelectRequest,Maybe<&2,String>,choose,SelectRequest{formatProjectTrustPrompt(cwd),optionLabels(options)})
        saved(store,chosenOption(options,selected))

def byDefault(defaultTrust: Settings.DefaultProjectTrust,store: Trust.ProjectTrustStore,cwd: String,select: Maybe<&2,Select()>) -> IO(Result<&2,&2,String,Bool>):
  match defaultTrust:
    case Settings.Always{}: IO.pure(Result<&2,&2,String,Bool>,Done{True{}})
    case Settings.Never{}: IO.pure(Result<&2,&2,String,Bool>,Done{False{}})
    case Settings.Ask{}: prompted(store,cwd,select)
def decided(decision: Result<&2,&2,Trust.Error,Maybe<&2,Bool>>,defaultTrust: Settings.DefaultProjectTrust,store: Trust.ProjectTrustStore,cwd: String,select: Maybe<&2,Select()>) -> IO(Result<&2,&2,String,Bool>):
  match decision:
    case Fail{Trust.Error{message}}: IO.pure(Result<&2,&2,String,Bool>,Fail{message})
    case Done{Some{trusted}}: IO.pure(Result<&2,&2,String,Bool>,Done{trusted})
    case Done{None{}}: byDefault(defaultTrust,store,cwd,select)
def withResources(requiring: Bool,+store: Trust.ProjectTrustStore,+cwd: String,defaultTrust: Settings.DefaultProjectTrust,select: Maybe<&2,Select()>) -> IO(Result<&2,&2,String,Bool>):
  match requiring:
    case False{}: IO.pure(Result<&2,&2,String,Bool>,Done{True{}})
    case True{}:
      do IO<Result<&2,&2,String,Bool>>:
        decision : Result<&2,&2,Trust.Error,Maybe<&2,Bool>> <- Trust.get(store,cwd)
        decided(decision,defaultTrust,store,cwd,select)
def resolveProjectTrusted(options: ResolveProjectTrustedOptions,select: Maybe<&2,Select()>) -> IO(Result<&2,&2,String,Bool>):
  match options:
    case ResolveProjectTrustedOptions{_,_,_,Some{trusted},_}: IO.pure(Result<&2,&2,String,Bool>,Done{trusted})
    case ResolveProjectTrustedOptions{+cwd,home,store,None{},defaultTrust}:
      do IO<Result<&2,&2,String,Bool>>:
        requiring : Bool <- Trust.hasTrustRequiringProjectResources(cwd,home)
        withResources(requiring,store,cwd,defaultTrust,select)
