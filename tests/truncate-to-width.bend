import Base
import ../packages/tui/src/utils.bend as U

# upstream packages/coding-agent/test/truncate-to-width.test.ts: pi-tui's
# truncateToWidth with upstream's default ellipsis "..." and no padding,
# measured with visibleWidth. (packages/tui/test/truncate-to-width.test.ts is
# covered by tests/ansi_layout_check.py.)

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def truncated(+message: String, +maxWidth: Nat) -> String: U.truncateToWidth(message, maxWidth, "...", False{})

def fits(+message: String, +maxWidth: Nat) -> Bool: Nat.is_le(U.visibleWidth(truncated(message, maxWidth)), maxWidth)

def main() -> IO(Unit):
  do IO<Unit>:
    check(fits("✔ script to run › dev $ concurrently \"vite\" \"node --import tsx ./", 67n - 2n), "should truncate messages with Unicode characters correctly")
    check(fits("🎉 Celebration! 🚀 Launch 📦 Package ready for deployment now", 40n - 2n), "should handle emoji characters")
    check(fits("Hello 世界 Test 你好 More text here that is long", 30n - 2n), "should handle mixed ASCII and wide characters")
    check(String.eq(truncated("Short message", 50n - 2n), "Short message") && fits("Short message", 50n - 2n), "should not truncate messages that fit")
    check(String.contains(truncated("This is a very long message that needs to be truncated", 30n - 2n), "...") && fits("This is a very long message that needs to be truncated", 30n - 2n), "should add ellipsis when truncating")
    check(Nat.is_le(U.visibleWidth(truncated("✔ script to run › dev $ concurrently \"vite\" \"node --import tsx ./server.ts\"", 67n - 2n)) + 2n, 67n), "should handle the exact crash case from issue report")
