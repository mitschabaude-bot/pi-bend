import Base
import ../packages/coding-agent/src/core/tools/renderers/write.bend as Write
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/coding-agent/src/modes/interactive/theme/markdown-theme.bend as MdTheme
import ../packages/coding-agent/src/utils/syntax-highlight.bend as SyntaxHighlight
import ../packages/tui/src/components/markdown.bend as Markdown
import ../packages/runtime/src/callback.bend as Callback
import ../packages/runtime/src/ref.bend as Ref
import ../packages/runtime/src/schema-value.bend as Value
import ../packages/runtime/src/record.bend as R

# Streamed write previews (upstream writeRenderers.renderCall with the
# component's highlight cache). Arguments: path, then pairs of
# "partial"/"complete" and the content so far. Prints each expanded call text.
def loaded(value: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match value: case Done{theme}: IO.pure(Theme.Theme,theme) case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def args(+path: String,content: String) -> Value.Value:
  Value.ObjectValue{R.Record{R.Property{"path",Value.Text{path}} <> R.Property{"content",Value.Text{content}} <> Nil{}}}
def steps(rest: List<String>,+highlight: Callback.Callback<Markdown.HighlightInput,List<&2,String>>,+theme: Theme.Theme,+path: String,cache: Maybe<&2,Write.WriteHighlightCache>) -> IO(Unit):
  match rest:
    case kind <> content <> more:
      do IO<Unit>:
        +value : Value.Value <- IO.pure(Value.Value,args(path,content))
        +next : Maybe<&2,Write.WriteHighlightCache> <- Write.refreshCache(Some{highlight},value,String.eq(kind,"complete"),cache)
        text : String <- Write.renderCall(value,Some{highlight},next,theme,True{})
        IO.print(text ++ "\u{1e}")
        steps(more,highlight,theme,path,next)
    case _: IO.pure(Unit,Unit{})
def run(+theme: Theme.Theme,+highlighter: SyntaxHighlight.Highlighter,arguments: List<String>) -> IO(Unit):
  match arguments:
    case path <> rest:
      do IO<Unit>:
        +live : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
        +highlight : Callback.Callback<Markdown.HighlightInput,List<&2,String>> <- Callback.create(~MdTheme.CodeStyle,~Markdown.HighlightInput,~List<&2,String>,~MdTheme.highlighted,MdTheme.CodeStyle{live,highlighter})
        steps(rest,highlight,theme,path,None{})
    case Nil{}: IO.die(Unit,1,"expected a path")
def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    loadedTheme : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(loadedTheme)
    highlighter : SyntaxHighlight.Highlighter <- SyntaxHighlight.create("packages/runtime/data/highlight")
    run(theme,highlighter,arguments)
