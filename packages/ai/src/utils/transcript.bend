import Base
import ../types.bend as T
import ./text.bend as Text
import ./tool-declaration.bend as Declaration
import ../../../runtime/src/schema-value.bend as Schema
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ordered-map.bend as M
import ../../../runtime/src/f64.bend as Number

# Initial normalization from transcript.ts. It does not implicitly replay
# existing system messages; the replay operations below remain separate.
def promptValue(prompt: Maybe<&2, String>) -> String:
  match prompt:
    case None{}: ""
    case Some{value}: value

def nonEmptyTools(-P: Data, tools: Maybe<&2, List<&2, T.Tool<P>>>) -> Maybe<&2, List<&2, T.Tool<P>>>:
  match tools:
    case None{}: None{}
    case Some{Nil{}}: None{}
    case Some{head <> tail}: Some{head <> tail}

def hasTools(-P: Data, tools: Maybe<&2, List<&2, T.Tool<P>>>) -> Bool:
  match tools:
    case None{}: False{}
    case Some{_}: True{}

def createInitial(-P: Data, needed: Bool, prompt: String, tools: Maybe<&2, List<&2, T.Tool<P>>>) -> Maybe<&2, T.SystemMessage<P>>:
  match needed:
    case False{}: None{}
    case True{}:
      value = {T.SystemMessage{T.SystemText{prompt}, None{}, tools, None{}, Number.fromU32(0)} : T.SystemMessage<P>}
      Some{value}

def createInitialSystemMessage(-P: Data, systemPrompt: Maybe<&2, String>, tools: Maybe<&2, List<&2, T.Tool<P>>>) -> Maybe<&2, T.SystemMessage<P>>:
  +prompt = promptValue(systemPrompt)
  +available = nonEmptyTools(P, tools)
  createInitial(P, Bool.not(String.is_empty(prompt)) || hasTools(P, available), prompt, available)

def prependInitial(-P: Data, -A: Data, -G: Data, -H: Data, initial: Maybe<&2, T.SystemMessage<P>>, messages: List<&2, T.Message<P, A, G, H>>) -> T.TranscriptContext<P, A, G, H>:
  match initial:
    case None{}: T.TranscriptContext{messages}
    case Some{value}:
      original = {messages : List<&2, T.Message<P, A, G, H>>}
      copied = {T.System{value} <> original : List<&2, T.Message<P, A, G, H>>}
      T.TranscriptContext{copied}

def normalizeContext(-P: Data, -A: Data, -G: Data, -H: Data, context: T.Context<P, A, G, H>) -> T.TranscriptContext<P, A, G, H>:
  match context:
    case T.Context{systemPrompt, messages, tools}:
      initial = {createInitialSystemMessage(P, systemPrompt, tools) : Maybe<&2, T.SystemMessage<P>>}
      prependInitial(P, A, G, H, initial, messages)

def getInitialSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> Maybe<&2, T.SystemMessage<P>>:
  match messages:
    case T.System{value} <> _: Some{value}
    case _: None{}

def withoutInitialSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match messages:
    case T.System{_} <> tail: tail
    case messages: messages

# Tool replay uses insertion-ordered maps, not object property ordering.
def toolName(-P: Data, tool: T.Tool<P>) -> String:
  match tool:
    case T.Tool{name, _, _, _}: name

def removeTools(-P: Data, removed: List<&2, T.ToolReference>, tools: M.OrderedMap<T.Tool<P>>) -> M.OrderedMap<T.Tool<P>>:
  match removed:
    case Nil{}: tools
    case T.ToolReference{name} <> rest: removeTools(P, rest, M.remove(T.Tool<P>, tools, name))

def addTools(-P: Data, added: List<&2, T.Tool<P>>, tools: M.OrderedMap<T.Tool<P>>) -> M.OrderedMap<T.Tool<P>>:
  match added:
    case Nil{}: tools
    case +head <> rest:
      value = {head : T.Tool<P>}
      addTools(P, rest, M.set(T.Tool<P>, tools, toolName(P, value), head))

def listValue(-V: Data, value: Maybe<&2, List<&2, V>>) -> List<&2, V>:
  match value:
    case None{}: Nil{}
    case Some{items}: items

def replayTools(-P: Data, message: T.SystemMessage<P>, tools: M.OrderedMap<T.Tool<P>>, includeRemoved: Bool) -> M.OrderedMap<T.Tool<P>>:
  match message:
    case T.SystemMessage{_, _, added, removed, _}:
      addTools(P, listValue(T.Tool<P>, added), removeTools(P, Bool.pick(List<&2, T.ToolReference>, includeRemoved, listValue(T.ToolReference, removed), Nil{}), tools))

def collectTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, tools: M.OrderedMap<T.Tool<P>>, +includeRemoved: Bool) -> List<&2, T.Tool<P>>:
  match messages:
    case Nil{}: M.values(T.Tool<P>, tools)
    case T.System{reference} <> rest:
      message = {reference : T.SystemMessage<P>}
      updated = {replayTools(P, message, tools, includeRemoved) : M.OrderedMap<T.Tool<P>>}
      collectTools(P, A, G, H, rest, updated, includeRemoved)
    case _ <> rest: collectTools(P, A, G, H, rest, tools, includeRemoved)

def getCurrentTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Tool<P>>:
  collectTools(P, A, G, H, messages, M.new(T.Tool<P>), True{})

def getDeclaredTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Tool<P>>:
  collectTools(P, A, G, H, messages, M.new(T.Tool<P>), False{})

type ReplayState is Data:
  ReplayState{content: List<&2, String>, sections: R.Record<Maybe<&2, String>>, timestamp: Maybe<&2, Number.F64>}

def applySections(properties: List<&2, R.Property<Maybe<&2, String>>>, sections: R.Record<Maybe<&2, String>>) -> R.Record<Maybe<&2, String>>:
  match properties:
    case Nil{}: sections
    case R.Property{name, None{}} <> rest: applySections(rest, R.remove(Maybe<&2, String>, sections, name))
    case R.Property{name, Some{value}} <> rest: applySections(rest, R.set(Maybe<&2, String>, sections, name, Some{value}))

def firstTimestamp(existing: Maybe<&2, Number.F64>, timestamp: Number.F64) -> Maybe<&2, Number.F64>:
  match existing:
    case None{}: Some{timestamp}
    case Some{value}: Some{value}

def appendContent(+text: String, +content: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(text), content, text <> content)

def replayMessage(-P: Data, message: T.SystemMessage<P>, state: ReplayState) -> ReplayState:
  match message state:
    case T.SystemMessage{content, sections, _, _, timestamp} ReplayState{parts, currentSections, initialTimestamp}:
      ReplayState{appendContent(Text.systemContentText(content), parts), applySections(Text.sectionEntries(sections), currentSections), firstTimestamp(initialTimestamp, timestamp)}

def replayMessages(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, state: ReplayState) -> ReplayState:
  match messages:
    case Nil{}: state
    case T.System{reference} <> rest:
      message = {reference : T.SystemMessage<P>}
      replayMessages(P, A, G, H, rest, replayMessage(P, message, state))
    case _ <> rest: replayMessages(P, A, G, H, rest, state)

def optionalSections(properties: List<&2, R.Property<Maybe<&2, String>>>) -> Maybe<&2, R.Record<Maybe<&2, String>>>:
  match properties:
    case Nil{}: None{}
    case head <> tail: Some{R.Record{head <> tail}}

def timestampValue(timestamp: Maybe<&2, Number.F64>) -> Number.F64:
  match timestamp:
    case None{}: Number.fromU32(0)
    case Some{value}: value

def finishReplay(-P: Data, state: ReplayState, tools: List<&2, T.Tool<P>>) -> Maybe<&2, T.SystemMessage<P>>:
  match state tools:
    case ReplayState{_, _, None{}} Nil{}: None{}
    case ReplayState{content, sections, timestamp} tools:
      message = {T.SystemMessage{T.SystemText{String.join(List.reverse(&2, String, content), "\n\n")}, optionalSections(R.entries(Maybe<&2, String>, sections)), nonEmptyTools(P, Some{tools}), None{}, timestampValue(timestamp)} : T.SystemMessage<P>}
      Some{message}

def getCurrentSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, +messages: List<&2, T.Message<P, A, G, H>>) -> Maybe<&2, T.SystemMessage<P>>:
  state = {replayMessages(P, A, G, H, messages, ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}}) : ReplayState}
  tools = {getCurrentTools(P, A, G, H, messages) : List<&2, T.Tool<P>>}
  finishReplay(P, state, tools)

def currentPrompt(-P: Data, message: Maybe<&2, T.SystemMessage<P>>) -> String:
  match message:
    case None{}: ""
    case Some{reference}:
      value = {reference : T.SystemMessage<P>}
      Text.renderComplete(P, value)

def getCurrentSystemPrompt(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> String:
  message = {getCurrentSystemMessage(P, A, G, H, messages) : Maybe<&2, T.SystemMessage<P>>}
  currentPrompt(P, message)

def withoutSystemMessages(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match messages:
    case Nil{}: Nil{}
    case T.System{_} <> rest: withoutSystemMessages(P, A, G, H, rest)
    case head <> rest: head <> withoutSystemMessages(P, A, G, H, rest)

def collapsedMessages(-P: Data, -A: Data, -G: Data, -H: Data, head: Maybe<&2, T.SystemMessage<P>>, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match head:
    case None{}: messages
    case Some{value}: T.System{value} <> messages

def collapseSystemMessages(-P: Data, -A: Data, -G: Data, -H: Data, context: T.TranscriptContext<P, A, G, H>) -> T.TranscriptContext<P, A, G, H>:
  match context:
    case T.TranscriptContext{reference}:
      +messages = {reference : List<&2, T.Message<P, A, G, H>>}
      head = {getCurrentSystemMessage(P, A, G, H, messages) : Maybe<&2, T.SystemMessage<P>>}
      copied = {collapsedMessages(P, A, G, H, head, withoutSystemMessages(P, A, G, H, messages)) : List<&2, T.Message<P, A, G, H>>}
      T.TranscriptContext{copied}

def resolveTranscript(-P: Data, -A: Data, -G: Data, -H: Data, context: T.TranscriptContext<P, A, G, H>, supportsMidConvoSystemMessages: Maybe<&2, Bool>) -> T.TranscriptContext<P, A, G, H>:
  match supportsMidConvoSystemMessages:
    case Some{True{}}: context
    case _: collapseSystemMessages(P, A, G, H, context)

def addNames(-P: Data, added: List<&2, T.Tool<P>>, +seen: M.OrderedMap<Unit>) -> M.OrderedMap<Unit> & Bool:
  match added:
    case Nil{}: (seen, False{})
    case reference <> rest:
      tool = {reference : T.Tool<P>}
      +name = {toolName(P, tool) : String}
      Bool.pick(M.OrderedMap<Unit> & Bool, Maybe.is_some(&2, Unit, M.get(Unit, seen, name)), (seen, True{}), addNames(P, rest, M.set(Unit, seen, name, Unit{})))

def nameChanges(-P: Data, message: T.SystemMessage<P>, seen: M.OrderedMap<Unit>) -> M.OrderedMap<Unit> & Bool:
  match message:
    case T.SystemMessage{_, _, _, Some{_ <> _}, _}: (seen, True{})
    case T.SystemMessage{_, _, added, _, _}: addNames(P, listValue(T.Tool<P>, added), seen)

def scanNonAdditive(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, state: M.OrderedMap<Unit> & Bool) -> Bool:
  match messages state:
    case _ Tuple{_, True{}}: True{}
    case Nil{} Tuple{_, False{}}: False{}
    case T.System{reference} <> rest Tuple{seen, False{}}:
      message = {reference : T.SystemMessage<P>}
      updated = {nameChanges(P, message, seen) : M.OrderedMap<Unit> & Bool}
      scanNonAdditive(P, A, G, H, rest, updated)
    case _ <> rest state: scanNonAdditive(P, A, G, H, rest, state)

def hasNonAdditiveToolChanges(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> Bool:
  scanNonAdditive(P, A, G, H, messages, (M.new(Unit), False{}))

type TranscriptTools<-P: Data> is Data:
  TranscriptTools{requestTools: List<&2, T.Tool<P>>, anchorsAdditions: Bool}

def initialToolsValue(-P: Data, message: T.SystemMessage<P>) -> List<&2, T.Tool<P>>:
  match message:
    case T.SystemMessage{_, _, added, _, _}: listValue(T.Tool<P>, added)

def initialTools(-P: Data, message: Maybe<&2, T.SystemMessage<P>>) -> TranscriptTools<P>:
  match message:
    case None{}: TranscriptTools{Nil{}, True{}}
    case Some{reference}:
      value = {reference : T.SystemMessage<P>}
      TranscriptTools{initialToolsValue(P, value), True{}}

def resolveToolMode(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, anchors: Bool) -> TranscriptTools<P>:
  match anchors:
    case True{}: initialTools(P, getInitialSystemMessage(P, A, G, H, messages))
    case False{}:
      tools = {getCurrentTools(P, A, G, H, messages) : List<&2, T.Tool<P>>}
      TranscriptTools{tools, False{}}

def resolveTranscriptTools(-P: Data, -A: Data, -G: Data, -H: Data, +messages: List<&2, T.Message<P, A, G, H>>, supportsToolAdditions: Bool) -> TranscriptTools<P>:
  match supportsToolAdditions:
    case False{}: resolveToolMode(P, A, G, H, messages, False{})
    case True{}:
      nonAdditive = {hasNonAdditiveToolChanges(P, A, G, H, messages) : Bool}
      resolveToolMode(P, A, G, H, messages, Bool.not(nonAdditive))

# Schema-data entry points. The TypeBox static-schema adapter is still pending.
def toToolDeclaration(tool: T.Tool<Schema.Value>) -> Declaration.DeclarationResult<T.Tool<Schema.Value>>:
  Declaration.toToolDeclaration(tool)

def declarationsEqual(left: T.Tool<Schema.Value>, right: T.Tool<Schema.Value>) -> Declaration.DeclarationResult<Bool>:
  Declaration.declarationsEqual(left, right)

# Upstream transcript.ts ToolStateChanges. Schema-data entry points currently
# use value lists; mutable/extended-tool adapters remain a separate boundary.
type ToolStateChanges<-P: Data> is Data:
  ToolStateChanges{toolsAdded: List<&2, T.Tool<P>>, toolsRemoved: List<&2, T.ToolReference>}

def indexToolValues(-P: Data, remaining: List<&2, T.Tool<P>>, indexed: M.OrderedMap<T.Tool<P>>) -> M.OrderedMap<T.Tool<P>>:
  match remaining:
    case Nil{}: indexed
    case +head <> tail: indexToolValues(P, tail, M.set(T.Tool<P>, indexed, toolName(P, head), head))

def unequal(result: Declaration.DeclarationResult<Bool>) -> Declaration.DeclarationResult<Bool>:
  match result:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{same}: Declaration.Success{Bool.not(same)}

def compareIndexed(existing: T.Tool<Schema.Value>, item: T.Tool<Schema.Value>, existingFirst: Bool) -> Declaration.DeclarationResult<Bool>:
  match existingFirst:
    case True{}: unequal(declarationsEqual(existing, item))
    case False{}: unequal(declarationsEqual(item, existing))

def changedAgainst(existing: Maybe<&2, T.Tool<Schema.Value>>, item: T.Tool<Schema.Value>, existingFirst: Bool) -> Declaration.DeclarationResult<Bool>:
  match existing:
    case None{}: Declaration.Success{True{}}
    case Some{value}: compareIndexed(value, item, existingFirst)

def retainChanged(item: T.Tool<Schema.Value>, selected: List<&2, T.Tool<Schema.Value>>, changed: Declaration.DeclarationResult<Bool>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>:
  match changed:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{True{}}: Declaration.Success{item <> selected}
    case Declaration.Success{False{}}: Declaration.Success{selected}

# Keep duplicates and source order. The maps are lookup indexes, not the lists
# returned by filter. Complete filtering before projecting any added schemas.
def selectChanged(remaining: List<&2, T.Tool<Schema.Value>>, +indexed: M.OrderedMap<T.Tool<Schema.Value>>, +existingFirst: Bool, state: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>:
  match remaining state:
    case _ Declaration.Failure{error}: Declaration.Failure{error}
    case Nil{} Declaration.Success{selected}: Declaration.Success{List.reverse(&2, T.Tool<Schema.Value>, selected)}
    case +head <> tail Declaration.Success{selected}:
      selectChanged(tail, indexed, existingFirst, retainChanged(head, selected, changedAgainst(M.get(T.Tool<Schema.Value>, indexed, toolName(Schema.Value, head)), head, existingFirst)))

def retainDeclaration(selected: List<&2, T.Tool<Schema.Value>>, result: Declaration.DeclarationResult<T.Tool<Schema.Value>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>:
  match result:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{value}: Declaration.Success{value <> selected}

def projectAdded(remaining: List<&2, T.Tool<Schema.Value>>, state: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>:
  match remaining state:
    case _ Declaration.Failure{error}: Declaration.Failure{error}
    case Nil{} Declaration.Success{selected}: Declaration.Success{List.reverse(&2, T.Tool<Schema.Value>, selected)}
    case head <> tail Declaration.Success{selected}: projectAdded(tail, retainDeclaration(selected, toToolDeclaration(head)))

def projectSelected(selected: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>:
  match selected:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: projectAdded(values, Declaration.Success{Nil{}})

def toolReferences(-P: Data, values: List<&2, T.Tool<P>>) -> List<&2, T.ToolReference>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: T.ToolReference{toolName(P, head)} <> toolReferences(P, tail)

def finishRemoved(added: List<&2, T.Tool<Schema.Value>>, removed: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value>>:
  match removed:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: Declaration.Success{ToolStateChanges{added, toolReferences(Schema.Value, values)}}

def finishAdded(previous: List<&2, T.Tool<Schema.Value>>, currentIndex: M.OrderedMap<T.Tool<Schema.Value>>, added: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value>>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value>>:
  match added:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: finishRemoved(values, selectChanged(previous, currentIndex, False{}, Declaration.Success{Nil{}}))

def getToolStateChanges(+previous: List<&2, T.Tool<Schema.Value>>, +current: List<&2, T.Tool<Schema.Value>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value>>:
  previousIndex = indexToolValues(Schema.Value, previous, M.new(T.Tool<Schema.Value>))
  currentIndex = indexToolValues(Schema.Value, current, M.new(T.Tool<Schema.Value>))
  finishAdded(previous, currentIndex, projectSelected(selectChanged(current, previousIndex, True{}, Declaration.Success{Nil{}})))

type RedefinitionState is Data:
  Definitions{tools: M.OrderedMap<T.Tool<Schema.Value>>}
  Redefined{}
  RedefinitionFailure{error: Declaration.DeclarationError}

def retainDefinition(tools: M.OrderedMap<T.Tool<Schema.Value>>, name: String, reference: T.Tool<Schema.Value>, equal: Declaration.DeclarationResult<Bool>) -> RedefinitionState:
  match equal:
    case Declaration.Failure{error}: RedefinitionFailure{error}
    case Declaration.Success{False{}}: Redefined{}
    case Declaration.Success{True{}}: Definitions{M.set(T.Tool<Schema.Value>, tools, name, reference)}

def compareDefinition(previous: Maybe<&2, T.Tool<Schema.Value>>, current: T.Tool<Schema.Value>, reference: T.Tool<Schema.Value>, name: String, tools: M.OrderedMap<T.Tool<Schema.Value>>) -> RedefinitionState:
  match previous:
    case None{}: Definitions{M.set(T.Tool<Schema.Value>, tools, name, reference)}
    case Some{value}:
      previousTool = {value : T.Tool<Schema.Value>}
      retainDefinition(tools, name, reference, declarationsEqual(previousTool, current))

def inspectDefinition(+reference: T.Tool<Schema.Value>, +tools: M.OrderedMap<T.Tool<Schema.Value>>) -> RedefinitionState:
  +current = {reference : T.Tool<Schema.Value>}
  +name = {toolName(Schema.Value, current) : String}
  compareDefinition(M.get(T.Tool<Schema.Value>, tools, name), current, reference, name, tools)

def inspectDefinitions(remaining: List<&2, T.Tool<Schema.Value>>, state: RedefinitionState) -> RedefinitionState:
  match remaining state:
    case _ Redefined{}: Redefined{}
    case _ RedefinitionFailure{error}: RedefinitionFailure{error}
    case Nil{} state: state
    case head <> tail Definitions{tools}:
      updated = {inspectDefinition(head, tools) : RedefinitionState}
      inspectDefinitions(tail, updated)

def messageDefinitions(message: T.SystemMessage<Schema.Value>, tools: M.OrderedMap<T.Tool<Schema.Value>>) -> RedefinitionState:
  match message:
    case T.SystemMessage{_, _, added, _, _}: inspectDefinitions(listValue(T.Tool<Schema.Value>, added), Definitions{tools})

# Retain live tool references, ignore removals, and stop immediately after a
# changed same-name definition. A first declaration never serializes its schema.
def scanRedefinitions(-A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<Schema.Value, A, G, H>>, state: RedefinitionState) -> Declaration.DeclarationResult<Bool>:
  match messages state:
    case _ Redefined{}: Declaration.Success{True{}}
    case _ RedefinitionFailure{error}: Declaration.Failure{error}
    case Nil{} Definitions{_}: Declaration.Success{False{}}
    case T.System{reference} <> rest Definitions{tools}:
      message = {reference : T.SystemMessage<Schema.Value>}
      updated = {messageDefinitions(message, tools) : RedefinitionState}
      scanRedefinitions(A, G, H, rest, updated)
    case _ <> rest state: scanRedefinitions(A, G, H, rest, state)

def hasToolRedefinitions(-A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<Schema.Value, A, G, H>>) -> Declaration.DeclarationResult<Bool>:
  scanRedefinitions(A, G, H, messages, Definitions{M.new(T.Tool<Schema.Value>)})
