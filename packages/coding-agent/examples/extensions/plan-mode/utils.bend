import Base
import ../../../../runtime/src/ecma-regex.bend as Re
import ../../../../runtime/src/text.bend as Text

# pi v0.87.1 examples/extensions/plan-mode/utils.ts: pure helpers of the plan
# mode example (command safety, plan step extraction and completion
# markers). The patterns are upstream's JavaScript regular expressions,
# matched by runtime/src/ecma-regex.bend. cleanStepText capitalizes ASCII
# letters only (upstream: String.prototype.toUpperCase).

# Patterns
# --------

type Pattern is Data: Pattern{source: String, flags: String}

# Destructive commands blocked in plan mode.
def destructivePatterns() -> List<&2, Pattern>:
  [Pattern{"\\brm\\b", "i"}, Pattern{"\\brmdir\\b", "i"}, Pattern{"\\bmv\\b", "i"}, Pattern{"\\bcp\\b", "i"}, Pattern{"\\bmkdir\\b", "i"}, Pattern{"\\btouch\\b", "i"}, Pattern{"\\bchmod\\b", "i"}, Pattern{"\\bchown\\b", "i"}, Pattern{"\\bchgrp\\b", "i"}, Pattern{"\\bln\\b", "i"}, Pattern{"\\btee\\b", "i"}, Pattern{"\\btruncate\\b", "i"}, Pattern{"\\bdd\\b", "i"}, Pattern{"\\bshred\\b", "i"},
   Pattern{"(^|[^<])>(?!>)", ""}, Pattern{">>", ""},
   Pattern{"\\bnpm\\s+(install|uninstall|update|ci|link|publish)", "i"}, Pattern{"\\byarn\\s+(add|remove|install|publish)", "i"}, Pattern{"\\bpnpm\\s+(add|remove|install|publish)", "i"}, Pattern{"\\bpip\\s+(install|uninstall)", "i"}, Pattern{"\\bapt(-get)?\\s+(install|remove|purge|update|upgrade)", "i"}, Pattern{"\\bbrew\\s+(install|uninstall|upgrade)", "i"},
   Pattern{"\\bgit\\s+(add|commit|push|pull|merge|rebase|reset|checkout|branch\\s+-[dD]|stash|cherry-pick|revert|tag|init|clone)", "i"},
   Pattern{"\\bsudo\\b", "i"}, Pattern{"\\bsu\\b", "i"}, Pattern{"\\bkill\\b", "i"}, Pattern{"\\bpkill\\b", "i"}, Pattern{"\\bkillall\\b", "i"}, Pattern{"\\breboot\\b", "i"}, Pattern{"\\bshutdown\\b", "i"},
   Pattern{"\\bsystemctl\\s+(start|stop|restart|enable|disable)", "i"}, Pattern{"\\bservice\\s+\\S+\\s+(start|stop|restart)", "i"}, Pattern{"\\b(vim?|nano|emacs|code|subl)\\b", "i"}]

# Safe read-only commands allowed in plan mode.
def safePatterns() -> List<&2, Pattern>:
  [Pattern{"^\\s*cat\\b", ""}, Pattern{"^\\s*head\\b", ""}, Pattern{"^\\s*tail\\b", ""}, Pattern{"^\\s*less\\b", ""}, Pattern{"^\\s*more\\b", ""}, Pattern{"^\\s*grep\\b", ""}, Pattern{"^\\s*find\\b", ""}, Pattern{"^\\s*ls\\b", ""}, Pattern{"^\\s*pwd\\b", ""}, Pattern{"^\\s*echo\\b", ""}, Pattern{"^\\s*printf\\b", ""}, Pattern{"^\\s*wc\\b", ""}, Pattern{"^\\s*sort\\b", ""}, Pattern{"^\\s*uniq\\b", ""}, Pattern{"^\\s*diff\\b", ""}, Pattern{"^\\s*file\\b", ""}, Pattern{"^\\s*stat\\b", ""}, Pattern{"^\\s*du\\b", ""}, Pattern{"^\\s*df\\b", ""}, Pattern{"^\\s*tree\\b", ""}, Pattern{"^\\s*which\\b", ""}, Pattern{"^\\s*whereis\\b", ""}, Pattern{"^\\s*type\\b", ""}, Pattern{"^\\s*env\\b", ""}, Pattern{"^\\s*printenv\\b", ""}, Pattern{"^\\s*uname\\b", ""}, Pattern{"^\\s*whoami\\b", ""}, Pattern{"^\\s*id\\b", ""}, Pattern{"^\\s*date\\b", ""}, Pattern{"^\\s*cal\\b", ""}, Pattern{"^\\s*uptime\\b", ""}, Pattern{"^\\s*ps\\b", ""}, Pattern{"^\\s*top\\b", ""}, Pattern{"^\\s*htop\\b", ""}, Pattern{"^\\s*free\\b", ""},
   Pattern{"^\\s*git\\s+(status|log|diff|show|branch|remote|config\\s+--get)", "i"}, Pattern{"^\\s*git\\s+ls-", "i"}, Pattern{"^\\s*npm\\s+(list|ls|view|info|search|outdated|audit)", "i"}, Pattern{"^\\s*yarn\\s+(list|info|why|audit)", "i"}, Pattern{"^\\s*node\\s+--version", "i"}, Pattern{"^\\s*python\\s+--version", "i"}, Pattern{"^\\s*curl\\s", "i"}, Pattern{"^\\s*wget\\s+-O\\s*-", "i"},
   Pattern{"^\\s*jq\\b", ""}, Pattern{"^\\s*sed\\s+-n", "i"}, Pattern{"^\\s*awk\\b", ""}, Pattern{"^\\s*rg\\b", ""}, Pattern{"^\\s*fd\\b", ""}, Pattern{"^\\s*bat\\b", ""}, Pattern{"^\\s*eza\\b", ""}]

def matches(+pattern: Pattern, +text: String) -> Bool:
  match pattern:
    case Pattern{source, flags}: Result.default(&2, &2, Re.Error, Bool, Result.map(&2, &2, Re.Error, Re.RegExp, Bool, regex => Re.test(regex, text), Re.compile(source, flags)), False{})

def anyMatches(+patterns: List<&2, Pattern>, +text: String) -> Bool:
  match patterns:
    case Nil{}: False{}
    case pattern <> rest: matches(pattern, text) || anyMatches(rest, text)

def isSafeCommand(+command: String) -> Bool:
  Bool.not(anyMatches(destructivePatterns(), command)) && anyMatches(safePatterns(), command)

# Plan steps
# ----------

type TodoItem is Data:
  TodoItem{step: Nat, text: String, completed: Bool}

def slice(+text: String, +start: Nat, +end: Nat) -> String:
  String.take(String.drop(text, start), Nat.sub(end, start))

def captureText(+text: String, +capture: Maybe<&2, Re.Span>) -> String:
  match capture:
    case None{}: ""
    case Some{Re.Span{start, end}}: slice(text, start, end)

# How a match is replaced: by its first capture, or by a fixed text.
type Replacement is Data:
  FirstCapture{}
  Fixed{text: String}

def replacementOf(+replacement: Replacement, +text: String, +captures: List<&2, Maybe<&2, Re.Span>>) -> String:
  match replacement captures:
    case FirstCapture{} first <> _: captureText(text, first)
    case FirstCapture{} Nil{}: ""
    case Fixed{fixed} _: fixed

# String.prototype.replace with a regular expression: every match when
# `global`, otherwise the first; after an empty match the search goes on one
# scalar later. `done` is the replaced text before `position`.
def replaceLoop(fuel: Nat, +regex: Re.RegExp, +text: String, +global: Bool, +replacement: Replacement, +position: Nat, +found: Maybe<&2, Re.Match>, +done: String) -> String:
  match fuel found:
    case 0n _: done ++ String.drop(text, position)
    case _ None{}: done ++ String.drop(text, position)
    case 1n+rest Some{Re.Match{+index, +end, captures}}:
      +replaced = done ++ slice(text, position, index) ++ replacementOf(replacement, text, captures)
      +next = Bool.pick(Nat, Nat.is_eq(index, end), end + 1n, end)
      Bool.pick(Unit -> String, global && Nat.is_le(next, String.length(text)),
        _ => replaceLoop(rest, regex, text, global, replacement, next, Re.exec(regex, text, next), replaced ++ slice(text, end, next)),
        _ => replaced ++ String.drop(text, end))(Unit{})

def replaceCompiled(+compiled: Result<&2, &2, Re.Error, Re.RegExp>, +global: Bool, +replacement: Replacement, +text: String) -> String:
  match compiled:
    case Fail{_}: text
    case Done{regex}: replaceLoop(String.length(text) + 1n, regex, text, global, replacement, 0n, Re.exec(regex, text, 0n), "")

def replaceWith(+source: String, +flags: String, +global: Bool, +replacement: Replacement, +text: String) -> String:
  replaceCompiled(Re.compile(source, flags), global, replacement, text)

# upstream cleanStepText: markdown emphasis and code removed, a leading
# action word (and "the") dropped, whitespace collapsed, the first letter
# capitalized, and more than 50 characters cut to 47 and "...".
def capitalized(+text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, rest}: SCon{Chr{Re.upper(code)}, rest}

def truncated(+text: String) -> String:
  Bool.pick(String, Nat.is_gt(String.length(text), 50n), String.take(text, 47n) ++ "...", text)

def cleanStepText(+text: String) -> String:
  +emphasis = replaceWith("\\*{1,2}([^*]+)\\*{1,2}", "g", True{}, FirstCapture{}, text)
  +code = replaceWith("`([^`]+)`", "g", True{}, FirstCapture{}, emphasis)
  +action = replaceWith("^(Use|Run|Execute|Create|Write|Read|Check|Verify|Update|Modify|Add|Remove|Delete|Install)\\s+(the\\s+)?", "i", False{}, Fixed{""}, code)
  +spaced = Text.trim(replaceWith("\\s+", "g", True{}, Fixed{" "}, action))
  truncated(capitalized(spaced))

def execCompiled(+compiled: Result<&2, &2, Re.Error, Re.RegExp>, +text: String, +position: Nat) -> Maybe<&2, Re.Match>:
  match compiled:
    case Fail{_}: None{}
    case Done{regex}: Re.exec(regex, text, position)

def matchAt(+source: String, +flags: String, +text: String, +position: Nat) -> Maybe<&2, Re.Match>:
  execCompiled(Re.compile(source, flags), text, position)

# Every match of a global pattern from `position` (String.prototype.matchAll).
def matchesFrom(fuel: Nat, +regex: Re.RegExp, +text: String, +found: Maybe<&2, Re.Match>) -> List<&2, Re.Match>:
  match fuel found:
    case 0n _: Nil{}
    case _ None{}: Nil{}
    case 1n+rest Some{Re.Match{+index, +end, captures}}:
      +next = Bool.pick(Nat, Nat.is_eq(index, end), end + 1n, end)
      Re.Match{index, end, captures} <> Bool.pick(Unit -> List<&2, Re.Match>, Nat.is_le(next, String.length(text)), _ => matchesFrom(rest, regex, text, Re.exec(regex, text, next)), _ => Nil{})(Unit{})

def matchAllCompiled(+compiled: Result<&2, &2, Re.Error, Re.RegExp>, +text: String) -> List<&2, Re.Match>:
  match compiled:
    case Fail{_}: Nil{}
    case Done{regex}: matchesFrom(String.length(text) + 1n, regex, text, Re.exec(regex, text, 0n))

def matchAll(+source: String, +flags: String, +text: String) -> List<&2, Re.Match>:
  matchAllCompiled(Re.compile(source, flags), text)

def secondCapture(+captures: List<&2, Maybe<&2, Re.Span>>, +text: String) -> String:
  match captures:
    case _ <> second <> _: captureText(text, second)
    case _: ""

def firstCapture(+captures: List<&2, Maybe<&2, Re.Span>>, +text: String) -> String:
  match captures:
    case first <> _: captureText(text, first)
    case _: ""

def startsWithAny(+text: String) -> Bool:
  String.starts_with(text, "`") || String.starts_with(text, "/") || String.starts_with(text, "-")

# The items of the numbered list after the plan header, numbered in order.
def todoItems(+matches: List<&2, Re.Match>, +section: String, +items: List<&2, TodoItem>) -> List<&2, TodoItem>:
  match matches:
    case Nil{}: List.reverse(&2, TodoItem, items)
    case Re.Match{_, _, captures} <> rest:
      +text = Text.trim(replaceWith("\\*{1,2}$", "", False{}, Fixed{""}, Text.trim(secondCapture(captures, section))))
      +cleaned = cleanStepText(text)
      +kept = Nat.is_gt(String.length(text), 5n) && Bool.not(startsWithAny(text)) && Nat.is_gt(String.length(cleaned), 3n)
      todoItems(rest, section, Bool.pick(List<&2, TodoItem>, kept, TodoItem{List.length(&2, TodoItem, items) + 1n, cleaned, False{}} <> items, items))

def todoAfter(+message: String, +header: Maybe<&2, Re.Match>) -> List<&2, TodoItem>:
  match header:
    case None{}: Nil{}
    case Some{Re.Match{_, end, _}}:
      +section = String.drop(message, end)
      todoItems(matchAll("^\\s*(\\d+)[.)]\\s+\\*{0,2}([^*\\n]+)", "gm", section), section, Nil{})

# upstream extractTodoItems.
def extractTodoItems(+message: String) -> List<&2, TodoItem>:
  todoAfter(message, matchAt("\\*{0,2}Plan:\\*{0,2}\\s*\\n", "i", message, 0n))

def digitsValue(+digits: String, +value: Nat) -> Nat:
  match digits:
    case SNil{}: value
    case SCon{Chr{code}, rest}: digitsValue(rest, value * 10n + U32.to_nat(U32.sub(code, 48)))

def doneSteps(+matches: List<&2, Re.Match>, +message: String) -> List<&2, Nat>:
  match matches:
    case Nil{}: Nil{}
    case Re.Match{_, _, captures} <> rest: digitsValue(firstCapture(captures, message), 0n) <> doneSteps(rest, message)

# upstream extractDoneSteps: the numbers of the [DONE:n] markers, in order.
def extractDoneSteps(+message: String) -> List<&2, Nat>:
  doneSteps(matchAll("\\[DONE:(\\d+)\\]", "gi", message), message)

def containsStep(+steps: List<&2, Nat>, +step: Nat) -> Bool:
  match steps:
    case Nil{}: False{}
    case first <> rest: Nat.is_eq(first, step) || containsStep(rest, step)

def marked(+items: List<&2, TodoItem>, +steps: List<&2, Nat>) -> List<&2, TodoItem>:
  match items:
    case Nil{}: Nil{}
    case TodoItem{+step, text, completed} <> rest: TodoItem{step, text, completed || containsStep(steps, step)} <> marked(rest, steps)

# upstream markCompletedSteps: the items with the marked steps completed, and
# the number of markers found (upstream mutates the items in place).
def markCompletedSteps(+text: String, +items: List<&2, TodoItem>) -> List<&2, TodoItem> & Nat:
  +steps = extractDoneSteps(text)
  (marked(items, steps), List.length(&2, Nat, steps))
