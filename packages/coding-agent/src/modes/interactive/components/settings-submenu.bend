import Base
import ../../../../../runtime/src/record.bend as Record
import ../../../../../runtime/src/callback.bend as C
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/components/select-list.bend as Select
import ../../../../../tui/src/components/text.bend as Text
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../../../../../tui/src/keybindings.bend as Keys
import ../../../../../tui/src/keys.bend as Keyboard
import ../../../../../tui/src/word-navigation.bend as Word
import ../theme/theme.bend as Theme

# Callback handles are borrowed. Owners keep them alive until the submenu closes.
type SelectSubmenuOptions is Data:
  SelectSubmenuOptions{searchable: Bool,layout: Maybe<&2,Select.SelectListLayoutOptions>}
type Callbacks is Data:
  Callbacks{onSelect: Maybe<&2,C.Callback<String,Unit>>,onCancel: Maybe<&2,C.Callback<Unit,Unit>>,onSelectionChange: Maybe<&2,C.Callback<String,Unit>>}
type SelectSubmenu is Data:
  SelectSubmenu{title: String,description: String,allOptions: List<&2,Select.SelectItem>,selectList: Select.SelectList,searchInput: Maybe<&2,Input.Input>,callbacks: Callbacks}
type Action is Data: Continue{} Selected{value: String} Cancel{} SelectionChanged{value: String}
type Paint is Data: Paint{theme: Ref.Ref<Theme.Theme>,key: String}
type ThemeOwner is Data:
  ThemeOwner{theme: Select.SelectListTheme,accent: C.Callback<String,String>,muted: C.Callback<String,String>}

def colored(environment: Paint,text: String) -> IO(String):
  match environment:
    case Paint{theme,key}:
      do IO<String>:
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        +value : String = text
        return Result.default(&2,&2,Theme.Error,String,Theme.foreground(colors,key,value),value)
def createTheme(+theme: Ref.Ref<Theme.Theme>) -> IO(ThemeOwner):
  do IO<ThemeOwner>:
    +accent : C.Callback<String,String> <- C.create(~Paint,~String,~String,~colored,Paint{theme,"accent"})
    +muted : C.Callback<String,String> <- C.create(~Paint,~String,~String,~colored,Paint{theme,"muted"})
    return ThemeOwner{Select.SelectListTheme{accent,accent,muted,muted,muted},accent,muted}
def theme(owner: ThemeOwner) -> ThemeOwner & Select.SelectListTheme:
  match owner: case ThemeOwner{+theme,accent,muted}: (ThemeOwner{theme,accent,muted},theme)
def disposeTheme(owner: ThemeOwner) -> IO(Unit):
  match owner:
    case ThemeOwner{_,accent,muted}:
      do IO<Unit>:
        C.dispose(String,String,accent)
        C.dispose(String,String,muted)
def noCallbacks() -> Callbacks: Callbacks{None{},None{},None{}}
def defaultOptions() -> SelectSubmenuOptions: SelectSubmenuOptions{False{},None{}}
def indexOf(items: List<&2,Select.SelectItem>,+value: String,+index: Nat) -> Nat:
  match items:
    case Nil{}: 0n
    case Select.SelectItem{candidate,_,_} <> rest:
      Bool.pick(Unit -> Nat,String.eq(candidate,value),_ => index,_ => indexOf(rest,value,index + 1n))(Unit{})
def new(title: String,description: String,+items: List<&2,Select.SelectItem>,current: String,theme: Select.SelectListTheme,callbacks: Callbacks,options: SelectSubmenuOptions) -> SelectSubmenu:
  match options:
    case SelectSubmenuOptions{searchable,layout}:
      SelectSubmenu{title,description,items,Select.setSelectedIndex(Select.new(items,Nat.min(List.length(&2,Select.SelectItem,items),10n),theme,Some{Maybe.default(&2,Select.SelectListLayoutOptions,layout,Select.SelectListLayoutOptions{Some{12n},Some{32n},None{}})}),indexOf(items,current,0n)),Bool.pick(Maybe<&2,Input.Input>,searchable,Some{Input.new(None{})},None{}),callbacks}
def selected(state: SelectSubmenu) -> Maybe<&2,Select.SelectItem>:
  match state: case SelectSubmenu{_,_,_,list,_,_}: Select.getSelectedItem(list)
def value(item: Select.SelectItem) -> String: match item: case Select.SelectItem{value,_,_}: value
def selectedValue(state: SelectSubmenu) -> Maybe<&2,String>:
  Maybe.map(&2,Select.SelectItem,String,item => value(item),selected(state))
def query(state: SelectSubmenu) -> String:
  match state:
    case SelectSubmenu{_,_,_,_,Some{search},_}: Input.getValue(search)
    case _: ""
def searchText(item: Select.SelectItem) -> String:
  match item: case Select.SelectItem{_,label,description}: label ++ " " ++ Maybe.default(&2,String,description,"")
def filtered(+items: List<&2,Select.SelectItem>,query: String) -> List<&2,Select.SelectItem>:
  match query: case SNil{}: items case query: Fuzzy.fuzzyFilter(~Select.SelectItem,~searchText,items,query)
def applyFilter(state: SelectSubmenu,+search: Input.Input) -> SelectSubmenu:
  match state:
    case SelectSubmenu{title,description,+all,Select.SelectList{_,_,_,_,_,theme,layout,_,_,_},_,callbacks}:
      +visible = filtered(all,Input.getValue(search))
      SelectSubmenu{title,description,all,Select.new(visible,Nat.min(List.length(&2,Select.SelectItem,visible),10n),theme,Some{layout}),Some{search},callbacks}
def withList(state: SelectSubmenu,list: Select.SelectList) -> SelectSubmenu:
  match state: case SelectSubmenu{title,description,all,_,search,callbacks}: SelectSubmenu{title,description,all,list,search,callbacks}
def callbacksOf(state: SelectSubmenu) -> Callbacks:
  match state: case SelectSubmenu{_,_,_,_,_,callbacks}: callbacks
def notifyValue(callback: Maybe<&2,C.Callback<String,Unit>>,value: String) -> IO(Unit):
  match callback: case None{}: IO.pure(Unit,Unit{}) case Some{callback}: C.call(String,Unit,callback,value)
def notify(callbacks: Callbacks,action: Action) -> IO(Unit):
  match callbacks action:
    case Callbacks{onSelect,_,_} Selected{value}: notifyValue(onSelect,value)
    case Callbacks{_,_,onChange} SelectionChanged{value}: notifyValue(onChange,value)
    case Callbacks{_,Some{cancel},_} Cancel{}: C.call(Unit,Unit,cancel,Unit{})
    case _ _: IO.pure(Unit,Unit{})
def emitted(+state: SelectSubmenu,+action: Action) -> IO(SelectSubmenu & Action):
  do IO<SelectSubmenu & Action>:
    notify(callbacksOf(state),action)
    return (state,action)
def selectionAction(value: Maybe<&2,String>,confirm: Bool) -> Action:
  match value: case None{}: Continue{} case Some{+value}: Bool.pick(Action,confirm,Selected{value},SelectionChanged{value})
def navigated(state: SelectSubmenu,list: Select.SelectList) -> IO(SelectSubmenu & Action):
  +updated = withList(state,list)
  emitted(updated,selectionAction(selectedValue(updated),False{}))
def edited(state: SelectSubmenu,result: Word.ResultOf(Input.Input)) -> IO(SelectSubmenu & Action):
  match result:
    case Done{search}: emitted(applyFilter(state,search),Continue{})
    case Fail{_}: IO.pure(SelectSubmenu & Action,(state,Continue{}))
def nonAtomic(_: Words.Source,_: String) -> Bool: False{}
def otherInput(+state: SelectSubmenu,source: Words.Source,bindings: Keys.KeybindingsManager,keyboard: Keyboard.Context,data: String) -> IO(SelectSubmenu & Action):
  match state:
    case SelectSubmenu{_,_,_,_,Some{search},_}:
      do IO<SelectSubmenu & Action>:
        result : Word.ResultOf(Input.Input) <- Input.handleInput(~Words.Source,~Word.sourceSegments,~nonAtomic,source,search,bindings,keyboard,data)
        edited(state,result)
    case state: IO.pure(SelectSubmenu & Action,(state,Continue{}))
def navigation(+state: SelectSubmenu,+bindings: Keys.KeybindingsManager,+keyboard: Keyboard.Context,+data: String) -> IO(SelectSubmenu & Action):
  match state:
    case SelectSubmenu{_,_,_,list,_,_}:
      do IO<SelectSubmenu & Action>:
        updated : Select.SelectList <- Select.handleInput(list,bindings,keyboard,data)
        navigated(state,updated)
def handleInput(+state: SelectSubmenu,source: Words.Source,+bindings: Keys.KeybindingsManager,+keyboard: Keyboard.Context,+data: String) -> IO(SelectSubmenu & Action):
  Bool.pick(Unit -> IO(SelectSubmenu & Action),Keys.matches(bindings,keyboard,data,"tui.select.confirm"),_ => emitted(state,selectionAction(selectedValue(state),True{})),
    _ => Bool.pick(Unit -> IO(SelectSubmenu & Action),Keys.matches(bindings,keyboard,data,"tui.select.cancel"),_ => emitted(state,Cancel{}),
      _ => Bool.pick(Unit -> IO(SelectSubmenu & Action),Keys.matches(bindings,keyboard,data,"tui.select.up") || Keys.matches(bindings,keyboard,data,"tui.select.down"),_ => navigation(state,bindings,keyboard,data),_ => otherInput(state,source,bindings,keyboard,data))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def textLines(pair: Text.Text & List<&2,String>) -> List<&2,String>: match pair: case (_,lines): lines
def wrapped(text: String,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    pair : Text.Text & List<&2,String> <- Text.render(Text.new(text,Some{0n},Some{0n},None{}),width)
    return textLines(pair)
def descriptionLines(description: String,theme: Theme.Theme,width: Nat) -> IO(List<&2,String>):
  match description:
    case SNil{}: IO.pure(List<&2,String>,Nil{})
    case description:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- wrapped(paint(theme,"muted",description),width)
        return "" <> lines
def renderedSearch(pair: Input.Input & List<&2,String>) -> Maybe<&2,Input.Input> & List<&2,String>:
  match pair: case (search,lines): (Some{search},"" <> lines)
def renderSearch(search: Maybe<&2,Input.Input>,width: Nat) -> IO(Maybe<&2,Input.Input> & List<&2,String>):
  match search:
    case None{}: IO.pure(Maybe<&2,Input.Input> & List<&2,String>,(None{},Nil{}))
    case Some{search}:
      do IO<Maybe<&2,Input.Input> & List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(search,width)
        return renderedSearch(pair)
def rendered(state: SelectSubmenu,search: Maybe<&2,Input.Input> & List<&2,String>,title: List<&2,String>,description: List<&2,String>,body: List<&2,String>,hint: List<&2,String>) -> SelectSubmenu & List<&2,String>:
  match state search:
    case SelectSubmenu{heading,detail,all,list,_,callbacks} Tuple{search,searchLines}:
      (SelectSubmenu{heading,detail,all,list,search,callbacks},List.concat(&2,String,[title,description,searchLines,[""],body,[""],hint]))
def render(+state: SelectSubmenu,+theme: Theme.Theme,+width: Nat) -> IO(SelectSubmenu & List<&2,String>):
  match state:
    case SelectSubmenu{title,description,_,list,+search,_}:
      do IO<SelectSubmenu & List<&2,String>>:
        titleLines : List<&2,String> <- wrapped(Theme.bold(paint(theme,"accent",title)),width)
        detail : List<&2,String> <- descriptionLines(description,theme,width)
        searchPair : Maybe<&2,Input.Input> & List<&2,String> <- renderSearch(search,width)
        body : List<&2,String> <- Select.render(list,width)
        hint : List<&2,String> <- wrapped(paint(theme,"dim",Bool.pick(String,Maybe.is_some(&2,Input.Input,search),"  Type to filter · Enter to select · Esc to go back","  Enter to select · Esc to go back")),width)
        return rendered(state,searchPair,titleLines,detail,body,hint)

# Step builders and completion callbacks are borrowed, like SelectSubmenu callbacks.

def Context() -> Data: Record.Record<String>
type StepText is Data: Literal{text: String} Dynamic{callback: C.Callback<Context(),String>}
type SteppedSubmenuStep is Data:
  SteppedSubmenuStep{key: String,title: StepText,description: StepText,options: C.Callback<Context(),List<&2,Select.SelectItem>>,preselect: Maybe<&2,C.Callback<Context(),Maybe<&2,String>>>,searchable: Bool,layout: Maybe<&2,Select.SelectListLayoutOptions>}
type SteppedSubmenuOptions is Data:
  SteppedSubmenuOptions{startAtStep: Nat,initialContext: Context(),loop: Bool}
type SteppedSubmenu is Data:
  SteppedSubmenu{steps: List<&2,SteppedSubmenuStep>,index: Nat,context: Context(),activeComponent: SelectSubmenu,theme: Select.SelectListTheme,onComplete: C.Callback<Context(),Unit>,onCancel: C.Callback<Unit,Unit>,loop: Bool}
type BuildError is Data: NoSteps{} InvalidStart{index: Nat} MissingContext{key: String}

def defaultSteppedOptions() -> SteppedSubmenuOptions: SteppedSubmenuOptions{0n,Record.new(String),False{}}
def stepText(text: StepText,context: Context()) -> IO(String):
  match text: case Literal{value}: IO.pure(String,value) case Dynamic{callback}: C.call(Context(),String,callback,context)
def preselect(callback: Maybe<&2,C.Callback<Context(),Maybe<&2,String>>>,context: Context()) -> IO(String):
  match callback:
    case None{}: IO.pure(String,"")
    case Some{callback}:
      do IO<String>:
        value : Maybe<&2,String> <- C.call(Context(),Maybe<&2,String>,callback,context)
        return Maybe.default(&2,String,value,"")
def buildStep(step: SteppedSubmenuStep,+context: Context(),+index: Nat,+total: Nat,+theme: Select.SelectListTheme) -> IO(SelectSubmenu):
  match step:
    case SteppedSubmenuStep{_,title,description,options,current,searchable,layout}:
      do IO<SelectSubmenu>:
        heading : String <- stepText(title,context)
        detail : String <- stepText(description,context)
        items : List<&2,Select.SelectItem> <- C.call(Context(),List<&2,Select.SelectItem>,options,context)
        selected : String <- preselect(current,context)
        +prefix : String = Bool.pick(String,Nat.is_gt(total,1n),"Step " ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(total) ++ " · ","")
        return new(heading,prefix ++ detail,items,selected,theme,noCallbacks(),SelectSubmenuOptions{searchable,layout})
def skipped(steps: List<&2,SteppedSubmenuStep>,count: Nat,+context: Context()) -> Maybe<&2,BuildError>:
  match steps count:
    case _ Zero{}: None{}
    case SteppedSubmenuStep{+key,_,_,_,_,_,_} <> rest Succ{count}:
      Bool.pick(Unit -> Maybe<&2,BuildError>,Maybe.is_some(&2,String,Record.get(String,context,key)),_ => skipped(rest,count,context),_ => Some{MissingContext{key}})(Unit{})
    case Nil{} _: Some{NoSteps{}}
def initialError(+steps: List<&2,SteppedSubmenuStep>,+index: Nat,context: Context()) -> Maybe<&2,BuildError>:
  Bool.pick(Unit -> Maybe<&2,BuildError>,List.is_empty(&2,SteppedSubmenuStep,steps),_ => Some{NoSteps{}},
    _ => Bool.pick(Unit -> Maybe<&2,BuildError>,Nat.is_ge(index,List.length(&2,SteppedSubmenuStep,steps)),_ => Some{InvalidStart{index}},_ => skipped(steps,index,context))(Unit{}))(Unit{})
def requiredStep(value: Maybe<&2,SteppedSubmenuStep>) -> IO(SteppedSubmenuStep):
  match value: case Some{step}: IO.pure(SteppedSubmenuStep,step) case None{}: IO.die(SteppedSubmenuStep,1,"invalid submenu step index")
def initialized(error: Maybe<&2,BuildError>,+steps: List<&2,SteppedSubmenuStep>,+index: Nat,+context: Context(),+theme: Select.SelectListTheme,onComplete: C.Callback<Context(),Unit>,onCancel: C.Callback<Unit,Unit>,loop: Bool) -> IO(Result<&2,&2,BuildError,SteppedSubmenu>):
  match error:
    case Some{error}: IO.pure(Result<&2,&2,BuildError,SteppedSubmenu>,Fail{error})
    case None{}:
      do IO<Result<&2,&2,BuildError,SteppedSubmenu>>:
        step : SteppedSubmenuStep <- requiredStep(List.get(&2,SteppedSubmenuStep,steps,index))
        active : SelectSubmenu <- buildStep(step,context,index,List.length(&2,SteppedSubmenuStep,steps),theme)
        return Done{SteppedSubmenu{steps,index,context,active,theme,onComplete,onCancel,loop}}
def stepped(+steps: List<&2,SteppedSubmenuStep>,theme: Select.SelectListTheme,onComplete: C.Callback<Context(),Unit>,onCancel: C.Callback<Unit,Unit>,options: SteppedSubmenuOptions) -> IO(Result<&2,&2,BuildError,SteppedSubmenu>):
  match options:
    case SteppedSubmenuOptions{+index,+context,loop}: initialized(initialError(steps,index,context),steps,index,context,theme,onComplete,onCancel,loop)
def rebuilt(state: SteppedSubmenu,+index: Nat,+context: Context()) -> IO(SteppedSubmenu):
  match state:
    case SteppedSubmenu{+steps,_,_,_,+theme,complete,cancel,loop}:
      do IO<SteppedSubmenu>:
        step : SteppedSubmenuStep <- requiredStep(List.get(&2,SteppedSubmenuStep,steps,index))
        active : SelectSubmenu <- buildStep(step,context,index,List.length(&2,SteppedSubmenuStep,steps),theme)
        return SteppedSubmenu{steps,index,context,active,theme,complete,cancel,loop}
def withContext(state: SteppedSubmenu,context: Context()) -> SteppedSubmenu:
  match state: case SteppedSubmenu{steps,index,_,active,theme,complete,cancel,loop}: SteppedSubmenu{steps,index,context,active,theme,complete,cancel,loop}
def finalStep(+state: SteppedSubmenu,+context: Context()) -> IO(SteppedSubmenu):
  match state:
    case SteppedSubmenu{_,_,_,_,_,complete,cancel,+loop}:
      do IO<SteppedSubmenu>:
        +updated : SteppedSubmenu = withContext(state,context)
        C.call(Context(),Unit,complete,context)
        Bool.pick(Unit -> IO(SteppedSubmenu),loop,_ => rebuilt(updated,0n,Record.new(String)),_ => do IO<SteppedSubmenu>:
          C.call(Unit,Unit,cancel,Unit{})
          return updated)(Unit{})
def withActive(state: SteppedSubmenu,active: SelectSubmenu) -> SteppedSubmenu:
  match state: case SteppedSubmenu{steps,index,context,_,theme,complete,cancel,loop}: SteppedSubmenu{steps,index,context,active,theme,complete,cancel,loop}
def stepKey(step: SteppedSubmenuStep) -> String: match step: case SteppedSubmenuStep{key,_,_,_,_,_,_}: key
def advance(+state: SteppedSubmenu,value: String) -> IO(SteppedSubmenu):
  match state:
    case SteppedSubmenu{+steps,+index,context,_,_,_,_,_}:
      do IO<SteppedSubmenu>:
        step : SteppedSubmenuStep <- requiredStep(List.get(&2,SteppedSubmenuStep,steps,index))
        +next : Context() = Record.set(String,context,stepKey(step),value)
        Bool.pick(Unit -> IO(SteppedSubmenu),Nat.is_lt(index + 1n,List.length(&2,SteppedSubmenuStep,steps)),_ => rebuilt(state,index + 1n,next),_ => finalStep(state,next))(Unit{})
def goBack(+state: SteppedSubmenu) -> IO(SteppedSubmenu):
  match state:
    case SteppedSubmenu{+steps,+index,context,_,_,_,cancel,_}:
      do IO<SteppedSubmenu>:
        step : SteppedSubmenuStep <- requiredStep(List.get(&2,SteppedSubmenuStep,steps,index))
        Bool.pick(Unit -> IO(SteppedSubmenu),Nat.is_gt(index,0n),_ => rebuilt(state,index - 1n,Record.remove(String,context,stepKey(step))),_ => do IO<SteppedSubmenu>:
          C.call(Unit,Unit,cancel,Unit{})
          return state)(Unit{})
def transitioned(state: SteppedSubmenu,pair: SelectSubmenu & Action) -> IO(SteppedSubmenu):
  match pair:
    case (active,Selected{value}): advance(withActive(state,active),value)
    case (active,Cancel{}): goBack(withActive(state,active))
    case (active,_): IO.pure(SteppedSubmenu,withActive(state,active))
def active(state: SteppedSubmenu) -> SelectSubmenu: match state: case SteppedSubmenu{_,_,_,active,_,_,_,_}: active
def handleSteppedInput(+state: SteppedSubmenu,source: Words.Source,bindings: Keys.KeybindingsManager,keyboard: Keyboard.Context(),data: String) -> IO(SteppedSubmenu):
  match state:
    case SteppedSubmenu{_,_,_,active,_,_,_,_}:
      do IO<SteppedSubmenu>:
        pair : SelectSubmenu & Action <- handleInput(active,source,bindings,keyboard,data)
        transitioned(state,pair)
def renderedStep(state: SteppedSubmenu,pair: SelectSubmenu & List<&2,String>) -> SteppedSubmenu & List<&2,String>:
  match pair: case (active,lines): (withActive(state,active),lines)
def renderStepped(+state: SteppedSubmenu,theme: Theme.Theme,width: Nat) -> IO(SteppedSubmenu & List<&2,String>):
  match state:
    case SteppedSubmenu{_,_,_,active,_,_,_,_}:
      do IO<SteppedSubmenu & List<&2,String>>:
        pair : SelectSubmenu & List<&2,String> <- render(active,theme,width)
        return renderedStep(state,pair)
def invalidate(state: SelectSubmenu) -> SelectSubmenu: state
def invalidateStepped(state: SteppedSubmenu) -> SteppedSubmenu: state
