import Base
import ../packages/tui/src/components/markdown.bend as M
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref

def plain(_: Unit,value: String) -> IO(String): IO.pure(String,value)
def theme(+style: C.Callback<String,String>) -> M.MarkdownTheme:
  M.MarkdownTheme{style,style,style,style,style,style,style,style,style,style,style,style,style,style,None{},None{}}
def cases() -> List<&2,String>:
  "hello" <> "hello world" <> "**bold**" <> "*italic*" <> "~~gone~~" <> "`code`" <> "# title" <> "## subtitle" <> "line\nnext" <> "hello\n\nworld" <> "- one\n- two" <> "1. one\n2. two" <> "> quoted" <> "---" <> "```js\nconst x = 1;\n```" <> "[site](https://example.com)" <> "a  \nb" <> "- outer\n  - inner\n- other" <> "3. a\n7. b" <> "# heading\nnext" <> "```js\nx\n```\nnext" <> "> a\n> b" <> "---\nnext" <> "simple <b>tag</b>" <> "\\*literal*" <> "~~foo~~ ~bar~" <> "```x\nfoo\n```\n" <> "| A | B |\n|---|---|\n| one | two |" <> "| A | B |\n|---|---|\n| x | y |\n| z | w |" <> "| Keys | Action |\n| --- | --- |\n| `Ctrl+P` / `Ctrl+K` | choose |" <> Nil{}
def shown(+lines: List<&2,String>) -> String:
  Nat.show(List.length(&2,String,lines)) ++ ":" ++ String.join(lines,"|")
def result(pair: M.Markdown & List<&2,String>) -> String:
  match pair: case (_,lines): shown(lines)
def runOne(source: String,theme: M.MarkdownTheme) -> IO(String):
  do IO<String>:
    pair : M.Markdown & List<&2,String> <- M.render(M.new(source,0n,0n,theme,None{},None{}),20n)
    return result(pair)
def runWidth(source: String,width: Nat,theme: M.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    pair : M.Markdown & List<&2,String> <- M.render(M.new(source,0n,0n,theme,None{},None{}),width)
    IO.print(result(pair))
def runLinks(source: String,theme: M.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    pair : M.Markdown & List<&2,String> <- M.render(M.new(source,0n,0n,theme,None{},Some{M.MarkdownOptions{False{},False{},None{},True{},True{}}}),80n)
    IO.print(result(pair))
type Affix is Data: Affix{open: String,close: String}
def decorate(style: Affix,value: String) -> IO(String):
  match style: case Affix{open,close}: IO.pure(String,open ++ value ++ close)
def makeStyle(open: String,close: String) -> IO(C.Callback<String,String>):
  C.create(~Affix,~String,~String,~decorate,Affix{open,close})
def styledCases(+plain: C.Callback<String,String>) -> IO(Unit):
  do IO<Unit>:
    +heading : C.Callback<String,String> <- makeStyle("\u{1b}[36m","\u{1b}[39m")
    +code : C.Callback<String,String> <- makeStyle("\u{1b}[33m","\u{1b}[39m")
    +bold : C.Callback<String,String> <- makeStyle("\u{1b}[1m","\u{1b}[22m")
    +underline : C.Callback<String,String> <- makeStyle("\u{1b}[4m","\u{1b}[24m")
    +italic : C.Callback<String,String> <- makeStyle("\u{1b}[3m","\u{1b}[23m")
    +quote : C.Callback<String,String> <- makeStyle("\u{1b}[35m","\u{1b}[39m")
    +styled : M.MarkdownTheme <- IO.pure(M.MarkdownTheme,M.MarkdownTheme{heading,plain,plain,code,plain,plain,quote,plain,plain,plain,bold,italic,plain,underline,None{},None{}})
    runWidth("# Title with `code` inside",80n,styled)
    runWidth("## Heading with **bold** and more",80n,styled)
    runWidth("> Quote with **bold** and `code`",80n,styled)
    runWidth("plain `code` later",80n,styled)
    +gray : C.Callback<String,String> <- makeStyle("\u{1b}[90m","\u{1b}[39m")
    +defaultStyle : M.DefaultTextStyle <- IO.pure(M.DefaultTextStyle,M.DefaultTextStyle{Some{gray},None{},False{},True{},False{},False{}})
    defaultOne : M.Markdown & List<&2,String> <- M.render(M.new("gray `code` after",0n,0n,styled,Some{defaultStyle},None{}),80n)
    IO.print(result(defaultOne))
    defaultTwo : M.Markdown & List<&2,String> <- M.render(M.new("before **bold** after",0n,0n,styled,Some{defaultStyle},None{}),80n)
    IO.print(result(defaultTwo))
    runWidth("| Code |\n| --- |\n| `averyveryveryverylongidentifier` |",20n,styled)
    runWidth("| Plain | Link |\n| --- | --- |\n| normal | [short](https://example.com) |",35n,styled)
    C.dispose(String,String,gray)
    C.dispose(String,String,heading)
    C.dispose(String,String,code)
    C.dispose(String,String,bold)
    C.dispose(String,String,underline)
    C.dispose(String,String,italic)
    C.dispose(String,String,quote)
def runCases(inputs: List<&2,String>,+theme: M.MarkdownTheme) -> IO(Unit):
  match inputs:
    case Nil{}: IO.pure(Unit,Unit{})
    case source <> rest:
      do IO<Unit>:
        value : String <- runOne(source,theme)
        IO.print(value)
        runCases(rest,theme)
def transform(counter: Ref.Ref<Nat>,pair: String & Nat) -> IO(String):
  match pair:
    case (source,width):
      do IO<String>:
        value : Nat <- Ref.modify(Nat,Nat,counter,+old => (Succ{old},Succ{old}))
        return source ++ " " ++ Nat.show(width)
def stateResult(pair: M.Markdown & List<&2,String>) -> IO(M.Markdown):
  match pair:
    case (state,lines):
      do IO<M.Markdown>:
        IO.print(shown(lines))
        return state
def renderState(state: M.Markdown,width: Nat) -> IO(M.Markdown):
  do IO<M.Markdown>:
    pair : M.Markdown & List<&2,String> <- M.render(state,width)
    stateResult(pair)
def stateCases(theme: M.MarkdownTheme) -> IO(Unit):
  do IO<Unit>:
    +counter : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +callback : C.Callback<(String & Nat),String> <- C.create(~Ref.Ref<Nat>,~(String & Nat),~String,~transform,counter)
    options : M.MarkdownOptions <- IO.pure(M.MarkdownOptions,M.MarkdownOptions{False{},False{},Some{callback},True{},False{}})
    first : M.Markdown <- renderState(M.new("source",2n,0n,theme,None{},Some{options}),80n)
    second : M.Markdown <- renderState(first,80n)
    third : M.Markdown <- renderState(second,60n)
    fourth : M.Markdown <- renderState(M.setText(third,"updated"),60n)
    fifth : M.Markdown <- renderState(M.invalidate(fourth),60n)
    calls : Nat <- Ref.read(Nat,counter)
    IO.print(Nat.show(calls))
    C.dispose((String & Nat),String,callback)
    final : Nat <- Ref.dispose(Nat,counter)
    return Unit{}
def main() -> IO(Unit):
  do IO<Unit>:
    +callback : C.Callback<String,String> <- C.create(~Unit,~String,~String,~plain,Unit{})
    runCases(cases(),theme(callback))
    runWidth("- alpha beta gamma delta epsilon",20n,theme(callback))
    runWidth("1. alpha beta gamma delta epsilon",20n,theme(callback))
    runWidth("10. alpha beta gamma delta epsilon",21n,theme(callback))
    runWidth("- parent\n  - alpha beta gamma delta epsilon",24n,theme(callback))
    runWidth("1. parent\n   - alpha beta gamma delta epsilon",24n,theme(callback))
    runWidth("> This is a very long blockquote line that should wrap to multiple lines when rendered",30n,theme(callback))
    runWidth(">Foo\nbar",80n,theme(callback))
    runWidth(">Foo\n>bar",80n,theme(callback))
    runWidth("> 1. bla bla\n> - nested bullet",80n,theme(callback))
    runWidth("> Quote with **bold** and `code`",80n,theme(callback))
    runWidth("> One\n\nafter",20n,theme(callback))
    runWidth("| Command | Description | Example |\n| --- | --- | --- |\n| npm install | Install all dependencies | npm install |\n| npm run build | Build the project | npm run build |",50n,theme(callback))
    runWidth("| Header |\n| --- |\n| This is a very long cell content that should wrap |",25n,theme(callback))
    runWidth("| Value |\n| --- |\n| prefix https://example.com/this/is/a/very/long/url/that/should/wrap |",30n,theme(callback))
    runWidth("| Column One | Column Two |\n| --- | --- |\n| superlongword short | otherword |\n| small | tiny |",32n,theme(callback))
    runLinks("[click here](https://example.com)",theme(callback))
    runLinks("[Email me](mailto:test@example.com)",theme(callback))
    runLinks("[label](https://example.com) and more",theme(callback))
    runWidth("| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |",15n,theme(callback))
    runWidth("| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |",12n,theme(callback))
    runWidth("| Long | Header |\n| --- | --- |\n| words words words | split split split |",20n,theme(callback))
    styledCases(callback)
    runWidth("| Left | Center | Right |\n| :--- | :---: | ---: |\n| A | B | C |\n| Long text | Middle | End |",80n,theme(callback))
    stateCases(theme(callback))
    C.dispose(String,String,callback)
