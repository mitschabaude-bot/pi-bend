import Base
import ../../../tui/src/keybindings.bend as Tui
import ../../../tui/src/keys.bend as Keys
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/stable-sort.bend as Sort

# Platform facts are supplied by the application, including WSL detection.
type Environment is Data:
  Environment{platform: String,wslDistroName: Maybe<&2,String>,wslInterop: Maybe<&2,String>}
def nonempty(value: Maybe<&2,String>) -> Bool:
  match value:
    case None{}: False{}
    case Some{SNil{}}: False{}
    case Some{_}: True{}
def useWindowsKeybindings(environment: Environment) -> Bool:
  match environment:
    case Environment{+platform,distro,interop}: String.eq(platform,"win32") || (String.eq(platform,"linux") && (nonempty(distro) || nonempty(interop)))
def onPlatform(environment: Environment,name: String) -> Bool:
  match environment:
    case Environment{platform,_,_}: String.eq(platform,name)
def applyDefinitions(values: List<&2,R.Property<Tui.KeybindingDefinition>>,definitions: Tui.KeybindingDefinitions()) -> Tui.KeybindingDefinitions():
  match values:
    case Nil{}: definitions
    case R.Property{name,value} <> rest: applyDefinitions(rest,R.set(Tui.KeybindingDefinition,definitions,name,value))

# App additions and overrides; unchanged TUI definitions stay shared.
def appDefinitions(+windows: Bool,+native: Bool,+darwin: Bool) -> List<&2,R.Property<Tui.KeybindingDefinition>>:
  R.Property{"tui.editor.undo",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,native,Keys.KeyId{Keys.Printable{'z'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'z'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Keys.KeyId{Keys.Printable{'-'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{})),Some{"Undo"}}} <>
  R.Property{"tui.altScreen.previousPrompt",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Up{},Keys.Modifiers{True{},False{},True{},False{}}} <> Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{}),Some{"Jump to previous semantic prompt"}}} <>
  R.Property{"tui.altScreen.nextPrompt",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Down{},Keys.Modifiers{True{},False{},True{},False{}}} <> Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{}),Some{"Jump to next semantic prompt"}}} <>
  R.Property{"tui.altScreen.search",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'f'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Printable{'f'},Keys.Modifiers{True{},False{},True{},False{}}} <> Nil{}),Some{"Search the primary scroll view"}}} <>
  R.Property{"app.interrupt",Tui.KeybindingDefinition{Keys.KeyId{Keys.Escape{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Cancel or abort"}}} <>
  R.Property{"app.clear",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'c'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Clear editor"}}} <>
  R.Property{"app.exit",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'d'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Exit when editor is empty"}}} <>
  R.Property{"app.suspend",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,native,Nil{},Keys.KeyId{Keys.Printable{'z'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{}),Some{"Suspend to background"}}} <>
  R.Property{"app.thinking.cycle",Tui.KeybindingDefinition{Keys.KeyId{Keys.Tab{},Keys.Modifiers{True{},False{},False{},False{}}} <> Nil{},Some{"Cycle thinking level"}}} <>
  R.Property{"app.thinking.save",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'s'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Save thinking level"}}} <>
  R.Property{"app.model.cycleForward",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'p'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Cycle to next model"}}} <>
  R.Property{"app.model.cycleBackward",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'p'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Keys.KeyId{Keys.Printable{'p'},Keys.Modifiers{True{},False{},True{},False{}}} <> Nil{}),Some{"Cycle to previous model"}}} <>
  R.Property{"app.model.select",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'l'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Open model selector"}}} <>
  R.Property{"app.tools.expand",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'o'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle tool output"}}} <>
  R.Property{"app.thinking.toggle",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'t'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle thinking blocks"}}} <>
  R.Property{"app.session.toggleNamedFilter",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'n'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle named session filter"}}} <>
  R.Property{"app.editor.external",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'g'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Open external editor"}}} <>
  R.Property{"app.message.copy",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'x'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Copy selection or last assistant message"}}} <>
  R.Property{"app.message.followUp",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'q'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Enter{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{}),Some{"Queue follow-up message"}}} <>
  R.Property{"app.message.dequeue",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'q'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{}),Some{"Restore queued messages"}}} <>
  R.Property{"app.clipboard.pasteImage",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,windows,Keys.KeyId{Keys.Printable{'v'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Keys.KeyId{Keys.Printable{'v'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{}),Some{"Paste image from clipboard (text fallback)"}}} <>
  R.Property{"app.session.new",Tui.KeybindingDefinition{Nil{},Some{"Start a new session"}}} <>
  R.Property{"app.session.tree",Tui.KeybindingDefinition{Nil{},Some{"Open session tree"}}} <>
  R.Property{"app.session.fork",Tui.KeybindingDefinition{Nil{},Some{"Fork current session"}}} <>
  R.Property{"app.session.resume",Tui.KeybindingDefinition{Nil{},Some{"Resume a session"}}} <>
  R.Property{"app.tree.foldOrUp",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,darwin,Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},True{},False{},False{}}} <> Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{}),Some{"Fold tree branch or move up"}}} <>
  R.Property{"app.tree.unfoldOrDown",Tui.KeybindingDefinition{Bool.pick(List<&2,Keys.KeyId>,darwin,Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},True{},False{},False{}}} <> Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{}),Some{"Unfold tree branch or move down"}}} <>
  R.Property{"app.tree.editLabel",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'l'},Keys.Modifiers{True{},False{},False{},False{}}} <> Nil{},Some{"Edit tree label"}}} <>
  R.Property{"app.tree.toggleLabelTimestamp",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'t'},Keys.Modifiers{True{},False{},False{},False{}}} <> Nil{},Some{"Toggle tree label timestamps"}}} <>
  R.Property{"app.session.togglePath",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'p'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle session path display"}}} <>
  R.Property{"app.session.toggleSort",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'s'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle session sort mode"}}} <>
  R.Property{"app.session.rename",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'r'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Rename session"}}} <>
  R.Property{"app.session.delete",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'d'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Delete session"}}} <>
  R.Property{"app.session.deleteNoninvasive",Tui.KeybindingDefinition{Keys.KeyId{Keys.Backspace{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Delete session when query is empty"}}} <>
  R.Property{"app.models.save",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'s'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Save model selection"}}} <>
  R.Property{"app.models.enableAll",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'a'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Enable all models"}}} <>
  R.Property{"app.models.clearAll",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'x'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Clear all models"}}} <>
  R.Property{"app.models.toggleProvider",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'p'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Toggle all models for provider"}}} <>
  R.Property{"app.models.reorderUp",Tui.KeybindingDefinition{Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Move model up in order"}}} <>
  R.Property{"app.models.reorderDown",Tui.KeybindingDefinition{Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Move model down in order"}}} <>
  R.Property{"app.tree.filter.default",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'d'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: default view"}}} <>
  R.Property{"app.tree.filter.noTools",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'t'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: hide tool results"}}} <>
  R.Property{"app.tree.filter.userOnly",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'u'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: user messages only"}}} <>
  R.Property{"app.tree.filter.labeledOnly",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'l'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: labeled entries only"}}} <>
  R.Property{"app.tree.filter.all",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'a'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: show all entries"}}} <>
  R.Property{"app.tree.filter.cycleForward",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'o'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: cycle forward"}}} <>
  R.Property{"app.tree.filter.cycleBackward",Tui.KeybindingDefinition{Keys.KeyId{Keys.Printable{'o'},Keys.Modifiers{True{},False{},True{},False{}}} <> Nil{},Some{"Tree filter: cycle backward"}}} <> Nil{}

def KEYBINDINGS(+environment: Environment) -> Tui.KeybindingDefinitions():
  applyDefinitions(appDefinitions(useWindowsKeybindings(environment),onPlatform(environment,"win32"),onPlatform(environment,"darwin")),Tui.TUI_KEYBINDINGS())

def migratedName(name: String) -> String:
  match name:
    case "cursorUp": "tui.editor.cursorUp"
    case "cursorDown": "tui.editor.cursorDown"
    case "cursorLeft": "tui.editor.cursorLeft"
    case "cursorRight": "tui.editor.cursorRight"
    case "cursorWordLeft": "tui.editor.cursorWordLeft"
    case "cursorWordRight": "tui.editor.cursorWordRight"
    case "cursorLineStart": "tui.editor.cursorLineStart"
    case "cursorLineEnd": "tui.editor.cursorLineEnd"
    case "jumpForward": "tui.editor.jumpForward"
    case "jumpBackward": "tui.editor.jumpBackward"
    case "pageUp": "tui.editor.pageUp"
    case "pageDown": "tui.editor.pageDown"
    case "deleteCharBackward": "tui.editor.deleteCharBackward"
    case "deleteCharForward": "tui.editor.deleteCharForward"
    case "deleteWordBackward": "tui.editor.deleteWordBackward"
    case "deleteWordForward": "tui.editor.deleteWordForward"
    case "deleteToLineStart": "tui.editor.deleteToLineStart"
    case "deleteToLineEnd": "tui.editor.deleteToLineEnd"
    case "yank": "tui.editor.yank"
    case "yankPop": "tui.editor.yankPop"
    case "undo": "tui.editor.undo"
    case "newLine": "tui.input.newLine"
    case "submit": "tui.input.submit"
    case "tab": "tui.input.tab"
    case "copy": "tui.input.copy"
    case "selectUp": "tui.select.up"
    case "selectDown": "tui.select.down"
    case "selectPageUp": "tui.select.pageUp"
    case "selectPageDown": "tui.select.pageDown"
    case "selectConfirm": "tui.select.confirm"
    case "selectCancel": "tui.select.cancel"
    case "interrupt": "app.interrupt"
    case "clear": "app.clear"
    case "exit": "app.exit"
    case "suspend": "app.suspend"
    case "cycleThinkingLevel": "app.thinking.cycle"
    case "cycleModelForward": "app.model.cycleForward"
    case "cycleModelBackward": "app.model.cycleBackward"
    case "selectModel": "app.model.select"
    case "expandTools": "app.tools.expand"
    case "toggleThinking": "app.thinking.toggle"
    case "toggleSessionNamedFilter": "app.session.toggleNamedFilter"
    case "externalEditor": "app.editor.external"
    case "followUp": "app.message.followUp"
    case "dequeue": "app.message.dequeue"
    case "pasteImage": "app.clipboard.pasteImage"
    case "newSession": "app.session.new"
    case "tree": "app.session.tree"
    case "fork": "app.session.fork"
    case "resume": "app.session.resume"
    case "treeFoldOrUp": "app.tree.foldOrUp"
    case "treeUnfoldOrDown": "app.tree.unfoldOrDown"
    case "treeEditLabel": "app.tree.editLabel"
    case "treeToggleLabelTimestamp": "app.tree.toggleLabelTimestamp"
    case "toggleSessionPath": "app.session.togglePath"
    case "toggleSessionSort": "app.session.toggleSort"
    case "renameSession": "app.session.rename"
    case "deleteSession": "app.session.delete"
    case "deleteSessionNoninvasive": "app.session.deleteNoninvasive"
    case other: other

type Migration is Data:
  Migration{config: R.Record<V.Value>,migrated: Bool}
def present(-A: Data,value: Maybe<&2,A>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}
def migrateEntry(+name: String,+value: V.Value,+raw: R.Record<V.Value>,state: Migration) -> Migration:
  match state:
    case Migration{+config,+moved}:
      +next = migratedName(name)
      +changed = Bool.not(String.eq(name,next))
      Bool.pick(Unit -> Migration,changed && present(V.Value,R.get(V.Value,raw,next)),
        _ => Migration{config,True{}},
        _ => Migration{R.set(V.Value,config,next,value),moved || changed})(Unit{})
def migrateEntries(rows: List<&2,R.Property<V.Value>>,+raw: R.Record<V.Value>,state: Migration) -> Migration:
  match rows:
    case Nil{}: state
    case R.Property{name,value} <> rest: migrateEntries(rest,raw,migrateEntry(name,value,raw,state))
def knownEntries(definitions: List<&2,R.Property<Tui.KeybindingDefinition>>,+config: R.Record<V.Value>,+reversed: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<V.Value>>:
  match definitions:
    case Nil{}: List.reverse(&2,R.Property<V.Value>,reversed)
    case R.Property{+name,_} <> rest:
      knownEntries(rest,config,Maybe.default(&2,List<&2,R.Property<V.Value>>,Maybe.map(&2,V.Value,List<&2,R.Property<V.Value>>,value => R.Property{name,value} <> reversed,R.get(V.Value,config,name)),reversed))
def extraEntries(rows: List<&2,R.Property<V.Value>>,+definitions: Tui.KeybindingDefinitions(),+reversed: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<V.Value>>:
  match rows:
    case Nil{}: reversed
    case R.Property{+name,+value} <> rest: extraEntries(rest,definitions,Bool.pick(List<&2,R.Property<V.Value>>,present(Tui.KeybindingDefinition,R.get(Tui.KeybindingDefinition,definitions,name)),reversed,R.Property{name,value} <> reversed))
# Deterministic scalar order for extension action names, without host locale.
def nameBefore(left: String,right: String) -> Bool:
  match left right:
    case SNil{} _: True{}
    case _ SNil{}: False{}
    case SCon{+a,left} SCon{+b,right}: Bool.pick(Unit -> Bool,Char.is_eq(a,b),_ => nameBefore(left,right),_ => U32.is_lt(Char.to_u32(a),Char.to_u32(b)))(Unit{})
def entryBefore(left: R.Property<V.Value>,right: R.Property<V.Value>) -> Bool:
  match left right:
    case R.Property{a,_} R.Property{b,_}: nameBefore(a,b)
def orderedMigration(+definitions: Tui.KeybindingDefinitions(),state: Migration) -> Migration:
  match state:
    case Migration{+config,moved}: Migration{R.Record{List.append(&2,R.Property<V.Value>,knownEntries(R.entries(Tui.KeybindingDefinition,definitions),config,Nil{}),Sort.sort(~R.Property<V.Value>,~entryBefore,extraEntries(R.entries(V.Value,config),definitions,Nil{})))},moved}
def migrateKeybindingsConfig(environment: Environment,+raw: R.Record<V.Value>) -> Migration:
  orderedMigration(KEYBINDINGS(environment),migrateEntries(R.entries(V.Value,raw),raw,Migration{R.new(V.Value),False{}}))

type Error is Data:
  Filesystem{cause: FS.Error}
  Encoding{cause: Utf8.Error}
  InvalidJson{cause: Json.ParseError}
  InvalidRoot{}
  InvalidBinding{name: String}
  InvalidKey{name: String,identifier: String}
def identifierResult(+name: String,+identifier: String,value: Maybe<&2,Keys.KeyId>) -> Result<&2,&2,Error,Keys.KeyId>:
  match value:
    case None{}: Fail{InvalidKey{name,identifier}}
    case Some{key}: Done{key}
def decodeKey(+name: String,value: V.Value) -> Result<&2,&2,Error,Keys.KeyId>:
  match value:
    case V.Text{+identifier}: identifierResult(name,identifier,Keys.parseKeyId(identifier))
    case _: Fail{InvalidBinding{name}}
def decodeKeys(+name: String,values: List<&2,V.Value>,reversed: List<&2,Keys.KeyId>) -> Result<&2,&2,Error,List<&2,Keys.KeyId>>:
  match values:
    case Nil{}: Done{List.reverse(&2,Keys.KeyId,reversed)}
    case value <> rest:
      do Result<&2,&2,Error,List<&2,Keys.KeyId>>:
        key : Keys.KeyId <- decodeKey(name,value)
        decodeKeys(name,rest,key <> reversed)
def decodeBinding(name: String,value: V.Value) -> Result<&2,&2,Error,List<&2,Keys.KeyId>>:
  match value:
    case V.ArrayValue{values}: decodeKeys(name,values,Nil{})
    case value: decodeKeys(name,value <> Nil{},Nil{})
def decodeFields(values: List<&2,R.Property<V.Value>>,reversed: List<&2,R.Property<List<&2,Keys.KeyId>>>) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  match values:
    case Nil{}: Done{R.Record{List.reverse(&2,R.Property<List<&2,Keys.KeyId>>,reversed)}}
    case R.Property{+name,value} <> rest:
      do Result<&2,&2,Error,Tui.KeybindingsConfig()>:
        keys : List<&2,Keys.KeyId> <- decodeBinding(name,value)
        decodeFields(rest,R.Property{name,keys} <> reversed)
def decodeMigration(value: Migration) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  match value:
    case Migration{config,_}: decodeFields(R.entries(V.Value,config),Nil{})
def parsed(environment: Environment,value: Result<&2,&2,Json.ParseError,V.Value>) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  match value:
    case Fail{cause}: Fail{InvalidJson{cause}}
    case Done{V.ObjectValue{config}}: decodeMigration(migrateKeybindingsConfig(environment,config))
    case _: Fail{InvalidRoot{}}
def decodeConfig(environment: Environment,text: String) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  parsed(environment,Json.parse(text))
def decoded(environment: Environment,value: Result<&2,&2,Utf8.Error,String>) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  match value:
    case Fail{cause}: Fail{Encoding{cause}}
    case Done{text}: decodeConfig(environment,text)
def loaded(environment: Environment,value: Result<&2,&2,FS.Error,List<&2,U32>>) -> Result<&2,&2,Error,Tui.KeybindingsConfig()>:
  match value:
    case Fail{FS.System{2,_}}: Done{R.new(List<&2,Keys.KeyId>)}
    case Fail{cause}: Fail{Filesystem{cause}}
    case Done{bytes}: decoded(environment,Utf8.decodeStrict(bytes))
def loadFromFile(environment: Environment,path: String) -> IO(Result<&2,&2,Error,Tui.KeybindingsConfig()>):
  do IO<Result<&2,&2,Error,Tui.KeybindingsConfig()>>:
    value : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return loaded(environment,value)

type KeybindingsManager is Data:
  KeybindingsManager{bindings: Tui.KeybindingsManager,configPath: Maybe<&2,String>,environment: Environment}
def inMemory(+environment: Environment,bindings: Tui.KeybindingsConfig()) -> KeybindingsManager:
  KeybindingsManager{Tui.create(KEYBINDINGS(environment),bindings),None{},environment}
def fromLoaded(+environment: Environment,path: String,value: Result<&2,&2,Error,Tui.KeybindingsConfig()>) -> Result<&2,&2,Error,KeybindingsManager>:
  match value:
    case Fail{cause}: Fail{cause}
    case Done{bindings}: Done{KeybindingsManager{Tui.create(KEYBINDINGS(environment),bindings),Some{path},environment}}
def create(+environment: Environment,agentDir: String) -> IO(Result<&2,&2,Error,KeybindingsManager>):
  +path = Path.join(agentDir,"keybindings.json")
  do IO<Result<&2,&2,Error,KeybindingsManager>>:
    value : Result<&2,&2,Error,Tui.KeybindingsConfig()> <- loadFromFile(environment,path)
    return fromLoaded(environment,path,value)
def reloaded(manager: KeybindingsManager,value: Result<&2,&2,Error,Tui.KeybindingsConfig()>) -> Result<&2,&2,Error,KeybindingsManager>:
  match manager value:
    case _ Fail{cause}: Fail{cause}
    case KeybindingsManager{previous,path,environment} Done{bindings}: Done{KeybindingsManager{Tui.setUserBindings(previous,bindings),path,environment}}
def reload(manager: KeybindingsManager) -> IO(Result<&2,&2,Error,KeybindingsManager>):
  match manager:
    case KeybindingsManager{bindings,None{},environment}: IO.pure(Result<&2,&2,Error,KeybindingsManager>,Done{KeybindingsManager{bindings,None{},environment}})
    case KeybindingsManager{bindings,Some{+path},+environment}:
      do IO<Result<&2,&2,Error,KeybindingsManager>>:
        value : Result<&2,&2,Error,Tui.KeybindingsConfig()> <- loadFromFile(environment,path)
        return reloaded(KeybindingsManager{bindings,Some{path},environment},value)
def getEffectiveConfig(manager: KeybindingsManager) -> Tui.KeybindingsConfig():
  match manager:
    case KeybindingsManager{bindings,_,_}: Tui.getResolvedBindings(bindings)
