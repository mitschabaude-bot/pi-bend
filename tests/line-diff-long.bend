import Base
import ../packages/coding-agent/src/core/tools/diff.bend as D
import ../packages/runtime/src/string.bend as Strings

# Construct long lines inside Bend so process argument and fixture serialization
# limits cannot hide a stack overflow in the actual comparison/rendering path.
def repeat(count: Nat, text: String) -> String:
  match count:
    case 0n: text
    case 1n+rest: repeat(rest,SCon{'x',text})

def check(ok: Bool, name: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,name)

def display(value: D.DiffResult, expected: String, first: Maybe<&2,Nat>) -> Bool:
  match value first:
    case D.DiffResult{actual,None{}} None{}: Strings.equal(actual,expected)
    case D.DiffResult{actual,Some{line}} Some{wanted}: Strings.equal(actual,expected) && Nat.is_eq(line,wanted)
    case _ _: False{}

def identity(changes: List<&2,D.Change>, expected: String) -> Bool:
  match changes:
    case D.Change{D.Same{},line <> Nil{}} <> Nil{}: Strings.equal(line,expected)
    case _: False{}

def main() -> IO(Unit):
  +prefix = repeat(200000n,"")
  +before = prefix ++ "a"
  +after = prefix ++ "b"
  do IO<Unit>:
    check(identity(D.diffLines(before,before),before),"long identity changes")
    check(display(D.generateDiffString(before,before,4n),"",None{}),"long identity display")
    check(Strings.equal(D.generateUnifiedPatch("f",before,before,4n),"--- f\n+++ f\n"),"long identity patch")
    check(display(D.generateDiffString(before ++ "\n",after ++ "\n",4n),"-1 " ++ before ++ "\n+1 " ++ after,Some{1n}),"long replacement display")
    check(Strings.equal(D.generateUnifiedPatch("f",before ++ "\n",after ++ "\n",4n),"--- f\n+++ f\n@@ -1,1 +1,1 @@\n-" ++ before ++ "\n+" ++ after ++ "\n"),"long replacement patch")
    check(display(D.generateDiffString(before ++ "\n",before,4n),"-1 " ++ before ++ "\n+1 " ++ before,Some{1n}),"long EOF display")
    check(Strings.equal(D.generateUnifiedPatch("f",before ++ "\n",before,4n),"--- f\n+++ f\n@@ -1,1 +1,1 @@\n-" ++ before ++ "\n+" ++ before ++ "\n\\ No newline at end of file\n"),"long EOF patch")
    check(display(D.generateDiffString(before ++ "\na\n" ++ before,before ++ "\nb\n" ++ before,4n)," 1 " ++ before ++ "\n-2 a\n+2 b\n 3 " ++ before,Some{2n}),"long context display")
    check(Strings.equal(D.generateUnifiedPatch("f",before ++ "\na\n" ++ before,before ++ "\nb\n" ++ before,4n),"--- f\n+++ f\n@@ -1,3 +1,3 @@\n " ++ before ++ "\n-a\n+b\n " ++ before ++ "\n\\ No newline at end of file\n"),"long context patch")
    IO.print("long lines: identity, replacement, EOF and context pass")
