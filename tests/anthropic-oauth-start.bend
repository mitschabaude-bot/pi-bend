import Base
import ../packages/ai/src/auth/oauth/anthropic.bend as OAuth

def report(result: Result<&2,&2,String,OAuth.Authorization>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{OAuth.Authorization{url,_}}: IO.print(url)
def main() -> IO(Unit):
  do IO<Unit>:
    started : Result<&2,&2,String,OAuth.Authorization> <- OAuth.beginAuthorization()
    report(started)
