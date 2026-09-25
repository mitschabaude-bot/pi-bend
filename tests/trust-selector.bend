import Base
import ../packages/runtime/src/record.bend as Record
import ../packages/tui/src/keybindings.bend as Keybindings
import ../packages/tui/src/keys.bend as Keys
import ../packages/coding-agent/src/core/keybindings.bend as AppKeys
import ../packages/coding-agent/src/core/trust-manager.bend as Trust
import ../packages/coding-agent/src/modes/interactive/components/trust-selector.bend as Selector
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as C
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/utils/ansi.bend as Ansi

# upstream test/trust-selector.test.ts (TrustSelectorComponent). The selector
# is a state value: Selector.new over getProjectTrustOptions(cwd), rendered
# with the dark theme and ANSI stripped; input is Selector.action and
# Selector.changed, and upstream's onSelect({trusted, updates}) is the option
# a confirm chooses. The cwd paths do not exist, so normalizeCwd keeps them.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def bindings() -> Keybindings.KeybindingsManager:
  Keybindings.create(AppKeys.KEYBINDINGS(AppKeys.Environment{"linux", None{}, None{}}), Record.new(List<&2, Keys.KeyId>))

def plain(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: Ansi.stripAnsi(line) <> plain(rest)

def output(+theme: Theme.Theme, state: Selector.State) -> String: String.join(plain(Selector.render(state, theme, bindings(), 120n)), "\n")

def pressed(state: Selector.State, +data: String) -> Selector.State: Selector.changed(state, Selector.action(bindings(), Keys.defaults(), data))

def saved(+path: String, decision: Bool) -> Maybe<&2, Trust.ProjectTrustStoreEntry>: Some{Trust.ProjectTrustStoreEntry{path, decision}}

def selector(+cwd: String, +savedDecision: Maybe<&2, Trust.ProjectTrustStoreEntry>, trusted: Bool) -> IO(Selector.State):
  do IO<Selector.State>:
    options : List<&2, Trust.ProjectTrustOption> <- Trust.getProjectTrustOptions(cwd, False{})
    return Selector.new(cwd, options, savedDecision, trusted)

# The selection a confirm reports: upstream's {trusted, updates}.
def updateText(updates: List<&2, Trust.ProjectTrustUpdate>) -> List<&2, String>:
  match updates:
    case Nil{}: Nil{}
    case Trust.ProjectTrustUpdate{path, None{}} <> rest: (path ++ "=null") <> updateText(rest)
    case Trust.ProjectTrustUpdate{path, Some{True{}}} <> rest: (path ++ "=true") <> updateText(rest)
    case Trust.ProjectTrustUpdate{path, Some{False{}}} <> rest: (path ++ "=false") <> updateText(rest)

def selectionText(option: Maybe<&2, Trust.ProjectTrustOption>) -> String:
  match option:
    case None{}: "none"
    case Some{Trust.ProjectTrustOption{_, trusted, updates, _}}: Bool.pick(String, trusted, "trusted", "untrusted") ++ " " ++ String.join(updateText(updates), ",")

def confirmedBy(action: Selector.Action, state: Selector.State) -> String:
  match action:
    case Selector.Confirm{}: selectionText(Selector.selectedOption(state))
    case _: "not confirmed"

def confirmed(state: Selector.State) -> String: confirmedBy(Selector.action(bindings(), Keys.defaults(), "\n"), state)

def keepsSavedMarked(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +state : Selector.State <- selector("/project", saved("/project", True{}), True{})
    +first : String = output(theme, state)
    check(String.contains(first, "Saved decision: trusted (/project)") && String.contains(first, "Current session: trusted") && String.contains(first, "→ ✓ Trust"), "keeps the saved trusted decision marked while browsing: initial")
    +second : String = output(theme, pressed(state, "\u{1b}[B"))
    check(String.contains(second, "✓ Trust") && String.contains(second, "→   Trust parent folder (/)") && Bool.not(String.contains(second, "✓ Do not trust")), "keeps the saved trusted decision marked while browsing: after down")

def selectsDecision() -> IO(Unit):
  do IO<Unit>:
    state : Selector.State <- selector("/project", None{}, False{})
    check(String.eq(confirmed(state), "trusted /project=true"), "selects a trust decision")

def labelsInherited(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    state : Selector.State <- selector("/parent/project/nested", saved("/parent", True{}), True{})
    check(String.contains(output(theme, state), "Saved decision: trusted (inherited from /parent)"), "labels saved ancestor decisions as inherited")

def addsParentOption(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    +state : Selector.State <- selector("/parent/project", saved("/parent", True{}), True{})
    +shown : String = output(theme, state)
    check(String.contains(shown, "Saved decision: trusted (inherited from /parent)") && String.contains(shown, "✓ Trust parent folder (/parent)"), "adds a trust parent option: rendered")
    check(String.eq(confirmed(state), "trusted /parent=true,/parent/project=null"), "adds a trust parent option: selection")

def run(result: Result<&2, &2, Theme.LoadError, Theme.Theme>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "FAIL cannot load the dark theme")
    case Done{+theme}:
      do IO<Unit>:
        keepsSavedMarked(theme)
        selectsDecision()
        labelsInherited(theme)
        addsParentOption(theme)

def main() -> IO(Unit):
  do IO<Unit>:
    dark : Result<&2, &2, Theme.LoadError, Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json", C.TrueColor{})
    run(dark)
