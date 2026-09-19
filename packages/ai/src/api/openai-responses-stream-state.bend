import Base
import ../types.bend as T
import ./openai-responses-stream-content.bend as Content
import ./constrained-sampling.bend as Sampling
import ./transform-messages.bend as Transform
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Provider output indices and assistant content indices are distinct: items may
# arrive out of order, and replacing an output slot appends a new content block.
# Wire indices retain fixed-size binary64 values; sparse/large numeric keys
# must not allocate unary naturals in proportion to their magnitude.
type Slot is Data:
  Slot{outputIndex: F.F64, contentIndex: Nat, block: Content.Block}

type State<-G: Data> is Data:
  State{output: T.AssistantMessage<V.Value, G>, slots: List<&2, Slot>, reasoningBlocks: R.Record<Nat>, grammarProperties: R.Record<String>}

type ContentEvent is Data:
  Added{outputIndex: F.F64, item: Content.OutputItem}
  Changed{outputIndex: F.F64, input: Content.Input}

type Update<-G: Data> is Data:
  Update{state: State<G>, events: List<&2, T.AssistantMessageEvent<V.Value, G>>, error: Maybe<&2, Sampling.Error>}

def create(-G: Data, output: T.AssistantMessage<V.Value, G>, grammarProperties: R.Record<String>) -> State<G>:
  State{output, Nil{}, R.new(Nat), grammarProperties}

def output(-G: Data, state: State<G>) -> T.AssistantMessage<V.Value, G>:
  match state:
    case State{value, _, _, _}: value

def blocks(-G: Data, message: T.AssistantMessage<V.Value, G>) -> List<&2, T.AssistantContent<V.Value>>:
  match message:
    case T.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: content

def count(values: List<&2, T.AssistantContent<V.Value>>) -> Nat:
  match values:
    case Nil{}: 0n
    case _ <> rest: 1n + count(rest)

def numericIndex(index: Nat) -> F.F64:
  match index:
    case 0n: F.fromU32(0)
    case 1n+rest: F.add(F.fromU32(1), numericIndex(rest))

def find(slots: List<&2, Slot>, +index: F.F64) -> Maybe<&2, Slot>:
  match slots:
    case Nil{}: None{}
    case Slot{+key, position, block} <> rest: Bool.pick(Maybe<&2, Slot>, V.equal(V.Number{key}, V.Number{index}), Some{Slot{key, position, block}}, find(rest, index))

def remove(slots: List<&2, Slot>, +index: F.F64) -> List<&2, Slot>:
  match slots:
    case Nil{}: Nil{}
    case Slot{+key, position, block} <> rest:
      +tail = remove(rest, index)
      Bool.pick(List<&2, Slot>, V.equal(V.Number{key}, V.Number{index}), tail, Slot{key, position, block} <> tail)

# Only the internal append position may reach Nil; all other positions came
# from an existing slot. Replacing a block never mutates retained snapshots.
def replace(values: List<&2, T.AssistantContent<V.Value>>, index: Nat, value: T.AssistantContent<V.Value>) -> List<&2, T.AssistantContent<V.Value>>:
  match values index:
    case Nil{} _: value <> Nil{}
    case _ <> rest 0n: value <> rest
    case head <> rest 1n+tail: head <> replace(rest, tail, value)

def withBlock(-G: Data, +message: T.AssistantMessage<V.Value, G>, index: Nat, value: T.AssistantContent<V.Value>) -> T.AssistantMessage<V.Value, G>:
  Transform.withContent(V.Value, G, message, replace(blocks(G, message), index, value))

def stop(-G: Data, message: T.AssistantMessage<V.Value, G>) -> T.AssistantMessage<V.Value, G>:
  match message:
    case T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, _, deferred, error, raw, endTurn, time}:
      T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, T.Stop{}, deferred, error, raw, endTurn, time}

def phase(-G: Data, state: State<G>, item: Content.OutputItem) -> State<G>:
  match state item:
    case State{message, slots, reasoning, properties} Content.MessageItem{_, Some{T.FinalAnswer{}}, _}: State{stop(G, message), slots, reasoning, properties}
    case other _: other

def startedEvent(-G: Data, index: F.F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{_}: T.TextStart{index, message}
    case T.AssistantThinking{_}: T.ThinkingStart{index, message}
    case T.AssistantToolCall{_}: T.ToolcallStart{index, message}

def deltaEvent(-G: Data, index: F.F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>, delta: String) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{_}: T.TextDelta{index, delta, message}
    case T.AssistantThinking{_}: T.ThinkingDelta{index, delta, message}
    case T.AssistantToolCall{_}: T.ToolcallDelta{index, delta, message}

def endedEvent(-G: Data, index: F.F64, message: T.AssistantMessage<V.Value, G>, content: T.AssistantContent<V.Value>) -> T.AssistantMessageEvent<V.Value, G>:
  match content:
    case T.AssistantText{T.TextContent{text, _}}: T.TextEnd{index, text, message}
    case T.AssistantThinking{T.ThinkingContent{text, _, _}}: T.ThinkingEnd{index, text, message}
    case T.AssistantToolCall{value}: T.ToolcallEnd{index, value, message}

def signalContent(signal: Content.Signal) -> T.AssistantContent<V.Value>:
  match signal:
    case Content.Started{value}: value
    case Content.Delta{value, _}: value
    case Content.Ended{value}: value

def event(-G: Data, index: Nat, message: T.AssistantMessage<V.Value, G>, signal: Content.Signal) -> T.AssistantMessageEvent<V.Value, G>:
  match signal:
    case Content.Started{value}: startedEvent(G, numericIndex(index), message, value)
    case Content.Delta{value, delta}: deltaEvent(G, numericIndex(index), message, value, delta)
    case Content.Ended{value}: endedEvent(G, numericIndex(index), message, value)

type Emission<-G: Data> is Data:
  Emission{output: T.AssistantMessage<V.Value, G>, reversed: List<&2, T.AssistantMessageEvent<V.Value, G>>}

def emitOne(-G: Data, +index: Nat, current: Emission<G>, +signal: Content.Signal) -> Emission<G>:
  match current:
    case Emission{message, reversed}:
      +next = withBlock(G, message, index, signalContent(signal))
      Emission{next, event(G, index, next, signal) <> reversed}

def emit(-G: Data, signals: List<&2, Content.Signal>, +index: Nat, current: Emission<G>) -> Emission<G>:
  match signals:
    case Nil{}: current
    case head <> tail: emit(G, tail, index, emitOne(G, index, current, head))

def slotsAfter(slots: List<&2, Slot>, +key: F.F64, position: Nat, block: Content.Block, finished: Bool) -> List<&2, Slot>:
  match finished:
    case True{}: remove(slots, key)
    case False{}: Slot{key, position, block} <> remove(slots, key)

def reasoningAfter(refs: R.Record<Nat>, position: Nat, finished: Bool, item: Maybe<&2, Content.OutputItem>) -> R.Record<Nat>:
  match finished item:
    case True{} Some{Content.ReasoningItem{fields}}: R.set(Nat, refs, Content.textField(R.get(V.Value, fields, "id")), position)
    case _ _: refs

def committed(-G: Data, slots: List<&2, Slot>, refs: R.Record<Nat>, properties: R.Record<String>, +position: Nat, block: Content.Block, emission: Emission<G>) -> Update<G>:
  match emission:
    case Emission{message, reversed}: Update{State{withBlock(G, message, position, Content.content(block)), slots, refs, properties}, List.reverse(&2, T.AssistantMessageEvent<V.Value, G>, reversed), None{}}

def apply(-G: Data, state: State<G>, key: F.F64, +position: Nat, item: Maybe<&2, Content.OutputItem>, update: Content.Update) -> Update<G>:
  match state update:
    case State{message, slots, refs, properties} Content.Update{+block, signals, +finished}:
      committed(G, slotsAfter(slots, key, position, block, finished), reasoningAfter(refs, position, finished, item), properties, position, block, emit(G, signals, position, Emission{message, Nil{}}))

def unchanged(-G: Data, state: State<G>) -> Update<G>: Update{state, Nil{}, None{}}

def created(-G: Data, +state: State<G>, key: F.F64, value: Maybe<&2, Content.Update>) -> Update<G>:
  match value:
    case None{}: unchanged(G, state)
    case Some{update}: apply(G, state, key, count(blocks(G, output(G, state))), None{}, update)

def add(-G: Data, state: State<G>, key: F.F64, item: Content.OutputItem) -> Update<G>:
  match state:
    case State{message, slots, refs, +properties}: created(G, State{message, slots, refs, properties}, key, Content.start(item, properties))

def applied(-G: Data, state: State<G>, key: F.F64, position: Nat, item: Maybe<&2, Content.OutputItem>, result: Result<&2, &2, Sampling.Error, Content.Update>) -> Update<G>:
  match result:
    case Fail{error}: Update{state, Nil{}, Some{error}}
    case Done{update}: apply(G, state, key, position, item, update)

def doneItem(input: Content.Input) -> Maybe<&2, Content.OutputItem>:
  match input:
    case Content.ItemDone{item}: Some{item}
    case _: None{}

def changeExisting(-G: Data, state: State<G>, slot: Maybe<&2, Slot>, +input: Content.Input) -> Update<G>:
  match slot:
    case None{}: unchanged(G, state)
    case Some{Slot{key, position, block}}: applied(G, state, key, position, doneItem(input), Content.step(block, input))

def change(-G: Data, state: State<G>, key: F.F64, input: Content.Input) -> Update<G>:
  match state:
    case State{message, +slots, refs, properties}: changeExisting(G, State{message, slots, refs, properties}, find(slots, key), input)

def prependEvents(-G: Data, earlier: List<&2, T.AssistantMessageEvent<V.Value, G>>, update: Update<G>) -> Update<G>:
  match update:
    case Update{state, events, error}: Update{state, List.append(&2, T.AssistantMessageEvent<V.Value, G>, earlier, events), error}

def finishCreated(-G: Data, key: F.F64, item: Content.OutputItem, update: Update<G>) -> Update<G>:
  match update:
    case Update{state, events, _}: prependEvents(G, events, change(G, state, key, Content.ItemDone{item}))

def finish(-G: Data, state: State<G>, +key: F.F64, +item: Content.OutputItem, slot: Maybe<&2, Slot>) -> Update<G>:
  match slot:
    case None{}: finishCreated(G, key, item, add(G, state, key, item))
    case some: changeExisting(G, state, some, Content.ItemDone{item})

def step(-G: Data, state: State<G>, input: ContentEvent) -> Update<G>:
  match state input:
    case value Added{key, +item}: add(G, phase(G, value, item), key, item)
    case State{message, +slots, refs, properties} Changed{+key, Content.ItemDone{+item}}: finish(G, phase(G, State{message, slots, refs, properties}, item), key, item, find(slots, key))
    case value Changed{key, input}: change(G, value, key, input)
