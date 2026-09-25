import Base
import ../core/project-trust.bend as Trust
import ../core/keybindings.bend as AppKeys
import ../core/settings-manager.bend as Settings
import ../modes/interactive/theme/theme.bend as Theme
import ../modes/interactive/theme/color.bend as Color
import ../modes/interactive/theme/detection.bend as Detection
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/deferred.bend as Deferred
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/ref.bend as Ref
import ../../../tui/src/component.bend as Component
import ../../../tui/src/keybindings.bend as Bindings
import ../../../tui/src/keys.bend as Keys
import ../../../tui/src/tui-base.bend as Tui
import ../../../tui/src/tui-main-screen.bend as Screen
import ../../../tui/src/tui-process.bend as Process
import ../../../tui/src/terminal.bend as Terminal
import ../../../tui/src/terminal-image.bend as Image
import ../../../tui/src/utils.bend as Utils

# A startup question owns the terminal only until the user chooses or cancels.
# The answer remains data; the trust policy and persistence live in core.
type State is Data:
  State{title: String,options: List<&2,String>,selected: Nat,answer: Maybe<&2,String>,done: Bool}
type Input is Data:
  Input{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,bindings: Bindings.KeybindingsManager}
type Paint is Data:
  Paint{state: Ref.Ref<State>,theme: Theme.Theme,bindings: Bindings.KeybindingsManager}
type Owner is Data:
  Owner{state: Ref.Ref<State>,stop: Deferred.Deferred<Unit>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,invalidate: Callback.Callback<Unit,Unit>,focus: Callback.Callback<Bool,Unit>}

def colored(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def border(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ border(rest)
def indent(parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: (" " ++ part) <> indent(rest)
def boldLines(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: ("\u{1b}[1m" ++ line ++ "\u{1b}[22m") <> boldLines(rest)
def titled(title: String,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  indent(Utils.wrapTextWithAnsi(colored(theme,"accent",String.join(boldLines(String.split(title,'\n')),"\n")),width - 2n))
def choices(options: List<&2,String>,+index: Nat,+selected: Nat,+theme: Theme.Theme) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case +option <> rest:
      +active = Nat.is_eq(index,selected)
      +line = Bool.pick(String,active," " ++ colored(theme,"accent","→ " ++ option),"   " ++ colored(theme,"text",option))
      line <> choices(rest,index + 1n,selected,theme)
def namedKey(keys: List<&2,Keys.KeyId>,name: String) -> String:
  match keys:
    case Nil{}: name
    case key <> Nil{}: Keys.formatKeyId(key)
    case key <> rest: Keys.formatKeyId(key) ++ "/" ++ namedKey(rest,name)
def firstKey(bindings: Bindings.KeybindingsManager,+name: String) -> String:
  namedKey(Bindings.getKeys(bindings,name),name)
def hint(+theme: Theme.Theme,key: String,description: String) -> String:
  colored(theme,"dim",key) ++ colored(theme,"muted"," " ++ description)
def lines(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> List<&2,String>:
  match state:
    case State{title,options,selected,_,_}:
      +rule = colored(theme,"border",border(width))
      +help = " " ++ hint(theme,"↑↓","navigate") ++ "  " ++ hint(theme,firstKey(bindings,"tui.select.confirm"),"select") ++ "  " ++ hint(theme,firstKey(bindings,"tui.select.cancel"),"cancel")
      rule <> "" <> List.append(&2,String,titled(title,theme,width),
        "" <> List.append(&2,String,choices(options,0n,selected,theme),
          "" <> help <> "" <> rule <> Nil{}))
def draw(paint: Paint,width: Nat) -> IO(List<&2,String>):
  match paint:
    case Paint{state,theme,bindings}:
      do IO<List<&2,String>>:
        current : State <- Ref.read(State,state)
        return lines(current,theme,bindings,width)
type Action is Data: Up{} Down{} Confirm{} Cancel{} Ignore{}
def action(+data: String,+bindings: Bindings.KeybindingsManager) -> Action:
  Bool.pick(Unit -> Action,Bindings.matches(bindings,Keys.defaults(),data,"tui.select.up") || String.eq(data,"k"),
    _ => Up{},_ => Bool.pick(Unit -> Action,Bindings.matches(bindings,Keys.defaults(),data,"tui.select.down") || String.eq(data,"j"),
      _ => Down{},_ => Bool.pick(Unit -> Action,Bindings.matches(bindings,Keys.defaults(),data,"tui.select.confirm") || String.eq(data,"\n"),
        _ => Confirm{},_ => Bool.pick(Action,Bindings.matches(bindings,Keys.defaults(),data,"tui.select.cancel"),Cancel{},Ignore{}))(Unit{}))(Unit{}))(Unit{})
def step(state: State,action: Action) -> State & Bool:
  match state action:
    case State{title,options,index,answer,True{}} _: (State{title,options,index,answer,True{}},False{})
    case State{title,options,index,_,False{}} Up{}: (State{title,options,index - 1n,None{},False{}},False{})
    case State{title,+options,index,_,False{}} Down{}: (State{title,options,Nat.min(index + 1n,List.length(&2,String,options) - 1n),None{},False{}},False{})
    case State{title,+options,+index,_,False{}} Confirm{}: (State{title,options,index,List.get(&2,String,options,index),True{}},True{})
    case State{title,options,index,_,False{}} Cancel{}: (State{title,options,index,None{},True{}},True{})
    case State{title,options,index,_,False{}} Ignore{}: (State{title,options,index,None{},False{}},False{})
def received(input: Input,data: String) -> IO(Unit):
  match input:
    case Input{state,stop,bindings}:
      do IO<Unit>:
        finished : Bool <- Ref.modify(State,Bool,state,current => step(current,action(data,bindings)))
        Bool.pick(Unit -> IO(Unit),finished,_ => do IO<Unit>:
          resolved : Bool <- Deferred.resolve(Unit,stop,Unit{})
          return Unit{},_ => IO.pure(Unit,Unit{}))(Unit{})
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def unfocused(_: Unit,_: Bool) -> IO(Unit): IO.pure(Unit,Unit{})
def new(title: String,options: List<&2,String>,theme: Theme.Theme,+bindings: Bindings.KeybindingsManager) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<State> <- Ref.new(State,State{title,options,0n,None{},False{}})
    +stop : Deferred.Deferred<Unit> <- Deferred.new(Unit)
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Paint,~Nat,~List<&2,String>,~draw,Paint{state,theme,bindings})
    +input : Callback.Callback<String,Unit> <- Callback.create(~Input,~String,~Unit,~received,Input{state,stop,bindings})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    +focus : Callback.Callback<Bool,Unit> <- Callback.create(~Unit,~Bool,~Unit,~unfocused,Unit{})
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.ComponentId{1n},render,Some{input},None{},invalidate,Some{focus},False{}})
    return Owner{state,stop,component,render,input,invalidate,focus}
def terminalError(error: Terminal.Error) -> String:
  match error:
    case Terminal.System{operation,_,message}: "Terminal " ++ operation ++ ": " ++ message
    case _: "Cannot start startup selector terminal"
def settled(outcome: Result<&2,&2,Terminal.Error,Process.Active>,final: State) -> Result<&2,&2,String,Maybe<&2,String>>:
  match outcome final:
    case Fail{error} _: Fail{terminalError(error)}
    case Done{_} State{_,_,_,answer,_}: Done{answer}
def finish(owner: Owner,outcome: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  match owner:
    case Owner{state,stop,_,render,input,invalidate,focus}:
      do IO<Result<&2,&2,String,Maybe<&2,String>>>:
        final : State <- Ref.dispose(State,state)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,input)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(Bool,Unit,focus)
        Deferred.dispose(Unit,stop)
        return settled(outcome,final)
def clearPrompt(outcome: Result<&2,&2,Terminal.Error,Process.Active>) -> IO(Unit):
  match outcome:
    case Done{_}: IO.write("\u{1b}[2J\u{1b}[H")
    case Fail{_}: IO.pure(Unit,Unit{})
def mounted(owner: Owner,base: Tui.ResultOf(Tui.TuiBase)) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  match owner base:
    case owner Fail{_}: finish(owner,Fail{Terminal.Closed{}})
    case Owner{state,+stop,+component,render,input,invalidate,focus} Done{tui}:
      do IO<Result<&2,&2,String,Maybe<&2,String>>>:
        +outcome : Result<&2,&2,Terminal.Error,Process.Active> <- Process.runProcess(Process.active(Process.Session{tui,Process.Main{Screen.initial()}},[component],[Component.ComponentId{1n}]),stop,False{})
        clearPrompt(outcome)
        finish(Owner{state,stop,component,render,input,invalidate,focus},outcome)
def run(owner: Owner) -> IO(Result<&2,&2,String,Maybe<&2,String>>):
  match owner:
    case Owner{state,stop,+component,render,input,invalidate,focus}:
      do IO<Result<&2,&2,String,Maybe<&2,String>>>:
        base : Tui.ResultOf(Tui.TuiBase) <- Tui.setFocus(Tui.added(Tui.newTui(),component),[component],[Component.ComponentId{1n}],Some{Component.ComponentId{1n}})
        mounted(Owner{state,stop,component,render,input,invalidate,focus},base)
def withTheme(request: Trust.SelectRequest,bindings: Bindings.KeybindingsManager,theme: Theme.Theme) -> IO(Maybe<&2,String>):
  match request:
    case Trust.SelectRequest{title,options}:
      do IO<Maybe<&2,String>>:
        owner : Owner <- new(title,options,theme,bindings)
        outcome : Result<&2,&2,String,Maybe<&2,String>> <- run(owner)
        return Result.default(&2,&2,String,Maybe<&2,String>,outcome,None{})
def loaded(request: Trust.SelectRequest,keys: Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager>,theme: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Maybe<&2,String>):
  match keys theme:
    case Done{AppKeys.KeybindingsManager{bindings,_,_}} Done{ready}: withTheme(request,bindings,ready)
    case _ _: IO.pure(Maybe<&2,String>,None{})
def envValue(value: Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match value:
    case Done{text}: Some{text}
    case Fail{_}: None{}
def terminalName(theme: Detection.TerminalTheme) -> String:
  match theme:
    case Detection.Dark{}: "dark"
    case Detection.Light{}: "light"
def themeName(setting: Maybe<&2,String>,background: Maybe<&2,String>) -> String:
  +detected = Detection.detectionTheme(Detection.detectTerminalBackgroundFromEnv(background))
  Maybe.default(&2,String,Detection.resolveThemeSetting(setting,detected),terminalName(detected))
def trueColorOverride(capabilities: Settings.TerminalCapabilities) -> Maybe<&2,Bool>:
  match capabilities: case Settings.TerminalCapabilities{_,color,_}: color
def select(request: Trust.SelectRequest,+agentDir: String,assetsRoot: String,+settings: Settings.SettingsManager) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    keys : Result<&2,&2,AppKeys.Error,AppKeys.KeybindingsManager> <- AppKeys.create(AppKeys.Environment{"linux",None{},None{}},agentDir)
    background : Result<&1,&1,U32 & String,String> <- IO.get_env("COLORFGBG")
    home : Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
    environment : Image.Environment <- Image.processEnvironment("linux",Maybe.default(&2,String,envValue(home),""))
    mode : Color.Mode <- IO.pure(Color.Mode,Color.modeFor(Image.trueColor(environment,trueColorOverride(Settings.getTerminalCapabilityOverrides(settings)))))
    theme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadByName(themeName(Settings.getThemeSetting(settings),envValue(background)),Path.join(assetsRoot,"packages/coding-agent/src/modes/interactive/theme"),Path.join(agentDir,"themes"),mode)
    loaded(request,keys,theme)
