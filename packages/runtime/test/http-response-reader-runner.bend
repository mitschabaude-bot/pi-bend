import Base
import ./http-response-reader-support.bend as H
import ./utf8-runner.bend as Codec

def inputs(parts: List<&2, String>) -> List<&2, H.Input>:
  match parts:
    case Nil{}: Nil{}
    case SCon{Chr{98}, data} <> rest: H.ChunkStep{Codec.parseNumbers(data)} <> inputs(rest)
    case SCon{Chr{101}, _} <> rest: H.ReadError{} <> inputs(rest)
    case SCon{Chr{114}, _} <> rest: H.ResetError{} <> inputs(rest)
    case SCon{Chr{110}, _} <> rest: H.ChunkStep{Nil{}} <> inputs(rest)
    case _ <> rest: inputs(rest)

def actions(text: String) -> List<&2, H.Action>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{110}, rest}: H.Pull{} <> actions(rest)
    case SCon{Chr{114}, rest}: H.Return{} <> actions(rest)
    case SCon{_, rest}: actions(rest)

def run(transport: Bool, inputs: List<&2, H.Input>, actions: List<&2, H.Action>, fails: Bool) -> IO(Unit):
  match transport:
    case False{}: H.run(inputs, actions, fails)
    case True{}: H.runTransport(inputs, actions, fails)

def protocol(transport: Bool, parts: List<&2, String>) -> IO(Unit):
  match parts:
    case fails <> commands <> chunks <> Nil{}: run(transport, inputs(String.split(chunks, '|')), actions(commands), String.eq(fails, "1"))
    case _: IO.die(Unit, 1, "invalid reader test protocol")

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case SCon{Chr{115}, text} <> rest:
      do IO<Unit>:
        protocol(False{}, String.split(text, '/'))
        all(rest)
    case SCon{Chr{116}, text} <> rest:
      do IO<Unit>:
        protocol(True{}, String.split(text, '/'))
        all(rest)
    case _ <> rest: all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
