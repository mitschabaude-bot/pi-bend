import Base

# Limits for tool output, matching the coding agent's truncation policy.
type TruncationBy is Data:
  NoLimit{}
  LineLimit{}
  ByteLimit{}

type TruncationResult is Data:
  TruncationResult{content: String, truncated: Bool, truncatedBy: TruncationBy, totalLines: Nat, totalBytes: Nat, outputLines: Nat, outputBytes: Nat, lastLinePartial: Bool, firstLineExceedsLimit: Bool, maxLines: Nat, maxBytes: Nat}

type LineTruncation is Data:
  LineTruncation{text: String, wasTruncated: Bool}

# TypeScript's optional fields are explicit Maybe values in Bend.
type TruncationOptions is Data:
  TruncationOptions{maxLines: Maybe<&2, Nat>, maxBytes: Maybe<&2, Nat>}

type Collected is Data:
  Collected{items: List<&2, String>, bytes: Nat, lines: Nat, byte_limit_hit: Bool}

type TailCollected is Data:
  TailCollected{items: List<&2, String>, bytes: Nat, lines: Nat, byte_limit_hit: Bool, lastLinePartial: Bool}

def DEFAULT_MAX_LINES() -> Nat:
  U32.to_nat(2000)

def DEFAULT_MAX_BYTES() -> Nat:
  U32.to_nat(51200)

def GREP_MAX_LINE_LENGTH() -> Nat:
  U32.to_nat(500)

def byte_width(+c: Char) -> Nat:
  +code = Char.to_u32(c)
  Bool.pick(Nat, U32.is_lt(code, 128), 1n, Bool.pick(Nat, U32.is_lt(code, 2048), 2n, Bool.pick(Nat, U32.is_lt(code, 65536), 3n, 4n)))

def byte_length(s: String) -> Nat:
  match s:
    case SNil{}: 0n
    case SCon{c, rest}: Nat.add(byte_width(c), byte_length(rest))

# This differs from String.split only in making the trailing-empty-line rule
# explicit: an ending newline terminates a line but does not add another one.
def count_lines_scan(s: String, +reversed_line: String) -> List<&2, String>:
  match s:
    case SNil{}: Bool.pick(List<&2, String>, String.is_empty(reversed_line), Nil{}, String.reverse(reversed_line) <> Nil{})
    case SCon{'\n', rest}: String.reverse(reversed_line) <> count_lines_scan(rest, "")
    case SCon{c, rest}: count_lines_scan(rest, SCon{c, reversed_line})

def split_lines_for_counting(s: String) -> List<&2, String>:
  count_lines_scan(s, "")

def first_line_bytes(lines: List<&2, String>) -> Nat:
  match lines:
    case Nil{}: 0n
    case line <> rest: byte_length(line)

def separator_bytes(line_count: Nat) -> Nat:
  match line_count:
    case 0n: 0n
    case 1n+rest: 1n

def truncate_string_to_bytes_from_end_drop(s: String, bytes_to_drop: Nat) -> String:
  match s bytes_to_drop:
    case s 0n: s
    case SNil{} 1n+remaining: ""
    case SCon{c, rest} 1n+remaining:
      +available = (1n + remaining : Nat)
      truncate_string_to_bytes_from_end_drop(rest, Nat.sub(available, byte_width(c)))

def truncate_string_to_bytes_from_end(+s: String, +maxBytes: Nat) -> String:
  +total = byte_length(s)
  Bool.pick(String, Nat.is_le(total, maxBytes), s, truncate_string_to_bytes_from_end_drop(s, Nat.sub(total, maxBytes)))

# Buffer/TextEncoder replaces unpaired UTF-16 units when a partial tail is decoded.
def replace_unpaired(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+c, rest}:
      +code = Char.to_u32(c)
      SCon{Bool.pick(Char, U32.is_ge(code, 55296) && U32.is_le(code, 57343), Chr{65533}, c), replace_unpaired(rest)}

def collect_head_loop(lines: List<&2, String>, remaining_lines: Nat, +reversed_output: List<&2, String>, +outputBytes: Nat, +outputLines: Nat, +maxBytes: Nat) -> Collected:
  match lines remaining_lines:
    case Nil{} _: Collected{List.reverse(&2, String, reversed_output), outputBytes, outputLines, False{}}
    case lines 0n: Collected{List.reverse(&2, String, reversed_output), outputBytes, outputLines, False{}}
    case +line <> rest 1n+remaining:
      +line_bytes = Nat.add(byte_length(line), separator_bytes(outputLines))
      +next_bytes = Nat.add(outputBytes, line_bytes)
      Bool.pick(Collected, Nat.is_gt(next_bytes, maxBytes), Collected{List.reverse(&2, String, reversed_output), outputBytes, outputLines, True{}}, collect_head_loop(rest, remaining, line <> reversed_output, next_bytes, 1n+outputLines, maxBytes))

def tail_overflow(line: String, maxBytes: Nat, +output: List<&2, String>, outputBytes: Nat, +outputLines: Nat) -> TailCollected:
  +partial = replace_unpaired(truncate_string_to_bytes_from_end(line, maxBytes))
  Bool.pick(TailCollected, Nat.is_eq(outputLines, 0n), TailCollected{partial <> output, byte_length(partial), 1n, True{}, True{}}, TailCollected{output, outputBytes, outputLines, True{}, False{}})

def collect_tail_loop(reversed_lines: List<&2, String>, remaining_lines: Nat, +output: List<&2, String>, +outputBytes: Nat, +outputLines: Nat, +maxBytes: Nat) -> TailCollected:
  match reversed_lines remaining_lines:
    case Nil{} _: TailCollected{output, outputBytes, outputLines, False{}, False{}}
    case lines 0n: TailCollected{output, outputBytes, outputLines, False{}, False{}}
    case +line <> rest 1n+remaining:
      +line_bytes = Nat.add(byte_length(line), separator_bytes(outputLines))
      +next_bytes = Nat.add(outputBytes, line_bytes)
      Bool.pick(TailCollected, Nat.is_gt(next_bytes, maxBytes), tail_overflow(line, maxBytes, output, outputBytes, outputLines), collect_tail_loop(rest, remaining, line <> output, next_bytes, 1n+outputLines, maxBytes))

def selected_limit(outputLines: Nat, outputBytes: Nat, maxLines: Nat, maxBytes: Nat, byte_limit_hit: Bool) -> TruncationBy:
  +line_limit_hit = Nat.is_ge(outputLines, maxLines) && Nat.is_le(outputBytes, maxBytes)
  Bool.pick(TruncationBy, line_limit_hit, LineLimit{}, Bool.pick(TruncationBy, byte_limit_hit, ByteLimit{}, LineLimit{}))

def no_truncation(content: String, +totalLines: Nat, +totalBytes: Nat, maxLines: Nat, maxBytes: Nat) -> TruncationResult:
  TruncationResult{content, False{}, NoLimit{}, totalLines, totalBytes, totalLines, totalBytes, False{}, False{}, maxLines, maxBytes}

def first_line_too_large(totalLines: Nat, totalBytes: Nat, maxLines: Nat, maxBytes: Nat) -> TruncationResult:
  TruncationResult{"", True{}, ByteLimit{}, totalLines, totalBytes, 0n, 0n, False{}, True{}, maxLines, maxBytes}

def head_result_from_collected(collected: Collected, +totalLines: Nat, +totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  match collected:
    case Collected{items, outputBytes, +outputLines, byte_limit_hit}:
      +output = String.join(items, "\n")
      TruncationResult{output, True{}, selected_limit(outputLines, outputBytes, maxLines, maxBytes, byte_limit_hit), totalLines, totalBytes, outputLines, byte_length(output), False{}, False{}, maxLines, maxBytes}

def truncate_head_needed(lines: List<&2, String>, totalLines: Nat, totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  head_result_from_collected(collect_head_loop(lines, maxLines, Nil{}, 0n, 0n, maxBytes), totalLines, totalBytes, maxLines, maxBytes)

def truncate_head_choose(first_too_large: Bool, lines: List<&2, String>, +totalLines: Nat, +totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  Bool.pick(TruncationResult, first_too_large, first_line_too_large(totalLines, totalBytes, maxLines, maxBytes), truncate_head_needed(lines, totalLines, totalBytes, maxLines, maxBytes))

def truncateHeadWithLimits(+content: String, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  +totalBytes = byte_length(content)
  +lines = split_lines_for_counting(content)
  +totalLines = List.length(&2, String, lines)
  +within_limits = Nat.is_le(totalLines, maxLines) && Nat.is_le(totalBytes, maxBytes)
  +first_too_large = Nat.is_gt(first_line_bytes(lines), maxBytes)
  Bool.pick(TruncationResult, within_limits, no_truncation(content, totalLines, totalBytes, maxLines, maxBytes), truncate_head_choose(first_too_large, lines, totalLines, totalBytes, maxLines, maxBytes))

def defaultOptions() -> TruncationOptions:
  TruncationOptions{None{}, None{}}

def truncateHead(content: String, options: TruncationOptions) -> TruncationResult:
  match options:
    case TruncationOptions{lines, bytes}: truncateHeadWithLimits(content, Maybe.default(&2, Nat, lines, DEFAULT_MAX_LINES()), Maybe.default(&2, Nat, bytes, DEFAULT_MAX_BYTES()))

def tail_result_from_collected(collected: TailCollected, +totalLines: Nat, +totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  match collected:
    case TailCollected{items, outputBytes, +outputLines, byte_limit_hit, lastLinePartial}:
      +output = String.join(items, "\n")
      TruncationResult{output, True{}, selected_limit(outputLines, outputBytes, maxLines, maxBytes, byte_limit_hit), totalLines, totalBytes, outputLines, byte_length(output), lastLinePartial, False{}, maxLines, maxBytes}

def truncate_tail_needed(lines: List<&2, String>, totalLines: Nat, totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  tail_result_from_collected(collect_tail_loop(List.reverse(&2, String, lines), maxLines, Nil{}, 0n, 0n, maxBytes), totalLines, totalBytes, maxLines, maxBytes)

def truncate_tail_choose(within_limits: Bool, content: String, lines: List<&2, String>, +totalLines: Nat, +totalBytes: Nat, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  Bool.pick(TruncationResult, within_limits, no_truncation(content, totalLines, totalBytes, maxLines, maxBytes), truncate_tail_needed(lines, totalLines, totalBytes, maxLines, maxBytes))

def truncateTailWithLimits(+content: String, +maxLines: Nat, +maxBytes: Nat) -> TruncationResult:
  +totalBytes = byte_length(content)
  +lines = split_lines_for_counting(content)
  +totalLines = List.length(&2, String, lines)
  +within_limits = Nat.is_le(totalLines, maxLines) && Nat.is_le(totalBytes, maxBytes)
  truncate_tail_choose(within_limits, content, lines, totalLines, totalBytes, maxLines, maxBytes)

def truncateTail(content: String, options: TruncationOptions) -> TruncationResult:
  match options:
    case TruncationOptions{lines, bytes}: truncateTailWithLimits(content, Maybe.default(&2, Nat, lines, DEFAULT_MAX_LINES()), Maybe.default(&2, Nat, bytes, DEFAULT_MAX_BYTES()))

def utf16_length(s: String) -> Nat:
  match s:
    case SNil{}: 0n
    case SCon{c, rest}: Nat.add(Bool.pick(Nat, U32.is_gt(Char.to_u32(c), 65535), 2n, 1n), utf16_length(rest))

def take_characters(s: String, remaining: Nat) -> String:
  match s remaining:
    case SNil{} _: ""
    case s 0n: ""
    case SCon{+c, rest} 1n:
      +code = Char.to_u32(c)
      SCon{Bool.pick(Char, U32.is_gt(code, 65535), Chr{(55296 + (code - 65536) / 1024 : U32)}, c), SNil{}}
    case SCon{+c, rest} 2n+remaining:
      width = Bool.pick(Nat, U32.is_gt(Char.to_u32(c), 65535), 2n, 1n)
      SCon{c, take_characters(rest, Nat.sub(2n+remaining, width))}

def truncateLine(+line: String, +max_chars: Nat) -> LineTruncation:
  Bool.pick(LineTruncation, Nat.is_le(utf16_length(line), max_chars), LineTruncation{line, False{}}, LineTruncation{take_characters(line, max_chars) ++ "... [truncated]", True{}})

def truncateLineDefault(line: String) -> LineTruncation:
  truncateLine(line, GREP_MAX_LINE_LENGTH())

def format_tenths(bytes: Nat, +unit: Nat) -> String:
  +tenths = Nat.div(Nat.add(Nat.mul(bytes, U32.to_nat(10)), Nat.div(unit, 2n)), unit)
  Nat.show(Nat.div(tenths, U32.to_nat(10))) ++ "." ++ Nat.show(Nat.mod(tenths, U32.to_nat(10)))

def formatSize(+bytes: Nat) -> String:
  Bool.pick(String, Nat.is_lt(bytes, U32.to_nat(1024)), Nat.show(bytes) ++ "B", Bool.pick(String, Nat.is_lt(bytes, U32.to_nat(1048576)), format_tenths(bytes, U32.to_nat(1024)) ++ "KB", format_tenths(bytes, U32.to_nat(1048576)) ++ "MB"))
