import Base
import ../src/json-pointer.bend as P
import ../src/uri-component.bend as Uri
import ../src/schema-value.bend as V
import ../src/record.bend as R
import ../src/utf16.bend as U
import ./schema.bend as T

def decoded(actual: Maybe<&2, String>, expected: Maybe<&2, String>) -> IO(Unit):
  match actual expected:
    case None{} None{}: IO.pure(Unit, Unit{})
    case Some{a} Some{b}: T.assertion(U.equal(a, b), "URI component text differs")
    case _ _: T.assertion(False{}, "URI component validity differs")

def found(actual: Maybe<&2, V.Value>, expected: Maybe<&2, V.Value>) -> IO(Unit):
  match actual expected:
    case None{} None{}: IO.pure(Unit, Unit{})
    case Some{a} Some{b}: T.assertion(V.equal(a, b), "JSON pointer value differs")
    case _ _: T.assertion(False{}, "JSON pointer presence differs")

def lookup(value: V.Value, pointer: Maybe<&2, P.Pointer>) -> Maybe<&2, V.Value>:
  match pointer:
    case None{}: None{}
    case Some{pointer}: P.get(value, pointer)

def main() -> IO(Unit):
  do IO<Unit>:
    +value : V.Value = V.ObjectValue{R.Record{R.Property{"", V.Null{}} <> R.Property{"a/b~c", V.Text{"yes"}} <> R.Property{"__proto__", V.Boolean{True{}}} <> R.Property{"array", V.ArrayValue{V.Text{"first"} <> V.Null{} <> Nil{}}} <> Nil{}}}
    found(lookup(value, P.parse("")), Some{value})
    found(lookup(value, P.parse("/")), Some{V.Null{}})
    found(lookup(value, P.parse("/a~1b~0c")), Some{V.Text{"yes"}})
    found(lookup(value, P.parse("/__proto__")), Some{V.Boolean{True{}}})
    found(lookup(value, P.parse("/array/0")), Some{V.Text{"first"}})
    found(lookup(value, P.parse("/array/1")), Some{V.Null{}})
    found(lookup(value, P.parse("/array/01")), None{})
    found(lookup(value, P.parse("/array/-1")), None{})
    found(lookup(value, P.parse("/array/length")), None{})
    found(lookup(value, P.parse("/array/9999999999999999999999999999999999999999")), None{})
    found(lookup(value, P.parseFragment("#/a~1b~0c")), Some{V.Text{"yes"}})
    found(lookup(value, P.parseFragment("#/%61~1b~0c")), Some{V.Text{"yes"}})
    found(lookup(value, P.parseFragment("#name")), None{})
    decoded(Uri.decode("a+b%20c"), Some{"a+b c"})
    decoded(Uri.decode("%F0%9F%98%80"), Some{"😀"})
    decoded(Uri.decode("%ED%A0%80"), None{})
    decoded(Uri.decode("%F4%90%80%80"), None{})
    decoded(Uri.decode("%C0%80"), None{})
    T.assertion(String.eq(P.render(P.Pointer{"~1" <> "/" <> "" <> Nil{}}), "/~01/~1/"), "canonical pointer escapes preserve segment identity")
    IO.print("PASS native JSON pointer keys, canonical list indices and strict URI fragments")
