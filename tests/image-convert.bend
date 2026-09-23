import Base
import ../packages/coding-agent/src/utils/image-convert.bend as Convert
import ../packages/runtime/src/base64.bend as Base64
import ../packages/runtime/src/string.bend as Strings

def show(value: Maybe<&2,Convert.ConvertedImage>) -> String:
  match value:
    case None{}: "none"
    case Some{Convert.ConvertedImage{data,mime}}: mime ++ ":" ++ data

def bytesResult(value: Maybe<&2,List<&2,U32>>) -> String:
  match value:
    case None{}: "none"
    case Some{bytes}: show(Convert.base64Result(Base64.encode(bytes)))

def bounded(pixels: Nat, bytes: Nat, value: Result<&2,&2,Base64.Error,List<&2,U32>>) -> String:
  match value:
    case Fail{_}: "none"
    case Done{input}: bytesResult(Convert.convertImageBytesToPngWithLimits(input,pixels,bytes))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "convert" <> mime <> data <> Nil{}: show(Convert.convertToPng(data,mime))
    case "bounded" <> pixels <> bytes <> data <> Nil{}: bounded(Maybe.default(&2,Nat,Nat.read(pixels),0n),Maybe.default(&2,Nat,Nat.read(bytes),0n),Base64.decode(data))
    case _: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(value,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
