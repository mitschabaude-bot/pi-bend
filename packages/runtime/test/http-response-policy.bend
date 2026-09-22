import Base
import ../src/http-response.bend as Policy
import ../src/http-message.bend as Head
import ../src/http-message.bend as Status
import ./http-framing-fields.bend as Framing
import ./http-content-length.bend as Input
import ./utf8-runner.bend as Text

def shown(result: Result<&2, &2, Policy.PolicyError, Policy.ResponsePlan>) -> String:
  match result:
    case Fail{_}: "error"
    case Done{Policy.Informational{}}: "next"
    case Done{Policy.Final{framing, expose}}:
      "final:" ++ Framing.mode(framing) ++ ":" ++ Bool.pick(String, expose, "body", "null")

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case method <> major <> minor <> status <> fields:
      IO.print(shown(Policy.plan(method, Head.ResponseHead{Status.StatusLine{Text.decimal(major, 0), Text.decimal(minor, 0), Text.decimal(status, 0), Nil{}}, Input.fields(fields)})))
    case _: IO.die(Unit, 1, "invalid response policy fixture")

def cases(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(String.split(head, ';'))
        cases(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    cases(arguments)
