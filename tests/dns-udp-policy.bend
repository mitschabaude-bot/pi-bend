import Base
import ../packages/runtime/src/dns-udp-policy.bend as Policy
import ../packages/runtime/src/dns-message.bend as Message
import ../packages/runtime/test/utf8-runner.bend as Scalar

def show(value: Policy.Decision) -> String:
  match value:
    case Policy.Accept{}: "accept"
    case Policy.UseTCP{}: "tcp"
    case Policy.Retry{Policy.ServerFailure{}}: "servfail"
    case Policy.Retry{Policy.NotImplemented{}}: "notimp"
    case Policy.Retry{Policy.Refused{}}: "refused"
    case Policy.Retry{Policy.UnhelpfulEmpty{}}: "empty"

def cases(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case flags <> answers <> additional <> ignore <> +other <> rest:
      do IO<Unit>:
        IO.print(show(Policy.header(Message.Header{Scalar.decimal(other, 0), Scalar.decimal(flags, 0), Scalar.decimal(other, 0), Scalar.decimal(answers, 0), Scalar.decimal(other, 0), Scalar.decimal(additional, 0)}, String.eq(ignore, "1"))))
        cases(rest)
    case _: IO.die(Unit, 1, "expected groups: flags answers additional ignore other")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    cases(values)
