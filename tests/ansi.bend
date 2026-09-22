import Base
import ../packages/coding-agent/src/utils/ansi.bend as Ansi
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire
import ./tool-truncate.bend as Text

def repeated(count: Nat, +character: Char, value: String) -> String:
  match count:
    case 0n: value
    case 1n+count: repeated(count,character,SCon{character,value})

def longCases() -> IO(Unit):
  +plain = repeated(200000n,'x',"")
  +unfinished = "\u{1b}]" ++ plain
  +digits = repeated(200000n,'1',"mend")
  +ok = Strings.equal(Ansi.stripAnsi(plain),plain) && Strings.equal(Ansi.stripAnsi(unfinished),unfinished) && Strings.equal(Ansi.stripAnsi(unfinished ++ "\u{1b}\\end"),"end") && Strings.equal(Ansi.stripAnsi("\u{1b}[" ++ digits),"end")
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("long:ok"),_ => IO.die(Unit,1,"long scanner case failed"))(Unit{})

def run(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case "long" <> rest:
      do IO<Unit>:
        longCases()
        run(rest)
    case value <> rest:
      do IO<Unit>:
        IO.print(Wire.showText(Ansi.stripAnsi(Text.text(value))))
        run(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    run(arguments)
