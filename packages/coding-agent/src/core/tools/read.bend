import Base
import ./truncate.bend as Truncate
import ../../../../runtime/src/string.bend as Strings

type ReadToolInput is Data:
  ReadToolInput{path: String, offset: Maybe<&2, Nat>, limit: Maybe<&2, Nat>}

type ReadToolDetails is Data:
  ReadToolDetails{truncation: Truncate.TruncationResult}

type TextResult is Data:
  TextResult{text: String, details: Maybe<&2, ReadToolDetails>}

type Error is Data:
  OffsetBeyondEnd{offset: Nat, totalLines: Nat}

def errorMessage(error: Error) -> String:
  match error:
    case OffsetBeyondEnd{offset, total}:
      "Offset " ++ Nat.show(offset) ++ " is beyond end of file (" ++ Nat.show(total) ++ " lines total)"

def continuation(cause: Maybe<&2, Truncate.Limit>) -> String:
  match cause:
    case Some{Truncate.Lines{}}: ""
    case _: " (" ++ Truncate.formatSize(Truncate.DEFAULT_MAX_BYTES()) ++ " limit)"

def remainingNotice(+text: String, start: Nat, +total: Nat, limited: Maybe<&2, Nat>) -> TextResult:
  match limited:
    case None{}: TextResult{text, None{}}
    case Some{count}:
      +end = start + count
      Bool.pick(Unit -> TextResult, Nat.is_lt(end, total),
        unused => TextResult{text ++ "\n\n[" ++ Nat.show(total - end) ++ " more lines in file. Use offset=" ++ Nat.show(1n + end) ++ " to continue.]", None{}},
        unused => TextResult{text, None{}})(Unit{})

def render(path: String, +start: Nat, total: Nat, firstLineBytes: Nat, limited: Maybe<&2, Nat>, +truncation: Truncate.TruncationResult) -> TextResult:
  match truncation:
    case Truncate.TruncationResult{_, _, _, _, _, _, _, _, True{}, _, _}:
      +line = Nat.show(1n + start)
      +maximum = Truncate.DEFAULT_MAX_BYTES()
      TextResult{"[Line " ++ line ++ " is " ++ Truncate.formatSize(firstLineBytes) ++ ", exceeds " ++ Truncate.formatSize(maximum) ++ " limit. Use bash: sed -n '" ++ line ++ "p' -- " ++ Strings.quoteShell(path) ++ " | head -c " ++ Nat.show(maximum) ++ "]", Some{ReadToolDetails{truncation}}}
    case Truncate.TruncationResult{content, True{}, cause, _, _, outputLines, _, _, False{}, _, _}:
      +end = start + outputLines
      TextResult{content ++ "\n\n[Showing lines " ++ Nat.show(1n + start) ++ "-" ++ Nat.show(end) ++ " of " ++ Nat.show(total) ++ continuation(cause) ++ ". Use offset=" ++ Nat.show(1n + end) ++ " to continue.]", Some{ReadToolDetails{truncation}}}
    case Truncate.TruncationResult{content, False{}, _, _, _, _, _, _, False{}, _, _}:
      remainingNotice(content, start, total, limited)

def firstLineBytes(lines: List<&2, String>) -> Nat:
  match lines:
    case Nil{}: 0n
    case first <> _: Truncate.byteLength(first)

def selected(path: String, +start: Nat, +total: Nat, +remaining: List<&2, String>, limit: Maybe<&2, Nat>) -> TextResult:
  match limit:
    case None{}:
      render(path, start, total, firstLineBytes(remaining), None{}, Truncate.truncateHead(String.join(remaining, "\n"), Truncate.TruncationOptions{None{}, None{}}))
    case Some{+count}:
      render(path, start, total, firstLineBytes(remaining), Some{Nat.min(count, total - start)}, Truncate.truncateHead(String.join(List.take(&2, String, remaining, count), "\n"), Truncate.TruncationOptions{None{}, None{}}))

# Offset and limit are natural line counts. An absent or zero offset starts at
# the first line, as in Pi. The public argument decoder must reject fractions
# and negative counts before reaching this pure operation.
def readText(input: ReadToolInput, content: String) -> Result<&2, &2, Error, TextResult>:
  match input:
    case ReadToolInput{path, offset, limit}:
      +lines = Strings.split(content, '\n')
      +total = Truncate.countLines(lines, 0n)
      +offset = Maybe.default(&2, Nat, offset, 1n)
      +start = offset - 1n
      Bool.pick(Unit -> Result<&2, &2, Error, TextResult>, Nat.is_ge(start, total),
        unused => Fail{OffsetBeyondEnd{offset, total}},
        unused => Done{selected(path, start, total, List.drop(&2, String, lines, start), limit)})(Unit{})
