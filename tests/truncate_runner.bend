import Base
import ../src/native.bend as N
import ../src/json.bend as J
import ../src/util.bend as U
import ../packages/agent/src/harness/utils/truncate.bend as T

def cause(value: T.TruncationBy) -> J.Json:
  match value:
    case T.NoLimit{}: J.Null{}
    case T.LineLimit{}: J.Text{"lines"}
    case T.ByteLimit{}: J.Text{"bytes"}

def number(key: String, value: Nat, rest: J.Json) -> J.Json:
  J.Field{key, J.Number{Nat.show(value)}, rest}

def encoded(value: T.TruncationResult) -> J.Json:
  match value:
    case T.TruncationResult{content, truncated, by, totalLines, totalBytes, outputLines, outputBytes, partial, first, maxLines, maxBytes}:
      limits = number("maxLines", maxLines, number("maxBytes", maxBytes, J.End{}))
      flags = {J.Field{"lastLinePartial", J.Boolean{partial}, J.Field{"firstLineExceedsLimit", J.Boolean{first}, limits}} : J.Json}
      totals = number("totalLines", totalLines, number("totalBytes", totalBytes, number("outputLines", outputLines, number("outputBytes", outputBytes, flags))))
      J.Object{J.str_field("content", content, J.Field{"truncated", J.Boolean{truncated}, J.Field{"truncatedBy", cause(by), totals}})}

def evaluate(+value: J.Json) -> J.Json:
  +content = U.field(value, "text")
  +lines = J.number(J.get(value, "lines"), 0n)
  +bytes = J.number(J.get(value, "bytes"), 0n)
  head = encoded(T.truncateHead(content, T.TruncationOptions{Some{lines}, Some{bytes}}))
  tail = encoded(T.truncateTail(content, T.TruncationOptions{Some{lines}, Some{bytes}}))
  J.Object{J.Field{"head", head, J.Field{"tail", tail, J.End{}}}}

def cases(values: J.Json) -> J.Json:
  match values:
    case J.Item{value, rest}: J.Item{evaluate(value), cases(rest)}
    case _: J.End{}

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- N.arg(1n)
    data : String <- IO.try(String, N.read(path))
    values : J.Json <- U.parsed(J.parse(data))
    IO.print(J.encode(J.Array{cases(J.array(values))}))
