import Base
import ./theme.bend as Theme
import ../../../../../tui/src/components/markdown.bend as Markdown
import ../../../../../runtime/src/callback.bend as Callback

# The theme document owns colors; this value owns the callbacks borrowed by
# Markdown components. Retire those components before disposing these styles.
type ColorStyle is Data: ColorStyle{theme: Theme.Theme,key: String}
type Effect is Data: Bold{} Italic{} Underline{} Strike{}
type Styles is Type: Styles{markdown: Markdown.MarkdownTheme,callbacks: List<&2,Callback.Callback<String,String>>}

def colorResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{value}: IO.pure(String,value)
    case Fail{_}: IO.die(String,1,"invalid Markdown theme color")
def colored(style: ColorStyle,text: String) -> IO(String):
  match style:
    case ColorStyle{theme,key}: colorResult(Theme.foreground(theme,key,text))
def ansi(effect: Effect,text: String) -> String:
  match effect:
    case Bold{}: "\u{1b}[1m" ++ text ++ "\u{1b}[22m"
    case Italic{}: "\u{1b}[3m" ++ text ++ "\u{1b}[23m"
    case Underline{}: "\u{1b}[4m" ++ text ++ "\u{1b}[24m"
    case Strike{}: "\u{1b}[9m" ++ text ++ "\u{1b}[29m"
def effectStyle(effect: Effect,text: String) -> IO(String): IO.pure(String,ansi(effect,text))
def color(theme: Theme.Theme,key: String) -> IO(Callback.Callback<String,String>):
  Callback.create(~ColorStyle,~String,~String,~colored,ColorStyle{theme,key})
def effect(value: Effect) -> IO(Callback.Callback<String,String>):
  Callback.create(~Effect,~String,~String,~effectStyle,value)
def create(+theme: Theme.Theme) -> IO(Styles):
  do IO<Styles>:
    +heading : Callback.Callback<String,String> <- color(theme,"mdHeading")
    +link : Callback.Callback<String,String> <- color(theme,"mdLink")
    +url : Callback.Callback<String,String> <- color(theme,"mdLinkUrl")
    +code : Callback.Callback<String,String> <- color(theme,"mdCode")
    +block : Callback.Callback<String,String> <- color(theme,"mdCodeBlock")
    +blockBorder : Callback.Callback<String,String> <- color(theme,"mdCodeBlockBorder")
    +quote : Callback.Callback<String,String> <- color(theme,"mdQuote")
    +quoteBorder : Callback.Callback<String,String> <- color(theme,"mdQuoteBorder")
    +rule : Callback.Callback<String,String> <- color(theme,"mdHr")
    +bullet : Callback.Callback<String,String> <- color(theme,"mdListBullet")
    +bold : Callback.Callback<String,String> <- effect(Bold{})
    +italic : Callback.Callback<String,String> <- effect(Italic{})
    +strike : Callback.Callback<String,String> <- effect(Strike{})
    +underline : Callback.Callback<String,String> <- effect(Underline{})
    return Styles{Markdown.MarkdownTheme{heading,link,url,code,block,blockBorder,quote,quoteBorder,rule,bullet,bold,italic,strike,underline,None{},None{}},heading <> link <> url <> code <> block <> blockBorder <> quote <> quoteBorder <> rule <> bullet <> bold <> italic <> strike <> underline <> Nil{}}
def theme(styles: Styles) -> Markdown.MarkdownTheme:
  match styles:
    case Styles{value,_}: value
def borrow(styles: Styles) -> Styles & Markdown.MarkdownTheme:
  match styles:
    case Styles{+value,callbacks}: (Styles{value,callbacks},value)
def disposeCallbacks(values: List<&2,Callback.Callback<String,String>>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case callback <> rest:
      do IO<Unit>:
        Callback.dispose(String,String,callback)
        disposeCallbacks(rest)
def dispose(styles: Styles) -> IO(Unit):
  match styles:
    case Styles{_,callbacks}: disposeCallbacks(callbacks)
