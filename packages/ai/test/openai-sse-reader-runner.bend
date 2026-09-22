import Base
import ./openai-sse-reader-support.bend as H
import ../../runtime/test/utf8-runner.bend as Codec
import ../../runtime/src/sse.bend as D

def inputs(parts: List<&2, String>) -> List<&2, H.Input>:
  match parts:
    case Nil{}: Nil{}
    case SCon{Chr{116}, data} <> rest: H.ChunkStep{D.Text{Codec.fromScalars(Codec.parseNumbers(data))}} <> inputs(rest)
    case SCon{Chr{98}, data} <> rest: H.ChunkStep{D.Bytes{Codec.parseNumbers(data)}} <> inputs(rest)
    case SCon{Chr{101}, _} <> rest: H.ReadError{} <> inputs(rest)
    case SCon{Chr{97}, _} <> rest: H.ReadAbort{} <> inputs(rest)
    case SCon{Chr{110}, _} <> rest: H.ChunkStep{D.EmptyChunk{}} <> inputs(rest)
    case _ <> rest: inputs(rest)

def actions(text: String) -> List<&2, H.Action>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{110}, rest}: H.Pull{} <> actions(rest)
    case SCon{Chr{114}, rest}: H.Return{} <> actions(rest)
    case SCon{_, rest}: actions(rest)

def protocol(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case closeMode <> diagnosticMode <> synthesize <> commands <> chunks <> Nil{}: H.run(inputs(String.split(chunks, '|')), actions(commands), closeMode, diagnosticMode, String.eq(synthesize, "1"))
    case _: IO.die(Unit, 1, "invalid reader test protocol")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, text} <> rest:
      do IO<Unit>:
        protocol(String.split(text, '/'))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
