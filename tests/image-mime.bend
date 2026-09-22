import Base
import ../packages/coding-agent/src/utils/mime.bend as Mime

def nibble(+char: Char) -> U32:
  +code = Char.to_u32(char)
  Bool.pick(U32,U32.is_le(code,57),(code - 48 : U32),(code - 87 : U32))

def decode(text: String, reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SCon{a,SCon{b,rest}}: decode(rest,(nibble(a) * 16 + nibble(b) : U32) <> reversed)
    case _: List.reverse(&2,U32,reversed)

def render(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "null"
    case Some{mime}: mime

def chunks(count: Nat, tail: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: tail
    case 1n+rest: chunks(rest,0 <> 0 <> 0 <> 0 <> 116 <> 69 <> 88 <> 116 <> 0 <> 0 <> 0 <> 0 <> tail)

def png(tail: List<&2,U32>) -> List<&2,U32>:
  137 <> 80 <> 78 <> 71 <> 13 <> 10 <> 26 <> 10 <>
  0 <> 0 <> 0 <> 13 <> 73 <> 72 <> 68 <> 82 <>
  0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> tail

def long() -> IO(Unit):
  do IO<Unit>:
    IO.print(render(Mime.detectSupportedImageMimeType(png(chunks(20000n,0 <> 0 <> 0 <> 0 <> 97 <> 99 <> 84 <> 76 <> Nil{})))))
    IO.print(render(Mime.detectSupportedImageMimeType(png(chunks(20000n,0 <> 0 <> 0 <> 0 <> 73 <> 68 <> 65 <> 84 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 97 <> 99 <> 84 <> 76 <> Nil{})))))
    IO.print(render(Mime.detectSupportedImageMimeType(png(255 <> 255 <> 255 <> 255 <> 116 <> 69 <> 88 <> 116 <> Nil{}))))
    IO.print(render(Mime.detectSupportedImageMimeType(71 <> 73 <> 70 <> 256 <> Nil{})))
    IO.print(render(Mime.detectSupportedImageMimeType(255 <> 216 <> 255 <> 4294967295 <> Nil{})))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case +text <> rest:
      do IO<Unit>:
        Bool.pick(Unit -> IO(Unit),String.eq(text,"long"),unused => long(),unused => IO.print(render(Mime.detectSupportedImageMimeType(decode(text,Nil{})))))(Unit{})
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
