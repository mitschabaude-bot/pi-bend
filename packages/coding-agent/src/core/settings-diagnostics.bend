import Base
import ../../../runtime/src/json.bend as Decode
import ./settings-manager.bend as Settings

# upstream core/settings-diagnostics.ts: settings load errors as runtime
# diagnostics, and their de-duplication.

# upstream AgentSessionRuntimeDiagnostic (core/agent-session-services.ts);
# its `type` field is `kind` here.
type DiagnosticType is Data:
  Info{}
  Warning{}
  Error{}

type AgentSessionRuntimeDiagnostic is Data:
  AgentSessionRuntimeDiagnostic{kind: DiagnosticType, message: String}

def typeName(kind: DiagnosticType) -> String:
  match kind:
    case Info{}: "info"
    case Warning{}: "warning"
    case Error{}: "error"

def segmentText(segment: Decode.Segment) -> String:
  match segment:
    case Decode.Field{name}: "." ++ name
    case Decode.Index{index}: "[" ++ Nat.show(index) ++ "]"

def pathText(path: List<&2, Decode.Segment>) -> String:
  match path:
    case Nil{}: ""
    case segment <> rest: segmentText(segment) ++ pathText(rest)

def decodeText(error: Decode.Error) -> String:
  match error:
    case Decode.MissingField{path}: "missing " ++ pathText(path)
    case Decode.WrongType{path, expected}: "expected " ++ expected ++ " at " ++ pathText(path)
    case Decode.InvalidValue{path, expected}: "expected " ++ expected ++ " at " ++ pathText(path)

# The message of a settings error (upstream error.message).
def settingsErrorText(error: Settings.Error) -> String:
  match error:
    case Settings.InvalidJson{_}: "invalid JSON"
    case Settings.InvalidSetting{cause}: decodeText(cause)
    case Settings.DuplicateSetting{path}: "duplicate setting " ++ path
    case Settings.UntrustedProject{}: "project settings are not trusted"
    case Settings.StorageFailure{message}: message
    case Settings.FileFailure{_}: "could not read the settings file"
    case Settings.InvalidEncoding{_}: "the settings file is not valid UTF-8"
    case Settings.LockFailure{_}: "could not lock the settings file"
    case Settings.CleanupFailure{_, _}: "could not release the settings lock"

def scopeText(scope: Settings.SettingsScope) -> String:
  match scope:
    case Settings.Global{}: "global"
    case Settings.Project{}: "project"

def settingsDiagnostic(error: Settings.SettingsError) -> AgentSessionRuntimeDiagnostic:
  match error:
    case Settings.SettingsError{_, Some{path}, cause}: AgentSessionRuntimeDiagnostic{Warning{}, "Invalid settings file " ++ path ++ ": " ++ settingsErrorText(cause)}
    case Settings.SettingsError{scope, None{}, cause}: AgentSessionRuntimeDiagnostic{Warning{}, "Invalid " ++ scopeText(scope) ++ " settings: " ++ settingsErrorText(cause)}

def diagnosticsOf(errors: List<&2, Settings.SettingsError>) -> List<&2, AgentSessionRuntimeDiagnostic>:
  match errors:
    case Nil{}: Nil{}
    case error <> rest: settingsDiagnostic(error) <> diagnosticsOf(rest)

# upstream collectSettingsDiagnostics(settingsManager): drains the manager's
# load errors, each a warning; the drained manager is returned with them.
def collected(pair: Settings.SettingsManager & List<&2, Settings.SettingsError>) -> Settings.SettingsManager & List<&2, AgentSessionRuntimeDiagnostic>:
  match pair:
    case (drained, errors): (drained, diagnosticsOf(errors))

def collectSettingsDiagnostics(manager: Settings.SettingsManager) -> Settings.SettingsManager & List<&2, AgentSessionRuntimeDiagnostic>:
  collected(Settings.drainErrors(manager))

def sameDiagnostic(left: AgentSessionRuntimeDiagnostic, right: AgentSessionRuntimeDiagnostic) -> Bool:
  match left right:
    case AgentSessionRuntimeDiagnostic{leftType, leftMessage} AgentSessionRuntimeDiagnostic{rightType, rightMessage}: String.eq(typeName(leftType), typeName(rightType)) && String.eq(leftMessage, rightMessage)

def seen(earlier: List<&2, AgentSessionRuntimeDiagnostic>, +diagnostic: AgentSessionRuntimeDiagnostic) -> Bool:
  match earlier:
    case Nil{}: False{}
    case previous <> rest: sameDiagnostic(previous, diagnostic) || seen(rest, diagnostic)

def distinct(diagnostics: List<&2, AgentSessionRuntimeDiagnostic>, +kept: List<&2, AgentSessionRuntimeDiagnostic>) -> List<&2, AgentSessionRuntimeDiagnostic>:
  match diagnostics:
    case Nil{}: List.reverse(&2, AgentSessionRuntimeDiagnostic, kept)
    case +diagnostic <> rest: distinct(rest, Bool.pick(List<&2, AgentSessionRuntimeDiagnostic>, seen(kept, diagnostic), kept, diagnostic <> kept))

# upstream deduplicateDiagnostics: the first occurrence of each type and
# message, in order. Startup and runtime settings managers can report the
# same file error.
def deduplicateDiagnostics(diagnostics: List<&2, AgentSessionRuntimeDiagnostic>) -> List<&2, AgentSessionRuntimeDiagnostic>:
  distinct(diagnostics, Nil{})
