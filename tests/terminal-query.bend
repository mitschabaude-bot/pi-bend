import Base
import ../packages/runtime/src/callback.bend as Callback
import ../packages/tui/src/terminal-query.bend as Query
import ../packages/tui/src/terminal-colors.bend as Colors

def write(channel: Chan(String),value: String) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(String,channel,value)
    return Unit{}
def color(value: Maybe<&2,Colors.RgbColor>) -> String:
  match value:
    case None{}: "none"
    case Some{Colors.RgbColor{r,g,b}}: U32.show(r) ++ "," ++ U32.show(g) ++ "," ++ U32.show(b)
def scheme(value: Maybe<&2,Colors.TerminalColorScheme>) -> String:
  match value:
    case None{}: "none"
    case Some{Colors.Dark{}}: "dark"
    case Some{Colors.Light{}}: "light"
def observe(ignored: Unit,value: Colors.TerminalColorScheme) -> IO(Unit):
  IO.print("listener:" ++ scheme(Some{value}))
def colorCase(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    query : Chan(Maybe<&2,Colors.RgbColor>) <- IO.fork(Maybe<&2,Colors.RgbColor>,Query.colorQuery(handle,writer,200))
    sent : Maybe<&1,String> <- Chan.recv(String,writes)
    IO.print("write:" ++ Maybe.default(&1,String,sent,"closed"))
    ignored : Bool <- Query.consume(handle,"x")
    IO.print("ordinary:" ++ Bool.show(ignored))
    consumed : Bool <- Query.consume(handle,"\u{1b}]11;#ff8040\u{7}")
    answer : Maybe<&2,Colors.RgbColor> <- IO.join(Maybe<&2,Colors.RgbColor>,query)
    IO.print("color:" ++ Bool.show(consumed) ++ ":" ++ color(answer))
def malformedCase(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    query : Chan(Maybe<&2,Colors.RgbColor>) <- IO.fork(Maybe<&2,Colors.RgbColor>,Query.colorQuery(handle,writer,200))
    sent : Maybe<&1,String> <- Chan.recv(String,writes)
    consumed : Bool <- Query.consume(handle,"\u{1b}]11;not-a-color\u{7}")
    answer : Maybe<&2,Colors.RgbColor> <- IO.join(Maybe<&2,Colors.RgbColor>,query)
    IO.print("malformed:" ++ Bool.show(consumed) ++ ":" ++ color(answer))
def lateCase(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    query : Chan(Maybe<&2,Colors.RgbColor>) <- IO.fork(Maybe<&2,Colors.RgbColor>,Query.colorQuery(handle,writer,1))
    sent : Maybe<&1,String> <- Chan.recv(String,writes)
    answer : Maybe<&2,Colors.RgbColor> <- IO.join(Maybe<&2,Colors.RgbColor>,query)
    consumed : Bool <- Query.consume(handle,"\u{1b}]11;#ffffff\u{7}")
    IO.print("late:" ++ color(answer) ++ ":" ++ Bool.show(consumed))
def orderedCase(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    old : Chan(Maybe<&2,Colors.RgbColor>) <- IO.fork(Maybe<&2,Colors.RgbColor>,Query.colorQuery(handle,writer,1))
    first : Maybe<&1,String> <- Chan.recv(String,writes)
    expired : Maybe<&2,Colors.RgbColor> <- IO.join(Maybe<&2,Colors.RgbColor>,old)
    next : Chan(Maybe<&2,Colors.RgbColor>) <- IO.fork(Maybe<&2,Colors.RgbColor>,Query.colorQuery(handle,writer,200))
    second : Maybe<&1,String> <- Chan.recv(String,writes)
    oldConsumed : Bool <- Query.consume(handle,"\u{1b}]11;#000000\u{7}")
    nextConsumed : Bool <- Query.consume(handle,"\u{1b}]11;#ffffff\u{7}")
    fresh : Maybe<&2,Colors.RgbColor> <- IO.join(Maybe<&2,Colors.RgbColor>,next)
    IO.print("ordered:" ++ color(expired) ++ ":" ++ Bool.show(oldConsumed) ++ ":" ++ Bool.show(nextConsumed) ++ ":" ++ color(fresh))
def schemeCase(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    query : Chan(Maybe<&2,Colors.TerminalColorScheme>) <- IO.fork(Maybe<&2,Colors.TerminalColorScheme>,Query.schemeQuery(handle,writer,200))
    sent : Maybe<&1,String> <- Chan.recv(String,writes)
    IO.print("scheme-write:" ++ Maybe.default(&1,String,sent,"closed"))
    consumed : Bool <- Query.consume(handle,"\u{1b}[?997;1n")
    answer : Maybe<&2,Colors.TerminalColorScheme> <- IO.join(Maybe<&2,Colors.TerminalColorScheme>,query)
    IO.print("scheme:" ++ Bool.show(consumed) ++ ":" ++ scheme(answer))
def schemeTimeout(+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,writes: Chan(String)) -> IO(Unit):
  do IO<Unit>:
    query : Chan(Maybe<&2,Colors.TerminalColorScheme>) <- IO.fork(Maybe<&2,Colors.TerminalColorScheme>,Query.schemeQuery(handle,writer,1))
    sent : Maybe<&1,String> <- Chan.recv(String,writes)
    invalid : Bool <- Query.consume(handle,"\u{1b}[?997;3n")
    answer : Maybe<&2,Colors.TerminalColorScheme> <- IO.join(Maybe<&2,Colors.TerminalColorScheme>,query)
    IO.print("scheme-timeout:" ++ Bool.show(invalid) ++ ":" ++ scheme(answer))
def run(owner: Query.Owner,+handle: Query.Handle,+writer: Callback.Callback<String,Unit>,+writes: Chan(String),+listener: Callback.Callback<Colors.TerminalColorScheme,Unit>) -> IO(Unit):
  do IO<Unit>:
    colorCase(handle,writer,writes)
    malformedCase(handle,writer,writes)
    lateCase(handle,writer,writes)
    orderedCase(handle,writer,writes)
    Query.setNotifications(handle,writer,True{})
    Query.setRunning(handle,writer,True{})
    enabled : Maybe<&1,String> <- Chan.recv(String,writes)
    IO.print("notification:" ++ Maybe.default(&1,String,enabled,"closed"))
    listenerId : Nat <- Query.onSchemeChange(handle,listener)
    schemeCase(handle,writer,writes)
    Query.offSchemeChange(handle,listenerId)
    schemeTimeout(handle,writer,writes)
    Query.setRunning(handle,writer,False{})
    disabled : Maybe<&1,String> <- Chan.recv(String,writes)
    IO.print("notification:" ++ Maybe.default(&1,String,disabled,"closed"))
    Query.close(owner)
    Callback.dispose(String,Unit,writer)
    Callback.dispose(Colors.TerminalColorScheme,Unit,listener)
def borrowed(pair: Query.Owner & Query.Handle,writer: Callback.Callback<String,Unit>,writes: Chan(String),+listener: Callback.Callback<Colors.TerminalColorScheme,Unit>) -> IO(Unit):
  match pair:
    case (owned,handle): run(owned,handle,writer,writes,listener)
def main() -> IO(Unit):
  do IO<Unit>:
    +writes : Chan(String) <- Chan.new(String,8)
    +writer : Callback.Callback<String,Unit> <- Callback.create(~Chan(String),~String,~Unit,~write,writes)
    +listener : Callback.Callback<Colors.TerminalColorScheme,Unit> <- Callback.create(~Unit,~Colors.TerminalColorScheme,~Unit,~observe,Unit{})
    owner : Query.Owner <- Query.create()
    borrowed(Query.borrow(owner),writer,writes,listener)
