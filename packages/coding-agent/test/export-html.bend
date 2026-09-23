import Base
import ../src/core/export-html/index.bend as Export
import ../src/core/session-manager.bend as S
import ../src/core/session-persistence.bend as Persistence
import ../src/core/messages.bend as Messages
import ../src/core/tools/index.bend as Tools
import ../../agent/src/types.bend as Agent
import ../../ai/src/types.bend as Ai
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/string.bend as Set
import ../../runtime/src/utf8.bend as Utf8

# The export must retain the typed session tree and encode hostile/Unicode text
# as UTF-8 Base64 before it is inserted into the standalone HTML viewer.
def State() -> Data: S.SessionManager<Unit, Tools.ToolDetails, V.Value>
def Entries() -> Data: List<&2, S.SessionEntry<Unit, Tools.ToolDetails, V.Value>>
def Source() -> String: "build/export-html-source.jsonl"
def AssetsDir() -> String: "packages/coding-agent/src/core/export-html"

def usage() -> Ai.Usage:
  +zero = F.fromU32(0)
  Ai.Usage{F.fromU32(1), F.fromU32(2), zero, zero, None{}, None{}, F.fromU32(3), Ai.UsageCost{zero, zero, zero, zero, zero}}

def assistant() -> Agent.AgentMessage<Unit, Tools.ToolDetails, Messages.CodingMessage<V.Value>>:
  +args = {V.ObjectValue{R.set(V.Value, R.new(V.Value), "command", V.Text{"printf '<script>'"})} : V.Value}
  Agent.LlmMessage{Ai.Assistant{Ai.AssistantMessage{Ai.AssistantText{Ai.TextContent{"I will run it.", None{}}} <> Ai.AssistantToolCall{Ai.ToolCall{"call-1", "bash", args, None{}, None{}}} <> Nil{}, "openai-responses", "openai", "gpt-test", None{}, None{}, None{}, None{}, usage(), Ai.ToolUse{}, None{}, None{}, None{}, None{}, F.fromU32(2)}}}

def timestamp() -> String: "2026-01-01T00:00:00.000Z"

def entries() -> Entries():
  S.SessionMessageEntry{S.SessionEntryBase{"u1", None{}, timestamp()}, Agent.LlmMessage{Ai.User{Ai.UserMessage{Ai.UserText{"<script>alert(1)</script> & é"}, F.fromU32(1)}}}} <>
  S.SessionMessageEntry{S.SessionEntryBase{"a1", Some{"u1"}, timestamp()}, assistant()} <>
  S.SessionMessageEntry{S.SessionEntryBase{"r1", Some{"a1"}, timestamp()}, Agent.LlmMessage{Ai.ToolResult{Ai.ToolResultMessage{"call-1", "bash", Ai.TextImageText{Ai.TextContent{"<ok>\n  indented", None{}}} <> Nil{}, Some{Tools.WriteDetails{}}, None{}, False{}, F.fromU32(3)}}}} <> Nil{}

def session() -> Result<&2, &2, S.Error, State()>:
  S.restore(Unit, Tools.ToolDetails, V.Value, S.SessionHeader{Some{S.CURRENT_SESSION_VERSION()}, "export-1", "2026-01-01T00:00:00.000Z", "/tmp", None{}}, entries())

def sourceContent(result: Result<&2, &2, S.Error, State()>) -> String:
  match result:
    case Fail{_}: ""
    case Done{manager}: Persistence.fileContent(~Unit, ~Tools.ToolDetails, ~V.Value, ~Export.unitValue, ~Tools.detailsValue, ~Export.rawValue, manager)

def model() -> Ai.Model<Ai.JsonValue>:
  +zero = F.fromU32(0)
  Ai.Model{"gpt-test", "Test", Ai.OpenAIResponsesApi{}, "openai", "https://example.test", False{}, None{}, Ai.InputText{} <> Nil{}, None{}, Ai.ModelCost{zero, zero, zero, zero, None{}}, None{}, F.fromU32(1000), F.fromU32(100), None{}, None{}, None{}}

def agentState() -> Export.AgentState():
  Agent.AgentState{model(), Ai.Off{}, Nil{}, Agent.LlmMessage{Ai.System{Ai.SystemMessage{Ai.SystemText{"System instructions <safe>"}, None{}, None{}, None{}, F.fromU32(0)}}} <> Nil{}, False{}, None{}, Set.empty(), None{}}

def assertion(ok: Bool, label: String) -> IO(Unit):
  Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.die(Unit, 1, label))

def checkedWrite(result: Export.Outcome(String)) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{path}:
      do IO<Unit>:
        assertion(String.ends_with(path, "/pi-session-export-html-source.html"), "wrong default output path")
        IO.print("PASS typed session HTML export")

def checkedFromFile(result: Export.Outcome(String)) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit, 1, message)
    case Done{path}:
      do IO<Unit>:
        assertion(String.ends_with(path, "/build/export-html-from-file.html"), "wrong explicit output path")
        IO.print("PASS standalone JSONL HTML export")

def checkedAssets(assets: Export.Outcome(Export.Assets), manager: Result<&2, &2, S.Error, State()>, created: Result<&2, &2, FS.Error, Unit>) -> IO(Unit):
  match assets manager created:
    case Fail{message} _ _: IO.die(Unit, 1, message)
    case _ Fail{_} _: IO.die(Unit, 1, "session restore failed")
    case _ _ Fail{_}: IO.die(Unit, 1, "source file creation failed")
    case Done{+assets} Done{+manager} Done{_}:
      +data = Export.sessionDataOf(manager, (V.Null{}, V.ArrayValue{Nil{}}))
      +raw = Export.json(data)
      +stored = {Persistence.Session{manager, "/tmp", "build", Some{Source()}, True{}, True{}} : Export.Session()}
      do IO<Unit>:
        assertion(String.contains(raw, "bash"), "tool call missing from typed export")
        assertion(String.contains(raw, "toolResult"), "tool result missing from typed export")
        assertion(String.contains(raw, "<script>alert(1)</script> & é"), "Unicode user message missing")
        result : Export.Outcome(String) <- Export.write(assets, stored, agentState(), None{})
        checkedWrite(result)
        standalone : Export.Outcome(String) <- Export.exportFromFile(assets, Source(), Some{"build/export-html-from-file.html"})
        checkedFromFile(standalone)

def main() -> IO(Unit):
  do IO<Unit>:
    assertion(String.eq(Export.payload(V.Text{"<script>é"}), "IjxzY3JpcHQ+w6ki"), "UTF-8 Base64 payload")
    +assets : Export.Outcome(Export.Assets) <- Export.loadAssets(AssetsDir())
    created : Result<&2, &2, FS.Error, Unit> <- FS.writeFile(Source(), sourceContent(session()))
    checkedAssets(assets, session(), created)
