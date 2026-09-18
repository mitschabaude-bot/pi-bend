import Base
import ../src/ref.bend as R
import ../src/callback.bend as C

def assertion(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, label)

def echo(unused: Unit, text: String) -> IO(String): IO.pure(String, text)

def main() -> IO(Unit):
  do IO<Unit>:
    +first : Chan(U32) <- Chan.new(U32, 1)
    +second : Chan(U32) <- Chan.new(U32, 1)
    assertion(Chan.same(U32, first, first), "channel aliases must share identity")
    assertion(Bool.not(Chan.same(U32, first, second)), "fresh channels must have distinct identities")
    sent : Bool <- Chan.send(U32, first, 42)
    assertion(sent && Chan.same(U32, first, first), "contents must not affect channel identity")
    value : U32 <- IO.join(U32, first)
    assertion(U32.is_eq(value, 42), "identity comparison must not consume contents")
    +reused : Chan(U32) <- Chan.new(U32, 1)
    assertion(Bool.not(Chan.same(U32, first, reused)), "channel slot reuse must include its generation")
    Chan.close(U32, second)
    Chan.close(U32, reused)
    +a : R.Ref<String> <- R.new(String, "same value")
    +b : R.Ref<String> <- R.new(String, "same value")
    assertion(R.same(String, a, a) && Bool.not(R.same(String, a, b)), "reference identity must differ from value equality")
    +holder : R.Ref<R.Ref<String>> <- R.new(R.Ref<String>, a)
    alias : R.Ref<String> <- R.read(R.Ref<String>, holder)
    assertion(R.same(String, a, alias), "reference aliases obtained through IO must share identity")
    R.write(String, a, "changed")
    assertion(R.same(String, a, a), "writing a reference must preserve identity")
    previous : R.Ref<String> <- R.dispose(R.Ref<String>, holder)
    previous : String <- R.dispose(String, a)
    previous : String <- R.dispose(String, b)
    +f : C.Callback<String, String> <- C.create(~Unit, ~String, ~String, ~echo, Unit{})
    +g : C.Callback<String, String> <- C.create(~Unit, ~String, ~String, ~echo, Unit{})
    assertion(C.same(String, String, f, f) && Bool.not(C.same(String, String, f, g)), "callback identity must distinguish equal code and captures")
    +callbacks : R.Ref<C.Callback<String, String>> <- R.new(C.Callback<String, String>, f)
    +alias : C.Callback<String, String> <- R.read(C.Callback<String, String>, callbacks)
    assertion(C.same(String, String, f, alias) && Bool.not(C.same(String, String, g, alias)), "runtime callback aliases must retain exact identity")
    echoed : String <- C.call(String, String, f, "unchanged")
    assertion(String.eq(echoed, "unchanged") && C.same(String, String, f, f), "callback calls must preserve identity")
    previous : C.Callback<String, String> <- R.dispose(C.Callback<String, String>, callbacks)
    C.dispose(String, String, f)
    C.dispose(String, String, g)
    IO.print("PASS channel, reference and callback identity without observing contents")
