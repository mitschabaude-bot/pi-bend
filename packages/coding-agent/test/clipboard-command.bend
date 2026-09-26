import Base
import ../src/utils/clipboard-command.bend as Cmd

# pi-mono packages/coding-agent/test/clipboard-command.test.ts. Upstream runs
# `node -e` scripts; the same contracts run through /bin/sh here (a native
# binary has no Node): binary stdout, empty success versus failure, a missing
# program, Unicode stdin, the timeout and the output limit.

def report(+name: String,passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit),passed,IO.print("PASS " ++ name),IO.print("FAIL " ++ name))
def sameBytes(a: List<&2,U32>,b: List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && sameBytes(xs,ys)
    case _ _: False{}
def isBytes(value: Maybe<&2,List<&2,U32>>,expected: List<&2,U32>) -> Bool:
  match value:
    case Some{bytes}: sameBytes(bytes,expected)
    case None{}: False{}
def isNone(value: Maybe<&2,List<&2,U32>>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}
def sh(+script: String,options: Cmd.Options) -> IO(Maybe<&2,List<&2,U32>>):
  Cmd.runClipboardCommand("/bin/sh",["-c",script],options,"/")

def binary(_: Unit) -> IO(Unit):
  do IO<Unit>:
    written : Maybe<&2,List<&2,U32>> <- sh("printf '\\000\\377\\n'",Cmd.options())
    empty : Maybe<&2,List<&2,U32>> <- sh(":",Cmd.options())
    failed : Maybe<&2,List<&2,U32>> <- sh("exit 1",Cmd.options())
    missing : Maybe<&2,List<&2,U32>> <- Cmd.runClipboardCommand("pi-clipboard-command-does-not-exist",Nil{},Cmd.options(),"/")
    report("clipboard commands > preserves binary output and distinguishes empty success from failure",isBytes(written,[0,255,10]) && isBytes(empty,Nil{}) && isNone(failed) && isNone(missing))
def unicode(_: Unit) -> IO(Unit):
  do IO<Unit>:
    result : Maybe<&2,List<&2,U32>> <- sh("[ \"$(cat)\" = 'café 日本語' ]",Cmd.Options{Some{"café 日本語"},None{},None{}})
    report("clipboard commands > sends Unicode input to clipboard writers",isBytes(result,Nil{}))
def millis(time: U32 & U32) -> Nat:
  match time:
    case (high,low): Nat.add(Nat.mul(U32.to_nat(high),Nat.mul(65536n,65536n)),U32.to_nat(low))
def elapsed(started: U32 & U32,ended: U32 & U32) -> Nat: Nat.sub(millis(ended),millis(started))
# Upstream also checks the event loop kept running; the native lane checks
# that the command was stopped at the timeout rather than waited for.
def timeout(_: Unit) -> IO(Unit):
  do IO<Unit>:
    started : U32 & U32 <- IO.unixMilliseconds()
    result : Maybe<&2,List<&2,U32>> <- sh("sleep 5",Cmd.Options{None{},Some{200},None{}})
    ended : U32 & U32 <- IO.unixMilliseconds()
    report("clipboard commands > times out without blocking the event loop",isNone(result) && Nat.is_lt(elapsed(started,ended),3000n))
def limit(_: Unit) -> IO(Unit):
  do IO<Unit>:
    result : Maybe<&2,List<&2,U32>> <- sh("head -c 1024 /dev/zero",Cmd.Options{None{},None{},Some{16n}})
    report("clipboard commands > rejects output above the buffer limit",isNone(result))

def main() -> IO(Unit):
  do IO<Unit>:
    binary(Unit{})
    unicode(Unit{})
    timeout(Unit{})
    limit(Unit{})
