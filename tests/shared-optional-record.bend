import Base

# Sharing an optional string must not change the value or ownership of an
# optional record of a different type. Both instantiate Base.Some.
type Wide is Data:
  Wide{a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32, a8: U32, a9: U32, a10: U32, a11: U32}

def make(+n: U32) -> Wide: Wide{n, (n + 1 : U32), (n + 2 : U32), (n + 3 : U32), (n + 4 : U32), (n + 5 : U32), (n + 6 : U32), (n + 7 : U32), (n + 8 : U32), (n + 9 : U32), (n + 10 : U32), (n + 11 : U32)}

def chosen(flag: Bool, x: Wide, y: Wide) -> Maybe<&2, Wide>:
  Bool.pick(Maybe<&2, Wide>, flag, Some{x}, Some{y})

def total(value: Maybe<&2, Wide>) -> U32:
  match value:
    case None{}: 0
    case Some{Wide{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11}}: (a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11 : U32)

def length(value: Maybe<&2, String>) -> U32:
  match value:
    case None{}: 0
    case Some{s}: U32.from_nat(String.length(s))

def lengths(values: List<&2, Maybe<&2, String>>) -> U32:
  match values:
    case Nil{}: 0
    case head <> rest: (length(head) + lengths(rest) : U32)

def shared(+value: Maybe<&2, String>) -> U32: lengths(value <> value <> Nil{})

def record(+n: U32) -> U32:
  total(chosen(U32.is_eq(n, 0), make(n), make((n + 1 : U32))))

def run(order: String, +text: String) -> U32:
  match order:
    case "before": (shared(Some{text}) + record(U32.from_nat(String.length(text))) : U32)
    case _: (record(U32.from_nat(String.length(text))) + shared(Some{text}) : U32)

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case order <> text <> Nil{}: IO.print(U32.show(run(order, text)))
    case _: IO.print("expected order and text")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
