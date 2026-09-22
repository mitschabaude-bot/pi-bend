import Base
import ../packages/coding-agent/src/core/tools/truncate.bend as T
import ../packages/runtime/test/utf8-runner.bend as Wire
import ../packages/runtime/src/string.bend as Strings

def characters(parts: List<&2,String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case "" <> rest: characters(rest,reversed)
    case part <> rest: characters(rest,SCon{Chr{Wire.decimal(part,0)},reversed})

def text(value: String) -> String: characters(Strings.split(value,','),"")

def boolean(value: Bool) -> String: Bool.pick(String,value,"1","0")

def limit(value: Maybe<&2,T.Limit>) -> String:
  match value:
    case None{}: "none"
    case Some{T.Lines{}}: "lines"
    case Some{T.Bytes{}}: "bytes"

def report(value: T.TruncationResult) -> String:
  match value:
    case T.TruncationResult{content,truncated,cause,totalLines,totalBytes,outputLines,outputBytes,partial,oversized,maxLines,maxBytes}:
      String.join(Wire.showText(content) <> boolean(truncated) <> limit(cause) <> Nat.show(totalLines) <> Nat.show(totalBytes) <> Nat.show(outputLines) <> Nat.show(outputBytes) <> boolean(partial) <> boolean(oversized) <> Nat.show(maxLines) <> Nat.show(maxBytes) <> Nil{},"|")

def line(value: T.LineResult) -> String:
  match value:
    case T.LineResult{content,truncated}: Wire.showText(content) ++ "|" ++ boolean(truncated)

def option(text: String) -> Maybe<&2,Nat>:
  match text:
    case "": None{}
    case value: Some{U32.to_nat(Wire.decimal(value,0))}

def run(parts: List<&2,String>) -> String:
  match parts:
    case "h" <> lines <> bytes <> content <> Nil{}: report(T.truncateHead(text(content),T.TruncationOptions{option(lines),option(bytes)}))
    case "t" <> lines <> bytes <> content <> Nil{}: report(T.truncateTail(text(content),T.TruncationOptions{option(lines),option(bytes)}))
    case "l" <> count <> content <> Nil{}: line(T.truncateLine(text(content),option(count)))
    case "s" <> count <> Nil{}: T.formatSize(U32.to_nat(Wire.decimal(count,0)))
    case _: "invalid"

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(value,':')))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
