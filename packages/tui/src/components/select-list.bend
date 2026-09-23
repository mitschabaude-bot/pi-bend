import Base
import ../utils.bend as U
import ../tui.bend as Tui
import ../keys.bend as Keys
import ../keybindings.bend as KB
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/case-map.bend as CaseMap

type SelectItem is Data:
  SelectItem{value: String,label: String,description: Maybe<&2,String>}
type SelectListTheme is Data:
  SelectListTheme{selectedPrefix: C.Callback<String,String>,selectedText: C.Callback<String,String>,description: C.Callback<String,String>,scrollInfo: C.Callback<String,String>,noMatch: C.Callback<String,String>}
type SelectListTruncatePrimaryContext is Data:
  SelectListTruncatePrimaryContext{text: String,maxWidth: Tui.Offset,columnWidth: Tui.Offset,item: SelectItem,isSelected: Bool}
type SelectListLayoutOptions is Data:
  SelectListLayoutOptions{minPrimaryColumnWidth: Maybe<&2,Nat>,maxPrimaryColumnWidth: Maybe<&2,Nat>,truncatePrimary: Maybe<&2,C.Callback<SelectListTruncatePrimaryContext,String>>}
type SelectList is Data:
  SelectList{items: List<&2,SelectItem>,filteredItems: List<&2,SelectItem>,selectedIndex: Nat,mousePressedIndex: Maybe<&2,Nat>,maxVisible: Nat,theme: SelectListTheme,layout: SelectListLayoutOptions,onSelect: Maybe<&2,C.Callback<SelectItem,Unit>>,onCancel: Maybe<&2,C.Callback<Unit,Unit>>,onSelectionChange: Maybe<&2,C.Callback<SelectItem,Unit>>}

# Callbacks are borrowed; their owner keeps them alive for each operation.
def new(+items: List<&2,SelectItem>,maxVisible: Nat,theme: SelectListTheme,layout: Maybe<&2,SelectListLayoutOptions>) -> SelectList:
  SelectList{items,items,0n,None{},maxVisible,theme,Maybe.default(&2,SelectListLayoutOptions,layout,SelectListLayoutOptions{None{},None{},None{}}),None{},None{},None{}}
def invalidate(state: SelectList) -> SelectList: state
def setCallbacks(state: SelectList,onSelect: Maybe<&2,C.Callback<SelectItem,Unit>>,onCancel: Maybe<&2,C.Callback<Unit,Unit>>,onSelectionChange: Maybe<&2,C.Callback<SelectItem,Unit>>) -> SelectList:
  match state:
    case SelectList{items,filtered,index,pressed,maximum,theme,layout,_,_,_}: SelectList{items,filtered,index,pressed,maximum,theme,layout,onSelect,onCancel,onSelectionChange}
def selection(state: SelectList,index: Nat,pressed: Maybe<&2,Nat>) -> SelectList:
  match state:
    case SelectList{items,filtered,_,_,maximum,theme,layout,select,cancel,change}: SelectList{items,filtered,index,pressed,maximum,theme,layout,select,cancel,change}
def setSelectedIndex(state: SelectList,index: Nat) -> SelectList:
  match state:
    case SelectList{items,+filtered,_,pressed,maximum,theme,layout,select,cancel,change}: SelectList{items,filtered,Nat.min(index,List.length(&2,SelectItem,filtered) - 1n),pressed,maximum,theme,layout,select,cancel,change}
def itemAt(items: List<&2,SelectItem>,index: Nat) -> Maybe<&2,SelectItem>:
  match items index:
    case item <> _ Zero{}: Some{item}
    case _ <> rest Succ{index}: itemAt(rest,index)
    case Nil{} _: None{}
def getSelectedItem(state: SelectList) -> Maybe<&2,SelectItem>:
  match state:
    case SelectList{_,items,index,_,_,_,_,_,_,_}: itemAt(items,index)
def starts(text: String,prefix: String) -> Bool:
  match text prefix:
    case _ SNil{}: True{}
    case SCon{char,+rest} SCon{expected,+tail}: Bool.pick(Unit -> Bool,Char.is_eq(char,expected),_ => starts(rest,tail),_ => False{})(Unit{})
    case _ _: False{}
def filtered(items: List<&2,SelectItem>,+prefix: String,+reversed: List<&2,SelectItem>) -> List<&2,SelectItem>:
  match items:
    case Nil{}: List.reverse(&2,SelectItem,reversed)
    case SelectItem{+value,label,desc} <> rest: filtered(rest,prefix,Bool.pick(List<&2,SelectItem>,starts(CaseMap.lower(value),prefix),SelectItem{value,label,desc} <> reversed,reversed))

def setFilter(state: SelectList,filter: String) -> SelectList:
  match state:
    case SelectList{+items,_,_,pressed,maximum,theme,layout,select,cancel,change}: SelectList{items,filtered(items,CaseMap.lower(filter),Nil{}),0n,pressed,maximum,theme,layout,select,cancel,change}

def display(item: SelectItem) -> String:
  match item:
    case SelectItem{value,+label,_}: Bool.pick(String,String.eq(label,""),value,label)
def trimStart(text: String) -> String:
  match text:
    case SCon{+char,+rest}: Bool.pick(Unit -> String,Text.whitespace(Char.to_u32(char)),_ => trimStart(rest),_ => SCon{char,rest})(Unit{})
    case SNil{}: ""
def singleLine(text: String,+newline: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(trimStart(String.reverse(trimStart(String.reverse(reversed)))))
    case SCon{+char,rest}:
      +isNewline = Char.is_eq(char,'\r') || Char.is_eq(char,'\n')
      singleLine(rest,isNewline,Bool.pick(String,isNewline,Bool.pick(String,newline,reversed,SCon{' ',reversed}),SCon{char,reversed}))
def description(item: SelectItem) -> String:
  match item:
    case SelectItem{_,_,value}: singleLine(Maybe.default(&2,String,value,""),False{},"")
def widest(items: List<&2,SelectItem>,maximum: Nat) -> Nat:
  match items:
    case Nil{}: maximum
    case item <> rest: widest(rest,Nat.max(maximum,U.visibleWidth(display(item)) + 2n))
def primaryWidth(items: List<&2,SelectItem>,options: SelectListLayoutOptions) -> Nat:
  match options:
    case SelectListLayoutOptions{+minimum,+maximum,_}:
      +low = Maybe.default(&2,Nat,minimum,Maybe.default(&2,Nat,maximum,32n))
      +high = Maybe.default(&2,Nat,maximum,Maybe.default(&2,Nat,minimum,32n))
      Nat.max(Nat.max(1n,Nat.min(low,high)),Nat.min(widest(items,0n),Nat.max(1n,Nat.max(low,high))))
def difference(+left: Nat,+right: Nat) -> Tui.Offset:
  Bool.pick(Tui.Offset,Nat.is_ge(left,right),Tui.Forward{left - right},Tui.Backward{right - left})
def nonnegative(offset: Tui.Offset) -> Nat:
  match offset:
    case Tui.Forward{value}: value
    case Tui.Backward{_}: 0n
def truncatePrimary(+item: SelectItem,isSelected: Bool,+maxWidth: Tui.Offset,columnWidth: Tui.Offset,layout: SelectListLayoutOptions) -> IO(String):
  match layout:
    case SelectListLayoutOptions{_,_,None{}}: IO.pure(String,U.truncateToWidth(display(item),nonnegative(maxWidth),"",False{}))
    case SelectListLayoutOptions{_,_,Some{callback}}:
      do IO<String>:
        result : String <- C.call(SelectListTruncatePrimaryContext,String,callback,SelectListTruncatePrimaryContext{display(item),maxWidth,columnWidth,item,isSelected})
        return U.truncateToWidth(result,nonnegative(maxWidth),"",False{})
def plain(item: SelectItem,+selected: Bool,+width: Nat,theme: SelectListTheme,layout: SelectListLayoutOptions) -> IO(String):
  match theme:
    case SelectListTheme{_,paint,_,_,_}:
      do IO<String>:
        +value : String <- truncatePrimary(item,selected,difference(width,4n),difference(width,4n),layout)
        Bool.pick(Unit -> IO(String),selected,_ => C.call(String,String,paint,"→ " ++ value),_ => IO.pure(String,"  " ++ value))(Unit{})
def withDescription(+item: SelectItem,+selected: Bool,+width: Nat,+theme: SelectListTheme,+layout: SelectListLayoutOptions,+desc: String,column: Nat,+value: String) -> IO(String):
  match theme:
    case SelectListTheme{_,paint,paintDesc,_,_}:
      +spacing = U.spaces(Nat.max(1n,column - U.visibleWidth(value)),"")
      +remaining = width - (2n + U.visibleWidth(value) + String.length(spacing)) - 2n
      Bool.pick(Unit -> IO(String),Nat.is_gt(remaining,10n),
        _ => Bool.pick(Unit -> IO(String),selected,
          _ => C.call(String,String,paint,"→ " ++ value ++ spacing ++ U.truncateToWidth(desc,remaining,"",False{})),
          _ =>
            do IO<String>:
              painted : String <- C.call(String,String,paintDesc,spacing ++ U.truncateToWidth(desc,remaining,"",False{}))
              return "  " ++ value ++ painted)(Unit{}),
        _ => plain(item,selected,width,theme,layout))(Unit{})
def renderItem(+item: SelectItem,+selected: Bool,+width: Nat,+theme: SelectListTheme,+layout: SelectListLayoutOptions,primaryColumnWidth: Nat) -> IO(String):
  +desc = description(item)
  +column = Nat.max(1n,Nat.min(primaryColumnWidth,width - 6n))
  Bool.pick(Unit -> IO(String),Bool.not(String.eq(desc,"")) && Nat.is_gt(width,40n),
    _ =>
      do IO<String>:
        value : String <- truncatePrimary(item,selected,Tui.Forward{Nat.max(1n,column - 2n)},Tui.Forward{column},layout)
        withDescription(item,selected,width,theme,layout,desc,column,value),
    _ => plain(item,selected,width,theme,layout))(Unit{})
def visibleStart(+index: Nat,+count: Nat,+maximum: Nat) -> Nat:
  Nat.min(index - maximum / 2n,count - maximum)
def renderItems(items: List<&2,SelectItem>,skip: Nat,count: Nat,+selected: Nat,+index: Nat,+width: Nat,+theme: SelectListTheme,+layout: SelectListLayoutOptions,+column: Nat,reversed: List<&2,String>) -> IO(List<&2,String>):
  match items skip count:
    case _ _ Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Nil{} _ _: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case _ <> rest Succ{skip} count: renderItems(rest,skip,count,selected,index + 1n,width,theme,layout,column,reversed)
    case item <> rest Zero{} Succ{count}:
      do IO<List<&2,String>>:
        line : String <- renderItem(item,Nat.is_eq(index,selected),width,theme,layout,column)
        renderItems(rest,0n,count,selected,index + 1n,width,theme,layout,column,line <> reversed)
def renderNonempty(+items: List<&2,SelectItem>,+index: Nat,+maximum: Nat,+theme: SelectListTheme,+layout: SelectListLayoutOptions,+width: Nat) -> IO(List<&2,String>):
  match theme:
    case SelectListTheme{_,_,_,scroll,_}:
      +count = List.length(&2,SelectItem,items)
      +start = visibleStart(index,count,maximum)
      do IO<List<&2,String>>:
        +lines : List<&2,String> <- renderItems(items,start,maximum,index,0n,width,theme,layout,primaryWidth(items,layout),Nil{})
        Bool.pick(Unit -> IO(List<&2,String>),Nat.is_gt(start,0n) || Nat.is_lt(start + maximum,count),
          _ =>
            do IO<List<&2,String>>:
              indicator : String <- C.call(String,String,scroll,U.truncateToWidth("  (" ++ Nat.show(index + 1n) ++ "/" ++ Nat.show(count) ++ ")",width - 2n,"",False{}))
              return List.append(&2,String,lines,indicator <> Nil{}),
          _ => IO.pure(List<&2,String>,lines))(Unit{})
def render(state: SelectList,+width: Nat) -> IO(List<&2,String>):
  match state:
    case SelectList{_,+items,index,_,maximum,SelectListTheme{prefix,paint,desc,scroll,+noMatch},layout,_,_,_}:
      Bool.pick(Unit -> IO(List<&2,String>),List.is_empty(&2,SelectItem,items),
        _ =>
          do IO<List<&2,String>>:
            line : String <- C.call(String,String,noMatch,"  No matching commands")
            return line <> Nil{},
        _ => renderNonempty(items,index,maximum,SelectListTheme{prefix,paint,desc,scroll,noMatch},layout,width))(Unit{})

def callItem(callback: Maybe<&2,C.Callback<SelectItem,Unit>>,item: Maybe<&2,SelectItem>) -> IO(Unit):
  match callback item:
    case Some{callback} Some{item}: C.call(SelectItem,Unit,callback,item)
    case _ _: IO.pure(Unit,Unit{})
def notifySelectionChange(+state: SelectList) -> IO(Unit):
  match state:
    case SelectList{_,_,_,_,_,_,_,_,_,callback}: callItem(callback,getSelectedItem(state))
def notifySelect(+state: SelectList) -> IO(Unit):
  match state:
    case SelectList{_,_,_,_,_,_,_,callback,_,_}: callItem(callback,getSelectedItem(state))
def notifyCancel(state: SelectList) -> IO(Unit):
  match state:
    case SelectList{_,_,_,_,_,_,_,_,Some{callback},_}: C.call(Unit,Unit,callback,Unit{})
    case _: IO.pure(Unit,Unit{})
def changed(+state: SelectList) -> IO(SelectList):
  do IO<SelectList>:
    notifySelectionChange(state)
    return state

def handleInput(+state: SelectList,+keybindings: KB.KeybindingsManager,+context: Keys.Context,+keyData: String) -> IO(SelectList):
  match state:
    case SelectList{_,items,+index,+pressed,_,_,_,_,_,_}:
      +count = List.length(&2,SelectItem,items)
      Bool.pick(Unit -> IO(SelectList),KB.matches(keybindings,context,keyData,"tui.select.up"),
        _ => changed(selection(state,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),pressed)),
        _ => Bool.pick(Unit -> IO(SelectList),KB.matches(keybindings,context,keyData,"tui.select.down"),
          _ => changed(selection(state,Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n),pressed)),
          _ => Bool.pick(Unit -> IO(SelectList),KB.matches(keybindings,context,keyData,"tui.select.confirm"),
            _ =>
              do IO<SelectList>:
                notifySelect(state)
                return state,
            _ => Bool.pick(Unit -> IO(SelectList),KB.matches(keybindings,context,keyData,"tui.select.cancel"),
              _ =>
                do IO<SelectList>:
                  notifyCancel(state)
                  return state,
              _ => IO.pure(SelectList,state))(Unit{}))(Unit{}))(Unit{}))(Unit{})

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
def wheel(+state: SelectList,delta: Tui.Offset) -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>):
  match state:
    case SelectList{_,items,+index,+pressed,_,_,_,_,_,_}:
      +next = wheelIndex(delta,index,List.length(&2,SelectItem,items))
      +moved = Bool.not(Nat.is_eq(index,next))
      +updated = selection(state,next,pressed)
      do IO<SelectList & Maybe<&2,Tui.TuiMouseEventResult>>:
        Bool.pick(Unit -> IO(Unit),moved,_ => notifySelectionChange(updated),_ => IO.pure(Unit,Unit{}))(Unit{})
        return (updated,Some{Tui.TuiMouseEventResult{True{},False{},False{},Some{moved}}})
def validRow(row: Tui.Offset,count: Nat) -> Bool:
  match row:
    case Tui.Forward{value}: Nat.is_lt(value,count)
    case Tui.Backward{Zero{}}: Nat.is_gt(count,0n)
    case _: False{}
def mouseItem(+state: SelectList,+pressed: Bool,+row: Tui.Offset) -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>):
  match state:
    case SelectList{_,items,+index,oldPressed,+maximum,_,_,_,_,_}:
      +count = List.length(&2,SelectItem,items)
      +start = visibleStart(index,count,maximum)
      +target = start + nonnegative(row)
      +chosen = Bool.pick(Nat,pressed,target,Maybe.default(&2,Nat,oldPressed,target))
      +updated = selection(state,chosen,Bool.pick(Maybe<&2,Nat>,pressed,Some{target},None{}))
      Bool.pick(Unit -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>),validRow(row,Nat.min(maximum,count - start)),
        _ =>
          do IO<SelectList & Maybe<&2,Tui.TuiMouseEventResult>>:
            Bool.pick(Unit -> IO(Unit),Bool.not(Nat.is_eq(index,chosen)),_ => notifySelectionChange(updated),_ => IO.pure(Unit,Unit{}))(Unit{})
            Bool.pick(Unit -> IO(Unit),pressed,_ => IO.pure(Unit,Unit{}),_ => notifySelect(updated))(Unit{})
            return (updated,Some{Tui.TuiMouseEventResult{True{},False{},pressed,None{}}}),
        _ => IO.pure(SelectList & Maybe<&2,Tui.TuiMouseEventResult>,(state,None{})))(Unit{})
def mouseNonempty(+state: SelectList,event: Tui.TuiMouseEvent) -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>):
  match event:
    case Tui.TuiMouseEvent{Tui.MouseWheel{},_,_,_,_,_,_,_,_,_,_,+delta,_}:
      Bool.pick(Unit -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>),nonzero(delta),_ => wheel(state,Maybe.default(&2,Tui.Offset,delta,Tui.Forward{0n})),_ => IO.pure(SelectList & Maybe<&2,Tui.TuiMouseEventResult>,(state,None{})))(Unit{})
    case Tui.TuiMouseEvent{Tui.MousePress{},Tui.MouseLeft{},_,row,_,_,_,_,_,_,_,_,_}: mouseItem(state,True{},row)
    case Tui.TuiMouseEvent{Tui.MouseClick{},Tui.MouseLeft{},_,row,_,_,_,_,_,_,_,_,_}: mouseItem(state,False{},row)
    case _: IO.pure(SelectList & Maybe<&2,Tui.TuiMouseEventResult>,(state,None{}))
def handleMouse(+state: SelectList,event: Tui.TuiMouseEvent) -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>):
  match state:
    case SelectList{_,items,_,_,_,_,_,_,_,_}:
      Bool.pick(Unit -> IO(SelectList & Maybe<&2,Tui.TuiMouseEventResult>),List.is_empty(&2,SelectItem,items),_ => IO.pure(SelectList & Maybe<&2,Tui.TuiMouseEventResult>,(state,None{})),_ => mouseNonempty(state,event))(Unit{})
