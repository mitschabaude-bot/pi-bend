import Base
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints
import ./extension-selector.bend as Selector

# Extension input shares the selector's frame, but retains the TUI Input's
# editing state so cursor movement, paste and IME placement use the same rules.
type State is Data:
  State{title: String,input: Input.Input,description: Maybe<&2,String>,remaining: Maybe<&2,Nat>}
type Action is Data: Continue{} Submit{value: String} Cancel{}

def create(title: String,initial: String,description: Maybe<&2,String>) -> State:
  State{title,Input.setFocused(Input.setValue(Input.new(None{}),initial),True{}),description,None{}}
def setRemaining(state: State,remaining: Nat) -> State:
  match state: case State{title,input,description,_}: State{title,input,description,Some{remaining}}
def value(state: State) -> String:
  match state: case State{_,input,_,_}: Input.getValue(input)
def nonAtomic(_: Words.Source,_: String) -> Bool: False{}
def edited(state: State,result: Word.ResultOf(Input.Input)) -> State & Action:
  match state result:
    case State{title,_,description,remaining} Done{input}: (State{title,input,description,remaining},Continue{})
    case state Fail{_}: (state,Continue{})
def otherInput(+state: State,source: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(State & Action):
  match state:
    case State{_,+input,_,_}:
      do IO<State & Action>:
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Words.Source,~Word.sourceSegments,~nonAtomic,source,input,bindings,keyboard,data)
        return edited(state,result)
def cancelInput(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),
    _ => IO.pure(State & Action,(state,Cancel{})),_ => otherInput(state,source,bindings,keyboard,data))(Unit{})
def handleInput(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.confirm") || String.eq(data,"\n"),
    _ => IO.pure(State & Action,(state,Submit{value(state)})),_ => cancelInput(state,source,bindings,keyboard,data))(Unit{})

def suffix(remaining: Maybe<&2,Nat>) -> String:
  match remaining: case None{}: "" case Some{seconds}: " (" ++ Nat.show(seconds) ++ "s)"
def rendered(state: State,pair: Input.Input & List<&2,String>,before: List<&2,String>,after: List<&2,String>) -> State & List<&2,String>:
  match state pair:
    case State{title,_,description,remaining} Tuple{input,lines}: (State{title,input,description,remaining},List.concat(&2,String,[before,lines,after]))
def render(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{+title,+input,+description,+remaining}:
      do IO<State & List<&2,String>>:
        heading : List<&2,String> <- Selector.textLine(Selector.color(theme,"accent",title ++ suffix(remaining)),width)
        detail : List<&2,String> <- Selector.descriptionRows(description,width,theme)
        pair : Input.Input & List<&2,String> <- Input.render(input,width)
        hint : String <- IO.pure(String,Hints.keyHint(theme,bindings,"tui.select.confirm","submit") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel"))
        keys : List<&2,String> <- Selector.textLine(hint,width)
        +rule : String <- IO.pure(String,Selector.border(width,theme))
        return rendered(State{title,input,description,remaining},pair,rule <> "" <> List.append(&2,String,heading,List.append(&2,String,detail,"" <> Nil{})),"" <> List.append(&2,String,keys,"" <> rule <> Nil{}))
