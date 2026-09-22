import Base
import ./keys.bend as Keys
import ../../runtime/src/record.bend as R

# Extensible action names map to native keys. Owners pass their manager
# explicitly; replacing user bindings produces a new immutable configuration.
type KeybindingDefinition is Data:
  KeybindingDefinition{defaultKeys: List<&2,Keys.KeyId>, description: Maybe<&2,String>}
type KeybindingConflict is Data:
  KeybindingConflict{key: Keys.KeyId, keybindings: List<&2,String>}
def KeybindingDefinitions() -> Data: R.Record<KeybindingDefinition>
def KeybindingsConfig() -> Data: R.Record<List<&2,Keys.KeyId>>
type KeybindingsManager is Data:
  KeybindingsManager{definitions: KeybindingDefinitions(), userBindings: KeybindingsConfig(), resolved: KeybindingsConfig(), conflicts: List<&2,KeybindingConflict>}

def contains(keys: List<&2,Keys.KeyId>,+name: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case key <> rest: Bool.pick(Unit -> Bool,String.eq(Keys.formatKeyId(key),name),_ => True{},_ => contains(rest,name))(Unit{})
def unique(keys: List<&2,Keys.KeyId>,+reversed: List<&2,Keys.KeyId>) -> List<&2,Keys.KeyId>:
  match keys:
    case Nil{}: List.reverse(&2,Keys.KeyId,reversed)
    case +key <> rest: unique(rest,Bool.pick(List<&2,Keys.KeyId>,contains(reversed,Keys.formatKeyId(key)),reversed,key <> reversed))
def normalizeKeys(keys: List<&2,Keys.KeyId>) -> List<&2,Keys.KeyId>:
  unique(keys,Nil{})

def claimants(previous: Maybe<&2,KeybindingConflict>,key: Keys.KeyId,action: String) -> KeybindingConflict:
  match previous:
    case None{}: KeybindingConflict{key,action <> Nil{}}
    case Some{KeybindingConflict{key,actions}}: KeybindingConflict{key,List.append(&2,String,actions,action <> Nil{})}
def claimKeys(keys: List<&2,Keys.KeyId>,+action: String,+claims: R.Record<KeybindingConflict>) -> R.Record<KeybindingConflict>:
  match keys:
    case Nil{}: claims
    case +key <> rest:
      +name = Keys.formatKeyId(key)
      claimKeys(rest,action,R.set(KeybindingConflict,claims,name,claimants(R.get(KeybindingConflict,claims,name),key,action)))
def userClaims(bindings: List<&2,R.Property<List<&2,Keys.KeyId>>>,+definitions: KeybindingDefinitions(),+claims: R.Record<KeybindingConflict>) -> R.Record<KeybindingConflict>:
  match bindings:
    case Nil{}: claims
    case R.Property{+action,keys} <> rest:
      userClaims(rest,definitions,Maybe.default(&2,R.Record<KeybindingConflict>,Maybe.map(&2,KeybindingDefinition,R.Record<KeybindingConflict>,_ => claimKeys(normalizeKeys(keys),action,claims),R.get(KeybindingDefinition,definitions,action)),claims))
def conflicting(value: KeybindingConflict) -> Bool:
  match value:
    case KeybindingConflict{_,_ <> _ <> _}: True{}
    case _: False{}
def collectConflicts(claims: List<&2,R.Property<KeybindingConflict>>,+reversed: List<&2,KeybindingConflict>) -> List<&2,KeybindingConflict>:
  match claims:
    case Nil{}: List.reverse(&2,KeybindingConflict,reversed)
    case R.Property{_,+value} <> rest: collectConflicts(rest,Bool.pick(List<&2,KeybindingConflict>,conflicting(value),value <> reversed,reversed))
def resolve(definitions: List<&2,R.Property<KeybindingDefinition>>,+bindings: KeybindingsConfig(),reversed: List<&2,R.Property<List<&2,Keys.KeyId>>>) -> KeybindingsConfig():
  match definitions:
    case Nil{}: R.Record{List.reverse(&2,R.Property<List<&2,Keys.KeyId>>,reversed)}
    case R.Property{+action,KeybindingDefinition{defaults,_}} <> rest:
      resolve(rest,bindings,R.Property{action,normalizeKeys(Maybe.default(&2,List<&2,Keys.KeyId>,R.get(List<&2,Keys.KeyId>,bindings,action),defaults))} <> reversed)

def create(+definitions: KeybindingDefinitions(),+userBindings: KeybindingsConfig()) -> KeybindingsManager:
  KeybindingsManager{definitions,userBindings,resolve(R.entries(KeybindingDefinition,definitions),userBindings,Nil{}),collectConflicts(R.entries(KeybindingConflict,userClaims(R.entries(List<&2,Keys.KeyId>,userBindings),definitions,R.new(KeybindingConflict))),Nil{})}
def getKeys(manager: KeybindingsManager,action: String) -> List<&2,Keys.KeyId>:
  match manager:
    case KeybindingsManager{_,_,resolved,_}: Maybe.default(&2,List<&2,Keys.KeyId>,R.get(List<&2,Keys.KeyId>,resolved,action),Nil{})
def getDefinition(manager: KeybindingsManager,action: String) -> Maybe<&2,KeybindingDefinition>:
  match manager:
    case KeybindingsManager{definitions,_,_,_}: R.get(KeybindingDefinition,definitions,action)
def getConflicts(manager: KeybindingsManager) -> List<&2,KeybindingConflict>:
  match manager:
    case KeybindingsManager{_,_,_,conflicts}: conflicts
def getUserBindings(manager: KeybindingsManager) -> KeybindingsConfig():
  match manager:
    case KeybindingsManager{_,bindings,_,_}: bindings
def getResolvedBindings(manager: KeybindingsManager) -> KeybindingsConfig():
  match manager:
    case KeybindingsManager{_,_,resolved,_}: resolved
def setUserBindings(manager: KeybindingsManager,bindings: KeybindingsConfig()) -> KeybindingsManager:
  match manager:
    case KeybindingsManager{definitions,_,_,_}: create(definitions,bindings)
def matchKeys(keys: List<&2,Keys.KeyId>,+context: Keys.Context,+data: String) -> Bool:
  match keys:
    case Nil{}: False{}
    case key <> rest: Bool.pick(Unit -> Bool,Keys.matchesKey(context,data,key),_ => True{},_ => matchKeys(rest,context,data))(Unit{})
def matches(manager: KeybindingsManager,context: Keys.Context,data: String,action: String) -> Bool:
  matchKeys(getKeys(manager,action),context,data)

# Defaults and descriptions from pinned pi-mono TUI_KEYBINDINGS.
def TUI_KEYBINDINGS() -> KeybindingDefinitions():
  R.Record{
    R.Property{"tui.editor.cursorUp",KeybindingDefinition{Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Move cursor up"}}} <>
    R.Property{"tui.editor.cursorDown",KeybindingDefinition{Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Move cursor down"}}} <>
    R.Property{"tui.editor.historyPrevious",KeybindingDefinition{Nil{},Some{"Select previous prompt history entry"}}} <>
    R.Property{"tui.editor.historyNext",KeybindingDefinition{Nil{},Some{"Select next prompt history entry"}}} <>
    R.Property{"tui.editor.cursorLeft",KeybindingDefinition{Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'b'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Move cursor left"}}} <>
    R.Property{"tui.editor.cursorRight",KeybindingDefinition{Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'f'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Move cursor right"}}} <>
    R.Property{"tui.editor.cursorWordLeft",KeybindingDefinition{Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},True{},False{},False{}}} <> Keys.KeyId{Keys.Left{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Printable{'b'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Move cursor word left"}}} <>
    R.Property{"tui.editor.cursorWordRight",KeybindingDefinition{Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},True{},False{},False{}}} <> Keys.KeyId{Keys.Right{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Printable{'f'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Move cursor word right"}}} <>
    R.Property{"tui.editor.cursorLineStart",KeybindingDefinition{Keys.KeyId{Keys.Home{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Home{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Printable{'a'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Move to line start"}}} <>
    R.Property{"tui.editor.cursorLineEnd",KeybindingDefinition{Keys.KeyId{Keys.End{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.End{},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Printable{'e'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Move to line end"}}} <>
    R.Property{"tui.editor.jumpForward",KeybindingDefinition{Keys.KeyId{Keys.Printable{']'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Jump forward to character"}}} <>
    R.Property{"tui.editor.jumpBackward",KeybindingDefinition{Keys.KeyId{Keys.Printable{']'},Keys.Modifiers{False{},True{},True{},False{}}} <> Nil{},Some{"Jump backward to character"}}} <>
    R.Property{"tui.editor.pageUp",KeybindingDefinition{Keys.KeyId{Keys.PageUp{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.PageUp{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Page up"}}} <>
    R.Property{"tui.editor.pageDown",KeybindingDefinition{Keys.KeyId{Keys.PageDown{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.PageDown{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Page down"}}} <>
    R.Property{"tui.editor.deleteCharBackward",KeybindingDefinition{Keys.KeyId{Keys.Backspace{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Delete character backward"}}} <>
    R.Property{"tui.editor.deleteCharForward",KeybindingDefinition{Keys.KeyId{Keys.Delete{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'d'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Delete character forward"}}} <>
    R.Property{"tui.editor.deleteWordBackward",KeybindingDefinition{Keys.KeyId{Keys.Printable{'w'},Keys.Modifiers{False{},False{},True{},False{}}} <> Keys.KeyId{Keys.Backspace{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Delete word backward"}}} <>
    R.Property{"tui.editor.deleteWordForward",KeybindingDefinition{Keys.KeyId{Keys.Printable{'d'},Keys.Modifiers{False{},True{},False{},False{}}} <> Keys.KeyId{Keys.Delete{},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Delete word forward"}}} <>
    R.Property{"tui.editor.deleteToLineStart",KeybindingDefinition{Keys.KeyId{Keys.Printable{'u'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Delete to line start"}}} <>
    R.Property{"tui.editor.deleteToLineEnd",KeybindingDefinition{Keys.KeyId{Keys.Printable{'k'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Delete to line end"}}} <>
    R.Property{"tui.editor.yank",KeybindingDefinition{Keys.KeyId{Keys.Printable{'y'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Yank"}}} <>
    R.Property{"tui.editor.yankPop",KeybindingDefinition{Keys.KeyId{Keys.Printable{'y'},Keys.Modifiers{False{},True{},False{},False{}}} <> Nil{},Some{"Yank pop"}}} <>
    R.Property{"tui.editor.undo",KeybindingDefinition{Keys.KeyId{Keys.Printable{'-'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Undo"}}} <>
    R.Property{"tui.input.newLine",KeybindingDefinition{Keys.KeyId{Keys.Enter{},Keys.Modifiers{True{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'j'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Insert newline"}}} <>
    R.Property{"tui.input.submit",KeybindingDefinition{Keys.KeyId{Keys.Enter{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Submit input"}}} <>
    R.Property{"tui.input.tab",KeybindingDefinition{Keys.KeyId{Keys.Tab{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Tab / autocomplete"}}} <>
    R.Property{"tui.input.copy",KeybindingDefinition{Keys.KeyId{Keys.Printable{'c'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Copy selection"}}} <>
    R.Property{"tui.select.up",KeybindingDefinition{Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Move selection up"}}} <>
    R.Property{"tui.select.down",KeybindingDefinition{Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Move selection down"}}} <>
    R.Property{"tui.select.pageUp",KeybindingDefinition{Keys.KeyId{Keys.PageUp{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Selection page up"}}} <>
    R.Property{"tui.select.pageDown",KeybindingDefinition{Keys.KeyId{Keys.PageDown{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Selection page down"}}} <>
    R.Property{"tui.select.confirm",KeybindingDefinition{Keys.KeyId{Keys.Enter{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Confirm selection"}}} <>
    R.Property{"tui.select.cancel",KeybindingDefinition{Keys.KeyId{Keys.Escape{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'c'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Cancel selection"}}} <>
    R.Property{"tui.altScreen.pageUp",KeybindingDefinition{Keys.KeyId{Keys.PageUp{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Scroll viewport up one page"}}} <>
    R.Property{"tui.altScreen.pageDown",KeybindingDefinition{Keys.KeyId{Keys.PageDown{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Scroll viewport down one page"}}} <>
    R.Property{"tui.altScreen.halfPageUp",KeybindingDefinition{Nil{},Some{"Scroll viewport up half a page"}}} <>
    R.Property{"tui.altScreen.halfPageDown",KeybindingDefinition{Nil{},Some{"Scroll viewport down half a page"}}} <>
    R.Property{"tui.altScreen.lineUp",KeybindingDefinition{Nil{},Some{"Scroll viewport up one line"}}} <>
    R.Property{"tui.altScreen.lineDown",KeybindingDefinition{Nil{},Some{"Scroll viewport down one line"}}} <>
    R.Property{"tui.altScreen.previousPrompt",KeybindingDefinition{Keys.KeyId{Keys.Up{},Keys.Modifiers{True{},False{},True{},False{}}} <> Keys.KeyId{Keys.Up{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Jump to previous semantic prompt"}}} <>
    R.Property{"tui.altScreen.nextPrompt",KeybindingDefinition{Keys.KeyId{Keys.Down{},Keys.Modifiers{True{},False{},True{},False{}}} <> Keys.KeyId{Keys.Down{},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Jump to next semantic prompt"}}} <>
    R.Property{"tui.altScreen.search",KeybindingDefinition{Keys.KeyId{Keys.Printable{'f'},Keys.Modifiers{True{},False{},True{},False{}}} <> Nil{},Some{"Search the primary scroll view"}}} <>
    R.Property{"tui.altScreen.searchNext",KeybindingDefinition{Keys.KeyId{Keys.Enter{},Keys.Modifiers{False{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'g'},Keys.Modifiers{False{},False{},True{},False{}}} <> Nil{},Some{"Select the next search match"}}} <>
    R.Property{"tui.altScreen.searchPrevious",KeybindingDefinition{Keys.KeyId{Keys.Enter{},Keys.Modifiers{True{},False{},False{},False{}}} <> Keys.KeyId{Keys.Printable{'g'},Keys.Modifiers{True{},False{},True{},False{}}} <> Nil{},Some{"Select the previous search match"}}} <>
    R.Property{"tui.altScreen.searchClose",KeybindingDefinition{Keys.KeyId{Keys.Escape{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Close transcript search"}}} <>
    R.Property{"tui.altScreen.top",KeybindingDefinition{Keys.KeyId{Keys.Home{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Scroll viewport to top"}}} <>
    R.Property{"tui.altScreen.bottom",KeybindingDefinition{Keys.KeyId{Keys.End{},Keys.Modifiers{False{},False{},False{},False{}}} <> Nil{},Some{"Scroll viewport to bottom"}}} <> Nil{}}
