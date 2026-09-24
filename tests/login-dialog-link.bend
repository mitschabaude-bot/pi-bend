import Base
import ../packages/coding-agent/src/modes/interactive/components/login-dialog.bend as Login
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/record.bend as Record

def main() -> IO(Unit):
  do IO<Unit>:
    +url : String = "https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback&state=full_state"
    +theme : Theme.Theme = Theme.Theme{"test",Color.TrueColor{},Record.new(Color.Color),Record.new(Color.Color)}
    +text : String = String.join(Login.manual(theme,120n,url,""),"\n")
    Bool.pick(Unit -> IO(Unit),String.contains(text,"\u{1b}]8;;" ++ url ++ "\u{7}"),_ => IO.print("complete hyperlink"),_ => IO.die(Unit,1,"OAuth hyperlink was truncated"))(Unit{})
