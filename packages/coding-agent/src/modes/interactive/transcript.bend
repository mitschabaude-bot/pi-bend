import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/markdown.bend as Markdown
import ./theme/theme.bend as Theme
import ./components/messages.bend as Messages
import ./components/tool-execution.bend as Tool
import ./viewport.bend as View
import ../../core/messages.bend as CoreMessages
import ../../core/tools/index.bend as Tools

# The transcript owns mounted messages, tools, and transient status lines.
# Agent events replace the active assistant and matching tool snapshots.
type Entry is Type: MessageEntry{owner: Messages.Owner} ToolEntry{owner: Tool.Owner} StatusEntry{owner: Messages.Owner,handle: Messages.Handle}
type ToolLink is Data: ToolLink{id: String,handle: Tool.Handle}
type State is Type:
  State{entries: List<&1,Entry>,tools: List<&2,ToolLink>,active: Maybe<&2,Messages.Handle>,nextId: Nat,view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool}
type Owner is Type: Owner{resource: Serial.Owner<State>}
type Handle is Data: Handle{resource: Serial.Handle<State>}

def create(view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{Nil{},Nil{},None{},100n,view,theme,styles,False{},False{}})
    return Owner{resource}
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>) -> Owner & Handle:
  match pair:
    case (resource,handle): (Owner{resource},Handle{handle})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource}: borrowed(Serial.borrow(State,resource))
def insertedState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,_,id,+view,theme,styles,expanded,hidden}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{MessageEntry{owner} <> entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,assistant,Some{handle},None{}),id + 1n,view,theme,styles,expanded,hidden},True{})
def inserted(state: State,pair: Messages.Owner & Component.Component & Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match pair:
    case (owner,component,handle): insertedState(state,owner,component,handle,assistant)
def append(state: State,body: Messages.Body,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,view,theme,styles,expanded,hidden}:
      do IO<State & Bool>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},body)
        inserted(State{entries,tools,active,id,view,theme,styles,expanded,hidden},Messages.borrow(owner),assistant)
def statusAppended(pair: Messages.Owner & Component.Component & Messages.Handle,entries: List<&1,Entry>,tools: List<&2,ToolLink>,active: Maybe<&2,Messages.Handle>,id: Nat,+view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme,expanded: Bool,hidden: Bool) -> IO(State & Unit):
  match pair:
    case (owner,component,handle):
      do IO<State & Unit>:
        View.append(view,component)
        return (State{StatusEntry{owner,handle} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden},Unit{})
def statusChanged(state: State,+message: String) -> IO(State & Unit):
  match state:
    case State{StatusEntry{owner,+handle} <> rest,tools,active,+id,view,+theme,styles,expanded,hidden}:
      do IO<State & Unit>:
        Messages.set(handle,Messages.StatusBody{message,theme})
        return (State{StatusEntry{owner,handle} <> rest,tools,active,id,view,theme,styles,expanded,hidden},Unit{})
    case State{entries,tools,active,+id,+view,+theme,styles,expanded,hidden}:
      do IO<State & Unit>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},Messages.StatusBody{message,theme})
        statusAppended(Messages.borrow(owner),entries,tools,active,id,view,theme,styles,expanded,hidden)
def status(handle: Handle,message: String) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => statusChanged(state,message))
def mountedBashState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden}:
      do IO<State & Messages.Handle>:
        View.append(view,component)
        return (State{MessageEntry{owner} <> entries,tools,active,id + 1n,view,theme,styles,expanded,hidden},handle)
def mountedBash(state: State,pair: Messages.Owner & Component.Component & Messages.Handle) -> IO(State & Messages.Handle):
  match pair:
    case (owner,component,handle): mountedBashState(state,owner,component,handle)
def bashCreated(state: State,command: String,excluded: Bool) -> IO(State & Messages.Handle):
  match state:
    case State{entries,tools,active,+id,view,+theme,styles,+expanded,hidden}:
      do IO<State & Messages.Handle>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},Messages.BashBody{Messages.bash(command,excluded,theme,expanded)})
        mountedBash(State{entries,tools,active,id,view,theme,styles,expanded,hidden},Messages.borrow(owner))
def startBash(handle: Handle,command: String,excluded: Bool) -> IO(Messages.Handle):
  match handle:
    case Handle{resource}: Serial.run(State,Messages.Handle,resource,state => bashCreated(state,command,excluded))
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
def bashFailed(body: Messages.Body,reason: String) -> Messages.Body:
  match body:
    case Messages.BashBody{state}: Messages.BashBody{Messages.failBash(state,reason)}
    case other: other
def failBash(+handle: Messages.Handle,reason: String) -> IO(Unit):
  do IO<Unit>:
    body : Messages.Body <- Messages.current(handle)
    Messages.set(handle,bashFailed(body,reason))
def user(state: State,text: String) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles,expanded,+hidden}:
      append(State{entries,tools,active,id,view,theme,styles,expanded,hidden},Messages.UserBody{Messages.user(text,theme,styles,1n)},False{})
def findTool(tools: List<&2,ToolLink>,+id: String) -> Maybe<&2,Tool.Handle>:
  match tools:
    case Nil{}: None{}
    case ToolLink{current,handle} <> rest:
      Bool.pick(Maybe<&2,Tool.Handle>,String.eq(current,id),Some{handle},findTool(rest,id))
def mountedOwned(state: State,toolId: String,owned: Tool.Owner,component: Component.Component,handle: Tool.Handle) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles,expanded,hidden}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{ToolEntry{owned} <> entries,ToolLink{toolId,handle} <> tools,active,id + 1n,view,theme,styles,expanded,hidden},True{})
def mountedBorrowed(state: State,toolId: String,pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(State & Bool):
  match pair:
    case (owned,component,handle): mountedOwned(state,toolId,owned,component,handle)
def mountedTool(state: State,toolId: String,componentId: Nat,value: Tool.ToolExecution) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,nextId,view,theme,styles,+expanded,hidden}:
      do IO<State & Bool>:
        owner : Tool.Owner <- Tool.create(Component.ComponentId{componentId},Tool.setExpanded(value,expanded))
        mountedBorrowed(State{entries,tools,active,nextId,view,theme,styles,expanded,hidden},toolId,Tool.borrow(owner))
def ensureFound(state: State,+id: String,name: String,args: Schema.Value,componentId: Nat,theme: Theme.Theme,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateArgs(current,args))
        return (state,True{})
    case None{}: mountedTool(state,id,componentId,Tool.new(name,id,args,theme,Tool.Generic{}))
def ensureTool(state: State,+id: String,name: String,args: Schema.Value) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,+componentId,view,+theme,styles,expanded,hidden}:
      ensureFound(State{entries,tools,active,componentId,view,theme,styles,expanded,hidden},id,name,args,componentId,theme,findTool(tools,id))
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
    case State{entries,tools,active,id,view,+theme,+styles,expanded,+hidden}:
      +snapshot = Messages.updateFromAi(Schema.Value,D,Messages.assistant(Nil{},theme,styles),message,True{})
      do IO<State & Bool>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles,expanded,hidden},Messages.AssistantBody{Messages.setHideThinkingBlock(snapshot,hidden)},True{})
        startedCalls(D,pair,message)
def updated(-A: Data,-D: Data,body: Messages.Body,message: Ai.AssistantMessage<A,D>,streaming: Bool) -> Messages.Body:
  match body:
    case Messages.AssistantBody{value}: Messages.AssistantBody{Messages.updateFromAi(A,D,value,message,streaming)}
    case value: value
def assistantUpdate(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>,+streaming: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,theme,styles,expanded,hidden}:
      match active:
        case None{}: IO.pure(State & Bool,(State{entries,tools,None{},id,view,theme,styles,expanded,hidden},False{}))
        case Some{+handle}:
          do IO<State & Bool>:
            body : Messages.Body <- Messages.current(handle)
            Messages.set(handle,updated(Schema.Value,D,body,message,streaming))
            mountCalls(Ai.assistantContent(Schema.Value,D,message),State{entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,streaming,Some{handle},None{}),id,view,theme,styles,expanded,hidden})
def blocksText(blocks: List<&2,Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: text ++ blocksText(rest)
    case _ <> rest: blocksText(rest)
def historicalFound(-D: Data,state: State,message: Ai.ToolResultMessage<D>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAiResult(D,current,message))
        return (state,True{})
def historicalTool(-D: Data,state: State,+message: Ai.ToolResultMessage<D>) -> IO(State & Bool):
  match state message:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden} Ai.ToolResultMessage{id,_,_,_,_,_,_}:
      historicalFound(D,State{entries,tools,active,next,view,theme,styles,expanded,hidden},message,findTool(tools,id))
def userMessage(-G: Data,-D: Data,-C: Data,state: State,message: Agent.AgentMessage<G,D,C>) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},_}}}: user(state,text)
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks},_}}}: user(state,blocksText(blocks))
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantStart(G,state,assistant)
    case Agent.LlmMessage{Ai.ToolResult{result}}: historicalTool(D,state,result)
    case _: IO.pure(State & Bool,(state,False{}))
def updateMessage(-G: Data,-D: Data,-C: Data,state: State,message: Agent.AgentMessage<G,D,C>,streaming: Bool) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantUpdate(G,state,assistant,streaming)
    case _: IO.pure(State & Bool,(state,False{}))
def beginFound(state: State,args: Schema.Value,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.markExecutionStarted(Tool.setArgsComplete(Tool.updateArgs(current,args))))
        return (state,True{})
def beginState(state: State,id: String,args: Schema.Value) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden}:
      beginFound(State{entries,tools,active,next,view,theme,styles,expanded,hidden},args,findTool(tools,id))
def begunPair(pair: State & Bool,id: String,args: Schema.Value) -> IO(State & Bool):
  match pair: case (next,_): beginState(next,id,args)
def startedTool(state: State,+id: String,name: String,+args: Schema.Value) -> IO(State & Bool):
  do IO<State & Bool>:
    pair : State & Bool <- ensureTool(state,id,name,args)
    begunPair(pair,id,args)
def partialFound(-D: Data,state: State,result: Agent.AgentToolResult<D>,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAgent(D,current,result,False{},True{}))
        return (state,True{})
def partialState(-D: Data,state: State,id: String,result: Agent.AgentToolResult<D>) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden}:
      partialFound(D,State{entries,tools,active,next,view,theme,styles,expanded,hidden},result,findTool(tools,id))
def partialPair(-D: Data,pair: State & Bool,id: String,result: Agent.AgentToolResult<D>) -> IO(State & Bool):
  match pair: case (next,_): partialState(D,next,id,result)
def partialTool(-D: Data,state: State,+id: String,name: String,args: Schema.Value,result: Agent.AgentToolResult<D>) -> IO(State & Bool):
  do IO<State & Bool>:
    pair : State & Bool <- startedTool(state,id,name,args)
    partialPair(D,pair,id,result)
def finishedFound(-D: Data,state: State,result: Agent.AgentToolResult<D>,error: Bool,found: Maybe<&2,Tool.Handle>) -> IO(State & Bool):
  match found:
    case None{}: IO.pure(State & Bool,(state,False{}))
    case Some{+handle}:
      do IO<State & Bool>:
        current : Tool.ToolExecution <- Tool.current(handle)
        Tool.set(handle,Tool.updateFromAgent(D,Tool.markExecutionStarted(current),result,error,False{}))
        return (state,True{})
def finishedTool(-D: Data,state: State,id: String,result: Agent.AgentToolResult<D>,error: Bool) -> IO(State & Bool):
  match state:
    case State{entries,+tools,active,next,view,theme,styles,expanded,hidden}:
      finishedFound(D,State{entries,tools,active,next,view,theme,styles,expanded,hidden},result,error,findTool(tools,id))
def transition(-G: Data,-D: Data,-C: Data,state: State,event: Agent.AgentEvent<G,D,C,Agent.AgentToolResult<D>,Agent.AgentToolResult<D>>) -> IO(State & Bool):
  match event:
    case Agent.MessageStart{message}: userMessage(G,D,C,state,message)
    case Agent.MessageUpdate{message,_}: updateMessage(G,D,C,state,message,True{})
    case Agent.MessageEnd{message}: updateMessage(G,D,C,state,message,False{})
    case Agent.ToolExecutionStart{id,name,args}: startedTool(state,id,name,args)
    case Agent.ToolExecutionUpdate{id,name,args,result}: partialTool(D,state,id,name,args,result)
    case Agent.ToolExecutionEnd{id,_,result,error}: finishedTool(D,state,id,result,error)
    case _: IO.pure(State & Bool,(state,False{}))
def accept(-G: Data,-D: Data,-C: Data,handle: Handle,event: Agent.AgentEvent<G,D,C,Agent.AgentToolResult<D>,Agent.AgentToolResult<D>>) -> IO(Bool):
  match handle:
    case Handle{resource}: Serial.run(State,Bool,resource,state => transition(G,D,C,state,event))
def seed(-G: Data,-D: Data,-C: Data,+handle: Handle,messages: List<&2,Agent.AgentMessage<G,D,C>>) -> IO(Unit):
  match messages:
    case Nil{}: IO.pure(Unit,Unit{})
    case +message <> rest:
      do IO<Unit>:
        begun : Bool <- accept(G,D,C,handle,Agent.MessageStart{message})
        ended : Bool <- accept(G,D,C,handle,Agent.MessageEnd{message})
        seed(G,D,C,handle,rest)
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
        begun : Bool <- accept(Unit,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageStart{Agent.LlmMessage{value}})
        ended : Bool <- accept(Unit,Tools.ToolDetails,CoreMessages.CodingMessage<Schema.Value>,handle,Agent.MessageEnd{Agent.LlmMessage{value}})
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
    case State{entries,tools,active,nextId,view,_,styles,expanded,hidden}:
      do IO<State & Unit>:
        next : List<&1,Entry> <- rethemeEntries(entries,theme)
        return (State{next,tools,active,nextId,view,theme,styles,expanded,hidden},Unit{})
def retheme(handle: Handle,theme: Theme.Theme) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => rethemed(state,theme))
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
    case State{entries,tools,active,nextId,view,theme,styles,+expanded,hidden}:
      do IO<State & Bool>:
        +next : Bool <- IO.pure(Bool,Bool.not(expanded))
        changed : List<&1,Entry> <- expandEntries(entries,next)
        return (State{changed,tools,active,nextId,view,theme,styles,next,hidden},next)
def toggleExpanded(handle: Handle) -> IO(Bool):
  match handle:
    case Handle{resource}: Serial.run(State,Bool,resource,toggled)
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
    case State{entries,tools,active,id,view,theme,styles,expanded,_}:
      do IO<State & Unit>:
        changed : List<&1,Entry> <- hideThinkingEntries(entries,hidden)
        return (State{changed,tools,active,id,view,theme,styles,expanded,hidden},Unit{})
def setHideThinking(handle: Handle,hidden: Bool) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,state => changedThinking(state,hidden))
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
    case State{entries,_,_,nextId,+view,theme,styles,expanded,hidden}:
      do IO<State & Unit>:
        View.clear(view)
        disposeEntries(entries)
        return (State{Nil{},Nil{},None{},nextId,view,theme,styles,expanded,hidden},Unit{})
def clear(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{resource}: Serial.run(State,Unit,resource,cleared)
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{entries,_,_,_,_,_,_,_,_}: disposeEntries(entries)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
