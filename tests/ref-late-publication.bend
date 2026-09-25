import Base
import ../packages/runtime/src/ref.bend as Ref

def increment(+value: Nat) -> Nat & Nat: (value + 1n,value)
def incrementAsync(+value: Nat) -> IO(Nat & Nat): IO.pure(Nat & Nat,(value + 1n,value))
def was(value: Maybe<&1,Nat>,expected: Nat) -> Bool:
  match value:
    case Some{found}: Nat.is_eq(found,expected)
    case None{}: False{}
def declined(value: Maybe<&1,Nat>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}
def main() -> IO(Unit):
  do IO<Unit>:
    +reference : Ref.Ref<Nat> <- Ref.new(Nat,1n)
    first : Maybe<&1,Nat> <- Ref.tryModify(Nat,Nat,reference,value => increment(value))
    second : Maybe<&1,Nat> <- Ref.tryUpdate(Nat,Nat,reference,value => incrementAsync(value))
    final : Nat <- Ref.dispose(Nat,reference)
    late : Maybe<&1,Nat> <- Ref.tryModify(Nat,Nat,reference,value => increment(value))
    later : Maybe<&1,Nat> <- Ref.tryUpdate(Nat,Nat,reference,value => incrementAsync(value))
    Bool.pick(Unit -> IO(Unit),was(first,1n) && was(second,2n) && Nat.is_eq(final,3n) && declined(late) && declined(later),
      _ => IO.print("late Ref publication declined"),_ => IO.die(Unit,1,"late Ref publication changed a retired owner"))(Unit{})
