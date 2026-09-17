import Base
import ../src/json.bend as J

def check_bool(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def check_equal(name: String, +expected: String, +actual: String) -> IO(Unit):
  check_bool(String.eq(expected, actual), name ++ ": expected " ++ expected ++ ", got " ++ actual)

def check_result(name: String, expect: String, result: Result<&2, &2, String, J.Json>) -> IO(Unit):
  match result:
    case Done{j}: check_equal(name, expect, J.encode(j))
    case Fail{e}: IO.die(Unit, 1, name ++ ": " ++ e)

def invalid(r: Result<&2, &2, String, J.Json>) -> IO(Unit):
  match r:
    case Fail{e}: IO.pure(Unit, Unit{})
    case Done{j}: IO.die(Unit, 1, "Accepted invalid JSON: " ++ J.encode(j))

def main() -> IO(Unit):
  do IO<Unit>:
    check_result("nested", "{\"a\":[true,false,null,{\"b\":-1.25e+3}]}", J.parse(" {\"a\": [true, false, null, {\"b\": -1.25e+3}]} "))
    check_result("unicode", "\"😃\"", J.parse("\"\\ud83d\\ude03\""))
    check_result("escapes", "\"a\\n\\t\\\"\\\\\"", J.parse("\"a\\n\\t\\\"\\\\\""))
    check_result("large number", "9007199254740993", J.parse("9007199254740993"))
    check_result("empty", "[]", J.parse("[]"))
    invalid(J.parse("[1,]"))
    invalid(J.parse("{\"x\":1,}"))
    invalid(J.parse("01"))
    invalid(J.parse("1e"))
    invalid(J.parse("true false"))
    check_result("isolated high surrogate", "\"\\ud800\"", J.parse("\"\\ud800\""))
    check_result("isolated low surrogate", "\"\\udc00\"", J.parse("\"\\udc00\""))
    check_result("surrogate followed by text", "\"\\ud800x\"", J.parse("\"\\ud800x\""))
    check_result("adjacent high surrogates", "\"\\ud800😃\"", J.parse("\"\\ud800\\ud83d\\ude03\""))
    invalid(J.parse("\"\\x\""))
    IO.print("json: all tests passed")
