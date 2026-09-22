import Base
import ../packages/runtime/src/text-decoder.bend as Text
import ../packages/runtime/src/base64.bend as Base64
import ../packages/runtime/src/utf8.bend as Utf8

def final(result: Result<&2,&2,Text.Error,Unit>,text: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{_}: IO.print("ok:" ++ Base64.encoded(Utf8.encode(text),""))

def second(result: Result<&2,&2,Text.Error,Text.Decoded>,prefix: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{Text.Decoded{decoder,text}}: final(Text.finish(decoder),prefix ++ text)

def first(result: Result<&2,&2,Text.Error,Text.Decoded>,rest: List<&2,U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{Text.Decoded{decoder,text}}: second(Text.feed(rest,decoder),text)

def decoded(mode: String,result: Result<&2,&2,Base64.Error,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit,1,"fixture Base64 invalid")
    case Done{+bytes}:
      +split = String.length(mode)
      first(Text.feed(List.take(&2,U32,bytes,split),Text.create()),List.drop(&2,U32,bytes,split))

def run(args: List<String>) -> IO(Unit):
  match args:
    case mode <> bytes <> rest:
      do IO<Unit>:
        decoded(mode,Base64.decode(bytes))
        run(rest)
    case Nil{}: IO.pure(Unit,Unit{})
    case _: IO.die(Unit,1,"expected split/Base64 pairs")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
