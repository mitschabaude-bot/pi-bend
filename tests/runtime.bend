import Base
import ../src/native.bend as N
import ../src/util.bend as U
import ../src/json.bend as J

def assert(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def process_test(+handle: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, String> <- U.collect(handle)
    output : String <- IO.pass(String, result)
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    assert(String.eq(output, "αβγ\n"), "process output differs")
    assert(String.eq(status, "7"), "process status differs")

def http_test(+handle: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, String> <- U.collect(handle)
    output : String <- IO.pass(String, result)
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    assert(String.eq(status, "201"), "HTTP status differs")
    assert(String.eq(output, "data: {\"text\":\"😃\"}\r\n\r\n"), "HTTP UTF-8 streaming differs")

def expect_timeout(result: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match result:
    case Fail{(code, msg)}: assert(U32.is_eq(code, 110), "expected ETIMEDOUT")
    case Done{s}: IO.die(Unit, 1, "process timeout did not fire")

def timeout_test(+handle: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- N.next(handle)
    expect_timeout(r)
    closed : String <- N.close(handle)
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    h : String <- IO.try(String, N.spawn("printf 'αβγ\\n'; exit 7", "/tmp", U32.to_nat(1000)))
    process_test(h)
    h : String <- IO.try(String, N.spawn("sleep 5", "/tmp", 10n))
    timeout_test(h)
    url : String <- N.arg(1n)
    h : String <- N.http(url, "Content-Type: application/json", "{}", U32.to_nat(5000))
    http_test(h)
    IO.print("runtime: all tests passed")
