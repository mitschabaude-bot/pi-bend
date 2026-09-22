import Base
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/utils/json.bend as Render
import ../packages/ai/src/utils/schema-json.bend as SchemaJson
import ../packages/agent/src/types.bend as Agent
import ../packages/coding-agent/src/core/messages.bend as Messages
import ../packages/coding-agent/src/core/session-manager.bend as S
import ../packages/coding-agent/src/core/session-json.bend as SJ
import ../packages/coding-agent/src/core/session-persistence.bend as P
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8
import ../packages/runtime/src/posix-path.bend as Path
import ../packages/runtime/src/date.bend as Date
import ../packages/runtime/src/record.bend as R
import ../packages/runtime/src/schema-value.bend as V
import ../packages/runtime/src/json.bend as Decode
import ../packages/runtime/src/f64.bend as F

# Answers the JSON operations of tests/session_file_check.py through the
# native session persistence, one JSON result line per operation, as
# tests/session_file_reference.ts does through the pinned SessionManager.

def unitValue(value: Unit) -> V.Value: V.Null{}
def readUnit(value: V.Value) -> Result<&2, &2, Decode.Error, Unit>: Done{Unit{}}
def same(value: V.Value) -> V.Value: value
def readSame(value: V.Value) -> Result<&2, &2, Decode.Error, V.Value>: Done{value}

def Session() -> Data: P.Session<Unit, Unit, V.Value>
def State() -> Data: S.SessionManager<Unit, Unit, V.Value>
def Entry() -> Data: S.SessionEntry<Unit, Unit, V.Value>
def Outcome() -> Data: P.Outcome(Session())

type World is Data:
  World{session: Maybe<&2, Session()>, agentDir: String, cwd: String}

# Fields
# ------

def textOf(found: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match found:
    case Some{V.Text{text}}: Some{text}
    case _: None{}

def opt(fields: R.Record<V.Value>, key: String) -> Maybe<&2, String>: textOf(R.get(V.Value, fields, key))
def str(fields: R.Record<V.Value>, key: String) -> String: Maybe.default(&2, String, opt(fields, key), "")

def numberOf(found: Maybe<&2, V.Value>) -> Nat:
  match found:
    case Some{V.Number{scalar}}: Result.default(&2, &2, F.Error, Nat, F.convert(scalar), 0n)
    case _: 0n

def num(fields: R.Record<V.Value>, key: String) -> Nat: numberOf(R.get(V.Value, fields, key))

def valuesOf(found: Maybe<&2, V.Value>) -> Maybe<&2, List<&2, V.Value>>:
  match found:
    case Some{V.ArrayValue{values}}: Some{values}
    case _: None{}

def flagOf(found: Maybe<&2, V.Value>) -> Bool:
  match found:
    case Some{V.Boolean{flag}}: flag
    case _: False{}

def value(fields: R.Record<V.Value>, key: String) -> Maybe<&2, V.Value>: R.get(V.Value, fields, key)

# Rendering
# ---------

def nullable(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{text}: V.Text{text}

def textValues(values: List<&2, String>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case text <> rest: V.Text{text} <> textValues(rest)

def texts(values: List<&2, String>) -> V.Value: V.ArrayValue{textValues(values)}

def line(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def errorLine(message: String) -> V.Value:
  SJ.object(SJ.field("error", V.Text{message}, Nil{}))

def shape(+session: Session()) -> V.Value:
  +state = P.stateOf(Unit, Unit, V.Value, session)
  SJ.object(SJ.field("sessionId", V.Text{S.getSessionId(Unit, Unit, V.Value, state)}, SJ.field("cwd", V.Text{P.getCwd(Unit, Unit, V.Value, session)}, SJ.field("sessionFile", nullable(P.getSessionFile(Unit, Unit, V.Value, session)), SJ.field("sessionDir", V.Text{P.getSessionDir(Unit, Unit, V.Value, session)}, SJ.field("persisted", V.Boolean{P.isPersisted(Unit, Unit, V.Value, session)}, SJ.field("entries", SJ.natural(List.length(&2, Entry(), S.getEntries(Unit, Unit, V.Value, state))), SJ.field("header", SJ.header(S.getHeader(Unit, Unit, V.Value, state)), Nil{}))))))))

def withReturned(+session: Session(), shaped: V.Value) -> V.Value:
  match shaped:
    case V.ObjectValue{fields}: V.ObjectValue{R.set(V.Value, fields, "returned", nullable(Bool.pick(Maybe<&2, String>, P.isPersisted(Unit, Unit, V.Value, session), P.getSessionFile(Unit, Unit, V.Value, session), None{})))}
    case other: other

def entryValue(entry: Entry()) -> V.Value:
  SJ.entry(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, entry)

def entryValues(entries: List<&2, Entry()>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: entryValue(entry) <> entryValues(rest)

def fileEntryValues(entries: List<&2, S.FileEntry<Unit, Unit, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: SJ.fileEntry(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, entry) <> fileEntryValues(rest)

def entryIds(entries: List<&2, Entry()>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: S.entryId(Unit, Unit, V.Value, entry) <> entryIds(rest)

def idsOf(result: Result<&2, &2, S.Error, List<&2, Entry()>>) -> V.Value:
  match result:
    case Fail{_}: V.Null{}
    case Done{entries}: texts(entryIds(entries))

type Visit is Data:
  Visit{depth: Nat, nodes: List<&2, S.SessionTreeNode<Unit, Unit, V.Value>>}

def treeLines(fuel: Nat, pending: List<&2, Visit>, +reversed: List<&2, String>) -> List<&2, String>:
  match fuel pending:
    case _ Nil{}: List.reverse(&2, String, reversed)
    case 0n _: List.reverse(&2, String, reversed)
    case 1n+remaining Visit{_, Nil{}} <> rest: treeLines(remaining, rest, reversed)
    case 1n+remaining Visit{+depth, S.SessionTreeNode{entry, children, label, labelTimestamp} <> siblings} <> rest:
      treeLines(remaining, Visit{1n + depth, children} <> Visit{depth, siblings} <> rest, (Nat.show(depth) ++ ":" ++ S.entryId(Unit, Unit, V.Value, entry) ++ ":" ++ Maybe.default(&2, String, label, "") ++ ":" ++ Maybe.default(&2, String, labelTimestamp, "")) <> reversed)

def treeOf(count: Nat, result: Result<&2, &2, S.Error, List<&2, S.SessionTreeNode<Unit, Unit, V.Value>>>) -> V.Value:
  match result:
    case Fail{_}: V.Null{}
    case Done{roots}: texts(treeLines(Nat.mul(2n, 1n + count), Visit{0n, roots} <> Nil{}, Nil{}))

def messageCount(result: Result<&2, &2, S.Error, S.SessionContext<Unit, Unit, V.Value>>) -> V.Value:
  match result:
    case Fail{_}: V.Null{}
    case Done{S.SessionContext{messages, _, _}}: SJ.natural(List.length(&2, Agent.AgentMessage<Unit, Unit, Messages.CodingMessage<V.Value>>, messages))

def labelProperty(id: String, label: Maybe<&2, String>, +reversed: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match label:
    case None{}: reversed
    case Some{text}: R.Property{id, V.Text{text}} <> reversed

def labelFields(ids: List<&2, String>, +state: State(), +reversed: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  match ids:
    case Nil{}: List.reverse(&2, R.Property<V.Value>, reversed)
    case +id <> rest: labelFields(rest, state, labelProperty(id, S.getLabel(Unit, Unit, V.Value, state, id), reversed))

def snapshot(+session: Session()) -> V.Value:
  +state = P.stateOf(Unit, Unit, V.Value, session)
  +entries = S.getEntries(Unit, Unit, V.Value, state)
  SJ.object(SJ.field("sessionId", V.Text{S.getSessionId(Unit, Unit, V.Value, state)}, SJ.field("sessionFile", nullable(P.getSessionFile(Unit, Unit, V.Value, session)), SJ.field("cwd", V.Text{P.getCwd(Unit, Unit, V.Value, session)}, SJ.field("persisted", V.Boolean{P.isPersisted(Unit, Unit, V.Value, session)}, SJ.field("leafId", nullable(S.getLeafId(Unit, Unit, V.Value, state)), SJ.field("entries", V.ArrayValue{entryValues(entries)}, SJ.field("branch", idsOf(S.getBranch(Unit, Unit, V.Value, state, S.Latest{})), SJ.field("tree", treeOf(List.length(&2, Entry(), entries), S.getTree(Unit, Unit, V.Value, state)), SJ.field("context", idsOf(S.sessionContextEntries(Unit, Unit, V.Value, state)), SJ.field("messages", messageCount(S.sessionContext(Unit, Unit, V.Value, state)), SJ.field("labels", V.ObjectValue{R.Record{labelFields(entryIds(entries), state, Nil{})}}, SJ.field("name", nullable(S.getSessionName(Unit, Unit, V.Value, state)), Nil{})))))))))))))

def infoValue(info: S.SessionInfo) -> V.Value:
  match info:
    case S.SessionInfo{+path, +id, +cwd, +name, +parentSessionPath, +created, +modified, +messageCount, +firstMessage, +allMessagesText}:
      SJ.object(SJ.field("path", V.Text{path}, SJ.field("id", V.Text{id}, SJ.field("cwd", V.Text{cwd}, SJ.field("name", nullable(name), SJ.field("parentSessionPath", nullable(parentSessionPath), SJ.field("created", V.Number{created}, SJ.field("modified", V.Number{modified}, SJ.field("messageCount", SJ.natural(messageCount), SJ.field("firstMessage", V.Text{firstMessage}, SJ.field("allMessagesText", V.Text{allMessagesText}, Nil{})))))))))))

def infoValues(infos: List<&2, S.SessionInfo>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case info <> rest: infoValue(info) <> infoValues(rest)

def infoPath(info: S.SessionInfo) -> V.Value:
  match info:
    case S.SessionInfo{path, _, _, _, _, _, _, _, _, _}: V.Text{path}

def infoPaths(infos: List<&2, S.SessionInfo>) -> List<&2, V.Value>:
  match infos:
    case Nil{}: Nil{}
    case info <> rest: infoPath(info) <> infoPaths(rest)

# Messages
# --------

def userMessage(+text: String, blocks: Bool, timestamp: F64) -> Agent.AgentMessage<Unit, Unit, Messages.CodingMessage<V.Value>>:
  Agent.LlmMessage{Ai.User{Ai.UserMessage{Bool.pick(Ai.UserContent, blocks, Ai.UserBlocks{Ai.TextImageText{Ai.TextContent{text, None{}}} <> Nil{}}, Ai.UserText{text}), timestamp}}}

def assistantMessage(text: String, timestamp: F64) -> Agent.AgentMessage<Unit, Unit, Messages.CodingMessage<V.Value>>:
  +zero = U32.to_f64(0)
  +one = U32.to_f64(1)
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{text, None{}}} <> Nil{}, "anthropic-messages", "anthropic", "test", None{}, None{}, None{}, None{}, Ai.Usage{one, one, zero, zero, None{}, None{}, U32.to_f64(2), Ai.UsageCost{zero, zero, zero, zero, zero}}, Ai.Stop{}, None{}, None{}, None{}, None{}, timestamp}}}

# Operations
# ----------

def replaced(world: World, outcome: Outcome()) -> World & V.Value:
  match world outcome:
    case World{previous, agentDir, cwd} Fail{error}: (World{previous, agentDir, cwd}, errorLine(P.message(error)))
    case World{_, agentDir, cwd} Done{+session}: (World{Some{session}, agentDir, cwd}, shape(session))

def replacedWithReturn(world: World, outcome: Outcome()) -> World & V.Value:
  match world outcome:
    case World{previous, agentDir, cwd} Fail{error}: (World{previous, agentDir, cwd}, errorLine(P.message(error)))
    case World{_, agentDir, cwd} Done{+session}: (World{Some{session}, agentDir, cwd}, withReturned(session, shape(session)))

def appended(world: World, outcome: P.Outcome(P.Appended<Unit, Unit, V.Value>), +timestamp: Maybe<&2, F64>) -> World & V.Value:
  match world outcome:
    case World{previous, agentDir, cwd} Fail{error}: (World{previous, agentDir, cwd}, errorLine(P.message(error)))
    case World{_, agentDir, cwd} Done{P.Appended{session, +id}}: (World{Some{session}, agentDir, cwd}, SJ.object(SJ.field("id", V.Text{id}, SJ.optional("timestamp", Maybe.map(&2, F64, V.Value, time => V.Number{time}, timestamp), Nil{}))))

def modified(world: World, outcome: Outcome()) -> World & V.Value:
  match world outcome:
    case World{previous, agentDir, cwd} Fail{error}: (World{previous, agentDir, cwd}, errorLine(P.message(error)))
    case World{_, agentDir, cwd} Done{+session}: (World{Some{session}, agentDir, cwd}, snapshot(session))

def options(+fields: R.Record<V.Value>) -> P.NewSessionOptions:
  P.NewSessionOptions{opt(fields, "id"), opt(fields, "parentSession")}

def restoredEntries(found: Maybe<&2, List<&2, V.Value>>) -> Maybe<&2, List<&2, S.FileEntry<Unit, Unit, V.Value>>>:
  Maybe.map(&2, List<&2, V.Value>, List<&2, S.FileEntry<Unit, Unit, V.Value>>, values => SJ.decodeValues(~Unit, ~Unit, ~V.Value, ~readUnit, ~readUnit, ~readSame, values), found)

def migratedValues(migration: SJ.Migration) -> V.Value:
  match migration:
    case SJ.Migration{_, values}: SJ.object(SJ.field("entries", V.ArrayValue{values}, Nil{}))

def keep(world: World, result: V.Value) -> World & V.Value: (world, result)

def sessionOp(+world: World, +fields: R.Record<V.Value>, +op: String, +session: Session()) -> IO(World & V.Value):
  match op:
    case "newSession":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.newSession(Unit, Unit, V.Value, session, options(fields))
        return replacedWithReturn(world, outcome)
    case "appendUser":
      do IO<World & V.Value>:
        +now : F64 <- Date.now()
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendMessage(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, userMessage(str(fields, "text"), flagOf(value(fields, "blocks")), now))
        return appended(world, outcome, Some{now})
    case "appendAssistant":
      do IO<World & V.Value>:
        +now : F64 <- Date.now()
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendMessage(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, assistantMessage(str(fields, "text"), now))
        return appended(world, outcome, Some{now})
    case "appendModelChange":
      do IO<World & V.Value>:
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendModelChange(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, str(fields, "provider"), str(fields, "modelId"))
        return appended(world, outcome, None{})
    case "appendCustomEntry":
      do IO<World & V.Value>:
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendCustomEntry(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, str(fields, "customType"), value(fields, "data"))
        return appended(world, outcome, None{})
    case "appendLabelChange":
      do IO<World & V.Value>:
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendLabelChange(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, str(fields, "targetId"), opt(fields, "label"))
        return appended(world, outcome, None{})
    case "appendCompaction":
      do IO<World & V.Value>:
        outcome : P.Outcome(P.Appended<Unit, Unit, V.Value>) <- P.appendCompaction(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, str(fields, "summary"), str(fields, "firstKeptEntryId"), num(fields, "tokensBefore"), None{}, None{}, None{})
        return appended(world, outcome, None{})
    case "branch": IO.pure(World & V.Value, modified(world, P.branch(Unit, Unit, V.Value, session, str(fields, "id"))))
    case "createBranchedSession":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.createBranchedSession(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, session, Maybe.default(&2, String, Maybe.or(&2, String, opt(fields, "leafId"), S.getLeafId(Unit, Unit, V.Value, P.stateOf(Unit, Unit, V.Value, session))), ""))
        return replacedWithReturn(world, outcome)
    case "snapshot": IO.pure(World & V.Value, keep(world, snapshot(session)))
    case _: IO.pure(World & V.Value, keep(world, errorLine("unknown op " ++ op)))

def withSession(world: World, fields: R.Record<V.Value>, op: String) -> IO(World & V.Value):
  match world:
    case World{None{}, agentDir, cwd}: IO.pure(World & V.Value, (World{None{}, agentDir, cwd}, errorLine("no session")))
    case World{Some{+session}, agentDir, cwd}: sessionOp(World{Some{session}, agentDir, cwd}, fields, op, session)

def step(world: World, +fields: R.Record<V.Value>, +op: String) -> IO(World & V.Value):
  match world op:
    case World{previous, +agentDir, +cwd} "load":
      do IO<World & V.Value>:
        entries : List<&2, S.FileEntry<Unit, Unit, V.Value>> <- P.loadEntriesFromFile(~Unit, ~Unit, ~V.Value, ~readUnit, ~readUnit, ~readSame, str(fields, "path"))
        return (World{previous, agentDir, cwd}, SJ.object(SJ.field("entries", V.ArrayValue{fileEntryValues(entries)}, Nil{})))
    case World{previous, +agentDir, +cwd} "open":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.open(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, ~readUnit, ~readUnit, ~readSame, str(fields, "path"), opt(fields, "sessionDir"), opt(fields, "cwdOverride"), cwd)
        return replaced(World{previous, agentDir, cwd}, outcome)
    case World{previous, +agentDir, +cwd} "create":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.create(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, ~readUnit, ~readUnit, ~readSame, str(fields, "cwd"), opt(fields, "sessionDir"), agentDir, options(fields))
        return replaced(World{previous, agentDir, cwd}, outcome)
    case World{previous, +agentDir, +cwd} "inMemory":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.inMemory(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, ~readUnit, ~readUnit, ~readSame, Maybe.default(&2, String, opt(fields, "cwd"), cwd), options(fields), restoredEntries(valuesOf(value(fields, "entries"))))
        return replaced(World{previous, agentDir, cwd}, outcome)
    case World{previous, +agentDir, +cwd} "continueRecent":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.continueRecent(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, ~readUnit, ~readUnit, ~readSame, str(fields, "cwd"), opt(fields, "sessionDir"), agentDir)
        return replaced(World{previous, agentDir, cwd}, outcome)
    case World{previous, +agentDir, +cwd} "forkFrom":
      do IO<World & V.Value>:
        outcome : Outcome() <- P.forkFrom(~Unit, ~Unit, ~V.Value, ~unitValue, ~unitValue, ~same, ~readUnit, ~readUnit, ~readSame, str(fields, "sourcePath"), str(fields, "targetCwd"), opt(fields, "sessionDir"), agentDir, options(fields))
        return replaced(World{previous, agentDir, cwd}, outcome)
    case World{previous, +agentDir, +cwd} "findMostRecent":
      do IO<World & V.Value>:
        found : Maybe<&2, String> <- P.findMostRecentSession(str(fields, "dir"), opt(fields, "cwd"))
        return (World{previous, agentDir, cwd}, SJ.object(SJ.field("path", nullable(found), Nil{})))
    case World{previous, +agentDir, +cwd} "findById":
      do IO<World & V.Value>:
        found : Maybe<&2, String> <- P.findById(str(fields, "cwd"), str(fields, "id"), opt(fields, "sessionDir"), agentDir)
        return (World{previous, agentDir, cwd}, SJ.object(SJ.field("path", nullable(found), Nil{})))
    case World{previous, +agentDir, +cwd} "list":
      do IO<World & V.Value>:
        infos : List<&2, S.SessionInfo> <- P.list(str(fields, "cwd"), opt(fields, "sessionDir"), agentDir)
        return (World{previous, agentDir, cwd}, SJ.object(SJ.field("sessions", V.ArrayValue{infoValues(infos)}, Nil{})))
    case World{previous, +agentDir, +cwd} "listAll":
      do IO<World & V.Value>:
        infos : List<&2, S.SessionInfo> <- P.listAll(opt(fields, "sessionDir"), Path.join(agentDir, "sessions"))
        return (World{previous, agentDir, cwd}, SJ.object(SJ.field("paths", V.ArrayValue{infoPaths(infos)}, Nil{})))
    case World{previous, +agentDir, +cwd} "migrate":
      do IO<World & V.Value>:
        migration : SJ.Migration <- SJ.migrated(Maybe.default(&2, List<&2, V.Value>, valuesOf(value(fields, "entries")), Nil{}))
        return (World{previous, agentDir, cwd}, migratedValues(migration))
    case World{previous, +agentDir, +cwd} "sleep":
      do IO<World & V.Value>:
        IO.sleep(U32.from_nat(num(fields, "ms")))
        return (World{previous, agentDir, cwd}, SJ.object(Nil{}))
    case current other: withSession(current, fields, other)

def perform(+world: World, parsed: Result<&2, &2, Decode.ParseError, V.Value>) -> IO(World & V.Value):
  match parsed:
    case Done{V.ObjectValue{+fields}}: step(world, fields, str(fields, "op"))
    case _: IO.pure(World & V.Value, (world, errorLine("malformed operation")))

def reported(outcome: World & V.Value) -> IO(World):
  match outcome:
    case (next, result):
      do IO<World>:
        IO.print(line(result))
        return next

def performed(+world: World, +row: String, blank: Bool) -> IO(World):
  match blank:
    case True{}: IO.pure(World, world)
    case False{}:
      do IO<World>:
        outcome : World & V.Value <- perform(world, Decode.parse(row))
        reported(outcome)

def operations(lines: List<&2, String>, world: World) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case +row <> rest:
      do IO<Unit>:
        next : World <- performed(world, row, String.is_empty(String.trim(row)))
        operations(rest, next)

def scriptText(decoded: Result<&2, &2, Utf8.Error, String>) -> IO(List<&2, String>):
  match decoded:
    case Fail{_}: IO.die(List<&2, String>, 1, "operations file is not UTF-8")
    case Done{text}: IO.pure(List<&2, String>, String.split(text, '\n'))

def scriptBytes(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> IO(List<&2, String>):
  match bytes:
    case Fail{_}: IO.die(List<&2, String>, 1, "could not read the operations file")
    case Done{content}: scriptText(Utf8.decodeWith(Utf8.Preserve{}, content))

def script(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    scriptBytes(bytes)

def located(result: Result<&2, &2, FS.Error, String>) -> String:
  Result.default(&2, &2, FS.Error, String, result, "/")

def start(args: List<String>) -> IO(Unit):
  match args:
    case path <> Nil{}:
      do IO<Unit>:
        agentDir : Result<&1, &1, U32 & String, String> <- IO.get_env("PI_CODING_AGENT_DIR")
        cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
        lines : List<&2, String> <- script(path)
        operations(lines, World{None{}, Result.default(&1, &1, U32 & String, String, agentDir, "/tmp/pi-agent"), located(cwd)})
    case _: IO.die(Unit, 1, "usage: session-file <operations.jsonl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    start(args)
