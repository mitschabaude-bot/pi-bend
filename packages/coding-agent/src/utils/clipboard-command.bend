import Base
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/ref.bend as Ref

# pi-mono packages/coding-agent/src/utils/clipboard-command.ts: runs a
# clipboard command and gives its stdout bytes. None means the command
# failed (not found, a non-zero exit, a timeout, or more than maxBytes of
# output); an empty list is a successful, empty result.
def DEFAULT_TIMEOUT_MS() -> U32: 3000
def DEFAULT_MAX_BUFFER_BYTES() -> Nat: 52428800n

type Options is Data: Options{input: Maybe<&2,String>,timeoutMs: Maybe<&2,U32>,maxBufferBytes: Maybe<&2,Nat>}
def options() -> Options: Options{None{},None{},None{}}
def withTimeout(+timeoutMs: U32) -> Options: Options{None{},Some{timeoutMs},None{}}

type Capture is Data: Capture{reversed: List<&2,U32>,size: Nat,limit: Nat}
def captured(+bytes: List<&2,U32>,state: Capture) -> Capture & Result<&2,&2,String,Unit>:
  match state:
    case Capture{+reversed,+size,+limit}:
      +next = size + List.length(&2,U32,bytes)
      Bool.pick(Unit -> Capture & Result<&2,&2,String,Unit>,Nat.is_le(next,limit),
        _ => (Capture{List.append(&2,U32,List.reverse(&2,U32,bytes),reversed),next,limit},Done{Unit{}}),
        _ => (Capture{reversed,size,limit},Fail{"clipboard output exceeds its limit"}))(Unit{})
def capture(target: Ref.Ref<Capture>,bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  Ref.modify(Capture,Result<&2,&2,String,Unit>,target,state => captured(bytes,state))
def outcome(result: Result<&2,&2,Child.ExecutionError,U32>,state: Capture) -> Maybe<&2,List<&2,U32>>:
  match result state:
    case Done{0} Capture{reversed,_,_}: Some{List.reverse(&2,U32,reversed)}
    case _ _: None{}
def input(options: Options) -> String:
  match options: case Options{value,_,_}: Maybe.default(&2,String,value,"")
def fed(options: Options) -> Bool:
  match options: case Options{value,_,_}: Maybe.is_some(&2,String,value)
def timeoutOf(options: Options) -> U32:
  match options: case Options{_,value,_}: Maybe.default(&2,U32,value,DEFAULT_TIMEOUT_MS())
def limitOf(options: Options) -> Nat:
  match options: case Options{_,_,value}: Maybe.default(&2,Nat,value,DEFAULT_MAX_BUFFER_BYTES())
def runResolved(program: Maybe<&2,String>,args: List<String>,+options: Options,cwd: String,env: List<String>) -> IO(Maybe<&2,List<&2,U32>>):
  match program:
    case None{}: IO.pure(Maybe<&2,List<&2,U32>>,None{})
    case Some{path}:
      do IO<Maybe<&2,List<&2,U32>>>:
        +state : Ref.Ref<Capture> <- Ref.new(Capture,Capture{Nil{},0n,limitOf(options)})
        +sink : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Ref.Ref<Capture>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~capture,state)
        result : Result<&2,&2,Child.ExecutionError,U32> <- Child.executeValidated(Child.Stdout{},fed(options),path,args,input(options),cwd,env,Nil{},sink,Done{Some{timeoutOf(options)}})
        Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,sink)
        collected : Capture <- Ref.dispose(Capture,state)
        return outcome(result,collected)
def runFound(name: String,args: List<String>,options: Options,cwd: String,found: String & List<String>) -> IO(Maybe<&2,List<&2,U32>>):
  match found:
    case (path,env):
      do IO<Maybe<&2,List<&2,U32>>>:
        program : Maybe<&2,String> <- Child.resolveCommand(name,path)
        runResolved(program,args,options,cwd,env)
def runClipboardCommand(command: String,args: List<String>,options: Options,cwd: String) -> IO(Maybe<&2,List<&2,U32>>):
  do IO<Maybe<&2,List<&2,U32>>>:
    env : List<String> <- IO.environment()
    runFound(command,args,options,cwd,Child.withSearchPath(env,None{}))
