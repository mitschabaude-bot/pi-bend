import Base
import ../packages/runtime/src/json.bend as J
import ../packages/runtime/src/string.bend as Strings

# Construct inside Bend: OS argument size and host strings are not the workload.
def repeated(count: Nat,+fragment: String,content: String) -> String:
  match count:
    case 0n: content
    case 1n+n: repeated(n,fragment,fragment ++ content)
def size(text: String,count: U32) -> U32:
  match text:
    case SNil{}: count
    case SCon{_,rest}: size(rest,(count + 1 : U32))
def run(count: Nat,+text: String,total: U32) -> U32:
  match count:
    case 0n: total
    case 1n+n: run(n,text,(total + size(J.quote(text),0) : U32))
def check(accepted: Bool) -> IO(Unit):
  match accepted:
    case True{}: IO.print("PASS large escaped JSON string")
    case False{}: IO.die(Unit,1,"incorrect JSON escaping")
def command(values: List<String>) -> IO(Unit):
  match values:
    case "small" <> _: IO.print(U32.show(run(20000n,repeated(4n,"normal text\n\"\\雪", ""),0)))
    case "large" <> _: IO.print(U32.show(run(8n,repeated(7500n,"Project instructions.\n", ""),0)))
    case _:
      check(Strings.equal(J.quote(repeated(12000n,"line\n\"\\雪\t", "")),"\"" ++ repeated(12000n,"line\\n\\\"\\\\雪\\t", "") ++ "\""))
def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    command(values)
