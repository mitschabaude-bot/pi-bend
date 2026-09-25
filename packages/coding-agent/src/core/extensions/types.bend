import Base
import ../../../../ai/src/models.bend as AiModels
import ../../../../agent/src/types.bend as Agent
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/ref.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../tui/src/autocomplete.bend as AC
import ../messages.bend as Messages
import ../model-runtime.bend as Models
import ../skills.bend as Skills
import ../tools/index.bend as Tools
import ./context.bend as Ctx

# upstream core/extensions/types.ts: registrations, events and the loaded
# extension state. Extensions are Bend code linked into the binary; their
# handlers are callbacks over typed events and results.

# Commands
# --------

def ArgumentCompletions() -> Data: C.Callback<String, AC.ResultOf(Maybe<&2, List<&2, AC.AutocompleteItem>>)>

type CommandCall is Data:
  CommandCall{args: String, ctx: Ctx.ExtensionCommandContext}

# A failure is the message of upstream's rejected handler promise.
def CommandHandler() -> Data: C.Callback<CommandCall, Result<&2, &2, String, Unit>>

# upstream Omit<RegisteredCommand, "name" | "sourceInfo">
type CommandOptions is Data:
  CommandOptions{description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

type RegisteredCommand is Data:
  RegisteredCommand{name: String, sourceInfo: Skills.SourceInfo, description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

# upstream ResolvedCommand extends RegisteredCommand with invocationName.
type ResolvedCommand is Data:
  ResolvedCommand{name: String, invocationName: String, sourceInfo: Skills.SourceInfo, description: Maybe<&2, String>, getArgumentCompletions: Maybe<&2, ArgumentCompletions()>, handler: CommandHandler()}

# Errors
# ------

type ExtensionError is Data:
  ExtensionError{extensionPath: String, event: String, error: String, stack: Maybe<&2, String>}

# Events
# ------

def AgentMessage() -> Data: Agent.AgentMessage<Unit, Tools.ToolDetails, Messages.CodingMessage<V.Value>>

type AgentEndEvent is Data:
  AgentEndEvent{messages: List<&2, AgentMessage()>}

type HandlerCall<-E: Data> is Data:
  HandlerCall{event: E, ctx: Ctx.ExtensionContext}

# upstream ExtensionHandler<E, R>: None is a handler returning nothing; a
# failure is the message of the error it threw.
def ExtensionHandler(-E: Data, -R: Data) -> Data: C.Callback<HandlerCall<E>, Result<&2, &2, String, Maybe<&2, R>>>

# One constructor per event, carrying a handler typed by the event and its
# result (upstream's `on` overloads). Later phases add the other events.
type EventHandler is Data:
  OnAgentEnd{handler: ExtensionHandler(AgentEndEvent, Unit)}

type ExtensionEvent is Data:
  AgentEnd{event: AgentEndEvent}

def handlerEventType(handler: EventHandler) -> String:
  match handler:
    case OnAgentEnd{_}: "agent_end"

def eventType(event: ExtensionEvent) -> String:
  match event:
    case AgentEnd{_}: "agent_end"

# `on` returns the id its unsubscribe removes (upstream removes the handler
# by function identity).
type Subscription is Data:
  Subscription{id: Nat, handler: EventHandler}

# Loaded extensions (upstream Extension and ExtensionRuntime)
# -----------------------------------------------------------

type LoadState is Data:
  Loading{}
  Active{}
  Failed{}

# Provider changes an extension makes while it loads apply when it has loaded
# (upstream applyRuntimeChange).
type ProviderChange is Data:
  RegisterProvider{provider: AiModels.Provider}
  UnregisterProvider{name: String}

type Extension is Data:
  Extension{id: Nat, path: String, resolvedPath: String, hidden: Bool, sourceInfo: Skills.SourceInfo, handlers: List<&2, Subscription>, commands: List<&2, RegisteredCommand>, state: LoadState, changes: List<&2, ProviderChange>}

type PendingProvider is Data:
  PendingProvider{provider: AiModels.Provider, extensionPath: String}

# Where provider registrations go once they are bound (upstream bindCore's
# providerActions): the model runtime, and what to do after a provider
# changed (the session refreshes its current model).
type ProviderBinding is Data:
  ProviderBinding{models: Models.ModelRuntime, changed: Maybe<&2, C.Callback<Unit, Unit>>}

# Before registrations are bound, they queue (upstream
# pendingNativeProviderRegistrations).
type ExtensionRuntimeState is Data:
  ExtensionRuntimeState{extensions: List<&2, Extension>, pendingProviders: List<&2, PendingProvider>, providers: Maybe<&2, ProviderBinding>, nextId: Nat}

def ExtensionRuntime() -> Data: R.Ref<ExtensionRuntimeState>

# Inline extensions
# -----------------

type ExtensionAPI is Data:
  ExtensionAPI{runtime: R.Ref<ExtensionRuntimeState>, extension: Nat}

# upstream ExtensionFactory. A failure is the message the factory threw.
def ExtensionFactory() -> Type: ExtensionAPI -> IO(Result<&2, &2, String, Unit>)

# upstream InlineExtension in its named form: `<inline:name>`, omitted from
# the startup list when hidden. Factories are Bend functions, so the list is
# consumed when it is loaded.
type InlineExtension is Type:
  InlineExtension{name: String, factory: ExtensionFactory(), hidden: Bool}

# upstream LoadExtensionsResult.errors
type LoadError is Data:
  LoadError{path: String, error: String}
