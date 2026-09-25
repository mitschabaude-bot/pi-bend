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
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../../../agent/src/types.bend as Agent
import ../session-manager.bend as S
import ../session-persistence.bend as Persistence
import ../session-json.bend as SessionJson
import ../messages.bend as Messages
import ../tools/index.bend as Tools
import ../../modes/interactive/theme/theme.bend as Theme
import ../../modes/interactive/theme/color.bend as Color
import ../../modes/interactive/theme/detection.bend as Detection

# The browser viewer is a copied static asset from pi-mono at f07218c4d.
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

# HTML uses the same resolved palette as the terminal. The theme's optional
# export backgrounds are read from its document; missing ones derive from the
# user-message background, as in pi's browser export.
type ExportColors is Data: ExportColors{page: Maybe<&2,String>,card: Maybe<&2,String>,info: Maybe<&2,String>}
type ExportPalette is Data: ExportPalette{page: String,card: String,info: String}
def hexDigit(+value: Nat) -> Char:
  Char.from_u32(U32.from_nat(Bool.pick(Nat,Nat.is_lt(value,10n),48n + value,87n + value)))

def hexByte(+value: Nat) -> String:
  SCon{hexDigit(value / 16n),SCon{hexDigit(value % 16n),SNil{}}}

def rgbHex(value: Color.Rgb) -> String:
  match value:
    case Color.Rgb{r,g,b}: "#" ++ hexByte(r) ++ hexByte(g) ++ hexByte(b)

def colorRgb(color: Color.Color) -> Maybe<&2,Color.Rgb>:
  match color:
    case Color.RgbColor{rgb}: Some{rgb}
    case Color.Indexed{index}: Some{Detection.ansiRgb(index)}
    case Color.Default{}: None{}

def cssRgb(value: Maybe<&2,Color.Rgb>,light: Bool) -> String:
  match value:
    case Some{rgb}: rgbHex(rgb)
    case None{}: Bool.pick(String,light,"#000000","#e5e5e7")

def cssColor(color: Color.Color,light: Bool) -> String:
  cssRgb(colorRgb(color),light)

def cssEntries(items: List<&2,R.Property<Color.Color>>,+light: Bool) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case R.Property{key,color} <> rest: ("--" ++ key ++ ": " ++ cssColor(color,light) ++ ";") <> cssEntries(rest,light)

def themeColors(theme: Theme.Theme) -> List<&2,String>:
  match theme:
    case Theme.Theme{name,_,fg,bg,_,_}:
      +light = String.eq(name,"light")
      List.append(&2,String,cssEntries(R.entries(Color.Color,fg),light),cssEntries(R.entries(Color.Color,bg),light))

def themeBackground(theme: Theme.Theme) -> Color.Rgb:
  match theme:
    case Theme.Theme{_,_,_,background,_,_}:
      Maybe.default(&2,Color.Rgb,Maybe.bind(&2,Color.Color,Color.Rgb,R.get(Color.Color,background,"userMessageBg"),colorRgb),Color.Rgb{52n,53n,65n})

def resolvedColor(value: Result<&2,&2,Theme.Error,Color.Color>,light: Bool) -> Maybe<&2,String>:
  match value:
    case Fail{_}: None{}
    case Done{Color.Default{}}: None{}
    case Done{color}: Some{cssColor(color,light)}

def resolvedToken(value: Result<&2,&2,Theme.Error,Theme.Token>,vars: R.Record<Theme.Token>,light: Bool) -> Maybe<&2,String>:
  match value:
    case Fail{_}: None{}
    case Done{token}: resolvedColor(Theme.resolve(token,vars,Nil{}),light)

def resolvedExport(value: Maybe<&2,V.Value>,key: String,vars: R.Record<Theme.Token>,light: Bool) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{source}: resolvedToken(Theme.token(key,source),vars,light)

def exportFields(+fields: R.Record<V.Value>,+vars: R.Record<Theme.Token>,+light: Bool) -> ExportColors:
  ExportColors{resolvedExport(R.get(V.Value,fields,"pageBg"),"pageBg",vars,light),resolvedExport(R.get(V.Value,fields,"cardBg"),"cardBg",vars,light),resolvedExport(R.get(V.Value,fields,"infoBg"),"infoBg",vars,light)}

def exportVars(value: Maybe<&2,V.Value>) -> R.Record<Theme.Token>:
  match value:
    case Some{V.ObjectValue{fields}}: Result.default(&2,&2,Theme.Error,R.Record<Theme.Token>,Theme.tokenMap(fields),R.new(Theme.Token))
    case _: R.new(Theme.Token)

def exportSection(value: Maybe<&2,V.Value>,vars: R.Record<Theme.Token>,light: Bool) -> ExportColors:
  match value:
    case Some{V.ObjectValue{export}}: exportFields(export,vars,light)
    case _: ExportColors{None{},None{},None{}}

def exportDocument(value: V.Value,light: Bool) -> ExportColors:
  match value:
    case V.ObjectValue{+fields}:
      exportSection(R.get(V.Value,fields,"export"),exportVars(R.get(V.Value,fields,"vars")),light)
    case _: ExportColors{None{},None{},None{}}

def exportJson(result: Result<&2,&2,Decode.ParseError,V.Value>,light: Bool) -> ExportColors:
  match result:
    case Done{value}: exportDocument(value,light)
    case Fail{_}: ExportColors{None{},None{},None{}}

def exportBytes(result: Result<&2,&2,FS.Error,List<&2,U32>>,light: Bool) -> ExportColors:
  match result:
    case Done{bytes}: exportJson(Decode.parse(Utf8.decodeBytes(bytes)),light)
    case Fail{_}: ExportColors{None{},None{},None{}}

def adjusted(channel: Nat,percent: Nat) -> Nat: Nat.min(255n,(channel * percent + 50n) / 100n)

def rgbText(red: Nat,green: Nat,blue: Nat) -> String:
  "rgb(" ++ Nat.show(red) ++ ", " ++ Nat.show(green) ++ ", " ++ Nat.show(blue) ++ ")"

def derivedFor(mode: Detection.TerminalTheme,+r: Nat,+g: Nat,+b: Nat) -> ExportPalette:
  match mode:
    case Detection.Light{}:
      ExportPalette{rgbText(adjusted(r,96n),adjusted(g,96n),adjusted(b,96n)),rgbHex(Color.Rgb{r,g,b}),rgbText(Nat.min(255n,r + 10n),Nat.min(255n,g + 5n),b - 20n)}
    case Detection.Dark{}:
      ExportPalette{rgbText(adjusted(r,70n),adjusted(g,70n),adjusted(b,70n)),rgbText(adjusted(r,85n),adjusted(g,85n),adjusted(b,85n)),rgbText(Nat.min(255n,r + 20n),Nat.min(255n,g + 15n),b)}

def derivedColors(rgb: Color.Rgb) -> ExportPalette:
  match rgb:
    case Color.Rgb{+r,+g,+b}:
      derivedFor(Detection.getThemeForRgbColor(Color.Rgb{r,g,b}),r,g,b)

def selectFallback(derived: ExportPalette,page: Maybe<&2,String>,card: Maybe<&2,String>,info: Maybe<&2,String>) -> ExportPalette:
  match derived:
    case ExportPalette{fallbackPage,fallbackCard,fallbackInfo}:
      ExportPalette{Maybe.default(&2,String,page,fallbackPage),Maybe.default(&2,String,card,fallbackCard),Maybe.default(&2,String,info,fallbackInfo)}

def selectedColors(explicit: ExportColors,derived: ExportPalette) -> ExportPalette:
  match explicit:
    case ExportColors{page,card,info}: selectFallback(derived,page,card,info)

def applyColorsToCss(template: String,css: String,javascript: String,marked: String,highlight: String,vars: String,colors: ExportPalette) -> Assets:
  match colors:
    case ExportPalette{page,card,info}:
      +styled = replaceFirst(replaceFirst(replaceFirst(css,"{{BODY_BG}}",page,""),"{{CONTAINER_BG}}",card,""),"{{INFO_BG}}",info,"")
      Assets{template,styled,javascript,marked,highlight,vars}

def applyColors(assets: Assets,vars: String,colors: ExportPalette) -> Assets:
  match assets:
    case Assets{template,css,javascript,marked,highlight,_}: applyColorsToCss(template,css,javascript,marked,highlight,vars,colors)

def styledColors(assets: Assets,vars: String,colors: ExportPalette) -> Assets:
  match colors:
    case ExportPalette{+page,+card,+info}:
      applyColors(assets,vars ++ "\n      --exportPageBg: " ++ page ++ ";\n      --exportCardBg: " ++ card ++ ";\n      --exportInfoBg: " ++ info ++ ";",ExportPalette{page,card,info})

def styleAssets(assets: Assets,+theme: Theme.Theme,explicit: ExportColors) -> Assets:
  +colors = selectedColors(explicit,derivedColors(themeBackground(theme)))
  +vars = String.join(themeColors(theme),"\n      ")
  styledColors(assets,vars,colors)

def isLight(theme: Theme.Theme) -> Bool:
  match theme: case Theme.Theme{name,_,_,_,_,_}: String.eq(name,"light")

def themed(assets: Assets,+theme: Theme.Theme,path: String) -> IO(Assets):
  do IO<Assets>:
    result : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return styleAssets(assets,theme,exportBytes(result,isLight(theme)))

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

def fromResolved(ids: Uuid.Generator, assets: Assets, +source: String, +cwd: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    opened : Persistence.Outcome(Session()) <- Persistence.open(~Unit, ~Tools.ToolDetails, ~V.Value, ~unitValue, ~Tools.detailsValue, ~rawValue, ~readUnit, ~readDetails, ~readRaw, ids, source, None{}, None{}, cwd)
    fromOpened(assets, source, cwd, outputPath, opened)

def fromFound(ids: Uuid.Generator, assets: Assets, cwd: String, outputPath: Maybe<&2, String>, found: Result<&2, &2, FS.Error, String>) -> IO(Outcome(String)):
  match found:
    case Fail{error}: IO.pure(Outcome(String), Fail{fileError(error)})
    case Done{source}: fromResolved(ids, assets, source, cwd, outputPath)

def fromCwd(ids: Uuid.Generator, assets: Assets, +inputPath: String, outputPath: Maybe<&2, String>, result: Result<&2, &2, FS.Error, String>) -> IO(Outcome(String)):
  match result:
    case Fail{error}: IO.pure(Outcome(String), Fail{fileError(error)})
    case Done{+cwd}:
      do IO<Outcome(String)>:
        found : Result<&2, &2, FS.Error, String> <- FS.realpath(Maybe.default(&2, String, Path.resolve(cwd, inputPath), inputPath))
        fromFound(ids, assets, cwd, outputPath, found)

def exportFromFile(ids: Uuid.Generator, assets: Assets, inputPath: String, outputPath: Maybe<&2, String>) -> IO(Outcome(String)):
  do IO<Outcome(String)>:
    cwd : Result<&2, &2, FS.Error, String> <- FS.cwd()
    fromCwd(ids, assets, inputPath, outputPath, cwd)
