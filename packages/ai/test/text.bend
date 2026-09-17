import Base
import ../src/types.bend as T
import ../src/utils/text.bend as Text
import ../../runtime/src/record.bend as R
import ../../runtime/src/f64.bend as N

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def main() -> IO(Unit):
  do IO<Unit>:
    +content : Text.ContentInput<Unit> = Text.ContentBlocks{Text.TextBlock{T.TextContent{"", None{}}} <> Text.ImageBlock{T.ImageContent{"data", "image/png"}} <> Text.ThinkingBlock{T.ThinkingContent{"hidden", None{}, None{}}} <> Text.TextBlock{T.TextContent{"visible", None{}}} <> Text.ToolCallBlock{T.ToolCall{"id", "tool", Unit{}, None{}, None{}}} <> Text.TextBlock{T.TextContent{"", None{}}} <> Nil{}}
    assertion(String.eq(Text.contentTextDefault(Unit, content), "\nvisible\n"), "only text blocks contribute; empty text blocks retain separators")
    assertion(String.eq(Text.contentText(Unit, content, "::"), "::visible::"), "custom separator")
    assertion(String.eq(Text.contentText(Unit, Text.ContentString{"unchanged\ntext"}, "::"), "unchanged\ntext"), "string content passes through unchanged")
    sections : R.Record<Maybe<&2, String>> = R.set(Maybe<&2, String>, R.set(Maybe<&2, String>, R.set(Maybe<&2, String>, R.set(Maybe<&2, String>, R.new(Maybe<&2, String>), "a", Some{"last"}), "10", Some{"ten"}), "2", Some{"two"}), "empty", Some{""})
    +message : T.SystemMessage<Unit> = T.SystemMessage{T.SystemBlocks{T.TextContent{"", None{}} <> T.TextContent{"base", None{}} <> Nil{}}, Some{sections}, None{}, None{}, N.fromU32(0)}
    assertion(String.eq(Text.renderComplete(Unit, message), "\nbase\n\ntwo\n\nten\n\nlast"), "numeric key order and omitted empty sections")
    assertion(String.eq(Text.renderUpdate(Unit, message), "\nbase\n\nUpdated system prompt section \"2\":\n\ntwo\n\nUpdated system prompt section \"10\":\n\nten\n\nUpdated system prompt section \"a\":\n\nlast\n\nUpdated system prompt section \"empty\":\n\n"), "empty updates still include their framing")
    IO.print("PASS text filtering, separators, section enumeration and empty update framing")
