import Base
import ./input.bend as Input
import ../component.bend as Component
import ../tui.bend as Tui
import ../utils.bend as U
import ../fuzzy.bend as Fuzzy
import ../keys.bend as Keys
import ../keybindings.bend as KB
import ../word-navigation.bend as Word
import ../../../runtime/src/callback.bend as C

type Completion is Data:
  Completion{itemId: String,selectedValue: Maybe<&2,String>,navigateTo: Maybe<&2,String>}
# Bound origin plus a borrowed dispatcher replaces a closure over mutable self.
type SubmenuDone is Data:
  SubmenuDone{itemId: String,dispatch: C.Callback<Completion,Unit>}
type SubmenuRequest is Data:
  SubmenuRequest{currentValue: String,done: SubmenuDone}
type SettingItem is Data:
  SettingItem{id: String,label: String,description: Maybe<&2,String>,currentValue: String,values: Maybe<&2,List<&2,String>>,submenu: Maybe<&2,C.Callback<SubmenuRequest,Component.Component>>}
type ThemeText is Data: ThemeText{text: String,selected: Bool}
type SettingsListTheme is Data:
  SettingsListTheme{label: C.Callback<ThemeText,String>,value: C.Callback<ThemeText,String>,description: C.Callback<String,String>,cursor: String,hint: C.Callback<String,String>}
type SettingsListOptions is Data:
  SettingsListOptions{enableSearch: Bool}
type Change is Data: Change{id: String,newValue: String}
type SettingsList is Data:
  SettingsList{items: List<&2,SettingItem>,filteredItems: List<&2,SettingItem>,theme: SettingsListTheme,selectedIndex: Nat,mousePressedIndex: Maybe<&2,Nat>,maxVisible: Nat,onChange: C.Callback<Change,Unit>,onCancel: C.Callback<Unit,Unit>,searchInput: Maybe<&2,Input.Input>,submenuComponent: Maybe<&2,Component.Component>,submenuItemIndex: Maybe<&2,Nat>,completionDispatcher: C.Callback<Completion,Unit>}

def searchEnabled(options: Maybe<&2,SettingsListOptions>) -> Bool:
  match options:
    case Some{SettingsListOptions{enabled}}: enabled
    case _: False{}
def new(+items: List<&2,SettingItem>,maxVisible: Nat,theme: SettingsListTheme,onChange: C.Callback<Change,Unit>,onCancel: C.Callback<Unit,Unit>,options: Maybe<&2,SettingsListOptions>,completionDispatcher: C.Callback<Completion,Unit>) -> SettingsList:
  SettingsList{items,items,theme,0n,None{},maxVisible,onChange,onCancel,Bool.pick(Maybe<&2,Input.Input>,searchEnabled(options),Some{Input.new(None{})},None{}),None{},None{},completionDispatcher}
def complete(done: SubmenuDone,selectedValue: Maybe<&2,String>,navigateTo: Maybe<&2,String>) -> IO(Unit):
  match done:
    case SubmenuDone{id,dispatch}: C.call(Completion,Unit,dispatch,Completion{id,selectedValue,navigateTo})
def updateItem(items: List<&2,SettingItem>,+id: String,+newValue: String) -> List<&2,SettingItem>:
  match items:
    case Nil{}: Nil{}
    case SettingItem{+key,+label,+description,value,+values,+submenu} <> +rest:
      Bool.pick(Unit -> List<&2,SettingItem>,String.eq(key,id),
        _ => SettingItem{key,label,description,newValue,values,submenu} <> rest,
        _ => SettingItem{key,label,description,value,values,submenu} <> updateItem(rest,id,newValue))(Unit{})
def updateValue(state: SettingsList,+id: String,+newValue: String) -> SettingsList:
  match state:
    case SettingsList{items,filtered,theme,index,pressed,maximum,change,cancel,search,submenu,origin,dispatch}:
      SettingsList{updateItem(items,id,newValue),updateItem(filtered,id,newValue),theme,index,pressed,maximum,change,cancel,search,submenu,origin,dispatch}
def enabled(value: Maybe<&2,Input.Input>) -> Bool:
  match value:
    case Some{_}: True{}
    case None{}: False{}
def getDisplayItems(state: SettingsList) -> List<&2,SettingItem>:
  match state:
    case SettingsList{items,filtered,_,_,_,_,_,_,search,_,_,_}: Bool.pick(List<&2,SettingItem>,enabled(search),filtered,items)
def itemAt(items: List<&2,SettingItem>,index: Nat) -> Maybe<&2,SettingItem>:
  match items index:
    case item <> _ Zero{}: Some{item}
    case _ <> rest Succ{index}: itemAt(rest,index)
    case Nil{} _: None{}
def getSelectedItem(+state: SettingsList) -> Maybe<&2,SettingItem>:
  match state:
    case SettingsList{_,_,_,index,_,_,_,_,_,_,_,_}: itemAt(getDisplayItems(state),index)
def selection(state: SettingsList,index: Nat,pressed: Maybe<&2,Nat>) -> SettingsList:
  match state:
    case SettingsList{items,filtered,theme,_,_,maximum,change,cancel,search,submenu,origin,dispatch}: SettingsList{items,filtered,theme,index,pressed,maximum,change,cancel,search,submenu,origin,dispatch}
def findId(items: List<&2,SettingItem>,+wanted: String,+index: Nat) -> Maybe<&2,Nat>:
  match items:
    case Nil{}: None{}
    case SettingItem{id,_,_,_,_,_} <> rest: Bool.pick(Unit -> Maybe<&2,Nat>,String.eq(id,wanted),_ => Some{index},_ => findId(rest,wanted,index + 1n))(Unit{})
def selectItem(+state: SettingsList,id: String) -> SettingsList:
  match state:
    case SettingsList{_,_,_,index,pressed,_,_,_,_,_,_,_}: selection(state,Maybe.default(&2,Nat,findId(getDisplayItems(state),id,0n),index),pressed)
def getLabel(item: SettingItem) -> String:
  match item:
    case SettingItem{_,value,_,_,_,_}: value
def applyFilter(state: SettingsList,query: String) -> SettingsList:
  match state:
    case SettingsList{+items,_,theme,_,pressed,maximum,change,cancel,search,submenu,origin,dispatch}: SettingsList{items,Fuzzy.fuzzyFilter(~SettingItem,~getLabel,items,query),theme,0n,pressed,maximum,change,cancel,search,submenu,origin,dispatch}
def withSearch(state: SettingsList,search: Input.Input) -> SettingsList:
  match state:
    case SettingsList{items,filtered,theme,index,pressed,maximum,change,cancel,_,submenu,origin,dispatch}: SettingsList{items,filtered,theme,index,pressed,maximum,change,cancel,Some{search},submenu,origin,dispatch}
def opened(state: SettingsList,component: Component.Component) -> SettingsList:
  match state:
    case SettingsList{items,filtered,theme,+index,pressed,maximum,change,cancel,search,_,_,dispatch}: SettingsList{items,filtered,theme,index,pressed,maximum,change,cancel,search,Some{component},Some{index},dispatch}
def closed(state: SettingsList,navigating: Bool) -> SettingsList:
  match state:
    case SettingsList{items,filtered,theme,+index,pressed,maximum,change,cancel,search,_,origin,dispatch}: SettingsList{items,filtered,theme,Bool.pick(Nat,navigating,index,Maybe.default(&2,Nat,origin,index)),pressed,maximum,change,cancel,search,None{},None{},dispatch}
def currentChanged(+state: SettingsList,+id: String,+value: String) -> IO(SettingsList):
  match state:
    case SettingsList{_,_,_,_,_,_,callback,_,_,_,_,_}:
      +updated = updateValue(state,id,value)
      do IO<SettingsList>:
        C.call(Change,Unit,callback,Change{id,value})
        return updated
def nextValue(values: List<&2,String>,+current: String,+first: String) -> String:
  match values:
    case Nil{}: first
    case value <> +rest:
      Bool.pick(Unit -> String,String.eq(value,current),_ => Maybe.default(&2,String,List.head(&2,String,rest),first),_ => nextValue(rest,current,first))(Unit{})
def activateSelected(+state: SettingsList,item: Maybe<&2,SettingItem>) -> IO(SettingsList):
  match state item:
    case SettingsList{_,_,_,_,_,_,_,_,_,_,_,dispatch} Some{SettingItem{id,_,_,value,_,Some{factory}}}:
      do IO<SettingsList>:
        child : Component.Component <- C.call(SubmenuRequest,Component.Component,factory,SubmenuRequest{value,SubmenuDone{id,dispatch}})
        return opened(state,child)
    case _ Some{SettingItem{id,_,_,value,Some{+first <> rest},None{}}}: currentChanged(state,id,nextValue(first <> rest,value,first))
    case _ _: IO.pure(SettingsList,state)
def activateItem(+state: SettingsList) -> IO(SettingsList): activateSelected(state,getSelectedItem(state))
def navigateAfter(state: SettingsList,target: Maybe<&2,String>) -> IO(SettingsList):
  match target:
    case Some{SCon{char,rest}}: activateItem(selectItem(closed(state,True{}),SCon{char,rest}))
    case _: IO.pure(SettingsList,closed(state,False{}))
def completeSubmenu(+state: SettingsList,completion: Completion) -> IO(SettingsList):
  match completion:
    case Completion{id,Some{value},target}:
      do IO<SettingsList>:
        updated : SettingsList <- currentChanged(state,id,value)
        navigateAfter(updated,target)
    case Completion{_,None{},target}: navigateAfter(state,target)
def invalidate(+state: SettingsList) -> IO(SettingsList):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,_,Some{child},_,_}:
      do IO<SettingsList>:
        Component.invalidate(child)
        return state
    case _: IO.pure(SettingsList,state)

def visibleStart(+index: Nat,+count: Nat,+maximum: Nat) -> Nat:
  Nat.min(index - maximum / 2n,count - maximum)
def widest(items: List<&2,SettingItem>,width: Nat) -> Nat:
  match items:
    case Nil{}: Nat.min(36n,width)
    case item <> rest: widest(rest,Nat.max(width,U.visibleWidth(getLabel(item))))
def renderItem(item: SettingItem,+selected: Bool,+width: Nat,+labelWidth: Nat,theme: SettingsListTheme) -> IO(String):
  match item theme:
    case SettingItem{_,+label,_,value,_,_} SettingsListTheme{paintLabel,paintValue,_,cursor,_}:
      +prefix = Bool.pick(String,selected,cursor,"  ")
      do IO<String>:
        labelText : String <- C.call(ThemeText,String,paintLabel,ThemeText{label ++ U.spaces(labelWidth - U.visibleWidth(label),""),selected})
        valueText : String <- C.call(ThemeText,String,paintValue,ThemeText{U.truncateToWidth(value,width - U.visibleWidth(prefix) - labelWidth - 4n,"",False{}),selected})
        return U.truncateToWidth(prefix ++ labelText ++ "  " ++ valueText,width,"...",False{})
def renderItems(items: List<&2,SettingItem>,skip: Nat,count: Nat,+selected: Nat,+index: Nat,+width: Nat,+labelWidth: Nat,+theme: SettingsListTheme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match items skip count:
    case _ _ Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Nil{} _ _: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case _ <> rest Succ{skip} count: renderItems(rest,skip,count,selected,index + 1n,width,labelWidth,theme,reversed)
    case item <> rest Zero{} Succ{count}:
      do IO<List<&2,String>>:
        line : String <- renderItem(item,Nat.is_eq(index,selected),width,labelWidth,theme)
        renderItems(rest,0n,count,selected,index + 1n,width,labelWidth,theme,line <> reversed)
def descriptionLines(lines: List<&2,String>,+callback: C.Callback<String,String>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        painted : String <- C.call(String,String,callback,"  " ++ line)
        descriptionLines(rest,callback,painted <> reversed)
def selectedDescription(item: Maybe<&2,SettingItem>,width: Nat,theme: SettingsListTheme) -> IO(List<&2,String>):
  match item theme:
    case Some{SettingItem{_,_,Some{SCon{char,rest}},_,_,_}} SettingsListTheme{_,_,paint,_,_}:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- descriptionLines(U.wrapTextWithAnsi(SCon{char,rest},width - 4n),paint,Nil{})
        return "" <> lines
    case _ _: IO.pure(List<&2,String>,Nil{})
def hintLine(theme: SettingsListTheme,search: Bool,width: Nat) -> IO(List<&2,String>):
  match theme:
    case SettingsListTheme{_,_,_,_,hint}:
      do IO<List<&2,String>>:
        painted : String <- C.call(String,String,hint,Bool.pick(String,search,"  Type to search · Enter/Space to change · Esc to cancel","  Enter/Space to change · Esc to cancel"))
        return "" <> U.truncateToWidth(painted,width,"...",False{}) <> Nil{}
def scrollLine(theme: SettingsListTheme,index: Nat,count: Nat,width: Nat) -> IO(List<&2,String>):
  match theme:
    case SettingsListTheme{_,_,_,_,hint}:
      do IO<List<&2,String>>:
        line : String <- C.call(String,String,hint,U.truncateToWidth("  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")",width - 2n,"",False{}))
        return line <> Nil{}
def listLines(+items: List<&2,SettingItem>,+index: Nat,+maximum: Nat,+theme: SettingsListTheme,search: Bool,+width: Nat,labelWidth: Nat) -> IO(List<&2,String>):
  +count = List.length(&2,SettingItem,items)
  +start = visibleStart(index,count,maximum)
  do IO<List<&2,String>>:
    content : List<&2,String> <- renderItems(items,start,maximum,index,0n,width,labelWidth,theme,Nil{})
    scroll : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),Nat.is_gt(start,0n) || Nat.is_lt(start + maximum,count),_ => scrollLine(theme,index,count,width),_ => IO.pure(List<&2,String>,Nil{}))(Unit{})
    desc : List<&2,String> <- selectedDescription(itemAt(items,index),width,theme)
    hint : List<&2,String> <- hintLine(theme,search,width)
    return List.append(&2,String,content,List.append(&2,String,scroll,List.append(&2,String,desc,hint)))
def emptyLines(theme: SettingsListTheme,+hasItems: Bool,+search: Bool,+width: Nat) -> IO(List<&2,String>):
  match theme:
    case SettingsListTheme{+label,+value,+desc,+cursor,+hint}:
      do IO<List<&2,String>>:
        +message : String <- C.call(String,String,hint,Bool.pick(String,hasItems,"  No matching settings","  No settings available"))
        lines : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),search,_ => hintLine(SettingsListTheme{label,value,desc,cursor,hint},True{},width),_ => IO.pure(List<&2,String>,Nil{}))(Unit{})
        return Bool.pick(String,hasItems,U.truncateToWidth(message,width,"...",False{}),message) <> lines
def renderMainList(+state: SettingsList,+width: Nat) -> IO(List<&2,String>):
  match state:
    case SettingsList{+items,_,+theme,index,_,maximum,_,_,+search,_,_,_}:
      +display = getDisplayItems(state)
      Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,SettingItem,items) || List.is_empty(&2,SettingItem,display),
        _ => emptyLines(theme,Bool.not(List.is_empty(&2,SettingItem,items)),enabled(search),width),
        _ => listLines(display,index,maximum,theme,enabled(search),width,widest(items,0n)))(Unit{})
def searchRendered(state: SettingsList,pair: Input.Input & List<&2,String>) -> SettingsList & List<&2,String>:
  match pair:
    case (input,lines): (withSearch(state,input),List.append(&2,String,lines,"" <> Nil{}))
def searchLines(+state: SettingsList,width: Nat) -> IO(SettingsList & List<&2,String>):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,Some{input},_,_,_}:
      do IO<SettingsList & List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(input,width)
        return searchRendered(state,pair)
    case _: IO.pure(SettingsList & List<&2,String>,(state,Nil{}))
def appendedMain(width: Nat,pair: SettingsList & List<&2,String>) -> IO(SettingsList & List<&2,String>):
  match pair:
    case (+state,search):
      do IO<SettingsList & List<&2,String>>:
        lines : List<&2,String> <- renderMainList(state,width)
        return (state,List.append(&2,String,search,lines))
def render(+state: SettingsList,+width: Nat) -> IO(SettingsList & List<&2,String>):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,_,Some{child},_,_}:
      do IO<SettingsList & List<&2,String>>:
        lines : List<&2,String> <- Component.render(child,width)
        return (state,lines)
    case _:
      do IO<SettingsList & List<&2,String>>:
        pair : SettingsList & List<&2,String> <- searchLines(state,width)
        appendedMain(width,pair)

def searched(state: SettingsList,value: Word.ResultOf(Input.Input)) -> Word.ResultOf(SettingsList):
  match value:
    case Fail{error}: Fail{error}
    case Done{+input}: Done{applyFilter(withSearch(state,input),Input.getValue(input))}
def searchQueryEmpty(value: Maybe<&2,Input.Input>) -> Bool:
  match value:
    case None{}: True{}
    case Some{input}: String.eq(Input.getValue(input),"")
def searchKey(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,+state: SettingsList,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Word.ResultOf(SettingsList)):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,Some{input},_,_,_}:
      do IO<Word.ResultOf(SettingsList)>:
        next : Word.ResultOf(Input.Input) <- Input.handleInput(~Context,~segment,~isAtomic,context,input,manager,keyboard,data)
        return searched(state,next)
    case _: IO.pure(Word.ResultOf(SettingsList),Done{state})
def mainInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,+state: SettingsList,+manager: KB.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(Word.ResultOf(SettingsList)):
  match state:
    case SettingsList{_,_,_,+index,+pressed,_,_,cancel,search,_,_,_}:
      +count = List.length(&2,SettingItem,getDisplayItems(state))
      Bool.pick(Unit -> IO(Word.ResultOf(SettingsList)),KB.matches(manager,keyboard,data,"tui.select.up"),
        _ => IO.pure(Word.ResultOf(SettingsList),Done{Bool.pick(SettingsList,Nat.is_eq(count,0n),state,selection(state,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),pressed))}),
        _ => Bool.pick(Unit -> IO(Word.ResultOf(SettingsList)),KB.matches(manager,keyboard,data,"tui.select.down"),
          _ => IO.pure(Word.ResultOf(SettingsList),Done{Bool.pick(SettingsList,Nat.is_eq(count,0n),state,selection(state,Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n),pressed))}),
          _ => Bool.pick(Unit -> IO(Word.ResultOf(SettingsList)),KB.matches(manager,keyboard,data,"tui.select.confirm") || (String.eq(data," ") && searchQueryEmpty(search)),
            _ =>
              do IO<Word.ResultOf(SettingsList)>:
                next : SettingsList <- activateItem(state)
                return Done{next},
            _ => Bool.pick(Unit -> IO(Word.ResultOf(SettingsList)),KB.matches(manager,keyboard,data,"tui.select.cancel"),
              _ =>
                do IO<Word.ResultOf(SettingsList)>:
                  C.call(Unit,Unit,cancel,Unit{})
                  return Done{state},
              _ => searchKey(~Context,~segment,~isAtomic,context,state,manager,keyboard,data))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def handleInput(~Context: Data,~segment: Context -> String -> Word.ResultOf(List<&2,Word.Segment>),~isAtomic: Context -> String -> Bool,context: Context,+state: SettingsList,manager: KB.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Word.ResultOf(SettingsList)):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,_,Some{child},_,_}:
      do IO<Word.ResultOf(SettingsList)>:
        Component.handleInput(child,data)
        return Done{state}
    case _: mainInput(~Context,~segment,~isAtomic,context,state,manager,keyboard,data)

def focusMouse(response: Maybe<&2,Component.MouseResponse>) -> Maybe<&2,Component.MouseResponse>:
  match response:
    case Some{Component.LocalResult{Tui.TuiMouseEventResult{handled,capture,_,wantsRender}}}: Some{Component.LocalResult{Tui.TuiMouseEventResult{handled,capture,True{},wantsRender}}}
    case Some{Component.DispatchedResult{Component.TuiMouseDispatchResult{target,focusTarget,capture,_,wantsRender}}}: Some{Component.DispatchedResult{Component.TuiMouseDispatchResult{target,focusTarget,capture,True{},wantsRender}}}
    case None{}: None{}
def childMouse(child: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match child:
    case Component.Component{_,_,_,Some{callback},_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        response : Maybe<&2,Component.MouseResponse> <- C.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
        return focusMouse(response)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def searchMouse(state: SettingsList,pair: Input.Input & Maybe<&2,Tui.TuiMouseEventResult>) -> SettingsList & Maybe<&2,Component.MouseResponse>:
  match pair:
    case (input,result): (withSearch(state,input),focusMouse(Maybe.map(&2,Tui.TuiMouseEventResult,Component.MouseResponse,value => Component.LocalResult{value},result)))
def wheelIndex(delta: Tui.Offset,+index: Nat,count: Nat) -> Nat:
  match delta:
    case Tui.Backward{Succ{_}}: Nat.min(count - 1n,index - 1n)
    case Tui.Forward{Succ{_}}: Nat.min(count - 1n,index + 1n)
    case _: index
def nonzero(delta: Maybe<&2,Tui.Offset>) -> Bool:
  match delta:
    case Some{Tui.Forward{Succ{_}}}: True{}
    case Some{Tui.Backward{Succ{_}}}: True{}
    case _: False{}
def wheel(+state: SettingsList,delta: Tui.Offset) -> SettingsList & Maybe<&2,Component.MouseResponse>:
  match state:
    case SettingsList{_,_,_,+index,pressed,_,_,_,_,_,_,_}:
      +next = wheelIndex(delta,index,List.length(&2,SettingItem,getDisplayItems(state)))
      (selection(state,next,pressed),Some{Component.LocalResult{Tui.TuiMouseEventResult{True{},False{},False{},Some{Bool.not(Nat.is_eq(index,next))}}}})
def rowNumber(row: Tui.Offset) -> Nat:
  match row:
    case Tui.Forward{value}: value
    case Tui.Backward{_}: 0n
def validRow(row: Tui.Offset,count: Nat) -> Bool:
  match row:
    case Tui.Forward{value}: Nat.is_lt(value,count)
    case Tui.Backward{Zero{}}: Nat.is_gt(count,0n)
    case _: False{}
def clicked(+state: SettingsList,+press: Bool,row: Tui.Offset) -> IO(SettingsList & Maybe<&2,Component.MouseResponse>):
  match state:
    case SettingsList{_,_,_,index,pressed,+maximum,_,_,search,_,_,_}:
      +count = List.length(&2,SettingItem,getDisplayItems(state))
      +start = visibleStart(index,count,maximum)
      +relative = Component.subtract(row,Tui.Forward{Bool.pick(Nat,enabled(search),2n,0n)})
      +target = start + rowNumber(relative)
      +selected = Bool.pick(Nat,press,target,Maybe.default(&2,Nat,pressed,target))
      +updated = selection(state,selected,Bool.pick(Maybe<&2,Nat>,press,Some{target},None{}))
      Bool.pick(Unit -> IO(SettingsList & Maybe<&2,Component.MouseResponse>),validRow(relative,Nat.min(maximum,count - start)),
        _ =>
          do IO<SettingsList & Maybe<&2,Component.MouseResponse>>:
            next : SettingsList <- Bool.pick(Unit -> IO(SettingsList),press,_ => IO.pure(SettingsList,updated),_ => activateItem(updated))(Unit{})
            return (next,Some{Component.LocalResult{Tui.TuiMouseEventResult{True{},False{},press,None{}}}}),
        _ => IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,(state,None{})))(Unit{})
def listMouse(+state: SettingsList,event: Tui.TuiMouseEvent) -> IO(SettingsList & Maybe<&2,Component.MouseResponse>):
  match event:
    case Tui.TuiMouseEvent{Tui.MouseWheel{},_,_,_,_,_,_,_,_,_,_,+delta,_}:
      IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,Bool.pick(Unit -> SettingsList & Maybe<&2,Component.MouseResponse>,nonzero(delta),_ => wheel(state,Maybe.default(&2,Tui.Offset,delta,Tui.Forward{0n})),_ => (state,None{}))(Unit{}))
    case Tui.TuiMouseEvent{Tui.MousePress{},Tui.MouseLeft{},_,row,_,_,_,_,_,_,_,_,_}: clicked(state,True{},row)
    case Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},_,row,_,_,_,_,_,_,_,_,_}: clicked(state,False{},row)
    case _: IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,(state,None{}))
def mainMouse(+state: SettingsList,+event: Tui.TuiMouseEvent) -> IO(SettingsList & Maybe<&2,Component.MouseResponse>):
  match state event:
    case SettingsList{_,_,_,_,_,_,_,_,Some{input},_,_,_} Tui.TuiMouseEvent{_,_,_,Tui.Forward{Zero{}},_,_,_,_,_,_,_,_,_}: IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,searchMouse(state,Input.handleMouse(input,event)))
    case SettingsList{_,_,_,_,_,_,_,_,Some{input},_,_,_} Tui.TuiMouseEvent{_,_,_,Tui.Backward{Zero{}},_,_,_,_,_,_,_,_,_}: IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,searchMouse(state,Input.handleMouse(input,event)))
    case SettingsList{_,_,_,_,_,_,_,_,Some{_},_,_,_} Tui.TuiMouseEvent{_,_,_,Tui.Forward{Succ{Zero{}}},_,_,_,_,_,_,_,_,_}: IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,(state,None{}))
    case _ _: Bool.pick(Unit -> IO(SettingsList & Maybe<&2,Component.MouseResponse>),List.is_empty(&2,SettingItem,getDisplayItems(state)),_ => IO.pure(SettingsList & Maybe<&2,Component.MouseResponse>,(state,None{})),_ => listMouse(state,event))(Unit{})
def handleMouse(+state: SettingsList,+event: Tui.TuiMouseEvent) -> IO(SettingsList & Maybe<&2,Component.MouseResponse>):
  match state:
    case SettingsList{_,_,_,_,_,_,_,_,_,Some{child},_,_}:
      do IO<SettingsList & Maybe<&2,Component.MouseResponse>>:
        response : Maybe<&2,Component.MouseResponse> <- childMouse(child,event)
        return (state,response)
    case _: mainMouse(state,event)
