import Base
import ../packages/coding-agent/src/modes/interactive/external-editor.bend as Editor

def finished(result: Editor.ExternalEditorResult) -> IO(Unit):
  match result:
    case Editor.Failed{}: IO.print("failed")
    case Editor.Complete{content}: IO.print("complete:" ++ content)

def run(args: List<String>) -> IO(Unit):
  match args:
    case command <> content <> Nil{}:
      do IO<Unit>:
        result : Editor.ExternalEditorResult <- Editor.editInExternalEditor(Editor.ExternalEditorOptions{command,content})
        finished(result)
    case _: IO.die(Unit,1,"usage: COMMAND CONTENT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
