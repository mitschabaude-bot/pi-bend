import Base
import ../../../../../runtime/src/stable-sort.bend as Sort
import ../../../../../runtime/src/collation.bend as Collation
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/components/text.bend as Text
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../core/model-runtime.bend as Models
import ../theme/theme.bend as Theme
import ../model-search.bend as Search
import ./keybinding-hints.bend as Hints

# A searchable, mounted catalog selector. The catalog is already limited to
# authenticated providers by ModelRuntime; selection carries the real model.
type State is Data:
  State{all: List<&2,Models.Model()>,scoped: List<&2,Models.Model()>,visible: List<&2,Models.Model()>,selected: Nat,query: Input.Input,current: Maybe<&2,Models.Model()>,defaultRef: Maybe<&2,String>,scopedMode: Bool,status: String,searchRow: Maybe<&2,Nat>}
type Action is Data: Continue{} Cancel{} Chosen{model: Models.Model(),persist: Bool}
type Choice is Data: Choice{model: Models.Model(),persist: Bool}

def sameModel(+left: Models.Model(),+right: Models.Model()) -> Bool:
  String.eq(Models.modelProvider(left),Models.modelProvider(right)) && String.eq(Models.modelId(left),Models.modelId(right))
def isCurrent(model: Models.Model(),current: Maybe<&2,Models.Model()>) -> Bool:
  match current:
    case None{}: False{}
    case Some{value}: sameModel(model,value)
def currentFirst(items: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+other: List<&2,Models.Model()>) -> List<&2,Models.Model()>:
  match items:
    case Nil{}: List.reverse(&2,Models.Model(),other)
    case +model <> +rest:
      Bool.pick(Unit -> List<&2,Models.Model()>,isCurrent(model,current),_ => model <> List.append(&2,Models.Model(),List.reverse(&2,Models.Model(),other),rest),_ => currentFirst(rest,current,model <> other))(Unit{})
def isDefault(model: Models.Model(),defaultRef: Maybe<&2,String>) -> Bool:
  match defaultRef: case None{}: False{} case Some{reference}: String.eq(Models.reference(model),reference)
type SearchItem is Data: SearchItem{model: Models.Model(),text: String}
def searchText(item: SearchItem) -> String: match item: case SearchItem{_,text}: text
def searchItems(items: List<&2,Models.Model()>,+defaultRef: Maybe<&2,String>) -> List<&2,SearchItem>:
  match items:
    case Nil{}: Nil{}
    case +model <> rest: SearchItem{model,Search.modelSelectorText(model) ++ Bool.pick(String,isDefault(model,defaultRef)," default","")} <> searchItems(rest,defaultRef)
def searchModels(items: List<&2,SearchItem>) -> List<&2,Models.Model()>:
  match items: case Nil{}: Nil{} case SearchItem{model,_} <> rest: model <> searchModels(rest)
def defaults(items: List<&2,Models.Model()>,+defaultRef: Maybe<&2,String>,+wanted: Bool) -> List<&2,Models.Model()>:
  match items:
    case Nil{}: Nil{}
    case +model <> rest:
      +tail = defaults(rest,defaultRef,wanted)
      Bool.pick(List<&2,Models.Model()>,Bool.pick(Bool,wanted,isDefault(model,defaultRef),Bool.not(isDefault(model,defaultRef))),model <> tail,tail)
def defaultSearch(+query: String) -> Bool:
  +normalized = String.to_lower(String.trim(query))
  Bool.not(String.is_empty(normalized)) && String.starts_with("default",normalized)
def filtered(+items: List<&2,Models.Model()>,query: String,+defaultRef: Maybe<&2,String>) -> List<&2,Models.Model()>:
  match query:
    case SNil{}: items
    case +query:
      +matches = searchModels(Fuzzy.fuzzyFilter(~SearchItem,~searchText,searchItems(items,defaultRef),query))
      Bool.pick(List<&2,Models.Model()>,defaultSearch(query),List.append(&2,Models.Model(),defaults(items,defaultRef,True{}),defaults(matches,defaultRef,False{})),matches)
type OrderedModel is Data: OrderedModel{model: Models.Model(),priority: Nat,provider: Collation.Key}
def providerOrder(left: Cmp) -> Bool: match left: case GT{}: False{} case _: True{}
def orderedBefore(left: OrderedModel,right: OrderedModel) -> Bool:
  match left right:
    case OrderedModel{_,+a,ka} OrderedModel{_,+b,kb}:
      Nat.is_lt(a,b) || (Nat.is_eq(a,b) && providerOrder(Collation.compareKeys(ka,kb)))
def orderedItems(items: List<&2,Models.Model()>,+collator: Collation.Collator,+current: Maybe<&2,Models.Model()>,+defaultRef: Maybe<&2,String>) -> List<&2,OrderedModel>:
  match items:
    case Nil{}: Nil{}
    case +model <> rest: OrderedModel{model,Bool.pick(Nat,isCurrent(model,current),0n,Bool.pick(Nat,isDefault(model,defaultRef),1n,2n)),Collation.key(collator,Models.modelProvider(model))} <> orderedItems(rest,collator,current,defaultRef)
def orderedModels(items: List<&2,OrderedModel>) -> List<&2,Models.Model()>:
  match items: case Nil{}: Nil{} case OrderedModel{model,_,_} <> rest: model <> orderedModels(rest)
def sortedModels(items: List<&2,Models.Model()>,collator: Collation.Collator,current: Maybe<&2,Models.Model()>,defaultRef: Maybe<&2,String>) -> List<&2,Models.Model()>:
  orderedModels(Sort.sort(~OrderedModel,~orderedBefore,orderedItems(items,collator,current,defaultRef)))
def currentIndex(items: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+index: Nat) -> Nat:
  match items:
    case Nil{}: 0n
    case model <> rest:
      Bool.pick(Unit -> Nat,isCurrent(model,current),_ => index,_ => currentIndex(rest,current,index + 1n))(Unit{})
def hasScope(items: List<&2,Models.Model()>) -> Bool: Bool.not(List.is_empty(&2,Models.Model(),items))
def hasScopeOf(state: State) -> Bool:
  match state: case State{_,scoped,_,_,_,_,_,_,_,_}: hasScope(scoped)
def initial(items: List<&2,Models.Model()>,+scoped: List<&2,Models.Model()>,+current: Maybe<&2,Models.Model()>,+query: String,+defaultRef: Maybe<&2,String>,status: String) -> State:
  +ordered = currentFirst(items,current,Nil{})
  +scope = hasScope(scoped)
  +active = Bool.pick(List<&2,Models.Model()>,scope,scoped,ordered)
  +visible = filtered(active,query,defaultRef)
  +selected = Bool.pick(Nat,String.is_empty(query),currentIndex(visible,current,0n),0n)
  State{ordered,scoped,visible,selected,Input.setFocused(Input.setValue(Input.new(None{}),query),True{}),current,defaultRef,scope,status,None{}}
def create(items: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: String,_height: Nat) -> State:
  initial(items,Nil{},current,query,None{},"")
def createScoped(items: List<&2,Models.Model()>,scoped: List<&2,Models.Model()>,current: Maybe<&2,Models.Model()>,query: String,defaultRef: Maybe<&2,String>) -> State:
  initial(items,scoped,current,query,defaultRef,"Refreshing model catalogs…")
def withQuery(state: State,+query: Input.Input) -> State:
  match state:
    case State{+all,+scoped,_,+index,_,current,+defaultRef,+mode,status,_}:
      +active = Bool.pick(List<&2,Models.Model()>,mode,scoped,all)
      +visible = filtered(active,Input.getValue(query),defaultRef)
      State{all,scoped,visible,Bool.pick(Nat,String.is_empty(Input.getValue(query)),Nat.min(index,List.length(&2,Models.Model(),visible) - 1n),0n),query,current,defaultRef,mode,status,None{}}
def toggled(state: State) -> State:
  match state:
    case State{+all,+scoped,_,_,+query,+current,+defaultRef,+mode,status,_}:
      +next = Bool.not(mode)
      +active = Bool.pick(List<&2,Models.Model()>,next,scoped,all)
      +visible = filtered(active,Input.getValue(query),defaultRef)
      +selected = Bool.pick(Nat,String.is_empty(Input.getValue(query)),currentIndex(visible,current,0n),0n)
      State{all,scoped,visible,selected,query,current,defaultRef,next,status,None{}}
def toggleIfScoped(+state: State) -> State:
  Bool.pick(Unit -> State,hasScopeOf(state),_ => toggled(state),_ => state)(Unit{})
def refreshedState(state: State,models: List<&2,Models.Model()>,status: String) -> State:
  match state:
    case State{_,+scoped,_,_,+query,+current,+defaultRef,+mode,_,_}:
      +ordered = currentFirst(models,current,Nil{})
      +active = Bool.pick(List<&2,Models.Model()>,mode,scoped,ordered)
      +visible = filtered(active,Input.getValue(query),defaultRef)
      +index = Bool.pick(Nat,String.is_empty(Input.getValue(query)),currentIndex(visible,current,0n),0n)
      State{ordered,scoped,visible,index,query,current,defaultRef,mode,status,None{}}
def sortedState(state: State,collator: Collation.Collator) -> State:
  match state:
    case State{all,+scoped,_,+index,+query,+current,+defaultRef,+mode,status,row}:
      +ordered = sortedModels(all,collator,current,defaultRef)
      +visible = filtered(Bool.pick(List<&2,Models.Model()>,mode,scoped,ordered),Input.getValue(query),defaultRef)
      +selected = Bool.pick(Nat,String.is_empty(Input.getValue(query)),currentIndex(visible,current,0n),Nat.min(index,List.length(&2,Models.Model(),visible) - 1n))
      State{ordered,scoped,visible,selected,query,current,defaultRef,mode,status,row}
def selected(state: State) -> Maybe<&2,Models.Model()>:
  match state: case State{_,_,visible,index,_,_,_,_,_,_}: List.get(&2,Models.Model(),visible,index)
def count(state: State) -> Nat:
  match state: case State{_,_,visible,_,_,_,_,_,_,_}: List.length(&2,Models.Model(),visible)
def queryOf(state: State) -> String:
  match state: case State{_,_,_,_,query,_,_,_,_,_}: Input.getValue(query)
def move(state: State,up: Bool) -> State:
  match state:
    case State{all,scoped,+visible,+index,query,current,defaultRef,mode,status,_}:
      +count = List.length(&2,Models.Model(),visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{all,scoped,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),query,current,defaultRef,mode,status,None{}}
def selectFound(state: State,model: Maybe<&2,Models.Model()>,persist: Bool) -> State & Action:
  match model:
    case None{}: (state,Continue{})
    case Some{value}: (state,Chosen{value,persist})
def edited(state: State,result: Word.ResultOf(Input.Input)) -> State & Action:
  match result: case Done{input}: (withQuery(state,input),Continue{}) case Fail{_}: (state,Continue{})
def nonAtomic(_: Words.Source,_: String) -> Bool: False{}
def otherInput(+state: State,source: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(State & Action):
  match state:
    case State{_,_,_,_,+search,_,_,_,_,_}:
      do IO<State & Action>:
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Words.Source,~Word.sourceSegments,~nonAtomic,source,search,bindings,keyboard,data)
        return edited(state,result)
def input(+state: State,source: Words.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"app.models.save"),_ => IO.pure(State & Action,selectFound(state,selected(state),True{})),
    _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.input.tab"),_ => IO.pure(State & Action,(toggleIfScoped(state),Continue{})),
    _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => IO.pure(State & Action,(move(state,True{}),Continue{})),
    _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => IO.pure(State & Action,(move(state,False{}),Continue{})),
      _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => IO.pure(State & Action,selectFound(state,selected(state),False{})),
        _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => IO.pure(State & Action,(state,Cancel{})),_ => otherInput(state,source,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def shade(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.background(theme,key,text),text)
def line(+model: Models.Model(),current: Maybe<&2,Models.Model()>,defaultRef: Maybe<&2,String>,+selected: Bool,+theme: Theme.Theme,width: Nat) -> String:
  +cursor = Bool.pick(String,selected,paint(theme,"accent","→ "),"  ")
  +marker = Bool.pick(String,isCurrent(model,current),paint(theme,"accent","✓ "),"  ")
  +id = Models.modelId(model)
  +name = Bool.pick(String,selected,paint(theme,"accent",id),id)
  +provider = " " ++ paint(theme,"muted","[" ++ Models.modelProvider(model) ++ "]")
  +defaultBadge = Bool.pick(String,isDefault(model,defaultRef),paint(theme,"muted"," · default"),"")
  cursor ++ marker ++ name ++ provider ++ defaultBadge
def rows(items: List<&2,Models.Model()>,skip: Nat,remaining: Nat,+index: Nat,+selected: Nat,+current: Maybe<&2,Models.Model()>,+defaultRef: Maybe<&2,String>,+theme: Theme.Theme,+width: Nat) -> List<&2,String>:
  match items skip remaining:
    case _ _ Zero{}: Nil{}
    case Nil{} _ _: Nil{}
    case _ <> rest Succ{skip} _: rows(rest,skip,remaining,index + 1n,selected,current,defaultRef,theme,width)
    case model <> rest Zero{} Succ{remaining}:
      line(model,current,defaultRef,Nat.is_eq(index,selected),theme,width) <> rows(rest,0n,remaining,index + 1n,selected,current,defaultRef,theme,width)
def scopeText(+mode: Bool,+theme: Theme.Theme) -> String:
  paint(theme,"muted","Scope: ") ++ Bool.pick(String,mode,paint(theme,"muted","all"),paint(theme,"accent","all")) ++ paint(theme,"muted"," | ") ++ Bool.pick(String,mode,paint(theme,"accent","scoped"),paint(theme,"muted","scoped"))
def scopeLines(scoped: List<&2,Models.Model()>,mode: Bool,+theme: Theme.Theme,bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  match scoped:
    case Nil{}: paint(theme,"warning","Only showing models from configured providers. Use /login to add providers.") <> Nil{}
    case _: scopeText(mode,theme) <> (Hints.keyHint(theme,bindings,"tui.input.tab","scope") ++ paint(theme,"muted"," (all/scoped)")) <> Nil{}
def detail(found: Maybe<&2,Models.Model()>,theme: Theme.Theme) -> List<&2,String>:
  match found:
    case None{}: Nil{}
    case Some{model}: "" <> paint(theme,"muted","  Model Name: " ++ Models.modelName(model)) <> Nil{}
def statusLines(+status: String,theme: Theme.Theme) -> List<&2,String>:
  +color = Bool.pick(String,String.eq(status,"Model catalogs refreshed."),"success",Bool.pick(String,String.eq(status,"Refreshing model catalogs…"),"muted","error"))
  Bool.pick(List<&2,String>,String.is_empty(status),Nil{},"" <> paint(theme,color,"  " ++ status) <> Nil{})
def border(width: Nat) -> String: String.repeat("─",width)
def textLines(pair: Text.Text & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def wrapped(text: String,width: Nat) -> IO(List<&2,String>):
  match text:
    case SNil{}: IO.pure(List<&2,String>,[""])
    case text:
      do IO<List<&2,String>>:
        pair : Text.Text & List<&2,String> <- Text.render(Text.new(text,Some{0n},Some{0n},None{}),width)
        return textLines(pair)
def wrapLines(lines: List<&2,String>,+width: Nat) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case line <> rest:
      do IO<List<&2,String>>:
        first : List<&2,String> <- wrapped(line,width)
        following : List<&2,String> <- wrapLines(rest,width)
        return List.append(&2,String,first,following)
def renderedState(state: State,+heading: List<&2,String>,pair: Input.Input & List<&2,String>,body: List<&2,String>) -> State & List<&2,String>:
  match state pair:
    case State{all,scoped,visible,index,_,current,defaultRef,mode,status,_} Tuple{query,search}:
      (State{all,scoped,visible,index,query,current,defaultRef,mode,status,Some{List.length(&2,String,heading)}},List.concat(&2,String,[heading,search,[""],body]))
def render(+state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{_,+scoped,+visible,+index,+query,current,defaultRef,mode,status,_}:
      do IO<State & List<&2,String>>:
        +count : Nat = List.length(&2,Models.Model(),visible)
        +start : Nat = Nat.min(index - 5n,count - Nat.min(count,10n))
        +body : List<&2,String> = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching models") <> Nil{},rows(visible,start,10n,0n,index,current,defaultRef,theme,width))
        +counter : List<&2,String> = Bool.pick(List<&2,String>,Nat.is_gt(count,10n),paint(theme,"muted","  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")") <> Nil{},Nil{})
        +hint : String = "  " ++ Hints.keyDisplayText(bindings,"tui.select.confirm") ++ " to select · " ++ Hints.keyDisplayText(bindings,"app.models.save") ++ " to set as default · " ++ Hints.keyDisplayText(bindings,"tui.select.cancel") ++ " to cancel"
        scope : List<&2,String> <- wrapLines(scopeLines(scoped,mode,theme,bindings),width)
        bodyLines : List<&2,String> <- wrapLines(List.concat(&2,String,[body,counter,detail(selected(state),theme),statusLines(status,theme),["",paint(theme,"dim",hint)]]),width)
        search : Input.Input & List<&2,String> <- Input.render(query,width)
        return renderedState(state,List.concat(&2,String,[[paint(theme,"border",border(width)),""],scope,[""]]),search,List.append(&2,String,bodyLines,[paint(theme,"border",border(width))]))

type Modal is Data: Closed{} Open{state: State}
def refreshedModal(current: Modal,models: List<&2,Models.Model()>,status: String) -> Modal & Bool:
  match current:
    case Closed{}: (Closed{},False{})
    case Open{state}: (Open{refreshedState(state,models,status)},True{})
type Host is Data:
  Host{modal: Ref.Ref<Modal>,words: Ref.Ref<Words.Source>,collator: Ref.Ref<Maybe<&2,Collation.Collator>>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}
def drawn(modal: Ref.Ref<Modal>,pair: State & List<&2,String>) -> IO(List<&2,String>):
  match pair:
    case (state,lines):
      do IO<List<&2,String>>:
        Ref.write(Modal,modal,Open{state})
        return lines
def drawCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,theme: Theme.Theme,bindings: Bindings.KeybindingsManager,width: Nat) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        pair : State & List<&2,String> <- render(state,theme,bindings,width)
        drawn(modal,pair)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,_,collator,editor,theme,bindings,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        chosenTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,modal,editor,chosenTheme,bindings,width)
def receiveOpen(modal: Ref.Ref<Modal>,chosen: Callback.Callback<Choice,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,Continue{}): Ref.write(Modal,modal,Open{state})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,Chosen{model,persist}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,chosen,Choice{model,persist})
def needsWords(command: Input.Command) -> Bool:
  match command:
    case Input.WordLeft{}: True{} case Input.WordRight{}: True{}
    case Input.KillWordBackward{}: True{} case Input.KillWordForward{}: True{}
    case _: False{}
def wordsFor(needed: Bool,source: Words.Source,text: String) -> IO(Words.Source):
  match needed: case True{}: Words.readyFor(source,text) case False{}: IO.pure(Words.Source,source)
def receiveCurrent(current: Modal,modal: Ref.Ref<Modal>,+words: Ref.Ref<Words.Source>,editor: Component.Component,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>,+data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{+state}:
      do IO<Unit>:
        stored : Words.Source <- Ref.read(Words.Source,words)
        +source : Words.Source <- wordsFor(needsWords(Input.command(Input.bindings(),bindings,keyboard,data)),stored,queryOf(state))
        Ref.write(Words.Source,words,source)
        pair : State & Action <- input(state,source,bindings,keyboard,data)
        receiveOpen(modal,chosen,pair)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,words,collator,editor,_,bindings,keyboard,chosen}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(current,modal,words,editor,bindings,keyboard,chosen,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseEdited(state: State,pair: Input.Input & Maybe<&2,Tui.TuiMouseEventResult>) -> State & Maybe<&2,Component.MouseResponse>:
  match pair state:
    case (search,response) State{all,scoped,visible,index,_,current,defaultRef,mode,status,row}:
      (State{all,scoped,visible,index,search,current,defaultRef,mode,status,row},Maybe.map(&2,Tui.TuiMouseEventResult,Component.MouseResponse,value => Component.LocalResult{value},response))
def mouseSearch(+state: State,event: Tui.TuiMouseEvent) -> State & Maybe<&2,Component.MouseResponse>:
  match state event:
    case State{_,_,_,_,+search,_,_,_,_,Some{row}} Tui.TuiMouseEvent{kind,button,x,Tui.Forward{+y},sx,sy,width,height,shift,alt,ctrl,wheel,count}:
      Bool.pick(State & Maybe<&2,Component.MouseResponse>,Nat.is_eq(y,row) && Nat.is_lt(y,height),mouseEdited(state,Input.handleMouse(search,Tui.TuiMouseEvent{kind,button,x,Tui.Forward{0n},sx,sy,width,1n,shift,alt,ctrl,wheel,count})),(state,None{}))
    case state _: (state,None{})
def mouseStored(modal: Ref.Ref<Modal>,pair: State & Maybe<&2,Component.MouseResponse>) -> IO(Maybe<&2,Component.MouseResponse>):
  match pair:
    case (state,response):
      do IO<Maybe<&2,Component.MouseResponse>>:
        Ref.write(Modal,modal,Open{state})
        return response
def mouseCurrent(current: Modal,modal: Ref.Ref<Modal>,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{state}: mouseStored(modal,mouseSearch(state,event))
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{+modal,_,collator,editor,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(current,modal,editor,event)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,_,_,editor,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,_,_,editor,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,source: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    words : Ref.Ref<Words.Source> <- Ref.new(Words.Source,source)
    collator : Ref.Ref<Maybe<&2,Collation.Collator>> <- Ref.new(Maybe<&2,Collation.Collator>,None{})
    +host : Host <- IO.pure(Host,Host{modal,words,collator,editor,theme,bindings,keyboard,chosen})
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
def loadCollator(source: Words.Source) -> IO(Result<&2,&2,Collation.LoadError,Collation.Collator>):
  match source:
    case Words.Pending{directory}: Collation.load(directory)
    case Words.Ready{_,directory}: Collation.load(directory)
    case Words.Unavailable{_}: IO.pure(Result<&2,&2,Collation.LoadError,Collation.Collator>,Fail{Collation.InvalidAsset{"word source unavailable"}})
def cachedCollator(stored: Maybe<&2,Collation.Collator>,words: Ref.Ref<Words.Source>) -> IO(Result<&2,&2,Collation.LoadError,Collation.Collator>):
  match stored:
    case Some{value}: IO.pure(Result<&2,&2,Collation.LoadError,Collation.Collator>,Done{value})
    case None{}:
      do IO<Result<&2,&2,Collation.LoadError,Collation.Collator>>:
        source : Words.Source <- Ref.read(Words.Source,words)
        loadCollator(source)
def openSorted(modal: Ref.Ref<Modal>,cache: Ref.Ref<Maybe<&2,Collation.Collator>>,state: State,result: Result<&2,&2,Collation.LoadError,Collation.Collator>) -> IO(Unit):
  match result state:
    case Done{+collator} state:
      do IO<Unit>:
        Ref.write(Maybe<&2,Collation.Collator>,cache,Some{collator})
        Ref.write(Modal,modal,Open{sortedState(state,collator)})
    case Fail{_} State{all,scoped,_,_,query,current,defaultRef,mode,_,_}:
      Ref.write(Modal,modal,Open{State{all,scoped,Nil{},0n,query,current,defaultRef,mode,"Cannot load model sorting data.",None{}}})
def open(host: Host,state: State) -> IO(Unit):
  match host:
    case Host{modal,words,+collator,_,_,_,_,_}:
      do IO<Unit>:
        stored : Maybe<&2,Collation.Collator> <- Ref.read(Maybe<&2,Collation.Collator>,collator)
        ready : Result<&2,&2,Collation.LoadError,Collation.Collator> <- cachedCollator(stored,words)
        openSorted(modal,collator,state,ready)
def refreshedSorted(current: Modal,models: List<&2,Models.Model()>,status: String,collator: Collation.Collator) -> Modal & Bool:
  match current:
    case Closed{}: (Closed{},False{})
    case Open{state}: (Open{sortedState(refreshedState(state,models,status),collator)},True{})
def refreshCached(modal: Ref.Ref<Modal>,models: List<&2,Models.Model()>,status: String,cache: Maybe<&2,Collation.Collator>) -> IO(Bool):
  match cache:
    case None{}: IO.pure(Bool,False{})
    case Some{collator}:
      do IO<Bool>:
        published : Maybe<&1,Bool> <- Ref.tryModify(Modal,Bool,modal,current => refreshedSorted(current,models,status,collator))
        return Maybe.default(&1,Bool,published,False{})
def refreshed(host: Host,models: List<&2,Models.Model()>,status: String) -> IO(Bool):
  match host:
    case Host{modal,_,collator,_,_,_,_,_}:
      do IO<Bool>:
        cached : Maybe<&2,Collation.Collator> <- Ref.read(Maybe<&2,Collation.Collator>,collator)
        refreshCached(modal,models,status,cached)
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,words,collator,_,_,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        source : Words.Source <- Ref.dispose(Words.Source,words)
        sorting : Maybe<&2,Collation.Collator> <- Ref.dispose(Maybe<&2,Collation.Collator>,collator)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
