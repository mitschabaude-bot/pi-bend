import Base
import ../types.bend as T
import ./text.bend as Text
import ./tool-declaration.bend as Declaration
import ../../../runtime/src/schema-value.bend as Schema
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/ordered-map.bend as M
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/f64.bend as Number

# Initial normalization from transcript.ts. It does not implicitly replay
# existing system messages; the replay operations below remain separate.
def promptValue(prompt: Maybe<&2, String>) -> String:
  match prompt:
    case None{}: ""
    case Some{value}: value

def nonEmptyTools(-P: Data, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>:
  match tools:
    case None{}: None{}
    case Some{Nil{}}: None{}
    case Some{head <> tail}: Some{head <> tail}

def hasTools(-P: Data, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> Bool:
  match tools:
    case None{}: False{}
    case Some{_}: True{}

def createInitial(-P: Data, needed: Bool, prompt: String, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  match needed:
    case False{}: IO.pure(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>, None{})
    case True{}:
      do IO<Maybe<&2, Ref.Ref<T.SystemMessage<P>>>>:
        value : Ref.Ref<T.SystemMessage<P>> <- Ref.new(T.SystemMessage<P>, T.SystemMessage{T.SystemText{prompt}, None{}, tools, None{}, Number.fromU32(0)})
        return Some{value}

def createInitialSystemMessage(-P: Data, systemPrompt: Maybe<&2, String>, tools: Maybe<&2, List<&2, Ref.Ref<T.Tool<P>>>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  +prompt = promptValue(systemPrompt)
  +available = nonEmptyTools(P, tools)
  createInitial(P, Bool.not(String.is_empty(prompt)) || hasTools(P, available), prompt, available)

def prependInitial(-P: Data, -A: Data, -G: Data, -H: Data, initial: Maybe<&2, Ref.Ref<T.SystemMessage<P>>>, messages: List<&2, T.Message<P, A, G, H>>) -> T.TranscriptContext<P, A, G, H>:
  match initial:
    case None{}: T.TranscriptContext{messages}
    case Some{value}: T.TranscriptContext{T.System{value} <> messages}

def normalizeContext(-P: Data, -A: Data, -G: Data, -H: Data, context: T.Context<P, A, G, H>) -> IO(T.TranscriptContext<P, A, G, H>):
  match context:
    case T.Context{systemPrompt, messages, tools}:
      do IO<T.TranscriptContext<P, A, G, H>>:
        initial : Maybe<&2, Ref.Ref<T.SystemMessage<P>>> <- createInitialSystemMessage(P, systemPrompt, tools)
        return prependInitial(P, A, G, H, initial, messages)

def getInitialSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> Maybe<&2, Ref.Ref<T.SystemMessage<P>>>:
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

def removeTools(-P: Data, removed: List<&2, T.ToolReference>, tools: M.OrderedMap<Ref.Ref<T.Tool<P>>>) -> M.OrderedMap<Ref.Ref<T.Tool<P>>>:
  match removed:
    case Nil{}: tools
    case T.ToolReference{name} <> rest: removeTools(P, rest, M.remove(Ref.Ref<T.Tool<P>>, tools, name))

def addTools(-P: Data, added: List<&2, Ref.Ref<T.Tool<P>>>, tools: M.OrderedMap<Ref.Ref<T.Tool<P>>>) -> IO(M.OrderedMap<Ref.Ref<T.Tool<P>>>):
  match added:
    case Nil{}: IO.pure(M.OrderedMap<Ref.Ref<T.Tool<P>>>, tools)
    case +head <> rest:
      do IO<M.OrderedMap<Ref.Ref<T.Tool<P>>>>:
        value : T.Tool<P> <- Ref.read(T.Tool<P>, head)
        addTools(P, rest, M.set(Ref.Ref<T.Tool<P>>, tools, toolName(P, value), head))

def listValue(-V: Data, value: Maybe<&2, List<&2, V>>) -> List<&2, V>:
  match value:
    case None{}: Nil{}
    case Some{items}: items

def replayTools(-P: Data, message: T.SystemMessage<P>, tools: M.OrderedMap<Ref.Ref<T.Tool<P>>>, includeRemoved: Bool) -> IO(M.OrderedMap<Ref.Ref<T.Tool<P>>>):
  match message:
    case T.SystemMessage{_, _, added, removed, _}:
      addTools(P, listValue(Ref.Ref<T.Tool<P>>, added), removeTools(P, Bool.pick(List<&2, T.ToolReference>, includeRemoved, listValue(T.ToolReference, removed), Nil{}), tools))

def collectTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, tools: M.OrderedMap<Ref.Ref<T.Tool<P>>>, +includeRemoved: Bool) -> IO(List<&2, Ref.Ref<T.Tool<P>>>):
  match messages:
    case Nil{}: IO.pure(List<&2, Ref.Ref<T.Tool<P>>>, M.values(Ref.Ref<T.Tool<P>>, tools))
    case T.System{reference} <> rest:
      do IO<List<&2, Ref.Ref<T.Tool<P>>>>:
        message : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, reference)
        updated : M.OrderedMap<Ref.Ref<T.Tool<P>>> <- replayTools(P, message, tools, includeRemoved)
        collectTools(P, A, G, H, rest, updated, includeRemoved)
    case _ <> rest: collectTools(P, A, G, H, rest, tools, includeRemoved)

def getCurrentTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> IO(List<&2, Ref.Ref<T.Tool<P>>>):
  collectTools(P, A, G, H, messages, M.new(Ref.Ref<T.Tool<P>>), True{})

def getDeclaredTools(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> IO(List<&2, Ref.Ref<T.Tool<P>>>):
  collectTools(P, A, G, H, messages, M.new(Ref.Ref<T.Tool<P>>), False{})

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

def replayMessages(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, state: ReplayState) -> IO(ReplayState):
  match messages:
    case Nil{}: IO.pure(ReplayState, state)
    case T.System{reference} <> rest:
      do IO<ReplayState>:
        message : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, reference)
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

def finishReplay(-P: Data, state: ReplayState, tools: List<&2, Ref.Ref<T.Tool<P>>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  match state tools:
    case ReplayState{_, _, None{}} Nil{}: IO.pure(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>, None{})
    case ReplayState{content, sections, timestamp} tools:
      do IO<Maybe<&2, Ref.Ref<T.SystemMessage<P>>>>:
        message : Ref.Ref<T.SystemMessage<P>> <- Ref.new(T.SystemMessage<P>, T.SystemMessage{T.SystemText{String.join(List.reverse(&2, String, content), "\n\n")}, optionalSections(R.entries(Maybe<&2, String>, sections)), nonEmptyTools(P, Some{tools}), None{}, timestampValue(timestamp)})
        return Some{message}

def getCurrentSystemMessage(-P: Data, -A: Data, -G: Data, -H: Data, +messages: List<&2, T.Message<P, A, G, H>>) -> IO(Maybe<&2, Ref.Ref<T.SystemMessage<P>>>):
  do IO<Maybe<&2, Ref.Ref<T.SystemMessage<P>>>>:
    state : ReplayState <- replayMessages(P, A, G, H, messages, ReplayState{Nil{}, R.new(Maybe<&2, String>), None{}})
    tools : List<&2, Ref.Ref<T.Tool<P>>> <- getCurrentTools(P, A, G, H, messages)
    finishReplay(P, state, tools)

# The temporary replayed message belongs to this helper; do not leak its Ref.
def currentPrompt(-P: Data, message: Maybe<&2, Ref.Ref<T.SystemMessage<P>>>) -> IO(String):
  match message:
    case None{}: IO.pure(String, "")
    case Some{reference}:
      do IO<String>:
        value : T.SystemMessage<P> <- Ref.dispose(T.SystemMessage<P>, reference)
        return Text.renderComplete(P, value)

def getCurrentSystemPrompt(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> IO(String):
  do IO<String>:
    message : Maybe<&2, Ref.Ref<T.SystemMessage<P>>> <- getCurrentSystemMessage(P, A, G, H, messages)
    currentPrompt(P, message)

def withoutSystemMessages(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> List<&2, T.Message<P, A, G, H>>:
  match messages:
    case Nil{}: Nil{}
    case T.System{_} <> rest: withoutSystemMessages(P, A, G, H, rest)
    case head <> rest: head <> withoutSystemMessages(P, A, G, H, rest)

def collapseSystemMessages(-P: Data, -A: Data, -G: Data, -H: Data, context: T.TranscriptContext<P, A, G, H>) -> IO(T.TranscriptContext<P, A, G, H>):
  match context:
    case T.TranscriptContext{+messages}:
      do IO<T.TranscriptContext<P, A, G, H>>:
        head : Maybe<&2, Ref.Ref<T.SystemMessage<P>>> <- getCurrentSystemMessage(P, A, G, H, messages)
        return prependInitial(P, A, G, H, head, withoutSystemMessages(P, A, G, H, messages))

def resolveTranscript(-P: Data, -A: Data, -G: Data, -H: Data, context: T.TranscriptContext<P, A, G, H>, supportsMidConvoSystemMessages: Maybe<&2, Bool>) -> IO(T.TranscriptContext<P, A, G, H>):
  match supportsMidConvoSystemMessages:
    case Some{True{}}: IO.pure(T.TranscriptContext<P, A, G, H>, context)
    case _: collapseSystemMessages(P, A, G, H, context)

def present(-V: Data, value: Maybe<&2, V>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def addNames(-P: Data, added: List<&2, Ref.Ref<T.Tool<P>>>, +seen: M.OrderedMap<Unit>) -> IO(M.OrderedMap<Unit> & Bool):
  match added:
    case Nil{}: IO.pure(M.OrderedMap<Unit> & Bool, (seen, False{}))
    case reference <> rest:
      do IO<M.OrderedMap<Unit> & Bool>:
        tool : T.Tool<P> <- Ref.read(T.Tool<P>, reference)
        +name : String = toolName(P, tool)
        Bool.pick(IO(M.OrderedMap<Unit> & Bool), present(Unit, M.get(Unit, seen, name)), IO.pure(M.OrderedMap<Unit> & Bool, (seen, True{})), addNames(P, rest, M.set(Unit, seen, name, Unit{})))

def nameChanges(-P: Data, message: T.SystemMessage<P>, seen: M.OrderedMap<Unit>) -> IO(M.OrderedMap<Unit> & Bool):
  match message:
    case T.SystemMessage{_, _, _, Some{_ <> _}, _}: IO.pure(M.OrderedMap<Unit> & Bool, (seen, True{}))
    case T.SystemMessage{_, _, added, _, _}: addNames(P, listValue(Ref.Ref<T.Tool<P>>, added), seen)

def scanNonAdditive(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, state: M.OrderedMap<Unit> & Bool) -> IO(Bool):
  match messages state:
    case _ Tuple{_, True{}}: IO.pure(Bool, True{})
    case Nil{} Tuple{_, False{}}: IO.pure(Bool, False{})
    case T.System{reference} <> rest Tuple{seen, False{}}:
      do IO<Bool>:
        message : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, reference)
        updated : M.OrderedMap<Unit> & Bool <- nameChanges(P, message, seen)
        scanNonAdditive(P, A, G, H, rest, updated)
    case _ <> rest state: scanNonAdditive(P, A, G, H, rest, state)

def hasNonAdditiveToolChanges(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>) -> IO(Bool):
  scanNonAdditive(P, A, G, H, messages, (M.new(Unit), False{}))

type TranscriptTools<-P: Data> is Data:
  TranscriptTools{requestTools: List<&2, Ref.Ref<T.Tool<P>>>, anchorsAdditions: Bool}

def initialToolsValue(-P: Data, message: T.SystemMessage<P>) -> List<&2, Ref.Ref<T.Tool<P>>>:
  match message:
    case T.SystemMessage{_, _, added, _, _}: listValue(Ref.Ref<T.Tool<P>>, added)

def initialTools(-P: Data, message: Maybe<&2, Ref.Ref<T.SystemMessage<P>>>) -> IO(TranscriptTools<P>):
  match message:
    case None{}: IO.pure(TranscriptTools<P>, TranscriptTools{Nil{}, True{}})
    case Some{reference}:
      do IO<TranscriptTools<P>>:
        value : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, reference)
        return TranscriptTools{initialToolsValue(P, value), True{}}

def resolveToolMode(-P: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<P, A, G, H>>, anchors: Bool) -> IO(TranscriptTools<P>):
  match anchors:
    case True{}: initialTools(P, getInitialSystemMessage(P, A, G, H, messages))
    case False{}:
      do IO<TranscriptTools<P>>:
        tools : List<&2, Ref.Ref<T.Tool<P>>> <- getCurrentTools(P, A, G, H, messages)
        return TranscriptTools{tools, False{}}

def resolveTranscriptTools(-P: Data, -A: Data, -G: Data, -H: Data, +messages: List<&2, T.Message<P, A, G, H>>, supportsToolAdditions: Bool) -> IO(TranscriptTools<P>):
  match supportsToolAdditions:
    case False{}: resolveToolMode(P, A, G, H, messages, False{})
    case True{}:
      do IO<TranscriptTools<P>>:
        nonAdditive : Bool <- hasNonAdditiveToolChanges(P, A, G, H, messages)
        resolveToolMode(P, A, G, H, messages, Bool.not(nonAdditive))

# Schema-data entry points. The TypeBox static-schema adapter is still pending.
def toToolDeclaration(-Metadata: Data, tool: T.Tool<Schema.Value<Metadata>>) -> Declaration.DeclarationResult<T.Tool<Schema.Value<Metadata>>>:
  Declaration.toToolDeclaration(Metadata, tool)

def declarationsEqual(-Metadata: Data, left: T.Tool<Schema.Value<Metadata>>, right: T.Tool<Schema.Value<Metadata>>) -> Declaration.DeclarationResult<Bool>:
  Declaration.declarationsEqual(Metadata, left, right)

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

def compareIndexed(-Metadata: Data, existing: T.Tool<Schema.Value<Metadata>>, item: T.Tool<Schema.Value<Metadata>>, existingFirst: Bool) -> Declaration.DeclarationResult<Bool>:
  match existingFirst:
    case True{}: unequal(declarationsEqual(Metadata, existing, item))
    case False{}: unequal(declarationsEqual(Metadata, item, existing))

def changedAgainst(-Metadata: Data, existing: Maybe<&2, T.Tool<Schema.Value<Metadata>>>, item: T.Tool<Schema.Value<Metadata>>, existingFirst: Bool) -> Declaration.DeclarationResult<Bool>:
  match existing:
    case None{}: Declaration.Success{True{}}
    case Some{value}: compareIndexed(Metadata, value, item, existingFirst)

def retainChanged(-Metadata: Data, item: T.Tool<Schema.Value<Metadata>>, selected: List<&2, T.Tool<Schema.Value<Metadata>>>, changed: Declaration.DeclarationResult<Bool>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>:
  match changed:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{True{}}: Declaration.Success{item <> selected}
    case Declaration.Success{False{}}: Declaration.Success{selected}

# Keep duplicates and source order. The maps are lookup indexes, not the lists
# returned by filter. Complete filtering before projecting any added schemas.
def selectChanged(-Metadata: Data, remaining: List<&2, T.Tool<Schema.Value<Metadata>>>, +indexed: M.OrderedMap<T.Tool<Schema.Value<Metadata>>>, +existingFirst: Bool, state: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>:
  match remaining state:
    case _ Declaration.Failure{error}: Declaration.Failure{error}
    case Nil{} Declaration.Success{selected}: Declaration.Success{List.reverse(&2, T.Tool<Schema.Value<Metadata>>, selected)}
    case +head <> tail Declaration.Success{selected}:
      selectChanged(Metadata, tail, indexed, existingFirst, retainChanged(Metadata, head, selected, changedAgainst(Metadata, M.get(T.Tool<Schema.Value<Metadata>>, indexed, toolName(Schema.Value<Metadata>, head)), head, existingFirst)))

def retainDeclaration(-Metadata: Data, selected: List<&2, T.Tool<Schema.Value<Metadata>>>, result: Declaration.DeclarationResult<T.Tool<Schema.Value<Metadata>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>:
  match result:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{value}: Declaration.Success{value <> selected}

def projectAdded(-Metadata: Data, remaining: List<&2, T.Tool<Schema.Value<Metadata>>>, state: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>:
  match remaining state:
    case _ Declaration.Failure{error}: Declaration.Failure{error}
    case Nil{} Declaration.Success{selected}: Declaration.Success{List.reverse(&2, T.Tool<Schema.Value<Metadata>>, selected)}
    case head <> tail Declaration.Success{selected}: projectAdded(Metadata, tail, retainDeclaration(Metadata, selected, toToolDeclaration(Metadata, head)))

def projectSelected(-Metadata: Data, selected: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>) -> Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>:
  match selected:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: projectAdded(Metadata, values, Declaration.Success{Nil{}})

def toolReferences(-P: Data, values: List<&2, T.Tool<P>>) -> List<&2, T.ToolReference>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: T.ToolReference{toolName(P, head)} <> toolReferences(P, tail)

def finishRemoved(-Metadata: Data, added: List<&2, T.Tool<Schema.Value<Metadata>>>, removed: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value<Metadata>>>:
  match removed:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: Declaration.Success{ToolStateChanges{added, toolReferences(Schema.Value<Metadata>, values)}}

def finishAdded(-Metadata: Data, previous: List<&2, T.Tool<Schema.Value<Metadata>>>, currentIndex: M.OrderedMap<T.Tool<Schema.Value<Metadata>>>, added: Declaration.DeclarationResult<List<&2, T.Tool<Schema.Value<Metadata>>>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value<Metadata>>>:
  match added:
    case Declaration.Failure{error}: Declaration.Failure{error}
    case Declaration.Success{values}: finishRemoved(Metadata, values, selectChanged(Metadata, previous, currentIndex, False{}, Declaration.Success{Nil{}}))

def getToolStateChanges(-Metadata: Data, +previous: List<&2, T.Tool<Schema.Value<Metadata>>>, +current: List<&2, T.Tool<Schema.Value<Metadata>>>) -> Declaration.DeclarationResult<ToolStateChanges<Schema.Value<Metadata>>>:
  previousIndex = indexToolValues(Schema.Value<Metadata>, previous, M.new(T.Tool<Schema.Value<Metadata>>))
  currentIndex = indexToolValues(Schema.Value<Metadata>, current, M.new(T.Tool<Schema.Value<Metadata>>))
  finishAdded(Metadata, previous, currentIndex, projectSelected(Metadata, selectChanged(Metadata, current, previousIndex, True{}, Declaration.Success{Nil{}})))

type RedefinitionState<-Metadata: Data> is Data:
  Definitions{tools: M.OrderedMap<Ref.Ref<T.Tool<Schema.Value<Metadata>>>>}
  Redefined{}
  RedefinitionFailure{error: Declaration.DeclarationError}

def retainDefinition(-Metadata: Data, tools: M.OrderedMap<Ref.Ref<T.Tool<Schema.Value<Metadata>>>>, name: String, reference: Ref.Ref<T.Tool<Schema.Value<Metadata>>>, equal: Declaration.DeclarationResult<Bool>) -> RedefinitionState<Metadata>:
  match equal:
    case Declaration.Failure{error}: RedefinitionFailure{error}
    case Declaration.Success{False{}}: Redefined{}
    case Declaration.Success{True{}}: Definitions{M.set(Ref.Ref<T.Tool<Schema.Value<Metadata>>>, tools, name, reference)}

def compareDefinition(-Metadata: Data, previous: Maybe<&2, Ref.Ref<T.Tool<Schema.Value<Metadata>>>>, current: T.Tool<Schema.Value<Metadata>>, reference: Ref.Ref<T.Tool<Schema.Value<Metadata>>>, name: String, tools: M.OrderedMap<Ref.Ref<T.Tool<Schema.Value<Metadata>>>>) -> IO(RedefinitionState<Metadata>):
  match previous:
    case None{}: IO.pure(RedefinitionState<Metadata>, Definitions{M.set(Ref.Ref<T.Tool<Schema.Value<Metadata>>>, tools, name, reference)})
    case Some{value}:
      do IO<RedefinitionState<Metadata>>:
        previousTool : T.Tool<Schema.Value<Metadata>> <- Ref.read(T.Tool<Schema.Value<Metadata>>, value)
        return retainDefinition(Metadata, tools, name, reference, declarationsEqual(Metadata, previousTool, current))

def inspectDefinition(-Metadata: Data, +reference: Ref.Ref<T.Tool<Schema.Value<Metadata>>>, +tools: M.OrderedMap<Ref.Ref<T.Tool<Schema.Value<Metadata>>>>) -> IO(RedefinitionState<Metadata>):
  do IO<RedefinitionState<Metadata>>:
    +current : T.Tool<Schema.Value<Metadata>> <- Ref.read(T.Tool<Schema.Value<Metadata>>, reference)
    +name : String = toolName(Schema.Value<Metadata>, current)
    compareDefinition(Metadata, M.get(Ref.Ref<T.Tool<Schema.Value<Metadata>>>, tools, name), current, reference, name, tools)

def inspectDefinitions(-Metadata: Data, remaining: List<&2, Ref.Ref<T.Tool<Schema.Value<Metadata>>>>, state: RedefinitionState<Metadata>) -> IO(RedefinitionState<Metadata>):
  match remaining state:
    case _ Redefined{}: IO.pure(RedefinitionState<Metadata>, Redefined{})
    case _ RedefinitionFailure{error}: IO.pure(RedefinitionState<Metadata>, RedefinitionFailure{error})
    case Nil{} state: IO.pure(RedefinitionState<Metadata>, state)
    case head <> tail Definitions{tools}:
      do IO<RedefinitionState<Metadata>>:
        updated : RedefinitionState<Metadata> <- inspectDefinition(Metadata, head, tools)
        inspectDefinitions(Metadata, tail, updated)

def messageDefinitions(-Metadata: Data, message: T.SystemMessage<Schema.Value<Metadata>>, tools: M.OrderedMap<Ref.Ref<T.Tool<Schema.Value<Metadata>>>>) -> IO(RedefinitionState<Metadata>):
  match message:
    case T.SystemMessage{_, _, added, _, _}: inspectDefinitions(Metadata, listValue(Ref.Ref<T.Tool<Schema.Value<Metadata>>>, added), Definitions{tools})

# Retain live tool references, ignore removals, and stop immediately after a
# changed same-name definition. A first declaration never serializes its schema.
def scanRedefinitions(-Metadata: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<Schema.Value<Metadata>, A, G, H>>, state: RedefinitionState<Metadata>) -> IO(Declaration.DeclarationResult<Bool>):
  match messages state:
    case _ Redefined{}: IO.pure(Declaration.DeclarationResult<Bool>, Declaration.Success{True{}})
    case _ RedefinitionFailure{error}: IO.pure(Declaration.DeclarationResult<Bool>, Declaration.Failure{error})
    case Nil{} Definitions{_}: IO.pure(Declaration.DeclarationResult<Bool>, Declaration.Success{False{}})
    case T.System{reference} <> rest Definitions{tools}:
      do IO<Declaration.DeclarationResult<Bool>>:
        message : T.SystemMessage<Schema.Value<Metadata>> <- Ref.read(T.SystemMessage<Schema.Value<Metadata>>, reference)
        updated : RedefinitionState<Metadata> <- messageDefinitions(Metadata, message, tools)
        scanRedefinitions(Metadata, A, G, H, rest, updated)
    case _ <> rest state: scanRedefinitions(Metadata, A, G, H, rest, state)

def hasToolRedefinitions(-Metadata: Data, -A: Data, -G: Data, -H: Data, messages: List<&2, T.Message<Schema.Value<Metadata>, A, G, H>>) -> IO(Declaration.DeclarationResult<Bool>):
  scanRedefinitions(Metadata, A, G, H, messages, Definitions{M.new(Ref.Ref<T.Tool<Schema.Value<Metadata>>>)})
