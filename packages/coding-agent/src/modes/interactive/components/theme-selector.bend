import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/filesystem.bend as FS
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../tui/src/components/settings-list.bend as SettingsList
import ../transcript.bend as Transcript
import ../theme/detection.bend as Detection
import ../theme/theme.bend as Theme
import ../theme/theme-controller.bend as Controller

# The theme submenu keeps selection and preview separate: moving changes only
# the live palette; Enter persists through SettingsList, and Escape restores.
type Stage is Data: Single{} Automatic{} PickLight{} PickDark{}
type State is Data:
  State{original: Maybe<&2,String>,current: String,available: List<&2,String>,single: String,light: String,dark: String,terminal: Detection.TerminalTheme,stage: Stage,index: Nat,done: SettingsList.SubmenuDone}
type Modal is Data: Closed{} Open{state: State}
type Action is Data: Continue{} Preview{name: String} Finish{setting: String} Cancel{}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,theme: Ref.Ref<Theme.Theme>,controller: Ref.Ref<Maybe<&2,Controller.Handle>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context}
type Factory is Data: Factory{host: Host,component: Component.Component}
type Owner is Data:
  Owner{host: Host,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,input: Callback.Callback<String,Unit>,invalidate: Callback.Callback<Unit,Unit>,factory: Callback.Callback<SettingsList.SubmenuRequest,Component.Component>}

def contains(names: List<&2,String>,+wanted: String) -> Bool:
  match names:
    case Nil{}: False{}
    case candidate <> rest: String.eq(candidate,wanted) || contains(rest,wanted)
def preferred(+available: List<&2,String>,+wanted: String,+fallback: String) -> String:
  Bool.pick(Unit -> String,contains(available,wanted),_ => wanted,
    _ => Bool.pick(String,contains(available,fallback),fallback,Maybe.default(&2,String,List.head(&2,String,available),fallback)))(Unit{})
def automaticNames(setting: Maybe<&2,Detection.AutoSetting>,+fixed: String) -> String & String:
  match setting:
    case Some{Detection.AutoSetting{light,dark}}: (light,dark)
    case None{}: (fixed,fixed)
def initialStage(setting: Maybe<&2,Detection.AutoSetting>) -> Stage:
  match setting:
    case Some{_}: Automatic{}
    case None{}: Single{}
def nameIndex(names: List<&2,String>,+wanted: String,+index: Nat) -> Nat:
  match names:
    case Nil{}: 0n
    case candidate <> rest: Bool.pick(Unit -> Nat,String.eq(candidate,wanted),_ => index,_ => nameIndex(rest,wanted,index + 1n))(Unit{})
def terminalLight(terminal: Detection.TerminalTheme) -> Bool:
  match terminal:
    case Detection.Light{}: True{}
    case Detection.Dark{}: False{}
def initialStateNames(setting: Maybe<&2,String>,+current: String,+available: List<&2,String>,+terminal: Detection.TerminalTheme,done: SettingsList.SubmenuDone,+auto: Maybe<&2,Detection.AutoSetting>,pair: String & String) -> State:
  match pair:
    case (+light,+dark):
      +single = preferred(available,Bool.pick(String,terminalLight(terminal),light,dark),"dark")
      +stage = initialStage(auto)
      +index = Bool.pick(Nat,Controller.isAuto(Some{current}),0n,nameIndex(available,single,1n))
      State{setting,current,available,single,light,dark,terminal,stage,index,done}
def initialState(setting: Maybe<&2,String>,+current: String,+available: List<&2,String>,terminal: Detection.TerminalTheme,done: SettingsList.SubmenuDone) -> State:
  +auto = Detection.parseAutoThemeSetting(Some{current})
  +fixed = preferred(available,current,"dark")
  initialStateNames(setting,current,available,terminal,done,auto,automaticNames(auto,fixed))
def active(light: String,dark: String,terminal: Detection.TerminalTheme) -> String:
  match terminal:
    case Detection.Light{}: light
    case Detection.Dark{}: dark
def menuLength(+state: State) -> Nat:
  match state:
    case State{_,_,available,_,_,_,_,Single{},_,_}: List.length(&2,String,available) + 1n
    case State{_,_,_,_,_,_,_,Automatic{},_,_}: 4n
    case State{_,_,available,_,_,_,_,_,_,_}: List.length(&2,String,available)
def withIndex(+state: State,index: Nat) -> State:
  match state:
    case State{original,current,available,single,light,dark,terminal,stage,_,done}: State{original,current,available,single,light,dark,terminal,stage,index,done}
def moved(+state: State,up: Bool) -> State:
  match state:
    case State{_,_,_,_,_,_,_,_,index,_}:
      +count = menuLength(state)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      withIndex(state,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next))
def previewChoice(+state: State) -> Maybe<&2,String>:
  match state:
    case State{_,_,available,_,light,dark,terminal,Single{},Zero{},_}: Some{active(light,dark,terminal)}
    case State{_,_,available,_,_,_,_,Single{},Succ{index},_}: List.get(&2,String,available,index)
    case State{_,_,_,_,_,_,_,Automatic{},_,_}: None{}
    case State{_,_,available,_,_,_,_,_,index,_}: List.get(&2,String,available,index)
def movedChoice(+state: State,choice: Maybe<&2,String>) -> State & Action:
  match choice:
    case Some{name}: (state,Preview{name})
    case None{}: (state,Continue{})
def movedAction(+state: State) -> State & Action:
  movedChoice(state,previewChoice(state))
def chooseName(+state: State,choice: Maybe<&2,String>) -> State & Action:
  match choice:
    case Some{name}: (state,Finish{name})
    case None{}: (state,Continue{})
def chooseSingle(+state: State,index: Nat) -> State & Action:
  match state:
    case State{original,current,available,single,+light,+dark,+terminal,_,_,done}:
      match index:
        case Zero{}: (State{original,current,available,single,light,dark,terminal,Automatic{},0n,done},Preview{active(light,dark,terminal)})
        case Succ{index}:
          chooseName(state,List.get(&2,String,available,index))
def chooseAutomatic(+state: State,index: Nat) -> State & Action:
  match state:
    case State{original,current,available,single,+light,+dark,+terminal,_,_,done}:
      match index:
        case 0n: (State{original,current,available,single,light,dark,terminal,PickLight{},nameIndex(available,light,0n),done},Continue{})
        case 1n: (State{original,current,available,single,light,dark,terminal,PickDark{},nameIndex(available,dark,0n),done},Continue{})
        case 2n: (state,Finish{light ++ "/" ++ dark})
        case _: (State{original,current,available,active(light,dark,terminal),light,dark,terminal,Single{},nameIndex(available,active(light,dark,terminal),1n),done},Preview{active(light,dark,terminal)})
def chooseLightName(+state: State,choice: Maybe<&2,String>) -> State & Action:
  match state choice:
    case State{original,current,available,single,_,+dark,+terminal,_,_,done} Some{+light}: (State{original,current,available,single,light,dark,terminal,Automatic{},0n,done},Preview{active(light,dark,terminal)})
    case _ _: (state,Continue{})
def chooseLight(+state: State,index: Nat) -> State & Action:
  match state:
    case State{_,_,available,_,_,_,_,_,_,_}:
      chooseLightName(state,List.get(&2,String,available,index))
def chooseDarkName(+state: State,choice: Maybe<&2,String>) -> State & Action:
  match state choice:
    case State{original,current,available,single,+light,_,+terminal,_,_,done} Some{+dark}: (State{original,current,available,single,light,dark,terminal,Automatic{},1n,done},Preview{active(light,dark,terminal)})
    case _ _: (state,Continue{})
def chooseDark(+state: State,index: Nat) -> State & Action:
  match state:
    case State{_,_,available,_,_,_,_,_,_,_}:
      chooseDarkName(state,List.get(&2,String,available,index))
def choose(+state: State) -> State & Action:
  match state:
    case State{_,_,_,_,_,_,_,Single{},index,_}: chooseSingle(state,index)
    case State{_,_,_,_,_,_,_,Automatic{},index,_}: chooseAutomatic(state,index)
    case State{_,_,_,_,_,_,_,PickLight{},index,_}: chooseLight(state,index)
    case State{_,_,_,_,_,_,_,PickDark{},index,_}: chooseDark(state,index)
def cancel(+state: State) -> State & Action:
  match state:
    case State{original,current,available,single,light,dark,terminal,PickLight{},_,done}: (State{original,current,available,single,light,dark,terminal,Automatic{},0n,done},Preview{active(light,dark,terminal)})
    case State{original,current,available,single,light,dark,terminal,PickDark{},_,done}: (State{original,current,available,single,light,dark,terminal,Automatic{},1n,done},Preview{active(light,dark,terminal)})
    case _: (state,Cancel{})
def input(+state: State,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> State & Action:
  Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => movedAction(moved(state,True{})),
    _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => movedAction(moved(state,False{})),
      _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => choose(state),
        _ => Bool.pick(Unit -> State & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => cancel(state),_ => (state,Continue{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})

def paint(theme: Theme.Theme,key: String,text: String) -> String: Theme.fg(theme,key,text)
def title(+state: State) -> String:
  match state:
    case State{_,_,_,_,_,_,_,Single{},_,_}: "Theme"
    case State{_,_,_,_,_,_,_,Automatic{},_,_}: "Automatic Theme"
    case State{_,_,_,_,_,_,_,PickLight{},_,_}: "Light Theme"
    case _: "Dark Theme"
def explanation(+state: State) -> List<&2,String>:
  match state:
    case State{_,_,_,_,_,_,_,Single{},_,_}: "Select a theme, or choose Automatic to follow terminal appearance." <> Nil{}
    case State{_,_,_,_,_,_,_,Automatic{},_,_}: "Choose themes for terminal light and dark appearance." <> "Light/dark detection requires terminal support." <> Nil{}
    case State{_,_,_,_,_,_,_,PickLight{},_,_}: "Select the theme to use for light terminal appearance" <> Nil{}
    case _: "Select the theme to use for dark terminal appearance" <> Nil{}
def namesRows(names: List<&2,String>,+current: String,skip: Nat) -> List<&2,String>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: (Bool.pick(String,String.eq(name,current),"✓ ","  ") ++ name) <> namesRows(rest,current,skip + 1n)
def menuRows(+state: State) -> List<&2,String>:
  match state:
    case State{_,_,available,single,_,_,_,Single{},_,_}: "  Automatic  Use separate themes for light and dark terminal appearance" <> namesRows(available,single,0n)
    case State{_,_,_,_,light,dark,_,Automatic{},_,_}: ["Light theme  " ++ light,"Dark theme   " ++ dark,"Apply        save and go back","Change mode  switch to single theme"]
    case State{_,_,available,_,light,_,_,PickLight{},_,_}: namesRows(available,light,0n)
    case State{_,_,available,_,_,dark,_,PickDark{},_,_}: namesRows(available,dark,0n)
def automaticRow(selected: Bool,+theme: Theme.Theme) -> String:
  Bool.pick(String,selected,paint(theme,"accent","→   Automatic"),"    Automatic") ++ paint(theme,"muted","  Use separate themes for light and dark terminal appearance")
def selectedRow(+line: String,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat) -> String:
  Bool.pick(Unit -> String,String.starts_with(line,"  Automatic"),_ => Utils.truncateToWidth(automaticRow(Nat.is_eq(index,selected),theme),width,"",False{}),_ =>
    Utils.truncateToWidth(Bool.pick(String,Nat.is_eq(index,selected),paint(theme,"accent","→ "),"  ") ++ Bool.pick(String,Nat.is_eq(index,selected),paint(theme,"accent",line),line),width,"",False{}))(Unit{})
def visibleRows(lines: List<&2,String>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match lines skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: visibleRows(rest,skip,remaining,index + 1n,selected,theme,width)
    case line <> rest Zero{} Succ{remaining}: selectedRow(line,index,selected,theme,width) <> visibleRows(rest,0n,remaining,index + 1n,selected,theme,width)
def automaticSettingRow(+label: String,+value: String,+selected: Bool,+theme: Theme.Theme) -> String:
  +name = Bool.pick(String,selected,paint(theme,"accent","→ " ++ label),"  " ++ label)
  +spacing = String.drop(Utils.truncateToWidth(label,11n,"",True{}),String.length(label)) ++ "  "
  +shown = Bool.pick(String,selected,paint(theme,"accent",value),paint(theme,"muted",value))
  name ++ spacing ++ shown
def automaticRows(light: String,dark: String,+index: Nat,+theme: Theme.Theme) -> List<&2,String>:
  automaticSettingRow("Light theme",light,Nat.is_eq(index,0n),theme) <>
  automaticSettingRow("Dark theme",dark,Nat.is_eq(index,1n),theme) <>
  automaticSettingRow("Apply","save and go back",Nat.is_eq(index,2n),theme) <>
  automaticSettingRow("Change mode","switch to single theme",Nat.is_eq(index,3n),theme) <> Nil{}
def drawnRows(state: State,lines: List<&2,String>,start: Nat,index: Nat,theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match state:
    case State{_,_,_,_,light,dark,_,Automatic{},_,_}: automaticRows(light,dark,index,theme)
    case _: visibleRows(lines,start,10n,0n,index,theme,width)
def heading(state: State,theme: Theme.Theme) -> List<&2,String>:
  paint(theme,"accent",Theme.bold(title(state))) <> "" <> Nil{}
def mutedLines(lines: List<&2,String>,+theme: Theme.Theme) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: paint(theme,"muted",line) <> mutedLines(rest,theme)
def automaticDescription(index: Nat) -> String:
  match index:
    case 0n: "  Theme to use in automatic mode when the terminal is light"
    case 1n: "  Theme to use in automatic mode when the terminal is dark"
    case 2n: "  Save the selected light and dark themes"
    case _: "  Switch to one theme for light and dark"
def footer(state: State,+theme: Theme.Theme) -> List<&2,String>:
  match state:
    case State{_,_,_,_,_,_,_,Automatic{},index,_}: "" <> paint(theme,"dim",automaticDescription(index)) <> "" <> paint(theme,"dim","  Enter/Space to change · Esc to cancel") <> Nil{}
    case _: "" <> paint(theme,"dim","  Enter to select · Esc to go back") <> Nil{}
def drawState(+state: State,+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match state:
    case State{_,_,_,_,_,_,_,_,index,_}:
      +lines = menuRows(state)
      +count = List.length(&2,String,lines)
      +start = Nat.min(index - 5n,count - Nat.min(count,10n))
      List.append(&2,String,heading(state,theme),List.append(&2,String,mutedLines(explanation(state),theme),"" <> List.append(&2,String,drawnRows(state,lines,start,index,theme,width),footer(state,theme))))
def drawCurrent(current: Modal,theme: Ref.Ref<Theme.Theme>,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: IO.pure(List<&2,String>,Nil{})
    case Open{state}:
      do IO<List<&2,String>>:
        selected : Theme.Theme <- Ref.read(Theme.Theme,theme)
        return drawState(state,selected,width)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,theme,_,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,theme,width)
def previewResult(transcript: Transcript.Handle,result: Result<&2,&2,Theme.LoadError,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: Transcript.showError(transcript,"Cannot preview theme")
def previewCurrent(current: Maybe<&2,Controller.Handle>,transcript: Transcript.Handle,name: String) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        result : Result<&2,&2,Theme.LoadError,Unit> <- Controller.preview(handle,name)
        previewResult(transcript,result)
def previewTheme(controller: Ref.Ref<Maybe<&2,Controller.Handle>>,transcript: Transcript.Handle,name: String) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Controller.Handle> <- Ref.read(Maybe<&2,Controller.Handle>,controller)
    previewCurrent(current,transcript,name)
def restored(result: Result<&2,&2,Theme.LoadError,Controller.Selection>,transcript: Transcript.Handle) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit,Unit{})
    case Fail{_}: Transcript.showError(transcript,"Cannot restore theme")
def restoreCurrent(current: Maybe<&2,Controller.Handle>,transcript: Transcript.Handle,setting: Maybe<&2,String>) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{handle}:
      do IO<Unit>:
        result : Result<&2,&2,Theme.LoadError,Controller.Selection> <- Controller.setThemeSetting(handle,setting)
        restored(result,transcript)
def restoreTheme(controller: Ref.Ref<Maybe<&2,Controller.Handle>>,transcript: Transcript.Handle,setting: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Controller.Handle> <- Ref.read(Maybe<&2,Controller.Handle>,controller)
    restoreCurrent(current,transcript,setting)
def doneOf(+state: State) -> SettingsList.SubmenuDone:
  match state: case State{_,_,_,_,_,_,_,_,_,done}: done
def originalOf(+state: State) -> Maybe<&2,String>:
  match state: case State{original,_,_,_,_,_,_,_,_,_}: original
def action(host: Host,+state: State,result: Action) -> IO(Unit):
  match host result:
    case Host{modal,_,_,_,_,_} Continue{}: Ref.write(Modal,modal,Open{state})
    case Host{modal,_,controller,transcript,_,_} Preview{name}:
      do IO<Unit>:
        Ref.write(Modal,modal,Open{state})
        previewTheme(controller,transcript,name)
    case Host{modal,_,_,_,_,_} Finish{setting}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        SettingsList.complete(doneOf(state),Some{setting},None{})
    case Host{modal,_,controller,transcript,_,_} Cancel{}:
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        restoreTheme(controller,transcript,originalOf(state))
        SettingsList.complete(doneOf(state),None{},None{})
def accepted(host: Host,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,result): action(host,state,result)
def receiveCurrent(current: Modal,host: Host,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{state}: accepted(host,input(state,bindings,keyboard,data))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,theme,controller,transcript,+bindings,+keyboard}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,Host{modal,theme,controller,transcript,bindings,keyboard},bindings,keyboard,data)
def invalidated(_: Host,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def currentSetting(selection: Controller.Selection) -> Maybe<&2,String>:
  match selection: case Controller.Selection{setting,_,_,_,_,_,_}: setting
def currentName(selection: Controller.Selection) -> String:
  match selection: case Controller.Selection{_,_,name,_,_,_,_}: name
def terminalOf(selection: Controller.Selection) -> Detection.TerminalTheme:
  match selection: case Controller.Selection{_,terminal,_,_,_,_,_}: terminal
def catalogNames(result: Result<&2,&2,FS.Error,List<&2,Theme.ThemeInfo>>,transcript: Transcript.Handle) -> IO(List<&2,String>):
  match result:
    case Done{items}: IO.pure(List<&2,String>,Theme.names(items))
    case Fail{_}:
      do IO<List<&2,String>>:
        Transcript.showError(transcript,"Cannot list custom themes")
        return "dark" <> "light" <> Nil{}
def openWith(host: Host,request: SettingsList.SubmenuRequest,+handle: Controller.Handle) -> IO(Unit):
  match host request handle:
    case Host{modal,_,_,transcript,_,_} SettingsList.SubmenuRequest{current,done} Controller.Handle{_,_,_,_,customDir,mode}:
      do IO<Unit>:
        +selection : Controller.Selection <- Controller.current(handle)
        found : Result<&2,&2,FS.Error,List<&2,Theme.ThemeInfo>> <- Theme.catalog(customDir,mode)
        available : List<&2,String> <- catalogNames(found,transcript)
        Ref.write(Modal,modal,Open{initialState(currentSetting(selection),current,available,terminalOf(selection),done)})
def openCurrent(current: Maybe<&2,Controller.Handle>,host: Host,request: SettingsList.SubmenuRequest,transcript: Transcript.Handle) -> IO(Unit):
  match current:
    case None{}: Transcript.showError(transcript,"Theme controller is not ready")
    case Some{handle}: openWith(host,request,handle)
def open(+host: Host,request: SettingsList.SubmenuRequest) -> IO(Unit):
  match host:
    case Host{_,_,controller,transcript,_,_}:
      do IO<Unit>:
        current : Maybe<&2,Controller.Handle> <- Ref.read(Maybe<&2,Controller.Handle>,controller)
        openCurrent(current,host,request,transcript)
def factory(context: Factory,request: SettingsList.SubmenuRequest) -> IO(Component.Component):
  match context:
    case Factory{host,component}:
      do IO<Component.Component>:
        open(host,request)
        return component
def createHost(parent: Component.Component,theme: Ref.Ref<Theme.Theme>,controller: Ref.Ref<Maybe<&2,Controller.Handle>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +host : Host <- IO.pure(Host,Host{modal,theme,controller,transcript,bindings,keyboard})
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +input : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidated,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(parent),render,Some{input},None{},invalidate,None{},False{}})
    +factoryCallback : Callback.Callback<SettingsList.SubmenuRequest,Component.Component> <- Callback.create(~Factory,~SettingsList.SubmenuRequest,~Component.Component,~factory,Factory{host,component})
    return Owner{host,component,render,input,invalidate,factoryCallback}
def factoryOf(owner: Owner) -> Callback.Callback<SettingsList.SubmenuRequest,Component.Component>:
  match owner: case Owner{_,_,_,_,_,factoryCallback}: factoryCallback
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_},_,render,inputCallback,invalidate,factoryCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Unit,Unit,invalidate)
        Callback.dispose(SettingsList.SubmenuRequest,Component.Component,factoryCallback)
