import Base
import ../src/string.bend as Text

# replaceAll against JavaScript's String.prototype.replaceAll; the expected
# values were produced by Bun for the same (text, pattern, replacement).

def check(+text: String, +pattern: String, +replacement: String, +expected: String) -> IO(Unit):
  +actual = Text.replaceAll(text, pattern, replacement)
  Bool.pick(IO(Unit), String.eq(actual, expected), IO.print("PASS " ++ text ++ " / " ++ pattern ++ " -> " ++ actual), IO.die(Unit, 1, "FAIL " ++ text ++ " / " ++ pattern ++ ": " ++ actual ++ " != " ++ expected))

def main() -> IO(Unit):
  do IO<Unit>:
    check("a{X}b{X}{X}", "{X}", "yy", "ayybyyyy")
    check("aaa", "aa", "b", "ba")
    check("abc", "", "-", "-a-b-c-")
    check("", "", "-", "-")
    check("", "x", "-", "")
    check("abc", "zz", "-", "abc")
    check("abcab", "ab", "", "c")
    check("aaaa", "aa", "a", "aa")
    check("ab", "abc", "-", "ab")
    check("xaxa", "a", "aa", "xaaxaa")
