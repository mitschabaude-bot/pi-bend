import Base
import ../packages/coding-agent/src/cli/initial-message.bend as Initial

# upstream test/initial-message.test.ts (buildInitialMessage). Upstream shifts
# the first CLI message off parsed.messages; the port returns the remaining
# messages, which the checks compare with upstream's parsed.messages.

def check(value: Bool, +name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit), value, _ => IO.print("ok " ++ name), _ => IO.die(Unit, 1, "FAIL " ++ name))(Unit{})

def shown(result: Initial.InitialMessage) -> String:
  match result:
    case Initial.InitialMessage{text, _, remaining}: Maybe.default(&2, String, text, "<undefined>") ++ "|" ++ String.join(remaining, ",")

def main() -> IO(Unit):
  do IO<Unit>:
    check(String.eq(shown(Initial.buildInitialMessage(Some{"README contents\n"}, None{}, Nil{}, ["Summarize the text given"])), "README contents\nSummarize the text given|"), "merges piped stdin with the first CLI message into one prompt")
    check(String.eq(shown(Initial.buildInitialMessage(Some{"README contents"}, None{}, Nil{}, Nil{})), "README contents|"), "uses stdin as the initial prompt when no CLI message is present")
    check(String.eq(shown(Initial.buildInitialMessage(Some{"stdin\n"}, Some{"file\n"}, Nil{}, ["Explain it", "Second message"])), "stdin\nfile\nExplain it|Second message"), "combines stdin, file text, and first CLI message in one prompt")
