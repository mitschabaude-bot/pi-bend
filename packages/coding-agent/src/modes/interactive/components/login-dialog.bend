import Base
import ../../../../../runtime/src/abort.bend as Abort
import ../../../../../ai/src/auth/types.bend as Auth
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/deferred.bend as Deferred
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/word-segmenter.bend as Words
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/tui.bend as Tui
import ../../../../../tui/src/utils.bend as Utils
import ../../../../../tui/src/fuzzy.bend as Fuzzy
import ../theme/theme.bend as Theme
import ./keybinding-hints.bend as Hints

# Replaces the editor while the native device flow waits for authorization.
# Esc calls the flow's abort controller; closing restores the original editor.
type Choice is Data: Choice{id: String,label: String,description: String,search: String}
type Menu is Data: Method{} Provider{} Generic{} AuthSelect{}
type AuthLine is Data:
  Blank{}
  Text{style: String, text: String}
  Link{style: String, url: String, label: String}
  Entered{}
  Hint{manual: Bool}
type State is Data: Closed{} Choosing{menu: Menu,title: String,all: List<&2,Choice>,visible: List<&2,Choice>,selected: Nat,query: String} Waiting{} Device{url: String,code: String} Manual{url: String,input: Input.Input} Prompt{title: String,message: String,secret: Bool,input: Input.Input} Info{title: String,message: String} AuthDialog{title: String,content: List<&2,AuthLine>,input: Input.Input,secret: Bool,active: Bool}
type InputSubmission is Data:
  InputSubmission{state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>}
type Host is Data:
  Host{state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,editor: Component.Component,theme: Ref.Ref<Theme.Theme>,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>,words: Ref.Ref<Words.Source>,submit: Callback.Callback<String,Unit>}
type Owner is Type:
  Owner{host: Host,component: Component.Component,renderCallback: Callback.Callback<Nat,List<&2,String>>,inputCallback: Callback.Callback<String,Unit>,mouseCallback: Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>>,invalidateCallback: Callback.Callback<Unit,Unit>,focusCallback: Callback.Callback<Bool,Unit>}

def paint(theme: Theme.Theme,key: String,+text: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,text),text)
def bar(width: Nat) -> String:
  match width:
    case Zero{}: ""
    case Succ{rest}: "─" ++ bar(rest)
def clipped(text: String,width: Nat) -> String:
  Utils.truncateToWidth(text,width,"",False{})
def linked(+url: String,width: Nat) -> String:
  +label = clipped(url,width - 1n)
  " \u{1b}]8;;" ++ url ++ "\u{7}" ++ label ++ "\u{1b}]8;;\u{7}"
def clipLines(lines: List<&2,String>,+width: Nat) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: clipped(line,width) <> clipLines(rest,width)
def frameLines(+theme: Theme.Theme,+width: Nat,title: String,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent",title) <> "" <> List.append(&2,String,body,paint(theme,"dim",bar(width)) <> Nil{})
def frame(theme: Theme.Theme,+width: Nat,title: String,body: List<&2,String>) -> List<&2,String>:
  clipLines(frameLines(theme,width,title,body),width)
def linkedFrame(+theme: Theme.Theme,+width: Nat,title: String,url: String,body: List<&2,String>) -> List<&2,String>:
  paint(theme,"dim",bar(width)) <> paint(theme,"accent",title) <> "" <> paint(theme,"accent",linked(url,width)) <> List.append(&2,String,clipLines(body,width),paint(theme,"dim",bar(width)) <> Nil{})
def waiting(+theme: Theme.Theme,width: Nat) -> List<&2,String>:
  frame(theme,width," Login to OpenAI Codex",paint(theme,"dim"," Requesting device code...") <> "" <> " (Esc to cancel)" <> Nil{})
def searchText(choice: Choice) -> String:
  match choice: case Choice{_,_,_,search}: search
def filtered(+choices: List<&2,Choice>,+query: String) -> List<&2,Choice>:
  Bool.pick(List<&2,Choice>,String.is_empty(query),choices,Fuzzy.fuzzyFilter(~Choice,~searchText,choices,query))
def choiceRow(choice: Choice,+index: Nat,+selected: Nat,width: Nat,theme: Theme.Theme) -> String:
  match choice:
    case Choice{_,+label,+description,_}:
      +text = Bool.pick(String,Nat.is_eq(index,selected)," › ","   ") ++ label ++ Bool.pick(String,String.is_empty(description),""," · " ++ description)
      Utils.truncateToWidth(paint(theme,Bool.pick(String,Nat.is_eq(index,selected),"accent","muted"),text),width,"",False{})
def choiceRows(choices: List<&2,Choice>,+index: Nat,+selected: Nat,+width: Nat,+theme: Theme.Theme) -> List<&2,String>:
  match choices:
    case Nil{}: Nil{}
    case choice <> rest: choiceRow(choice,index,selected,width,theme) <> choiceRows(rest,index + 1n,selected,width,theme)
def selectorRow(choice: Choice,index: Nat,selected: Nat,+theme: Theme.Theme) -> String:
  match choice:
    case Choice{_,+label,+description,_}:
      +chosen = Nat.is_eq(index,selected)
      +name = Bool.pick(String,chosen," " ++ paint(theme,"accent","→ " ++ label),"   " ++ paint(theme,"text",label))
      +status = Bool.pick(String,String.is_empty(description),"",paint(theme,Bool.pick(String,String.starts_with(description," ✓"),"success","muted"),description))
      name ++ status
def selectorRows(choices: List<&2,Choice>,+index: Nat,+selected: Nat,+theme: Theme.Theme) -> List<&2,String>:
  match choices:
    case Nil{}: Nil{}
    case choice <> rest: selectorRow(choice,index,selected,theme) <> selectorRows(rest,index + 1n,selected,theme)
def selectorTitle(theme: Theme.Theme,title: String) -> String:
  " " ++ paint(theme,"accent",Theme.bold(title))
def selectorBorder(theme: Theme.Theme,width: Nat) -> String:
  paint(theme,"border",bar(width))
def methodMenu(+theme: Theme.Theme,+width: Nat,title: String,choices: List<&2,Choice>,selected: Nat,+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  selectorBorder(theme,width) <> "" <> selectorTitle(theme,title) <> "" <>
    List.append(&2,String,selectorRows(choices,0n,selected,theme),
      "" <> (" " ++ Hints.rawKeyHint(theme,"↑↓","navigate") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.confirm","select") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel")) <> "" <> selectorBorder(theme,width) <> Nil{})
def providerMenu(+theme: Theme.Theme,+width: Nat,+visible: List<&2,Choice>,+selected: Nat,query: String) -> List<&2,String>:
  +count = List.length(&2,Choice,visible)
  +start = Nat.min(selected - 4n,count - Nat.min(count,8n))
  +shown = List.take(&2,Choice,List.drop(&2,Choice,visible,start),8n)
  +rows = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching providers") <> Nil{},selectorRows(shown,start,selected,theme))
  +paging = Bool.pick(List<&2,String>,Nat.is_gt(count,8n),(" " ++ paint(theme,"muted","  (" ++ Nat.show(selected + 1n) ++ "/" ++ Nat.show(count) ++ ")")) <> Nil{},Nil{})
  selectorBorder(theme,width) <> "" <> selectorTitle(theme,"Select provider to configure:") <> "" <>
    ("> " ++ query ++ "\u{1b}[7m \u{1b}[0m") <> "" <> List.append(&2,String,rows,List.append(&2,String,paging,"" <> selectorBorder(theme,width) <> Nil{}))
def choosing(+theme: Theme.Theme,+width: Nat,title: String,+visible: List<&2,Choice>,+selected: Nat,query: String) -> List<&2,String>:
  +count = List.length(&2,Choice,visible)
  +start = Nat.min(selected - 5n,count - Nat.min(count,10n))
  +body = Bool.pick(List<&2,String>,Nat.is_eq(count,0n),paint(theme,"muted","  No matching credentials") <> Nil{},choiceRows(List.take(&2,Choice,List.drop(&2,Choice,visible,start),10n),start,selected,width,theme))
  frame(theme,width,title,(paint(theme,"muted"," Search: ") ++ paint(theme,"accent",query)) <> List.append(&2,String,body,"" <> paint(theme,"dim"," ↑/↓ select · Enter confirm · Esc cancel") <> Nil{}))
def choosingMenu(menu: Menu,theme: Theme.Theme,+width: Nat,title: String,visible: List<&2,Choice>,selected: Nat,query: String,bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  match menu:
    case Method{}: clipLines(methodMenu(theme,width,title,visible,selected,bindings),width)
    case Provider{}: clipLines(providerMenu(theme,width,visible,selected,query),width)
    case Generic{}: choosing(theme,width,title,visible,selected,query)
    case AuthSelect{}: clipLines(methodMenu(theme,width,title,visible,selected,bindings),width)
def manual(+theme: Theme.Theme,+width: Nat,+url: String,+input: String) -> List<&2,String>:
  linkedFrame(theme,width," Login to Anthropic",url,paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"dim"," Complete login in your browser; paste the redirect URL if it is on another machine.") <> paint(theme,"warning"," Paste authorization code or redirect URL:") <> input <> "" <> paint(theme,"dim"," Enter to submit · Esc to cancel") <> Nil{})
def promptFrame(+theme: Theme.Theme,+width: Nat,title: String,message: String,input: String,+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  clipLines(selectorBorder(theme,width) <> selectorTitle(theme,title) <> "" <> (" " ++ paint(theme,"text",message)) <>
    input <>
    (" (" ++ Hints.keyHint(theme,bindings,"tui.select.cancel","to cancel,") ++ " " ++ Hints.keyHint(theme,bindings,"tui.select.confirm","to submit") ++ ")") <>
    selectorBorder(theme,width) <> Nil{},width)
def infoFrame(+theme: Theme.Theme,+width: Nat,title: String,message: String,+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  clipLines(selectorBorder(theme,width) <> selectorTitle(theme,title) <> "" <> (" " ++ paint(theme,"text",message)) <>
    "" <> (" (" ++ Hints.keyHint(theme,bindings,"tui.select.cancel","to close") ++ ")") <>
    selectorBorder(theme,width) <> Nil{},width)
def device(+theme: Theme.Theme,+width: Nat,+url: String,code: String) -> List<&2,String>:
  linkedFrame(theme,width," Login to OpenAI Codex",url,paint(theme,"dim"," Ctrl+click to open") <> "" <> paint(theme,"warning"," Enter code: " ++ code) <> "" <> paint(theme,"dim"," Waiting for authentication...") <> " (Esc to cancel)" <> Nil{})
def masked(input: Input.Input,secret: Bool) -> Input.Input:
  match input:
    case Input.Input{Input.Editing{+value,cursor,ring,action,undo},options,start,focused,paste,pasting,submit,escape}:
      Input.Input{Input.Editing{Bool.pick(String,secret,String.repeat("•",String.length(value)),value),cursor,ring,action,undo},options,start,focused,paste,pasting,submit,escape}
def inputLine(pair: Input.Input & List<&2,String>) -> String:
  match pair: case (_,lines): Maybe.default(&2,String,List.head(&2,String,lines),"")
def authLines(lines: List<&2,AuthLine>,+theme: Theme.Theme,+width: Nat,+input: String,+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case Blank{} <> rest: "" <> authLines(rest,theme,width,input,bindings)
    case Text{style,text} <> rest: (" " ++ paint(theme,style,text)) <> authLines(rest,theme,width,input,bindings)
    case Link{style,+url,label} <> rest:
      paint(theme,style," \u{1b}]8;;" ++ url ++ "\u{7}" ++ clipped(label,width - 1n) ++ "\u{1b}]8;;\u{7}") <> authLines(rest,theme,width,input,bindings)
    case Entered{} <> rest: input <> authLines(rest,theme,width,input,bindings)
    case Hint{+isManual} <> rest:
      (" (" ++ Hints.keyHint(theme,bindings,"tui.select.cancel",Bool.pick(String,isManual,"to cancel","to cancel,")) ++ Bool.pick(String,isManual,""," " ++ Hints.keyHint(theme,bindings,"tui.select.confirm","to submit")) ++ ")") <> authLines(rest,theme,width,input,bindings)
def authFrame(+theme: Theme.Theme,+width: Nat,title: String,content: List<&2,AuthLine>,input: String,bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  clipLines(selectorBorder(theme,width) <> selectorTitle(theme,title) <> List.append(&2,String,authLines(content,theme,width,input,bindings),selectorBorder(theme,width) <> Nil{}),width)
def drawCurrent(state: State,editor: Component.Component,theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(List<&2,String>):
  match state:
    case Closed{}: Component.render(editor,width)
    case Choosing{menu,title,_,visible,selected,query}: IO.pure(List<&2,String>,choosingMenu(menu,theme,width,title,visible,selected,query,bindings))
    case Waiting{}: IO.pure(List<&2,String>,waiting(theme,width))
    case Device{url,code}: IO.pure(List<&2,String>,device(theme,width,url,code))
    case Manual{url,input}:
      do IO<List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(input,width)
        return manual(theme,width,url,inputLine(pair))
    case Prompt{title,message,secret,input}:
      do IO<List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(masked(input,secret),width)
        return promptFrame(theme,width,title,message,inputLine(pair),bindings)
    case AuthDialog{title,content,input,secret,_}:
      do IO<List<&2,String>>:
        pair : Input.Input & List<&2,String> <- Input.render(masked(input,secret),width)
        return authFrame(theme,width,title,content,inputLine(pair),bindings)
    case Info{title,message}: IO.pure(List<&2,String>,infoFrame(theme,width,title,message,bindings))
def draw(host: Host,width: Nat) -> IO(List<&2,String>):
  match host:
    case Host{state,_,editor,theme,bindings,_,_,_,_}:
      do IO<List<&2,String>>:
        current : State <- Ref.read(State,state)
        colors : Theme.Theme <- Ref.read(Theme.Theme,theme)
        drawCurrent(current,editor,colors,width,bindings)
def resolveReply(current: Maybe<&2,Deferred.Deferred<String>>,value: String) -> IO(Unit):
  match current:
    case None{}: IO.pure(Unit,Unit{})
    case Some{pending}:
      do IO<Unit>:
        done : Bool <- Deferred.resolve(String,pending,value)
        return Unit{}
def settle(reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,value: String) -> IO(Unit):
  do IO<Unit>:
    current : Maybe<&2,Deferred.Deferred<String>> <- Ref.swap(Maybe<&2,Deferred.Deferred<String>>,reply,None{})
    resolveReply(current,value)
def dropReversed(reversed: String) -> String:
  match reversed:
    case SNil{}: ""
    case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: dropReversed(String.reverse(text))
def printableTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{code},rest}: U32.is_ge(code,32) && printableTail(rest)
def printable(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code},rest}: U32.is_ge(code,32) && printableTail(rest)
def submittedLines(lines: List<&2,AuthLine>,+value: String) -> List<&2,AuthLine>:
  match lines:
    case Nil{}: Nil{}
    case Entered{} <> rest: Text{"text","> " ++ value} <> submittedLines(rest,value)
    case line <> rest: line <> submittedLines(rest,value)
def submittedState(current: State,+value: String) -> State & Unit:
  match current:
    case AuthDialog{title,content,input,+secret,_}:
      (AuthDialog{title,submittedLines(content,Bool.pick(String,secret,String.repeat("•",String.length(value)),value)),input,secret,False{}},Unit{})
    case _: (Waiting{},Unit{})
def submitInput(context: InputSubmission,value: String) -> IO(Unit):
  match context:
    case InputSubmission{state,reply}:
      do IO<Unit>:
        +submitted : String = value
        Ref.modify(State,Unit,state,current => submittedState(current,submitted))
        settle(reply,submitted)
def nonAtomic(_: Words.Source,_: String) -> Bool: False{}
def editedInput(current: State,result: Word.ResultOf(Input.Input)) -> State & Unit:
  match current result:
    case Manual{url,_} Done{input}: (Manual{url,input},Unit{})
    case Prompt{title,message,secret,_} Done{input}: (Prompt{title,message,secret,input},Unit{})
    case AuthDialog{title,content,_,secret,True{}} Done{input}: (AuthDialog{title,content,input,secret,True{}},Unit{})
    case previous _: (previous,Unit{})
def inputPrompt(+state: Ref.Ref<State>,+words: Ref.Ref<Words.Source>,+input: Input.Input,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> IO(Unit):
  do IO<Unit>:
    previous : Words.Source <- Ref.read(Words.Source,words)
    +source : Words.Source <- Words.readyFor(previous,Input.getValue(input))
    Ref.write(Words.Source,words,source)
    result : Word.ResultOf(Input.Input) <- Input.handleInput(~Words.Source,~Word.sourceSegments,~nonAtomic,source,input,bindings,keyboard,data)
    # A submit/cancel callback may already have changed the phase.
    Ref.modify(State,Unit,state,current => editedInput(current,result))
def choiceId(choice: Maybe<&2,Choice>) -> Maybe<&2,String>:
  match choice:
    case None{}: None{}
    case Some{Choice{id,_,_,_}}: Some{id}
def selectedChoice(state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,choice: Maybe<&2,String>) -> IO(Unit):
  match choice:
    case None{}: IO.pure(Unit,Unit{})
    case Some{id}:
      do IO<Unit>:
        Ref.write(State,state,Waiting{})
        settle(reply,id)
def chooseIndex(state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,choices: List<&2,Choice>,index: Nat) -> IO(Unit):
  selectedChoice(state,reply,choiceId(List.get(&2,Choice,choices,index)))
def menuChanged(state: Ref.Ref<State>,menu: Menu,title: String,+all: List<&2,Choice>,selected: Nat,+query: String) -> IO(Unit):
  Ref.write(State,state,Choosing{menu,title,all,filtered(all,query),selected,query})
def moveChoice(state: Ref.Ref<State>,menu: Menu,title: String,all: List<&2,Choice>,visible: List<&2,Choice>,+selected: Nat,query: String,up: Bool) -> IO(Unit):
  +count = List.length(&2,Choice,visible)
  +next = Bool.pick(Nat,up,selected - 1n,Nat.min(selected + 1n,count - 1n))
  menuChanged(state,menu,title,all,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),query)
def searchable(menu: Menu) -> Bool:
  match menu:
    case Method{}: False{}
    case AuthSelect{}: False{}
    case _: True{}
def methodKey(menu: Menu,data: String,key: String) -> Bool:
  match menu:
    case Method{}: String.eq(data,key)
    case _: False{}
def menuInput(+state: Ref.Ref<State>,reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+menu: Menu,+title: String,+all: List<&2,Choice>,+visible: List<&2,Choice>,+selected: Nat,+query: String,+data: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.up") || methodKey(menu,data,"k"),
    _ => moveChoice(state,menu,title,all,visible,selected,query,True{}),
    _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.down") || methodKey(menu,data,"j"),
      _ => moveChoice(state,menu,title,all,visible,selected,query,False{}),
      _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),
        _ => chooseIndex(state,reply,visible,selected),
        _ => Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.editor.deleteCharBackward"),
          _ => menuChanged(state,menu,title,all,0n,withoutLast(query)),
          _ => Bool.pick(Unit -> IO(Unit),printable(data) && searchable(menu),
            _ => menuChanged(state,menu,title,all,0n,query ++ data),
            _ => IO.pure(Unit,Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def receiveCurrent(current: State,+state: Ref.Ref<State>,+reply: Ref.Ref<Maybe<&2,Deferred.Deferred<String>>>,editor: Component.Component,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+cancel: Callback.Callback<Unit,Unit>,words: Ref.Ref<Words.Source>,+data: String) -> IO(Unit):
  match current:
    case Closed{}: Component.handleInput(editor,data)
    case Choosing{menu,title,all,visible,selected,query}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => Callback.call(Unit,Unit,cancel,Unit{}),_ => menuInput(state,reply,bindings,keyboard,menu,title,all,visible,selected,query,data))(Unit{})
    case Manual{url,input}:
      inputPrompt(state,words,input,bindings,keyboard,data)
    case Prompt{title,message,secret,input}:
      inputPrompt(state,words,input,bindings,keyboard,data)
    case AuthDialog{_,_,input,_,True{}}:
      inputPrompt(state,words,input,bindings,keyboard,data)
    case Info{_,_}:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => settle(reply,""),_ => IO.pure(Unit,Unit{}))(Unit{})
    case _:
      Bool.pick(Unit -> IO(Unit),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => do IO<Unit>:
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
        Callback.call(Unit,Unit,cancel,Unit{}),_ => IO.pure(Unit,Unit{}))(Unit{})
def receive(host: Host,data: String) -> IO(Unit):
  match host:
    case Host{+state,reply,editor,_,bindings,keyboard,cancel,words,_}:
      do IO<Unit>:
        current : State <- Ref.read(State,state)
        receiveCurrent(current,state,reply,editor,bindings,keyboard,cancel,words,data)
def editorMouse(editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match editor:
    case Component.Component{_,_,_,Some{callback},_,_,_}: Callback.call(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,callback,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouseCurrent(current: State,editor: Component.Component,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match current:
    case Closed{}: editorMouse(editor,event)
    case _: IO.pure(Maybe<&2,Component.MouseResponse>,None{})
def mouse(host: Host,event: Tui.TuiMouseEvent) -> IO(Maybe<&2,Component.MouseResponse>):
  match host:
    case Host{state,_,editor,_,_,_,_,_,_}:
      do IO<Maybe<&2,Component.MouseResponse>>:
        current : State <- Ref.read(State,state)
        mouseCurrent(current,editor,event)
def invalidate(host: Host,_: Unit) -> IO(Unit):
  match host: case Host{_,_,editor,_,_,_,_,_,_}: Component.invalidate(editor)
def focus(host: Host,value: Bool) -> IO(Unit):
  match host: case Host{_,_,editor,_,_,_,_,_,_}: Component.setFocused(editor,value)
def create(+editor: Component.Component,theme: Ref.Ref<Theme.Theme>,words: Words.Source,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,cancel: Callback.Callback<Unit,Unit>) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<State> <- Ref.new(State,Closed{})
    +reply : Ref.Ref<Maybe<&2,Deferred.Deferred<String>>> <- Ref.new(Maybe<&2,Deferred.Deferred<String>>,None{})
    wordSource : Ref.Ref<Words.Source> <- Ref.new(Words.Source,words)
    +submit : Callback.Callback<String,Unit> <- Callback.create(~InputSubmission,~String,~Unit,~submitInput,InputSubmission{state,reply})
    +host : Host <- IO.pure(Host,Host{state,reply,editor,theme,bindings,keyboard,cancel,wordSource,submit})
    +renderCallback : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Host,~Nat,~List<&2,String>,~draw,host)
    +inputCallback : Callback.Callback<String,Unit> <- Callback.create(~Host,~String,~Unit,~receive,host)
    +mouseCallback : Callback.Callback<Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>> <- Callback.create(~Host,~Tui.TuiMouseEvent,~Maybe<&2,Component.MouseResponse>,~mouse,host)
    +invalidateCallback : Callback.Callback<Unit,Unit> <- Callback.create(~Host,~Unit,~Unit,~invalidate,host)
    +focusCallback : Callback.Callback<Bool,Unit> <- Callback.create(~Host,~Bool,~Unit,~focus,host)
    +component : Component.Component <- IO.pure(Component.Component,Component.Component{Component.id(editor),renderCallback,Some{inputCallback},Some{mouseCallback},invalidateCallback,Some{focusCallback},False{}})
    return Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}
def borrow(owner: Owner) -> Owner & Host & Component.Component:
  match owner:
    case Owner{+host,+component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}: (Owner{host,component,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback},host,component)
def openMenu(host: Host,menu: Menu,title: String,+choices: List<&2,Choice>) -> IO(Deferred.Deferred<String>):
  match host:
    case Host{state,reply,editor,_,_,_,_,_,_}:
      do IO<Deferred.Deferred<String>>:
        +choice : Deferred.Deferred<String> <- Deferred.new(String)
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{choice})
        Component.setFocused(editor,False{})
        Ref.write(State,state,Choosing{menu,title,choices,choices,0n,""})
        return choice
def openChoices(host: Host,title: String,choices: List<&2,Choice>) -> IO(Deferred.Deferred<String>):
  openMenu(host,Generic{},title,choices)
def open(host: Host) -> IO(Deferred.Deferred<String>):
  openMenu(host,Method{},"Select authentication method:",Choice{"oauth","Sign in with an account","","Sign in with an account"} <> Choice{"api_key","Sign in with an API key","","Sign in with an API key"} <> Nil{})
def openOAuth(host: Host) -> IO(Deferred.Deferred<String>):
  openMenu(host,Provider{},"Select provider to configure:",Choice{"openai-codex","OpenAI Codex","","OpenAI Codex openai-codex oauth"} <> Choice{"anthropic","Anthropic (Claude Pro/Max)","","Anthropic anthropic oauth"} <> Nil{})
def openApiKeys(host: Host,choices: List<&2,Choice>) -> IO(Deferred.Deferred<String>):
  openMenu(host,Provider{},"Select provider to configure:",choices)
def openDirect(host: Host) -> IO(Unit):
  match host:
    case Host{state,_,editor,_,_,_,_,_,_}:
      do IO<Unit>:
        Component.setFocused(editor,False{})
        Ref.write(State,state,Waiting{})
def authContent(current: State,title: String) -> State:
  match current:
    case AuthDialog{_,_,_,_,_}: current
    case _: AuthDialog{title,Nil{},Input.new(None{}),False{},False{}}
def infoLinks(links: List<&2,Auth.AuthInfoLink>) -> List<&2,AuthLine>:
  match links:
    case Nil{}: Nil{}
    case Auth.AuthInfoLink{+url,label} <> rest:
      Link{"accent",url,Maybe.default(&2,String,Maybe.map(&2,String,String,text => text ++ ": " ++ url,label),url)} <> infoLinks(rest)
def authorizationLines(+url: String,instructions: Maybe<&2,String>) -> List<&2,AuthLine>:
  Blank{} <> Link{"accent",url,url} <> Link{"dim",url,"Ctrl+click to open"} <>
    Maybe.default(&2,List<&2,AuthLine>,Maybe.map(&2,String,List<&2,AuthLine>,text => Blank{} <> Text{"warning",text} <> Nil{},instructions),Nil{})
def notifiedContent(current: State,event: Auth.AuthEvent) -> State & Unit:
  match current event:
    case AuthDialog{title,_,input,secret,active} Auth.AuthUrlEvent{url,instructions}:
      (AuthDialog{title,authorizationLines(url,instructions),input,secret,active},Unit{})
    case AuthDialog{title,_,input,_,_} Auth.DeviceCodeEvent{code,url,_,_}:
      (AuthDialog{title,List.append(&2,AuthLine,authorizationLines(url,None{}),[Blank{},Text{"warning","Enter code: " ++ code},Blank{},Text{"dim","Waiting for authentication..."},Hint{True{}}]),input,False{},False{}},Unit{})
    case AuthDialog{title,content,input,secret,active} Auth.InfoEvent{message,links}:
      (AuthDialog{title,List.append(&2,AuthLine,content,Blank{} <> Text{"text",message} <> infoLinks(links)),input,secret,active},Unit{})
    case AuthDialog{title,content,input,secret,active} Auth.ProgressEvent{message}:
      (AuthDialog{title,List.append(&2,AuthLine,content,Text{"dim",message} <> Nil{}),input,secret,active},Unit{})
    case _ _: (current,Unit{})
def notified(current: State,title: String,event: Auth.AuthEvent) -> State & Unit:
  match current:
    case Closed{}: (Closed{},Unit{})
    case _: notifiedContent(authContent(current,title),event)
def notify(host: Host,title: String,event: Auth.AuthEvent) -> IO(Unit):
  match host:
    case Host{state,_,_,_,_,_,_,_,_}: Ref.modify(State,Unit,state,current => notified(current,title,event))
def authOptions(options: List<&2,Auth.AuthSelectOption>) -> List<&2,Choice>:
  match options:
    case Nil{}: Nil{}
    case Auth.AuthSelectOption{id,+label,description} <> rest:
      Choice{id,label,"",label} <> authOptions(rest)
def promptedContent(current: State,title: String,message: String,placeholder: Maybe<&2,String>,secret: Bool,+isManual: Bool,cancel: Callback.Callback<Unit,Unit>,submit: Callback.Callback<String,Unit>) -> State:
  match current:
    case AuthDialog{title,content,_,_,_}:
      +example = Maybe.default(&2,List<&2,AuthLine>,Maybe.map(&2,String,List<&2,AuthLine>,text => Text{"dim","e.g., " ++ text} <> Nil{},placeholder),Nil{})
      AuthDialog{title,List.append(&2,AuthLine,content,Blank{} <> Text{Bool.pick(String,isManual,"dim","text"),message} <> List.append(&2,AuthLine,example,[Entered{},Hint{isManual}])),Input.setCallbacks(Input.setFocused(Input.new(None{}),True{}),Some{submit},Some{cancel}),secret,True{}}
    case other: other
def prompted(current: State,+title: String,message: String,placeholder: Maybe<&2,String>,secret: Bool,+isManual: Bool,cancel: Callback.Callback<Unit,Unit>,submit: Callback.Callback<String,Unit>) -> State:
  promptedContent(authContent(current,title),title,message,placeholder,secret,isManual,cancel,submit)
def showAuthContent(+state: Ref.Ref<State>,+title: String,prompt: Auth.AuthPrompt,+cancel: Callback.Callback<Unit,Unit>,+submit: Callback.Callback<String,Unit>) -> IO(Unit):
  match prompt:
    case Auth.SelectPrompt{message,options,_}:
      +choices = authOptions(options)
      Ref.write(State,state,Choosing{AuthSelect{},message,choices,choices,0n,""})
    case Auth.TextPrompt{message,placeholder,_}: Ref.modify(State,Unit,state,current => (prompted(current,title,message,placeholder,False{},False{},cancel,submit),Unit{}))
    case Auth.SecretPrompt{message,placeholder,_}: Ref.modify(State,Unit,state,current => (prompted(current,title,message,placeholder,True{},False{},cancel,submit),Unit{}))
    case Auth.ManualCodePrompt{message,_,_}: Ref.modify(State,Unit,state,current => (prompted(current,title,message,None{},False{},True{},cancel,submit),Unit{}))
def showAuthPrompt(host: Host,title: String,prompt: Auth.AuthPrompt,+answer: Deferred.Deferred<String>) -> IO(Unit):
  match host:
    case Host{state,reply,editor,_,_,_,cancel,_,submit}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{answer})
        Component.setFocused(editor,False{})
        showAuthContent(state,title,prompt,cancel,submit)
def authState(host: Host) -> IO(State):
  match host: case Host{state,_,_,_,_,_,_,_,_}: Ref.read(State,state)
def promptFinished(current: State,previous: Maybe<&2,State>) -> State & Unit:
  match current previous:
    case Closed{} _: (Closed{},Unit{})
    case _ Some{prior}: (prior,Unit{})
    case AuthDialog{title,content,input,secret,_} _: (AuthDialog{title,content,input,secret,False{}},Unit{})
    case other _: (other,Unit{})
def finishAuthPrompt(host: Host,previous: Maybe<&2,State>) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,_,_,_}:
      do IO<Unit>:
        unused : Maybe<&2,Deferred.Deferred<String>> <- Ref.swap(Maybe<&2,Deferred.Deferred<String>>,reply,None{})
        Ref.modify(State,Unit,state,current => promptFinished(current,previous))
# Each observer owns one removable wait. The completion is first-settlement
# arbitration, so a later abort cannot override an already submitted value.
type PromptWatch is Type:
  InputWatch{cancel: Deferred.Cancellation<String>,worker: Chan(Unit)}
  AbortWatch{cancel: Deferred.Cancellation<Abort.AbortReason<Unit>>,worker: Chan(Unit)}
def settleCompletion(completion: Deferred.Deferred<Result<&2,&2,String,String>>,value: Maybe<&2,Result<&2,&2,String,String>>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{result}:
      do IO<Unit>:
        won : Bool <- Deferred.resolve(Result<&2,&2,String,String>,completion,result)
        return Unit{}
def completeInput(ticket: Deferred.Ticket<Maybe<&2,String>>,completion: Deferred.Deferred<Result<&2,&2,String,String>>) -> IO(Unit):
  do IO<Unit>:
    value : Maybe<&2,String> <- Deferred.wait(Maybe<&2,String>,ticket)
    settleCompletion(completion,Maybe.map(&2,String,Result<&2,&2,String,String>,text => Done{text},value))
def completeAbort(ticket: Deferred.Ticket<Maybe<&2,Abort.AbortReason<Unit>>>,completion: Deferred.Deferred<Result<&2,&2,String,String>>) -> IO(Unit):
  do IO<Unit>:
    reason : Maybe<&2,Abort.AbortReason<Unit>> <- Deferred.wait(Maybe<&2,Abort.AbortReason<Unit>>,ticket)
    settleCompletion(completion,Maybe.map(&2,Abort.AbortReason<Unit>,Result<&2,&2,String,String>,_ => Fail{"Login cancelled"},reason))
type PromptRegistration is Type:
  InputRegistration{observation: Deferred.Observation<String>}
  AbortRegistration{observation: Deferred.Observation<Abort.AbortReason<Unit>>}
def watchRegistered(registration: PromptRegistration,completion: Deferred.Deferred<Result<&2,&2,String,String>>) -> IO(PromptWatch):
  match registration:
    case InputRegistration{Deferred.Observation{ticket,cancel}}:
      do IO<PromptWatch>:
        worker : Chan(Unit) <- IO.fork(Unit,completeInput(ticket,completion))
        return InputWatch{cancel,worker}
    case AbortRegistration{Deferred.Observation{ticket,cancel}}:
      do IO<PromptWatch>:
        worker : Chan(Unit) <- IO.fork(Unit,completeAbort(ticket,completion))
        return AbortWatch{cancel,worker}
def watchInput(completion: Deferred.Deferred<Result<&2,&2,String,String>>,answer: Deferred.Deferred<String>) -> IO(PromptWatch):
  do IO<PromptWatch>:
    observation : Deferred.Observation<String> <- Deferred.observe(String,answer)
    watchRegistered(InputRegistration{observation},completion)
def watchAbort(completion: Deferred.Deferred<Result<&2,&2,String,String>>,signal: Abort.AbortSignal<Unit>) -> IO(PromptWatch):
  do IO<PromptWatch>:
    observation : Deferred.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit,signal)
    watchRegistered(AbortRegistration{observation},completion)
def stopWatch(watch: PromptWatch) -> IO(Unit):
  match watch:
    case InputWatch{cancel,worker}:
      do IO<Unit>:
        removed : Bool <- Deferred.cancel(String,cancel)
        IO.join(Unit,worker)
    case AbortWatch{cancel,worker}:
      do IO<Unit>:
        removed : Bool <- Deferred.cancel(Abort.AbortReason<Unit>,cancel)
        IO.join(Unit,worker)
def optionalWatch(completion: Deferred.Deferred<Result<&2,&2,String,String>>,signal: Auth.Signal()) -> IO(Maybe<&1,PromptWatch>):
  match signal:
    case None{}: IO.pure(Maybe<&1,PromptWatch>,None{})
    case Some{signal}:
      do IO<Maybe<&1,PromptWatch>>:
        watcher : PromptWatch <- watchAbort(completion,signal)
        return Some{watcher}
def stopOptional(watch: Maybe<&1,PromptWatch>) -> IO(Unit):
  match watch:
    case None{}: IO.pure(Unit,Unit{})
    case Some{watcher}: stopWatch(watcher)
def awaitAuthActive(answer: Deferred.Deferred<String>,parent: Abort.AbortSignal<Unit>,signal: Auth.Signal()) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    +completion : Deferred.Deferred<Result<&2,&2,String,String>> <- Deferred.new(Result<&2,&2,String,String>)
    input : PromptWatch <- watchInput(completion,answer)
    whole : PromptWatch <- watchAbort(completion,parent)
    prompt : Maybe<&1,PromptWatch> <- optionalWatch(completion,signal)
    result : Result<&2,&2,String,String> <- Deferred.result(Result<&2,&2,String,String>,completion)
    stopWatch(input)
    stopWatch(whole)
    stopOptional(prompt)
    Deferred.dispose(Result<&2,&2,String,String>,completion)
    return result
def promptAborted(signal: Auth.Signal()) -> IO(Bool):
  match signal:
    case None{}: IO.pure(Bool,False{})
    case Some{signal}: Abort.aborted(Unit,signal)
def awaitAuthAnswer(+answer: Deferred.Deferred<String>,+parent: Abort.AbortSignal<Unit>,+signal: Auth.Signal()) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    whole : Bool <- Abort.aborted(Unit,parent)
    prompt : Bool <- promptAborted(signal)
    Bool.pick(Unit -> IO(Result<&2,&2,String,String>),whole || prompt,
      _ => IO.pure(Result<&2,&2,String,String>,Fail{"Login cancelled"}),
      _ => awaitAuthActive(answer,parent,signal))(Unit{})
def showManual(host: Host,url: String,answer: Deferred.Deferred<String>) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,cancel,_,submit}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{answer})
        Ref.write(State,state,Manual{url,Input.setCallbacks(Input.setFocused(Input.new(None{}),True{}),Some{submit},Some{cancel})})
def showPrompt(host: Host,title: String,message: String,secret: Bool,answer: Deferred.Deferred<String>) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,cancel,_,submit}:
      do IO<Unit>:
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{answer})
        Ref.write(State,state,Prompt{title,message,secret,Input.setCallbacks(Input.setFocused(Input.new(None{}),True{}),Some{submit},Some{cancel})})
def openInfo(host: Host,title: String,message: String) -> IO(Deferred.Deferred<String>):
  match host:
    case Host{state,reply,editor,_,_,_,_,_,_}:
      do IO<Deferred.Deferred<String>>:
        +closed : Deferred.Deferred<String> <- Deferred.new(String)
        Ref.write(Maybe<&2,Deferred.Deferred<String>>,reply,Some{closed})
        Component.setFocused(editor,False{})
        Ref.write(State,state,Info{title,message})
        return closed
def waitingAfterManual(current: State) -> State & Unit:
  match current:
    case Closed{}: (Closed{},Unit{})
    case _: (Waiting{},Unit{})
def stopManual(host: Host) -> IO(Unit):
  match host:
    case Host{state,reply,_,_,_,_,_,_,_}:
      do IO<Unit>:
        settle(reply,"")
        Ref.modify(State,Unit,state,waitingAfterManual)
def withCode(current: State,url: String,code: String) -> State & Unit:
  match current:
    case Waiting{}: (Device{url,code},Unit{})
    case _: (current,Unit{})
def showCode(host: Host,url: String,code: String) -> IO(Unit):
  match host: case Host{state,_,_,_,_,_,_,_,_}: Ref.modify(State,Unit,state,current => withCode(current,url,code))
def close(host: Host) -> IO(Unit):
  match host:
    case Host{state,reply,editor,_,_,_,_,_,_}:
      do IO<Unit>:
        settle(reply,"")
        Ref.write(State,state,Closed{})
        Component.setFocused(editor,True{})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{Host{state,reply,_,_,_,_,_,words,submit},_,renderCallback,inputCallback,mouseCallback,invalidateCallback,focusCallback}:
      do IO<Unit>:
        old : State <- Ref.dispose(State,state)
        unused : Words.Source <- Ref.dispose(Words.Source,words)
        Callback.dispose(String,Unit,submit)
        pending : Maybe<&2,Deferred.Deferred<String>> <- Ref.dispose(Maybe<&2,Deferred.Deferred<String>>,reply)
        Callback.dispose(Nat,List<&2,String>,renderCallback)
        Callback.dispose(String,Unit,inputCallback)
        Callback.dispose(Tui.TuiMouseEvent,Maybe<&2,Component.MouseResponse>,mouseCallback)
        Callback.dispose(Unit,Unit,invalidateCallback)
        Callback.dispose(Bool,Unit,focusCallback)
