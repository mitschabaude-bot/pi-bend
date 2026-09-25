import Base
import ../packages/ai/src/utils/uuid.bend as Uuid
import ../packages/coding-agent/src/core/settings-manager.bend as S
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/utf8.bend as Utf8

# upstream test/settings-manager.test.ts, describe("cacheWarming"): real
# settings files under a fresh temporary directory, read back through
# SettingsManager.create exactly as upstream does.

def check(ok: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), ok, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def isMode(mode: S.CacheWarmingMode, +expected: String) -> Bool: String.eq(S.cacheWarmingModeName(mode), expected)

def managerOf(pair: S.FileSettingsStorage & S.SettingsManager) -> S.SettingsManager:
  match pair:
    case (_, manager): manager

def modeIn(+projectDir: String, +agentDir: String) -> IO(S.CacheWarmingMode):
  do IO<S.CacheWarmingMode>:
    pair : S.FileSettingsStorage & S.SettingsManager <- S.create(projectDir, agentDir, S.options())
    return S.getCacheWarmingMode(managerOf(pair))

def written(+path: String, content: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, content)
    return Unit{}

def prepared(+root: String) -> IO(Unit):
  do IO<Unit>:
    project : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(root ++ "/project/.pi")
    agent : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(root ++ "/agent")
    return Unit{}

def defaults(+root: String) -> IO(Unit):
  do IO<Unit>:
    prepared(root)
    +projectDir : String = root ++ "/project"
    +agentDir : String = root ++ "/agent"
    initial : S.CacheWarmingMode <- modeIn(projectDir, agentDir)
    written(projectDir ++ "/.pi/settings.json", "{\"cacheWarming\":\"idle\"}")
    projectOnly : S.CacheWarmingMode <- modeIn(projectDir, agentDir)
    written(agentDir ++ "/settings.json", "{\"cacheWarming\":\"idle\"}")
    global : S.CacheWarmingMode <- modeIn(projectDir, agentDir)
    written(agentDir ++ "/settings.json", "{\"cacheWarming\":\"bogus\"}")
    bogus : S.CacheWarmingMode <- modeIn(projectDir, agentDir)
    check(isMode(initial, "streaming") && isMode(projectOnly, "streaming") && isMode(global, "idle") && isMode(bogus, "streaming"), "defaults to streaming and ignores project settings")

def expectedFile() -> V.Value: V.ObjectValue{R.set(V.Value, R.new(V.Value), "cacheWarming", V.Text{"off"})}

def fileValue(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, V.Value>:
  match bytes:
    case Done{content}: Result.default(&2, &2, J.ParseError, Maybe<&2, V.Value>, Result.map(&2, &2, J.ParseError, V.Value, Maybe<&2, V.Value>, value => Some{value}, J.parse(Utf8.decodeBytes(content))), None{})
    case Fail{_}: None{}

def sameFile(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{parsed}: V.equal(parsed, expectedFile())
    case None{}: False{}

def persisted(+projectDir: String, +agentDir: String, updated: S.Outcome(S.SettingsManager)) -> IO(Unit):
  match updated:
    case Fail{_}: check(False{}, "persists the mode globally")
    case Done{manager}:
      do IO<Unit>:
        flushed : S.SettingsManager <- S.flushFiles(manager)
        reloaded : S.CacheWarmingMode <- modeIn(projectDir, agentDir)
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(agentDir ++ "/settings.json")
        check(isMode(reloaded, "off") && sameFile(fileValue(bytes)), "persists the mode globally")

def persists(+root: String) -> IO(Unit):
  do IO<Unit>:
    prepared(root)
    +projectDir : String = root ++ "/project"
    +agentDir : String = root ++ "/agent"
    pair : S.FileSettingsStorage & S.SettingsManager <- S.create(projectDir, agentDir, S.options())
    persisted(projectDir, agentDir, S.setCacheWarmingMode(S.CacheWarmingOff{}, managerOf(pair)))

def cleaned(+root: String) -> IO(Unit):
  do IO<Unit>:
    removed : Result<&2, &2, FS.Error, Unit> <- FS.remove(root, True{}, True{})
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    generated : Result<&2, &2, Uuid.Error, String> <- Uuid.randomUUID()
    +root : String = "/tmp/pi-bend-cache-warming-" ++ Result.default(&2, &2, Uuid.Error, String, generated, "settings")
    defaults(root ++ "/defaults")
    persists(root ++ "/persists")
    cleaned(root)
