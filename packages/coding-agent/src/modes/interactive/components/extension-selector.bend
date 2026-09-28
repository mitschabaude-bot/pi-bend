import Base
import ../../../../../tui/src/components/text.bend as Text
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints

# The selector's visible state. The host owns its callbacks and optional timer;
# input and rendering stay independent of the terminal event loop.
type State is Data:
  State{title: String,options: List<&2,String>,selected: Nat,description: Maybe<&2,String>,remaining: Maybe<&2,Nat>}
type Action is Data: Continue{} Select{value: String} Cancel{} ToggleTools{}

def create(title: String,options: List<&2,String>,description: Maybe<&2,String>) -> State:
  State{title,options,0n,description,None{}}
def setRemaining(state: State,remaining: Nat) -> State:
  match state: case State{title,options,selected,description,_}: State{title,options,selected,description,Some{remaining}}
def selected(state: State) -> Maybe<&2,String>:
  match state: case State{_,options,index,_,_}: List.get(&2,String,options,index)
def moved(state: State,up: Bool) -> State:
  match state:
    case State{title,+options,+index,description,remaining}:
      +last = List.length(&2,String,options) - 1n
      State{title,options,Bool.pick(Nat,up,index - 1n,Nat.min(index + 1n,last)),description,remaining}
def chosen(value: Maybe<&2,String>) -> Action:
  match value: case None{}: Continue{} case Some{item}: Select{item}
def cancelInput(+state: State,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> State & Action:
  Bool.pick(State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),(state,Cancel{}),(state,Continue{}))
def selectionInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm") || String.eq(data,"\n"),
    _ => (state,chosen(selected(state))),_ => cancelInput(state,bindings,keyboard,data))(Unit{})
def motionInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down") || String.eq(data,"j"),
    _ => (moved(state,False{}),Continue{}),_ => selectionInput(state,bindings,keyboard,data))(Unit{})
def boundInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up") || String.eq(data,"k"),
    _ => (moved(state,True{}),Continue{}),_ => motionInput(state,bindings,keyboard,data))(Unit{})
def handleInput(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"app.tools.expand"),
    _ => (state,ToggleTools{}),_ => boundInput(state,bindings,keyboard,data))(Unit{})

def color(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def titleLines(lines: List<&2,String>,+theme: Theme.Theme,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: titleLines(rest,theme,color(theme,"accent",Theme.bold(line)) <> reversed)
def border(width: Nat,theme: Theme.Theme) -> String:
  color(theme,"border",String.repeat("─",Nat.max(1n,width)))
def textRows(pair: Text.Text & List<&2,String>) -> List<&2,String>:
  match pair: case (_,rows): rows
def textLine(value: String,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    pair : Text.Text & List<&2,String> <- Text.render(Text.new(value,Some{1n},Some{0n},None{}),width)
    return textRows(pair)
def optionRows(options: List<&2,String>,+index: Nat,+selected: Nat,+width: Nat,+theme: Theme.Theme) -> IO(List<&2,String>):
  match options:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case +value <> rest:
      do IO<List<&2,String>>:
        current : List<&2,String> <- textLine(Bool.pick(String,Nat.is_eq(index,selected),color(theme,"accent","→ " ++ value),"  " ++ color(theme,"text",value)),width)
        more : List<&2,String> <- optionRows(rest,index + 1n,selected,width,theme)
        return List.append(&2,String,current,more)
def descriptionRows(value: Maybe<&2,String>,width: Nat,theme: Theme.Theme) -> IO(List<&2,String>):
  match value:
    case None{}: IO.pure(List<&2,String>,Nil{})
    case Some{body}:
      do IO<List<&2,String>>:
        rows : List<&2,String> <- textLine(color(theme,"text",body),width)
        return "" <> rows
def remainingSuffix(remaining: Maybe<&2,Nat>) -> String:
  match remaining: case None{}: "" case Some{seconds}: " (" ++ Nat.show(seconds) ++ "s)"
def render(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> IO(List<&2,String>):
  match state:
    case State{heading,options,index,description,remaining}:
      do IO<List<&2,String>>:
        headingRows : List<&2,String> <- textLine(String.join(titleLines(String.split(heading ++ remainingSuffix(remaining),'\n'),theme,Nil{}),"\n"),width)
        detail : List<&2,String> <- descriptionRows(description,width,theme)
        choices : List<&2,String> <- optionRows(options,0n,index,width,theme)
        hint : String <- IO.pure(String,Hints.rawKeyHint(theme,"↑↓","navigate") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.confirm","select") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel"))
        keys : List<&2,String> <- textLine(hint,width)
        +rule : String <- IO.pure(String,border(width,theme))
        return rule <> "" <> List.append(&2,String,headingRows,List.append(&2,String,detail,"" <> List.append(&2,String,choices,"" <> List.append(&2,String,keys,"" <> rule <> Nil{}))))
