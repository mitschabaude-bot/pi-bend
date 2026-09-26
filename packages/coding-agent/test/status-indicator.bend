import Base
import ../src/modes/interactive/components/status-indicator.bend as Status
import ../src/modes/interactive/theme/theme.bend as Theme
import ../src/modes/interactive/theme/color.bend as Color
import ../../../packages/runtime/src/callback.bend as Callback
import ../../../packages/runtime/src/ref.bend as Ref
import ../../../packages/tui/src/components/editor.bend as Editor
import ../../../packages/tui/src/components/select-list.bend as Select
import ../../../packages/tui/src/utils.bend as Utils

def check(valid: Bool,name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),valid,_ => IO.pure(Unit,Unit{}),_ => IO.die(Unit,1,name))(Unit{})
def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match result: case Done{value}: IO.pure(Theme.Theme,value) case Fail{_}: IO.die(Theme.Theme,1,"status theme failed to load")
def request(counter: Ref.Ref<Nat>,_: Unit) -> IO(Unit):
  Ref.modify(Nat,Unit,counter,previous => (previous + 1n,Unit{}))
def first(lines: List<&2,String>) -> String: Maybe.default(&2,String,List.get(&2,String,lines,0n),"")
def top(pair: Editor.Editor & List<&2,String>) -> IO(String):
  match pair:
    case (editor,lines):
      do IO<String>:
        Editor.dispose(editor)
        return first(lines)
def editor(+color: Callback.Callback<String,String>,status: Maybe<&2,String>,width: Nat) -> IO(String):
  do IO<String>:
    value : Editor.Editor <- Editor.new(Editor.EditorTheme{color,Select.SelectListTheme{color,color,color,color,color}},None{})
    result : Editor.Editor & List<&2,String> <- Editor.renderWithStatus(value,width,10n,status)
    top(result)
def ansi(theme: Theme.Theme,key: String) -> String:
  Theme.foregroundCode(theme,key)
def occurrences(+text: String,+needle: String) -> Nat:
  match text:
    case "": 0n
    case SCon{_,rest}: Bool.pick(Nat,String.starts_with(text,needle),1n,0n) + occurrences(rest,needle)
def testWorking(pair: Status.Owner & Status.Handle,+theme: Theme.Theme,+border: Callback.Callback<String,String>) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        rows : List<&2,String> <- Status.render(handle,20n)
        +body : String <- IO.pure(String,Maybe.default(&2,String,List.get(&2,String,rows,1n),""))
        plain : String <- editor(border,None{},20n)
        check(String.eq(Utils.stripTerminalSequences(plain),"────────────────────"),"keeps the top border unchanged unless the editor opts in")
        # Both default colors appear in a standalone status line.
        check(String.contains(body,ansi(theme,"accent")) && String.contains(body,ansi(theme,"muted")),"standalone working indicator uses accent and muted colors")
        Status.dispose(owner)
def testEmbedded(pair: Status.Owner & Status.Handle,+theme: Theme.Theme,+border: Callback.Callback<String,String>) -> IO(Unit):
  match pair:
    case (owner,handle):
      do IO<Unit>:
        label : String <- Status.renderInBorder(handle,20n)
        +line : String <- editor(border,Some{label},20n)
        check(String.eq(Utils.stripTerminalSequences(line),"── ⠋ Working ───────") && Nat.is_eq(Utils.visibleWidth(line),20n),"embeds the working indicator when the editor opts in")
        check(Nat.is_eq(occurrences(line,ansi(theme,"thinkingHigh")),4n),"embedded spinner and message follow the thinking border color")
        Status.dispose(owner)
def widths(values: List<&2,Nat>,+handle: Status.Handle,+border: Callback.Callback<String,String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +width <> rest:
      do IO<Unit>:
        label : String <- Status.renderInBorder(handle,width)
        line : String <- editor(border,Some{label},width)
        check(Nat.is_eq(Utils.visibleWidth(line),width),"embeds compaction, summary, and retry labels within the border width")
        widths(rest,handle,border)
def stopped(indicator: Status.Indicator,appearance: Status.Appearance) -> IO(Status.Owner):
  do IO<Status.Owner>:
    owner : Status.Owner <- Status.create(indicator,appearance)
    Status.stop(owner)
def testLabel(pair: Status.Owner & Status.Handle,expected: String,border: Callback.Callback<String,String>) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        label : String <- Status.renderInBorder(handle,120n)
        check(String.eq(Utils.stripTerminalSequences(label),"⠋ " ++ expected),"status label matches its reason")
        widths([1n,4n,10n,20n,80n,120n],handle,border)
        Status.dispose(owner)
def testCountdown(pair: Status.Owner & Status.Handle,+border: Callback.Callback<String,String>) -> IO(Unit):
  match pair:
    case (owner,+handle):
      do IO<Unit>:
        initial : String <- Status.renderInBorder(handle,120n)
        check(String.eq(Utils.stripTerminalSequences(initial),"⠋ Retrying (1/3) in 3s... (escape to cancel)"),"retry begins with the remaining rounded-up seconds")
        widths([1n,4n,10n,20n,80n,120n],handle,border)
        IO.sleep(1100)
        label : String <- Status.renderInBorder(handle,120n)
        line : String <- editor(border,Some{label},120n)
        check(String.contains(Utils.stripTerminalSequences(line),"Retrying (1/3) in 2s"),"retry countdown updates the embedded label")
        Status.dispose(owner)
        cleared : String <- editor(border,None{},120n)
        check(String.eq(Utils.stripTerminalSequences(cleared),Editor.repeat(120n,'─',"")),"clearing the status restores the plain border")
def cancelled(owner: Status.Owner,+counter: Ref.Ref<Nat>) -> IO(Unit):
  do IO<Unit>:
    before : Nat <- Ref.read(Nat,counter)
    Status.dispose(owner)
    IO.sleep(2100)
    after : Nat <- Ref.read(Nat,counter)
    check(Nat.is_eq(before,after),"disposes retry countdown updates")
def main() -> IO(Unit):
  do IO<Unit>:
    source : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.TrueColor{})
    +theme : Theme.Theme <- loaded(source)
    +live : Ref.Ref<Theme.Theme> <- Ref.new(Theme.Theme,theme)
    +counter : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    +redraw : Callback.Callback<Unit,Unit> <- Callback.create(~Ref.Ref<Nat>,~Unit,~Unit,~request,counter)
    +border : Callback.Callback<String,String> <- Callback.create(~Status.Paint,~String,~String,~Status.paint,Status.Paint{live,"thinkingHigh"})
    +appearance : Status.Appearance <- IO.pure(Status.Appearance,Status.Appearance{live,None{},redraw})
    +idle : List<&2,String> <- IO.pure(List<&2,String>,Status.idleStatus(20n))
    check(Nat.is_eq(List.length(&2,String,idle),2n) && Nat.is_eq(Utils.visibleWidth(first(idle)),20n) && String.eq(Utils.trimEnd(String.join(idle,"")),""),"keeps idle status at the same height as standalone status indicators")
    working : Status.Owner <- stopped(Status.WorkingStatusIndicator{"Working",None{}},appearance)
    testWorking(Status.borrow(working),theme,border)
    embedded : Status.Owner <- stopped(Status.WorkingStatusIndicator{"Working",None{}},Status.Appearance{live,Some{border},redraw})
    testEmbedded(Status.borrow(embedded),theme,border)
    manual : Status.Owner <- stopped(Status.CompactionStatusIndicator{Status.Manual{},"escape"},appearance)
    testLabel(Status.borrow(manual),"Compacting context... (escape to cancel)",border)
    threshold : Status.Owner <- stopped(Status.CompactionStatusIndicator{Status.Threshold{},"escape"},appearance)
    testLabel(Status.borrow(threshold),"Auto-compacting... (escape to cancel)",border)
    overflow : Status.Owner <- stopped(Status.CompactionStatusIndicator{Status.Overflow{},"escape"},appearance)
    testLabel(Status.borrow(overflow),"Context overflow detected, Auto-compacting... (escape to cancel)",border)
    branch : Status.Owner <- stopped(Status.BranchSummaryStatusIndicator{"escape"},appearance)
    testLabel(Status.borrow(branch),"Summarizing branch... (escape to cancel)",border)
    retry : Status.Owner <- stopped(Status.RetryStatusIndicator{1n,3n,3000n,"escape"},appearance)
    testCountdown(Status.borrow(retry),border)
    canceled : Status.Owner <- Status.create(Status.RetryStatusIndicator{1n,3n,1000n,"escape"},appearance)
    cancelled(canceled,counter)
    Callback.dispose(String,String,border)
    Callback.dispose(Unit,Unit,redraw)
    discarded : Nat <- Ref.dispose(Nat,counter)
    unused : Theme.Theme <- Ref.dispose(Theme.Theme,live)
    IO.print("status-indicator.test.ts: PASS")
