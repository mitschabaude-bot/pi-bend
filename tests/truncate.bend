import Base
import ../packages/agent/src/harness/utils/truncate.bend as T

def check_bool(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def bool_equal(left: Bool, +right: Bool) -> Bool:
  Bool.pick(Bool, left, right, Bool.not(right))

def cause_equal(left: T.TruncationBy, right: T.TruncationBy) -> Bool:
  match left right:
    case T.NoLimit{} T.NoLimit{}: True{}
    case T.LineLimit{} T.LineLimit{}: True{}
    case T.ByteLimit{} T.ByteLimit{}: True{}
    case _ _: False{}

def check_result(+name: String, expected_content: String, expected_truncated: Bool, expected_cause: T.TruncationBy, expected_total_lines: Nat, expected_total_bytes: Nat, expected_output_lines: Nat, expected_output_bytes: Nat, expected_partial: Bool, expected_first_too_large: Bool, expected_max_lines: Nat, expected_max_bytes: Nat, result: T.TruncationResult) -> IO(Unit):
  match result:
    case T.TruncationResult{got_content, got_truncated, got_cause, got_total_lines, got_total_bytes, got_output_lines, got_output_bytes, got_partial, got_first_too_large, got_max_lines, got_max_bytes}:
      do IO<Unit>:
        check_bool(String.eq(expected_content, got_content), name ++ ": content")
        check_bool(bool_equal(expected_truncated, got_truncated), name ++ ": truncated")
        check_bool(cause_equal(expected_cause, got_cause), name ++ ": cause")
        check_bool(Nat.is_eq(expected_total_lines, got_total_lines), name ++ ": total lines")
        check_bool(Nat.is_eq(expected_total_bytes, got_total_bytes), name ++ ": total bytes")
        check_bool(Nat.is_eq(expected_output_lines, got_output_lines), name ++ ": output lines")
        check_bool(Nat.is_eq(expected_output_bytes, got_output_bytes), name ++ ": output bytes")
        check_bool(bool_equal(expected_partial, got_partial), name ++ ": partial")
        check_bool(bool_equal(expected_first_too_large, got_first_too_large), name ++ ": first-line limit")
        check_bool(Nat.is_eq(expected_max_lines, got_max_lines), name ++ ": max lines")
        check_bool(Nat.is_eq(expected_max_bytes, got_max_bytes), name ++ ": max bytes")

def check_line(+name: String, expected_text: String, expected_truncated: Bool, result: T.LineTruncation) -> IO(Unit):
  match result:
    case T.LineTruncation{got_text, got_truncated}:
      do IO<Unit>:
        check_bool(String.eq(expected_text, got_text), name ++ ": text")
        check_bool(bool_equal(expected_truncated, got_truncated), name ++ ": truncated")

def main() -> IO(Unit):
  do IO<Unit>:
    # Original content and its trailing newline are retained when no limit fires.
    check_result("head no truncation trailing newline", "a\nb\n", False{}, T.NoLimit{}, 2n, 4n, 2n, 4n, False{}, False{}, U32.to_nat(10), U32.to_nat(100), T.truncateHeadWithLimits("a\nb\n", U32.to_nat(10), U32.to_nat(100)))
    # Head truncation only emits complete lines and accounts for separators as bytes.
    check_result("head byte limit whole lines", "aa\nbbb", True{}, T.ByteLimit{}, 3n, 8n, 2n, 6n, False{}, False{}, U32.to_nat(10), 6n, T.truncateHeadWithLimits("aa\nbbb\nc", U32.to_nat(10), 6n))
    check_result("head line limit", "one\ntwo", True{}, T.LineLimit{}, 3n, 13n, 2n, 7n, False{}, False{}, 2n, U32.to_nat(100), T.truncateHeadWithLimits("one\ntwo\nthree", 2n, U32.to_nat(100)))
    check_result("head optional line limit", "one", True{}, T.LineLimit{}, 2n, 7n, 1n, 3n, False{}, False{}, 1n, U32.to_nat(51200), T.truncateHead("one\ntwo", T.TruncationOptions{Some{1n}, None{}}))
    # Byte limits cannot split the first line of a head result.
    check_result("head first line too large", "", True{}, T.ByteLimit{}, 2n, 6n, 0n, 0n, False{}, True{}, U32.to_nat(10), 3n, T.truncateHeadWithLimits("éé\nx", U32.to_nat(10), 3n))
    # A terminal newline counts as a terminator, not as an additional empty line.
    check_result("head zero line limit", "", True{}, T.LineLimit{}, 1n, 2n, 0n, 0n, False{}, False{}, 0n, U32.to_nat(10), T.truncateHeadWithLimits("x\n", 0n, U32.to_nat(10)))
    check_result("tail line limit", "two\nthree", True{}, T.LineLimit{}, 3n, 13n, 2n, 9n, False{}, False{}, 2n, U32.to_nat(100), T.truncateTailWithLimits("one\ntwo\nthree", 2n, U32.to_nat(100)))
    check_result("tail byte limit whole lines", "bbb\nc", True{}, T.ByteLimit{}, 3n, 8n, 2n, 5n, False{}, False{}, U32.to_nat(10), 6n, T.truncateTailWithLimits("aa\nbbb\nc", U32.to_nat(10), 6n))
    # The partial-tail path starts on a UTF-8 character boundary, not a byte continuation.
    check_result("tail UTF-8 partial line", "😊", True{}, T.ByteLimit{}, 1n, 7n, 1n, 4n, True{}, False{}, U32.to_nat(10), 5n, T.truncateTailWithLimits("aé😊", U32.to_nat(10), 5n))
    # Upstream prioritizes the line label after a partial last line fills maxLines.
    check_result("tail line label overrides byte", "", True{}, T.LineLimit{}, 1n, 4n, 1n, 0n, True{}, False{}, 1n, 0n, T.truncateTailWithLimits("éé", 1n, 0n))
    check_line("grep line", "abc... [truncated]", True{}, T.truncateLine("abcdef", 3n))
    check_line("grep UTF-16 split", "a" ++ SCon{Chr{55357}, "... [truncated]"}, True{}, T.truncateLine("a😊b", 2n))
    check_line("grep UTF-16 pair", "a😊... [truncated]", True{}, T.truncateLine("a😊b", 3n))
    check_bool(String.eq(T.formatSize(U32.to_nat(1024)), "1.0KB"), "format size")
    IO.print("truncate: all tests passed")
