import Base
import ../src/modes/rpc-client.bend as Client
import ../src/modes/rpc-types.bend as Types
import ../src/modes/jsonl.bend as Jsonl
import ../src/core/agent-session.bend as Session
import ../../ai/src/utils/message-json.bend as Json
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/filesystem.bend as FS

# upstream rpc-client-clear-queue.test.ts, rpc-client-clone.test.ts and
# rpc-client-process-exit.test.ts. The first two substitute the client's
# transport with withSend, as upstream assigns the private `send`; upstream's
# `getData` stub returns `data` just as the real getData does for a success
# response, so the real one is kept. The process-exit child is a shell script
# (the client runs cliPath as an executable), reading one chunk of stdin and
# exiting with 43 as upstream's child.mjs does. That case needs the native
# process primitives.

def report(+name: String,passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit),passed,IO.print("PASS " ++ name),IO.die(Unit,1,"FAIL " ++ name))
def reportResult(+name: String,result: Result<&2,&2,String,Bool>) -> IO(Unit):
  match result:
    case Done{passed}: report(name,passed)
    case Fail{error}: IO.die(Unit,1,"FAIL " ++ name ++ ": " ++ error)

# A transport that records each command it receives and answers with `data`.
type Fake is Data:
  Fake{sent: Ref.Ref<List<&2,String>>,command: String,data: V.Value}
def fakeSend(fake: Fake,command: Types.RpcCommand) -> IO(Result<&2,&2,String,Types.RpcResponse>):
  match fake:
    case Fake{sent,name,data}:
      do IO<Result<&2,&2,String,Types.RpcResponse>>:
        Ref.modify(List<&2,String>,Unit,sent,previous => (List.append(&2,String,previous,[Jsonl.serializeJsonLine(Types.commandValue(command,None{}))]),Unit{}))
        return Done{Types.RpcResponse{None{},name,Types.RpcSuccess{Some{data}}}}
type Faked is Data:
  Faked{client: Client.RpcClient,sent: Ref.Ref<List<&2,String>>,send: Client.Sender()}
def clientOf(fake: Faked) -> Client.RpcClient:
  match fake:
    case Faked{client,_,_}: client
def withFake(command: String,data: V.Value) -> IO(Faked):
  do IO<Faked>:
    client : Client.RpcClient <- Client.create(Client.defaultOptions())
    +sent : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    +send : Client.Sender() <- Callback.create(~Fake,~Types.RpcCommand,~Client.Reply(),~fakeSend,Fake{sent,command,data})
    return Faked{Client.withSend(client,send),sent,send}
def released(fake: Faked) -> IO(List<&2,String>):
  match fake:
    case Faked{client,sent,send}:
      do IO<List<&2,String>>:
        Client.dispose(client)
        Callback.dispose(Types.RpcCommand,Client.Reply(),send)
        Ref.dispose(List<&2,String>,sent)

def texts(values: List<&2,String>) -> V.Value: V.ArrayValue{Types.texts(values)}
def clearedData() -> V.Value:
  Json.object(Json.field("steering",texts(["Change direction"]),Json.field("followUp",texts(["Summarize when finished"]),Nil{})))
def sameText(+left: String,right: String) -> Bool: String.eq(left,right)
def sameLists(left: List<&2,String>,right: List<&2,String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: String.eq(a,b) && sameLists(as,bs)
    case _ _: False{}
def clearedMatches(result: Result<&2,&2,String,Session.QueuedMessages>) -> Result<&2,&2,String,Bool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Session.QueuedMessages{steering,followUp}}: Done{sameLists(steering,["Change direction"]) && sameLists(followUp,["Summarize when finished"])}
def cancelledMatches(result: Result<&2,&2,String,Client.Cancellable>) -> Result<&2,&2,String,Bool>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Client.Cancellable{cancelled}}: Done{Bool.not(cancelled)}
def both(result: Result<&2,&2,String,Bool>,sent: Bool) -> Result<&2,&2,String,Bool>:
  Result.map(&2,&2,String,Bool,Bool,matched => matched && sent,result)

def clearQueueSendsCommand() -> IO(Unit):
  do IO<Unit>:
    +fake : Faked <- withFake("clear_queue",clearedData())
    result : Result<&2,&2,String,Session.QueuedMessages> <- Client.clearQueue(clientOf(fake))
    sent : List<&2,String> <- released(fake)
    reportResult("RpcClient clearQueue > sends the clear_queue RPC command",both(clearedMatches(result),sameLists(sent,["{\"type\":\"clear_queue\"}\n"])))

def cloneSendsCommand() -> IO(Unit):
  do IO<Unit>:
    +fake : Faked <- withFake("clone",Json.object(Json.field("cancelled",V.Boolean{False{}},Nil{})))
    result : Result<&2,&2,String,Client.Cancellable> <- Client.clone(clientOf(fake))
    sent : List<&2,String> <- released(fake)
    reportResult("RpcClient clone > sends the clone RPC command",both(cancelledMatches(result),sameLists(sent,["{\"type\":\"clone\"}\n"])))

# rpc-client-process-exit.test.ts
def childScript() -> String:
  "#!/bin/sh\nread -r line\nexit 43\n"
def exitRejected(result: Result<&2,&2,String,List<&2,Types.RpcSlashCommand>>) -> Result<&2,&2,String,Bool>:
  match result:
    case Done{_}: Fail{"getCommands resolved"}
    case Fail{+error}: Bool.pick(Result<&2,&2,String,Bool>,String.starts_with(error,"Agent process exited (code=43 signal=null)"),Done{True{}},Fail{"unexpected rejection: " ++ error})
def exitCase(+client: Client.RpcClient,started: Result<&2,&2,String,Unit>) -> IO(Result<&2,&2,String,Bool>):
  match started:
    case Fail{error}: IO.pure(Result<&2,&2,String,Bool>,Fail{"start failed: " ++ error})
    case Done{_}:
      do IO<Result<&2,&2,String,Bool>>:
        result : Result<&2,&2,String,List<&2,Types.RpcSlashCommand>> <- Client.getCommands(client)
        return exitRejected(result)
def withScript(+directory: String,+path: String,written: Result<&2,&2,FS.Error,Unit>) -> IO(Unit):
  match written:
    case Fail{error}: IO.die(Unit,1,"FAIL cannot write child script: " ++ FS.errorMessage(error))
    case Done{_}:
      do IO<Unit>:
        +client : Client.RpcClient <- Client.create(Client.RpcClientOptions{Some{path},None{},Nil{},None{},None{},Nil{}})
        started : Result<&2,&2,String,Unit> <- Client.start(client)
        outcome : Result<&2,&2,String,Bool> <- exitCase(client,started)
        Client.stop(client)
        Client.dispose(client)
        removed : Result<&2,&2,FS.Error,Unit> <- FS.remove(directory,True{},True{})
        reportResult("RpcClient child process failures > rejects an in-flight request when the child process exits",outcome)
def processExit(+directory: String) -> IO(Unit):
  do IO<Unit>:
    made : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(directory)
    +path : String = FS.child(directory,"child.sh")
    written : Result<&2,&2,FS.Error,Unit> <- FS.writeFileMode(path,childScript(),493)
    withScript(directory,path,written)

def run(args: List<String>) -> IO(Unit):
  match args:
    case "fake" <> Nil{}:
      do IO<Unit>:
        clearQueueSendsCommand()
        cloneSendsCommand()
    case "process" <> directory <> Nil{}: processExit(directory)
    case _: IO.die(Unit,1,"usage: rpc-client fake | process <temporary directory>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
