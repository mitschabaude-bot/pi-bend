import Base
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as Styles
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/runtime/src/json.bend as Json

def value(lines: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: Json.quote(line) <> value(rest)
def shown(pair: Markdown.Markdown & List<&2,String>) -> String:
  match pair:
    case (_,lines): "[" ++ String.join(value(lines),",") ++ "]"
def one(source: String,theme: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    pair : Markdown.Markdown & List<&2,String> <- Markdown.render(Markdown.new(source,0n,0n,theme,None{},None{}),42n)
    IO.print(shown(pair))
def cases(+theme: Markdown.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    one("# Heading",theme)
    one("**bold** and *italic*",theme)
    one("[link](https://example.com)",theme)
    one("~~gone~~ and `code`",theme)
    one("> quoted",theme)
def withBorrowed(pair: Styles.Styles & Markdown.MarkdownTheme) -> IO(Unit):
  match pair:
    case (styles,theme):
      do IO<Unit>:
        cases(theme)
        Styles.dispose(styles)
def withStyles(styles: Styles.Styles) -> IO(Unit):
  withBorrowed(Styles.borrow(styles))
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Unit):
  match result:
    case Done{theme}:
      do IO<Unit>:
        styles : Styles.Styles <- Styles.create(theme)
        withStyles(styles)
    case Fail{_}: IO.die(Unit,1,"theme failed to load")
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
    loaded(result)
