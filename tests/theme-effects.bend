import Base
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as MarkdownTheme

def describe(+text: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(Theme.bold(text))
    IO.print(Theme.italic(text))
    IO.print(Theme.underline(text))
    IO.print(Theme.inverse(text))
    IO.print(Theme.strikethrough(text))
    IO.print(Theme.bold(Theme.italic(text)))
    IO.print(MarkdownTheme.ansi(MarkdownTheme.Bold{},text))
    IO.print(MarkdownTheme.ansi(MarkdownTheme.Italic{},text))
    IO.print(MarkdownTheme.ansi(MarkdownTheme.Underline{},text))
    IO.print(MarkdownTheme.ansi(MarkdownTheme.Strike{},text))
def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        describe(text)
        run(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
