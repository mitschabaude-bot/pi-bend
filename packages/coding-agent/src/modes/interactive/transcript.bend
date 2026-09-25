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
import ./components/session-info.bend as SessionInfo
import ./components/tool-execution.bend as Tool
import ./viewport.bend as View
import ../../core/messages.bend as CoreMessages
import ../../core/tools/index.bend as Tools

# The transcript owns mounted messages, tools, and transient status lines.
# Agent events replace the active assistant and matching tool snapshots.
type Entry is Type: MessageEntry{owner: Messages.Owner} ToolEntry{owner: Tool.Owner} StatusEntry{owner: Messages.Owner,handle: Messages.Handle}
type ToolLink is Data: ToolLink{id: String,handle: Tool.Handle}
type State is Type:
  State{entries: List<&1,Entry>,tools: List<&2,ToolLink>,active: Maybe<&2,Messages.Handle>,nextId: Nat,view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool,outputPad: Nat}
type Owner is Type: Owner{resource: Serial.Owner<State>,bindings: Ref.Ref<Bindings.KeybindingsManager>}
type Handle is Data: Handle{resource: Serial.Handle<State>,bindings: Ref.Ref<Bindings.KeybindingsManager>}

def create(view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{Nil{},Nil{},None{},100n,view,theme,styles,False{},False{},1n})
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
def statusAppended(pair: Messages.Owner & Component.Component & Messages.Handle,entries: List<&1,Entry>,tools: List<&2,ToolLink>,active: Maybe<&2,Messages.Handle>,id: Nat,+view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool,pad: Nat) -> IO(State & Unit):
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
def mountedBashState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Messages.Handle>:
        View.append(view,component)
        return (State{MessageEntry{owner} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden,pad},handle)
def mountedBash(state: State,pair: Messages.Owner & Component.Component & Messages.Handle) -> IO(State & Messages.Handle):
  match pair:
    case (owner,component,handle): mountedBashState(state,owner,component,handle)
def bashCreated(state: State,command: String,excluded: Bool,bindings: Bindings.KeybindingsManager) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,view,+theme,styles,+expanded,hidden,pad}:
      do IO<State & Messages.Handle>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},Messages.BashBody{Messages.bash(command,excluded,theme,expanded,bindings)})
        mountedBash(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.borrow(owner))
def startBash(handle: Handle,command: String,excluded: Bool) -> IO(Messages.Handle):
  match handle:
    case Handle{resource,bindings}:
      do IO<Messages.Handle>:
        current : Bindings.KeybindingsManager <- Ref.read(Bindings.KeybindingsManager,bindings)
        Serial.run(State,Messages.Handle,resource,state => bashCreated(state,command,excluded,current))
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
def appendUser(state: State,text: String,preceded: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,expanded,+hidden,+pad}:
      append(State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad},Messages.UserBody{Messages.user(text,theme,styles,pad),preceded},False{})
def user(state: State,text: String) -> IO(State & Bool):
  match state:
    case State{Nil{},tools,active,id,view,theme,styles,expanded,hidden,pad}:
      appendUser(State{Nil{},tools,active,id,view,theme,styles,expanded,hidden,pad},text,False{})
    case current: appendUser(current,text,True{})
def findTool(tools: List<&2,ToolLink>,+id: String) -> Maybe<&2,Tool.Handle>:
  match tools:
    case Nil{}: None{}
    case ToolLink{current,handle} <> rest:
      Bool.pick(Maybe<&2,Tool.Handle>,String.eq(current,id),Some{handle},findTool(rest,id))
def mountedOwned(state: State,toolId: String,owned: Tool.Owner,component: Component.Component,handle: Tool.Handle) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{ToolEntry{owned} <> entries,ToolLink{toolId,handle} <> tools,active,id + 1n,view,theme,styles,expanded,hidden,pad},True{})
def mountedBorrowed(state: State,toolId: String,pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(State & Bool):
  match pair:
    case (owned,component,handle): mountedOwned(state,toolId,owned,component,handle)
def mountedTool(state: State,toolId: String,componentId: Nat,value: Tool.ToolExecution) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,nextId,view,theme,styles,+expanded,hidden,pad}:
      do IO<State & Bool>:
        owner : Tool.Owner <- Tool.create(Component.ComponentId{componentId},Tool.setExpanded(value,expanded))
        mountedBorrowed(State{entries,tools,active,nextId,view,theme,styles,expanded,hidden,pad},toolId,Tool.borrow(owner))
# Tool previews highlight code with the Markdown theme's highlightCode.
def codeHighlighter(styles: Markdown.MarkdownTheme) -> Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>:
  match styles: case Markdown.MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,highlight,_}: highlight
def ensureFound(state: State,+id: String,name: String,args: Schema.Value,componentId: Nat,theme: Theme.Theme,highlight: Maybe<&2,Callback.Callback<Markdown.HighlightInput,List<&2,String>>>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateArgs(current,args))
        return (state,True{})
    case None{}: mountedTool(state,id,componentId,Tool.withHighlightCode(Tool.new(name,id,args,theme,Tool.Generic{}),highlight))
def ensureTool(state: State,+id: String,name: String,args: Schema.Value) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,+componentId,view,+theme,+styles,expanded,hidden,pad}:
      ensureFound(State{entries,tools,active,componentId,view,theme,styles,expanded,hidden,pad},id,name,args,componentId,theme,codeHighlighter(styles),findTool(tools,id))
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
def assistantUpdate(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>,+streaming: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,hidden,pad}:
      match active:
        case None{}: IO.pure(State & Bool,(State{entries,tools,None{},id,view,theme,styles,expanded,hidden,pad},False{}))
        case Some{+handle}:
          do IO<State & Bool>:
            body : Messages.Body <- Messages.current(handle)
            Messages.set(handle,updated(Schema.Value,D,body,message,streaming))
            mountCalls(Ai.assistantContent(Schema.Value,D,message),State{entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,streaming,Some{handle},None{}),id,view,theme,styles,expanded,hidden,pad})
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
def updateMessage(-G: Data,-C: Data,state: State,message: Agent.AgentMessage<G,Tools.ToolDetails,C>,streaming: Bool) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantUpdate(G,state,assistant,streaming)
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
def transition(-G: Data,-C: Data,state: State,event: Agent.AgentEvent<G,Tools.ToolDetails,C,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>) -> IO(State & Bool):
  match event:
    case Agent.MessageStart{message}: userMessage(G,C,state,message)
    case Agent.MessageUpdate{message,_}: updateMessage(G,C,state,message,True{})
    case Agent.MessageEnd{message}: updateMessage(G,C,state,message,False{})
    case Agent.ToolExecutionStart{id,name,args}: startedTool(state,id,name,args)
    case Agent.ToolExecutionUpdate{id,name,args,result}: partialTool(state,id,name,args,result)
    case Agent.ToolExecutionEnd{id,_,result,error}: finishedTool(state,id,result,error)
    case _: IO.pure(State & Bool,(state,False{}))
def accept(-G: Data,-C: Data,handle: Handle,event: Agent.AgentEvent<G,Tools.ToolDetails,C,Agent.AgentToolResult<Tools.ToolDetails>,Agent.AgentToolResult<Tools.ToolDetails>>) -> IO(Bool):
  match handle:
    case Handle{resource,_}: Serial.run(State,Bool,resource,state => transition(G,C,state,event))
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
def seedSessionEntry(+handle: Handle,message: Agent.AgentMessage<Unit,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>>) -> IO(Unit):
  match message:
    case Agent.CustomMessage{CoreMessages.BashExecution{value}}: seedHistoricalBash(handle,value)
    case Agent.LlmMessage{+value}:
      do IO<Unit>:
        begun : Bool <- accept(Unit,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageStart{Agent.LlmMessage{value}})
        ended : Bool <- accept(Unit,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageEnd{Agent.LlmMessage{value}})
        return Unit{}
    case Agent.CustomMessage{_}: IO.pure(Unit,Unit{})
def seedSession(+handle: Handle,messages: List<&2,Agent.AgentMessage<Unit,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>>>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit,Unit{})
    case message <> rest:
      do IO<Unit>:
        seedSessionEntry(handle,message)
        seedSession(handle,rest)
def rethemeEntries(entries: List<&1,Entry>,+theme: Theme.Theme) -> IO(List<&1,Entry>):
  match entries:
    case Nil{}: IO.pure(List<&1,Entry>,Nil{})
    case MessageEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme)
        return MessageEntry{kept} <> next
    case ToolEntry{owner} <> rest:
      do IO<List<&1,Entry>>:
        kept : Tool.Owner <- Tool.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme)
        return ToolEntry{kept} <> next
    case StatusEntry{owner,handle} <> rest:
      do IO<List<&1,Entry>>:
        kept : Messages.Owner <- Messages.rethemeOwner(owner,theme)
        next : List<&1,Entry> <- rethemeEntries(rest,theme)
        return StatusEntry{kept,handle} <> next
def rethemed(state: State,+theme: Theme.Theme) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,nextId,view,_,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        next : List<&1,Entry> <- rethemeEntries(entries,theme)
        return (State{next,tools,active,nextId,view,theme,styles,expanded,hidden,pad},Unit{})
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
def toggled(state: State) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,nextId,view,theme,styles,+expanded,hidden,pad}:
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
def changedThinking(state: State,+hidden: Bool) -> IO(State & Unit):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,_,pad}:
      do IO<State & Unit>:
        changed : List<&1,Entry> <- hideThinkingEntries(entries,hidden)
        return (State{changed,tools,active,id,view,theme,styles,expanded,hidden,pad},Unit{})
def setHideThinking(handle: Handle,hidden: Bool) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,state => changedThinking(state,hidden))
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
def cleared(state: State) -> IO(State & Unit):
  match state:
    case State{entries,_,_,nextId,+view,theme,styles,expanded,hidden,pad}:
      do IO<State & Unit>:
        View.clear(view)
        disposeEntries(entries)
        return (State{Nil{},Nil{},None{},nextId,view,theme,styles,expanded,hidden,pad},Unit{})
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource,_}: Serial.run(State,Unit,resource,cleared)
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{entries,_,_,_,_,_,_,_,_,_}: disposeEntries(entries)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource,bindings}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
        old : Bindings.KeybindingsManager <- Ref.dispose(Bindings.KeybindingsManager,bindings)
        return Unit{}
