import Base
import ../src/http-body.bend as Body
import ../src/http-framing-fields.bend as Framing
import ../src/u64.bend as W
import ./http-content-length.bend as Input

def transfer(value: Framing.Transfer) -> String:
  match value:
    case Framing.NoTransferEncoding{}: "absent"
    case Framing.ChunkedTransfer{}: "chunked"
    case Framing.OtherTransfer{}: "other"

def length(value: Maybe<&2, W.U64>) -> String:
  match value:
    case None{}: "none"
    case Some{W.U64{hi, lo}}: U32.show(hi) ++ "," ++ U32.show(lo)

def mode(value: Body.Framing) -> String:
  match value:
    case Body.NoBody{}: "empty"
    case Body.ContentLength{size}: "fixed:" ++ length(Some{size})
    case Body.ChunkedEncoding{}: "chunked"
    case Body.UntilClose{}: "close"

def shown(result: Result<&2, &2, Framing.FieldError, Framing.Fields>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Framing.Fields{+size, +encoding}}: transfer(encoding) ++ ";" ++ length(size) ++ ";" ++ mode(Framing.bodyFraming(Framing.Fields{size, encoding}))

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(shown(Framing.analyze(Input.fields(String.split(head, ';')))))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
