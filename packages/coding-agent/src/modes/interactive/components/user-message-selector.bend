import Base
import ../../../../../runtime/src/text.bend as Text
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/utils.bend as Utils
import ../theme/theme.bend as Theme

type UserMessageItem is Data: UserMessageItem{id: String,text: String,timestamp: Maybe<&2,String>}
type UserMessageList is Data: UserMessageList{messages: List<&2,UserMessageItem>,selectedIndex: Nat}
type UserMessageSelectorComponent is Data: UserMessageSelectorComponent{messageList: UserMessageList}
type Action is Data: Continue{} Cancel{} Chosen{entryId: String}

def initialIndex(messages: List<&2,UserMessageItem>,+id: String,+index: Nat) -> Maybe<&2,Nat>:
  match messages:
    case Nil{}: None{}
    case UserMessageItem{found,_,_} <> rest:
      Bool.pick(Maybe<&2,Nat>,String.eq(found,id),Some{index},initialIndex(rest,id,index + 1n))
def newList(+messages: List<&2,UserMessageItem>,initialSelectedId: Maybe<&2,String>) -> UserMessageList:
  +fallback = List.length(&2,UserMessageItem,messages) - 1n
  +index = Maybe.bind(&2,String,Nat,initialSelectedId,id => initialIndex(messages,id,0n))
  UserMessageList{messages,Maybe.default(&2,Nat,index,fallback)}
def new(messages: List<&2,UserMessageItem>,initialSelectedId: Maybe<&2,String>) -> UserMessageSelectorComponent:
  UserMessageSelectorComponent{newList(messages,initialSelectedId)}
def getMessageList(component: UserMessageSelectorComponent) -> UserMessageList:
  match component: case UserMessageSelectorComponent{messageList}: messageList
def itemId(item: UserMessageItem) -> String:
  match item: case UserMessageItem{id,_,_}: id
def selectedId(list: UserMessageList) -> Maybe<&2,String>:
  match list:
    case UserMessageList{messages,index}: Maybe.map(&2,UserMessageItem,String,itemId,List.get(&2,UserMessageItem,messages,index))
def move(list: UserMessageList,up: Bool) -> UserMessageList:
  match list:
    case UserMessageList{+messages,+index}:
      +count = List.length(&2,UserMessageItem,messages)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      UserMessageList{messages,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next)}
def confirmed(list: UserMessageList) -> Action:
  Maybe.default(&2,Action,Maybe.map(&2,String,Action,id => Chosen{id},selectedId(list)),Continue{})
def handleInput(+list: UserMessageList,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> UserMessageList & Action:
  Bool.pick(Unit -> UserMessageList & Action,Bindings.matches(bindings,keyboard,data,"tui.select.up"),_ => (move(list,True{}),Continue{}),
    _ => Bool.pick(Unit -> UserMessageList & Action,Bindings.matches(bindings,keyboard,data,"tui.select.down"),_ => (move(list,False{}),Continue{}),
      _ => Bool.pick(Unit -> UserMessageList & Action,Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => (list,confirmed(list)),
        _ => Bool.pick(UserMessageList & Action,Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),(list,Cancel{}),(list,Continue{})))(Unit{}))(Unit{}))(Unit{})
def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def normalized(text: String) -> String:
  Text.trim(String.join(String.split(text,'\n')," "))
def renderRows(messages: List<&2,UserMessageItem>,+index: Nat,+selectedIndex: Nat,+count: Nat,+width: Nat,+theme: Theme.Theme) -> List<&2,String>:
  match messages:
    case Nil{}: Nil{}
    case UserMessageItem{_,text,_} <> rest:
      +active = Nat.is_eq(index,selectedIndex)
      +cursor = Bool.pick(String,active,paint(theme,"accent","› "),"  ")
      +body = Utils.truncateToWidth(normalized(text),width - 2n,"...",False{})
      (cursor ++ Bool.pick(String,active,Theme.bold(body),body)) <>
        paint(theme,"muted","  Message " ++ Nat.show(index + 1n) ++ " of " ++ Nat.show(count)) <> "" <>
        renderRows(rest,index + 1n,selectedIndex,count,width,theme)
def renderList(list: UserMessageList,+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  match list:
    case UserMessageList{+messages,+selectedIndex}:
      +count = List.length(&2,UserMessageItem,messages)
      +start = Nat.min(selectedIndex - 5n,count - 10n)
      +end = Nat.min(start + 10n,count)
      +rows = renderRows(List.take(&2,UserMessageItem,List.drop(&2,UserMessageItem,messages,start),10n),start,selectedIndex,count,width,theme)
      +scroll = Bool.pick(List<&2,String>,Nat.is_gt(start,0n) || Nat.is_lt(end,count),paint(theme,"muted","  (" ++ Nat.show(selectedIndex + 1n) ++ "/" ++ Nat.show(count) ++ ")") <> Nil{},Nil{})
      Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No user messages found") <> Nil{},List.append(&2,String,rows,scroll))
def rendered(component: UserMessageSelectorComponent,+theme: Theme.Theme,+width: Nat,title: TuiText.Text & List<&2,String>,description: TuiText.Text & List<&2,String>) -> List<&2,String>:
  match title description:
    case Tuple{_,heading} Tuple{_,details}:
      +border = paint(theme,"border",String.repeat("─",Nat.max(1n,width)))
      List.append(&2,String,"" <> heading,List.append(&2,String,details,"" <> border <> "" <> List.append(&2,String,renderList(getMessageList(component),theme,width),"" <> border <> Nil{})))
def render(component: UserMessageSelectorComponent,+theme: Theme.Theme,+width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    title : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(Theme.bold("Fork from Message"),Some{1n},Some{0n},None{}),width)
    description : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(paint(theme,"muted","Select a user message to copy the active path up to that point into a new session"),Some{1n},Some{0n},None{}),width)
    return rendered(component,theme,width,title,description)
