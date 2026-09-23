import Base
import ../packages/coding-agent/src/modes/interactive/components/footer.bend as Footer
import ../packages/coding-agent/src/modes/interactive/theme/theme.bend as Theme
import ../packages/coding-agent/src/modes/interactive/theme/color.bend as Color
import ../packages/runtime/src/f64.bend as F

def loaded(result: Result<&2,&2,Theme.LoadError,Theme.Theme>) -> IO(Theme.Theme):
  match result:
    case Done{theme}: IO.pure(Theme.Theme,theme)
    case Fail{_}: IO.die(Theme.Theme,1,"theme load failed")
def u(input: Nat,output: Nat,read: Nat,write: Nat,milli: Nat) -> Footer.Usage:
  Footer.Usage{input,output,read,write,F.divide(F.fromNat(milli),F.fromU32(1000))}
def model(id: String,provider: String,reasoning: Bool) -> Maybe<&2,Footer.Model>:
  Some{Footer.Model{id,provider,reasoning,200000n}}
def state(cwd: String,home: Maybe<&2,String>,branch: Maybe<&2,String>,name: Maybe<&2,String>,model: Footer.Model,thinking: String,totals: Footer.Usage,latest: Maybe<&2,Footer.Usage>,percent: Maybe<&2,F64>,providers: Nat,subscription: Bool,auto: Bool,statuses: List<&2,Footer.Status>) -> Footer.State:
  Footer.State{cwd,home,branch,name,Some{model},thinking,totals,latest,percent,Some{200000n},providers,subscription,auto,False{},statuses}
def output(label: String,lines: List<&2,String>) -> IO(Unit):
  IO.print(label ++ "\u{1e}" ++ String.join(lines,"\u{1f}"))
def repeated(+text: String,count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: text ++ repeated(text,rest)
def run(+theme: Theme.Theme) -> IO(Unit):
  do IO<Unit>:
    basic : List<&2,String> <- Footer.render(state("/home/user/project",Some{"/home/user"},Some{"main"},Some{repeated("한글",30n)},Footer.Model{"test-model","test",False{},200000n},"off",Footer.emptyUsage(),None{},Some{F.divide(F.fromU32(123),F.fromU32(10))},1n,False{},True{},Nil{}),theme,93n)
    output("basic",basic)
    +wideUsage : Footer.Usage <- IO.pure(Footer.Usage,u(12345n,6789n,0n,0n,1234n))
    wide : List<&2,String> <- Footer.render(state("/tmp/project",None{},Some{"main"},None{},Footer.Model{repeated("模",30n),"공급자",True{},200000n},"high",wideUsage,Some{wideUsage},Some{F.divide(F.fromU32(123),F.fromU32(10))},2n,False{},True{},Nil{}),theme,60n)
    output("wide-model",wide)
    +summary : Footer.Usage <- IO.pure(Footer.Usage,Footer.addUsage(Footer.addUsage(Footer.addUsage(u(100n,10n,0n,0n,500n),u(20n,5n,0n,0n,250n)),u(5n,2n,0n,0n,125n)),u(15n,3n,0n,0n,375n)))
    cumulative : List<&2,String> <- Footer.render(state("/home/user2",Some{"/home/user"},Some{"main"},None{},Footer.Model{"test-model","test",False{},200000n},"off",summary,Some{u(100n,10n,0n,0n,500n)},Some{F.divide(F.fromU32(123),F.fromU32(10))},1n,False{},True{},Nil{}),theme,120n)
    output("cumulative",cumulative)
    +cached : Footer.Usage <- IO.pure(Footer.Usage,u(100n,10n,50n,50n,1n))
    cache : List<&2,String> <- Footer.render(state("/tmp/project",None{},None{},None{},Footer.Model{"test-model","test",False{},200000n},"off",cached,Some{cached},Some{F.divide(F.fromU32(725),F.fromU32(10))},1n,False{},True{},Nil{}),theme,120n)
    output("cache",cache)
    subscription : List<&2,String> <- Footer.render(state("/tmp/project",None{},None{},None{},Footer.Model{"test-model","anthropic",False{},200000n},"off",Footer.emptyUsage(),None{},Some{F.divide(F.fromU32(911),F.fromU32(10))},1n,True{},False{},Nil{}),theme,120n)
    output("subscription",subscription)
    statuses : List<&2,String> <- Footer.render(state("/tmp/project",None{},None{},None{},Footer.Model{"test-model","test",False{},200000n},"off",Footer.emptyUsage(),None{},None{},1n,False{},True{},Footer.Status{"z"," build\n done "} <> Footer.Status{"a"," lint\t pass  "} <> Nil{}),theme,48n)
    output("statuses",statuses)
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2,&2,Theme.LoadError,Theme.Theme> <- Theme.loadFromPath("packages/coding-agent/src/modes/interactive/theme/dark.json",Color.Palette256{})
    +theme : Theme.Theme <- loaded(result)
    run(theme)
