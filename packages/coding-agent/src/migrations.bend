import Base
import ./config.bend as Config
import ./core/keybindings.bend as Keybindings
import ../../ai/src/utils/json.bend as Render
import ../../ai/src/utils/schema-json.bend as SchemaJson
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/json.bend as Json
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/src/posix-path.bend as Path
import ../../runtime/src/utf8.bend as Utf8

# upstream migrations.ts: one-time startup migrations of the agent directory.
# The agent and project directories are explicit arguments instead of
# getAgentDir()/process state. Messages are console.log output: stdout, or
# stderr when a non-interactive mode has taken stdout over (upstream
# takeOverStdout), in chalk's colours when stdout is a terminal.

def MIGRATION_GUIDE_URL() -> String: "https://github.com/earendil-works/pi/blob/main/packages/coding-agent/CHANGELOG.md#extensions-migration"
def EXTENSIONS_DOC_URL() -> String: "https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md"

type MigrationResult is Data:
  MigrationResult{migratedAuthProviders: List<&2, String>, deprecationWarnings: List<&2, String>}

# chalk's green/yellow/dim, applied when stdout supports colour.
def painted(colour: Bool, +open: String, +close: String, +text: String) -> String:
  Bool.pick(String, colour, open ++ text ++ close, text)

type Console is Data:
  Stdout{}
  TakenOver{}

def emit(console: Console, text: String) -> IO(Unit):
  match console:
    case Stdout{}: IO.print(text)
    case TakenOver{}: IO.print_err(text)

def say(console: Console, +open: String, +close: String, text: String) -> IO(Unit):
  do IO<Unit>:
    colour : Bool <- IO.isTerminal(1)
    emit(console, painted(colour, open, close, text))

def green(console: Console, text: String) -> IO(Unit): say(console, "\u{1b}[32m", "\u{1b}[39m", text)
def yellow(console: Console, text: String) -> IO(Unit): say(console, "\u{1b}[33m", "\u{1b}[39m", text)

def exists(path: String) -> IO(Bool): FS.accessible(path, 0)

def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{feff}', rest}: rest
    case other: other

def parsedJson(result: Result<&2, &2, Json.ParseError, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Done{value}: Some{value}
    case Fail{_}: None{}

# readFileSync(path, "utf-8") parsed with JSON.parse; None where either throws.
def jsonOf(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Maybe<&2, V.Value>:
  match bytes:
    case Fail{_}: None{}
    case Done{content}: parsedJson(Json.parse(stripBom(Utf8.decodeBuffer(content))))

def readJson(path: String) -> IO(Maybe<&2, V.Value>):
  do IO<Maybe<&2, V.Value>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return jsonOf(bytes)

# JSON.stringify(value, null, 2)
def pretty(value: V.Value) -> String: Maybe.default(&2, String, Render.stringifyPretty(SchemaJson.toJson(value)), "{}")

def ignore(result: Result<&2, &2, FS.Error, Unit>) -> Unit: Unit{}

# Auth
# ----

type Collected is Data:
  Collected{entries: List<&2, R.Property<V.Value>>, providers: List<&2, String>}

def has(entries: List<&2, R.Property<V.Value>>, +name: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case R.Property{key, _} <> rest: String.eq(key, name) || has(rest, name)

# A spread credential's own "type" replaces the literal's value in its place.
def withoutType(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutType(rest)
      Bool.pick(List<&2, R.Property<V.Value>>, String.eq(key, "type"), tail, R.Property{key, value} <> tail)

def indexed(items: List<&2, V.Value>, +index: Nat) -> List<&2, R.Property<V.Value>>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: R.Property{Nat.show(index), item} <> indexed(rest, 1n+index)

def characters(text: String, +index: Nat) -> List<&2, R.Property<V.Value>>:
  match text:
    case SNil{}: Nil{}
    case SCon{char, rest}: R.Property{Nat.show(index), V.Text{SCon{char, SNil{}}}} <> characters(rest, 1n+index)

def field(fields: List<&2, R.Property<V.Value>>, +name: String) -> Maybe<&2, V.Value>:
  match fields:
    case Nil{}: None{}
    case R.Property{+key, value} <> rest: Bool.pick(Unit -> Maybe<&2, V.Value>, String.eq(key, name), _ => Some{value}, _ => field(rest, name))(Unit{})

# { type: "oauth", ...cred }: spreading a non-object copies nothing.
def oauthEntry(value: V.Value) -> V.Value:
  match value:
    case V.ObjectValue{R.Record{+fields}}: V.ObjectValue{R.Record{R.Property{"type", Maybe.default(&2, V.Value, field(fields, "type"), V.Text{"oauth"})} <> withoutType(fields)}}
    case V.ArrayValue{items}: V.ObjectValue{R.Record{R.Property{"type", V.Text{"oauth"}} <> indexed(items, 0n)}}
    case V.Text{text}: V.ObjectValue{R.Record{R.Property{"type", V.Text{"oauth"}} <> characters(text, 0n)}}
    case _: V.ObjectValue{R.Record{[R.Property{"type", V.Text{"oauth"}}]}}

def oauthEntries(fields: List<&2, R.Property<V.Value>>, collected: Collected) -> Collected:
  match fields collected:
    case Nil{} _: collected
    case R.Property{+provider, credential} <> rest Collected{entries, providers}: oauthEntries(rest, Collected{List.append(&2, R.Property<V.Value>, entries, [R.Property{provider, oauthEntry(credential)}]), List.append(&2, String, providers, [provider])})

def fromOAuth(value: Maybe<&2, V.Value>) -> Maybe<&2, Collected>:
  match value:
    case Some{V.ObjectValue{R.Record{fields}}}: Some{oauthEntries(fields, Collected{Nil{}, Nil{}})}
    case Some{V.ArrayValue{items}}: Some{oauthEntries(indexed(items, 0n), Collected{Nil{}, Nil{}})}
    case Some{V.Text{text}}: Some{oauthEntries(characters(text, 0n), Collected{Nil{}, Nil{}})}
    case Some{_}: Some{Collected{Nil{}, Nil{}}}
    case None{}: None{}

def renamedOAuth(+oauthPath: String, collected: Maybe<&2, Collected>) -> IO(Collected):
  match collected:
    case None{}: IO.pure(Collected, Collected{Nil{}, Nil{}})
    case Some{found}:
      do IO<Collected>:
        renamed : Result<&2, &2, FS.Error, Unit> <- FS.rename(oauthPath, oauthPath ++ ".migrated")
        return found

def migrateOAuth(+oauthPath: String, present: Bool) -> IO(Collected):
  match present:
    case False{}: IO.pure(Collected, Collected{Nil{}, Nil{}})
    case True{}:
      do IO<Collected>:
        value : Maybe<&2, V.Value> <- readJson(oauthPath)
        renamedOAuth(oauthPath, fromOAuth(value))

def withKey(+provider: String, key: String, collected: Collected) -> Collected:
  match collected:
    case Collected{+entries, +providers}: Bool.pick(Collected, has(entries, provider), Collected{entries, providers}, Collected{List.append(&2, R.Property<V.Value>, entries, [R.Property{provider, V.ObjectValue{R.Record{[R.Property{"type", V.Text{"api_key"}}, R.Property{"key", V.Text{key}}]}}}]), List.append(&2, String, providers, [provider])})

def apiKeyEntries(keys: List<&2, R.Property<V.Value>>, collected: Collected) -> Collected:
  match keys:
    case Nil{}: collected
    case R.Property{provider, V.Text{key}} <> rest: apiKeyEntries(rest, withKey(provider, key, collected))
    case _ <> rest: apiKeyEntries(rest, collected)

def settingsApiKeys(fields: List<&2, R.Property<V.Value>>) -> Maybe<&2, List<&2, R.Property<V.Value>>>:
  match fields:
    case Nil{}: None{}
    case R.Property{"apiKeys", V.ObjectValue{R.Record{keys}}} <> _: Some{keys}
    case R.Property{"apiKeys", V.ArrayValue{items}} <> _: Some{indexed(items, 0n)}
    case _ <> rest: settingsApiKeys(rest)

def withoutApiKeys(fields: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match fields:
    case Nil{}: Nil{}
    case R.Property{+key, value} <> rest:
      +tail = withoutApiKeys(rest)
      Bool.pick(List<&2, R.Property<V.Value>>, String.eq(key, "apiKeys"), tail, R.Property{key, value} <> tail)

def withApiKeys(+settingsPath: String, fields: List<&2, R.Property<V.Value>>, keys: Maybe<&2, List<&2, R.Property<V.Value>>>, collected: Collected) -> IO(Collected):
  match keys:
    case None{}: IO.pure(Collected, collected)
    case Some{entries}:
      do IO<Collected>:
        written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(settingsPath, pretty(V.ObjectValue{R.Record{withoutApiKeys(fields)}}))
        return apiKeyEntries(entries, collected)

# settings.apiKeys entries with string keys join the migrated credentials
# unless oauth.json already had the provider; apiKeys leaves settings.json.
def settingsKeys(+settingsPath: String, value: Maybe<&2, V.Value>, collected: Collected) -> IO(Collected):
  match value:
    case Some{V.ObjectValue{R.Record{+fields}}}: withApiKeys(settingsPath, fields, settingsApiKeys(fields), collected)
    case _: IO.pure(Collected, collected)

def migrateSettingsKeys(+settingsPath: String, present: Bool, collected: Collected) -> IO(Collected):
  match present:
    case False{}: IO.pure(Collected, collected)
    case True{}:
      do IO<Collected>:
        value : Maybe<&2, V.Value> <- readJson(settingsPath)
        settingsKeys(settingsPath, value, collected)

def writeAuth(+agentDir: String, +authPath: String, collected: Collected) -> IO(List<&2, String>):
  match collected:
    case Collected{Nil{}, providers}: IO.pure(List<&2, String>, providers)
    case Collected{entries, providers}:
      do IO<List<&2, String>>:
        made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(agentDir)
        written : Result<&2, &2, FS.Error, Unit> <- FS.writeFileMode(authPath, pretty(V.ObjectValue{R.Record{entries}}), 384)
        return providers

def collectAuth(+agentDir: String) -> IO(List<&2, String>):
  +oauthPath = Path.join(agentDir, "oauth.json")
  +settingsPath = Path.join(agentDir, "settings.json")
  do IO<List<&2, String>>:
    hasOAuth : Bool <- exists(oauthPath)
    oauth : Collected <- migrateOAuth(oauthPath, hasOAuth)
    hasSettings : Bool <- exists(settingsPath)
    collected : Collected <- migrateSettingsKeys(settingsPath, hasSettings, oauth)
    writeAuth(agentDir, Path.join(agentDir, "auth.json"), collected)

# upstream migrateAuthToAuthJson: oauth.json and settings.json apiKeys into a
# new auth.json (mode 0600); nothing when auth.json exists. Returns the
# migrated provider names.
def migrateAuthToAuthJson(+agentDir: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    present : Bool <- exists(Path.join(agentDir, "auth.json"))
    Bool.pick(Unit -> IO(List<&2, String>), present, _ => IO.pure(List<&2, String>, Nil{}), _ => collectAuth(agentDir))(Unit{})

# Sessions
# --------

def firstLine(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'\n', _}: ""
    case SCon{char, rest}: SCon{char, firstLine(rest)}

def truthyText(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SCon{c, cs}}}: Some{SCon{c, cs}}
    case _: None{}

def isSession(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{V.Text{"session"}}: True{}
    case _: False{}

# A session header: {"type":"session", "cwd": <non-empty string>}.
def headerCwd(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.ObjectValue{R.Record{+fields}}}: Bool.pick(Maybe<&2, String>, isSession(field(fields, "type")), truthyText(field(fields, "cwd")), None{})
    case _: None{}

def dashed(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'/', rest}: SCon{'-', dashed(rest)}
    case SCon{'\\', rest}: SCon{'-', dashed(rest)}
    case SCon{':', rest}: SCon{'-', dashed(rest)}
    case SCon{char, rest}: SCon{char, dashed(rest)}

def withoutLeadingSeparator(text: String) -> String:
  match text:
    case SCon{'/', rest}: rest
    case SCon{'\\', rest}: rest
    case other: other

# The session-manager directory name for a cwd: --<cwd with separators as ->--.
def safePath(cwd: String) -> String: "--" ++ dashed(withoutLeadingSeparator(cwd)) ++ "--"

def movedSession(+file: String, +correctDir: String, taken: Bool) -> IO(Unit):
  match taken:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        renamed : Result<&2, &2, FS.Error, Unit> <- FS.rename(file, Path.join(correctDir, Path.basename(file)))
        return Unit{}

def sessionTo(+agentDir: String, +file: String, cwd: Maybe<&2, String>) -> IO(Unit):
  match cwd:
    case None{}: IO.pure(Unit, Unit{})
    case Some{directory}:
      +correctDir = Path.join(Path.join(agentDir, "sessions"), safePath(directory))
      do IO<Unit>:
        made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(correctDir)
        taken : Bool <- exists(Path.join(correctDir, Path.basename(file)))
        movedSession(file, correctDir, taken)

def migrateSession(+agentDir: String, +file: String) -> IO(Unit):
  do IO<Unit>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(file)
    +line : String <- IO.pure(String, firstLine(Result.default(&2, &2, FS.Error, String, Result.map(&2, &2, FS.Error, List<&2, U32>, String, Utf8.decodeBuffer, bytes), "")))
    Bool.pick(Unit -> IO(Unit), String.is_empty(String.trim(line)), _ => IO.pure(Unit, Unit{}), _ => sessionTo(agentDir, file, headerCwd(parsedJson(Json.parse(line)))))(Unit{})

def jsonlFiles(entries: List<&2, FS.DirectoryEntry>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case FS.DirectoryEntry{+name, _} <> rest:
      +tail = jsonlFiles(rest)
      Bool.pick(List<&2, String>, String.ends_with(name, ".jsonl"), name <> tail, tail)

def migrateSessions(+agentDir: String, files: List<&2, String>) -> IO(Unit):
  match files:
    case Nil{}: IO.pure(Unit, Unit{})
    case file <> rest:
      do IO<Unit>:
        migrateSession(agentDir, Path.join(agentDir, file))
        migrateSessions(agentDir, rest)

# upstream migrateSessionsFromAgentRoot: *.jsonl sessions saved directly in
# the agent directory (v0.30.0 bug) move to sessions/<encoded cwd>/, unless
# the target exists.
def migrateSessionsFromAgentRoot(+agentDir: String) -> IO(Unit):
  do IO<Unit>:
    listing : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(agentDir)
    migrateSessions(agentDir, jsonlFiles(Result.default(&2, &2, FS.Error, List<&2, FS.DirectoryEntry>, listing, Nil{})))

# Resources
# ---------

def reportCommands(+console: Console, +label: String, result: Result<&2, &2, FS.Error, Unit>) -> IO(Bool):
  match result:
    case Done{_}:
      do IO<Bool>:
        green(console, "Migrated " ++ label ++ " commands/ → prompts/")
        return True{}
    case Fail{error}:
      do IO<Bool>:
        yellow(console, "Warning: Could not migrate " ++ label ++ " commands/ to prompts/: " ++ FS.errorMessage(error))
        return False{}

def renameCommands(+console: Console, +commandsDir: String, +promptsDir: String, +label: String, pending: Bool) -> IO(Bool):
  match pending:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        renamed : Result<&2, &2, FS.Error, Unit> <- FS.rename(commandsDir, promptsDir)
        reportCommands(console, label, renamed)

# upstream migrateCommandsToPrompts: commands/ becomes prompts/ when only the
# former exists (directory or symlink).
def migrateCommandsToPrompts(+console: Console, +baseDir: String, +label: String) -> IO(Bool):
  +commandsDir = Path.join(baseDir, "commands")
  +promptsDir = Path.join(baseDir, "prompts")
  do IO<Bool>:
    commands : Bool <- exists(commandsDir)
    prompts : Bool <- exists(promptsDir)
    renameCommands(console, commandsDir, promptsDir, label, commands && Bool.not(prompts))

def keybindingsWith(+configPath: String, migration: Keybindings.Migration) -> IO(Unit):
  match migration:
    case Keybindings.Migration{_, False{}}: IO.pure(Unit, Unit{})
    case Keybindings.Migration{config, True{}}:
      do IO<Unit>:
        written : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(configPath, pretty(V.ObjectValue{config}) ++ "\n")
        return Unit{}

def keybindingsValue(+configPath: String, environment: Keybindings.Environment, value: Maybe<&2, V.Value>) -> IO(Unit):
  match value:
    case Some{V.ObjectValue{raw}}: keybindingsWith(configPath, Keybindings.migrateKeybindingsConfig(environment, raw))
    case _: IO.pure(Unit, Unit{})

def migrateKeybindingsPresent(+configPath: String, environment: Keybindings.Environment, present: Bool) -> IO(Unit):
  match present:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        value : Maybe<&2, V.Value> <- readJson(configPath)
        keybindingsValue(configPath, environment, value)

# upstream migrateKeybindingsConfigFile: renamed action ids in
# keybindings.json; malformed files are left alone.
def migrateKeybindingsConfigFile(+agentDir: String, environment: Keybindings.Environment) -> IO(Unit):
  +configPath = Path.join(agentDir, "keybindings.json")
  do IO<Unit>:
    present : Bool <- exists(configPath)
    migrateKeybindingsPresent(configPath, environment, present)

def BINARIES() -> List<&2, String>: ["fd", "rg", "fd.exe", "rg.exe"]

def moveBinary(+oldPath: String, +newPath: String, targetExists: Bool) -> IO(Bool):
  match targetExists:
    case False{}:
      do IO<Bool>:
        renamed : Result<&2, &2, FS.Error, Unit> <- FS.rename(oldPath, newPath)
        return Result.is_done(&2, &2, FS.Error, Unit, renamed)
    case True{}:
      do IO<Bool>:
        removed : Result<&2, &2, FS.Error, Unit> <- FS.remove(oldPath, False{}, True{})
        return False{}

def moveIfPresent(+oldPath: String, +newPath: String, +binDir: String, present: Bool) -> IO(Bool):
  match present:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        made : Result<&2, &2, FS.Error, Unit> <- FS.mkdir(binDir)
        targetExists : Bool <- exists(newPath)
        moveBinary(oldPath, newPath, targetExists)

def moveBinaries(names: List<&2, String>, +toolsDir: String, +binDir: String, moved: Bool) -> IO(Bool):
  match names:
    case Nil{}: IO.pure(Bool, moved)
    case +name <> rest:
      do IO<Bool>:
        present : Bool <- exists(Path.join(toolsDir, name))
        this : Bool <- moveIfPresent(Path.join(toolsDir, name), Path.join(binDir, name), binDir, present)
        moveBinaries(rest, toolsDir, binDir, moved || this)

def reportedTools(+console: Console, moved: Bool) -> IO(Unit):
  match moved:
    case True{}: green(console, "Migrated managed binaries tools/ → bin/")
    case False{}: IO.pure(Unit, Unit{})

def migrateToolsPresent(+console: Console, +toolsDir: String, +binDir: String, present: Bool) -> IO(Unit):
  match present:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        moved : Bool <- moveBinaries(BINARIES(), toolsDir, binDir, False{})
        reportedTools(console, moved)

# upstream migrateToolsToBin: managed fd/rg binaries move from tools/ to bin/
# (an existing target wins and the old copy is deleted).
def migrateToolsToBin(+console: Console, +agentDir: String) -> IO(Unit):
  +toolsDir = Path.join(agentDir, "tools")
  do IO<Unit>:
    present : Bool <- exists(toolsDir)
    migrateToolsPresent(console, toolsDir, Path.join(agentDir, "bin"), present)

def customTool(+name: String) -> Bool:
  +lower = String.to_lower(name)
  Bool.not(String.eq(lower, "fd") || String.eq(lower, "rg") || String.eq(lower, "fd.exe") || String.eq(lower, "rg.exe") || String.starts_with(name, "."))

def anyCustom(entries: List<&2, FS.DirectoryEntry>) -> Bool:
  match entries:
    case Nil{}: False{}
    case FS.DirectoryEntry{+name, _} <> rest: customTool(name) || anyCustom(rest)

def toolsWarning(+label: String, present: Bool, listing: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>) -> List<&2, String>:
  match present listing:
    case True{} Done{entries}: Bool.pick(List<&2, String>, anyCustom(entries), [label ++ " tools/ directory contains custom tools. Custom tools have been merged into extensions."], Nil{})
    case _ _: Nil{}

# upstream checkDeprecatedExtensionDirs: warnings for hooks/ and for tools/
# holding anything but the managed binaries and hidden files.
def checkDeprecatedExtensionDirs(+baseDir: String, +label: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    hooks : Bool <- exists(Path.join(baseDir, "hooks"))
    tools : Bool <- exists(Path.join(baseDir, "tools"))
    listing : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory(Path.join(baseDir, "tools"))
    return List.append(&2, String, Bool.pick(List<&2, String>, hooks, [label ++ " hooks/ directory found. Hooks have been renamed to extensions."], Nil{}), toolsWarning(label, tools, listing))

# upstream migrateExtensionSystem: commands/ → prompts/ for the agent and
# project directories, then their deprecation warnings.
def migrateExtensionSystem(+console: Console, +agentDir: String, +cwd: String) -> IO(List<&2, String>):
  +projectDir = Path.join(cwd, Config.configDirName())
  do IO<List<&2, String>>:
    global : Bool <- migrateCommandsToPrompts(console, agentDir, "Global")
    project : Bool <- migrateCommandsToPrompts(console, projectDir, "Project")
    globalWarnings : List<&2, String> <- checkDeprecatedExtensionDirs(agentDir, "Global")
    projectWarnings : List<&2, String> <- checkDeprecatedExtensionDirs(projectDir, "Project")
    return List.append(&2, String, globalWarnings, projectWarnings)

def printWarnings(+console: Console, warnings: List<&2, String>) -> IO(Unit):
  match warnings:
    case Nil{}: IO.pure(Unit, Unit{})
    case warning <> rest:
      do IO<Unit>:
        yellow(console, "Warning: " ++ warning)
        printWarnings(console, rest)

# upstream showDeprecationWarnings prints the warnings and the migration
# guide, then waits for a key; the key wait is not ported (the startup path
# has no raw-mode stdin reader outside the TUI).
def showDeprecationWarnings(+console: Console, warnings: List<&2, String>) -> IO(Unit):
  match warnings:
    case Nil{}: IO.pure(Unit, Unit{})
    case +first <> +rest:
      do IO<Unit>:
        printWarnings(console, first <> rest)
        yellow(console, "\nMove your extensions to the extensions/ directory.")
        yellow(console, "Migration guide: " ++ MIGRATION_GUIDE_URL())
        yellow(console, "Documentation: " ++ EXTENSIONS_DOC_URL())

# upstream runMigrations, once at startup.
def runMigrations(+console: Console, +agentDir: String, +cwd: String, environment: Keybindings.Environment) -> IO(MigrationResult):
  do IO<MigrationResult>:
    migratedAuthProviders : List<&2, String> <- migrateAuthToAuthJson(agentDir)
    migrateSessionsFromAgentRoot(agentDir)
    migrateToolsToBin(console, agentDir)
    migrateKeybindingsConfigFile(agentDir, environment)
    deprecationWarnings : List<&2, String> <- migrateExtensionSystem(console, agentDir, cwd)
    return MigrationResult{migratedAuthProviders, deprecationWarnings}
