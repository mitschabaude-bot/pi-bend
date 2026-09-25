import Base
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/record.bend as Record
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../tui/src/components/settings-list.bend as SettingsList
import ../../../core/agent-session.bend as Session
import ../../../core/model-runtime.bend as Models
import ../../../core/settings-manager.bend as Settings
import ../theme/theme.bend as Theme
import ../transcript.bend as Transcript
import ./model-selector.bend as ModelPicker
import ./thinking-selector.bend as ThinkingPicker

# A model choice followed by one of that model's supported levels. Saving a
# level returns to the model list so more than one override can be configured.
type Stage is Data:
  Models{list: ModelPicker.State}
  Levels{list: ModelPicker.State,model: Models.Model(),options: List<&2,Ai.ModelThinkingLevel>,selected: Nat,override: Maybe<&2,Ai.ModelThinkingLevel>}
type Modal is Data: Closed{} Open{stage: Stage,done: SettingsList.SubmenuDone}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context}
type Factory is Data: Factory{host: Host,component: Component.Component}
type Owner is Data:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,invalidateCallback: Callback.Callback<Unit,Unit>,factoryCallback: Callback.Callback<SettingsList.SubmenuRequest,Component.Component>}

def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def summary(settings: Settings.SettingsManager) -> String:
  +count = List.length(&2,Record.Property<Ai.ModelThinkingLevel>,Record.entries(Ai.ModelThinkingLevel,Settings.getAllModelThinkingLevels(settings)))
  Bool.pick(String,Nat.is_eq(count,0n),"none",Nat.show(count) ++ " configured")
def overrideText(level: Maybe<&2,Ai.ModelThinkingLevel>) -> String:
  match level:
    case None{}: ""
    case Some{value}: Levels.name(value)
def modelRow(+model: Models.Model(),+selected: Bool,+theme: Theme.Theme,width: Nat,overrides: Record.Record<Ai.ModelThinkingLevel>) -> String:
  +id = Models.modelId(model)
  +provider = "[" ++ Models.modelProvider(model) ++ "]"
  +label = id ++ " " ++ provider
  +override = overrideText(Record.get(Ai.ModelThinkingLevel,overrides,Models.reference(model)))
  +padding = Bool.pick(String,String.is_empty(override),"",String.drop(Utils.truncateToWidth(label,30n,"",True{}),String.length(label)) ++ override)
  +prefix = Bool.pick(String,selected,paint(theme,"accent","→ " ++ id ++ " "),"  " ++ id ++ " ")
  Utils.truncateToWidth(prefix ++ paint(theme,"muted",provider) ++ padding,width,"",False{})
def modelRows(items: List<&2,Models.Model()>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat,+overrides: Record.Record<Ai.ModelThinkingLevel>) -> List<&2,String>:
  match items skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: modelRows(rest,skip,remaining,index + 1n,selected,theme,width,overrides)
    case model <> rest Zero{} Succ{remaining}: modelRow(model,Nat.is_eq(index,selected),theme,width,overrides) <> modelRows(rest,0n,remaining,index + 1n,selected,theme,width,overrides)
def renderModels(list: ModelPicker.State,+theme: Theme.Theme,width: Nat,settings: Settings.SettingsManager) -> List<&2,String>:
  match list:
    case ModelPicker.State{_,_,+visible,+index,query,_,_,_,_}:
      +count = List.length(&2,Models.Model(),visible)
      +start = Nat.min(index - 5n,count - Nat.min(count,10n))
      +body = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),"  No matching models" <> Nil{},modelRows(visible,start,10n,0n,index,theme,width,Settings.getAllModelThinkingLevels(settings)))
      paint(theme,"accent",Theme.bold("Per-Model Thinking Level")) <> "" <>
      paint(theme,"muted","Step 1/2 · Select a model to configure") <> "" <>
      ("> " ++ query ++ "\u{1b}[7m \u{1b}[0m") <> "" <>
      List.append(&2,String,body,paint(theme,"muted","  (" ++ Nat.show(Bool.pick(Nat,Nat.is_eq(count,0n),0n,index + 1n)) ++ "/" ++ Nat.show(count) ++ ")") <> "" <>
        paint(theme,"dim","  Type to filter · Enter to select · Esc to go back") <> Nil{})
def sameLevel(left: Ai.ModelThinkingLevel,right: Ai.ModelThinkingLevel) -> Bool:
  U32.is_eq(Levels.rank(left),Levels.rank(right))
def levelIndex(options: List<&2,Ai.ModelThinkingLevel>,current: Maybe<&2,Ai.ModelThinkingLevel>,+index: Nat) -> Nat:
  match options current:
    case Nil{} _: 0n
    case _ None{}: 0n
    case value <> rest Some{+level}: Bool.pick(Unit -> Nat,sameLevel(value,level),_ => index,_ => levelIndex(rest,Some{level},index + 1n))(Unit{})
def sameOverride(level: Ai.ModelThinkingLevel,current: Maybe<&2,Ai.ModelThinkingLevel>) -> Bool:
  match current:
    case None{}: False{}
    case Some{active}: sameLevel(level,active)
def levelRow(+level: Ai.ModelThinkingLevel,+override: Maybe<&2,Ai.ModelThinkingLevel>,+selected: Bool,+theme: Theme.Theme,width: Nat,column: Nat) -> String:
  +current = Bool.pick(Bool,Maybe.is_some(&2,Ai.ModelThinkingLevel,override),sameOverride(level,override),False{})
  +name = Levels.name(level)
  +label = Bool.pick(String,current,"✓ ","  ") ++ name
  +detail = String.drop(Utils.truncateToWidth(name,column,"",True{}),String.length(name)) ++ ThinkingPicker.description(level)
  +prefix = Bool.pick(String,selected,"→ ","  ") ++ label
  Utils.truncateToWidth(Bool.pick(String,selected,paint(theme,"accent",prefix ++ detail),prefix ++ paint(theme,"muted",detail)),width,"",False{})
def levelRows(options: List<&2,Ai.ModelThinkingLevel>,+override: Maybe<&2,Ai.ModelThinkingLevel>,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat,+column: Nat) -> List<&2,String>:
  match options:
    case Nil{}: Nil{}
    case level <> rest: levelRow(level,override,Nat.is_eq(index,selected),theme,width,column) <> levelRows(rest,override,index + 1n,selected,theme,width,column)
def clearRow(+selected: Bool,+theme: Theme.Theme,settings: Settings.SettingsManager) -> String:
  +prefix = Bool.pick(String,selected,"→ ","  ") ++ "  (clear override)"
  +detail = "  Revert to global default (" ++ Levels.name(Maybe.default(&2,Ai.ModelThinkingLevel,Settings.getDefaultThinkingLevel(settings),Ai.Thinking{Ai.Medium{}})) ++ ")"
  Bool.pick(String,selected,paint(theme,"accent",prefix ++ detail),prefix ++ paint(theme,"muted",detail))
def clearRows(override: Maybe<&2,Ai.ModelThinkingLevel>,selected: Nat,count: Nat,theme: Theme.Theme,settings: Settings.SettingsManager) -> List<&2,String>:
  match override:
    case None{}: Nil{}
    case Some{_}: clearRow(Nat.is_eq(selected,count),theme,settings) <> Nil{}
def renderLevels(+model: Models.Model(),+options: List<&2,Ai.ModelThinkingLevel>,+selected: Nat,+override: Maybe<&2,Ai.ModelThinkingLevel>,+theme: Theme.Theme,width: Nat,settings: Settings.SettingsManager) -> List<&2,String>:
  +title = "Thinking Level for " ++ Models.modelId(model) ++ " [" ++ Models.modelProvider(model) ++ "]"
  +column = Bool.pick(Nat,Maybe.is_some(&2,Ai.ModelThinkingLevel,override),18n,10n)
  +rows = List.append(&2,String,levelRows(options,override,0n,selected,theme,width,column),clearRows(override,selected,List.length(&2,Ai.ModelThinkingLevel,options),theme,settings))
  paint(theme,"accent",Theme.bold(title)) <> "" <>
  paint(theme,"muted","Step 2/2 · Select default thinking level for this model") <> "" <>
  List.append(&2,String,rows,"" <> paint(theme,"dim","  Enter to select · Esc to go back") <> Nil{})
def renderStage(stage: Stage,theme: Theme.Theme,width: Nat,settings: Settings.SettingsManager) -> List<&2,String>:
  match stage:
    case Models{list}: renderModels(list,theme,width,settings)
    case Levels{_,model,options,index,override}: renderLevels(model,options,index,override,theme,width,settings)
def renderCurrent(current: Modal,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: IO.pure(List<&2,String>,Nil{})
    case Open{stage,_}:
      do IO<List<&2,String>>:
        selected : Theme.Theme <- Ref.read(Theme.Theme,theme)
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        return renderStage(stage,selected,width,settings)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{modal,theme,session,_,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        renderCurrent(current,theme,session,width)

def moveIndex(+index: Nat,+count: Nat,up: Bool) -> Nat:
  Bool.pick(Nat,Nat.is_eq(count,0n),0n,
    Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n)))
def selectedLevel(options: List<&2,Ai.ModelThinkingLevel>,index: Nat) -> Maybe<&2,Ai.ModelThinkingLevel>:
  List.get(&2,Ai.ModelThinkingLevel,options,index)
def currentModel(model: Models.Model(),current: Maybe<&2,Models.Model()>) -> Bool:
  match current:
    case None{}: False{}
    case Some{selected}: String.eq(Models.reference(model),Models.reference(selected))
def effectiveLevel(choice: Maybe<&2,Ai.ModelThinkingLevel>,settings: Settings.SettingsManager) -> Ai.ModelThinkingLevel:
  Maybe.default(&2,Ai.ModelThinkingLevel,choice,Maybe.default(&2,Ai.ModelThinkingLevel,Settings.getDefaultThinkingLevel(settings),Ai.Thinking{Ai.Medium{}}))
def afterCurrent(model: Models.Model(),choice: Maybe<&2,Ai.ModelThinkingLevel>,+session: Session.AgentSession,current: Session.AgentState()) -> IO(Result<&2,&2,String,Unit>):
  Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),currentModel(model,Session.stateModel(current)),
    _ => do IO<Result<&2,&2,String,Unit>>:
      settings : Settings.SettingsManager <- Session.getSettings(session)
      Session.setThinkingLevel(session,effectiveLevel(choice,settings),Session.ModelMutationOptions{False{}}),
    _ => IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}}))(Unit{})
def afterSaved(result: Result<&2,&2,String,Unit>,model: Models.Model(),choice: Maybe<&2,Ai.ModelThinkingLevel>,+session: Session.AgentSession) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{message}: IO.pure(Result<&2,&2,String,Unit>,Fail{message})
    case Done{_}:
      do IO<Result<&2,&2,String,Unit>>:
        current : Session.AgentState() <- Session.state(session)
        afterCurrent(model,choice,session,current)
def persistedLevel(+model: Models.Model(),choice: Maybe<&2,Ai.ModelThinkingLevel>,session: Session.AgentSession) -> IO(Result<&2,&2,String,Unit>):
  match choice:
    case Some{level}: Session.changeSettings(session,settings => Settings.setModelThinkingLevel(Models.modelProvider(model),Models.modelId(model),level,settings))
    case None{}: Session.changeSettings(session,settings => Settings.removeModelThinkingLevel(Models.modelProvider(model),Models.modelId(model),settings))
def changeLevel(+model: Models.Model(),+choice: Maybe<&2,Ai.ModelThinkingLevel>,+session: Session.AgentSession) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    result : Result<&2,&2,String,Unit> <- persistedLevel(model,choice,session)
    afterSaved(result,model,choice,session)
def supported(model: Models.Model()) -> List<&2,Ai.ModelThinkingLevel>:
  match model:
    case Ai.Model{_,_,_,_,_,reasoning,mapping,_,_,_,_,_,_,_,_,_}: Levels.available(reasoning,mapping)
def saved(result: Result<&2,&2,String,Unit>,modal: Ref.Ref<Modal>,list: ModelPicker.State,done: SettingsList.SubmenuDone,transcript: Transcript.Handle) -> IO(Unit):
  match result:
    case Done{_}: Ref.write(Modal,modal,Open{Models{list},done})
    case Fail{message}: Transcript.showError(transcript,message)
def chooseLevel(host: Host,list: ModelPicker.State,model: Models.Model(),options: List<&2,Ai.ModelThinkingLevel>,index: Nat,done: SettingsList.SubmenuDone) -> IO(Unit):
  match host:
    case Host{modal,_,session,_,transcript,_,_}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Unit> <- changeLevel(model,selectedLevel(options,index),current)
        saved(result,modal,list,done,transcript)
def showLevel(host: Host,list: ModelPicker.State,+model: Models.Model(),done: SettingsList.SubmenuDone) -> IO(Unit):
  match host:
    case Host{modal,_,session,_,_,_,_}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(current)
        +options : List<&2,Ai.ModelThinkingLevel> <- IO.pure(List<&2,Ai.ModelThinkingLevel>,supported(model))
        +override : Maybe<&2,Ai.ModelThinkingLevel> <- IO.pure(Maybe<&2,Ai.ModelThinkingLevel>,Settings.getModelThinkingLevel(Models.modelProvider(model),Models.modelId(model),settings))
        Ref.write(Modal,modal,Open{Levels{list,model,options,levelIndex(options,override,0n),override},done})
def finish(host: Host,done: SettingsList.SubmenuDone) -> IO(Unit):
  match host:
    case Host{modal,_,session,_,_,_,_}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(current)
        Ref.write(Modal,modal,Closed{})
        SettingsList.complete(done,Some{summary(settings)},None{})
def writeStage(host: Host,stage: Stage,done: SettingsList.SubmenuDone) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_}: Ref.write(Modal,modal,Open{stage,done})
def modelAction(host: Host,done: SettingsList.SubmenuDone,pair: ModelPicker.State & ModelPicker.Action) -> IO(Unit):
  match pair:
    case (list,ModelPicker.Continue{}): writeStage(host,Models{list},done)
    case (list,ModelPicker.Cancel{}): finish(host,done)
    case (list,ModelPicker.Chosen{model,_}): showLevel(host,list,model,done)
def levelInput(+host: Host,+list: ModelPicker.State,+model: Models.Model(),+options: List<&2,Ai.ModelThinkingLevel>,+index: Nat,+override: Maybe<&2,Ai.ModelThinkingLevel>,+done: SettingsList.SubmenuDone,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(Unit):
  +count = List.length(&2,Ai.ModelThinkingLevel,options) + Bool.pick(Nat,Maybe.is_some(&2,Ai.ModelThinkingLevel,override),1n,0n)
  Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => writeStage(host,Levels{list,model,options,moveIndex(index,count,True{}),override},done),
    _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => writeStage(host,Levels{list,model,options,moveIndex(index,count,False{}),override},done),
      _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => chooseLevel(host,list,model,options,index,done),
        _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => writeStage(host,Models{list},done),_ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def inputStage(host: Host,stage: Stage,done: SettingsList.SubmenuDone,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Unit):
  match stage:
    case Models{list}: modelAction(host,done,ModelPicker.input(list,bindings,keyboard,data))
    case Levels{list,model,options,index,override}: levelInput(host,list,model,options,index,override,done,bindings,keyboard,data)
def inputCurrent(current: Modal,host: Host,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{stage,done}: inputStage(host,stage,done,bindings,keyboard,data)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,theme,session,models,transcript,+bindings,+keyboard}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        inputCurrent(current,Host{modal,theme,session,models,transcript,bindings,keyboard},bindings,keyboard,data)
def invalidated(_: Host,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def opened(host: Host,request: SettingsList.SubmenuRequest) -> IO(Unit):
  match host request:
    case Host{modal,_,session,models,_,_,_} SettingsList.SubmenuRequest{_,done}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        agent : Session.AgentState() <- Session.state(current)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        Ref.write(Modal,modal,Open{Models{ModelPicker.create(available,Session.stateModel(agent),"",20n)},done})
def factory(context: Factory,request: SettingsList.SubmenuRequest) -> IO(Component.Component):
  match context:
    case Factory{host,component}:
      do IO<Component.Component>:
        opened(host,request)
        return component
def createHost(parent: Component.Component,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    +host : Host <- IO.pure(Host,Host{modal,theme,session,models,transcript,bindings,keyboard})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidated,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(parent),renderCallback,Some{inputCallback},None{},invalidateCallback,None{},False{}})
    +factoryCallback : Callback.Callback<SettingsList.SubmenuRequest,Component.Component> <- Callback.create(~Factory,~SettingsList.SubmenuRequest,~Component.Component,~factory,Factory{host,component})
    return Owner{host,component,renderCallback,inputCallback,invalidateCallback,factoryCallback}
def factoryOf(owner: Owner) -> Callback.Callback<SettingsList.SubmenuRequest,Component.Component>:
  match owner: case Owner{_,_,_,_,_,factoryCallback}: factoryCallback
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_,_},_,renderCallback,inputCallback,invalidateCallback,factoryCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(SettingsList.SubmenuRequest,Component.Component,factoryCallback)
