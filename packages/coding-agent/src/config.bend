import Base
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/posix-path.bend as Path

# Package identity. pi's package.json `piConfig` renames are build-time
# configuration; this port ships the default identity.
def appName() -> String: "pi"
def appTitle() -> String: "π"
def configDirName() -> String: ".pi"
def version() -> String: "0.85.1"

# e.g. PI_CODING_AGENT_DIR
def envAgentDir() -> String: "PI_CODING_AGENT_DIR"
def envSessionDir() -> String: "PI_CODING_AGENT_SESSION_DIR"

def Located() -> Data: Result<&2, &2, FS.Error, String>

# An explicit `~` is expanded against the home directory; other relative
# overrides resolve against the working directory, as Node's resolve() does.
def resolved(cwd: String, +path: String) -> String:
  Maybe.default(&2, String, Path.resolve(cwd, path), path)

def tilde(home: String, cwd: String, rest: String) -> String:
  match rest:
    case SNil{}: home
    case SCon{'/', more}: Path.join(home, more)
    case other: resolved(cwd, SCon{'~', other})

def expanded(home: String, cwd: String, path: String) -> String:
  match path:
    case SCon{'~', rest}: tilde(home, cwd, rest)
    case value: resolved(cwd, value)

def defaultAgentDir(home: String) -> String: Path.join(Path.join(home, configDirName()), "agent")

def overridden(value: String, +home: String, cwd: String) -> String:
  match value:
    case SNil{}: defaultAgentDir(home)
    case text: expanded(home, cwd, text)

def chosen(override: Result<&1, &1, U32 & String, String>, home: Located(), cwd: Located()) -> Located():
  match override home cwd:
    case _ Fail{error} _: Fail{error}
    case _ _ Fail{error}: Fail{error}
    case Done{value} Done{home} Done{cwd}: Done{overridden(String.trim(value), home, cwd)}
    case Fail{_} Done{home} _: Done{defaultAgentDir(home)}

# The agent config directory (~/.pi/agent), overridable through PI_CODING_AGENT_DIR.
def getAgentDir() -> IO(Located()):
  do IO<Located()>:
    override : Result<&1, &1, U32 & String, String> <- IO.get_env(envAgentDir())
    home : Located() <- FS.homedir()
    cwd : Located() <- FS.cwd()
    return chosen(override, home, cwd)

def inAgentDir(name: String) -> IO(Located()):
  do IO<Located()>:
    directory : Located() <- getAgentDir()
    return Result.map(&2, &2, FS.Error, String, String, value => Path.join(value, name), directory)

def getAuthPath() -> IO(Located()): inAgentDir("auth.json")
def getModelsPath() -> IO(Located()): inAgentDir("models.json")
def getSettingsPath() -> IO(Located()): inAgentDir("settings.json")
def getSessionsDir() -> IO(Located()): inAgentDir("sessions")
def getCustomThemesDir() -> IO(Located()): inAgentDir("themes")
def getToolsDir() -> IO(Located()): inAgentDir("tools")
