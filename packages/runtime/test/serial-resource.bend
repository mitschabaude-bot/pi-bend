import Base
import ../src/serial-resource.bend as Serial
import ../src/ref.bend as Ref

type Token is Type:
  Token{value: U32}

def assertion(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def updateTrace(label: String, prior: List<&2, String>) -> List<&2, String> & Unit:
  (label <> prior, Unit{})

def log(trace: Ref.Ref<List<&2, String>>, label: String) -> IO(Unit):
  Ref.modify(List<&2, String>, Unit, trace, prior => updateTrace(label, prior))

def first(started: Chan(Unit), release: Chan(Unit), +trace: Ref.Ref<List<&2, String>>, token: Token) -> IO(Token & Result<&2, &2, String, U32>):
  match token:
    case Token{value}:
      do IO<Token & Result<&2, &2, String, U32>>:
        log(trace, "first:start")
        sent : Bool <- Chan.send(Unit, started, Unit{})
        Ref.requireSent(sent)
        ready : Unit <- IO.join(Unit, release)
        log(trace, "first:end")
        return (Token{(value + 1 : U32)}, Fail{"expected"})

def second(trace: Ref.Ref<List<&2, String>>, token: Token) -> IO(Token & Result<&2, &2, String, U32>):
  match token:
    case Token{+value}:
      do IO<Token & Result<&2, &2, String, U32>>:
        log(trace, "second")
        return (Token{(value + 1 : U32)}, Done{value})

def failures(result: Result<&2, &2, String, U32>) -> Bool:
  match result:
    case Fail{"expected"}: True{}
    case _: False{}

def successes(result: Result<&2, &2, String, U32>) -> Bool:
  match result:
    case Done{1}: True{}
    case _: False{}

def final(token: Token) -> Bool:
  match token:
    case Token{2}: True{}
    case _: False{}

def runBorrowed(owner: Serial.Owner<Token>, +handle: Serial.Handle<Token>) -> IO(Unit):
  do IO<Unit>:
    +trace : Ref.Ref<List<&2, String>> <- Ref.new(List<&2, String>, Nil{})
    +started : Chan(Unit) <- Chan.new(Unit, 1)
    +release : Chan(Unit) <- Chan.new(Unit, 1)
    a : Chan(Result<&2, &2, String, U32>) <- IO.fork(Result<&2, &2, String, U32>, Serial.run(Token, Result<&2, &2, String, U32>, handle, token => first(started, release, trace, token)))
    ready : Unit <- IO.join(Unit, started)
    b : Chan(Result<&2, &2, String, U32>) <- IO.fork(Result<&2, &2, String, U32>, Serial.run(Token, Result<&2, &2, String, U32>, handle, token => second(trace, token)))
    sent : Bool <- Chan.send(Unit, release, Unit{})
    Ref.requireSent(sent)
    firstResult : Result<&2, &2, String, U32> <- IO.join(Result<&2, &2, String, U32>, a)
    secondResult : Result<&2, &2, String, U32> <- IO.join(Result<&2, &2, String, U32>, b)
    token : Token <- Serial.retire(Token, owner)
    events : List<&2, String> <- Ref.dispose(List<&2, String>, trace)
    assertion(failures(firstResult) && successes(secondResult) && final(token), "typed failure must release successor resource")
    assertion(String.eq(String.join(List.reverse(&2, String, events), "|"), "first:start|first:end|second"), "resource operations must remain serialized across awaits")

def borrowed(pair: Serial.Owner<Token> & Serial.Handle<Token>) -> IO(Unit):
  match pair:
    case Tuple{owner, handle}: runBorrowed(owner, handle)

def main() -> IO(Unit):
  do IO<Unit>:
    owner : Serial.Owner<Token> <- Serial.create(Token, Token{0})
    borrowed(Serial.borrow(Token, owner))
    IO.print("PASS serial affine resource: async exclusion and typed-failure release")
