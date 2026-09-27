import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/schema-value.bend as Value
import ../../../../../runtime/src/serial-resource.bend as Serial
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../ai/src/types.bend as Ai
import ../../../core/messages.bend as Core
import ../../../core/extensions/types.bend as Extensions
import ../theme/theme.bend as Theme
import ./messages.bend as Messages

type State is Type:
  State{id: Component.ComponentId, message: Core.CustomMessage<Value.Value>, renderer: Maybe<&2, Extensions.MessageRenderer()>, options: Extensions.MessageRenderOptions, theme: Theme.Theme, markdownTheme: Markdown.MarkdownTheme, child: Maybe<&1, Component.Owner>, custom: Bool}
type Handle is Data: Handle{state: Serial.Handle<State>}
type Owner is Type:
  Owner{state: Serial.Owner<State>, component: Component.Component, render: Callback.Callback<Nat, List<&2, String>>, invalidate: Callback.Callback<Unit, Unit>}

def disposeChild(child: Maybe<&1, Component.Owner>) -> IO(Unit):
  match child:
    case None{}: IO.pure(Unit, Unit{})
    case Some{owner}: Component.dispose(owner)

def contentPieces(blocks: List<&2, Ai.TextImageContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case Ai.TextImageText{Ai.TextContent{text, _}} <> rest: text <> contentPieces(rest)
    case _ <> rest: contentPieces(rest)
def contentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: String.join(contentPieces(blocks), "\n")
def defaultBody(message: Core.CustomMessage<Value.Value>, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> Messages.Body:
  match message:
    case Core.CustomMessage{label, content, _, _, _}: Messages.NoteBody{Messages.Note{label, None{}, contentText(content), True{}, theme, markdown, ""}}
def ownDefault(pair: Messages.Owner & Component.Component & Messages.Handle) -> Component.Owner:
  match pair:
    case Tuple{owner, Tuple{component, _}}: Component.Owner{component, _ => Messages.dispose(owner)}

def fallback(state: State) -> IO(State):
  match state:
    case State{+id, +message, renderer, options, +theme, +markdown, _, _}:
      do IO<State>:
        owner : Messages.Owner <- Messages.create(id, defaultBody(message, theme, markdown))
        return State{id, message, renderer, options, theme, markdown, Some{ownDefault(Messages.borrow(owner))}, False{}}
def installed(state: State, result: Extensions.MessageRenderResult()) -> IO(State):
  match state result:
    case State{id, message, renderer, options, theme, markdown, _, _} Done{Some{owner}}:
      IO.pure(State, State{id, message, renderer, options, theme, markdown, Some{owner}, True{}})
    case state _: fallback(state)
def renderSelected(state: State) -> IO(State):
  match state:
    case State{+id, +message, Some{+renderer}, +options, +theme, markdown, _, _}:
      do IO<State>:
        result : Extensions.MessageRenderResult() <- Callback.call(Extensions.MessageRenderInput, Extensions.MessageRenderResult(), renderer, Extensions.MessageRenderInput{message, options, theme})
        installed(State{id, message, Some{renderer}, options, theme, markdown, None{}, False{}}, result)
    case state: fallback(state)
def rebuild(state: State) -> IO(State):
  match state:
    case State{id, message, renderer, options, theme, markdown, child, _}:
      do IO<State>:
        disposeChild(child)
        renderSelected(State{id, message, renderer, options, theme, markdown, None{}, False{}})

def renderState(state: State, width: Nat) -> IO(State & List<&2, String>):
  match state:
    case State{id, message, renderer, options, theme, markdown, Some{Component.Owner{+component, retire}}, +custom}:
      do IO<State & List<&2, String>>:
        +rows : List<&2, String> <- Component.render(component, width)
        return (State{id, message, renderer, options, theme, markdown, Some{Component.Owner{component, retire}}, custom}, Bool.pick(List<&2, String>, custom, "" <> rows, rows))
    case state: IO.pure(State & List<&2, String>, (state, Nil{}))
def render(handle: Handle, width: Nat) -> IO(List<&2, String>):
  match handle:
    case Handle{state}: Serial.run(State, List<&2, String>, state, current => renderState(current, width))

def invalidateChild(state: State) -> IO(State):
  match state:
    case State{id, message, renderer, options, theme, markdown, Some{Component.Owner{+component, retire}}, custom}:
      do IO<State>:
        Component.invalidate(component)
        return State{id, message, renderer, options, theme, markdown, Some{Component.Owner{component, retire}}, custom}
    case state: IO.pure(State, state)
def invalidated(state: State) -> IO(State & Unit):
  do IO<State & Unit>:
    current : State <- invalidateChild(state)
    rebuilt : State <- rebuild(current)
    return (rebuilt, Unit{})
def invalidate(handle: Handle, _: Unit) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, invalidated)

def changed(state: State, options: Extensions.MessageRenderOptions) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, _, theme, markdown, child, custom}:
      do IO<State & Unit>:
        current : State <- rebuild(State{id, message, renderer, options, theme, markdown, child, custom})
        return (current, Unit{})
def updateOptions(different: Bool, state: State, options: Extensions.MessageRenderOptions) -> IO(State & Unit):
  match different:
    case False{}: IO.pure(State & Unit, (state, Unit{}))
    case True{}: changed(state, options)
def expanded(state: State, +value: Bool) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, Extensions.MessageRenderOptions{+current, +pad}, theme, markdown, child, custom}:
      updateOptions(Bool.xor(current, value), State{id, message, renderer, Extensions.MessageRenderOptions{current, pad}, theme, markdown, child, custom}, Extensions.MessageRenderOptions{value, pad})
def setExpanded(handle: Handle, value: Bool) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => expanded(current, value))
def padded(state: State, +value: Nat) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, Extensions.MessageRenderOptions{+isExpanded, +current}, theme, markdown, child, custom}:
      updateOptions(Bool.not(Nat.is_eq(current, value)), State{id, message, renderer, Extensions.MessageRenderOptions{isExpanded, current}, theme, markdown, child, custom}, Extensions.MessageRenderOptions{isExpanded, value})
def setOutputPad(handle: Handle, value: Nat) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => padded(current, value))

def themed(state: State, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(State & Unit):
  match state:
    case State{id, message, renderer, options, _, _, child, custom}:
      do IO<State & Unit>:
        current : State <- rebuild(State{id, message, renderer, options, theme, markdown, child, custom})
        return (current, Unit{})
def setTheme(handle: Handle, theme: Theme.Theme, markdown: Markdown.MarkdownTheme) -> IO(Unit):
  match handle:
    case Handle{state}: Serial.run(State, Unit, state, current => themed(current, theme, markdown))

def mounted(id: Component.ComponentId, pair: Serial.Owner<State> & Serial.Handle<State>) -> IO(Owner):
  match pair:
    case Tuple{owner, +state}:
      do IO<Owner>:
        +handle : Handle = Handle{state}
        +renderCallback : Callback.Callback<Nat, List<&2, String>> <- Callback.create(~Handle, ~Nat, ~List<&2, String>, ~render, handle)
        +invalidateCallback : Callback.Callback<Unit, Unit> <- Callback.create(~Handle, ~Unit, ~Unit, ~invalidate, handle)
        return Owner{owner, Component.Component{id, renderCallback, None{}, None{}, invalidateCallback, None{}, False{}}, renderCallback, invalidateCallback}
def create(+id: Component.ComponentId, message: Core.CustomMessage<Value.Value>, renderer: Maybe<&2, Extensions.MessageRenderer()>, theme: Theme.Theme, markdown: Markdown.MarkdownTheme, outputPad: Nat) -> IO(Owner):
  do IO<Owner>:
    current : State <- rebuild(State{id, message, renderer, Extensions.MessageRenderOptions{False{}, outputPad}, theme, markdown, None{}, False{}})
    owner : Serial.Owner<State> <- Serial.create(State, current)
    mounted(id, Serial.borrow(State, owner))
def borrowed(pair: Serial.Owner<State> & Serial.Handle<State>, +component: Component.Component, renderCallback: Callback.Callback<Nat, List<&2, String>>, invalidateCallback: Callback.Callback<Unit, Unit>) -> Owner & Component.Component & Handle:
  match pair:
    case Tuple{state, handle}: (Owner{state, component, renderCallback, invalidateCallback}, component, Handle{handle})
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{state, component, renderCallback, invalidateCallback}: borrowed(Serial.borrow(State, state), component, renderCallback, invalidateCallback)
def disposed(state: State) -> IO(Unit):
  match state:
    case State{_, _, _, _, _, _, child, _}: disposeChild(child)
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state, _, render, invalidate}:
      do IO<Unit>:
        current : State <- Serial.retire(State, state)
        disposed(current)
        Callback.dispose(Nat, List<&2, String>, render)
        Callback.dispose(Unit, Unit, invalidate)

# Apply a configuration change while retaining the affine component owner.
def updatedOwner(pair: Owner & Component.Component & Handle, change: Handle -> IO(Unit)) -> IO(Owner):
  match pair:
    case (owner, _, handle):
      do IO<Owner>:
        change(handle)
        return owner
def updateOwner(owner: Owner, change: Handle -> IO(Unit)) -> IO(Owner): updatedOwner(borrow(owner), change)
