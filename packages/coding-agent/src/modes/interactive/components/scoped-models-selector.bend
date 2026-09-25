import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../core/model-runtime.bend as Models
import ../model-search.bend as Search
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints

# All means no filter; Selected preserves the user's Ctrl+P cycling order.
type Scope is Data: All{} Selected{ids: List<&2,String>}
type Item is Data: Item{id: String,model: Maybe<&2,Models.Model()>,enabled: Bool}
type State is Data:
  State{models: List<&2,Models.Model()>,scope: Scope,visible: List<&2,Item>,selected: Nat,search: Input.Input,dirty: Bool,refreshStatus: String}
type Action is Data: Continue{} Cancel{} Changed{scope: Scope} Save{scope: Scope}

def contains(ids: List<&2,String>,+id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case candidate <> rest: String.eq(candidate,id) || contains(rest,id)
def remove(ids: List<&2,String>,+id: String) -> List<&2,String>:
  match ids:
    case Nil{}: Nil{}
    case +candidate <> +rest:
      Bool.pick(Unit -> List<&2,String>,String.eq(candidate,id),_ => remove(rest,id),_ => candidate <> remove(rest,id))(Unit{})
def removeMany(ids: List<&2,String>,+targets: List<&2,String>) -> List<&2,String>:
  match ids:
    case Nil{}: Nil{}
    case +candidate <> +rest:
      Bool.pick(Unit -> List<&2,String>,contains(targets,candidate),_ => removeMany(rest,targets),_ => candidate <> removeMany(rest,targets))(Unit{})
def appendMissing(targets: List<&2,String>,+ids: List<&2,String>) -> List<&2,String>:
  match targets:
    case Nil{}: ids
    case +id <> rest:
      appendMissing(rest,Bool.pick(List<&2,String>,contains(ids,id),ids,List.append(&2,String,ids,id <> Nil{})))
def idsOf(models: List<&2,Models.Model()>) -> List<&2,String>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: Models.reference(model) <> idsOf(rest)
def allPresent(all: List<&2,String>,+ids: List<&2,String>) -> Bool:
  match all:
    case Nil{}: True{}
    case id <> rest: contains(ids,id) && allPresent(rest,ids)
def coversAll(+ids: List<&2,String>,+all: List<&2,String>) -> Bool:
  Nat.is_eq(List.length(&2,String,ids),List.length(&2,String,all)) && allPresent(all,ids)
def normalize(+ids: List<&2,String>,all: List<&2,String>) -> Scope:
  Bool.pick(Unit -> Scope,coversAll(ids,all),_ => All{},_ => Selected{ids})(Unit{})
def enabled(scope: Scope,+id: String) -> Bool:
  match scope:
    case All{}: True{}
    case Selected{ids}: contains(ids,id)
def toggle(scope: Scope,all: List<&2,String>,+id: String) -> Scope:
  match scope:
    case All{}: Selected{remove(all,id)}
    case Selected{+ids}:
      Bool.pick(Unit -> Scope,contains(ids,id),_ => Selected{remove(ids,id)},_ => normalize(List.append(&2,String,ids,id <> Nil{}),all))(Unit{})
def enable(scope: Scope,all: List<&2,String>,targets: List<&2,String>) -> Scope:
  match scope:
    case All{}: All{}
    case Selected{ids}: normalize(appendMissing(targets,ids),all)
def clear(scope: Scope,all: List<&2,String>,targets: List<&2,String>) -> Scope:
  match scope:
    case All{}: Selected{removeMany(all,targets)}
    case Selected{ids}: Selected{removeMany(ids,targets)}
def swap(ids: List<&2,String>,index: Nat) -> List<&2,String>:
  match ids index:
    case first <> (second <> rest) Zero{}: second <> first <> rest
    case item <> rest Succ{index}: item <> swap(rest,index)
    case _ _: ids
def position(ids: List<&2,String>,+id: String,+index: Nat) -> Maybe<&2,Nat>:
  match ids:
    case Nil{}: None{}
    case candidate <> rest:
      Bool.pick(Maybe<&2,Nat>,String.eq(candidate,id),Some{index},position(rest,id,index + 1n))
def reorderedAt(+ids: List<&2,String>,up: Bool,found: Maybe<&2,Nat>) -> List<&2,String>:
  match found:
    case None{}: ids
    case Some{+index}:
      Bool.pick(Unit -> List<&2,String>,up,
        _ => Bool.pick(Unit -> List<&2,String>,Nat.is_eq(index,0n),_ => ids,_ => swap(ids,index - 1n))(Unit{}),
        _ => Bool.pick(Unit -> List<&2,String>,Nat.is_ge(index + 1n,List.length(&2,String,ids)),_ => ids,_ => swap(ids,index))(Unit{}))(Unit{})
def reordered(+ids: List<&2,String>,id: String,up: Bool) -> List<&2,String>:
  reorderedAt(ids,up,position(ids,id,0n))
def reorder(scope: Scope,id: String,up: Bool) -> Scope:
  match scope:
    case All{}: All{}
    case Selected{ids}: Selected{reordered(ids,id,up)}
def remaining(ids: List<&2,String>,+enabledIds: List<&2,String>) -> List<&2,String>:
  match ids:
    case Nil{}: Nil{}
    case +id <> +rest: Bool.pick(Unit -> List<&2,String>,contains(enabledIds,id),_ => remaining(rest,enabledIds),_ => id <> remaining(rest,enabledIds))(Unit{})
def sorted(scope: Scope,all: List<&2,String>) -> List<&2,String>:
  match scope:
    case All{}: all
    case Selected{+ids}: List.append(&2,String,ids,remaining(all,ids))
def findModel(models: List<&2,Models.Model()>,+id: String) -> Maybe<&2,Models.Model()>:
  match models:
    case Nil{}: None{}
    case +model <> rest:
      Bool.pick(Unit -> Maybe<&2,Models.Model()>,String.eq(Models.reference(model),id),_ => Some{model},_ => findModel(rest,id))(Unit{})
def buildItems(+models: List<&2,Models.Model()>,+scope: Scope,ids: List<&2,String>) -> List<&2,Item>:
  match ids:
    case Nil{}: Nil{}
    case +id <> rest: Item{id,findModel(models,id),enabled(scope,id)} <> buildItems(models,scope,rest)
def searchText(item: Item) -> String:
  match item:
    case Item{id,None{},_}: id
    case Item{_,Some{model},_}: Search.getModelSearchText(Search.searchItem(model))
def filtered(+items: List<&2,Item>,+query: String) -> List<&2,Item>:
  Bool.pick(Unit -> List<&2,Item>,String.is_empty(query),_ => items,_ => Fuzzy.fuzzyFilter(~Item,~searchText,items,query))(Unit{})
def rebuild(+models: List<&2,Models.Model()>,+scope: Scope,+search: Input.Input,selected: Nat,dirty: Bool,status: String) -> State:
  +all = idsOf(models)
  +visible = filtered(buildItems(models,scope,sorted(scope,all)),Input.getValue(search))
  +index = Nat.min(selected,List.length(&2,Item,visible) - 1n)
  State{models,scope,visible,index,search,dirty,status}
def create(models: List<&2,Models.Model()>,scope: Scope,status: String) -> State:
  rebuild(models,scope,Input.setFocused(Input.new(None{}),True{}),0n,False{},status)
def updateModels(state: State,models: List<&2,Models.Model()>,status: String) -> State:
  match state:
    case State{_,scope,_,selected,search,dirty,_}: rebuild(models,scope,search,selected,dirty,status)
def selectedItem(state: State) -> Maybe<&2,Item>:
  match state: case State{_,_,items,index,_,_,_}: List.get(&2,Item,items,index)
def modelsOf(state: State) -> List<&2,Models.Model()>:
  match state: case State{models,_,_,_,_,_,_}: models
def scopeOf(state: State) -> Scope:
  match state: case State{_,scope,_,_,_,_,_}: scope
def itemIds(items: List<&2,Item>) -> List<&2,String>:
  match items:
    case Nil{}: Nil{}
    case Item{id,_,_} <> rest: id <> itemIds(rest)
def targetIds(state: State) -> List<&2,String>:
  match state:
    case State{models,_,items,_,search,_,_}:
      Bool.pick(List<&2,String>,String.is_empty(Input.getValue(search)),idsOf(models),itemIds(items))
def changed(state: State,+scope: Scope) -> State & Action:
  match state:
    case State{models,_,_,selected,search,_,status}:
      (rebuild(models,scope,search,selected,True{},status),Changed{scope})
def moved(state: State,up: Bool) -> State:
  match state:
    case State{models,scope,+items,+index,search,dirty,status}:
      +count = List.length(&2,Item,items)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{models,scope,items,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),search,dirty,status}
def toggleFound(+state: State,found: Maybe<&2,Item>) -> State & Action:
  match found:
    case None{}: (state,Continue{})
    case Some{Item{id,_,_}}: changed(state,toggle(scopeOf(state),idsOf(modelsOf(state)),id))
def toggleSelected(+state: State) -> State & Action: toggleFound(state,selectedItem(state))
def enableTargets(+state: State) -> State & Action:
  changed(state,enable(scopeOf(state),idsOf(modelsOf(state)),targetIds(state)))
def clearTargets(+state: State) -> State & Action:
  changed(state,clear(scopeOf(state),idsOf(modelsOf(state)),targetIds(state)))
def providerTargets(models: List<&2,Models.Model()>,+provider: String) -> List<&2,String>:
  match models:
    case Nil{}: Nil{}
    case +model <> +rest:
      Bool.pick(Unit -> List<&2,String>,String.eq(Models.modelProvider(model),provider),_ => Models.reference(model) <> providerTargets(rest,provider),_ => providerTargets(rest,provider))(Unit{})
def scopeIds(scope: Scope,all: List<&2,String>) -> List<&2,String>:
  match scope:
    case All{}: all
    case Selected{ids}: ids
def toggleProviderFound(+state: State,found: Maybe<&2,Item>) -> State & Action:
  match found:
    case Some{Item{_,Some{model},_}}:
      +models = modelsOf(state)
      +scope = scopeOf(state)
      +targets = providerTargets(models,Models.modelProvider(model))
      +all = idsOf(models)
      +allOn = allPresent(targets,scopeIds(scope,all))
      changed(state,Bool.pick(Unit -> Scope,allOn,_ => clear(scope,all,targets),_ => enable(scope,all,targets))(Unit{}))
    case _: (state,Continue{})
def toggleProvider(+state: State) -> State & Action: toggleProviderFound(state,selectedItem(state))
def reorderAllowedAt(found: Maybe<&2,Nat>,up: Bool,count: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{+index}: Bool.pick(Bool,up,Nat.is_gt(index,0n),Nat.is_lt(index + 1n,count))
def reorderChoice(+state: State,scope: Scope,+id: String,+up: Bool) -> State & Action:
  match scope:
    case All{}: (state,Continue{})
    case Selected{+ids}:
      Bool.pick(Unit -> State & Action,reorderAllowedAt(position(ids,id,0n),up,List.length(&2,String,ids)),
        _ => changed(moved(state,up),Selected{reordered(ids,id,up)}),_ => (state,Continue{}))(Unit{})
def reorderFound(+state: State,up: Bool,found: Maybe<&2,Item>) -> State & Action:
  match found:
    case None{}: (state,Continue{})
    case Some{Item{id,_,False{}}}: (state,Continue{})
    case Some{Item{id,_,True{}}}:
      reorderChoice(state,scopeOf(state),id,up)
def reorderSelected(+state: State,up: Bool) -> State & Action: reorderFound(state,up,selectedItem(state))
def saved(state: State) -> State & Action:
  match state:
    case State{models,+scope,items,index,search,_,status}: (State{models,scope,items,index,search,False{},status},Save{scope})
def nonAtomic(_: Segmenter.Source,_: String) -> Bool: False{}
def editedDone(state: State,input: Input.Input) -> State & Action:
  match state:
    case State{models,scope,_,selected,_,dirty,status}: (rebuild(models,scope,input,selected,dirty,status),Continue{})
def edited(state: State,result: Word.ResultOf(Input.Input)) -> State & Action:
  match result:
    case Done{input}: editedDone(state,input)
    case Fail{_}: (state,Continue{})
def otherInput(+state: State,source: Segmenter.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(State & Action):
  match state:
    case State{_,_,_,_,search,_,_}:
      do IO<State & Action>:
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,search,bindings,keyboard,data)
        return edited(state,result)
def searchOf(state: State) -> Input.Input:
  match state: case State{_,_,_,_,search,_,_}: search
def clearSearch(state: State) -> State:
  match state:
    case State{models,scope,_,_,search,dirty,status}: rebuild(models,scope,Input.setValue(search,""),0n,dirty,status)
def cancelInput(+state: State,keyboard: Keys.Context,data: String) -> State & Action:
  +ctrlC = Keys.matchesKey(keyboard,data,Keys.ctrl(Keys.Printable{'c'}))
  +hasSearch = Bool.not(String.is_empty(Input.getValue(searchOf(state))))
  Bool.pick(State & Action,ctrlC && hasSearch,(clearSearch(state),Continue{}),(state,Cancel{}))
type KeyCommand is Data:
  MoveUp{} MoveDown{} ReorderUp{} ReorderDown{} Toggle{} EnableAll{} ClearAll{} ToggleProvider{} Persist{} CancelKey{} OtherKey{}
type KeyBinding is Data: KeyBinding{name: String,command: KeyCommand}
def keyCommands() -> List<&2,KeyBinding>:
  KeyBinding{"tui.select.up",MoveUp{}} <>
  KeyBinding{"tui.select.down",MoveDown{}} <>
  KeyBinding{"app.models.reorderUp",ReorderUp{}} <>
  KeyBinding{"app.models.reorderDown",ReorderDown{}} <>
  KeyBinding{"tui.select.confirm",Toggle{}} <>
  KeyBinding{"app.models.enableAll",EnableAll{}} <>
  KeyBinding{"app.models.clearAll",ClearAll{}} <>
  KeyBinding{"app.models.toggleProvider",ToggleProvider{}} <>
  KeyBinding{"app.models.save",Persist{}} <>
  KeyBinding{"tui.select.cancel",CancelKey{}} <> Nil{}
def findKey(keys: List<&2,KeyBinding>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> KeyCommand:
  match keys:
    case Nil{}: OtherKey{}
    case KeyBinding{name,+command} <> +rest:
      Bool.pick(Unit -> KeyCommand,Bindings.matches(bindings,keyboard,data,name),_ => command,_ => findKey(rest,bindings,keyboard,data))(Unit{})
def respond(state: State,source: Segmenter.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String,command: KeyCommand) -> IO(State & Action):
  match command:
    case MoveUp{}: IO.pure(State & Action,(moved(state,True{}),Continue{}))
    case MoveDown{}: IO.pure(State & Action,(moved(state,False{}),Continue{}))
    case ReorderUp{}: IO.pure(State & Action,reorderSelected(state,True{}))
    case ReorderDown{}: IO.pure(State & Action,reorderSelected(state,False{}))
    case Toggle{}: IO.pure(State & Action,toggleSelected(state))
    case EnableAll{}: IO.pure(State & Action,enableTargets(state))
    case ClearAll{}: IO.pure(State & Action,clearTargets(state))
    case ToggleProvider{}: IO.pure(State & Action,toggleProvider(state))
    case Persist{}: IO.pure(State & Action,saved(state))
    case CancelKey{}: IO.pure(State & Action,cancelInput(state,keyboard,data))
    case OtherKey{}: otherInput(state,source,bindings,keyboard,data)
def input(state: State,source: Segmenter.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(State & Action):
  respond(state,source,bindings,keyboard,data,findKey(keyCommands(),bindings,keyboard,data))

def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def statusColor(+status: String) -> String:
  Bool.pick(String,String.eq(status,"Model catalogs refreshed."),"success",Bool.pick(String,String.eq(status,"Refreshing model catalogs…"),"muted","warning"))
def border(width: Nat) -> String: String.repeat("─",width)
def label(item: Item) -> String:
  match item:
    case Item{id,None{},_}: "\u{1b}[9m" ++ id ++ "\u{1b}[29m"
    case Item{_,Some{model},_}: Models.modelId(model)
def providerBadge(item: Item) -> String:
  match item:
    case Item{_,None{},_}: " [unavailable]"
    case Item{_,Some{model},_}: " [" ++ Models.modelProvider(model) ++ "]"
def enabledMark(item: Item) -> Bool:
  match item:
    case Item{_,Some{_},True{}}: True{}
    case _: False{}
def row(+item: Item,+selected: Bool,+theme: Theme.Theme,width: Nat) -> String:
  +prefix = Bool.pick(String,selected,paint(theme,"accent","→ "),"  ")
  +mark = Bool.pick(String,enabledMark(item),paint(theme,"accent","✓ "),"  ")
  +name = label(item)
  +main = Bool.pick(String,selected,paint(theme,"accent",name),name)
  Utils.truncateToWidth(prefix ++ mark ++ main ++ paint(theme,"muted",providerBadge(item)),width,"",False{})
def rows(items: List<&2,Item>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match items skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: rows(rest,skip,remaining,index + 1n,selected,theme,width)
    case item <> rest Zero{} Succ{remaining}: row(item,Nat.is_eq(index,selected),theme,width) <> rows(rest,0n,remaining,index + 1n,selected,theme,width)
def detail(found: Maybe<&2,Item>,theme: Theme.Theme) -> List<&2,String>:
  match found:
    case None{}: Nil{}
    case Some{Item{_,None{},_}}: "" <> paint(theme,"muted","  Model unavailable") <> Nil{}
    case Some{Item{_,Some{model},_}}: "" <> paint(theme,"muted","  Model Name: " ++ Models.modelName(model)) <> Nil{}
def unavailableCount(ids: List<&2,String>,+models: List<&2,Models.Model()>) -> Nat:
  match ids:
    case Nil{}: 0n
    case id <> rest: Bool.pick(Nat,Maybe.is_some(&2,Models.Model(),findModel(models,id)),0n,1n) + unavailableCount(rest,models)
def enabledCount(ids: List<&2,String>,+models: List<&2,Models.Model()>) -> Nat:
  match ids:
    case Nil{}: 0n
    case id <> rest: Bool.pick(Nat,Maybe.is_some(&2,Models.Model(),findModel(models,id)),1n,0n) + enabledCount(rest,models)
def countText(scope: Scope,+models: List<&2,Models.Model()>) -> String:
  match scope:
    case All{}: "all enabled"
    case Selected{+ids}:
      +available = enabledCount(ids,models)
      +missing = unavailableCount(ids,models)
      Nat.show(available) ++ "/" ++ Nat.show(List.length(&2,Models.Model(),models)) ++ " enabled" ++ Bool.pick(String,Nat.is_gt(missing,0n)," · " ++ Nat.show(missing) ++ " unavailable","")
def footer(scope: Scope,models: List<&2,Models.Model()>,+dirty: Bool,+bindings: Bindings.KeybindingsManager,+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  +parts = String.join([
    Hints.keyDisplayText(bindings,"tui.select.confirm") ++ " toggle",
    Hints.keyDisplayText(bindings,"app.models.enableAll") ++ " all",
    Hints.keyDisplayText(bindings,"app.models.clearAll") ++ " clear",
    Hints.keyDisplayText(bindings,"app.models.toggleProvider") ++ " provider",
    Hints.keyDisplayText(bindings,"app.models.reorderUp") ++ "/" ++ Hints.keyDisplayText(bindings,"app.models.reorderDown") ++ " reorder",
    Hints.keyDisplayText(bindings,"app.models.save") ++ " save",
    countText(scope,models)
  ]," · ")
  +hint = paint(theme,"dim","  " ++ parts ++ Bool.pick(String,dirty," ","")) ++ Bool.pick(String,dirty,paint(theme,"warning","(unsaved)"),"")
  Utils.wrapTextWithAnsi(hint,width)
def body(+items: List<&2,Item>,+index: Nat,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  +count = List.length(&2,Item,items)
  +start = Nat.min(index - 4n,count - Nat.min(count,8n))
  +visible = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching models") <> Nil{},rows(items,start,8n,0n,index,theme,width))
  +scroll = Bool.pick(List<&2,String>,Nat.is_gt(start,0n) || Nat.is_gt(count,start + 8n),paint(theme,"muted","  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")") <> Nil{},Nil{})
  List.append(&2,String,visible,List.append(&2,String,scroll,detail(List.get(&2,Item,items,index),theme)))
def renderedState(state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat,search: Input.Input,searchLines: List<&2,String>) -> State & List<&2,String>:
  match state:
    case State{+models,+scope,+visible,+index,_,+dirty,+status}:
      +lines = List.concat(&2,String,[
        [paint(theme,"border",border(width)),"",paint(theme,"accent",Theme.bold("Model Configuration")),paint(theme,"muted","Session-only. " ++ Hints.keyDisplayText(bindings,"app.models.save") ++ " to save to settings."),""],
        searchLines,[""],body(visible,index,theme,width),[""],
        Bool.pick(List<&2,String>,String.is_empty(status),Nil{},paint(theme,statusColor(status),"  " ++ status) <> Nil{}),
        footer(scope,models,dirty,bindings,theme,width),[paint(theme,"border",border(width))]
      ])
      (State{models,scope,visible,index,search,dirty,status},lines)
def renderedPair(state: State,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,width: Nat,pair: Input.Input & List<&2,String>) -> State & List<&2,String>:
  match pair:
    case (search,lines): renderedState(state,theme,bindings,width,search,lines)
def render(+state: State,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,+width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{_,_,_,_,+search,_,_}:
      do IO<State & List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(search,width)
        return renderedPair(state,theme,bindings,width,pair)

type Modal is Data: Closed{} Open{state: State}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Ref.Ref<Segmenter.Source>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,notify: Callback.Callback<Action,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}
def displayedPair(modal: Ref.Ref<Modal>,pair: State & List<&2,String>) -> IO(List<&2,String>):
  match pair:
    case (next,lines):
      do IO<List<&2,String>>:
        Ref.write(Modal,modal,Open{next})
        return lines
def displayed(modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,width: Nat,current: Modal) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        chosenTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        pair : State & List<&2,String> <- render(state,chosenTheme,bindings,width)
        displayedPair(modal,pair)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,theme,_,bindings,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        displayed(modal,editor,theme,bindings,width,current)
def accepted(modal: Ref.Ref<Modal>,notify: Callback.Callback<Action,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,Continue{}): Ref.write(Modal,modal,Open{state})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (state,Changed{scope}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{state})
        Callback.call(Action,Unit,notify,Changed{scope})
    case (state,Save{scope}):
      do IO<Unit>:
        Ref.write(Modal,modal,Open{state})
        Callback.call(Action,Unit,notify,Save{scope})
def receiveCurrent(modal: Ref.Ref<Modal>,editor: Component.Component,words: Ref.Ref<Segmenter.Source>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,notify: Callback.Callback<Action,Unit>,data: String,current: Modal) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}:
      do IO<Unit>:
        source : Segmenter.Source <- Ref.read(Segmenter.Source,words)
        pair : State & Action <- input(state,source,bindings,keyboard,data)
        accepted(modal,notify,pair)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,words,bindings,keyboard,notify}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(modal,editor,words,bindings,keyboard,notify,data,current)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(editor: Component.Component,event: Tui.TuiMouseEvent,current: Modal) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{_}: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,editor,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(editor,event,current)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Segmenter.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,notify: Callback.Callback<Action,Unit>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    source : Ref.Ref<Segmenter.Source> <- Ref.new(Segmenter.Source,words)
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,source,bindings,keyboard,notify})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host,state: State) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_}: Ref.write(Modal,modal,Open{state})
def refreshedCurrent(modal: Ref.Ref<Modal>,models: List<&2,Models.Model()>,status: String,current: Modal) -> IO(Unit):
  match current:
    case Closed{}: IO.pure(Unit,Unit{})
    case Open{state}: Ref.write(Modal,modal,Open{updateModels(state,models,status)})
def refreshed(host: Host,models: List<&2,Models.Model()>,status: String) -> IO(Unit):
  match host:
    case Host{+modal,_,_,_,_,_,_}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        refreshedCurrent(modal,models,status,current)
def close(host: Host) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_}: Ref.write(Modal,modal,Closed{})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,words,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        source : Segmenter.Source <- Ref.dispose(Segmenter.Source,words)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
