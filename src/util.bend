import Base
import ./json.bend as J
import ./native.bend as N

def natural(s: String, fallback: Nat) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), fallback)

def field(+j: J.Json, key: String) -> String: J.text(J.get(j, key))

def either_text(r: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match r:
    case Done{s}: s
    case Fail{e}: fallback

def error_text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}: s
    case Fail{(code, message)}: "Error: " ++ message

def parsed(result: Result<&2, &2, String, J.Json>) -> IO(J.Json):
  match result:
    case Fail{message}: IO.die(J.Json, 1, "Invalid JSON: " ++ message)
    case Done{value}: IO.pure(J.Json, value)

def read_json_result(r: Result<&1, &1, U32 & String, String>) -> IO(J.Json):
  match r:
    case Fail{(code, message)}: IO.die(J.Json, code, message)
    case Done{s}: parsed(J.parse(s))

def read_json(path: String) -> IO(J.Json):
  do IO<J.Json>:
    result : Result<&1, &1, U32 & String, String> <- N.read(path)
    read_json_result(result)

def collect_step(fuel: Nat, chunk: Result<&1, &1, U32 & String, String>, +handle: String, acc: String) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel chunk:
    case 0n _: IO.pure(Result<&1, &1, U32 & String, String>, Fail{(27, "Stream chunk limit exceeded")})
    case 1n+n Fail{e}: IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case 1n+n Done{SNil{}}: IO.pure(Result<&1, &1, U32 & String, String>, Done{acc})
    case 1n+n Done{SCon{c, t}}:
      do IO<Result<&1, &1, U32 & String, String>>:
        next : Result<&1, &1, U32 & String, String> <- N.next(handle)
        collect_step(n, next, handle, acc ++ SCon{c, t})

def collect(+handle: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    next : Result<&1, &1, U32 & String, String> <- N.next(handle)
    collect_step(U32.to_nat(1048576), next, handle, "")

def drop_lines(xs: List<&2, String>, n: Nat) -> List<&2, String>:
  match xs n:
    case Nil{} _: Nil{}
    case h <> t 0n: h <> t
    case h <> t 1n+n: drop_lines(t, n)

def take_lines(xs: List<&2, String>, n: Nat) -> List<&2, String>:
  match xs n:
    case Nil{} _: Nil{}
    case h <> t 0n: Nil{}
    case h <> t 1n+n: h <> take_lines(t, n)

def byte_width(+c: Char) -> Nat:
  +x = Char.to_u32(c)
  Bool.pick(Nat, U32.is_lt(x, 128), 1n, Bool.pick(Nat, U32.is_lt(x, 2048), 2n, Bool.pick(Nat, U32.is_lt(x, 65536), 3n, 4n)))

def byte_length(s: String) -> Nat:
  match s:
    case SNil{}: 0n
    case SCon{c, t}: Nat.add(byte_width(c), byte_length(t))

def shell_quote_part(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+c, t}: Bool.pick(String, Char.is_eq(c, '\''), "'\\''", SCon{c, SNil{}}) ++ shell_quote_part(t)

def shell_quote(s: String) -> String: "'" ++ shell_quote_part(s) ++ "'"

def replace_char(s: String, +from: Char, +to: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+c, t}: Bool.pick(String, Char.is_eq(c, from), to, SCon{c, SNil{}}) ++ replace_char(t, from, to)
