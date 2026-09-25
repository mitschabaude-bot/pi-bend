import Base
import ../packages/runtime/src/record.bend as Record
import ../packages/tui/src/keybindings.bend as Keybindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/tui/src/utils.bend as U
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/modes/interactive/components/messages.bend as Messages
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme

# upstream test/bash-execution-width.test.ts (#2569): BashExecutionComponent's
# collapsed output respects the width of each render. The port's bash message
# is a value rendered by Messages.renderBash(state, width); upstream's
# setComplete(0, false) after appendOutput is completeBash with the same
# output and exit code 0.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def bindings() -> Keybindings.KeybindingsManager:
  Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux", None{}, None{}}), Record.new(List<&2, Keys.KeyId>))

def fit(lines: List<&2, String>, +width: Nat) -> Bool:
  match lines:
    case Nil{}: True{}
    case line <> rest: Nat.is_le(U.visibleWidth(line), width) && fit(rest, width)

def completed(+theme: Theme.Theme, +command: String, +output: String) -> Messages.BashMessage:
  Messages.completeBash(Messages.appendBash(Messages.bash(command, False{}, theme, False{}, bindings()), output), output, Some{0}, False{}, False{}, None{})

def collapsedPreview(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +line : String = String.repeat("x", 150n)
    lines : List<&2, String> <- Messages.renderBash(completed(theme, "pwd", line ++ "\n" ++ line ++ "\n"), 80n)
    check(fit(lines, 80n), "collapsed preview lines respect render-time width, not construction-time width")

def recomputes(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +state : Messages.BashMessage = completed(theme, "echo hello", String.repeat("abcdefghij", 20n) ++ "\n")
    wide : List<&2, String> <- Messages.renderBash(state, 200n)
    narrow : List<&2, String> <- Messages.renderBash(state, 60n)
    check(fit(wide, 200n) && fit(narrow, 60n), "re-computes lines when width changes between renders")

def run(result: Result<&2, &2, Theme.LoadError, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "FAIL cannot load the dark theme")
    case Done{+theme}:
      do IO<Unit>:
        collapsedPreview(theme)
        recomputes(theme)

def main() -> IO(Unit):
  do IO<Unit>:
    dark : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json", C.Palette256{})
    run(dark)
