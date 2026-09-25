import Base
import ../../../../../runtime/src/f64.bend as F
import ../../../../../runtime/src/number-string.bend as NumberString
import ../../../../../tui/src/components/text.bend as TuiText
import ../../../core/cache-stats.bend as Cache
import ../../../core/usage-totals.bend as Usage
import ../theme/theme.bend as Theme
import ./footer.bend as Footer

# upstream interactive-mode handleSessionCommand: the /session summary.
type SessionInfo is Data:
  SessionInfo{name: Maybe<&2, String>, sessionFile: Maybe<&2, String>, sessionId: String, totalMessages: Nat, userMessages: Nat, assistantMessages: Nat, toolCalls: Nat, toolResults: Nat, input: F64, output: F64, cacheRead: F64, cacheWrite: F64, cost: F64, waste: Cache.CacheWasteTotals, breakdown: List<&2, Usage.UsageCostBreakdownEntry>}

def paint(theme: Theme.Theme, key: String, +text: String) -> String:
  Result.default(&2, &2, Theme.Error, String, Theme.foreground(theme, key, text), text)
def bold(text: String) -> String: "\u{1b}[1m" ++ text ++ "\u{1b}[22m"
def zero() -> F64: F.fromU32(0)

# Number.prototype.toFixed and en-US toLocaleString of an integer count.
def fixed(value: F64, digits: Nat) -> String: Maybe.default(&2, String, NumberString.formatFixed(value, digits), "")
def consed(char: Char, rest: String) -> String: SCon{char, rest}
# `count` is the number of digits from this one to the end; a separator
# precedes every later digit that starts a group of three.
def grouped(digits: String, +count: Nat) -> String:
  match digits:
    case SNil{}: ""
    case SCon{char, rest}:
      +tail = consed(char, grouped(rest, count - 1n))
      Bool.pick(String, Nat.is_eq(Nat.mod(count, 3n), 0n), "," ++ tail, tail)
def groupedDigits(+digits: String) -> String:
  match digits:
    case SCon{first, rest}: SCon{first, grouped(rest, String.length(digits) - 1n)}
    case SNil{}: ""
def localeCount(value: F64) -> String: groupedDigits(fixed(value, 0n))

def labelled(theme: Theme.Theme, label: String, +value: String) -> String: paint(theme, "dim", label) ++ " " ++ value

def nameLine(+theme: Theme.Theme, name: Maybe<&2, String>) -> String:
  match name:
    case None{}: ""
    case Some{value}: labelled(theme, "Name:", value) ++ "\n"

# With cache activity the prompt splits into cached and uncached tokens (the
# provider-independent split); reported cache writes are part of uncached.
def cacheLines(+theme: Theme.Theme, +input: F64, +cacheRead: F64, +cacheWrite: F64, +prompt: F64) -> String:
  Bool.pick(Unit -> String, F64.is_gt(prompt, zero()) && (F64.is_gt(cacheRead, zero()) || F64.is_gt(cacheWrite, zero())),
    _ => "  " ++ labelled(theme, "Cached:", localeCount(cacheRead) ++ " " ++ paint(theme, "dim", "(" ++ fixed(F.multiply(F.divide(cacheRead, prompt), F.fromU32(100)), 1n) ++ "%)")) ++ "\n"
      ++ "  " ++ labelled(theme, "Uncached:", localeCount(F.add(input, cacheWrite)) ++ Bool.pick(String, F64.is_gt(cacheWrite, zero()), " " ++ paint(theme, "dim", "(" ++ localeCount(cacheWrite) ++ " written to cache)"), "")) ++ "\n",
    _ => "")(Unit{})

def breakdownLines(+theme: Theme.Theme, entries: List<&2, Usage.UsageCostBreakdownEntry>) -> String:
  match entries:
    case Nil{}: ""
    case Usage.UsageCostBreakdownEntry{key, cost, tokens} <> rest:
      "\n  " ++ paint(theme, "dim", key ++ ":") ++ " $" ++ fixed(cost, 3n) ++ " " ++ paint(theme, "dim", "(" ++ Footer.tokens(U32.to_nat(F64.to_u32(tokens))) ++ " tokens)") ++ breakdownLines(theme, rest)

def breakdown(+theme: Theme.Theme, +entries: List<&2, Usage.UsageCostBreakdownEntry>) -> String:
  Bool.pick(String, Nat.is_gt(List.length(&2, Usage.UsageCostBreakdownEntry, entries), 1n), breakdownLines(theme, entries), "")

def wasteLine(+theme: Theme.Theme, waste: Cache.CacheWasteTotals) -> String:
  match waste:
    case Cache.CacheWasteTotals{+tokens, +cost, +count}:
      +misses = Bool.pick(String, Nat.is_eq(count, 1n), "1 miss", Nat.show(count) ++ " misses")
      +detail = localeCount(tokens) ++ " tokens, " ++ misses
      Bool.pick(String, F64.is_gt(tokens, zero()),
        Bool.pick(String, Bool.not(F64.is_lt(cost, F.divide(F.fromU32(1), F.fromU32(10000)))),
          "\n" ++ labelled(theme, "Cache Re-billed:", "$" ++ fixed(cost, 3n) ++ " " ++ paint(theme, "dim", "(" ++ detail ++ ")")),
          "\n" ++ labelled(theme, "Cache Re-billed:", detail)),
        "")

def missedTokens(waste: Cache.CacheWasteTotals) -> F64:
  match waste: case Cache.CacheWasteTotals{tokens, _, _}: tokens

def costSection(+theme: Theme.Theme, +cost: F64, +waste: Cache.CacheWasteTotals, entries: List<&2, Usage.UsageCostBreakdownEntry>) -> String:
  Bool.pick(Unit -> String, F64.is_gt(cost, zero()) || F64.is_gt(missedTokens(waste), zero()),
    _ => "\n" ++ bold("Cost") ++ "\n" ++ labelled(theme, "Total:", "$" ++ fixed(cost, 3n)) ++ breakdown(theme, entries) ++ wasteLine(theme, waste),
    _ => "")(Unit{})

def text(+theme: Theme.Theme, info: SessionInfo) -> String:
  match info:
    case SessionInfo{name, file, id, total, users, assistants, calls, results, +input, +output, +cacheRead, +cacheWrite, +cost, +waste, entries}:
      +prompt = F.add(input, F.add(cacheRead, cacheWrite))
      bold("Session Info") ++ "\n\n" ++ nameLine(theme, name)
        ++ labelled(theme, "File:", Maybe.default(&2, String, file, "In-memory")) ++ "\n"
        ++ labelled(theme, "ID:", id) ++ "\n\n"
        ++ bold("Messages") ++ "\n"
        ++ labelled(theme, "Total:", Nat.show(total)) ++ "\n"
        ++ labelled(theme, "User:", Nat.show(users)) ++ "\n"
        ++ labelled(theme, "Assistant:", Nat.show(assistants)) ++ "\n"
        ++ labelled(theme, "Tools:", Nat.show(calls) ++ " calls, " ++ Nat.show(results) ++ " results") ++ "\n\n"
        ++ bold("Tokens") ++ "\n"
        ++ labelled(theme, "Input:", localeCount(prompt)) ++ "\n"
        ++ cacheLines(theme, input, cacheRead, cacheWrite, prompt)
        ++ labelled(theme, "Output:", localeCount(output)) ++ "\n"
        ++ labelled(theme, "Total:", localeCount(F.add(prompt, output))) ++ "\n"
        ++ costSection(theme, cost, waste, entries)

def lines(pair: TuiText.Text & List<&2, String>) -> List<&2, String>:
  match pair: case (_, value): value
# A spacer, then the text with one column of horizontal padding.
def render(info: SessionInfo, theme: Theme.Theme, width: Nat) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    rendered : TuiText.Text & List<&2, String> <- TuiText.render(TuiText.new(text(theme, info), Some{1n}, Some{0n}, None{}), width)
    return "" <> lines(rendered)
