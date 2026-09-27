import Base
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../../runtime/src/callback.bend as C
import ../../../../../runtime/src/collation.bend as Collation
import ../../../../../runtime/src/record.bend as Record
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/components/select-list.bend as Select
import ../../../../../tui/src/components/settings-list.bend as SettingsList
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../core/agent-session.bend as Session
import ../../../core/model-runtime.bend as Models
import ../../../core/settings-manager.bend as Settings
import ../theme/theme.bend as Theme
import ../transcript.bend as Transcript
import ./model-selector.bend as ModelPicker
import ./settings-submenu.bend as Submenu
import ./thinking-selector.bend as ThinkingPicker

# The settings-specific choices use the same reusable stepped submenu as pi.
type Modal is Data: Closed{} Open{submenu: Submenu.SteppedSubmenu,done: SettingsList.SubmenuDone}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,words: Ref.Ref<Words.Source>,listTheme: Select.SelectListTheme,collator: Ref.Ref<Maybe<&2,Collation.Collator>>}
type Factory is Data:
  Factory{host: Host,component: Component.Component,steps: List<&2,Submenu.SteppedSubmenuStep>,complete: C.Callback<Submenu.Context(),Unit>,cancel: C.Callback<Unit,Unit>}
type Owner is Data:
  Owner{host: Host,component: Component.Component,renderCallback: C.Callback<Nat,List<&2,String>>,inputCallback: C.Callback<String,Unit>,invalidateCallback: C.Callback<Unit,Unit>,factoryCallback: C.Callback<SettingsList.SubmenuRequest,Component.Component>,themeOwner: Submenu.ThemeOwner,modelOptions: C.Callback<Submenu.Context(),List<&2,Select.SelectItem>>,levelOptions: C.Callback<Submenu.Context(),List<&2,Select.SelectItem>>,levelTitle: C.Callback<Submenu.Context(),String>,modelPreselect: C.Callback<Submenu.Context(),Maybe<&2,String>>,levelPreselect: C.Callback<Submenu.Context(),Maybe<&2,String>>,complete: C.Callback<Submenu.Context(),Unit>,cancel: C.Callback<Unit,Unit>}

def summary(settings: Settings.SettingsManager) -> String:
  +count = List.length(&2,Record.Property<Ai.ModelThinkingLevel>,Record.entries(Ai.ModelThinkingLevel,Settings.getAllModelThinkingLevels(settings)))
  Bool.pick(String,Nat.is_eq(count,0n),"none",Nat.show(count) ++ " configured")
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
def defaultReference(provider: Maybe<&2,String>,id: Maybe<&2,String>) -> Maybe<&2,String>:
  match provider id: case Some{provider} Some{id}: Some{provider ++ "/" ++ id} case _ _: None{}
def defaultModel(+settings: Settings.SettingsManager) -> Maybe<&2,String>:
  defaultReference(Settings.getDefaultProvider(settings),Settings.getDefaultModel(settings))
def findModel(models: List<&2,Models.Model()>,+key: String) -> Maybe<&2,Models.Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest: Bool.pick(Unit -> Maybe<&2,Models.Model()>,String.eq(Models.reference(model),key),_ => Some{model},_ => findModel(rest,key))(Unit{})
def contextModel(context: Submenu.Context(),models: List<&2,Models.Model()>) -> Maybe<&2,Models.Model()>:
  Maybe.bind(&2,String,Models.Model(),Record.get(String,context,"model"),key => findModel(models,key))
def modelItems(models: List<&2,Models.Model()>,+settings: Settings.SettingsManager,+theme: Theme.Theme) -> List<&2,Select.SelectItem>:
  match models:
    case Nil{}: Nil{}
    case +model <> rest:
      Select.SelectItem{Models.reference(model),Models.modelId(model) ++ " " ++ Submenu.paint(theme,"muted","[" ++ Models.modelProvider(model) ++ "]"),Maybe.map(&2,Ai.ModelThinkingLevel,String,level => Levels.name(level),Settings.getModelThinkingLevel(Models.modelProvider(model),Models.modelId(model),settings))} <> modelItems(rest,settings,theme)
def sortedItems(result: Result<&2,&2,Collation.LoadError,Collation.Collator>,cache: Ref.Ref<Maybe<&2,Collation.Collator>>,models: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,+settings: Settings.SettingsManager,theme: Theme.Theme) -> IO(List<&2,Select.SelectItem>):
  match result:
    case Fail{_}: IO.die(List<&2,Select.SelectItem>,1,"cannot load model ordering data")
    case Done{+collator}:
      do IO<List<&2,Select.SelectItem>>:
        Ref.write(Maybe<&2,Collation.Collator>,cache,Some{collator})
        +items : List<&2,Select.SelectItem> = modelItems(ModelPicker.sortedModels(models,collator,current,defaultModel(settings)),settings,theme)
        return Bool.pick(List<&2,Select.SelectItem>,List.is_empty(&2,Select.SelectItem,items),[Select.SelectItem{"__none__","No models available",Some{"Log in to a provider or configure an API key first"}}],items)
def modelOptions(host: Host,_: Submenu.Context()) -> IO(List<&2,Select.SelectItem>):
  match host:
    case Host{_,theme,+session,models,_,_,_,words,_,+collator}:
      do IO<List<&2,Select.SelectItem>>:
        +live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        state : Session.AgentState() <- Session.state(live)
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        stored : Maybe<&2,Collation.Collator> <- Ref.read(Maybe<&2,Collation.Collator>,collator)
        ready : Result<&2,&2,Collation.LoadError,Collation.Collator> <- ModelPicker.cachedCollator(stored,words)
        sortedItems(ready,collator,available,Session.stateModel(state),settings,colors)
def levelItems(options: List<&2,Ai.ModelThinkingLevel>,+active: Maybe<&2,Ai.ModelThinkingLevel>) -> List<&2,Select.SelectItem>:
  match options:
    case Nil{}: Nil{}
    case +level <> rest:
      +name = Levels.name(level)
      Select.SelectItem{name,Bool.pick(String,Maybe.is_some(&2,Ai.ModelThinkingLevel,active) && String.eq(name,Maybe.default(&2,String,Maybe.map(&2,Ai.ModelThinkingLevel,String,item => Levels.name(item),active),"")),"✓ ","  ") ++ name,Some{ThinkingPicker.description(level)}} <> levelItems(rest,active)
def optionsFor(found: Maybe<&2,Models.Model()>,+settings: Settings.SettingsManager) -> List<&2,Select.SelectItem>:
  match found:
    case None{}: Nil{}
    case Some{+model}:
      +override = Settings.getModelThinkingLevel(Models.modelProvider(model),Models.modelId(model),settings)
      List.append(&2,Select.SelectItem,levelItems(supported(model),override),Bool.pick(List<&2,Select.SelectItem>,Maybe.is_some(&2,Ai.ModelThinkingLevel,override),[Select.SelectItem{"__clear__","  (clear override)",Some{"Revert to global default (" ++ Levels.name(effectiveLevel(None{},settings)) ++ ")"}}],Nil{}))
def levelOptions(host: Host,context: Submenu.Context()) -> IO(List<&2,Select.SelectItem>):
  match host:
    case Host{_,_,session,models,_,_,_,_,_,_}:
      do IO<List<&2,Select.SelectItem>>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        return optionsFor(contextModel(context,available),settings)
def modelLabel(+model: Models.Model()) -> String: Models.modelId(model) ++ " [" ++ Models.modelProvider(model) ++ "]"
def levelTitle(host: Host,context: Submenu.Context()) -> IO(String):
  match host:
    case Host{_,_,_,models,_,_,_,_,_,_}:
      do IO<String>:
        +context : Submenu.Context() = context
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        return "Thinking Level for " ++ Maybe.default(&2,String,Maybe.map(&2,Models.Model(),String,model => modelLabel(model),contextModel(context,available)),Maybe.default(&2,String,Record.get(String,context,"model"),""))
def preferred(current: Maybe<&2,String>,fallback: Maybe<&2,String>) -> Maybe<&2,String>:
  match current: case Some{value}: Some{value} case None{}: fallback
def modelPreselect(host: Host,_: Submenu.Context()) -> IO(Maybe<&2,String>):
  match host:
    case Host{_,_,session,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,String>>:
        ++live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        state : Session.AgentState() <- Session.state(live)
        return preferred(Maybe.map(&2,Models.Model(),String,model => Models.reference(model),Session.stateModel(state)),defaultModel(settings))
def levelPreselect(host: Host,context: Submenu.Context()) -> IO(Maybe<&2,String>):
  match host:
    case Host{_,_,session,_,_,_,_,_,_,_}:
      do IO<Maybe<&2,String>>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        return Maybe.bind(&2,String,String,Record.get(String,context,"model"),key => Maybe.map(&2,Ai.ModelThinkingLevel,String,level => Levels.name(level),Record.get(Ai.ModelThinkingLevel,Settings.getAllModelThinkingLevels(settings),key)))
def report(result: Result<&2,&2,String,Unit>,transcript: Transcript.Handle) -> IO(Unit):
  match result: case Done{_}: IO.pure(Unit,Unit{}) case Fail{message}: Transcript.showError(transcript,message)
def persistChoice(found: Maybe<&2,Models.Model()>,choice: Maybe<&2,String>,session: Ref.Ref<Session.AgentSession>,transcript: Transcript.Handle) -> IO(Unit):
  match found choice:
    case Some{model} Some{value}:
      do IO<Unit>:
        current : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        result : Result<&2,&2,String,Unit> <- changeLevel(model,Levels.fromName(value),current)
        report(result,transcript)
    case _ _: IO.pure(Unit,Unit{})
def completed(host: Host,context: Submenu.Context()) -> IO(Unit):
  match host:
    case Host{_,_,session,models,transcript,_,_,_,_,_}:
      do IO<Unit>:
        +context : Submenu.Context() = context
        available : List<&2,Models.Model()> <- Ref.read(List<&2,Models.Model()>,models)
        persistChoice(contextModel(context,available),Record.get(String,context,"level"),session,transcript)
def cancelledCurrent(current: Modal,modal: Ref.Ref<Modal>,session: Ref.Ref<Session.AgentSession>) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{_,done}:
      do IO<Unit>:
        live : Session.AgentSession <- Ref.read(Session.AgentSession,session)
        settings : Settings.SettingsManager <- Session.getSettings(live)
        Ref.write(Modal,modal,Closed{})
        SettingsList.complete(done,Some{summary(settings)},None{})
def cancelled(host: Host,_: Unit) -> IO(Unit):
  match host:
    case Host{+modal,_,session,_,_,_,_,_,_,_}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        cancelledCurrent(current,modal,session)
def stored(current: Modal,next: Submenu.SteppedSubmenu) -> Modal & Unit:
  match current: case Closed{}: (Closed{},Unit{}) case Open{_,done}: (Open{next,done},Unit{})
def drawn(pair: Submenu.SteppedSubmenu & List<&2,String>,modal: Ref.Ref<Modal>) -> IO(List<&2,String>):
  match pair:
    case (next,lines):
      do IO<List<&2,String>>:
        Ref.modify(Modal,Unit,modal,current => stored(current,next))
        return lines
def drawCurrent(current: Modal,modal: Ref.Ref<Modal>,theme: Ref.Ref<Theme.Theme>,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: IO.pure(List<&2,String>,Nil{})
    case Open{submenu,_}:
      do IO<List<&2,String>>:
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        pair : Submenu.SteppedSubmenu & List<&2,String> <- Submenu.renderStepped(submenu,colors,width)
        drawn(pair,modal)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,theme,_,_,_,_,_,_,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        drawCurrent(current,modal,theme,width)
def inputCurrent(current: Modal,modal: Ref.Ref<Modal>,+words: Ref.Ref<Words.Source>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{+submenu,_}:
      do IO<Unit>:
        previous : Words.Source <- Ref.read(Words.Source,words)
        +source : Words.Source <- ModelPicker.wordsFor(ModelPicker.needsWords(Input.command(Input.bindings(),bindings,keyboard,data)),previous,Submenu.query(Submenu.active(submenu)))
        Ref.write(Words.Source,words,source)
        next : Submenu.SteppedSubmenu <- Submenu.handleSteppedInput(submenu,source,bindings,keyboard,data)
        Ref.modify(Modal,Unit,modal,current => stored(current,next))
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,_,_,_,_,bindings,keyboard,words,_,_}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        inputCurrent(current,modal,words,bindings,keyboard,data)
def invalidated(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_,_,_,_}: Ref.modify(Modal,Unit,modal,current => (current,Unit{}))
def begun(result: Result<&2,&2,Submenu.BuildError,Submenu.SteppedSubmenu>,modal: Ref.Ref<Modal>,done: SettingsList.SubmenuDone) -> IO(Unit):
  match result:
    case Done{submenu}: Ref.write(Modal,modal,Open{submenu,done})
    case Fail{_}: IO.die(Unit,1,"invalid per-model thinking submenu")
def factory(environment: Factory,request: SettingsList.SubmenuRequest) -> IO(Component.Component):
  match environment request:
    case Factory{Host{modal,_,_,_,_,_,_,_,listTheme,_},component,steps,complete,cancel} SettingsList.SubmenuRequest{_,done}:
      do IO<Component.Component>:
        created : Result<&2,&2,Submenu.BuildError,Submenu.SteppedSubmenu> <- Submenu.stepped(steps,listTheme,complete,cancel,Submenu.SteppedSubmenuOptions{0n,Record.new(String),True{}})
        begun(created,modal,done)
        return component
def configured(pair: Submenu.ThemeOwner & Select.SelectListTheme,parent: Component.Component,theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,words: Ref.Ref<Words.Source>) -> IO(Owner):
  match pair:
    case (themeOwner,listTheme):
      do IO<Owner>:
        modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
        collator : Ref.Ref<Maybe<&2,Collation.Collator>> <- Ref.new(Maybe<&2,Collation.Collator>,None{})
        +host : Host = Host{modal,theme,session,models,transcript,bindings,keyboard,words,listTheme,collator}
        +renderCallback : C.Callback<Nat,List<&2,String>> <- C.create(~Host,~Nat,~List<&2,String>,~draw,host)
        +inputCallback : C.Callback<String,Unit> <- C.create(~Host,~String,~Unit,~receive,host)
        +invalidateCallback : C.Callback<Unit,Unit> <- C.create(~Host,~Unit,~Unit,~invalidated,host)
        +modelOptions : C.Callback<Submenu.Context(),List<&2,Select.SelectItem>> <- C.create(~Host,~Submenu.Context(),~List<&2,Select.SelectItem>,~modelOptions,host)
        +levelOptions : C.Callback<Submenu.Context(),List<&2,Select.SelectItem>> <- C.create(~Host,~Submenu.Context(),~List<&2,Select.SelectItem>,~levelOptions,host)
        +levelTitle : C.Callback<Submenu.Context(),String> <- C.create(~Host,~Submenu.Context(),~String,~levelTitle,host)
        +modelPreselect : C.Callback<Submenu.Context(),Maybe<&2,String>> <- C.create(~Host,~Submenu.Context(),~Maybe<&2,String>,~modelPreselect,host)
        +levelPreselect : C.Callback<Submenu.Context(),Maybe<&2,String>> <- C.create(~Host,~Submenu.Context(),~Maybe<&2,String>,~levelPreselect,host)
        +complete : C.Callback<Submenu.Context(),Unit> <- C.create(~Host,~Submenu.Context(),~Unit,~completed,host)
        +cancel : C.Callback<Unit,Unit> <- C.create(~Host,~Unit,~Unit,~cancelled,host)
        +component : Component.Component = Component.Component{Component.id(parent),renderCallback,Some{inputCallback},None{},invalidateCallback,None{},False{}}
        steps : List<&2,Submenu.SteppedSubmenuStep> = [Submenu.SteppedSubmenuStep{"model",Submenu.Literal{"Per-Model Thinking Level"},Submenu.Literal{"Select a model to configure"},modelOptions,Some{modelPreselect},True{},Some{Select.SelectListLayoutOptions{Some{12n},Some{46n},None{}}}},Submenu.SteppedSubmenuStep{"level",Submenu.Dynamic{levelTitle},Submenu.Literal{"Select default thinking level for this model"},levelOptions,Some{levelPreselect},False{},None{}}]
        +factoryCallback : C.Callback<SettingsList.SubmenuRequest,Component.Component> <- C.create(~Factory,~SettingsList.SubmenuRequest,~Component.Component,~factory,Factory{host,component,steps,complete,cancel})
        return Owner{host,component,renderCallback,inputCallback,invalidateCallback,factoryCallback,themeOwner,modelOptions,levelOptions,levelTitle,modelPreselect,levelPreselect,complete,cancel}
def createHost(parent: Component.Component,+theme: Ref.Ref<Theme.Theme>,session: Ref.Ref<Session.AgentSession>,models: Ref.Ref<List<&2,Models.Model()>>,transcript: Transcript.Handle,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,words: Ref.Ref<Words.Source>) -> IO(Owner):
  do IO<Owner>:
    owner : Submenu.ThemeOwner <- Submenu.createTheme(theme)
    configured(Submenu.theme(owner),parent,theme,session,models,transcript,bindings,keyboard,words)
def factoryOf(owner: Owner) -> C.Callback<SettingsList.SubmenuRequest,Component.Component>:
  match owner: case Owner{_,_,_,_,_,factory,_,_,_,_,_,_,_,_}: factory
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,_,_,_,_,_,_,collator},_,render,input,invalidate,factory,themeOwner,modelOptions,levelOptions,levelTitle,modelPreselect,levelPreselect,complete,cancel}:
      do IO<Unit>:
        discarded : Modal <- Ref.dispose(Modal,modal)
        unused : Maybe<&2,Collation.Collator> <- Ref.dispose(Maybe<&2,Collation.Collator>,collator)
        C.dispose(Nat,List<&2,String>,render)
        C.dispose(String,Unit,input)
        C.dispose(Unit,Unit,invalidate)
        C.dispose(SettingsList.SubmenuRequest,Component.Component,factory)
        C.dispose(Submenu.Context(),List<&2,Select.SelectItem>,modelOptions)
        C.dispose(Submenu.Context(),List<&2,Select.SelectItem>,levelOptions)
        C.dispose(Submenu.Context(),String,levelTitle)
        C.dispose(Submenu.Context(),Maybe<&2,String>,modelPreselect)
        C.dispose(Submenu.Context(),Maybe<&2,String>,levelPreselect)
        C.dispose(Submenu.Context(),Unit,complete)
        C.dispose(Unit,Unit,cancel)
        Submenu.disposeTheme(themeOwner)
