import Base
import ../core/model-runtime.bend as Models
import ../../../ai/src/types.bend as Ai
import ../../../runtime/src/f64.bend as F
import ../../../runtime/src/number-string.bend as Numbers
import ../../../tui/src/fuzzy.bend as Fuzzy
import ../../../runtime/src/stable-sort.bend as Sort

# The catalog is auth-filtered by ModelRuntime; this module only selects and
# presents its entries, as pi's cli/list-models.ts does.
type Row is Data:
  Row{provider: String, model: String, context: String, maxOut: String, thinking: String, images: String}

def searchText(model: Models.Model()) -> String:
  match model:
    case Ai.Model{id,_,_,provider,_,_,_,_,_,_,_,_,_,_,_,_}: provider ++ " " ++ id

def sortFields(model: Models.Model()) -> String & String:
  match model:
    case Ai.Model{id,_,_,provider,_,_,_,_,_,_,_,_,_,_,_,_}: (provider,id)

def notGreater(order: (String & String) & Cmp) -> Bool:
  match order:
    case (_,GT{}): False{}
    case _: True{}

def providerBefore(compared: (String & String) & Cmp,id: String,otherId: String) -> Bool:
  match compared:
    case (_,LT{}): True{}
    case (_,GT{}): False{}
    case _: notGreater(String.cmp(id,otherId))

def beforeOther(provider: String,id: String,right: String & String) -> Bool:
  match right:
    case (otherProvider,otherId): providerBefore(String.cmp(provider,otherProvider),id,otherId)

def fieldsBefore(left: String & String,right: String & String) -> Bool:
  match left:
    case (provider,id): beforeOther(provider,id,right)

def sortedBefore(a: Models.Model(), b: Models.Model()) -> Bool:
  fieldsBefore(sortFields(a),sortFields(b))

def selected(models: List<&2,Models.Model()>, search: Maybe<&2,String>) -> List<&2,Models.Model()>:
  match search:
    case None{}: Sort.sort(~Models.Model(),~sortedBefore,models)
    case Some{pattern}: Sort.sort(~Models.Model(),~sortedBefore,Fuzzy.fuzzyFilter(~Models.Model(),~searchText,models,pattern))

def tokens(+count: F64) -> String:
  +million = U32.to_f64(1000000)
  +thousand = U32.to_f64(1000)
  +divisor = Bool.pick(F64,F64.is_ge(count,million),million,thousand)
  +suffix = Bool.pick(String,F64.is_ge(count,million),"M","K")
  Bool.pick(Unit -> String,F64.is_ge(count,thousand),
    _ => Maybe.default(&2,String,Numbers.formatFixed(F64.div(count,divisor),Bool.pick(Nat,F64.is_eq(F64.mod(count,divisor),U32.to_f64(0)),0n,1n)),"0") ++ suffix,
    _ => Maybe.default(&2,String,F.toDecimal(count),"0"))(Unit{})

def hasImage(inputs: List<&2,Ai.ModelInput>) -> Bool:
  match inputs:
    case Nil{}: False{}
    case Ai.InputImage{} <> _: True{}
    case _ <> rest: hasImage(rest)

def row(model: Models.Model()) -> Row:
  match model:
    case Ai.Model{id,_,_,provider,_,reasoning,_,input,_,_,_,context,maxOut,_,_,_}:
      Row{provider,id,tokens(context),tokens(maxOut),Bool.pick(String,reasoning,"yes","no"),Bool.pick(String,hasImage(input),"yes","no")}

def rows(models: List<&2,Models.Model()>) -> List<&2,Row>:
  match models:
    case Nil{}: Nil{}
    case model <> rest: row(model) <> rows(rest)

type Widths is Data:
  Widths{provider: Nat, model: Nat, context: Nat, maxOut: Nat, thinking: Nat, images: Nat}

def maximum(+a: Nat,+b: Nat) -> Nat: Bool.pick(Nat,Nat.is_ge(a,b),a,b)
def widen(widths: Widths,item: Row) -> Widths:
  match widths item:
    case Widths{a,b,c,d,e,f} Row{provider,model,context,maxOut,thinking,images}:
      Widths{maximum(a,String.length(provider)),maximum(b,String.length(model)),maximum(c,String.length(context)),maximum(d,String.length(maxOut)),maximum(e,String.length(thinking)),maximum(f,String.length(images))}

def widths(rows: List<&2,Row>,current: Widths) -> Widths:
  match rows:
    case Nil{}: current
    case item <> rest: widths(rest,widen(current,item))

def spaces(n: Nat) -> String:
  match n:
    case Zero{}: ""
    case Succ{rest}: " " ++ spaces(rest)

def pad(+text: String,width: Nat) -> String: text ++ spaces(width - String.length(text))
def line(item: Row,widths: Widths) -> String:
  match item widths:
    case Row{a,b,c,d,e,f} Widths{wa,wb,wc,wd,we,wf}:
      pad(a,wa) ++ "  " ++ pad(b,wb) ++ "  " ++ pad(c,wc) ++ "  " ++ pad(d,wd) ++ "  " ++ pad(e,we) ++ "  " ++ pad(f,wf)

def lines(rows: List<&2,Row>,+widths: Widths) -> IO(Unit):
  match rows:
    case Nil{}: IO.pure(Unit,Unit{})
    case item <> rest:
      do IO<Unit>:
        IO.print(line(item,widths))
        lines(rest,widths)

def displaySelected(matching: List<&2,Models.Model()>,search: Maybe<&2,String>) -> IO(Unit):
  match matching:
    case Nil{}: IO.print("No models matching \"" ++ Maybe.default(&2,String,search,"") ++ "\"")
    case matches:
      +rendered = rows(matches)
      +width = widths(rendered,Widths{8n,5n,7n,7n,8n,6n})
      do IO<Unit>:
        IO.print(line(Row{"provider","model","context","max-out","thinking","images"},width))
        lines(rendered,width)

def display(models: List<&2,Models.Model()>,+search: Maybe<&2,String>) -> IO(Unit):
  match models:
    case Nil{}: IO.print("No models available. Use /login to log into a provider via OAuth or API key.")
    case values: displaySelected(selected(values,search),search)

def listModels(runtime: Models.ModelRuntime,search: Maybe<&2,String>) -> IO(Unit):
  do IO<Unit>:
    available : List<&2,Models.Model()> <- Models.getAvailable(runtime)
    display(available,search)
