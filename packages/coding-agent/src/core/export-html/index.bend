import Base
import ../../../../runtime/src/base64.bend as Base64
import ../../../../runtime/src/filesystem.bend as FS
import ../../../../runtime/src/posix-path.bend as Path
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/utf8.bend as Utf8
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/json.bend as Decode
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/json.bend as Json
import ../../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../../ai/src/utils/transcript.bend as Transcript
import ../../../../agent/src/types.bend as Agent
import ../session-manager.bend as S
import ../session-persistence.bend as Persistence
import ../session-json.bend as SessionJson
import ../messages.bend as Messages
import ../tools/index.bend as Tools

# The browser viewer is a copied static asset from pi-mono at 46c9de402.
# Bend owns the session snapshot, JSON encoding, asset loading and file write.
# Asset paths are explicit so an installed CLI can locate its bundled viewer
# independently of the user's conversation working directory.
type Assets is Data:
  Assets{template: String, css: String, javascript: String, marked: String, highlight: String, themeVars: String}

def State() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def AgentState() -> Data: Agent.AgentState<Unit, Tools.ToolDetails, Messages.CodingMessage<V.Value>, Tools.ToolError>
def Session() -> Data: Persistence.Session<Unit, Tools.ToolDetails, V.Value>
def Outcome(-A: Data) -> Data: Result<&2, &2, String, A>

def fileError(value: FS.Error) -> String:
  match value:
    case FS.System{_, message}: message
    case FS.InvalidPathEncoding{_}: "Invalid UTF-8 path"
    case FS.WriteAndClose{_, message, _, _}: message
    case FS.ReadAndClose{_, message, _, _}: message

def assetResult(path: String, result: Result<&2, &2, FS.Error, List<&2, U32>>) -> Outcome(String):
  match result:
    case Done{bytes}: Done{Utf8.decodeBytes(bytes)}
    case Fail{error}: Fail{path ++ ": " ++ fileError(error)}

def asset(+path: String) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    result : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile(path)
    return assetResult(path, result)

def loaded(template: Outcome(String), css: Outcome(String), javascript: Outcome(String), marked: Outcome(String), highlight: Outcome(String), theme: Outcome(String)) -> Outcome(Assets):
  match template css javascript marked highlight theme:
    case Done{a} Done{b} Done{c} Done{d} Done{e} Done{f}: Done{Assets{a, b, c, d, e, f}}
    case Fail{error} _ _ _ _ _: Fail{error}
    case _ Fail{error} _ _ _ _: Fail{error}
    case _ _ Fail{error} _ _ _: Fail{error}
    case _ _ _ Fail{error} _ _: Fail{error}
    case _ _ _ _ Fail{error} _: Fail{error}
    case _ _ _ _ _ Fail{error}: Fail{error}

def loadAssets(+directory: String) -> IO(Outcome(Assets)):
  do IO<Outcome(Assets)>:
    html : Outcome(String) <- asset(Path.join(directory, "template.html"))
    css : Outcome(String) <- asset(Path.join(directory, "template.css"))
    js : Outcome(String) <- asset(Path.join(directory, "template.js"))
    marked : Outcome(String) <- asset(Path.join(directory, "vendor/marked.min.js"))
    highlight : Outcome(String) <- asset(Path.join(directory, "vendor/highlight.min.js"))
    theme : Outcome(String) <- asset(Path.join(directory, "dark-vars.css"))
    return loaded(html, css, js, marked, highlight, theme)

# Replace one template marker. Session JSON is inserted only as Base64, never
# as raw HTML or an executable script body.
def replaceFirst(+text: String, +marker: String, +replacement: String, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{char, rest}:
      Bool.pick(Unit -> String, String.starts_with(text, marker), _ => String.reverse(reversed) ++ replacement ++ String.drop(text, String.length(marker)), _ => replaceFirst(rest, marker, replacement, SCon{char, reversed}))(Unit{})

def cssWithTheme(css: String, vars: String) -> String:
  a = replaceFirst(css, "{{INFO_BG}}", "#3c3728", "")
  b = replaceFirst(a, "{{CONTAINER_BG}}", "#1e1e24", "")
  c = replaceFirst(b, "{{BODY_BG}}", "#18181e", "")
  replaceFirst(c, "{{THEME_VARS}}", vars, "")

def json(value: V.Value) -> String:
  Maybe.default(&2, String, Json.stringify(SchemaJson.toJson(value)), "null")

def encoded(result: Result<&2, &2, Base64.Error, String>) -> String:
  match result:
    case Done{value}: value
    case Fail{_}: ""

def payload(value: V.Value) -> String:
  encoded(Base64.encode(Utf8.encode(json(value))))

def nullableText(value: Maybe<&2, String>) -> V.Value:
  match value:
    case None{}: V.Null{}
    case Some{value}: V.Text{value}

def field(key: String, value: V.Value, rest: List<&2, R.Property<V.Value>>) -> List<&2, R.Property<V.Value>>:
  R.Property{key, value} <> rest

def llmMessages(messages: List<&2, Agent.AgentMessage<Unit, Tools.ToolDetails, Messages.CodingMessage<V.Value>>>) -> List<&2, Ai.Message<V.Value, V.Value, Unit, Tools.ToolDetails>>:
  match messages:
    case Nil{}: Nil{}
    case Agent.LlmMessage{message} <> rest: message <> llmMessages(rest)
    case Agent.CustomMessage{_} <> rest: llmMessages(rest)

def tool(value: Agent.AgentTool<Tools.ToolDetails, Tools.ToolError>) -> V.Value:
  match value:
    case Agent.AgentTool{name, description, parameters, _, _, _, _, _, _}:
      V.ObjectValue{R.Record{field("name", V.Text{name}, field("description", V.Text{description}, field("parameters", parameters, Nil{})))}}

def tools(values: List<&2, Agent.AgentTool<Tools.ToolDetails, Tools.ToolError>>) -> List<&2, V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: tool(value) <> tools(rest)

def stateInfo(value: AgentState()) -> V.Value & V.Value:
  match value:
    case Agent.AgentState{_, _, definitions, messages, _, _, _, _}:
      (V.Text{Transcript.getCurrentSystemPrompt(V.Value, V.Value, Unit, Tools.ToolDetails, llmMessages(messages))}, V.ArrayValue{tools(definitions)})

def entryValues(entries: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>) -> List<&2, V.Value>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: SessionJson.entry(~Unit, ~Tools.ToolDetails, ~V.Value, ~(_ => V.Null{}), ~Tools.detailsValue, ~(value => value), entry) <> entryValues(rest)

def sessionDataOf(+manager: State(), info: V.Value & V.Value) -> V.Value:
  match info:
    case (prompt, toolList):
      f0 = {Nil{} : List<&2, R.Property<V.Value>>}
      f1 = field("tools", toolList, f0)
      f2 = field("systemPrompt", prompt, f1)
      f3 = field("leafId", nullableText(S.getLeafId(Unit, Tools.ToolDetails, V.Value, manager)), f2)
      f4 = field("entries", V.ArrayValue{entryValues(S.getEntries(Unit, Tools.ToolDetails, V.Value, manager))}, f3)
      f5 = field("header", SessionJson.header(S.getHeader(Unit, Tools.ToolDetails, V.Value, manager)), f4)
      V.ObjectValue{R.Record{f5}}

def sessionData(manager: State(), agentState: AgentState()) -> V.Value:
  sessionDataOf(manager, stateInfo(agentState))

def fileData(+manager: State()) -> V.Value:
  f0 = {Nil{} : List<&2, R.Property<V.Value>>}
  f1 = field("leafId", nullableText(S.getLeafId(Unit, Tools.ToolDetails, V.Value, manager)), f0)
  f2 = field("entries", V.ArrayValue{entryValues(S.getEntries(Unit, Tools.ToolDetails, V.Value, manager))}, f1)
  f3 = field("header", SessionJson.header(S.getHeader(Unit, Tools.ToolDetails, V.Value, manager)), f2)
  V.ObjectValue{R.Record{f3}}

def render(assets: Assets, data: V.Value) -> String:
  match assets:
    case Assets{template, css, javascript, marked, highlight, vars}:
      styled = cssWithTheme(css, vars)
      withJs = replaceFirst(template, "{{JS}}", javascript, "")
      withHighlight = replaceFirst(withJs, "{{HIGHLIGHT_JS}}", highlight, "")
      withMarked = replaceFirst(withHighlight, "{{MARKED_JS}}", marked, "")
      withData = replaceFirst(withMarked, "{{SESSION_DATA}}", payload(data), "")
      replaceFirst(withData, "{{CSS}}", styled, "")

def generate(assets: Assets, manager: State(), agentState: AgentState()) -> String:
  render(assets, sessionData(manager, agentState))

def generateFromFile(assets: Assets, manager: State()) -> String:
  render(assets, fileData(manager))

# The default filename follows upstream's pi-session-<source stem>.html rule
# in the process working directory.
def finalPart(parts: List<&2, String>) -> String:
  match parts:
    case Nil{}: ""
    case value <> Nil{}: value
    case _ <> rest: finalPart(rest)

def stem(+name: String, jsonl: Bool) -> String:
  match jsonl:
    case True{}: String.take(name, String.length(name) - 6n)
    case False{}: name

def sourceStem(path: String) -> String:
  +name = finalPart(Strings.split(path, '/'))
  stem(name, String.ends_with(name, ".jsonl"))

def resolvedPath(result: Maybe<&2, String>) -> Outcome(String):
  match result:
    case Some{resolved}: Done{resolved}
    case None{}: Fail{"Cannot resolve HTML output path"}

def chosenPath(+source: String, cwd: String, outputPath: Maybe<&2, String>) -> Outcome(String):
  match outputPath:
    case None{}: Done{Path.join(cwd, "pi-session-" ++ sourceStem(source) ++ ".html")}
    case Some{path}: resolvedPath(Path.resolve(cwd, path))

def writeResult(path: String, result: Result<&2, &2, FS.Error, Unit>) -> Outcome(String):
  match result:
    case Done{_}: Done{path}
    case Fail{error}: Fail{path ++ ": " ++ fileError(error)}

def writeHtml(+path: String, html: String) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    result : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(path, html)
    return writeResult(path, result)

def writeChosen(assets: Assets, session: Session(), agentState: AgentState(), chosen: Outcome(String)) -> IO(Outcome(String)):
  match chosen:
    case Fail{error}: IO.pure(Outcome(String), Fail{error})
    case Done{path}: writeHtml(path, generate(assets, Persistence.stateOf(Unit, Tools.ToolDetails, V.Value, session), agentState))

def writeResolved(assets: Assets, session: Session(), agentState: AgentState(), source: String, cwd: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  writeChosen(assets, session, agentState, chosenPath(source, cwd, outputPath))

def writeAfterSource(assets: Assets, session: Session(), agentState: AgentState(), outputPath: Maybe<&2, String>, found: Result<&2, &2, FS.Error, String>, cwd: Result<&2, &2, FS.Error, String>) -> IO(Outcome(String)):
  match found cwd:
    case Fail{_} _: IO.pure(Outcome(String), Fail{"Nothing to export yet - start a conversation first"})
    case _ Fail{error}: IO.pure(Outcome(String), Fail{fileError(error)})
    case Done{resolved} Done{current}: writeResolved(assets, session, agentState, resolved, current, outputPath)

def writeSource(assets: Assets, session: Session(), agentState: AgentState(), source: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    found : Result<&2, &2, FS.Error, String> <- FS.realpath(source)
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    writeAfterSource(assets, session, agentState, outputPath, found, cwd)

def writeWithFile(assets: Assets, session: Session(), agentState: AgentState(), outputPath: Maybe<&2, String>, file: Maybe<&2, String>) -> IO(Outcome(String)):
  match file:
    case None{}: IO.pure(Outcome(String), Fail{"Cannot export in-memory session to HTML"})
    case Some{source}: writeSource(assets, session, agentState, source, outputPath)

def write(assets: Assets, +session: Session(), agentState: AgentState(), outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  writeWithFile(assets, session, agentState, outputPath, Persistence.getSessionFile(Unit, Tools.ToolDetails, V.Value, session))

# Standalone export of an existing JSONL file uses the same session migration
# and typed decoder as normal session opening, without adding AgentState data.
def unitValue(value: Unit) -> V.Value: V.Null{}
def rawValue(value: V.Value) -> V.Value: value
def readUnit(value: V.Value) -> Result<&2, &2, Decode.Error, Unit>: Done{Unit{}}
def readRaw(value: V.Value) -> Result<&2, &2, Decode.Error, V.Value>: Done{value}
def readDetails(value: V.Value) -> Result<&2, &2, Decode.Error, Tools.ToolDetails>: Done{Tools.RawDetails{value}}

def fromFileChosen(assets: Assets, session: Session(), chosen: Outcome(String)) -> IO(Outcome(String)):
  match chosen:
    case Fail{error}: IO.pure(Outcome(String), Fail{error})
    case Done{path}: writeHtml(path, generateFromFile(assets, Persistence.stateOf(Unit, Tools.ToolDetails, V.Value, session)))

def fromOpened(assets: Assets, source: String, cwd: String, outputPath: Maybe<&2, String>, result: Persistence.Outcome(Session())) -> IO(Outcome(String)):
  match result:
    case Fail{error}: IO.pure(Outcome(String), Fail{Persistence.message(error)})
    case Done{session}: fromFileChosen(assets, session, chosenPath(source, cwd, outputPath))

def fromResolved(assets: Assets, +source: String, +cwd: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    opened : Persistence.Outcome(Session()) <- Persistence.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, source, None{}, None{}, cwd)
    fromOpened(assets, source, cwd, outputPath, opened)

def fromFound(assets: Assets, cwd: String, outputPath: Maybe<&2, String>, found: Result<&2, &2, FS.Error, String>) -> IO(Outcome(String)):
  match found:
    case Fail{error}: IO.pure(Outcome(String), Fail{fileError(error)})
    case Done{source}: fromResolved(assets, source, cwd, outputPath)

def fromCwd(assets: Assets, +inputPath: String, outputPath: Maybe<&2, String>, result: Result<&2, &2, FS.Error, String>) -> IO(Outcome(String)):
  match result:
    case Fail{error}: IO.pure(Outcome(String), Fail{fileError(error)})
    case Done{+cwd}:
      do IO<Outcome(String)>:
        found : Result<&2, &2, FS.Error, String> <- FS.realpath(Maybe.default(&2, String, Path.resolve(cwd, inputPath), inputPath))
        fromFound(assets, cwd, outputPath, found)

def exportFromFile(assets: Assets, inputPath: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    fromCwd(assets, inputPath, outputPath, cwd)
