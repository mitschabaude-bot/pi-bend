import Base
import ../../../../../tui/src/utils.bend as U
import ../../../../../runtime/src/f64.bend as F
import ../../../../../runtime/src/posix-path.bend as Path
import ../../../../../runtime/src/text.bend as Text
import ../theme/theme.bend as Theme

# Immutable footer input. Callers accumulate usage across the whole session,
# including summaries, compactions and tool results; latestAssistant is only
# the most recent assistant response and supplies the cache-hit percentage.
type Usage is Data: Usage{input: Nat,output: Nat,cacheRead: Nat,cacheWrite: Nat,cost: F64}
type Model is Data: Model{id: String,provider: String,reasoning: Bool,contextWindow: Nat}
type Status is Data: Status{key: String,text: String}
type State is Data:
  State{cwd: String,home: Maybe<&2,String>,branch: Maybe<&2,String>,sessionName: Maybe<&2,String>,model: Maybe<&2,Model>,thinkingLevel: String,totals: Usage,latestAssistant: Maybe<&2,Usage>,contextPercent: Maybe<&2,F64>,contextWindow: Maybe<&2,Nat>,providerCount: Nat,subscription: Bool,autoCompact: Bool,experimental: Bool,statuses: List<&2,Status>}

def emptyUsage() -> Usage: Usage{0n,0n,0n,0n,F.fromU32(0)}
def addUsage(left: Usage,right: Usage) -> Usage:
  match left right:
    case Usage{a,b,c,d,e} Usage{f,g,h,i,j}: Usage{a + f,b + g,c + h,d + i,F.add(e,j)}

def zeros(count: Nat) -> String:
  match count:
    case Zero{}: ""
    case Succ{rest}: "0" ++ zeros(rest)
def fixed(value: F64,+scale: Nat,digits: Nat) -> String:
  +rounded = U32.to_nat(F64.to_u32(F.add(F.multiply(value,F.fromNat(scale)),F.divide(F.fromU32(1),F.fromU32(2)))))
  +fraction = Nat.show(Nat.mod(rounded,scale))
  Nat.show(Nat.div(rounded,scale)) ++ "." ++ zeros(digits - String.length(fraction)) ++ fraction
def roundedDiv(number: Nat,+denominator: Nat) -> Nat: Nat.div(number + Nat.div(denominator,2n),denominator)
def tokens(+count: Nat) -> String:
  Bool.pick(Unit -> String,Nat.is_lt(count,1000n),_ => Nat.show(count),_ =>
    Bool.pick(Unit -> String,Nat.is_lt(count,10000n),_ => fixed(F.divide(F.fromNat(count),F.fromU32(1000)),10n,1n) ++ "k",_ =>
      Bool.pick(Unit -> String,Nat.is_lt(count,1000000n),_ => Nat.show(roundedDiv(count,1000n)) ++ "k",_ =>
        Bool.pick(String,Nat.is_lt(count,10000000n),fixed(F.divide(F.fromNat(count),F.fromU32(1000000)),10n,1n) ++ "M",Nat.show(roundedDiv(count,1000000n)) ++ "M"))(Unit{}))(Unit{}))(Unit{})

def cwdResolved(cwd: String,resolvedCwdValue: Maybe<&2,String>,resolvedHomeValue: Maybe<&2,String>) -> String:
  match resolvedCwdValue resolvedHomeValue:
    case Some{resolvedCwd} Some{resolvedHome}:
      +relative = Path.relative(resolvedHome,resolvedCwd)
      Bool.pick(String,String.eq(relative,"") || (Bool.not(String.eq(relative,"..")) && Bool.not(String.starts_with(relative,"../")) && Bool.not(Path.isAbsolute(relative))),Bool.pick(String,String.eq(relative,""),"~","~/" ++ relative),cwd)
    case _ _: cwd
def cwdForFooter(+cwd: String,home: Maybe<&2,String>) -> String:
  match home:
    case None{}: cwd
    case Some{""}: cwd
    case Some{base}:
      cwdResolved(cwd,Path.resolve("/",cwd),Path.resolve("/",base))

def maybeSuffix(value: Maybe<&2,String>,prefix: String) -> String:
  match value:
    case None{}: ""
    case Some{""}: ""
    case Some{text}: prefix ++ text
def branchSuffix(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: ""
    case Some{""}: ""
    case Some{text}: " (" ++ text ++ ")"
def directory(state: State) -> String:
  match state:
    case State{cwd,home,branch,sessionName,_,_,_,_,_,_,_,_,_,_,_}:
      cwdForFooter(cwd,home) ++ branchSuffix(branch) ++ maybeSuffix(sessionName," • ")

def cacheRate(usage: Usage) -> Maybe<&2,F64>:
  match usage:
    case Usage{input,_,+read,write,_}:
      +prompt = input + read + write
      Bool.pick(Maybe<&2,F64>,Nat.is_eq(prompt,0n),None{},Some{F.multiply(F.divide(F.fromNat(read),F.fromNat(prompt)),F.fromU32(100))})
def rateText(rate: Maybe<&2,F64>,cacheTokens: Nat) -> String:
  match rate:
    case Some{value}: Bool.pick(String,Nat.is_gt(cacheTokens,0n)," CH" ++ fixed(value,10n,1n) ++ "%","")
    case None{}: ""
def latestRate(usage: Maybe<&2,Usage>,cacheTokens: Nat) -> String:
  match usage:
    case Some{entry}: rateText(cacheRate(entry),cacheTokens)
    case None{}: ""
def countPart(prefix: String,+count: Nat) -> String:
  Bool.pick(String,Nat.is_eq(count,0n),""," " ++ prefix ++ tokens(count))
def costPart(+cost: F64,+subscription: Bool) -> String:
  Bool.pick(String,F.isGreater(F.compare(cost,F.fromU32(0))) || subscription," $" ++ fixed(cost,1000n,3n) ++ Bool.pick(String,subscription," (sub)",""),"")
def contextText(percent: Maybe<&2,F64>,window: Nat,autoCompact: Bool) -> String:
  match percent:
    case None{}: "?/" ++ tokens(window) ++ Bool.pick(String,autoCompact," (auto)","")
    case Some{value}: fixed(value,10n,1n) ++ "%/" ++ tokens(window) ++ Bool.pick(String,autoCompact," (auto)","")
def paintResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{value}: IO.pure(String,value)
    case Fail{_}: IO.die(String,1,"invalid footer theme color")
def painted(theme: Theme.Theme,key: String,text: String) -> IO(String):
  paintResult(Theme.foreground(theme,key,text))
def contextColor(+theme: Theme.Theme,percent: Maybe<&2,F64>,+text: String) -> IO(String):
  match percent:
    case None{}: IO.pure(String,text)
    case Some{+value}:
      Bool.pick(Unit -> IO(String),F.isGreater(F.compare(value,F.fromU32(90))),_ => painted(theme,"error",text),_ =>
        Bool.pick(Unit -> IO(String),F.isGreater(F.compare(value,F.fromU32(70))),_ => painted(theme,"warning",text),_ => IO.pure(String,text))(Unit{}))(Unit{})
def usageLine(totals: Usage,latest: Maybe<&2,Usage>,subscription: Bool) -> String:
  match totals:
    case Usage{input,output,+read,+write,cost}:
      +base = countPart("↑",input) ++ countPart("↓",output) ++ countPart("R",read) ++ countPart("W",write) ++ latestRate(latest,read + write) ++ costPart(cost,subscription)
      Bool.pick(String,String.starts_with(base," "),String.drop(base,1n),base)
def modelWindow(value: Maybe<&2,Model>) -> Nat:
  match value:
    case Some{Model{_,_,_,window}}: window
    case None{}: 0n
def contextWindow(override: Maybe<&2,Nat>,model: Maybe<&2,Model>) -> Nat:
  match override:
    case Some{window}: window
    case None{}: modelWindow(model)
def leftLine(state: State,+theme: Theme.Theme) -> IO(String):
  match state:
    case State{_,_,_,_,model,_,Usage{input,output,read,write,cost},latest,+percent,window,_,subscription,auto,+experimental,_}:
      do IO<String>:
        context : String <- contextColor(theme,percent,contextText(percent,contextWindow(window,model),auto))
        +plain : String <- IO.pure(String,usageLine(Usage{input,output,read,write,cost},latest,subscription))
        xp : String <- Bool.pick(Unit -> IO(String),experimental,_ => painted(theme,"warning","xp"),_ => IO.pure(String,""))(Unit{})
        bullet : String <- Bool.pick(Unit -> IO(String),experimental,_ => painted(theme,"dim","•"),_ => IO.pure(String,""))(Unit{})
        return plain ++ Bool.pick(String,String.eq(plain,""),""," ") ++ context ++ Bool.pick(String,experimental," " ++ bullet ++ " \u{1b}[1m" ++ xp ++ "\u{1b}[22m","")
def modelRight(model: Maybe<&2,Model>,+thinking: String) -> String:
  match model:
    case None{}: "no-model"
    case Some{Model{id,_,False{},_}}: id
    case Some{Model{id,_,True{},_}}: id ++ " • " ++ Bool.pick(String,String.eq(thinking,"off") || String.eq(thinking,""),"thinking off",thinking)
def withProvider(model: Maybe<&2,Model>,count: Nat,+base: String,leftWidth: Nat,width: Nat) -> String:
  match model:
    case None{}: base
    case Some{Model{_,provider,_,_}}:
      +candidate = "(" ++ provider ++ ") " ++ base
      Bool.pick(String,Nat.is_gt(count,1n) && Nat.is_le(leftWidth + 2n + U.visibleWidth(candidate),width),candidate,base)
def rightTruncated(left: String,right: String,+width: Nat,+leftWidth: Nat) -> String:
  +shortRight = U.truncateToWidth(right,width - leftWidth - 2n,"",False{})
  left ++ U.spaces(width - leftWidth - U.visibleWidth(shortRight),"") ++ shortRight
def statsLine(left: String,+right: String,+width: Nat) -> String:
  +shortLeft = U.truncateToWidth(left,width,"...",False{})
  +leftWidth = U.visibleWidth(shortLeft)
  +rightWidth = U.visibleWidth(right)
  Bool.pick(Unit -> String,Nat.is_le(leftWidth + 2n + rightWidth,width),
    _ => shortLeft ++ U.spaces(width - leftWidth - rightWidth,"") ++ right,
    _ => Bool.pick(Unit -> String,Nat.is_gt(width,leftWidth + 2n),
      _ => rightTruncated(shortLeft,right,width,leftWidth),_ => shortLeft)(Unit{}))(Unit{})

def cleanStatusGo(text: String,+reversed: String,space: Bool) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      +code = Char.to_u32(char)
      +blank = U32.is_eq(code,32) || U32.is_eq(code,9) || U32.is_eq(code,13) || U32.is_eq(code,10)
      Bool.pick(Unit -> String,blank,
        _ => cleanStatusGo(rest,Bool.pick(String,String.eq(reversed,"") || space,reversed,SCon{' ',reversed}),True{}),
        _ => cleanStatusGo(rest,SCon{char,reversed},False{}))(Unit{})
def cleanStatus(text: String) -> String: Text.trim(cleanStatusGo(text,"",False{}))
def statusBefore(a: Status,b: Status) -> Bool:
  match a b:
    case Status{key,_} Status{other,_}: String.is_le(key,other)
def statusTexts(statuses: List<&2,Status>) -> List<&2,String>:
  match statuses:
    case Nil{}: Nil{}
    case Status{_,text} <> rest: cleanStatus(text) <> statusTexts(rest)
def statusLine(statuses: List<&2,Status>,theme: Theme.Theme,width: Nat) -> IO(String):
  do IO<String>:
    ellipsis : String <- painted(theme,"dim","...")
    return U.truncateToWidth(String.join(statusTexts(List.sort(~Status,~statusBefore,statuses))," "),width,ellipsis,False{})
def withStatuses(statuses: List<&2,Status>,theme: Theme.Theme,width: Nat,first: String,second: String) -> IO(List<&2,String>):
  match statuses:
    case Nil{}: IO.pure(List<&2,String>,first <> second <> Nil{})
    case _:
      do IO<List<&2,String>>:
        third : String <- statusLine(statuses,theme,width)
        return first <> second <> third <> Nil{}

def render(+state: State,+theme: Theme.Theme,+width: Nat) -> IO(List<&2,String>):
  match state:
    case State{_,_,_,_,+model,thinking,_,_,_,_,providers,_,_,_,statuses}:
      do IO<List<&2,String>>:
        dimCwd : String <- painted(theme,"dim",directory(state))
        ellipsis : String <- painted(theme,"dim","...")
        +first : String <- IO.pure(String,U.truncateToWidth(dimCwd,width,ellipsis,False{}))
        +rightBase : String <- IO.pure(String,modelRight(model,thinking))
        +left : String <- leftLine(state,theme)
        +right : String <- IO.pure(String,withProvider(model,providers,rightBase,U.visibleWidth(left),width))
        +line : String <- IO.pure(String,statsLine(left,right,width))
        dimLeft : String <- painted(theme,"dim",U.truncateToWidth(left,width,"...",False{}))
        +remainder : String <- IO.pure(String,String.drop(line,String.length(U.truncateToWidth(left,width,"...",False{}))))
        dimRemainder : String <- painted(theme,"dim",remainder)
        withStatuses(statuses,theme,width,first,dimLeft ++ dimRemainder)
