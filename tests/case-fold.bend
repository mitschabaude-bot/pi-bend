import Base
import ../packages/runtime/src/case-fold.bend as Fold

def render(values: List<&2,Char>, text: String) -> String:
  match values:
    case Nil{}: text
    case Chr{value} <> rest: render(rest,text ++ "," ++ U32.show(value))

def equivalent(+char: Char, values: List<&2,Char>) -> Bool:
  match values:
    case Nil{}: True{}
    case +head <> rest: Fold.equal(char,head) && Fold.equal(head,char) && equivalent(char,rest)

def report(+code: U32, +values: List<&2,Char>) -> IO(Unit):
  match values:
    case Chr{value} <> Nil{}:
      Bool.pick(IO(Unit),U32.is_eq(code,value),IO.pure(Unit,Unit{}),IO.die(Unit,1,"singleton changed"))
    case _:
      do IO<Unit>:
        Bool.pick(IO(Unit),equivalent(Chr{code},values),IO.pure(Unit,Unit{}),IO.die(Unit,1,"asymmetric equivalence"))
        IO.print(U32.show(code) ++ render(values,""))

def scan(count: Nat, +code: U32) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        report(code,Fold.variants(Chr{code}))
        scan(rest,(code + 1 : U32))

def uppercaseScan(count: Nat, +code: U32) -> IO(Unit):
  match count:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        Bool.pick(IO(Unit),Fold.isUppercase(Chr{code}),IO.print(U32.show(code)),IO.pure(Unit,Unit{}))
        uppercaseScan(rest,(code + 1 : U32))

def membership(char: Char, first: U32, last: U32) -> Bool:
  match char:
    case Chr{+code}: U32.is_ge(code,first) && U32.is_le(code,last)

def inRange(values: List<&2,Char>, +first: U32, +last: U32) -> Bool:
  match values:
    case Nil{}: False{}
    case char <> rest: membership(char,first,last) || inRange(rest,first,last)

def number(text: String) -> U32: Maybe.default(&2,U32,U32.read(text),0)

def args(values: List<String>) -> IO(Unit):
  match values:
    case "uppercase" <> first <> count <> Nil{}: uppercaseScan(U32.to_nat(number(count)),number(first))
    case "scan" <> first <> count <> Nil{}: scan(U32.to_nat(number(count)),number(first))
    case "equal" <> a <> b <> Nil{}: IO.print(Bool.pick(String,Fold.equal(Chr{number(a)},Chr{number(b)}),"true","false"))
    case "range" <> code <> first <> last <> Nil{}: IO.print(Bool.pick(String,inRange(Fold.variants(Chr{number(code)}),number(first),number(last)),"true","false"))
    case _: IO.die(Unit,1,"expected scan/equal/range operands")

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    args(values)
