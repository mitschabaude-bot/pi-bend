import Base
import ../packages/runtime/src/sha512.bend as SHA
import ../packages/runtime/src/u64.bend as W
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/test/utf8-runner.bend as Bytes

def variant(text: String) -> SHA.Variant:
  Bool.pick(SHA.Variant,String.eq(text,"384"),SHA.Sha384{},SHA.Sha512{})

def chunks(parts: List<&2,String>, state: SHA.State) -> Result<&2,&2,SHA.Error,SHA.State>:
  match parts:
    case Nil{}: Done{state}
    case text <> rest:
      Result.bind(&2,&2,SHA.Error,SHA.State,SHA.State,SHA.update(Bytes.numbers(Split.split(text,',')),state), next => chunks(rest,next))

def error(cause: SHA.Error) -> String:
  match cause:
    case SHA.InvalidByte{value}: "byte:" ++ U32.show(value)
    case SHA.MessageTooLong{}: "length"
    case SHA.InvalidState{}: "state"

def show(result: Result<&2,&2,SHA.Error,List<&2,U32>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{bytes}: String.join(Bytes.showNumbers(bytes),",")

def repeated(count: Nat, reversed: List<&2,U32>) -> List<&2,U32>:
  match count:
    case 0n: reversed
    case 1n+rest: repeated(rest,97 <> reversed)

def countResult(result: Result<&2,&2,SHA.Error,SHA.State>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{SHA.State{_,_,_,used,W.U64{a,b},W.U64{c,d}}}:
      U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ ":" ++ U32.show(used)

type Operation is Data:
  HashOperation{variant: SHA.Variant}
  LengthOperation{}
  CounterOperation{high: W.U64, low: W.U64}

# Explicit string comparisons avoid the compiler's large expansion of
# overlapping string patterns in a multi-field match (see bend-issues.md).
def operation(+text: String) -> Operation:
  Bool.pick(Operation,String.eq(text,"state"),LengthOperation{},
    Bool.pick(Operation,String.eq(text,"carry32"),CounterOperation{W.zero(),W.U64{0,4294967295}},
      Bool.pick(Operation,String.eq(text,"carry64"),CounterOperation{W.zero(),W.U64{4294967295,4294967295}},
        Bool.pick(Operation,String.eq(text,"overflow"),CounterOperation{W.U64{536870911,4294967295},W.U64{4294967295,4294967295}},HashOperation{variant(text)}))))

def runOperation(op: Operation, parts: List<&2,String>) -> String:
  match op parts:
    case CounterOperation{high,low} Nil{}:
      countResult(SHA.update(0 <> Nil{},SHA.State{SHA.Sha512{},SHA.initial(SHA.Sha512{}),SHA.zeros(127n,Nil{}),127,high,low}))
    case LengthOperation{} kind <> a <> b <> c <> d <> Nil{}:
      +algorithm = variant(kind)
      show(SHA.finish(SHA.State{algorithm,SHA.initial(algorithm),Nil{},0,W.U64{Bytes.decimal(a,0),Bytes.decimal(b,0)},W.U64{Bytes.decimal(c,0),Bytes.decimal(d,0)}}))
    case HashOperation{+algorithm} +text <> Nil{}:
      Bool.pick(Unit -> String,String.eq(text,"m"),unused => show(SHA.digest(algorithm,repeated(1000000n,Nil{}))),unused => show(Result.bind(&2,&2,SHA.Error,SHA.State,List<&2,U32>,chunks(Split.split(text,'|'),SHA.create(algorithm)),SHA.finish)))(Unit{})
    case _ _: "invalid"

def run(parts: List<&2,String>) -> String:
  match parts:
    case head <> rest: runOperation(operation(head),rest)
    case Nil{}: "invalid"

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> rest:
      do IO<Unit>:
        IO.print(run(Split.split(head,':')))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
