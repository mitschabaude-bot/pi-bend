import Base
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../tui/src/components/editor.bend as Editor
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints
import ./extension-selector.bend as Selector

# A multiline extension prompt. Opening an external editor is a host action:
# the terminal owner suspends, edits, then replaces this Editor's text.
type State is Data:
  State{title: String,editor: Editor.Editor,description: Maybe<&2,String>}
type Action is Data: Continue{} Submit{value: String} Cancel{} External{content: String}

def create(title: String,prefill: String,description: Maybe<&2,String>,theme: Editor.EditorTheme,options: Maybe<&2,Editor.EditorOptions>) -> IO(State):
  do IO<State>:
    initial : Editor.Editor <- Editor.new(theme,options)
    prepared : Editor.Editor <- Editor.setText(initial,prefill)
    return State{title,Editor.setFocused(prepared,True{}),description}
def setText(state: State,text: String) -> IO(State):
  match state:
    case State{title,editor,description}:
      do IO<State>:
        changed : Editor.Editor <- Editor.setText(editor,text)
        return State{title,changed,description}
def value(state: State) -> String:
  match state: case State{_,editor,_}: Editor.getText(editor)
def edited(state: State,result: Editor.ResultOf(Editor.Editor)) -> State & Action:
  match state result:
    case State{title,_,description} Done{editor}: (State{title,editor,description},Continue{})
    case state Fail{_}: (state,Continue{})
def forwarded(+state: State,source: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String,rows: Nat) -> IO(State & Action):
  match state:
    case State{_,+editor,_}:
      do IO<State & Action>:
        result : Editor.ResultOf(Editor.Editor) <- Editor.handleInput(~Words.Source,~Word.sourceSegments,source,editor,bindings,keyboard,data,rows)
        return edited(state,result)
def externalInput(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String,rows: Nat) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"app.editor.external"),
    _ => IO.pure(State & Action,(state,External{value(state)})),_ => forwarded(state,source,bindings,keyboard,data,rows))(Unit{})
def submitInput(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String,rows: Nat) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.confirm") || String.eq(data,"\n"),
    _ => IO.pure(State & Action,(state,Submit{value(state)})),_ => externalInput(state,source,bindings,keyboard,data,rows))(Unit{})
def handleInput(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String,rows: Nat) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),
    _ => IO.pure(State & Action,(state,Cancel{})),_ => submitInput(state,source,bindings,keyboard,data,rows))(Unit{})

def rendered(state: State,pair: Editor.Editor & List<&2,String>,before: List<&2,String>,after: List<&2,String>) -> State & List<&2,String>:
  match state pair:
    case State{title,_,description} Tuple{editor,lines}: (State{title,editor,description},List.concat(&2,String,[before,lines,after]))
def render(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat,rows: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{+title,+editor,+description}:
      do IO<State & List<&2,String>>:
        heading : List<&2,String> <- Selector.textLine(Selector.color(theme,"accent",title),width)
        detail : List<&2,String> <- Selector.descriptionRows(description,width,theme)
        pair : Editor.Editor & List<&2,String> <- Editor.render(editor,width,rows)
        hint : String <- IO.pure(String,Hints.keyHint(theme,bindings,"tui.select.confirm","submit") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.input.newLine","newline") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel") ++ "  " ++ Hints.keyHint(theme,bindings,"app.editor.external","external editor"))
        keys : List<&2,String> <- Selector.textLine(hint,width)
        +rule : String <- IO.pure(String,Selector.border(width,theme))
        return rendered(State{title,editor,description},pair,rule <> "" <> List.append(&2,String,heading,List.append(&2,String,detail,"" <> Nil{})),"" <> List.append(&2,String,keys,"" <> rule <> Nil{}))
