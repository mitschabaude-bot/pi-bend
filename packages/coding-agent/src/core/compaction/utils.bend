import Base
import ../../../../agent/src/types.bend as Agent
import ../../../../ai/src/types.bend as Ai
import ../../../../ai/src/utils/text.bend as Text
import ../../../../ai/src/utils/json.bend as Render
import ../../../../ai/src/utils/schema-json.bend as SchemaJson
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/string.bend as Set

# pi `compaction/utils.ts`: the files an assistant touched through tool
# calls, the conversation serialization fed to the summarizer, and the
# summarizer's system prompt.

type FileOperations is Data:
  FileOperations{read: Set.StringSet, written: Set.StringSet, edited: Set.StringSet}

def createFileOps() -> FileOperations: FileOperations{Set.empty(), Set.empty(), Set.empty()}

def pathValue(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{SNil{}}}: None{}
    case Some{V.Text{path}}: Some{path}
    case _: None{}

def pathArgument(arguments: V.Value) -> Maybe<&2, String>:
  match arguments:
    case V.ObjectValue{record}: pathValue(R.get(V.Value, record, "path"))
    case _: None{}

def recordPath(ops: FileOperations, name: String, path: String) -> FileOperations:
  match ops name:
    case FileOperations{read, written, edited} "read": FileOperations{Set.insert(read, path), written, edited}
    case FileOperations{read, written, edited} "write": FileOperations{read, Set.insert(written, path), edited}
    case FileOperations{read, written, edited} "edit": FileOperations{read, written, Set.insert(edited, path)}
    case FileOperations{read, written, edited} _: FileOperations{read, written, edited}

def recordCall(ops: FileOperations, name: String, path: Maybe<&2, String>) -> FileOperations:
  match path:
    case None{}: ops
    case Some{value}: recordPath(ops, name, value)

def recordBlocks(blocks: List<&2, Ai.AssistantContent<V.Value>>, ops: FileOperations) -> FileOperations:
  match blocks:
    case Nil{}: ops
    case Ai.AssistantToolCall{Ai.ToolCall{_, name, arguments, _, _}} <> rest: recordBlocks(rest, recordCall(ops, name, pathArgument(arguments)))
    case _ <> rest: recordBlocks(rest, ops)

# Only assistant tool calls with a string `path` argument count.
def extractFileOpsFromMessage(-D: Data, -T: Data, -C: Data, message: Agent.AgentMessage<D, T, C>, ops: FileOperations) -> FileOperations:
  match message:
    case Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}}: recordBlocks(content, ops)
    case _: ops

def extractFileOpsFromMessages(-D: Data, -T: Data, -C: Data, messages: List<&2, Agent.AgentMessage<D, T, C>>, ops: FileOperations) -> FileOperations:
  match messages:
    case Nil{}: ops
    case message <> rest: extractFileOpsFromMessages(D, T, C, rest, extractFileOpsFromMessage(D, T, C, message, ops))

type FileLists is Data:
  FileLists{readFiles: List<&2, String>, modifiedFiles: List<&2, String>}

def notGreater(compared: (String & String) & Cmp) -> Bool:
  match compared:
    case Tuple{_, GT{}}: False{}
    case Tuple{_, _}: True{}

def lessOrEqual(a: String, b: String) -> Bool: notGreater(String.cmp(a, b))

def sorted(values: List<&2, String>) -> List<&2, String>: List.sort(~String, ~lessOrEqual, values)

def insertAll(added: List<&2, String>, values: Set.StringSet) -> Set.StringSet:
  match added:
    case Nil{}: values
    case value <> rest: insertAll(rest, Set.insert(values, value))

def prependUnless(skip: Bool, value: String, rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}: rest
    case False{}: value <> rest

def notIn(+excluded: Set.StringSet, values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case +value <> rest: prependUnless(Set.contains(excluded, value), value, notIn(excluded, rest))


# Modified files are the edited and written ones; read files exclude them.
def computeFileLists(ops: FileOperations) -> FileLists:
  match ops:
    case FileOperations{read, written, edited}:
      +modified = insertAll(Set.toList(written), edited)
      FileLists{sorted(notIn(modified, Set.toList(read))), sorted(Set.toList(modified))}

def section(+tag: String, files: List<&2, String>) -> List<&2, String>:
  match files:
    case Nil{}: Nil{}
    case first <> rest: ("<" ++ tag ++ ">\n" ++ String.join(first <> rest, "\n") ++ "\n</" ++ tag ++ ">") <> Nil{}

def joinedSections(sections: List<&2, String>) -> String:
  match sections:
    case Nil{}: ""
    case first <> rest: "\n\n" ++ String.join(first <> rest, "\n\n")

def formatFileOperations(readFiles: List<&2, String>, modifiedFiles: List<&2, String>) -> String:
  joinedSections(List.append(&2, String, section("read-files", readFiles), section("modified-files", modifiedFiles)))

# Serialization
# -------------

def TOOL_RESULT_MAX_CHARS() -> Nat: 2000n

# Lengths and slices count code points; upstream counts UTF-16 units.
def truncateForSummary(+text: String, +maxChars: Nat) -> String:
  +length = String.length(text)
  Bool.pick(String, Nat.is_gt(length, maxChars), String.take(text, maxChars) ++ "\n\n[... " ++ Nat.show(Nat.sub(length, maxChars)) ++ " more characters truncated]", text)

def textImageBlocks(values: List<&2, Ai.TextImageContent>) -> List<&2, Text.Content<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case Ai.TextImageText{value} <> rest: Text.TextBlock{value} <> textImageBlocks(rest)
    case Ai.TextImageImage{value} <> rest: Text.ImageBlock{value} <> textImageBlocks(rest)

def userInput(content: Ai.UserContent) -> Text.ContentInput<V.Value>:
  match content:
    case Ai.UserText{value}: Text.ContentString{value}
    case Ai.UserBlocks{values}: Text.ContentBlocks{textImageBlocks(values)}

def assistantBlocks(values: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, Text.Content<V.Value>>:
  match values:
    case Nil{}: Nil{}
    case Ai.AssistantText{value} <> rest: Text.TextBlock{value} <> assistantBlocks(rest)
    case Ai.AssistantThinking{value} <> rest: Text.ThinkingBlock{value} <> assistantBlocks(rest)
    case Ai.AssistantToolCall{value} <> rest: Text.ToolCallBlock{value} <> assistantBlocks(rest)

def jsonText(value: V.Value) -> String:
  Maybe.default(&2, String, Render.stringify(SchemaJson.toJson(value)), "null")

def argumentEntries(properties: List<&2, R.Property<V.Value>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case R.Property{key, value} <> rest: (key ++ "=" ++ jsonText(value)) <> argumentEntries(rest)

# Arguments that are not an object have no entries, where upstream would throw.
def argumentText(arguments: V.Value) -> String:
  match arguments:
    case V.ObjectValue{R.Record{properties}}: String.join(argumentEntries(properties), ", ")
    case _: ""

def thinkingParts(values: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Ai.AssistantThinking{Ai.ThinkingContent{thinking, _, _}} <> rest: thinking <> thinkingParts(rest)
    case _ <> rest: thinkingParts(rest)

def toolCallParts(values: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case Ai.AssistantToolCall{Ai.ToolCall{_, name, arguments, _, _}} <> rest: (name ++ "(" ++ argumentText(arguments) ++ ")") <> toolCallParts(rest)
    case _ <> rest: toolCallParts(rest)

def hasText(values: List<&2, Ai.AssistantContent<V.Value>>) -> Bool:
  match values:
    case Nil{}: False{}
    case Ai.AssistantText{_} <> _: True{}
    case _ <> rest: hasText(rest)

def labelled(label: String, parts: List<&2, String>, separator: String) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case first <> rest: (label ++ String.join(first <> rest, separator)) <> Nil{}

def nonEmpty(label: String, text: String) -> List<&2, String>:
  match text:
    case SNil{}: Nil{}
    case SCon{first, rest}: (label ++ SCon{first, rest}) <> Nil{}

def assistantParts(+content: List<&2, Ai.AssistantContent<V.Value>>) -> List<&2, String>:
  List.append(&2, String, labelled("[Assistant thinking]: ", thinkingParts(content), "\n"), List.append(&2, String, Bool.pick(List<&2, String>, hasText(content), ("[Assistant]: " ++ Text.contentText(V.Value, Text.ContentBlocks{assistantBlocks(content)}, "\n")) <> Nil{}, Nil{}), labelled("[Assistant tool calls]: ", toolCallParts(content), "; ")))

def messageParts(-G: Data, -D: Data, message: Ai.Message<V.Value, V.Value, G, D>) -> List<&2, String>:
  match message:
    case Ai.User{Ai.UserMessage{content, _}}: nonEmpty("[User]: ", Text.contentText(V.Value, userInput(content), ""))
    case Ai.Assistant{Ai.AssistantMessage{content, _, _, _, _, _, _, _, _, _, _, _, _, _, _}}: assistantParts(content)
    case Ai.ToolResult{Ai.ToolResultMessage{_, _, content, _, _, _, _}}: nonEmpty("[Tool result]: ", truncateForSummary(Text.contentText(V.Value, Text.ContentBlocks{textImageBlocks(content)}, ""), TOOL_RESULT_MAX_CHARS()))
    case _: Nil{}

def conversationParts(-G: Data, -D: Data, messages: List<&2, Ai.Message<V.Value, V.Value, G, D>>) -> List<&2, String>:
  match messages:
    case Nil{}: Nil{}
    case message <> rest: List.append(&2, String, messageParts(G, D, message), conversationParts(G, D, rest))

def serializeConversation(-G: Data, -D: Data, messages: List<&2, Ai.Message<V.Value, V.Value, G, D>>) -> String:
  String.join(conversationParts(G, D, messages), "\n\n")

def SUMMARIZATION_SYSTEM_PROMPT() -> String:
  "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\nDo NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary."
