import Base
import ./theme.bend as Theme
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../utils/syntax-highlight.bend as SyntaxHighlight

# The theme document owns colors; this value owns the callbacks borrowed by
# Markdown components. Retire those components before disposing these styles.
type ColorStyle is Data: ColorStyle{theme: Ref.Ref<Theme.Theme>,key: String}
type Effect is Data: Bold{} Italic{} Underline{} Strike{}
type Styles is Type: Styles{markdown: Markdown.MarkdownTheme,callbacks: List<&2,Callback.Callback<String,String>>,theme: Ref.Ref<Theme.Theme>,highlighter: SyntaxHighlight.Highlighter}

def colorResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{value}: IO.pure(String,value)
    case Fail{_}: IO.die(String,1,"invalid Markdown theme color")
def colored(style: ColorStyle,text: String) -> IO(String):
  match style:
    case ColorStyle{theme,key}:
      do IO<String>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        colorResult(Theme.foreground(current,key,text))
def ansi(effect: Effect,text: String) -> String:
  match effect:
    case Bold{}: "\u{1b}[1m" ++ text ++ "\u{1b}[22m"
    case Italic{}: "\u{1b}[3m" ++ text ++ "\u{1b}[23m"
    case Underline{}: "\u{1b}[4m" ++ text ++ "\u{1b}[24m"
    case Strike{}: "\u{1b}[9m" ++ text ++ "\u{1b}[29m"
def effectStyle(effect: Effect,text: String) -> IO(String): IO.pure(String,ansi(effect,text))
def color(theme: Ref.Ref<Theme.Theme>,key: String) -> IO(Callback.Callback<String,String>):
  Callback.create(~ColorStyle,~String,~String,~colored,ColorStyle{theme,key})
def effect(value: Effect) -> IO(Callback.Callback<String,String>):
  Callback.create(~Effect,~String,~String,~effectStyle,value)
# getMarkdownTheme().highlightCode: code blocks highlighted with the current
# theme; a failed highlight keeps the code-block colour.
type CodeStyle is Data: CodeStyle{theme: Ref.Ref<Theme.Theme>,highlighter: SyntaxHighlight.Highlighter}
def highlighted(style: CodeStyle,input: Markdown.HighlightInput) -> IO(List<&2,String>):
  match style input:
    case CodeStyle{theme,highlighter} Markdown.HighlightInput{code,lang}:
      do IO<List<&2,String>>:
        current : Theme.Theme <- Ref.read(Theme.Theme,theme)
        Theme.highlightLines(highlighter,current,code,lang,True{})
def create(+theme: Theme.Theme,+highlighter: SyntaxHighlight.Highlighter) -> IO(Styles):
  do IO<Styles>:
    +live : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
    highlight : Callback.Callback<Markdown.HighlightInput,List<&2,String>> <- Callback.create(~CodeStyle,~Markdown.HighlightInput,~List<&2,String>,~highlighted,CodeStyle{live,highlighter})
    +heading : Callback.Callback<String,String> <- color(live,"mdHeading")
    +link : Callback.Callback<String,String> <- color(live,"mdLink")
    +url : Callback.Callback<String,String> <- color(live,"mdLinkUrl")
    +code : Callback.Callback<String,String> <- color(live,"mdCode")
    +block : Callback.Callback<String,String> <- color(live,"mdCodeBlock")
    +blockBorder : Callback.Callback<String,String> <- color(live,"mdCodeBlockBorder")
    +quote : Callback.Callback<String,String> <- color(live,"mdQuote")
    +quoteBorder : Callback.Callback<String,String> <- color(live,"mdQuoteBorder")
    +rule : Callback.Callback<String,String> <- color(live,"mdHr")
    +bullet : Callback.Callback<String,String> <- color(live,"mdListBullet")
    +bold : Callback.Callback<String,String> <- effect(Bold{})
    +italic : Callback.Callback<String,String> <- effect(Italic{})
    +strike : Callback.Callback<String,String> <- effect(Strike{})
    +underline : Callback.Callback<String,String> <- effect(Underline{})
    return Styles{Markdown.MarkdownTheme{heading,link,url,code,block,blockBorder,quote,quoteBorder,rule,bullet,bold,italic,strike,underline,Some{highlight},None{},Markdown.newParser()},heading <> link <> url <> code <> block <> blockBorder <> quote <> quoteBorder <> rule <> bullet <> bold <> italic <> strike <> underline <> Nil{},live,highlighter}
def theme(styles: Styles) -> Markdown.MarkdownTheme:
  match styles:
    case Styles{value,_,_,_}: value
def live(styles: Styles) -> Ref.Ref<Theme.Theme>:
  match styles: case Styles{_,_,liveTheme,_}: liveTheme
def borrow(styles: Styles) -> Styles & Markdown.MarkdownTheme:
  match styles:
    case Styles{+value,callbacks,liveTheme,highlighter}: (Styles{value,callbacks,liveTheme,highlighter},value)
def disposeCallbacks(values: List<&2,Callback.Callback<String,String>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case callback <> rest:
      do IO<Unit>:
        Callback.dispose(String,String,callback)
        disposeCallbacks(rest)
def disposeHighlight(theme: Markdown.MarkdownTheme) -> IO(Unit):
  match theme:
    case Markdown.MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,Some{highlight},_,_}: Callback.dispose(Markdown.HighlightInput,List<&2,String>,highlight)
    case _: IO.pure(Unit,Unit{})
def dispose(styles: Styles) -> IO(Unit):
  match styles:
    case Styles{markdown,callbacks,liveTheme,_}:
      do IO<Unit>:
        disposeHighlight(markdown)
        disposeCallbacks(callbacks)
        old : Theme.Theme <- Ref.dispose(Theme.Theme,liveTheme)
        return Unit{}
