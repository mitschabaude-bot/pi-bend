import Base
import ../packages/tui/src/components/markdown.bend as M
import ../packages/runtime/src/callback.bend as C
import ../packages/runtime/src/ref.bend as Ref

def plain(_: Unit,value: String) -> IO(String): IO.pure(String,value)
def theme(+style: C.Callback<String,String>) -> M.MarkdownTheme:
  M.MarkdownTheme{style,style,style,style,style,style,style,style,style,style,style,style,style,style,None{},None{}}
def cases() -> List<&2,String>:
  "hello" <> "hello world" <> "**bold**" <> "*italic*" <> "~~gone~~" <> "`code`" <> "# title" <> "## subtitle" <> "line\nnext" <> "hello\n\nworld" <> "- one\n- two" <> "1. one\n2. two" <> "> quoted" <> "---" <> "```js\nconst x = 1;\n```" <> "[site](https://example.com)" <> "a  \nb" <> "- outer\n  - inner\n- other" <> "3. a\n7. b" <> "# heading\nnext" <> "```js\nx\n```\nnext" <> "> a\n> b" <> "---\nnext" <> "simple <b>tag</b>" <> "\\*literal*" <> "~~foo~~ ~bar~" <> "```x\nfoo\n```\n" <> "| A | B |\n|---|---|\n| one | two |" <> "| A | B |\n|---|---|\n| x | y |\n| z | w |" <> Nil{}
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
    options : M.MarkdownOptions <- IO.pure(M.MarkdownOptions,M.MarkdownOptions{False{},False{},Some{callback},True{}})
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
    stateCases(theme(callback))
    C.dispose(String,String,callback)
