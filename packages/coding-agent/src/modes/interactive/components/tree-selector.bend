import Base
import ../../../../../agent/src/types.bend as Agent
import ../../../../../ai/src/types.bend as Ai
import ../../../../../runtime/src/text.bend as Text
import ../../../../../runtime/src/case-map.bend as CaseMap
import ../../../../../runtime/src/schema-value.bend as V
import ../../../../../tui/src/keybindings.bend as Bindings
import ../../../../../tui/src/keys.bend as Keys
import ../../../../../tui/src/utils.bend as Utils
import ../../../core/messages.bend as Messages
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../core/session-manager.bend as Tree
import ../../../core/tools/index.bend as Tools
import ../theme/theme.bend as Theme
import ../../../../../tui/src/components/input.bend as Input
import ../../../../../tui/src/word-navigation.bend as Word
import ../../../../../runtime/src/word-segmenter.bend as Segmenter
import ../../../../../runtime/src/date.bend as Date
import ./keybinding-hints.bend as Hints
import ../../../../../runtime/src/record.bend as R
import ../../../../../runtime/src/f64.bend as F
import ../../../../../ai/src/utils/json.bend as Json
import ../../../../../ai/src/utils/schema-json.bend as SchemaJson

# The selector keeps the session graph, rather than flattening it to an
# unrelated menu. Its visible rows retain branch connectors and the active
# path; the filter changes which entries are visible, not their IDs.
def Entry() -> Data: Tree.SessionEntry<Unit,Tools.ToolDetails,V.Value>
def Node() -> Data: Tree.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>

type Filter is Data: Default{} NoTools{} UserOnly{} LabeledOnly{} All{}
type Action is Data: Continue{} Cancel{} Chosen{id: String} Copied{text: Maybe<&2,String>} EditLabel{id: String,label: Maybe<&2,String>} LabelChanged{id: String,label: Maybe<&2,String>} InputError{cause: Word.Error}
type Row is Data:
  Row{node: Node(),prefix: String,connector: String,active: Bool}
type ToolCallInfo is Data: ToolCallInfo{name: String,arguments: V.Value}
type Graph is Data:
  Graph{entries: Map<&2,Maybe<&2,Row>>,indices: Map<&2,Maybe<&2,Nat>>,parents: Map<&2,Maybe<&2,String>>,children: Map<&2,List<&2,String>>,roots: List<&2,String>,calls: Map<&2,Maybe<&2,ToolCallInfo>>}
type TreeList is Data:
  TreeList{all: List<&2,Row>,visible: List<&2,Row>,selected: Nat,filter: Filter,search: String,leaf: Maybe<&2,String>,folded: List<&2,String>,height: Nat,lastSelectedId: Maybe<&2,String>,graph: Graph}

def rowEntry(row: Row) -> Entry():
  match row: case Row{Tree.SessionTreeNode{entry,_,_,_},_,_,_}: entry
def rowId(row: Row) -> String:
  Tree.baseId(Tree.entryBase(Unit,Tools.ToolDetails,V.Value,rowEntry(row)))
def rowParent(row: Row) -> Maybe<&2,String>:
  Tree.baseParent(Tree.entryBase(Unit,Tools.ToolDetails,V.Value,rowEntry(row)))
def blockText(blocks: List<&2,Ai.TextImageContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextImageText{Ai.TextContent{text,_}} <> rest: text ++ blockText(rest)
    case _ <> rest: blockText(rest)
def assistantText(blocks: List<&2,Ai.AssistantContent<V.Value>>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.AssistantText{Ai.TextContent{text,_}} <> rest: text ++ assistantText(rest)
    case _ <> rest: assistantText(rest)
def contentText(content: Ai.UserContent) -> String:
  match content:
    case Ai.UserText{text}: text
    case Ai.UserBlocks{blocks}: blockText(blocks)
def systemBlocks(blocks: List<&2,Ai.TextContent>) -> String:
  match blocks:
    case Nil{}: ""
    case Ai.TextContent{text,_} <> rest: text ++ systemBlocks(rest)
def systemText(content: Ai.SystemContent) -> String:
  match content:
    case Ai.SystemText{text}: text
    case Ai.SystemBlocks{blocks}: systemBlocks(blocks)
def messageText(message: Agent.AgentMessage<Unit,Tools.ToolDetails,Messages.CodingMessage<V.Value>>) -> String:
  match message:
    case Agent.LlmMessage{Ai.System{Ai.SystemMessage{content,_,_,_,_}}}: "system " ++ systemText(content)
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content,_}}}: "user " ++ contentText(content)
    case Agent.LlmMessage{Ai.Assistant{assistant}}: "assistant " ++ assistantText(Ai.assistantContent(V.Value,Unit,assistant))
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_,_,content,_,_,_,_}}}: "toolResult " ++ blockText(content)
    case Agent.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command,_,_,_,_,_,_,_}}}: "bashExecution " ++ command
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{kind,content,_,_,_}}}: kind ++ " " ++ contentText(content)
    case Agent.CustomMessage{Messages.BranchSummary{Messages.BranchSummaryMessage{summary,_,_}}}: "branchSummary " ++ summary
    case Agent.CustomMessage{Messages.CompactionSummary{Messages.CompactionSummaryMessage{summary,_,_}}}: "compactionSummary " ++ summary
def entryText(entry: Entry()) -> String:
  match entry:
    case Tree.SessionMessageEntry{_,message}: messageText(message)
    case Tree.CustomMessageEntry{_,kind,content,_,_}: kind ++ " " ++ contentText(content)
    case Tree.Compaction{_}: "compaction"
    case Tree.BranchSummaryEntry{_,_,summary,_,_,_}: "branch summary " ++ summary
    case Tree.ModelChangeEntry{_,_,id}: "model " ++ id
    case Tree.UsageEntry{_,kind,_,_,_,_}: "usage " ++ kind
    case Tree.ThinkingLevelChangeEntry{_,level}: "thinking " ++ level
    case Tree.SessionInfoEntry{_,name}: "title " ++ Maybe.default(&2,String,name,"")
    case Tree.LabelEntry{_,_,label}: "label " ++ Maybe.default(&2,String,label,"")
    case Tree.ContextEditEntry{_,target,replacement}: "context edit " ++ Bool.pick(String,Maybe.is_none(&2,Tree.ContextEditableContent,replacement),"omit ","replace ") ++ target
    case Tree.CustomEntry{_,kind,_}: "custom " ++ kind
def isUser(entry: Entry()) -> Bool:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.User{_}}}: True{}
    case _: False{}
def isTool(entry: Entry()) -> Bool:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{_}}}: True{}
    case _: False{}
def isBookkeeping(entry: Entry()) -> Bool:
  match entry:
    case Tree.ModelChangeEntry{_,_,_}: True{}
    case Tree.ThinkingLevelChangeEntry{_,_}: True{}
    case Tree.SessionInfoEntry{_,_}: True{}
    case Tree.LabelEntry{_,_,_}: True{}
    case Tree.ContextEditEntry{_,_,_}: True{}
    case Tree.CustomEntry{_,_,_}: True{}
    case _: False{}
# Usage entries (cache refreshes) are hidden from the tree in every filter
# mode, as upstream's TreeList.
def isUsage(entry: Entry()) -> Bool:
  match entry:
    case Tree.UsageEntry{_,_,_,_,_,_}: True{}
    case _: False{}
def rowOf(node: Node(),prefix: String,connector: String,active: Bool) -> Row:
  Row{node,prefix,connector,active}

def lookupValue(-Value: Data,pair: Map<&2,Value> & Value) -> Value:
  match pair: case (_,value): value
def indexedRows(rows: List<&2,Row>,index: Map<&2,Maybe<&2,Row>>) -> Map<&2,Maybe<&2,Row>>:
  match rows:
    case Nil{}: index
    case +row <> rest: indexedRows(rest,Map.set(&2,Maybe<&2,Row>,index,rowId(row),Some{row}))
def parentFromRow(value: Maybe<&2,Row>) -> Maybe<&2,String>:
  match value: case None{}: None{} case Some{row}: rowParent(row)
def indexedParent(entries: Map<&2,Maybe<&2,Row>>,id: String) -> Maybe<&2,String>:
  parentFromRow(lookupValue(Maybe<&2,Row>,Map.get(Maybe<&2,Row>,None{},entries,id)))
def nodeChildren(node: Node()) -> List<&2,Node()>:
  match node: case Tree.SessionTreeNode{_,children,_,_}: children
def nodeId(node: Node()) -> String:
  match node: case Tree.SessionTreeNode{entry,_,_,_}: Tree.baseId(Tree.entryBase(Unit,Tools.ToolDetails,V.Value,entry))
@unsafe def unorderedRows(nodes: List<&2,Node()>,reversed: List<&2,Row>) -> List<&2,Row>:
  match nodes:
    case Nil{}: reversed
    case +node <> rest:
      +children = nodeChildren(node)
      unorderedRows(rest,unorderedRows(children,Row{node,"","",False{}} <> reversed))


def activeIds(fuel: Nat,+entries: Map<&2,Maybe<&2,Row>>,leaf: Maybe<&2,String>,path: Map<&2,Bool>) -> Map<&2,Bool>:
  match fuel leaf:
    case _ None{}: path
    case Zero{} _: path
    case Succ{remaining} Some{+id}: activeIds(remaining,entries,indexedParent(entries,id),Map.set(&2,Bool,path,id,True{}))
def selectedFirst(nodes: List<&2,Node()>,+path: Map<&2,Bool>,+active: List<&2,Node()>,+other: List<&2,Node()>) -> List<&2,Node()>:
  match nodes:
    case Nil{}: List.append(&2,Node(),List.reverse(&2,Node(),active),List.reverse(&2,Node(),other))
    case +node <> +rest:
      +onPath = lookupValue(Bool,Map.get(Bool,False{},path,nodeId(node)))
      Bool.pick(Unit -> List<&2,Node()>,onPath,
        _ => selectedFirst(rest,path,node <> active,other),
        _ => selectedFirst(rest,path,active,node <> other))(Unit{})
@unsafe def flattenNodes(nodes: List<&2,Node()>,+path: Map<&2,Bool>,reversed: List<&2,Row>) -> List<&2,Row>:
  match nodes:
    case Nil{}: reversed
    case +node <> rest:
      +row = rowOf(node,"","",lookupValue(Bool,Map.get(Bool,False{},path,nodeId(node))))
      +ordered = selectedFirst(nodeChildren(node),path,Nil{},Nil{})
      flattenNodes(rest,path,flattenNodes(ordered,path,row <> reversed))
def allRows(+nodes: List<&2,Node()>,leaf: Maybe<&2,String>) -> List<&2,Row>:
  +raw = unorderedRows(nodes,Nil{})
  +path = activeIds(List.length(&2,Row,raw),indexedRows(raw,Map.new(&2,Maybe<&2,Row>)),leaf,Map.new(&2,Bool))
  List.reverse(&2,Row,flattenNodes(selectedFirst(nodes,path,Nil{},Nil{}),path,Nil{}))

def spaceSeparated(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code},rest}:
      spaceSeparated(rest,SCon{Bool.pick(Char,Text.whitespace(code),' ',Chr{code}),reversed})
def everyToken(tokens: List<&2,String>,+haystack: String) -> Bool:
  match tokens:
    case Nil{}: True{}
    case +token <> rest:
      (String.is_empty(token) || String.contains(haystack,token)) && everyToken(rest,haystack)
def matchesSearch(text: String,label: Maybe<&2,String>,search: String) -> Bool:
  +haystack = CaseMap.lower(text ++ " " ++ Maybe.default(&2,String,label,""))
  everyToken(String.split(CaseMap.lower(spaceSeparated(search,"")),' '),haystack)
def equalFilterValue(left: Filter,right: Filter) -> Bool:
  match left right:
    case Default{} Default{}: True{}
    case NoTools{} NoTools{}: True{}
    case UserOnly{} UserOnly{}: True{}
    case LabeledOnly{} LabeledOnly{}: True{}
    case All{} All{}: True{}
    case _ _: False{}
def shown(row: Row,+filter: Filter,search: String) -> Bool:
  match row:
    case Row{Tree.SessionTreeNode{+entry,_,+label,_},_,_,_}:
      +settings = isBookkeeping(entry)
      +allows = Bool.pick(Unit -> Bool,equalFilterValue(filter,Default{}),_ => Bool.not(settings),
        _ => Bool.pick(Unit -> Bool,equalFilterValue(filter,NoTools{}),_ => Bool.not(settings || isTool(entry)),
          _ => Bool.pick(Unit -> Bool,equalFilterValue(filter,UserOnly{}),_ => isUser(entry),
            _ => Bool.pick(Bool,equalFilterValue(filter,LabeledOnly{}),Maybe.is_some(&2,String,label),True{}))(Unit{}))(Unit{}))(Unit{})
      allows && matchesSearch(entryText(entry),label,search)
def usageRow(row: Row) -> Bool: isUsage(rowEntry(row))
def successfulReason(reason: Ai.StopReason) -> Bool:
  match reason:
    case Ai.Stop{}: True{}
    case Ai.ToolUse{}: True{}
    case _: False{}
def assistantVisible(entry: Entry(),current: Bool) -> Bool:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{+assistant}}}:
      current || Bool.not(String.is_empty(Text.trim(assistantText(Ai.assistantContent(V.Value,Unit,assistant))))) || Bool.not(successfulReason(Ai.assistantStopReason(V.Value,Unit,assistant)))
    case _: True{}
def currentLeaf(id: String,leaf: Maybe<&2,String>) -> Bool:
  match leaf:
    case Some{selected}: String.eq(id,selected)
    case None{}: False{}
def passes(+row: Row,filter: Filter,search: String,leaf: Maybe<&2,String>) -> Bool:
  Bool.not(usageRow(row)) && assistantVisible(rowEntry(row),currentLeaf(rowId(row),leaf)) && shown(row,filter,search)
def filtered(rows: List<&2,Row>,+filter: Filter,+search: String,+leaf: Maybe<&2,String>) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = filtered(rest,filter,search,leaf)
      Bool.pick(List<&2,Row>,passes(row,filter,search,leaf),row <> tail,tail)
def indexOf(rows: List<&2,Row>,+id: String,+index: Nat) -> Maybe<&2,Nat>:
  match rows:
    case Nil{}: None{}
    case row <> rest: Bool.pick(Maybe<&2,Nat>,String.eq(rowId(row),id),Some{index},indexOf(rest,id,index + 1n))
def parentOf(rows: List<&2,Row>,+id: String) -> Maybe<&2,String>:
  match rows:
    case Nil{}: None{}
    case +row <> rest:
      Bool.pick(Maybe<&2,String>,String.eq(rowId(row),id),rowParent(row),parentOf(rest,id))
@unsafe def initialNear(+all: List<&2,Row>,+visible: List<&2,Row>,leaf: Maybe<&2,String>,fuel: Nat) -> Nat:
  match leaf fuel:
    case None{} _: List.length(&2,Row,visible) - 1n
    case _ Zero{}: List.length(&2,Row,visible) - 1n
    case Some{+id} Succ{remaining}:
      +found = indexOf(visible,id,0n)
      Bool.pick(Unit -> Nat,Maybe.is_some(&2,Nat,found),_ => Maybe.default(&2,Nat,found,0n),_ => initialNear(all,visible,parentOf(all,id),remaining))(Unit{})
# The filtered view reconnects each row to its nearest visible ancestor.
# Native persistent maps index IDs; row order stays in ordinary sequences.


def indexedPositions(rows: List<&2,Row>,+position: Nat,index: Map<&2,Maybe<&2,Nat>>) -> Map<&2,Maybe<&2,Nat>>:
  match rows:
    case Nil{}: index
    case row <> rest: indexedPositions(rest,position + 1n,Map.set(&2,Maybe<&2,Nat>,index,rowId(row),Some{position}))


def nearestParent(fuel: Nat,+entries: Map<&2,Maybe<&2,Row>>,+indices: Map<&2,Maybe<&2,Nat>>,parent: Maybe<&2,String>) -> Maybe<&2,String>:
  match fuel parent:
    case _ None{}: None{}
    case Zero{} _: None{}
    case Succ{remaining} Some{+id}:
      +present = lookupValue(Maybe<&2,Nat>,Map.get(Maybe<&2,Nat>,None{},indices,id))
      Bool.pick(Unit -> Maybe<&2,String>,Maybe.is_some(&2,Nat,present),_ => Some{id},_ => nearestParent(remaining,entries,indices,indexedParent(entries,id)))(Unit{})
def addedEdge(graph: Graph,parent: Maybe<&2,String>,+id: String) -> Graph:
  match graph parent:
    case Graph{entries,indices,parents,children,roots,calls} None{}:
      Graph{entries,indices,Map.set(&2,Maybe<&2,String>,parents,id,None{}),children,id <> roots,calls}
    case Graph{entries,indices,parents,+children,roots,calls} Some{+ancestor}:
      +siblings = lookupValue(List<&2,String>,Map.get(List<&2,String>,Nil{},children,ancestor))
      Graph{entries,indices,Map.set(&2,Maybe<&2,String>,parents,id,Some{ancestor}),Map.set(&2,List<&2,String>,children,ancestor,id <> siblings),roots,calls}
def edges(rows: List<&2,Row>,+entries: Map<&2,Maybe<&2,Row>>,+indices: Map<&2,Maybe<&2,Nat>>,+count: Nat,graph: Graph) -> Graph:
  match rows:
    case Nil{}: graph
    case +row <> rest: edges(rest,entries,indices,count,addedEdge(graph,nearestParent(count,entries,indices,rowParent(row)),rowId(row)))
def indexedCalls(blocks: List<&2,Ai.AssistantContent<V.Value>>,index: Map<&2,Maybe<&2,ToolCallInfo>>) -> Map<&2,Maybe<&2,ToolCallInfo>>:
  match blocks:
    case Nil{}: index
    case Ai.AssistantToolCall{Ai.ToolCall{id,name,arguments,_,_}} <> rest: indexedCalls(rest,Map.set(&2,Maybe<&2,ToolCallInfo>,index,id,Some{ToolCallInfo{name,arguments}}))
    case _ <> rest: indexedCalls(rest,index)
def callsIn(entry: Entry(),index: Map<&2,Maybe<&2,ToolCallInfo>>) -> Map<&2,Maybe<&2,ToolCallInfo>>:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{message}}}: indexedCalls(Ai.assistantContent(V.Value,Unit,message),index)
    case _: index
def toolCalls(rows: List<&2,Row>,index: Map<&2,Maybe<&2,ToolCallInfo>>) -> Map<&2,Maybe<&2,ToolCallInfo>>:
  match rows:
    case Nil{}: index
    case row <> rest: toolCalls(rest,callsIn(rowEntry(row),index))
def buildGraph(+all: List<&2,Row>,+visible: List<&2,Row>) -> Graph:
  +entries = indexedRows(all,Map.new(&2,Maybe<&2,Row>))
  +indices = indexedPositions(visible,0n,Map.new(&2,Maybe<&2,Nat>))
  edges(visible,entries,indices,List.length(&2,Row,all),Graph{entries,indices,Map.new(&2,Maybe<&2,String>),Map.new(&2,List<&2,String>),Nil{},toolCalls(all,Map.new(&2,Maybe<&2,ToolCallInfo>))})
def graphParent(graph: Graph,id: String) -> Maybe<&2,String>:
  match graph: case Graph{_,_,parents,_,_,_}: lookupValue(Maybe<&2,String>,Map.get(Maybe<&2,String>,None{},parents,id))
def graphChildren(graph: Graph,id: String) -> List<&2,String>:
  match graph: case Graph{_,_,_,children,_,_}: List.reverse(&2,String,lookupValue(List<&2,String>,Map.get(List<&2,String>,Nil{},children,id)))
def graphIndex(graph: Graph,id: String,fallback: Nat) -> Nat:
  match graph: case Graph{_,indices,_,_,_,_}: Maybe.default(&2,Nat,lookupValue(Maybe<&2,Nat>,Map.get(Maybe<&2,Nat>,None{},indices,id)),fallback)
def graphRow(graph: Graph,id: String) -> Maybe<&2,Row>:
  match graph: case Graph{entries,_,_,_,_,_}: lookupValue(Maybe<&2,Row>,Map.get(Maybe<&2,Row>,None{},entries,id))

def gutterAt(gutters: List<&2,Maybe<&2,Bool>>,level: Nat) -> Maybe<&2,Bool>:
  Maybe.default(&2,Maybe<&2,Bool>,List.get(&2,Maybe<&2,Bool>,gutters,level),None{})
def prefixPart(gutter: Maybe<&2,Bool>) -> String:
  match gutter:
    case Some{True{}}: "│  "
    case _: "   "
def prefixAt(count: Nat,+gutters: List<&2,Maybe<&2,Bool>>,+level: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{remaining}: prefixPart(gutterAt(gutters,level)) ++ prefixAt(remaining,gutters,level + 1n)
def setGutter(gutters: List<&2,Maybe<&2,Bool>>,level: Nat,value: Bool) -> List<&2,Maybe<&2,Bool>>:
  match gutters level:
    case _ Zero{}: Some{value} <> List.drop(&2,Maybe<&2,Bool>,gutters,1n)
    case head <> rest Succ{remaining}: head <> setGutter(rest,remaining,value)
    case Nil{} Succ{remaining}: None{} <> setGutter(Nil{},remaining,value)

type VisualTask is Data:
  VisualTask{ids: List<&2,String>,indent: Nat,branched: Bool,gutters: List<&2,Maybe<&2,Bool>>,virtual: Bool}
def visualRow(row: Row,prefix: String,connector: String) -> Row:
  match row: case Row{node,_,_,active}: Row{node,prefix,connector,active}
def prependVisual(value: Maybe<&2,Row>,prefix: String,connector: String,reversed: List<&2,Row>) -> List<&2,Row>:
  match value:
    case None{}: reversed
    case Some{row}: visualRow(row,prefix,connector) <> reversed
@unsafe def visualRows(tasks: List<&2,VisualTask>,+graph: Graph,+multipleRoots: Bool,reversed: List<&2,Row>) -> List<&2,Row>:
  match tasks:
    case Nil{}: List.reverse(&2,Row,reversed)
    case VisualTask{Nil{},_,_,_,_} <> rest: visualRows(rest,graph,multipleRoots,reversed)
    case VisualTask{+id <> +siblings,+indent,+branched,+gutters,+virtual} <> +rest:
      +displayIndent = Bool.pick(Nat,multipleRoots,indent - 1n,indent)
      +last = List.is_empty(&2,String,siblings)
      +connected = branched && Bool.not(virtual)
      +prefix = prefixAt(Bool.pick(Nat,connected,displayIndent - 1n,displayIndent),gutters,0n)
      +connector = Bool.pick(String,connected,Bool.pick(String,last,"└─ ","├─ "),"")
      +children = graphChildren(graph,id)
      +branching = Nat.is_gt(List.length(&2,String,children),1n)
      +nextIndent = Bool.pick(Nat,branching || (branched && Nat.is_gt(indent,0n)),indent + 1n,indent)
      +nextGutters = Bool.pick(List<&2,Maybe<&2,Bool>>,connected,setGutter(gutters,displayIndent - 1n,Bool.not(last)),gutters)
      +row = graphRow(graph,id)
      visualRows(VisualTask{children,nextIndent,branching,nextGutters,False{}} <> VisualTask{siblings,indent,branched,gutters,virtual} <> rest,graph,multipleRoots,prependVisual(row,prefix,connector,reversed))
def recalculate(+graph: Graph) -> List<&2,Row>:
  match graph:
    case Graph{_,_,_,_,+roots,_}:
      +ordered = List.reverse(&2,String,roots)
      +multiple = Nat.is_gt(List.length(&2,String,ordered),1n)
      visualRows([VisualTask{ordered,Bool.pick(Nat,multiple,1n,0n),multiple,Nil{},multiple}],graph,multiple,Nil{})

def createWithFilter(nodes: List<&2,Node()>,+leaf: Maybe<&2,String>,height: Nat,+filter: Filter) -> TreeList:
  +all = allRows(nodes,leaf)
  +candidate = filtered(all,filter,"",leaf)
  +graph = buildGraph(all,candidate)
  +visible = recalculate(graph)
  +index = initialNear(all,visible,leaf,List.length(&2,Row,all))
  TreeList{all,visible,index,filter,"",leaf,Nil{},Nat.max(5n,height / 2n),Maybe.map(&2,Row,String,rowId,List.get(&2,Row,visible,index)),graph}
def create(nodes: List<&2,Node()>,leaf: Maybe<&2,String>,height: Nat) -> TreeList:
  createWithFilter(nodes,leaf,height,Default{})

def hasRows(state: TreeList) -> Bool:
  match state: case TreeList{_,visible,_,_,_,_,_,_,_,graph}: Bool.not(List.is_empty(&2,Row,visible))
def at(rows: List<&2,Row>,index: Nat) -> Maybe<&2,Row>:
  match rows index:
    case row <> _ Zero{}: Some{row}
    case _ <> rest Succ{remaining}: at(rest,remaining)
    case Nil{} _: None{}
def selectedRow(state: TreeList) -> Maybe<&2,Row>:
  match state: case TreeList{_,visible,index,_,_,_,_,_,_,graph}: at(visible,index)
def selectedId(state: TreeList) -> Maybe<&2,String>:
  Maybe.map(&2,Row,String,row => rowId(row),selectedRow(state))
def containsId(ids: List<&2,String>,+id: String) -> Bool:
  match ids:
    case Nil{}: False{}
    case head <> rest: String.eq(head,id) || containsId(rest,id)
@unsafe def hiddenBy(+rows: List<&2,Row>,+folded: List<&2,String>,parent: Maybe<&2,String>,fuel: Nat) -> Bool:
  match parent fuel:
    case None{} _: False{}
    case _ Zero{}: False{}
    case Some{+id} Succ{remaining}:
      Bool.pick(Unit -> Bool,containsId(folded,id),_ => True{},_ => hiddenBy(rows,folded,parentOf(rows,id),remaining))(Unit{})
def filterVisible(+all: List<&2,Row>,rows: List<&2,Row>,+filter: Filter,+search: String,+folded: List<&2,String>,+leaf: Maybe<&2,String>) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = filterVisible(all,rest,filter,search,folded,leaf)
      Bool.pick(List<&2,Row>,passes(row,filter,search,leaf) && Bool.not(hiddenBy(all,folded,rowParent(row),List.length(&2,Row,all))),row <> tail,tail)
@unsafe def nearest(+rows: List<&2,Row>,+visible: List<&2,Row>,id: Maybe<&2,String>,fuel: Nat) -> Nat:
  match id fuel:
    case None{} _: List.length(&2,Row,visible) - 1n
    case _ Zero{}: List.length(&2,Row,visible) - 1n
    case Some{+value} Succ{remaining}:
      +found = indexOf(visible,value,0n)
      Bool.pick(Unit -> Nat,Maybe.is_some(&2,Nat,found),_ => Maybe.default(&2,Nat,found,0n),_ => nearest(rows,visible,parentOf(rows,value),remaining))(Unit{})
def refresh(state: TreeList,+filter: Filter,+search: String,+folded: List<&2,String>) -> TreeList:
  match state:
    case TreeList{+all,+previous,index,_,_,+leaf,_,height,lastSelectedId,_}:
      +prior = Maybe.map(&2,Row,String,rowId,at(previous,index))
      +selected = Bool.pick(Maybe<&2,String>,Maybe.is_some(&2,String,prior),prior,lastSelectedId)
      +candidate = filterVisible(all,all,filter,search,folded,leaf)
      +graph = buildGraph(all,candidate)
      +visible = recalculate(graph)
      +next = nearest(all,visible,selected,List.length(&2,Row,all))
      +found = Maybe.map(&2,Row,String,rowId,at(visible,next))
      TreeList{all,visible,next,filter,search,leaf,folded,height,Bool.pick(Maybe<&2,String>,Maybe.is_some(&2,String,found),found,selected),graph}
def move(state: TreeList,up: Bool) -> TreeList:
  match state:
    case TreeList{all,+visible,+index,filter,search,leaf,folded,height,lastSelectedId,graph}:
      +count = List.length(&2,Row,visible)
      +next = Bool.pick(Nat,up,Bool.pick(Nat,Nat.is_eq(index,0n),count - 1n,index - 1n),Bool.pick(Nat,Nat.is_eq(index,count - 1n),0n,index + 1n))
      TreeList{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),filter,search,leaf,folded,height,lastSelectedId,graph}
def page(state: TreeList,up: Bool) -> TreeList:
  match state:
    case TreeList{all,+visible,+index,filter,search,leaf,folded,+height,lastSelectedId,graph}:
      +count = List.length(&2,Row,visible)
      +next = Bool.pick(Nat,up,index - height,Nat.min(count - 1n,index + height))
      TreeList{all,visible,Bool.pick(Nat,Nat.is_eq(count,0n),0n,next),filter,search,leaf,folded,height,lastSelectedId,graph}
def filterOf(state: TreeList) -> Filter:
  match state: case TreeList{_,_,_,filter,_,_,_,_,_,graph}: filter
def searchOf(state: TreeList) -> String:
  match state: case TreeList{_,_,_,_,search,_,_,_,_,graph}: search
def foldedOf(state: TreeList) -> List<&2,String>:
  match state: case TreeList{_,_,_,_,_,_,folded,_,_,graph}: folded
def toggled(current: Filter,+wanted: Filter) -> Filter:
  Bool.pick(Filter,equalFilterValue(current,wanted),Default{},wanted)
def nextFilter(filter: Filter) -> Filter:
  match filter:
    case Default{}: NoTools{}
    case NoTools{}: UserOnly{}
    case UserOnly{}: LabeledOnly{}
    case LabeledOnly{}: All{}
    case All{}: Default{}
def previousFilter(filter: Filter) -> Filter:
  match filter:
    case Default{}: All{}
    case NoTools{}: Default{}
    case UserOnly{}: NoTools{}
    case LabeledOnly{}: UserOnly{}
    case All{}: LabeledOnly{}
def withFilter(+state: TreeList,+wanted: Filter,toggle: Bool) -> TreeList:
  +next = Bool.pick(Filter,toggle,toggled(filterOf(state),wanted),wanted)
  refresh(state,next,searchOf(state),Nil{})
def withSearch(+state: TreeList,search: String) -> TreeList:
  refresh(state,filterOf(state),search,Nil{})
def clearSearch(+state: TreeList) -> TreeList: withSearch(state,"")
def reversedWithoutFirst(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{_,rest}: String.reverse(rest)
def withoutLast(text: String) -> String: reversedWithoutFirst(String.reverse(text))
def printableTail(data: String) -> Bool:
  match data:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159)) && printableTail(rest)
def printable(data: String) -> Bool:
  match data:
    case SNil{}: False{}
    case SCon{Chr{+code},rest}: U32.is_ge(code,32) && Bool.not(U32.is_eq(code,127)) && Bool.not(U32.is_ge(code,128) && U32.is_le(code,159)) && printableTail(rest)
def foldedNext(folded: List<&2,String>,+id: String,+fold: Bool) -> List<&2,String>:
  match folded:
    case Nil{}: Bool.pick(List<&2,String>,fold,id <> Nil{},Nil{})
    case +head <> +rest:
      Bool.pick(Unit -> List<&2,String>,String.eq(head,id),_ => Bool.pick(List<&2,String>,fold,head <> rest,rest),_ => head <> foldedNext(rest,id,fold))(Unit{})
def graphOf(state: TreeList) -> Graph:
  match state: case TreeList{_,_,_,_,_,_,_,_,_,graph}: graph
def segmentUp(fuel: Nat,+graph: Graph,+id: String,+original: Nat) -> Nat:
  match fuel:
    case Zero{}: graphIndex(graph,id,original)
    case Succ{remaining}:
      +parent = graphParent(graph,id)
      +current = graphIndex(graph,id,original)
      +ancestor = Maybe.default(&2,String,parent,"")
      Bool.pick(Unit -> Nat,Maybe.is_none(&2,String,parent),_ => current,
        _ => Bool.pick(Unit -> Nat,Nat.is_gt(List.length(&2,String,graphChildren(graph,ancestor)),1n) && Nat.is_lt(current,original),_ => current,_ => segmentUp(remaining,graph,ancestor,original))(Unit{}))(Unit{})
def segmentDown(fuel: Nat,+graph: Graph,+id: String) -> Nat:
  match fuel:
    case Zero{}: graphIndex(graph,id,0n)
    case Succ{remaining}:
      +children = graphChildren(graph,id)
      +child = List.get(&2,String,children,0n)
      +next = Maybe.default(&2,String,child,"")
      Bool.pick(Unit -> Nat,Maybe.is_none(&2,String,child),_ => graphIndex(graph,id,0n),
        _ => Bool.pick(Unit -> Nat,Nat.is_gt(List.length(&2,String,children),1n),_ => graphIndex(graph,next,0n),_ => segmentDown(remaining,graph,next))(Unit{}))(Unit{})
def foldable(+graph: Graph,+id: String) -> Bool:
  +parent = graphParent(graph,id)
  Bool.not(List.is_empty(&2,String,graphChildren(graph,id))) && Bool.pick(Bool,Maybe.is_none(&2,String,parent),True{},Nat.is_gt(List.length(&2,String,graphChildren(graph,Maybe.default(&2,String,parent,""))),1n))
def setIndex(state: TreeList,index: Nat) -> TreeList:
  match state:
    case TreeList{all,visible,_,filter,search,leaf,folded,height,lastSelectedId,graph}: TreeList{all,visible,index,filter,search,leaf,folded,height,lastSelectedId,graph}
def visibleOf(state: TreeList) -> List<&2,Row>:
  match state: case TreeList{_,visible,_,_,_,_,_,_,_,graph}: visible
def allOf(state: TreeList) -> List<&2,Row>:
  match state: case TreeList{all,_,_,_,_,_,_,_,_,graph}: all
def indexOfTreeList(state: TreeList) -> Nat:
  match state: case TreeList{_,_,index,_,_,_,_,_,_,graph}: index
def selectedFold(+state: TreeList,+row: Row,collapse: Bool) -> TreeList:
  +visible = visibleOf(state)
  +graph = graphOf(state)
  +index = indexOfTreeList(state)
  +filter = filterOf(state)
  +search = searchOf(state)
  +folded = foldedOf(state)
  +id = rowId(row)
  Bool.pick(Unit -> TreeList,collapse,
    _ => Bool.pick(Unit -> TreeList,foldable(graph,id) && Bool.not(containsId(folded,id)),_ => refresh(state,filter,search,foldedNext(folded,id,True{})),_ => setIndex(state,segmentUp(List.length(&2,Row,visible),graph,id,index)))(Unit{}),
    _ => Bool.pick(Unit -> TreeList,containsId(folded,id),_ => refresh(state,filter,search,foldedNext(folded,id,False{})),_ => setIndex(state,segmentDown(List.length(&2,Row,visible),graph,id)))(Unit{}))(Unit{})
def foldFound(state: TreeList,selected: Maybe<&2,Row>,collapse: Bool) -> TreeList:
  match selected:
    case None{}: state
    case Some{row}: selectedFold(state,row,collapse)
def fold(+state: TreeList,collapse: Bool) -> TreeList:
  foldFound(state,selectedRow(state),collapse)
def entryCopyText(entry: Entry()) -> Maybe<&2,String>:
  match entry:
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.User{Ai.UserMessage{content,_}}}}: Some{contentText(content)}
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.Assistant{+assistant}}}:
      +text = assistantText(Ai.assistantContent(V.Value,Unit,assistant))
      Bool.pick(Maybe<&2,String>,String.is_empty(text),Ai.assistantErrorMessage(V.Value,Unit,assistant),Some{text})
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{_,_,content,_,_,_,_}}}}: Some{blockText(content)}
    case Tree.SessionMessageEntry{_,Agent.LlmMessage{Ai.System{Ai.SystemMessage{content,_,_,_,_}}}}: Some{systemText(content)}
    case Tree.SessionMessageEntry{_,Agent.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command,_,_,_,_,_,_,_}}}}: Some{command}
    case Tree.SessionMessageEntry{_,Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{_,content,_,_,_}}}}: Some{contentText(content)}
    case Tree.CustomMessageEntry{_,_,content,_,_}: Some{contentText(content)}
    case Tree.Compaction{Tree.CompactionEntry{_,summary,_,_,_,_,_,_}}: Some{summary}
    case Tree.BranchSummaryEntry{_,_,summary,_,_,_}: Some{summary}
    case _: None{}
def nonemptyCopy(value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case Some{+text}: Bool.pick(Maybe<&2,String>,String.is_empty(Text.trim(text)),None{},Some{text})
    case None{}: None{}
def copiedRow(row: Maybe<&2,Row>) -> Maybe<&2,String>:
  match row:
    case Some{value}: nonemptyCopy(entryCopyText(rowEntry(value)))
    case None{}: None{}
def copySelected(state: TreeList) -> Maybe<&2,String>: copiedRow(selectedRow(state))

type TreeKey is Data:
  MoveKey{up: Bool}
  FoldKey{collapse: Bool}
  PageKey{up: Bool}
  ConfirmKey{}
  CopyKey{}
  CancelKey{}
  FilterKey{filter: Filter,toggle: Bool}
  CycleKey{backward: Bool}
  BackspaceKey{}
  LabelKey{}
  SearchKey{}
type BoundKey is Data: BoundKey{action: String,key: TreeKey}
def treeBindings() -> List<&2,BoundKey>:
  [BoundKey{"tui.select.up",MoveKey{True{}}},BoundKey{"tui.select.down",MoveKey{False{}}},
   BoundKey{"app.tree.foldOrUp",FoldKey{True{}}},BoundKey{"app.tree.unfoldOrDown",FoldKey{False{}}},
   BoundKey{"tui.editor.cursorLeft",PageKey{True{}}},BoundKey{"tui.select.pageUp",PageKey{True{}}},
   BoundKey{"tui.editor.cursorRight",PageKey{False{}}},BoundKey{"tui.select.pageDown",PageKey{False{}}},
   BoundKey{"tui.select.confirm",ConfirmKey{}},BoundKey{"app.message.copy",CopyKey{}},BoundKey{"tui.select.cancel",CancelKey{}},
   BoundKey{"app.tree.filter.default",FilterKey{Default{},False{}}},BoundKey{"app.tree.filter.noTools",FilterKey{NoTools{},True{}}},
   BoundKey{"app.tree.filter.userOnly",FilterKey{UserOnly{},True{}}},BoundKey{"app.tree.filter.labeledOnly",FilterKey{LabeledOnly{},True{}}},
   BoundKey{"app.tree.filter.all",FilterKey{All{},True{}}},BoundKey{"app.tree.filter.cycleBackward",CycleKey{True{}}},
   BoundKey{"app.tree.filter.cycleForward",CycleKey{False{}}},BoundKey{"tui.editor.deleteCharBackward",BackspaceKey{}},BoundKey{"app.tree.editLabel",LabelKey{}}]
def matchedKey(options: List<&2,BoundKey>,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> TreeKey:
  match options:
    case Nil{}: SearchKey{}
    case BoundKey{action,+key} <> +rest:
      Bool.pick(Unit -> TreeKey,Bindings.matches(bindings,keyboard,data,action),_ => key,_ => matchedKey(rest,bindings,keyboard,data))(Unit{})
def rowLabel(row: Row) -> Maybe<&2,String>:
  match row: case Row{Tree.SessionTreeNode{_,_,label,_},_,_,_}: label
def labelAction(row: Maybe<&2,Row>) -> Action:
  match row:
    case None{}: Continue{}
    case Some{+value}: EditLabel{rowId(value),rowLabel(value)}
def keyTransition(+state: TreeList,key: TreeKey,+data: String) -> TreeList & Action:
  match key:
    case MoveKey{up}: (move(state,up),Continue{})
    case FoldKey{collapse}: (fold(state,collapse),Continue{})
    case PageKey{up}: (page(state,up),Continue{})
    case ConfirmKey{}: (state,Maybe.default(&2,Action,Maybe.map(&2,String,Action,id => Chosen{id},selectedId(state)),Continue{}))
    case CopyKey{}: (state,Copied{copySelected(state)})
    case CancelKey{}: Bool.pick(TreeList & Action,String.is_empty(searchOf(state)),(state,Cancel{}),(clearSearch(state),Continue{}))
    case FilterKey{filter,toggle}: (withFilter(state,filter,toggle),Continue{})
    case CycleKey{backward}: (withFilter(state,Bool.pick(Filter,backward,previousFilter(filterOf(state)),nextFilter(filterOf(state))),False{}),Continue{})
    case BackspaceKey{}: (withSearch(state,withoutLast(searchOf(state))),Continue{})
    case LabelKey{}: (state,labelAction(selectedRow(state)))
    case SearchKey{}: Bool.pick(TreeList & Action,printable(data),(withSearch(state,searchOf(state) ++ data),Continue{}),(state,Continue{}))
def input(state: TreeList,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> TreeList & Action:
  keyTransition(state,matchedKey(treeBindings(),bindings,keyboard,data),data)

def paint(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.foreground(theme,key,value),value)
def shade(theme: Theme.Theme,key: String,+value: String) -> String:
  Result.default(&2,&2,Theme.Error,String,Theme.background(theme,key,value),value)
def flattenText(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: Text.trim(String.reverse(reversed))
    case SCon{+char,rest}: flattenText(rest,Bool.pick(String,Char.is_eq(char,'\n') || Char.is_eq(char,'\t'),SCon{' ',reversed},SCon{char,reversed}))
def singleLine(text: String) -> String: flattenText(text,"")
def firstChars(text: String,count: Nat) -> String:
  match text count:
    case SCon{char,rest} Succ{remaining}: SCon{char,firstChars(rest,remaining)}
    case _ _: ""
def abortedReason(reason: Ai.StopReason) -> Bool:
  match reason: case Ai.Aborted{}: True{} case _: False{}
def assistantDisplay(+assistant: Ai.AssistantMessage<V.Value,Unit>,+theme: Theme.Theme) -> String:
  +text = singleLine(firstChars(assistantText(Ai.assistantContent(V.Value,Unit,assistant)),200n))
  +error = Ai.assistantErrorMessage(V.Value,Unit,assistant)
  +aborted = abortedReason(Ai.assistantStopReason(V.Value,Unit,assistant))
  paint(theme,"success","assistant: ") ++ Bool.pick(Unit -> String,String.is_empty(text),
    _ => Bool.pick(Unit -> String,aborted,_ => paint(theme,"muted","(aborted)"),
      _ => Bool.pick(Unit -> String,Maybe.is_some(&2,String,error),_ => paint(theme,"error",firstChars(singleLine(Maybe.default(&2,String,error,"")),80n)),_ => paint(theme,"muted","(no content)"))(Unit{}))(Unit{}),
    _ => text)(Unit{})
def argument(arguments: V.Value,key: String) -> Maybe<&2,V.Value>:
  match arguments: case V.ObjectValue{fields}: R.get(V.Value,fields,key) case _: None{}
def textArgument(value: Maybe<&2,V.Value>,fallback: String) -> String:
  match value: case Some{V.Text{+text}}: Bool.pick(String,String.is_empty(text),fallback,text) case _: fallback
def numberArgument(value: Maybe<&2,V.Value>) -> Maybe<&2,F64>:
  match value: case Some{V.Number{number}}: Some{number} case _: None{}
def shortenedPath(+path: String,+home: String) -> String:
  Bool.pick(String,Bool.not(String.is_empty(home)) && String.starts_with(path,home),"~" ++ String.drop(path,String.length(home)),path)
def pathArgument(+arguments: V.Value,home: String) -> String:
  shortenedPath(textArgument(argument(arguments,"path"),textArgument(argument(arguments,"file_path"),"")),home)
def readRange(path: String,+offset: Maybe<&2,F64>,+limit: Maybe<&2,F64>) -> String:
  +start = Maybe.default(&2,F64,offset,F.fromU32(1))
  +first = Maybe.default(&2,String,F.toDecimal(start),"")
  +last = Maybe.map(&2,F64,String,size => Maybe.default(&2,String,F.toDecimal(F.subtract(F.add(start,size),F.fromU32(1))),""),limit)
  path ++ Bool.pick(String,Maybe.is_some(&2,F64,offset) || Maybe.is_some(&2,F64,limit),":" ++ first ++ Maybe.default(&2,String,Maybe.map(&2,String,String,value => "-" ++ value,last),""),"")
def formattedToolCall(call: ToolCallInfo,+home: String) -> String:
  match call:
    case ToolCallInfo{"read",+arguments}: "[read: " ++ readRange(pathArgument(arguments,home),numberArgument(argument(arguments,"offset")),numberArgument(argument(arguments,"limit"))) ++ "]"
    case ToolCallInfo{"write",+arguments}: "[write: " ++ pathArgument(arguments,home) ++ "]"
    case ToolCallInfo{"edit",+arguments}: "[edit: " ++ pathArgument(arguments,home) ++ "]"
    case ToolCallInfo{"bash",+arguments}:
      +command = textArgument(argument(arguments,"command"),"")
      "[bash: " ++ firstChars(singleLine(command),50n) ++ Bool.pick(String,Nat.is_gt(String.length(command),50n),"...","") ++ "]"
    case ToolCallInfo{"grep",+arguments}: "[grep: /" ++ textArgument(argument(arguments,"pattern"),"") ++ "/ in " ++ shortenedPath(textArgument(argument(arguments,"path"),"."),home) ++ "]"
    case ToolCallInfo{"find",+arguments}: "[find: " ++ textArgument(argument(arguments,"pattern"),"") ++ " in " ++ shortenedPath(textArgument(argument(arguments,"path"),"."),home) ++ "]"
    case ToolCallInfo{"ls",+arguments}: "[ls: " ++ shortenedPath(textArgument(argument(arguments,"path"),"."),home) ++ "]"
    case ToolCallInfo{name,arguments}:
      +json = Maybe.default(&2,String,Json.stringify(SchemaJson.toJson(arguments)),"")
      "[" ++ name ++ ": " ++ firstChars(json,40n) ++ Bool.pick(String,Nat.is_gt(String.length(json),40n),"...","") ++ "]"
def toolFound(call: Maybe<&2,ToolCallInfo>,name: String,home: String) -> String:
  match call: case None{}: "[" ++ name ++ "]" case Some{value}: formattedToolCall(value,home)
def toolDescription(graph: Graph,id: String,name: String,home: String) -> String:
  match graph:
    case Graph{_,_,_,_,_,calls}: toolFound(lookupValue(Maybe<&2,ToolCallInfo>,Map.get(Maybe<&2,ToolCallInfo>,None{},calls,id)),name,home)
def messageDisplay(message: Agent.AgentMessage<Unit,Tools.ToolDetails,Messages.CodingMessage<V.Value>>,+theme: Theme.Theme,graph: Graph,home: String) -> String:
  match message:
    case Agent.LlmMessage{Ai.User{Ai.UserMessage{content,_}}}: paint(theme,"accent","user: ") ++ singleLine(firstChars(contentText(content),200n))
    case Agent.LlmMessage{Ai.Assistant{assistant}}: assistantDisplay(assistant,theme)
    case Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{id,name,_,_,_,_,_}}}: paint(theme,"muted",toolDescription(graph,id,name,home))
    case Agent.LlmMessage{Ai.System{_}}: paint(theme,"dim","[system]")
    case Agent.CustomMessage{Messages.BashExecution{Messages.BashExecutionMessage{command,_,_,_,_,_,_,_}}}: paint(theme,"dim","[bash]: " ++ singleLine(command))
    case Agent.CustomMessage{Messages.Custom{Messages.CustomMessage{kind,_,_,_,_}}}: paint(theme,"dim","[" ++ kind ++ "]")
    case Agent.CustomMessage{Messages.BranchSummary{_}}: paint(theme,"dim","[branchSummary]")
    case Agent.CustomMessage{Messages.CompactionSummary{_}}: paint(theme,"dim","[compactionSummary]")
def entryDisplay(entry: Entry(),+theme: Theme.Theme,graph: Graph,home: String) -> String:
  match entry:
    case Tree.SessionMessageEntry{_,message}: messageDisplay(message,theme,graph,home)
    case Tree.CustomMessageEntry{_,kind,content,_,_}: paint(theme,"customMessageLabel","[" ++ kind ++ "]: ") ++ singleLine(contentText(content))
    case Tree.Compaction{Tree.CompactionEntry{_,_,_,tokens,_,_,_,_}}: paint(theme,"borderAccent","[compaction: " ++ Nat.show((tokens + 500n) / 1000n) ++ "k tokens]")
    case Tree.BranchSummaryEntry{_,_,summary,_,_,_}: paint(theme,"warning","[branch summary]: ") ++ singleLine(summary)
    case Tree.ModelChangeEntry{_,_,id}: paint(theme,"dim","[model: " ++ id ++ "]")
    case Tree.ThinkingLevelChangeEntry{_,level}: paint(theme,"dim","[thinking: " ++ level ++ "]")
    case Tree.CustomEntry{_,kind,_}: paint(theme,"dim","[custom: " ++ kind ++ "]")
    case Tree.ContextEditEntry{_,target,replacement}: paint(theme,"dim","[context " ++ Bool.pick(String,Maybe.is_none(&2,Tree.ContextEditableContent,replacement),"omit","replace") ++ ": " ++ target ++ "]")
    case Tree.LabelEntry{_,_,label}: paint(theme,"dim","[label: " ++ Maybe.default(&2,String,label,"(cleared)") ++ "]")
    case Tree.SessionInfoEntry{_,Some{name}}: paint(theme,"dim","[title: ") ++ paint(theme,"dim",name) ++ paint(theme,"dim","]")
    case Tree.SessionInfoEntry{_,None{}}: paint(theme,"dim","[title: ") ++ Theme.italic(paint(theme,"dim","empty")) ++ paint(theme,"dim","]")
    case Tree.UsageEntry{_,_,_,_,_,_}: ""
def filterStatus(filter: Filter) -> String:
  match filter:
    case Default{}: ""
    case NoTools{}: " [no-tools]"
    case UserOnly{}: " [user]"
    case LabeledOnly{}: " [labeled]"
    case All{}: " [all]"

# Keep the selection gutter fixed while panning deep branches into view.
type ViewportRow is Data:
  ViewportRow{gutter: String,body: String,anchor: Nat,bodyWidth: Nat,selected: Bool}
def renderedRow(+row: Row,+selected: Bool,+folded: List<&2,String>,+theme: Theme.Theme,+graph: Graph,home: String) -> ViewportRow:
  match row:
    case Row{Tree.SessionTreeNode{entry,_,label,_},prefix,+connector,active}:
      +id = rowId(row)
      +collapsed = containsId(folded,id)
      +canFold = foldable(graph,id)
      +branch = Bool.pick(Unit -> String,String.is_empty(connector),_ => "",_ => firstChars(connector,1n) ++ Bool.pick(String,collapsed,"⊞",Bool.pick(String,canFold,"⊟","─")) ++ " ")(Unit{})
      +foldMarker = Bool.pick(String,collapsed && String.is_empty(connector),paint(theme,"accent","⊞ "),"")
      +path = Bool.pick(String,active,paint(theme,"accent","• "),"")
      +labelText = Maybe.default(&2,String,Maybe.map(&2,String,String,value => paint(theme,"warning","[" ++ value ++ "] "),label),"")
      +prefixPart = paint(theme,"dim",prefix ++ branch) ++ foldMarker ++ path
      +content = entryDisplay(entry,theme,graph,home)
      +body = prefixPart ++ labelText ++ Bool.pick(String,selected,Theme.bold(content),content)
      +gutter = Bool.pick(String,selected,paint(theme,"accent","› "),"  ")
      ViewportRow{Bool.pick(String,selected,shade(theme,"selectedBg",gutter),gutter),Bool.pick(String,selected,shade(theme,"selectedBg",body),body),Utils.visibleWidth(prefixPart),Utils.visibleWidth(body),selected}
def windowRows(rows: List<&2,Row>,+start: Nat,+count: Nat,+index: Nat,+selected: Nat,+folded: List<&2,String>,+theme: Theme.Theme,+graph: Graph,+home: String) -> List<&2,ViewportRow>:
  match rows:
    case Nil{}: Nil{}
    case row <> +rest:
      Bool.pick(Unit -> List<&2,ViewportRow>,Nat.is_ge(index,start + count),_ => Nil{},
        _ => Bool.pick(Unit -> List<&2,ViewportRow>,Nat.is_lt(index,start),
          _ => windowRows(rest,start,count,index + 1n,selected,folded,theme,graph,home),
          _ => renderedRow(row,Nat.is_eq(index,selected),folded,theme,graph,home) <> windowRows(rest,start,count,index + 1n,selected,folded,theme,graph,home))(Unit{}))(Unit{})
def maxBodyWidth(rows: List<&2,ViewportRow>,maximum: Nat) -> Nat:
  match rows:
    case Nil{}: maximum
    case ViewportRow{_,_,_,width,_} <> rest: maxBodyWidth(rest,Nat.max(maximum,width))
def selectedAnchor(rows: List<&2,ViewportRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case ViewportRow{_,_,anchor,_,True{}} <> _: anchor
    case _ <> rest: selectedAnchor(rest)
def pannedRows(rows: List<&2,ViewportRow>,+scroll: Nat,+width: Nat) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case ViewportRow{gutter,+body,_,_,_} <> rest:
      Utils.truncateToWidth(gutter ++ Bool.pick(Unit -> String,Nat.is_gt(scroll,0n),_ => Utils.sliceByColumn(body,scroll,width - 2n,True{}) ++ "\u{1b}[0m",_ => body)(Unit{}),width,"",False{}) <> pannedRows(rest,scroll,width)
def horizontalViewport(+rows: List<&2,ViewportRow>,+width: Nat) -> List<&2,String>:
  +viewport = width - 2n
  +maximum = maxBodyWidth(rows,0n) - viewport
  +anchor = selectedAnchor(rows)
  +content = Nat.min(20n,Nat.max(4n,viewport / 3n))
  +context = Nat.min(12n,Nat.max(2n,viewport / 4n))
  +scroll = Bool.pick(Nat,Nat.is_gt(anchor,viewport - content),Nat.min(maximum,anchor - context),0n)
  pannedRows(rows,scroll,width)
def renderList(state: TreeList,+theme: Theme.Theme,+width: Nat,+home: String) -> List<&2,String>:
  match state:
    case TreeList{+all,+visible,+index,filter,_,_,folded,+height,_,+graph}:
      +count = List.length(&2,Row,visible)
      +start = Nat.min(index - height / 2n,count - height)
      +position = Bool.pick(Nat,Nat.is_eq(count,0n),0n,index + 1n)
      +rows = Bool.pick(Unit -> List<&2,String>,List.is_empty(&2,Row,visible),_ => Utils.truncateToWidth(paint(theme,"muted","  No entries found"),width,"...",False{}) <> Nil{},
        _ => horizontalViewport(windowRows(visible,start,height,0n,index,folded,theme,graph,home),width))(Unit{})
      List.append(&2,String,rows,Utils.truncateToWidth(paint(theme,"muted","  (" ++ Nat.show(position) ++ "/" ++ Nat.show(count) ++ ")" ++ filterStatus(filter)),width,"...",False{}) <> Nil{})

type KeyParts is Data: KeyParts{prefix: String,suffix: String}
def splitKey(parts: List<&2,String>,prefix: String) -> KeyParts:
  match parts:
    case Nil{}: KeyParts{prefix,""}
    case last <> Nil{}: KeyParts{prefix,last}
    case part <> rest: splitKey(rest,prefix ++ part ++ "+")
def helpKeys(actions: List<&2,String>,+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  match actions:
    case Nil{}: Nil{}
    case action <> +rest:
      +keys = Bindings.getKeys(bindings,action)
      Bool.pick(Unit -> List<&2,String>,List.is_empty(&2,Keys.KeyId,keys),_ => helpKeys(rest,bindings),_ => Keys.formatKeyId(Maybe.default(&2,Keys.KeyId,List.get(&2,Keys.KeyId,keys,0n),Keys.plain(Keys.Escape{}))) <> helpKeys(rest,bindings))(Unit{})
def splitKeys(keys: List<&2,String>) -> List<&2,KeyParts>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: splitKey(String.split(key,'+'),"") <> splitKeys(rest)
def commonKeys(keys: List<&2,KeyParts>,+prefix: String,suffixes: List<&2,String>) -> Maybe<&2,String>:
  match keys:
    case Nil{}: Some{prefix ++ String.join(List.reverse(&2,String,suffixes),"/")}
    case KeyParts{found,suffix} <> +rest:
      Bool.pick(Unit -> Maybe<&2,String>,String.eq(found,prefix),_ => commonKeys(rest,prefix,suffix <> suffixes),_ => None{})(Unit{})
def compactParts(parts: List<&2,KeyParts>,+original: List<&2,String>) -> String:
  match parts:
    case Nil{}: ""
    case KeyParts{+prefix,suffix} <> rest:
      Bool.pick(Unit -> String,String.is_empty(prefix),_ => String.join(original,"/"),_ => Maybe.default(&2,String,commonKeys(rest,prefix,suffix <> Nil{}),String.join(original,"/")))(Unit{})
def compactKeys(+keys: List<&2,String>) -> String: compactParts(splitKeys(keys),keys)
def keyGlyphs(key: String) -> String:
  match key:
    case "up": "↑"
    case "down": "↓"
    case "left": "←"
    case "right": "→"
    case "pageUp": "pgup"
    case "pageDown": "pgdn"
    case _: key
def glyphParts(parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case part <> rest: keyGlyphs(part) <> glyphParts(rest)
def glyphKeys(keys: List<&2,String>) -> List<&2,String>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: String.join(glyphParts(String.split(key,'+')),"+") <> glyphKeys(rest)
def helpItem(+bindings: Bindings.KeybindingsManager,actions: List<&2,String>,+label: String,first: Bool) -> String:
  +keys = String.join(glyphKeys(String.split(compactKeys(helpKeys(actions,bindings)),'/')),"/")
  Bool.pick(String,String.is_empty(keys),label,Bool.pick(String,first,label ++ " " ++ keys,keys ++ " " ++ label))
def helpItems(+bindings: Bindings.KeybindingsManager) -> List<&2,String>:
  [helpItem(bindings,["tui.select.up","tui.select.down"],"move",False{}),
   helpItem(bindings,["tui.editor.cursorLeft","tui.editor.cursorRight"],"page",False{}),
   helpItem(bindings,["app.tree.foldOrUp","app.tree.unfoldOrDown"],"branch",False{}),
   helpItem(bindings,["app.message.copy"],"copy",False{}),
   helpItem(bindings,["app.tree.editLabel"],"label",False{}),
   helpItem(bindings,["app.tree.toggleLabelTimestamp"],"label time",False{}),
   helpItem(bindings,["app.tree.filter.default","app.tree.filter.noTools","app.tree.filter.userOnly","app.tree.filter.labeledOnly","app.tree.filter.all"],"filters",True{}),
   helpItem(bindings,["app.tree.filter.cycleForward","app.tree.filter.cycleBackward"],"cycle",True{})]
def helpRows(items: List<&2,String>,+width: Nat,+current: String,+reversed: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: List.append(&2,String,List.reverse(&2,String,reversed),Bool.pick(Unit -> List<&2,String>,String.is_empty(current),_ => Nil{},_ => Utils.wrapTextWithAnsi(current,width))(Unit{}))
    case +item <> +rest:
      +alone = Bool.pick(String,Nat.is_le(Utils.visibleWidth("  " ++ item),width),"  " ++ item,item)
      +candidate = Bool.pick(String,String.is_empty(current),alone,current ++ " · " ++ item)
      Bool.pick(Unit -> List<&2,String>,String.is_empty(current) || Nat.is_le(Utils.visibleWidth(candidate),width),
        _ => helpRows(rest,width,candidate,reversed),
        _ => helpRows(rest,width,alone,List.append(&2,String,List.reverse(&2,String,Utils.wrapTextWithAnsi(current,width)),reversed)))(Unit{})
def paintHelp(lines: List<&2,String>,+theme: Theme.Theme) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: paint(theme,"muted",line) <> paintHelp(rest,theme)

type LabelInput is Data: LabelInput{entryId: String,input: Input.Input}
type TreeSelectorComponent is Data:
  TreeSelectorComponent{treeList: TreeList,labelInput: Maybe<&2,LabelInput>,focused: Bool}
def fromList(list: TreeList) -> TreeSelectorComponent: TreeSelectorComponent{list,None{},False{}}
def getTreeList(component: TreeSelectorComponent) -> TreeList:
  match component: case TreeSelectorComponent{list,_,_}: list
def rowNode(row: Row) -> Node():
  match row: case Row{node,_,_,_}: node
def getSelectedNode(list: TreeList) -> Maybe<&2,Node()>:
  Maybe.map(&2,Row,Node(),rowNode,selectedRow(list))
def getSearchQuery(list: TreeList) -> String: searchOf(list)
def focusedLabel(value: Maybe<&2,LabelInput>,focused: Bool) -> Maybe<&2,LabelInput>:
  match value:
    case None{}: None{}
    case Some{LabelInput{id,input}}: Some{LabelInput{id,Input.setFocused(input,focused)}}
def setFocused(component: TreeSelectorComponent,+focused: Bool) -> TreeSelectorComponent:
  match component: case TreeSelectorComponent{list,label,_}: TreeSelectorComponent{list,focusedLabel(label,focused),focused}
def begunLabel(component: TreeSelectorComponent,id: String,label: Maybe<&2,String>) -> TreeSelectorComponent:
  match component:
    case TreeSelectorComponent{list,_,+focused}: TreeSelectorComponent{list,Some{LabelInput{id,Input.setFocused(Input.setValue(Input.new(None{}),Maybe.default(&2,String,label,"")),focused)}},focused}
def transitioned(component: TreeSelectorComponent,pair: TreeList & Action) -> TreeSelectorComponent & Action:
  match component pair:
    case TreeSelectorComponent{_,label,focused} Tuple{list,EditLabel{id,text}}: (begunLabel(TreeSelectorComponent{list,label,focused},id,text),Continue{})
    case TreeSelectorComponent{_,label,focused} Tuple{list,action}: (TreeSelectorComponent{list,label,focused},action)

# Update the immutable tree once, then reuse its nodes in the existing view.
# Label edits do not change filter membership until the next filter/search action.
def rootNodes(rows: List<&2,Row>) -> List<&2,Node()>:
  match rows:
    case Nil{}: Nil{}
    case +row <> +rest: Bool.pick(Unit -> List<&2,Node()>,Maybe.is_none(&2,String,rowParent(row)),_ => rowNode(row) <> rootNodes(rest),_ => rootNodes(rest))(Unit{})
@unsafe def labelledNodes(nodes: List<&2,Node()>,+id: String,+label: Maybe<&2,String>,+stamp: Maybe<&2,String>) -> List<&2,Node()>:
  match nodes:
    case Nil{}: Nil{}
    case Tree.SessionTreeNode{+entry,children,current,time} <> rest:
      +changed = String.eq(Tree.baseId(Tree.entryBase(Unit,Tools.ToolDetails,V.Value,entry)),id)
      Tree.SessionTreeNode{entry,labelledNodes(children,id,label,stamp),Bool.pick(Maybe<&2,String>,changed,label,current),Bool.pick(Maybe<&2,String>,changed,stamp,time)} <> labelledNodes(rest,id,label,stamp)
def labelledView(rows: List<&2,Row>,+entries: Map<&2,Maybe<&2,Row>>) -> List<&2,Row>:
  match rows:
    case Nil{}: Nil{}
    case Row{+node,prefix,connector,active} <> rest:
      +updated = Maybe.default(&2,Node(),Maybe.map(&2,Row,Node(),rowNode,lookupValue(Maybe<&2,Row>,Map.get(Maybe<&2,Row>,None{},entries,nodeId(node)))),node)
      Row{updated,prefix,connector,active} <> labelledView(rest,entries)
def updateNodeLabel(list: TreeList,+id: String,+label: Maybe<&2,String>,timestamp: String) -> TreeList:
  match list:
    case TreeList{all,+visible,index,filter,search,+leaf,folded,height,remembered,_}:
      +next = allRows(labelledNodes(rootNodes(all),id,label,Bool.pick(Maybe<&2,String>,Maybe.is_some(&2,String,label),Some{timestamp},None{})),leaf)
      +view = labelledView(visible,indexedRows(next,Map.new(&2,Maybe<&2,Row>)))
      TreeList{next,view,index,filter,search,leaf,folded,height,remembered,buildGraph(next,view)}
def savedLabel(component: TreeSelectorComponent,+id: String,+label: Maybe<&2,String>,timestamp: String) -> TreeSelectorComponent & Action:
  match component:
    case TreeSelectorComponent{list,_,focused}: (TreeSelectorComponent{updateNodeLabel(list,id,label,timestamp),None{},focused},LabelChanged{id,label})
def saveLabel(component: TreeSelectorComponent,id: String,text: String) -> IO(TreeSelectorComponent & Action):
  do IO<TreeSelectorComponent & Action>:
    now : F64 <- Date.now()
    return savedLabel(component,id,nonemptyCopy(Some{Text.trim(text)}),Maybe.default(&2,String,Date.formatIso(now),""))
def withoutLabelInput(component: TreeSelectorComponent) -> TreeSelectorComponent:
  match component: case TreeSelectorComponent{list,_,focused}: TreeSelectorComponent{list,None{},focused}
def needsWords(command: Input.Command) -> Bool:
  match command:
    case Input.WordLeft{}: True{}
    case Input.WordRight{}: True{}
    case Input.KillWordBackward{}: True{}
    case Input.KillWordForward{}: True{}
    case _: False{}
def wordText(component: TreeSelectorComponent,bindings: Bindings.KeybindingsManager,keyboard: Keys.Context,data: String) -> Maybe<&2,String>:
  match component:
    case TreeSelectorComponent{_,Some{LabelInput{_,editor}},_}: Bool.pick(Maybe<&2,String>,needsWords(Input.command(Input.bindings(),bindings,keyboard,data)),Some{Input.getValue(editor)},None{})
    case _: None{}
def nonAtomic(_: Segmenter.Source,_: String) -> Bool: False{}
def editedLabel(component: TreeSelectorComponent,id: String,result: Word.ResultOf(Input.Input)) -> TreeSelectorComponent & Action:
  match component result:
    case TreeSelectorComponent{list,_,focused} Done{input}: (TreeSelectorComponent{list,Some{LabelInput{id,input}},focused},Continue{})
    case _ Fail{error}: (component,InputError{error})
def handleInput(+component: TreeSelectorComponent,source: Segmenter.Source,+bindings: Bindings.KeybindingsManager,+keyboard: Keys.Context,+data: String) -> IO(TreeSelectorComponent & Action):
  match component:
    case TreeSelectorComponent{list,None{},_}: IO.pure(TreeSelectorComponent & Action,transitioned(component,input(list,bindings,keyboard,data)))
    case TreeSelectorComponent{_,Some{LabelInput{+id,+editor}},_}:
      Bool.pick(Unit -> IO(TreeSelectorComponent & Action),Bindings.matches(bindings,keyboard,data,"tui.select.confirm"),_ => saveLabel(component,id,Input.getValue(editor)),
        _ => Bool.pick(Unit -> IO(TreeSelectorComponent & Action),Bindings.matches(bindings,keyboard,data,"tui.select.cancel"),_ => IO.pure(TreeSelectorComponent & Action,(withoutLabelInput(component),Continue{})),
          _ => do IO<TreeSelectorComponent & Action>:
            result : Word.ResultOf(Input.Input) <- Input.handleInput(~Segmenter.Source,~Word.sourceSegments,~nonAtomic,source,editor,bindings,keyboard,data)
            return editedLabel(component,id,result))(Unit{}))(Unit{})

def labelLines(lines: List<&2,String>,+width: Nat) -> List<&2,String>:
  match lines: case Nil{}: Nil{} case line <> rest: Utils.truncateToWidth("  " ++ line,width,"...",False{}) <> labelLines(rest,width)
def labelRendered(component: TreeSelectorComponent,id: String,+theme: Theme.Theme,+bindings: Bindings.KeybindingsManager,+width: Nat,pair: Input.Input & List<&2,String>) -> TreeSelectorComponent & List<&2,String>:
  match component pair:
    case TreeSelectorComponent{list,_,focused} Tuple{input,lines}:
      (TreeSelectorComponent{list,Some{LabelInput{id,input}},focused},
       Utils.truncateToWidth("  " ++ paint(theme,"muted","Label (empty to remove):"),width,"...",False{}) <> List.append(&2,String,labelLines(lines,width),[Utils.truncateToWidth("  " ++ Hints.keyHint(theme,bindings,"tui.select.confirm","save") ++ "  " ++ Hints.keyHint(theme,bindings,"tui.select.cancel","cancel"),width,"...",False{})]))
def renderContent(+component: TreeSelectorComponent,theme: Theme.Theme,+width: Nat,bindings: Bindings.KeybindingsManager,home: String) -> IO(TreeSelectorComponent & List<&2,String>):
  match component:
    case TreeSelectorComponent{list,None{},_}: IO.pure(TreeSelectorComponent & List<&2,String>,(component,renderList(list,theme,width,home)))
    case TreeSelectorComponent{_,Some{LabelInput{+id,input}},_}:
      do IO<TreeSelectorComponent & List<&2,String>>:
        rendered : Input.Input & List<&2,String> <- Input.render(input,width - 2n)
        return labelRendered(component,id,theme,bindings,width,rendered)
def framed(component: TreeSelectorComponent & List<&2,String>,+theme: Theme.Theme,+width: Nat,bindings: Bindings.KeybindingsManager,title: TuiText.Text & List<&2,String>) -> TreeSelectorComponent & List<&2,String>:
  match component title:
    case Tuple{+next,content} Tuple{_,heading}:
      +query = searchOf(getTreeList(next))
      +border = paint(theme,"border",String.repeat("─",Nat.max(1n,width)))
      +search = Utils.truncateToWidth("  " ++ paint(theme,"muted","Type to search:") ++ Bool.pick(String,String.is_empty(query),""," " ++ paint(theme,"accent",query)),width,"...",False{})
      (next,List.append(&2,String,"" <> border <> heading,List.append(&2,String,paintHelp(helpRows(helpItems(bindings),Nat.max(1n,width),"",Nil{}),theme),search <> border <> "" <> List.append(&2,String,content,"" <> border <> Nil{}))))
def envText(value: Result<&1,&1,U32 & String,String>) -> String:
  match value: case Done{text}: text case Fail{_}: ""
def preferredHome(+home: String,profile: String) -> String:
  Bool.pick(String,String.is_empty(home),profile,home)
def render(component: TreeSelectorComponent,+theme: Theme.Theme,+width: Nat,+bindings: Bindings.KeybindingsManager) -> IO(TreeSelectorComponent & List<&2,String>):
  do IO<TreeSelectorComponent & List<&2,String>>:
    title : TuiText.Text & List<&2,String> <- TuiText.render(TuiText.new(Theme.bold("  Session Tree"),Some{1n},Some{0n},None{}),width)
    home : Result<&1,&1,U32 & String,String> <- IO.get_env("HOME")
    profile : Result<&1,&1,U32 & String,String> <- IO.get_env("USERPROFILE")
    content : TreeSelectorComponent & List<&2,String> <- renderContent(component,theme,width,bindings,preferredHome(envText(home),envText(profile)))
    return framed(content,theme,width,bindings,title)
