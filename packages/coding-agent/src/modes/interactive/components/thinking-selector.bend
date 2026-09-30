import Base
import ../../../../../ai/src/types.bend as Ai
import ../../../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/components/select-list.bend as Select
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/components/text.bend as Text
import ../../../../../tui/src/word-navigation.bend as Word
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints

type Entry is Data: Entry{level: Ai.ModelThinkingLevel,description: String}
type Layout is Data: Layout{width: Nat,searchRow: Nat,listRow: Nat,pressed: Maybe<&2,Nat>}
type State is Data:
  State{all: List<&2,Entry>,visible: List<&2,Entry>,selected: Nat,search: Input.Input,current: Ai.ModelThinkingLevel,defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>,layout: Maybe<&2,Layout>}
type Action is Data: Continue{} Cancel{} Chosen{level: Ai.ModelThinkingLevel,persist: Bool}

def description(level: Ai.ModelThinkingLevel) -> String:
  match level:
    case Ai.Off{}: "No reasoning"
    case Ai.Thinking{Ai.Minimal{}}: "Very brief reasoning (~1k tokens)"
    case Ai.Thinking{Ai.Low{}}: "Light reasoning (~2k tokens)"
    case Ai.Thinking{Ai.Medium{}}: "Moderate reasoning (~8k tokens)"
    case Ai.Thinking{Ai.High{}}: "Deep reasoning (~16k tokens)"
    case Ai.Thinking{Ai.XHigh{}}: "Extra-high reasoning (~32k tokens)"
    case Ai.Thinking{Ai.Max{}}: "Maximum reasoning"
def isDefault(defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>,level: Ai.ModelThinkingLevel) -> Bool:
  match defaultLevel: case None{}: False{} case Some{value}: U32.is_eq(Levels.rank(value),Levels.rank(level))
def entries(levels: List<&2,Ai.ModelThinkingLevel>,+defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>) -> List<&2,Entry>:
  match levels:
    case Nil{}: Nil{}
    case +level <> rest: Entry{level,description(level) ++ Bool.pick(String,isDefault(defaultLevel,level)," · default","")} <> entries(rest,defaultLevel)
def same(left: Ai.ModelThinkingLevel,right: Ai.ModelThinkingLevel) -> Bool:
  U32.is_eq(Levels.rank(left),Levels.rank(right))
def indexOf(items: List<&2,Entry>,+level: Ai.ModelThinkingLevel,+index: Nat) -> Nat:
  match items:
    case Nil{}: 0n
    case Entry{found,_} <> rest: Bool.pick(Nat,same(found,level),index,indexOf(rest,level,index + 1n))
def searchable(item: Entry) -> String:
  match item:
    case Entry{level,details}: Levels.name(level) ++ " " ++ details
def filtered(+items: List<&2,Entry>,+query: String) -> List<&2,Entry>:
  Bool.pick(List<&2,Entry>,String.is_empty(query),items,Fuzzy.fuzzyFilter(~Entry,~searchable,items,query))
def createWithDefault(levels: List<&2,Ai.ModelThinkingLevel>,+current: Ai.ModelThinkingLevel,+defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>) -> State:
  +all = entries(levels,defaultLevel)
  State{all,all,indexOf(all,current,0n),Input.setFocused(Input.new(None{}),True{}),current,defaultLevel,None{}}
def create(levels: List<&2,Ai.ModelThinkingLevel>,current: Ai.ModelThinkingLevel,defaultLevel: Ai.ModelThinkingLevel) -> State:
  createWithDefault(levels,current,Some{defaultLevel})
def selected(state: State) -> Maybe<&2,Entry>:
  match state:
    case State{_,visible,index,_,_,_,_}: List.get(&2,Entry,visible,index)
def choice(value: Maybe<&2,Entry>,persist: Bool) -> Action:
  match value:
    case None{}: Continue{}
    case Some{Entry{level,_}}: Chosen{level,persist}
def chosen(state: State,persist: Bool) -> Action: choice(selected(state),persist)
def selection(value: Maybe<&2,Entry>) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match value:
    case None{}: None{}
    case Some{Entry{level,_}}: Some{level}
def currentSelection(state: State) -> Maybe<&2,Ai.ModelThinkingLevel>: selection(selected(state))
def preserve(items: List<&2,Entry>,selection: Maybe<&2,Ai.ModelThinkingLevel>) -> Nat:
  match selection:
    case None{}: 0n
    case Some{level}: indexOf(items,level,0n)
def withSearch(state: State,+search: Input.Input) -> State:
  match state:
    case State{+all,+visible,+index,_,+current,+defaultLevel,_}:
      +old = currentSelection(State{all,visible,index,search,current,defaultLevel,None{}})
      +next = filtered(all,Input.getValue(search))
      State{all,next,preserve(next,old),search,current,defaultLevel,None{}}
def move(state: State,up: Bool) -> State:
  match state:
    case State{all,+visible,+index,search,current,defaultLevel,layout}:
      +count = List.length(&2,Entry,visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      State{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),search,current,defaultLevel,layout}
def nonAtomic(_: Segmenter.Source,_: String) -> Bool: False{}
def edited(state: State,result: Word.ResultOf(Input.Input)) -> State & Action:
  match result:
    case Done{input}: (withSearch(state,input),Continue{})
    case Fail{_}: (state,Continue{})
def otherInput(+state: State,source: Segmenter.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(State & Action):
  match state:
    case State{_,_,_,+search,_,_,_}:
      do IO<State & Action>:
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,search,bindings,keyboard,data)
        return edited(state,result)
def input(+state: State,source: Segmenter.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(State & Action):
  Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"app.thinking.save"),_ => IO.pure(State & Action,(state,chosen(state,True{}))),
    _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => IO.pure(State & Action,(move(state,True{}),Continue{})),
      _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => IO.pure(State & Action,(move(state,False{}),Continue{})),
        _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => IO.pure(State & Action,(state,chosen(state,False{}))),
          _ => Bool.pick(Unit -> IO(State & Action),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => IO.pure(State & Action,(state,Cancel{})),_ => otherInput(state,source,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def border(width: Nat) -> String: String.repeat("─",width)
def selectItems(items: List<&2,Entry>,+current: Ai.ModelThinkingLevel,+defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>) -> List<&2,Select.SelectItem>:
  match items:
    case Nil{}: Nil{}
    case Entry{+level,details} <> rest:
      Select.SelectItem{Levels.name(level),Bool.pick(String,same(level,current),"✓ ","  ") ++ Levels.name(level),Some{details}} <> selectItems(rest,current,defaultLevel)
type SelectPaint is Data: SelectPaint{theme: Theme.Theme,key: String}
def selectPaint(context: SelectPaint,text: String) -> IO(String):
  match context: case SelectPaint{theme,key}: IO.pure(String,paint(theme,key,text))
def selectRows(items: List<&2,Entry>,index: Nat,current: Ai.ModelThinkingLevel,defaultLevel: Maybe<&2,Ai.ModelThinkingLevel>,+theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +accent : Callback.Callback<String,String> <- Callback.create(~SelectPaint,~String,~String,~selectPaint,SelectPaint{theme,"accent"})
    +muted : Callback.Callback<String,String> <- Callback.create(~SelectPaint,~String,~String,~selectPaint,SelectPaint{theme,"muted"})
    +rows : List<&2,Select.SelectItem> = selectItems(items,current,defaultLevel)
    lines : List<&2,String> <- Select.render(Select.setSelectedIndex(Select.new(rows,Nat.max(1n,List.length(&2,Select.SelectItem,rows)),Select.SelectListTheme{accent,accent,muted,muted,muted},Some{Select.SelectListLayoutOptions{Some{12n},Some{32n},None{}}}),index),width)
    Callback.dispose(String,String,accent)
    Callback.dispose(String,String,muted)
    return lines
def pressed(layout: Maybe<&2,Layout>) -> Maybe<&2,Nat>:
  match layout: case None{}: None{} case Some{Layout{_,_,_,value}}: value
def textOutput(pair: Text.Text & List<&2,String>) -> List<&2,String>:
  match pair: case (_,lines): lines
def textLines(text: String,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    pair : Text.Text & List<&2,String> <- Text.render(Text.new(text,Some{0n},Some{0n},None{}),width)
    return textOutput(pair)
def renderedState(state: State,+width: Nat,nextSearch: Input.Input,+searchLines: List<&2,String>,+heading: List<&2,String>,footer: List<&2,String>,body: List<&2,String>) -> State & List<&2,String>:
  match state:
    case State{all,visible,index,_,current,defaultLevel,layout}:
      +searchRow = List.length(&2,String,heading)
      +listRow = searchRow + List.length(&2,String,searchLines) + 1n
      +lines = List.concat(&2,String,[heading,searchLines,[""],body,[""],footer])
      (State{all,visible,index,nextSearch,current,defaultLevel,Some{Layout{width,searchRow,listRow,pressed(layout)}}},lines)
def renderedPair(state: State,width: Nat,pair: Input.Input & List<&2,String>,heading: List<&2,String>,footer: List<&2,String>,body: List<&2,String>) -> State & List<&2,String>:
  match pair: case (nextSearch,searchLines): renderedState(state,width,nextSearch,searchLines,heading,footer,body)
def rendered(+state: State,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat) -> IO(State & List<&2,String>):
  match state:
    case State{_,visible,index,+search,current,defaultLevel,_}:
      do IO<State & List<&2,String>>:
        body : List<&2,String> <- selectRows(visible,index,current,defaultLevel,theme,width)
        title : List<&2,String> <- textLines("Thinking Level",width)
        hint : List<&2,String> <- textLines(Hints.keyDisplayText(bindings,"app.thinking.cycle") ++ " cycles thinking levels in-session",width)
        help : List<&2,String> <- textLines(paint(theme,"dim","  " ++ Hints.keyDisplayText(bindings,"tui.select.confirm") ++ " to select · " ++ Hints.keyDisplayText(bindings,"app.thinking.save") ++ " to set as default · " ++ Hints.keyDisplayText(bindings,"tui.select.cancel") ++ " to cancel"),width)
        pair : Input.Input & List<&2,String> <- Input.render(search,width)
        return renderedPair(state,width,pair,List.concat(&2,String,[[paint(theme,"border",border(width)),""],title,[""],hint,[""]]),List.concat(&2,String,[help,[paint(theme,"border",border(width))]]),body)

def containsRow(value: Tui.Offset,+start: Nat,count: Nat) -> Bool:
  match value:
    case Tui.Forward{+row}: Nat.is_le(start,row) && Nat.is_lt(row,start + count)
    case Tui.Backward{amount}: Nat.is_eq(amount,0n) && Nat.is_eq(start,0n) && Nat.is_lt(0n,count)
def mouseSelection(state: State,index: Nat,pressedIndex: Maybe<&2,Nat>) -> State:
  match state:
    case State{all,visible,_,search,current,defaultLevel,Some{Layout{width,searchRow,listRow,_}}}:
      State{all,visible,index,search,current,defaultLevel,Some{Layout{width,searchRow,listRow,pressedIndex}}}
    case state: state
def wheel(+state: State,delta: Maybe<&2,Tui.Offset>) -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>:
  match state delta:
    case State{_,visible,+index,_,_,_,layout} Some{+direction}:
      +next = Select.wheelIndex(direction,index,List.length(&2,Entry,visible))
      Bool.pick(State & Action & Maybe<&2,Tui.TuiMouseEventResult>,Select.nonzero(Some{direction}),
        (mouseSelection(state,next,pressed(layout)),Continue{},Some{Tui.TuiMouseEventResult{True{},False{},False{},Some{Bool.not(Nat.is_eq(index,next))}}}),
        (state,Continue{},None{}))
    case state _: (state,Continue{},None{})
def listMouse(+state: State,event: Tui.TuiMouseEvent) -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>:
  match state event:
    case State{_,_,index,_,_,_,Some{Layout{_,_,listRow,oldPressed}}} Tui.TuiMouseEvent{Tui.MousePress{},Tui.MouseLeft{},_,+y,_,_,_,_,_,_,_,_,_}:
      (mouseSelection(state,Select.nonnegative(y) - listRow,Some{Select.nonnegative(y) - listRow}),Continue{},Some{Tui.TuiMouseEventResult{True{},False{},True{},None{}}})
    case State{_,_,_,_,_,_,Some{Layout{_,_,listRow,oldPressed}}} Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},_,y,_,_,_,_,_,_,_,_,_}:
      +next = mouseSelection(state,Maybe.default(&2,Nat,oldPressed,Select.nonnegative(y) - listRow),None{})
      (next,chosen(next,False{}),Some{Tui.TuiMouseEventResult{True{},False{},False{},None{}}})
    case state Tui.TuiMouseEvent{Tui.MouseWheel{},_,_,_,_,_,_,_,_,_,_,delta,_}: wheel(state,delta)
    case state _: (state,Continue{},None{})
def searchedMouse(state: State,pair: Input.Input & Maybe<&2,Tui.TuiMouseEventResult>) -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>:
  match pair state:
    case (search,response) State{all,visible,index,_,current,defaultLevel,layout}:
      (State{all,visible,index,search,current,defaultLevel,layout},Continue{},response)
def searchMouse(+state: State,event: Tui.TuiMouseEvent) -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>:
  match state event:
    case State{_,_,_,+search,_,_,_} Tui.TuiMouseEvent{kind,button,x,_,sx,sy,width,_,shift,alt,ctrl,delta,count}:
      searchedMouse(state,Input.handleMouse(search,Tui.TuiMouseEvent{kind,button,x,Tui.Forward{0n},sx,sy,width,1n,shift,alt,ctrl,delta,count}))
def handleMouse(+state: State,+event: Tui.TuiMouseEvent) -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>:
  match state event:
    case State{_,visible,_,_,_,_,Some{Layout{width,searchRow,listRow,_}}} Tui.TuiMouseEvent{_,_,_,+y,_,_,_,+height,_,_,_,_,_}:
      Bool.pick(Unit -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>,containsRow(y,0n,height) && containsRow(y,searchRow,1n),
        _ => searchMouse(state,event),
        _ => Bool.pick(Unit -> State & Action & Maybe<&2,Tui.TuiMouseEventResult>,containsRow(y,0n,height) && containsRow(y,listRow,List.length(&2,Entry,visible)),_ => listMouse(state,event),_ => (state,Continue{},None{}))(Unit{}))(Unit{})
    case state _: (state,Continue{},None{})

type Modal is Data: Closed{} Open{state: State}
type Choice is Data: Choice{level: Ai.ModelThinkingLevel,persist: Bool}
type Host is Data:
  Host{modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Ref.Ref<Segmenter.Source>,bindings: Ref.Ref<Bindings.KeybindingsManager>,keyboard: Keys.Context,chosen: Callback.Callback<Choice,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}
def displayedPair(modal: Ref.Ref<Modal>,pair: State & List<&2,String>) -> IO(List<&2,String>):
  match pair:
    case (next,lines):
      do IO<List<&2,String>>:
        Ref.write(Modal,modal,Open{next})
        return lines
def displayed(modal: Ref.Ref<Modal>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Ref.Ref<Bindings.KeybindingsManager>,width: Nat,current: Modal) -> IO(List<&2,String>):
  match current:
    case Closed{}: Component.render(editor,width)
    case Open{state}:
      do IO<List<&2,String>>:
        chosenTheme : Theme.Theme <- Ref.read(Theme.Theme,theme)
        liveBindings : Bindings.KeybindingsManager <- Ref.read(Bindings.KeybindingsManager,bindings)
        pair : State & List<&2,String> <- rendered(state,chosenTheme,liveBindings,width)
        displayedPair(modal,pair)
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{+modal,editor,theme,_,bindings,_,_}:
      do IO<List<&2,String>>:
        current : Modal <- Ref.read(Modal,modal)
        displayed(modal,editor,theme,bindings,width,current)
def accepted(modal: Ref.Ref<Modal>,onSelect: Callback.Callback<Choice,Unit>,pair: State & Action) -> IO(Unit):
  match pair:
    case (state,Continue{}): Ref.write(Modal,modal,Open{state})
    case (_,Cancel{}): Ref.write(Modal,modal,Closed{})
    case (_,Chosen{level,persist}):
      do IO<Unit>:
        Ref.write(Modal,modal,Closed{})
        Callback.call(Choice,Unit,onSelect,Choice{level,persist})
def receiveCurrent(modal: Ref.Ref<Modal>,editor: Component.Component,words: Ref.Ref<Segmenter.Source>,bindings: Ref.Ref<Bindings.KeybindingsManager>,keyboard: Keys.Context,onSelect: Callback.Callback<Choice,Unit>,data: String,current: Modal) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Open{state}:
      do IO<Unit>:
        source : Segmenter.Source <- Ref.read(Segmenter.Source,words)
        liveBindings : Bindings.KeybindingsManager <- Ref.read(Bindings.KeybindingsManager,bindings)
        pair : State & Action <- input(state,source,liveBindings,keyboard,data)
        accepted(modal,onSelect,pair)
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+modal,editor,_,words,bindings,keyboard,onSelect}:
      do IO<Unit>:
        current : Modal <- Ref.read(Modal,modal)
        receiveCurrent(modal,editor,words,bindings,keyboard,onSelect,data,current)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse()>,None{})
def mouseAccepted(modal: Ref.Ref<Modal>,onSelect: Callback.Callback<Choice,Unit>,pair: State & Action & Maybe<&2,Tui.TuiMouseEventResult>) -> IO(Maybe<&2,Component.MouseResponse()>):
  match pair:
    case (state,action,response):
      do IO<Maybe<&2,Component.MouseResponse()>>:
        accepted(modal,onSelect,(state,action))
        return Maybe.map(&2,Tui.TuiMouseEventResult,Component.MouseResponse(),result => Component.LocalResult{result},response)
def mouseCurrent(modal: Ref.Ref<Modal>,onSelect: Callback.Callback<Choice,Unit>,editor: Component.Component,event: Tui.TuiMouseEvent,current: Modal) -> IO(Maybe<&2,Component.MouseResponse()>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case Open{state}: mouseAccepted(modal,onSelect,handleMouse(state,event))
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse()>):
  match host:
    case Host{+modal,editor,_,_,_,_,onSelect}:
      do IO<Maybe<&2,Component.MouseResponse()>>:
        current : Modal <- Ref.read(Modal,modal)
        mouseCurrent(modal,onSelect,editor,event,current)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,editor,_,_,_,_,_}: Component.setFocused(editor,value)
def createHost(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Segmenter.Source,bindings: Ref.Ref<Bindings.KeybindingsManager>,keyboard: Keys.Context,onSelect: Callback.Callback<Choice,Unit>) -> IO(Owner):
  do IO<Owner>:
    modal : Ref.Ref<Modal> <- Ref.new(Modal,Closed{})
    source : Ref.Ref<Segmenter.Source> <- Ref.new(Segmenter.Source,words)
    +host : Host <- IO.pure(Host,Host{modal,editor,theme,source,bindings,keyboard,onSelect})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse()>,~mouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrowHost(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def open(host: Host,state: State) -> IO(Unit):
  match host: case Host{modal,_,_,_,_,_,_}: Ref.write(Modal,modal,Open{state})
def disposeHost(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{modal,_,_,words,_,_,_},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : Modal <- Ref.dispose(Modal,modal)
        source : Segmenter.Source <- Ref.dispose(Segmenter.Source,words)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse()>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
