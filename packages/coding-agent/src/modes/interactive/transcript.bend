import Base
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/record.bend as Record
import ../../../../tui/src/keybindings.bend as Bindings
import ../../../../tui/src/keys.bend as Keys
import ../../core/keybindings.bend as AppKeys
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/markdown.bend as Markdown
import ../../../../runtime/src/callback.bend as Callback
import ./theme/theme.bend as Theme
import ./components/messages.bend as Messages
import ./components/custom-message.bend as Custom
import ../../core/extensions/runner.bend as ExtensionRunner
import ../../core/extensions/types.bend as ExtensionTypes
import ./components/keybinding-hints.bend as Hints
import ./components/session-info.bend as SessionInfo
import ./components/tool-execution.bend as Tool
import ../../core/extensions/tool-render.bend as ToolRender
import ./viewport.bend as View
import ../../core/messages.bend as CoreMessages
import ../../core/skills.bend as Skills
import ../../core/tools/index.bend as Tools
import ../../core/tools/edit.bend as Edit
import ../../core/tools/edit-diff.bend as Edits

# The transcript owns mounted messages, tools, and transient status lines.
# Agent events replace the active assistant and matching tool snapshots.
type Entry is Type: MessageEntry{owner: Messages.Owner} ToolEntry{owner: Tool.Owner} StatusEntry{owner: Messages.Owner,handle: Messages.Handle} CustomEntry{owner: Custom.Owner}
type ToolLink is Data: ToolLink{id: String,handle: Tool.Handle}
type RenderRegistry is Data: RenderRegistry{links: List<&2,ToolLink>,context: Maybe<&2,Tool.ToolContext>,extensions: Maybe<&2,ExtensionRunner.ExtensionRunner>}
type State is Type:
  State{entries: List<&1,Entry>,tools: RenderRegistry,active: Maybe<&2,Messages.Handle>,nextId: Nat,view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool,outputPad: Nat}
type Owner is Type: Owner{resource: Serial.Owner<State>,bindings: Ref.Ref<Bindings.KeybindingsManager>}
type Handle is Data: Handle{resource: Serial.Handle<State>,bindings: Ref.Ref<Bindings.KeybindingsManager>}

def create(view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{Nil{},RenderRegistry{Nil{},None{},None{}},None{},100n,view,theme,styles,False{},False{},1n})
    bindings : Ref.Ref<Bindings.KeybindingsManager> <- Ref.new(Bindings.KeybindingsManager,Bindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux",None{},None{}}),Record.new(List<&2,Keys.KeyId>)))
    return Owner{resource,bindings}
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>,+bindings: Ref.Ref<Bindings.KeybindingsManager>) -> Owner & Handle:
  match pair:
    case (resource,handle): (Owner{resource,bindings},Handle{handle,bindings})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource,+bindings}: borrowed(Serial.borrow(State,resource),bindings)
def setBindings(handle: Handle,bindings: Bindings.KeybindingsManager) -> IO(Unit):
  match handle: case Handle{_,target}: Ref.write(Bindings.KeybindingsManager,target,bindings)
def insertedState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,_,id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{MessageEntry{owner} <> entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,assistant,Some{handle},None{}),id + 1n,view,theme,styles,expanded,hidden,pad},True{})
def inserted(state: State,pair: Messages.Owner & Component.Component & Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match pair:
    case (owner,component,handle): insertedState(state,owner,component,handle,assistant)
def append(state: State,body: Messages.Body,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,view,theme,styles,expanded,hidden,pad}:
      do IO<State & Bool>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},body)
        inserted(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.borrow(owner),assistant)
def statusAppended(pair: Messages.Owner & Component.Component & Messages.Handle,entries: List<&1,Entry>,tools: RenderRegistry,active: Maybe<&2,Messages.Handle>,id: Nat,+view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool,pad: Nat) -> IO(State & Unit):
  match pair:
    case (owner,component,handle):
      do IO<State & Unit>:
        View.append(view,component)
        return (State{StatusEntry{owner,handle} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden,pad},Unit{})
def statusChanged(state: State,+message: String) -> IO(State & Unit):
  match state:
    case State{StatusEntry{owner,+handle} <> rest,tools,active,+id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        Messages.set(handle,Messages.StatusBody{message,theme})
        return (State{StatusEntry{owner,handle} <> rest,tools,active,id,view,theme,styles,expanded,hidden,pad},Unit{})
    case State{entries,tools,active,+id,+view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},Messages.StatusBody{message,theme})
        statusAppended(Messages.borrow(owner),entries,tools,active,id,view,theme,styles,expanded,hidden,pad)
def status(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => statusChanged(state,message))
def appendedUnit(pair: State & Bool) -> State & Unit:
  match pair:
    case (next,_): (next,Unit{})
def newSessionAppended(state: State) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.NewSessionBody{theme},False{})
        return appendedUnit(pair)
def sessionInfoAppended(state: State,info: SessionInfo.SessionInfo) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.SessionInfoBody{info,theme},False{})
        return appendedUnit(pair)
def sessionInfo(handle: Handle,info: SessionInfo.SessionInfo) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => sessionInfoAppended(state,info))
def newSession(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,newSessionAppended)
def noticeAppended(state: State,text: String) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.StatusBody{text,theme},False{})
        return appendedUnit(pair)
# A dim transcript notice (upstream's Spacer and dim Text) that stays in the
# chat; unlike `status`, a later status does not replace it.
def notice(handle: Handle,text: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => noticeAppended(state,text))
def spacerAppended(state: State) -> IO(State & Unit):
  do IO<State & Unit>:
    pair : State & Bool <- append(state,Messages.SpacerBody{},False{})
    return appendedUnit(pair)
def spacer(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,spacerAppended)
def errorAppended(state: State,message: String) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.ErrorBody{message,theme},False{})
        return appendedUnit(pair)
def showError(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => errorAppended(state,message))
def warningAppended(state: State,message: String,label: Bool) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.WarningBody{message,theme,label},False{})
        return appendedUnit(pair)
def showWarning(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => warningAppended(state,message,True{}))
def warningNotice(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => warningAppended(state,message,False{}))
def showProjectTrustWarning(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => warningAppended(state,message,False{}))
def managedAppended(state: State,message: String,warning: Bool,first: Bool) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.ManagedBody{message,theme,warning,first},False{})
        return appendedUnit(pair)
def managedStatus(handle: Handle,message: String,warning: Bool,first: Bool) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => managedAppended(state,message,warning,first))
# upstream adds a Spacer before the startup notice only after other chat content.
def changelogBlock(value: Messages.Changelog,spaced: Bool) -> Messages.Changelog:
  match value:
    case Messages.WhatsNew{markdown,_}: Messages.WhatsNew{markdown,spaced}
    case Messages.UpdatedTo{version,_}: Messages.UpdatedTo{version,spaced}
    case full: full
def changelogAppended(state: State,value: Messages.Changelog) -> IO(State & Unit):
  match state:
    case State{Nil{},tools,active,id,view,+theme,+styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{Nil{},tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.ChangelogBody{changelogBlock(value,False{}),theme,styles},False{})
        return appendedUnit(pair)
    case State{entries,tools,active,id,view,+theme,+styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.ChangelogBody{changelogBlock(value,True{}),theme,styles},False{})
        return appendedUnit(pair)
def changelog(handle: Handle,value: Messages.Changelog) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => changelogAppended(state,value))
def hotkeysAppended(state: State,markdown: String) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.HotkeysBody{markdown,theme,styles},False{})
        return appendedUnit(pair)
def hotkeys(handle: Handle,markdown: String) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => hotkeysAppended(state,markdown))
def mountedBashState(state: State,owner: Messages.Owner,+component: Component.Component,handle: Messages.Handle,deferred: Bool) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Messages.Handle>:
        Bool.pick(Unit -> IO(Unit),deferred,_ => View.appendPending(view,component),_ => View.append(view,component))(Unit{})
        return (State{MessageEntry{owner} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden,pad},handle)
def mountedBash(state: State,pair: Messages.Owner & Component.Component & Messages.Handle,deferred: Bool) -> IO(State & Messages.Handle):
  match pair:
    case (owner,component,handle): mountedBashState(state,owner,component,handle,deferred)
def bashCreated(state: State,command: String,excluded: Bool,bindings: Bindings.KeybindingsManager,deferred: Bool) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,view,+theme,styles,+expanded,hidden,pad}:
      do IO<State & Messages.Handle>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},Messages.BashBody{Messages.bash(command,excluded,theme,expanded,bindings)})
        mountedBash(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.borrow(owner),deferred)
def startBashWhile(handle: Handle,command: String,excluded: Bool,deferred: Bool) -> IO(Messages.Handle):
  match handle:
    case Handle{resource,bindings}:
      do IO<Messages.Handle>:
        current : Bindings.KeybindingsManager <- Ref.read(Bindings.KeybindingsManager,bindings)
        Serial.run(State,Messages.Handle,resource,state => bashCreated(state,command,excluded,current,deferred))
def startBash(handle: Handle,command: String,excluded: Bool) -> IO(Messages.Handle): startBashWhile(handle,command,excluded,False{})
def pendingFlushed(state: State) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        View.flushPending(view)
        return (State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Unit{})
def flushPending(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,pendingFlushed)
def bashAppended(body: Messages.Body,delta: String) -> Messages.Body:
  match body:
    case Messages.BashBody{state}: Messages.BashBody{Messages.appendBash(state,delta)}
    case other: other
def appendBash(+handle: Messages.Handle,delta: String) -> IO(Unit):
  do IO<Unit>:
    body : Messages.Body <- Messages.current(handle)
    Messages.set(handle,bashAppended(body,delta))
def bashFinished(body: Messages.Body,output: String,exitCode: Maybe<&2,U32>,cancelled: Bool,truncated: Bool,path: Maybe<&2,String>) -> Messages.Body:
  match body:
    case Messages.BashBody{state}: Messages.BashBody{Messages.completeBash(state,output,exitCode,cancelled,truncated,path)}
    case other: other
def finishBash(+handle: Messages.Handle,output: String,exitCode: Maybe<&2,U32>,cancelled: Bool,truncated: Bool,path: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    body : Messages.Body <- Messages.current(handle)
    Messages.set(handle,bashFinished(body,output,exitCode,cancelled,truncated,path))
def bashFailed(body: Messages.Body) -> Messages.Body:
  match body:
    case Messages.BashBody{state}: Messages.BashBody{Messages.failBash(state)}
    case other: other
def failBash(+handle: Messages.Handle) -> IO(Unit):
  do IO<Unit>:
    body : Messages.Body <- Messages.current(handle)
    Messages.set(handle,bashFailed(body))
def noteAppended(state: State,label: String,brief: Maybe<&2,String>,content: String,hint: String) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,+expanded,hidden,pad}:
      do IO<State & Unit>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.NoteBody{Messages.Note{label,brief,content,expanded,theme,styles,hint}},False{})
        return appendedUnit(pair)
def note(handle: Handle,label: String,brief: Maybe<&2,String>,content: String) -> IO(Unit):
  match handle:
    case Handle{resource,bindings}:
      do IO<Unit>:
        keys : Bindings.KeybindingsManager <- Ref.read(Bindings.KeybindingsManager,bindings)
        Serial.run(State,Unit,resource,state => noteAppended(state,label,brief,content,Hints.keyText(keys,"app.tools.expand")))
def appendUser(state: State,text: String,preceded: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,expanded,+hidden,+pad}:
      append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.UserBody{Messages.user(text,theme,styles,pad),preceded},False{})
def plainUser(state: State,text: String) -> IO(State & Bool):
  match state:
    case State{Nil{},tools,active,id,view,theme,styles,expanded,hidden,pad}:
      appendUser(State{Nil{},tools,active,id,view,theme,styles,expanded,hidden,pad},text,False{})
    case current: appendUser(current,text,True{})
def skillVisible(pair: State & Unit,userMessage: Maybe<&2,String>) -> IO(State & Bool):
  match pair userMessage:
    case (next,_) None{}: IO.pure(State & Bool,(next,True{}))
    case (next,_) Some{text}: appendUser(next,text,True{})
def parsedUser(state: State,text: String,parsed: Maybe<&2,Skills.ParsedSkillBlock>) -> IO(State & Bool):
  match parsed:
    case None{}: plainUser(state,text)
    case Some{Skills.ParsedSkillBlock{+name,_,content,userMessage}}:
      do IO<State & Bool>:
        pair : State & Unit <- noteAppended(state,"skill",Some{name},"**" ++ name ++ "**\n\n" ++ content,"ctrl+o")
        skillVisible(pair,userMessage)
def user(state: State,+text: String) -> IO(State & Bool):
  parsedUser(state,text,Skills.parseSkillBlock(text))
def findToolLink(tools: List<&2,ToolLink>,+id: String) -> Maybe<&2,Tool.Handle>:
  match tools:
    case Nil{}: None{}
    case ToolLink{current,handle} <> rest:
      Bool.pick(Unit -> Maybe<&2,Tool.Handle>,String.eq(current,id),_ => Some{handle},_ => findToolLink(rest,id))(Unit{})
def findTool(registry: RenderRegistry,id: String) -> Maybe<&2,Tool.Handle>:
  match registry: case RenderRegistry{links,_,_}: findToolLink(links,id)
def linkedTool(registry: RenderRegistry,id: String,handle: Tool.Handle) -> RenderRegistry:
  match registry: case RenderRegistry{links,context,extensions}: RenderRegistry{ToolLink{id,handle} <> links,context,extensions}
def toolContext(registry: RenderRegistry) -> Maybe<&2,Tool.ToolContext>:
  match registry: case RenderRegistry{_,context,_}: context
def mountedOwned(state: State,toolId: String,owned: Tool.Owner,component: Component.Component,handle: Tool.Handle) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{ToolEntry{owned} <> entries,linkedTool(tools,toolId,handle),active,id + 1n,view,theme,styles,expanded,hidden,pad},True{})
def mountedBorrowed(state: State,toolId: String,pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(State & Bool):
  match pair:
    case (owned,component,handle): mountedOwned(state,toolId,owned,component,handle)
def mountedTool(state: State,toolId: String,componentId: Nat,value: Tool.ToolExecution) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,nextId,view,theme,styles,+expanded,hidden,pad}:
      do IO<State & Bool>:
        owner : Tool.Owner <- Tool.createWithContext(Component.ComponentId{componentId},Tool.configuredImages(Tool.setExpanded(value,expanded),toolContext(tools)),toolContext(tools))
        mountedBorrowed(State{entries,tools,active,nextId,view,theme,styles,expanded,hidden,pad},toolId,Tool.borrow(owner))
# Tool previews highlight code with the Markdown theme's highlightCode.
def codeHighlighter(styles: Markdown.MarkdownTheme) -> Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>:
  match styles: case Markdown.MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,highlight,_,_}: highlight
def styledShell(style: ExtensionTypes.ToolRenderShell,call: Maybe<&2,ToolRender.Renderer()>,result: Maybe<&2,ToolRender.Renderer()>) -> Tool.Shell:
  match style:
    case ExtensionTypes.DefaultShell{}: Tool.Boxed{call,result}
    case ExtensionTypes.SelfShell{}: Tool.SelfRendered{call,result}
    case ExtensionTypes.NativeBuiltin{name}: Tool.NativeBuiltin{name}
def registeredShellIn(registered: List<&2,ExtensionTypes.RegisteredTool>,+name: String,selected: Tool.Shell) -> Tool.Shell:
  match registered:
    case Nil{}: selected
    case ExtensionTypes.RegisteredTool{ExtensionTypes.ToolDefinition{toolName,_,_,_,_,_,_,_,_,style,call,result,_},_} <> +rest:
      Bool.pick(Unit -> Tool.Shell,String.eq(toolName,name),
        _ => registeredShellIn(rest,name,styledShell(style,call,result)),
        _ => registeredShellIn(rest,name,selected))(Unit{})
def registeredShell(registered: List<&2,ExtensionTypes.RegisteredTool>,name: String) -> Tool.Shell:
  registeredShellIn(registered,name,Tool.Generic{})
def shellOfExtensions(extensions: Maybe<&2,ExtensionRunner.ExtensionRunner>,+name: String) -> IO(Tool.Shell):
  match extensions:
    case None{}: IO.pure(Tool.Shell,Tool.Generic{})
    case Some{runner}:
      do IO<Tool.Shell>:
        registered : List<&2,ExtensionTypes.RegisteredTool> <- ExtensionRunner.getAllRegisteredTools(runner)
        return registeredShell(registered,name)
def shellFor(registry: RenderRegistry,+name: String) -> IO(Tool.Shell):
  match registry:
    case RenderRegistry{_,_,extensions}: shellOfExtensions(extensions,name)
def mountRegistered(state: State,+id: String,+name: String,args: Schema.Value,componentId: Nat,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,nextId,view,+theme,styles,expanded,hidden,pad}:
      do IO<State & Bool>:
        shell : Tool.Shell <- shellFor(tools,name)
        mountedTool(State{entries,tools,active,nextId,view,theme,styles,expanded,hidden,pad},id,componentId,Tool.withHighlightCode(Tool.new(name,id,args,theme,shell),highlight))
def ensureFound(state: State,+id: String,+name: String,args: Schema.Value,componentId: Nat,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateArgs(current,args))
        return (state,True{})
    case None{}: mountRegistered(state,id,name,args,componentId,highlight)
def ensureTool(state: State,+id: String,name: String,args: Schema.Value) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,+componentId,view,+theme,+styles,expanded,hidden,pad}:
      ensureFound(State{entries,tools,active,componentId,view,theme,styles,expanded,hidden,pad},id,name,args,componentId,codeHighlighter(styles),findTool(tools,id))
def stateOf(pair: State & Bool) -> State:
  match pair: case (next,_): next
def mountCalls(content: List<&2,Ai.AssistantContent<Schema.Value>>,state: State) -> IO(State & Bool):
  match content:
    case Nil{}: IO.pure(State & Bool,(state,True{}))
    case Ai.AssistantToolCall{Ai.ToolCall{id,name,args,_,_}} <> rest:
      do IO<State & Bool>:
        pair : State & Bool <- ensureTool(state,id,name,args)
        mountCalls(rest,stateOf(pair))
    case _ <> rest: mountCalls(rest,state)
def startedCalls(-D: Data,pair: State & Bool,message: Ai.AssistantMessage<Schema.Value,D>) -> IO(State & Bool):
  match pair: case (next,_): mountCalls(Ai.assistantContent(Schema.Value,D,message),next)
def assistantStart(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,expanded,+hidden,+pad}:
      +snapshot = Messages.updateFromAi(Schema.Value,D,Messages.assistant(Nil{},theme,styles,pad),message,True{})
      do IO<State & Bool>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.AssistantBody{Messages.setHideThinkingBlock(snapshot,hidden)},True{})
        startedCalls(D,pair,message)
def updated(-A: Data,-D: Data,body: Messages.Body,message: Ai.AssistantMessage<A,D>,streaming: Bool) -> Messages.Body:
  match body:
    case Messages.AssistantBody{value}: Messages.AssistantBody{Messages.updateFromAi(A,D,value,message,streaming)}
    case value: value
def finalizeToolValue(handle: Tool.Handle,current: Tool.ToolExecution,failure: Maybe<&2,String>) -> IO(Unit):
  match failure:
    case None{}: Tool.set(handle,Tool.setArgsComplete(current))
    case Some{message}: Tool.set(handle,Tool.updateResult(current,ToolRender.ToolResult{Ai.TextImageText{Ai.TextContent{message,None{}}} <> Nil{},True{},None{}},False{}))
def finalizeTool(handle: Maybe<&2,Tool.Handle>,failure: Maybe<&2,String>) -> IO(Unit):
  match handle:
    case None{}: IO.pure(Unit,Unit{})
    case Some{+ready}:
      do IO<Unit>:
        current : Tool.ToolExecution <- Tool.current(ready)
        finalizeToolValue(ready,current,failure)
def finalizeCalls(content: List<&2,Ai.AssistantContent<Schema.Value>>,+tools: RenderRegistry,+failure: Maybe<&2,String>) -> IO(Unit):
  match content:
    case Nil{}: IO.pure(Unit,Unit{})
    case Ai.AssistantToolCall{Ai.ToolCall{id,_,_,_,_}} <> rest:
      do IO<Unit>:
        finalizeTool(findTool(tools,id),failure)
        finalizeCalls(rest,tools,failure)
    case _ <> rest: finalizeCalls(rest,tools,failure)
def abortLabel(attempt: Nat) -> String:
  match attempt:
    case Zero{}: "Operation aborted"
    case Succ{+rest}: "Aborted after " ++ Nat.show(Succ{rest}) ++ " retry attempt" ++ Bool.pick(String,Nat.is_eq(rest,0n),"","s")
def completedAssistant(-D: Data,message: Ai.AssistantMessage<Schema.Value,D>,liveRetry: Maybe<&2,Nat>,streaming: Bool) -> Ai.AssistantMessage<Schema.Value,D>:
  match message liveRetry streaming:
    case Ai.AssistantMessage{content,api,provider,model,responseModel,responseId,thinking,diagnostics,usage,Ai.Aborted{},deferred,_,raw,endTurn,timestamp} Some{attempt} False{}:
      Ai.AssistantMessage{content,api,provider,model,responseModel,responseId,thinking,diagnostics,usage,Ai.Aborted{},deferred,Some{abortLabel(attempt)},raw,endTurn,timestamp}
    case _ _ _: message
def toolFailure(reason: Ai.StopReason,message: Maybe<&2,String>,liveRetry: Maybe<&2,Nat>) -> Maybe<&2,String>:
  match reason:
    case Ai.Error{}:
      +text = {Maybe.default(&2,String,message,"Error"): String}
      Some{Bool.pick(String,String.is_empty(text),"Error",text)}
    case Ai.Aborted{}: Some{abortLabel(Maybe.default(&2,Nat,liveRetry,0n))}
    case _: None{}
def finalizedCalls(pair: State & Bool,content: List<&2,Ai.AssistantContent<Schema.Value>>,failure: Maybe<&2,String>) -> IO(State & Bool):
  match pair:
    case (State{entries,+tools,active,id,view,theme,styles,expanded,hidden,pad},changed):
      do IO<State & Bool>:
        finalizeCalls(content,tools,failure)
        return (State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},changed)
def finishedMessageCalls(pair: State & Bool,content: List<&2,Ai.AssistantContent<Schema.Value>>,failure: Maybe<&2,String>,streaming: Bool) -> IO(State & Bool):
  match streaming:
    case True{}: IO.pure(State & Bool,pair)
    case False{}: finalizedCalls(pair,content,failure)
def mountedMessageCalls(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>,streaming: Bool,liveRetry: Maybe<&2,Nat>) -> IO(State & Bool):
  do IO<State & Bool>:
    +content : List<&2,Ai.AssistantContent<Schema.Value>> = Ai.assistantContent(Schema.Value,D,message)
    pair : State & Bool <- mountCalls(content,state)
    finishedMessageCalls(pair,content,toolFailure(Ai.assistantStopReason(Schema.Value,D,message),Ai.assistantErrorMessage(Schema.Value,D,message),liveRetry),streaming)
def assistantUpdate(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>,+streaming: Bool,+liveRetry: Maybe<&2,Nat>) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad}:
      match active:
        case None{}: IO.pure(State & Bool,(State{entries,tools,None{},id,view,theme,styles,expanded,hidden,pad},False{}))
        case Some{+handle}:
          do IO<State & Bool>:
            Messages.update(handle,body => updated(Schema.Value,D,body,completedAssistant(D,message,liveRetry,streaming),streaming))
            mountedMessageCalls(D,State{entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,streaming,Some{handle},None{}),id,view,theme,styles,expanded,hidden,pad},message,streaming,liveRetry)
def blocksText(blocks: List<&2,Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: text ++ blocksText(rest)
    case _ <> rest: blocksText(rest)
def agentDetails(result: Agent.AgentToolResult<Tools.ToolDetails>) -> Maybe<&2,Tools.ToolDetails>:
  match result: case Agent.AgentToolResult{_,details,_,_}: details
def historicalDetails(message: Ai.ToolResultMessage<Tools.ToolDetails>) -> Maybe<&2,Tools.ToolDetails>:
  match message:
    case Ai.ToolResultMessage{_,name,_,details,_,_,_}:
      Maybe.map(&2,Tools.ToolDetails,Tools.ToolDetails,value => Tools.restoreDetails(name,value),details)
def historicalFound(state: State,+message: Ai.ToolResultMessage<Tools.ToolDetails>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAiResult(Tools.ToolDetails,current,message,historicalDetails(message)))
        return (state,True{})
def historicalTool(state: State,+message: Ai.ToolResultMessage<Tools.ToolDetails>) -> IO(State & Bool):
  match state message:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden,pad} Ai.ToolResultMessage{id,_,_,_,_,_,_}:
      historicalFound(State{entries,tools,active,next,view,theme,styles,expanded,hidden,pad},message,findTool(tools,id))
def userMessage(-G: Data,-C: Data,state: State,message: Agent.AgentMessage<G,Tools.ToolDetails,C>) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},_}}}: user(state,text)
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks},_}}}: user(state,blocksText(blocks))
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantStart(G,state,assistant)
    case Agent.LlmMessage{Ai.ToolResult{result}}: historicalTool(state,result)
    case _: IO.pure(State & Bool,(state,False{}))
def updateMessage(-G: Data,-C: Data,state: State,message: Agent.AgentMessage<G,Tools.ToolDetails,C>,streaming: Bool,liveRetry: Maybe<&2,Nat>) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantUpdate(G,state,assistant,streaming,liveRetry)
    case _: IO.pure(State & Bool,(state,False{}))
def beginFound(state: State,args: Schema.Value,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        Tool.executionBegan(handle)
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.markExecutionStarted(Tool.setArgsComplete(Tool.updateArgs(current,args))))
        return (state,True{})
def beginState(state: State,id: String,args: Schema.Value) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden,pad}:
      beginFound(State{entries,tools,active,next,view,theme,styles,expanded,hidden,pad},args,findTool(tools,id))
def begunPair(pair: State & Bool,id: String,args: Schema.Value) -> IO(State & Bool):
  match pair: case (next,_): beginState(next,id,args)
def startedTool(state: State,+id: String,name: String,+args: Schema.Value) -> IO(State & Bool):
  do IO<State & Bool>:
    pair : State & Bool <- ensureTool(state,id,name,args)
    begunPair(pair,id,args)
def partialFound(state: State,+result: Agent.AgentToolResult<Tools.ToolDetails>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAgent(Tools.ToolDetails,current,result,agentDetails(result),False{},True{}))
        return (state,True{})
def partialState(state: State,id: String,result: Agent.AgentToolResult<Tools.ToolDetails>) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden,pad}:
      partialFound(State{entries,tools,active,next,view,theme,styles,expanded,hidden,pad},result,findTool(tools,id))
def partialPair(pair: State & Bool,id: String,result: Agent.AgentToolResult<Tools.ToolDetails>) -> IO(State & Bool):
  match pair: case (next,_): partialState(next,id,result)
def partialTool(state: State,+id: String,name: String,args: Schema.Value,result: Agent.AgentToolResult<Tools.ToolDetails>) -> IO(State & Bool):
  do IO<State & Bool>:
    pair : State & Bool <- startedTool(state,id,name,args)
    partialPair(pair,id,result)
def finishedFound(state: State,+result: Agent.AgentToolResult<Tools.ToolDetails>,error: Bool,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAgent(Tools.ToolDetails,Tool.markExecutionStarted(current),result,agentDetails(result),error,False{}))
        return (state,True{})
def finishedTool(state: State,id: String,result: Agent.AgentToolResult<Tools.ToolDetails>,error: Bool) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden,pad}:
      finishedFound(State{entries,tools,active,next,view,theme,styles,expanded,hidden,pad},result,error,findTool(tools,id))
def transition(-G: Data,-C: Data,state: State,+liveRetry: Maybe<&2,Nat>,event: Agent.AgentEvent<G,Tools.ToolDetails,C,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>) -> IO(State & Bool):
  match event:
    case Agent.MessageStart{message}: userMessage(G,C,state,message)
    case Agent.MessageUpdate{message,_}: updateMessage(G,C,state,message,True{},liveRetry)
    case Agent.MessageEnd{message}: updateMessage(G,C,state,message,False{},liveRetry)
    case Agent.ToolExecutionStart{id,name,args}: startedTool(state,id,name,args)
    case Agent.ToolExecutionUpdate{id,name,args,result}: partialTool(state,id,name,args,result)
    case Agent.ToolExecutionEnd{id,_,result,error}: finishedTool(state,id,result,error)
    case _: IO.pure(State & Bool,(state,False{}))
def acceptWithRetry(-G: Data,-C: Data,handle: Handle,liveRetry: Maybe<&2,Nat>,event: Agent.AgentEvent<G,Tools.ToolDetails,C,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>) -> IO(Bool):
  match handle:
    case Handle{resource,_}: Serial.run(State,Bool,resource,state => transition(G,C,state,liveRetry,event))
# None replays stored messages; Some carries the live session retry context.
def accept(-G: Data,-C: Data,handle: Handle,event: Agent.AgentEvent<G,Tools.ToolDetails,C,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>) -> IO(Bool):
  acceptWithRetry(G,C,handle,None{},event)
def seed(-G: Data,-C: Data,+handle: Handle,messages: List<&2,Agent.AgentMessage<G,Tools.ToolDetails,C>>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit,Unit{})
    case +message <> rest:
      do IO<Unit>:
        begun : Bool <- accept(G,C,handle,Agent.MessageStart{message})
        ended : Bool <- accept(G,C,handle,Agent.MessageEnd{message})
        seed(G,C,handle,rest)
def seedHistoricalBash(handle: Handle,value: CoreMessages.BashExecutionMessage) -> IO(Unit):
  match value:
    case CoreMessages.BashExecutionMessage{command,output,exitCode,cancelled,truncated,path,_,excluded}:
      do IO<Unit>:
        bash : Messages.Handle <- startBash(handle,command,Maybe.default(&2,Bool,excluded,False{}))
        finishBash(bash,output,exitCode,cancelled,truncated,path)
def groupedDigits(input: String,+count: Nat,acc: String) -> String:
  match input:
    case SNil{}: acc
    case SCon{digit,rest}:
      +separator = Bool.pick(String,Nat.is_eq(count,3n),",","")
      groupedDigits(rest,Bool.pick(Nat,Nat.is_eq(count,3n),1n,count + 1n),SCon{digit,separator ++ acc})
def grouped(value: Nat) -> String: groupedDigits(String.reverse(Nat.show(value)),0n,"")
def extensionsConfigured(state: State, extensions: Maybe<&2,ExtensionRunner.ExtensionRunner>) -> IO(State & Unit):
  match state:
    case State{entries,RenderRegistry{links,context,_},active,id,view,theme,styles,expanded,hidden,pad}:
      IO.pure(State & Unit,(State{entries,RenderRegistry{links,context,extensions},active,id,view,theme,styles,expanded,hidden,pad},Unit{}))
def setExtensions(handle: Handle, extensions: Maybe<&2,ExtensionRunner.ExtensionRunner>) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => extensionsConfigured(state,extensions))
def extensionsOf(registry: RenderRegistry) -> Maybe<&2,ExtensionRunner.ExtensionRunner>:
  match registry:
    case RenderRegistry{_,_,extensions}: extensions
def rendererFor(runner: Maybe<&2,ExtensionRunner.ExtensionRunner>, customType: String) -> IO(Maybe<&2,ExtensionTypes.MessageRenderer()>):
  match runner:
    case None{}: IO.pure(Maybe<&2,ExtensionTypes.MessageRenderer()>,None{})
    case Some{value}: ExtensionRunner.getMessageRenderer(value,customType)
def customMounted(state: State, pair: Custom.Owner & Component.Component & Custom.Handle) -> IO(State & Unit):
  match state pair:
    case State{entries,tools,active,id,+view,theme,styles,expanded,hidden,pad} Tuple{owner,Tuple{component,_}}:
      do IO<State & Unit>:
        View.append(view,component)
        return (State{CustomEntry{owner} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden,pad},Unit{})
def customAppended(state: State, message: CoreMessages.CustomMessage<Schema.Value>, customType: String) -> IO(State & Unit):
  match state:
    case State{entries,+tools,active,+id,view,+theme,+styles,+expanded,hidden,+pad}:
      do IO<State & Unit>:
        renderer : Maybe<&2,ExtensionTypes.MessageRenderer()> <- rendererFor(extensionsOf(tools),customType)
        owner : Custom.Owner <- Custom.create(Component.ComponentId{id},message,renderer,theme,styles,pad)
        ready : Custom.Owner <- Custom.updateOwner(owner, handle => Custom.setExpanded(handle,expanded))
        customMounted(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Custom.borrow(ready))
def seedCustom(handle: Handle, value: CoreMessages.CustomMessage<Schema.Value>) -> IO(Unit):
  match handle value:
    case Handle{resource,_} CoreMessages.CustomMessage{+customType,content,True{},details,timestamp}:
      Serial.run(State,Unit,resource,state => customAppended(state,CoreMessages.CustomMessage{customType,content,True{},details,timestamp},customType))
    case _ _: IO.pure(Unit,Unit{})
def seedCompaction(handle: Handle,value: CoreMessages.CompactionSummaryMessage) -> IO(Unit):
  match value:
    case CoreMessages.CompactionSummaryMessage{summary,tokens,_}:
      +count = grouped(tokens)
      note(handle,"compaction",Some{"Compacted from " ++ count ++ " tokens"},"**Compacted from " ++ count ++ " tokens**\n\n" ++ summary)
def seedBranch(handle: Handle,value: CoreMessages.BranchSummaryMessage) -> IO(Unit):
  match value:
    case CoreMessages.BranchSummaryMessage{summary,_,_}: note(handle,"branch",Some{"Branch summary"},"**Branch Summary**\n\n" ++ summary)
def seedSessionEntry(+handle: Handle,message: Agent.AgentMessage<Schema.Value,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>>) -> IO(Unit):
  match message:
    case Agent.CustomMessage{CoreMessages.BashExecution{value}}: seedHistoricalBash(handle,value)
    case Agent.CustomMessage{CoreMessages.Custom{value}}: seedCustom(handle,value)
    case Agent.CustomMessage{CoreMessages.CompactionSummary{value}}: seedCompaction(handle,value)
    case Agent.CustomMessage{CoreMessages.BranchSummary{value}}: seedBranch(handle,value)
    case Agent.LlmMessage{+value}:
      do IO<Unit>:
        begun : Bool <- accept(Schema.Value,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageStart{Agent.LlmMessage{value}})
        ended : Bool <- accept(Schema.Value,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageEnd{Agent.LlmMessage{value}})
        return Unit{}
    case Agent.CustomMessage{_}: IO.pure(Unit,Unit{})
def seedSession(+handle: Handle,messages: List<&2,Agent.AgentMessage<Schema.Value,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>>>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit,Unit{})
    case message <> rest:
      do IO<Unit>:
        seedSessionEntry(handle,message)
        seedSession(handle,rest)
def rethemeEntries(entries: List<&1,Entry>,+theme: Theme.Theme,+styles: Markdown.MarkdownTheme) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme,styles)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Tool.Owner <- Tool.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme,styles)
        return ToolEntry{kept} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme,styles)
        return StatusEntry{kept,handle} <> next
    case CustomEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Custom.Owner <- Custom.updateOwner(owner,handle => Custom.setTheme(handle,theme,styles))
        next : List<&1,Entry> <- rethemeEntries(rest,theme,styles)
        return CustomEntry{kept} <> next
def applyTheme(state: State,+theme: Theme.Theme) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,nextId,view,_,+styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        next : List<&1,Entry> <- rethemeEntries(entries,theme,styles)
        return (State{next,tools,active,nextId,view,theme,styles,expanded,hidden,pad},Unit{})
def rethemeWhen(changed: Bool,state: State,theme: Theme.Theme) -> IO(State & Unit):
  match changed:
    case True{}: applyTheme(state,theme)
    case False{}: IO.pure(State & Unit,(state,Unit{}))
# The runner syncs the live theme before every render; entries are rethemed,
# and render again, only when it changed.
def rethemed(state: State,+theme: Theme.Theme) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,nextId,view,+current,styles,expanded,hidden,pad}:
      rethemeWhen(Bool.not(Theme.same(current,theme)),State{entries,tools,active,nextId,view,current,styles,expanded,hidden,pad},theme)
def retheme(handle: Handle,theme: Theme.Theme) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => rethemed(state,theme))
def expandEntries(entries: List<&1,Entry>,+expanded: Bool) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.expandOwner(owner,expanded)
        next : List<&1,Entry> <- expandEntries(rest,expanded)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Tool.Owner <- Tool.expandOwner(owner,expanded)
        next : List<&1,Entry> <- expandEntries(rest,expanded)
        return ToolEntry{kept} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- expandEntries(rest,expanded)
        return StatusEntry{owner,handle} <> next
    case CustomEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Custom.Owner <- Custom.updateOwner(owner,handle => Custom.setExpanded(handle,expanded))
        next : List<&1,Entry> <- expandEntries(rest,expanded)
        return CustomEntry{kept} <> next
def toggled(state: State) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,nextId,view,theme,styles,+expanded,hidden,pad}:
      do IO<State & Bool>:
        +next : Bool <- IO.pure(Bool,Bool.not(expanded))
        changed : List<&1,Entry> <- expandEntries(entries,next)
        return (State{changed,tools,active,nextId,view,theme,styles,next,hidden,pad},next)
def toggleExpanded(handle: Handle) -> IO(Bool):
  match handle:
    case Handle{resource,_}: Serial.run(State,Bool,resource,toggled)
def hideThinkingEntries(entries: List<&1,Entry>,+hidden: Bool) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.hideThinkingOwner(owner,hidden)
        next : List<&1,Entry> <- hideThinkingEntries(rest,hidden)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- hideThinkingEntries(rest,hidden)
        return ToolEntry{owner} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- hideThinkingEntries(rest,hidden)
        return StatusEntry{owner,handle} <> next
    case CustomEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- hideThinkingEntries(rest,hidden)
        return CustomEntry{owner} <> next
def changedThinking(state: State,+hidden: Bool) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,_,pad}:
      do IO<State & Unit>:
        changed : List<&1,Entry> <- hideThinkingEntries(entries,hidden)
        return (State{changed,tools,active,id,view,theme,styles,expanded,hidden,pad},Unit{})
def setHideThinking(handle: Handle,hidden: Bool) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => changedThinking(state,hidden))
def imageEntries(entries: List<&1,Entry>,+enabled: Bool) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Tool.Owner <- Tool.showImagesOwner(owner,enabled)
        next : List<&1,Entry> <- imageEntries(rest,enabled)
        return ToolEntry{kept} <> next
    case entry <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- imageEntries(rest,enabled)
        return entry <> next
def imageContext(context: Maybe<&2,Tool.ToolContext>,enabled: Bool) -> Maybe<&2,Tool.ToolContext>:
  match context:
    case None{}: None{}
    case Some{ready}: Some{Tool.withImageSetting(ready,enabled)}
def imagesChanged(state: State,+enabled: Bool) -> IO(State & Unit):
  match state:
    case State{entries,RenderRegistry{links,context,extensions},active,id,view,theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        changed : List<&1,Entry> <- imageEntries(entries,enabled)
        return (State{changed,RenderRegistry{links,imageContext(context,enabled),extensions},active,id,view,theme,styles,expanded,hidden,pad},Unit{})
def setShowImages(handle: Handle,enabled: Bool) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => imagesChanged(state,enabled))
def padEntries(entries: List<&1,Entry>,+pad: Nat) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.padOwner(owner,pad)
        next : List<&1,Entry> <- padEntries(rest,pad)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- padEntries(rest,pad)
        return ToolEntry{owner} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        next : List<&1,Entry> <- padEntries(rest,pad)
        return StatusEntry{owner,handle} <> next
# upstream ui.invalidate(): components drop their rendered lines.
    case CustomEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Custom.Owner <- Custom.updateOwner(owner,handle => Custom.setOutputPad(handle,pad))
        next : List<&1,Entry> <- padEntries(rest,pad)
        return CustomEntry{kept} <> next
def invalidateEntries(entries: List<&1,Entry>) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.invalidateOwner(owner)
        next : List<&1,Entry> <- invalidateEntries(rest)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Tool.Owner <- Tool.invalidateOwner(owner)
        next : List<&1,Entry> <- invalidateEntries(rest)
        return ToolEntry{kept} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.invalidateOwner(owner)
        next : List<&1,Entry> <- invalidateEntries(rest)
        return StatusEntry{kept,handle} <> next
    case CustomEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Custom.Owner <- Custom.updateOwner(owner,handle => Custom.invalidate(handle,Unit{}))
        next : List<&1,Entry> <- invalidateEntries(rest)
        return CustomEntry{kept} <> next
def invalidated(state: State) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,nextId,view,theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        next : List<&1,Entry> <- invalidateEntries(entries)
        return (State{next,tools,active,nextId,view,theme,styles,expanded,hidden,pad},Unit{})
def invalidate(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,invalidated)
def changedPadding(state: State,+pad: Nat) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,hidden,_}:
      do IO<State & Unit>:
        changed : List<&1,Entry> <- padEntries(entries,pad)
        return (State{changed,tools,active,id,view,theme,styles,expanded,hidden,pad},Unit{})
def setOutputPad(handle: Handle,pad: Nat) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => changedPadding(state,pad))
def disposeEntries(entries: List<&1,Entry>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case MessageEntry{entry} <> rest:
      do IO<Unit>:
        Messages.dispose(entry)
        disposeEntries(rest)
    case ToolEntry{entry} <> rest:
      do IO<Unit>:
        Tool.dispose(entry)
        disposeEntries(rest)
    case StatusEntry{entry,_} <> rest:
      do IO<Unit>:
        Messages.dispose(entry)
        disposeEntries(rest)
    case CustomEntry{owner} <> rest:
      do IO<Unit>:
        Custom.dispose(owner)
        disposeEntries(rest)
def cleared(state: State) -> IO(State & Unit):
  match state:
    case State{entries,RenderRegistry{_,context,extensions},_,nextId,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        View.clear(view)
        disposeEntries(entries)
        return (State{Nil{},RenderRegistry{Nil{},context,extensions},None{},nextId,view,theme,styles,expanded,hidden,pad},Unit{})
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,cleared)
def disposeToolContext(context: Maybe<&2,Tool.ToolContext>) -> IO(Unit):
  match context:
    case None{}: IO.pure(Unit,Unit{})
    case Some{Tool.ToolContext{_,compute,_,_,_,_}}: Callback.dispose(Tool.PreviewRequest,Edits.Preview(),compute)
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{entries,RenderRegistry{_,context,_},_,_,_,_,_,_,_,_}:
      do IO<Unit>:
        disposeEntries(entries)
        disposeToolContext(context)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,bindings}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
        old : Bindings.KeybindingsManager <- Ref.dispose(Bindings.KeybindingsManager,bindings)
        return Unit{}

def contextConfigured(state: State,context: Tool.ToolContext) -> IO(State & Unit):
  match state:
    case State{entries,RenderRegistry{links,None{},extensions},active,id,view,theme,styles,expanded,hidden,pad}:
      IO.pure(State & Unit,(State{entries,RenderRegistry{links,Some{context},extensions},active,id,view,theme,styles,expanded,hidden,pad},Unit{}))
    case _: IO.die(State & Unit,1,"Tool preview context is already configured")
def setToolContext(handle: Handle,context: Tool.ToolContext) -> IO(Unit):
  match handle: case Handle{resource,_}: Serial.run(State,Unit,resource,state => contextConfigured(state,context))

def contextCwd(context: Maybe<&2,Tool.ToolContext>,cwd: String) -> Maybe<&2,Tool.ToolContext>:
  match context:
    case None{}: None{}
    case Some{Tool.ToolContext{_,compute,redraw,read,markdown,images}}: Some{Tool.ToolContext{cwd,compute,redraw,read,markdown,images}}
def contextCwdChanged(state: State,cwd: String) -> IO(State & Unit):
  match state:
    case State{entries,RenderRegistry{links,context,extensions},active,id,view,theme,styles,expanded,hidden,pad}:
      IO.pure(State & Unit,(State{entries,RenderRegistry{links,contextCwd(context,cwd),extensions},active,id,view,theme,styles,expanded,hidden,pad},Unit{}))
def setToolCwd(handle: Handle,cwd: String) -> IO(Unit):
  match handle: case Handle{resource,_}: Serial.run(State,Unit,resource,state => contextCwdChanged(state,cwd))
