import Base
import ../packages/coding-agent/src/core/crash-log.bend as Crash
import ../packages/coding-agent/src/core/skills.bend as Skills
import ../packages/coding-agent/src/config.bend as Config
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/f64.bend as F
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/src/utf8.bend as Utf8

# upstream packages/coding-agent/test/crash-log.test.ts ("extension crash
# attribution", findExtensionStackMatches), plus native cases for the log
# file itself (recordCrash, takeUnnotifiedCrash, clearCrashLog), which
# upstream exercises only through the excluded /bug flow. Arg: a scratch
# directory.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def packageExtension(source: String, +baseDir: String, entry: String) -> Crash.ExtensionStackMetadata:
  +resolvedPath = String.concat([Strings.replaceAll(baseDir, "\\", "/"), "/", entry])
  Crash.ExtensionStackMetadata{resolvedPath, resolvedPath, Skills.SourceInfo{resolvedPath, source, Skills.User{}, Skills.Package{}, Some{baseDir}}}

def same(values: List<&2, String>, expected: List<&2, String>) -> Bool:
  match values expected:
    case Nil{} Nil{}: True{}
    case a <> left b <> right: String.eq(a, b) && same(left, right)
    case _ _: False{}

def memoryStack() -> String: "TypeError: Cannot read properties of undefined (reading 'runtime')\n    at streamSimple (file:///home/fedora/.local/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/chunks/chunk-CMRUVXTE.js:1093:16944)\n    at /home/fedora/.pi/agent/npm/node_modules/pi-observational-memory/src/agents/worker-stream.ts:43:45"

def windowsRoot() -> String: "C:\\Users\\reporter\\.pi\\agent\\npm\\node_modules\\@scope\\memory"

def windowsStack() -> String: "Error: broken\n    at run (c:\\users\\reporter\\.pi\\agent\\npm\\node_modules\\@scope\\memory\\src\\worker.ts:4:2)"

def localPath() -> String: "/Users/reporter/.pi/agent/extensions/local memory/index.ts"

def packageRoots() -> IO(Unit):
  +memory = packageExtension("npm:pi-observational-memory", "/home/fedora/.pi/agent/npm/node_modules/pi-observational-memory", "extensions/index.ts")
  +unrelated = packageExtension("npm:unrelated", "/home/fedora/.pi/agent/npm/node_modules/unrelated", "extensions/index.ts")
  check(same(Crash.findExtensionStackMatches(Some{memoryStack()}, [memory, unrelated]), ["npm:pi-observational-memory"]), "extension crash attribution matches stack frames beneath loaded package roots")

def windowsPaths() -> IO(Unit):
  +first = packageExtension("npm:@scope/memory", windowsRoot(), "extensions/first.ts")
  +second = packageExtension("npm:@scope/memory", windowsRoot(), "extensions/second.ts")
  check(same(Crash.findExtensionStackMatches(Some{windowsStack()}, [first, second]), ["npm:@scope/memory"]), "extension crash attribution normalizes Windows paths and deduplicates package extensions")

def plugin(+name: String) -> Crash.ExtensionStackMetadata:
  +path = String.concat(["/plugins/", name, ".ts"])
  Crash.ExtensionStackMetadata{path, path, Skills.SourceInfo{path, path, Skills.User{}, Skills.Package{}, Some{"/plugins"}}}

def siblings() -> IO(Unit):
  check(same(Crash.findExtensionStackMatches(Some{"Error: broken\n    at run (file:///plugins/b.ts:4:2)"}, [plugin("a"), plugin("b")]), ["/plugins/b.ts"]), "extension crash attribution does not attribute sibling single-file packages")

def messagePaths() -> IO(Unit):
  +extension = packageExtension("npm:memory", "/tmp/node_modules/memory", "extensions/index.ts")
  check(same(Crash.findExtensionStackMatches(Some{"Error: Failed to read /tmp/node_modules/memory/extensions/index.ts\n    at run (file:///opt/pi/dist/core.js:4:2)"}, [extension]), Nil{}), "extension crash attribution ignores extension paths in the error message")

def localExtension() -> Crash.ExtensionStackMetadata: Crash.ExtensionStackMetadata{localPath(), localPath(), Skills.SourceInfo{localPath(), "local", Skills.User{}, Skills.TopLevel{}, Some{"/Users/reporter/.pi/agent/extensions"}}}

def decodedFrames() -> IO(Unit):
  check(same(Crash.findExtensionStackMatches(Some{"Error: progress 100%\n    at run (file:///Users/reporter/.pi/agent/extensions/local%20memory/worker.ts:4:2)"}, [localExtension()]), [localPath()]), "extension crash attribution decodes frame paths independently from malformed error text")

# Native: the log file
# --------------------

def messages(records: List<&2, Crash.CrashRecord>) -> String:
  match records:
    case Nil{}: ""
    case Crash.CrashRecord{_, _, _, message, _, _, _, _} <> Nil{}: message
    case Crash.CrashRecord{_, _, _, message, _, _, _, _} <> rest: message ++ "," ++ messages(rest)

def notifiedAll(records: List<&2, Crash.CrashRecord>) -> Bool:
  match records:
    case Nil{}: True{}
    case Crash.CrashRecord{_, _, _, _, _, _, _, notified} <> rest: notified && notifiedAll(rest)

def crash(+message: String) -> Crash.Crash: Crash.Crash{Crash.FatalError{}, message, None{}, Some{"/tmp/session.jsonl"}, "/work"}

def recordAll(+path: String, names: List<&2, String>) -> IO(Unit):
  match names:
    case Nil{}: IO.pure(Unit, Unit{})
    case name <> rest:
      do IO<Unit>:
        recorded : Maybe<&2, Crash.CrashRecord> <- Crash.recordCrash(crash(name), path)
        recordAll(path, rest)

def textOf(result: Result<&2, &2, FS.Error, List<&2, U32>>) -> String:
  match result:
    case Done{bytes}: Utf8.decodeBuffer(bytes)
    case Fail{_}: ""

def keepsFive(+directory: String) -> IO(Unit):
  +path = String.concat([directory, "/nested/crashes.json"])
  do IO<Unit>:
    recordAll(path, ["one", "two", "three", "four", "five", "six"])
    +records : List<&2, Crash.CrashRecord> <- Crash.readCrashLog(path)
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    +text : String <- IO.pure(String, textOf(bytes))
    check(String.eq(messages(records), "two,three,four,five,six") && String.starts_with(text, "[\n  {\n    \"timestamp\": \"") && String.contains(text, "\"version\": \"" ++ Config.version() ++ "\",\n    \"kind\": \"fatal_error\",\n    \"message\": \"six\",\n    \"stack\": null,\n    \"sessionFile\": \"/tmp/session.jsonl\",\n    \"cwd\": \"/work\"\n  }\n]\n"), "native: recordCrash keeps the last five crashes in the log, creating its directory")

def messageOf(record: Maybe<&2, Crash.CrashRecord>) -> String:
  match record:
    case Some{Crash.CrashRecord{_, _, _, message, _, _, _, _}}: message
    case None{}: "<none>"

# A week-old crash is not announced; the newest recent unannounced one is,
# once, and every record is then marked announced.
def announcesOnce(+directory: String) -> IO(Unit):
  +path = String.concat([directory, "/announce.json"])
  do IO<Unit>:
    written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, "[{\"timestamp\":\"2026-01-01T00:00:00.000Z\",\"message\":\"old\"},{\"timestamp\":\"2026-09-20T00:00:00.000Z\",\"message\":\"recent\",\"notified\":\"\"},{\"message\":\"no timestamp\"},{\"timestamp\":\"2026-09-21T00:00:00.000Z\",\"message\":\"announced\",\"notified\":true},7]")
    +now : F64 <- IO.pure(F64, Result.default(&2, &2, Date.ParseError, F64, Date.parseIso("2026-09-26T00:00:00.000Z"), F.fromU32(0)))
    first : Maybe<&2, Crash.CrashRecord> <- Crash.takeUnnotifiedCrash(path, now)
    second : Maybe<&2, Crash.CrashRecord> <- Crash.takeUnnotifiedCrash(path, now)
    +records : List<&2, Crash.CrashRecord> <- Crash.readCrashLog(path)
    check(String.eq(messageOf(first), "recent") && String.eq(messageOf(second), "<none>") && String.eq(messages(records), "old,recent,announced") && notifiedAll(records), "native: takeUnnotifiedCrash announces the newest crash of the last week once")

def clears(+directory: String) -> IO(Unit):
  +path = String.concat([directory, "/announce.json"])
  do IO<Unit>:
    Crash.clearCrashLog(path)
    Crash.clearCrashLog(path)
    records : List<&2, Crash.CrashRecord> <- Crash.readCrashLog(path)
    check(List.is_empty(&2, Crash.CrashRecord, records), "native: clearCrashLog removes the log and ignores a missing one")

def started(args: List<String>) -> IO(Unit):
  match args:
    case +directory <> Nil{}:
      do IO<Unit>:
        packageRoots()
        windowsPaths()
        siblings()
        messagePaths()
        decodedFrames()
        keepsFive(directory)
        announcesOnce(directory)
        clears(directory)
    case _: IO.die(Unit, 2, "usage: crash-log <scratch directory>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    started(args)
