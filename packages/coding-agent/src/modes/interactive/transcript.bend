import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../runtime/src/serial-resource.bend as Serial
import ../../../../runtime/src/schema-value.bend as Schema
import ../../../../tui/src/component.bend as Component
import ../../../../tui/src/components/markdown.bend as Markdown
import ./theme/theme.bend as Theme
import ./components/messages.bend as Messages
import ./viewport.bend as View

# The transcript owns each mounted message. Agent events replace the active
# assistant's immutable snapshot; completed messages stay mounted for resizes.
type State is Type:
  State{entries: List<&1,Messages.Owner>,active: Maybe<&2,Messages.Handle>,nextId: Nat,view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme}
type Owner is Type: Owner{resource: Serial.Owner<State>}
type Handle is Data: Handle{resource: Serial.Handle<State>}

def create(view: View.Handle,theme: Theme.Theme,styles: Markdown.MarkdownTheme) -> IO(Owner):
  do IO<Owner>:
    resource : Serial.Owner<State> <- Serial.create(State,State{Nil{},None{},100n,view,theme,styles})
    return Owner{resource}
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>) -> Owner & Handle:
  match pair:
    case (resource,handle): (Owner{resource},Handle{handle})
def borrow(owner: Owner) -> Owner & Handle:
  match owner:
    case Owner{resource}: borrowed(Serial.borrow(State,resource))
def insertedState(state: State,owner: Messages.Owner,component: Component.Component,handle: Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,_,id,+view,theme,styles}:
      do IO<State & Bool>:
        View.append(view,component)
        return (State{List.append(&1,Messages.Owner,entries,owner <> Nil{}),Bool.pick(Maybe<&2,Messages.Handle>,assistant,Some{handle},None{}),id + 1n,view,theme,styles},True{})
def inserted(state: State,pair: Messages.Owner & Component.Component & Messages.Handle,assistant: Bool) -> IO(State & Bool):
  match pair:
    case (owner,component,handle): insertedState(state,owner,component,handle,assistant)
def append(state: State,body: Messages.Body,assistant: Bool) -> IO(State & Bool):
  match state:
    case State{entries,active,+id,view,theme,styles}:
      do IO<State & Bool>:
        owner : Messages.Owner <- Messages.create(Component.ComponentId{id},body)
        inserted(State{entries,active,id,view,theme,styles},Messages.borrow(owner),assistant)
def user(state: State,text: String) -> IO(State & Bool):
  match state:
    case State{entries,active,id,view,+theme,+styles}:
      append(State{entries,active,id,view,theme,styles},Messages.UserBody{Messages.user(text,theme,styles,1n)},False{})
def assistantStart(-A: Data,-D: Data,state: State,message: Ai.AssistantMessage<A,D>) -> IO(State & Bool):
  match state:
    case State{entries,active,id,view,+theme,+styles}:
      +snapshot = Messages.updateFromAi(A,D,Messages.assistant(Nil{},theme,styles),message,True{})
      append(State{entries,active,id,view,theme,styles},Messages.AssistantBody{snapshot},True{})
def updated(-A: Data,-D: Data,body: Messages.Body,message: Ai.AssistantMessage<A,D>,streaming: Bool) -> Messages.Body:
  match body:
    case Messages.AssistantBody{value}: Messages.AssistantBody{Messages.updateFromAi(A,D,value,message,streaming)}
    case value: value
def assistantUpdate(-A: Data,-D: Data,state: State,message: Ai.AssistantMessage<A,D>,+streaming: Bool) -> IO(State & Bool):
  match state:
    case State{entries,active,id,view,theme,styles}:
      match active:
        case None{}: IO.pure(State & Bool,(State{entries,None{},id,view,theme,styles},False{}))
        case Some{+handle}:
          do IO<State & Bool>:
            body : Messages.Body <- Messages.current(handle)
            Messages.set(handle,updated(A,D,body,message,streaming))
            return (State{entries,Bool.pick(Maybe<&2,Messages.Handle>,streaming,Some{handle},None{}),id,view,theme,styles},True{})
def blocksText(blocks: List<&2,Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: text ++ blocksText(rest)
    case _ <> rest: blocksText(rest)
def userMessage(-G: Data,-D: Data,-C: Data,state: State,message: Agent.AgentMessage<G,D,C>) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{text},_}}}: user(state,text)
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserBlocks{blocks},_}}}: user(state,blocksText(blocks))
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantStart(Schema.Value,G,state,assistant)
    case _: IO.pure(State & Bool,(state,False{}))
def updateMessage(-G: Data,-D: Data,-C: Data,state: State,message: Agent.AgentMessage<G,D,C>,streaming: Bool) -> IO(State & Bool):
  match message:
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantUpdate(Schema.Value,G,state,assistant,streaming)
    case _: IO.pure(State & Bool,(state,False{}))
def transition(-G: Data,-D: Data,-C: Data,-P: Data,-E: Data,state: State,event: Agent.AgentEvent<G,D,C,P,E>) -> IO(State & Bool):
  match event:
    case Agent.MessageStart{message}: userMessage(G,D,C,state,message)
    case Agent.MessageUpdate{message,_}: updateMessage(G,D,C,state,message,True{})
    case Agent.MessageEnd{message}: updateMessage(G,D,C,state,message,False{})
    case _: IO.pure(State & Bool,(state,False{}))
def accept(-G: Data,-D: Data,-C: Data,-P: Data,-E: Data,handle: Handle,event: Agent.AgentEvent<G,D,C,P,E>) -> IO(Bool):
  match handle:
    case Handle{resource}: Serial.run(State,Bool,resource,state => transition(G,D,C,P,E,state,event))
def disposeEntries(entries: List<&1,Messages.Owner>) -> IO(Unit):
  match entries:
    case Nil{}: IO.pure(Unit,Unit{})
    case entry <> rest:
      do IO<Unit>:
        Messages.dispose(entry)
        disposeEntries(rest)
def disposeState(state: State) -> IO(Unit):
  match state:
    case State{entries,_,_,_,_,_}: disposeEntries(entries)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{resource}:
      do IO<Unit>:
        state : State <- Serial.retire(State,resource)
        disposeState(state)
