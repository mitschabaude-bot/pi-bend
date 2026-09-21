import Base
type Value is Data:
  Null{}
  Text{value: String}
type Error is Data:
  Hook{message: String}
def check(mode: U32, value: Result<&2, &2, Error, Maybe<&2, Value>>) -> IO(Unit):
  match mode value:
    case 0 Done{None{}}: IO.pure(Unit, Unit{})
    case 1 Done{Some{Null{}}}: IO.pure(Unit, Unit{})
    case 3 Fail{Hook{"payload failure"}}: IO.pure(Unit, Unit{})
    case other Done{Some{Text{"original"}}}: IO.pure(Unit, Unit{})
    case _ _: IO.die(Unit, 1, "changed hook result")
