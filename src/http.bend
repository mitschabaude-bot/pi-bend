import Base
import ./native.bend as N
import ./util.bend as U

type Response is Data:
  Response{status: Nat, body: String}

def finish(+handle: String) -> IO(Response):
  do IO<Response>:
    result : Result<&1, &1, U32 & String, String> <- U.collect(handle)
    status : String <- N.status(handle)
    closed : String <- N.close(handle)
    body : String <- IO.pass(String, result)
    return Response{U.natural(status, 0n), body}

def fetch(url: String, headers: String, body: String) -> IO(Response):
  do IO<Response>:
    handle : String <- N.http(url, headers, body, U32.to_nat(120000))
    finish(handle)

def hex(+n: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(n, 10), (48 + n : U32), (55 + n : U32))}

def form_char(+c: Char) -> String:
  +code = Char.to_u32(c)
  Bool.pick(String, Char.is_digit(c) || Char.is_alpha(c) || U32.is_eq(code, 45) || U32.is_eq(code, 46) || U32.is_eq(code, 95) || U32.is_eq(code, 126), SCon{c, SNil{}}, "%" ++ SCon{hex((code / 16 : U32)), SCon{hex((code % 16 : U32)), SNil{}}})

def form(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{c, t}: form_char(c) ++ form(t)
