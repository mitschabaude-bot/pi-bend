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

# The transcript owns mounted messages and tools. Agent events replace the
# active assistant and matching tool snapshots; entries stay mounted for resizes.
type Entry is Type: MessageEntry{owner: Messages.Owner} ToolEntry{owner: Tool.Owner}
type ToolLink is Data: ToolLink{id: String,handle: Tool.Handle}
type State is Type:
  State{entries: List<&1,Entry>,tools: List<&2,ToolLink>,active: Maybe<&2,Messages.Handle>,nextId: Nat,view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme}
type Owner is Type: Owner{resource: Serial.Owner<State>}
type Handle is Data: Handle{resource: Serial.Handle<State>}

def create(view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{Nil{},Nil{},None{},100n,view,theme,styles})
    return Owner{resource}
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>) -> Owner & Handle:
  match pair:
    case (resource,handle): (Owner{resource},Handle{handle})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource}: borrowed(Serial.borrow(State,resource))
def insertedState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,_,id,+view,theme,styles}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{MessageEntry{owner} <> entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,assistant,Some{handle},None{}),id + 1n,view,theme,styles},True{})
def inserted(state: State,pair: Messages.Owner & Component.Component & Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match pair:
    case (owner,component,handle): insertedState(state,owner,component,handle,assistant)
def append(state: State,body: Messages.Body,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,view,theme,styles}:
      do IO<State & Bool>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},body)
        inserted(State{entries,tools,active,id,view,theme,styles},Messages.borrow(owner),assistant)
def user(state: State,text: String) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,+theme,+styles}:
      append(State{entries,tools,active,id,view,theme,styles},Messages.UserBody{Messages.user(text,theme,styles,1n)},False{})
def findTool(tools: List<&2,ToolLink>,+id: String) -> Maybe<&2,Tool.Handle>:
  match tools:
    case Nil{}: None{}
    case ToolLink{current,handle} <> rest:
      Bool.pick(Maybe<&2,Tool.Handle>,String.eq(current,id),Some{handle},findTool(rest,id))
def mountedOwned(state: State,toolId: String,owned: Tool.Owner,component: Component.Component,handle: Tool.Handle) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,+id,+view,theme,styles}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{ToolEntry{owned} <> entries,ToolLink{toolId,handle} <> tools,active,id + 1n,view,theme,styles},True{})
def mountedBorrowed(state: State,toolId: String,pair: Tool.Owner & Component.Component & Tool.Handle) -> IO(State & Bool):
  match pair:
    case (owned,component,handle): mountedOwned(state,toolId,owned,component,handle)
def mountedTool(state: State,toolId: String,componentId: Nat,value: Tool.ToolExecution) -> IO(State & Bool):
  do IO<State & Bool>:
    owner : Tool.Owner <- Tool.create(Component.ComponentId{componentId},value)
    mountedBorrowed(state,toolId,Tool.borrow(owner))
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
    case State{entries,+tools,active,+componentId,view,+theme,styles}:
      ensureFound(State{entries,tools,active,componentId,view,theme,styles},id,name,args,componentId,theme,findTool(tools,id))
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
    case State{entries,tools,active,id,view,+theme,+styles}:
      +snapshot = Messages.updateFromAi(Schema.Value,D,Messages.assistant(Nil{},theme,styles),message,True{})
      do IO<State & Bool>:
        pair : State & Bool <- append(State{entries,tools,active,id,view,theme,styles},Messages.AssistantBody{snapshot},True{})
        startedCalls(D,pair,message)
def updated(-A: Data,-D: Data,body: Messages.Body,message: Ai.AssistantMessage<A,D>,streaming: Bool) -> Messages.Body:
  match body:
    case Messages.AssistantBody{value}: Messages.AssistantBody{Messages.updateFromAi(A,D,value,message,streaming)}
    case value: value
def assistantUpdate(-D: Data,state: State,+message: Ai.AssistantMessage<Schema.Value,D>,+streaming: Bool) -> IO(State & Bool):
  match state:
    case State{entries,tools,active,id,view,theme,styles}:
      match active:
        case None{}: IO.pure(State & Bool,(State{entries,tools,None{},id,view,theme,styles},False{}))
        case Some{+handle}:
          do IO<State & Bool>:
            body : Messages.Body <- Messages.current(handle)
            Messages.set(handle,updated(Schema.Value,D,body,message,streaming))
            mountCalls(Ai.assistantContent(Schema.Value,D,message),State{entries,tools,Bool.pick(Maybe<&2,Messages.Handle>,streaming,Some{handle},None{}),id,view,theme,styles})
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
    case State{entries,+tools,active,next,view,theme,styles} Ai.ToolResultMessage{id,_,_,_,_,_,_}:
      historicalFound(D,State{entries,tools,active,next,view,theme,styles},message,findTool(tools,id))
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
    case State{entries,+tools,active,next,view,theme,styles}:
      beginFound(State{entries,tools,active,next,view,theme,styles},args,findTool(tools,id))
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
    case State{entries,+tools,active,next,view,theme,styles}:
      partialFound(D,State{entries,tools,active,next,view,theme,styles},result,findTool(tools,id))
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
    case State{entries,+tools,active,next,view,theme,styles}:
      finishedFound(D,State{entries,tools,active,next,view,theme,styles},result,error,findTool(tools,id))
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
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{entries,_,_,_,_,_,_}: disposeEntries(entries)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
