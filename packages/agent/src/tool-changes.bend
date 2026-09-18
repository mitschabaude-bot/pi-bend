import Base
import ./types.bend as T
import ./agent-loop.bend as Loop
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/transcript.bend as Transcript
import ../../ai/src/utils/tool-declaration.bend as D
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/f64.bend as F
import ../../runtime/src/date.bend as Date

# Split around the last pending system message. Only that message's tool fields
# express pending intent; preceding declarations remain part of the baseline.
type Pending<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  Existing{before: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<V.Value>, after: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>}
  Absent{messages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>}

def splitLast(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, reversed: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>, after: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> Pending<Arguments, DiagnosticDetails, Details, Custom>:
  match reversed:
    case Nil{}: Absent{after}
    case T.LlmMessage{Ai.System{system}} <> before: Existing{List.reverse(&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>, before), system, after}
    case message <> rest: splitLast(Arguments, DiagnosticDetails, Details, Custom, rest, message <> after)

def optional(-A: Data, values: List<&2, A>) -> Maybe<&2, List<&2, A>>:
  match values:
    case Nil{}: None{}
    case head <> tail: Some{head <> tail}

def withToolChanges(message: Ai.SystemMessage<V.Value>, changes: Transcript.ToolStateChanges<V.Value>) -> Ai.SystemMessage<V.Value>:
  match message changes:
    case Ai.SystemMessage{content, sections, _, _, timestamp} Transcript.ToolStateChanges{added, removed}:
      Ai.SystemMessage{content, sections, optional(Ai.Tool<V.Value>, added), optional(Ai.ToolReference, removed), timestamp}

def join(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, before: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>, system: Ai.SystemMessage<V.Value>, after: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  List.append(&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>, before, T.LlmMessage{Ai.System{system}} <> after)

def baseline(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: Pending<Arguments, DiagnosticDetails, Details, Custom>) -> List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match pending:
    case Existing{before, system, after}: join(Arguments, DiagnosticDetails, Details, Custom, before, withToolChanges(system, Transcript.ToolStateChanges{Nil{}, Nil{}}), after)
    case Absent{messages}: messages

# Tool replay reads only native LLM system records. Custom messages do not pass
# through convertToLlm here; that callback is reserved for provider requests.
def llmMessages(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> List<&2, Ai.Message<V.Value, Arguments, DiagnosticDetails, Details>>:
  match messages:
    case Nil{}: Nil{}
    case T.LlmMessage{message} <> rest: message <> llmMessages(Arguments, DiagnosticDetails, Details, Custom, rest)
    case T.CustomMessage{_} <> rest: llmMessages(Arguments, DiagnosticDetails, Details, Custom, rest)

def declarations(-Arguments: Data, -Details: Data, -Validated: Data, -Signal: Data, -Error: Data, tools: List<&2, T.AgentTool<V.Value, Validated, Details, Arguments, Signal, Error>>) -> List<&2, Ai.Tool<V.Value>>:
  match tools:
    case Nil{}: Nil{}
    case tool <> rest: T.toTool(V.Value, Validated, Details, Arguments, Signal, Error, tool) <> declarations(Arguments, Details, Validated, Signal, Error, rest)

type ChangePlan<-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data> is Data:
  ChangePlan{pending: Pending<Arguments, DiagnosticDetails, Details, Custom>, changes: Transcript.ToolStateChanges<V.Value>}

def packagePlan(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, pending: Pending<Arguments, DiagnosticDetails, Details, Custom>, changes: D.DeclarationResult<Transcript.ToolStateChanges<V.Value>>) -> D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>:
  match changes:
    case D.Failure{error}: D.Failure{error}
    case D.Success{changes}: D.Success{ChangePlan{pending, changes}}

def plan(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, +context: T.AgentContext<V.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pendingMessages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>:
  +pending = splitLast(Arguments, DiagnosticDetails, Details, Custom, List.reverse(&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>, pendingMessages), Nil{})
  history = List.append(&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>, Loop.contextMessages(V.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context), baseline(Arguments, DiagnosticDetails, Details, Custom, pending))
  previous = Transcript.getCurrentTools(V.Value, Arguments, DiagnosticDetails, Details, llmMessages(Arguments, DiagnosticDetails, Details, Custom, history))
  current = declarations(Arguments, Details, Validated, Signal, Error, Loop.availableContextTools(V.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context))
  packagePlan(Arguments, DiagnosticDetails, Details, Custom, pending, Transcript.getToolStateChanges(previous, current))

def nonempty(-A: Data, values: Maybe<&2, List<&2, A>>) -> Bool:
  match values:
    case Some{_ <> _}: True{}
    case _: False{}

def hasChanges(changes: Transcript.ToolStateChanges<V.Value>) -> Bool:
  match changes:
    case Transcript.ToolStateChanges{Nil{}, Nil{}}: False{}
    case _: True{}

def pendingChanges(message: Ai.SystemMessage<V.Value>) -> Bool:
  match message:
    case Ai.SystemMessage{_, _, added, removed, _}: nonempty(Ai.Tool<V.Value>, added) || nonempty(Ai.ToolReference, removed)

def replaceSystem(original: Ai.SystemMessage<V.Value>, changes: Transcript.ToolStateChanges<V.Value>, replace: Bool) -> Ai.SystemMessage<V.Value>:
  match replace:
    case False{}: original
    case True{}: withToolChanges(original, changes)

# No existing system implies insertion before the first non-system message.
def insert(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>, +update: Ai.SystemMessage<V.Value>) -> List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match messages:
    case T.LlmMessage{Ai.System{system}} <> rest: T.LlmMessage{Ai.System{system}} <> insert(Arguments, DiagnosticDetails, Details, Custom, rest, update)
    case remaining: T.LlmMessage{Ai.System{update}} <> remaining

def absent(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, messages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>, changes: Transcript.ToolStateChanges<V.Value>, timestamp: F.F64, changed: Bool) -> List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>:
  match changed:
    case False{}: messages
    case True{}: insert(Arguments, DiagnosticDetails, Details, Custom, messages, withToolChanges(Ai.SystemMessage{Ai.SystemText{""}, None{}, None{}, None{}, timestamp}, changes))

def applyAt(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, timestamp: F.F64, planned: D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>) -> D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>:
  match planned:
    case D.Failure{error}: D.Failure{error}
    case D.Success{ChangePlan{Existing{before, +system, after}, +changes}}:
      D.Success{join(Arguments, DiagnosticDetails, Details, Custom, before, replaceSystem(system, changes, hasChanges(changes) || pendingChanges(system)), after)}
    case D.Success{ChangePlan{Absent{messages}, +changes}}:
      D.Success{absent(Arguments, DiagnosticDetails, Details, Custom, messages, changes, timestamp, hasChanges(changes))}

def needsTimestamp(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>) -> Bool:
  match planned:
    case D.Success{ChangePlan{Absent{_}, changes}}: hasChanges(changes)
    case _: False{}

def commit(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, planned: D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>>, timestampNeeded: Bool) -> IO(D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  match timestampNeeded:
    case False{}: IO.pure(D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>, applyAt(Arguments, DiagnosticDetails, Details, Custom, F.fromU32(0), planned))
    case True{}:
      do IO<D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
        timestamp : F.F64 <- Date.now()
        return applyAt(Arguments, DiagnosticDetails, Details, Custom, timestamp, planned)

def declareToolChanges(-Arguments: Data, -DiagnosticDetails: Data, -Details: Data, -Custom: Data, -Validated: Data, -Signal: Data, -Error: Data, context: T.AgentContext<V.Value, Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error>, pendingMessages: List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>) -> IO(D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>):
  do IO<D.DeclarationResult<List<&2, T.AgentMessage<V.Value, Arguments, DiagnosticDetails, Details, Custom>>>>:
    +planned : D.DeclarationResult<ChangePlan<Arguments, DiagnosticDetails, Details, Custom>> = plan(Arguments, DiagnosticDetails, Details, Custom, Validated, Signal, Error, context, pendingMessages)
    commit(Arguments, DiagnosticDetails, Details, Custom, planned, needsTimestamp(Arguments, DiagnosticDetails, Details, Custom, planned))
