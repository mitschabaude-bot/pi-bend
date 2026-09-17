import Base
import ../src/auth.bend as A
import ../src/native.bend as N
import ../src/provider.bend as P
import ../src/json.bend as J

def main() -> IO(Unit):
  do IO<Unit>:
    auth : A.Credential <- A.load()
    session : String <- N.uuid()
    response : J.Json <- P.call(auth, session, "gpt-5.6-sol", "Reply exactly as requested.", J.Item{P.user_message("Reply with exactly: PI_BEND_OPENAI_OK"), J.End{}}, J.End{}, "low")
    IO.print("")
