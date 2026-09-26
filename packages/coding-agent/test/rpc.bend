import Base
import ../src/modes/rpc-client.bend as Client
import ../src/modes/rpc-types.bend as Types
import ../src/core/agent-session.bend as Session
import ../src/core/bash-executor.bend as Bash
import ../src/core/compaction/compaction.bend as Compaction
import ../src/core/session-manager.bend as S
import ../src/core/session-stats.bend as Stats
import ../src/core/tools/index.bend as Tools
import ../../ai/src/types.bend as Ai
import ../../ai/src/utils/thinking-levels.bend as Levels
import ../../agent/src/types.bend as AgentTypes
import ../../runtime/src/json.bend as Decode
import ../../runtime/src/record.bend as R
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/filesystem.bend as FS
import ../../runtime/src/utf8.bend as Utf8
import ../../runtime/src/date.bend as Date
import ../../runtime/src/f64.bend as F

# upstream rpc.test.ts ("RPC mode"), run through RpcClient against the native
# CLI. Upstream skips the suite without an Anthropic key and talks to Claude;
# here every test runs, with the CLI's openai provider pointed by models.json
# at tests/parity/fake_openai.py (started by tests/rpc_client_cli_check.py),
# which answers each request from its content. Assertions are upstream's.
#
# usage: rpc <cli> <cwd> <temporary root> <provider base URL>

# Steps: IO with upstream's thrown errors as failures
# ---------------------------------------------------

def Step(-A: Data) -> Type: IO(Result<&2,&2,String,A>)
def continued(-A: Data,-B: Data,result: Result<&2,&2,String,A>,next: A -> Step(B)) -> Step(B):
  match result:
    case Fail{error}: IO.pure(Result<&2,&2,String,B>,Fail{error})
    case Done{value}: next(value)
def Step.pure(-A: Data,value: A) -> Step(A): IO.pure(Result<&2,&2,String,A>,Done{value})
def Step.bind(-A: Data,-B: Data,step: Step(A),next: A -> Step(B)) -> Step(B):
  IO.bind(Result<&2,&2,String,A>,Result<&2,&2,String,B>,step,result => continued(A,B,result,next))
def lift(-A: Data,action: IO(A)) -> Step(A):
  IO.bind(A,Result<&2,&2,String,A>,action,value => IO.pure(Result<&2,&2,String,A>,Done{value}))
def expect(passed: Bool,message: String) -> Step(Unit):
  IO.pure(Result<&2,&2,String,Unit>,Bool.pick(Result<&2,&2,String,Unit>,passed,Done{Unit{}},Fail{message}))
def rejects(-A: Data,+needle: String,result: Result<&2,&2,String,A>) -> Step(Unit):
  match result:
    case Done{_}: expect(False{},"expected a rejection containing " ++ needle)
    case Fail{+error}: expect(String.contains(error,needle),"rejection " ++ error ++ " lacks " ++ needle)
def sleep(ms: U32) -> Step(Unit): lift(Unit,IO.sleep(ms))

# Test context
# ------------

type Context is Data:
  Context{cli: String,cwd: String,root: String,baseUrl: String,sessionDir: String}
def sessionDirOf(context: Context) -> String:
  match context:
    case Context{_,_,_,_,directory}: directory
def modelsJson(+baseUrl: String) -> String:
  "{\"providers\":{\"openai\":{\"baseUrl\":\"" ++ baseUrl ++ "\"}}}"
def optionsOf(context: Context) -> Client.RpcClientOptions:
  match context:
    case Context{cli,cwd,_,_,directory}: Client.RpcClientOptions{Some{cli},Some{cwd},[R.Property{"PI_CODING_AGENT_DIR",directory}],Some{"openai"},Some{"gpt-5-mini"},Nil{}}

def report(+name: String,result: Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.print("PASS RPC mode > " ++ name)
    case Fail{error}: IO.print("FAIL RPC mode > " ++ name ++ ": " ++ error)
def fsFailure(result: Result<&2,&2,FS.Error,Unit>) -> Result<&2,&2,String,Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{error}: Fail{FS.errorMessage(error)}
# beforeEach: a fresh agent directory and client; afterEach: stop the client
# and remove the directory.
def afterEach(+client: Client.RpcClient,+directory: String,result: Result<&2,&2,String,Unit>) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    Client.stop(client)
    Client.dispose(client)
    removed : Result<&2,&2,FS.Error,Unit> <- FS.remove(directory,True{},True{})
    return result
def prepared(+context: Context,body: Context -> Client.RpcClient -> Step(Unit),written: Result<&2,&2,FS.Error,Unit>) -> IO(Result<&2,&2,String,Unit>):
  match written:
    case Fail{error}: IO.pure(Result<&2,&2,String,Unit>,Fail{"cannot prepare the agent directory: " ++ FS.errorMessage(error)})
    case Done{_}:
      do IO<Result<&2,&2,String,Unit>>:
        +client : Client.RpcClient <- Client.create(optionsOf(context))
        result : Result<&2,&2,String,Unit> <- body(context,client)
        afterEach(client,sessionDirOf(context),result)

# Values
# ------

def textOf(value: Maybe<&2,V.Value>) -> String:
  match value:
    case Some{V.Text{text}}: text
    case _: ""
def fieldOf(value: V.Value,key: String) -> Maybe<&2,V.Value>:
  match value:
    case V.ObjectValue{fields}: R.get(V.Value,fields,key)
    case _: None{}
def typeOf(value: V.Value) -> String: textOf(fieldOf(value,"type"))
def roleOf(message: Maybe<&2,V.Value>) -> String:
  match message:
    case Some{value}: textOf(fieldOf(value,"role"))
    case None{}: ""
def messageRole(event: V.Value) -> String: roleOf(fieldOf(event,"message"))
def countType(values: List<&2,V.Value>,+kind: String) -> Nat:
  match values:
    case Nil{}: 0n
    case value <> rest: Bool.pick(Nat,String.eq(typeOf(value),kind),1n,0n) + countType(rest,kind)
def messageEnds(values: List<&2,V.Value>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case +value <> +rest: Bool.pick(List<&2,V.Value>,String.eq(typeOf(value),"message_end"),value <> messageEnds(rest),messageEnds(rest))
def firstText(parts: List<&2,V.Value>) -> Maybe<&2,String>:
  match parts:
    case Nil{}: None{}
    case +part <> rest: Bool.pick(Maybe<&2,String>,String.eq(typeOf(part),"text"),Some{textOf(fieldOf(part,"text"))},firstText(rest))
def contentText(content: Maybe<&2,V.Value>) -> Maybe<&2,String>:
  match content:
    case Some{V.ArrayValue{parts}}: firstText(parts)
    case _: None{}
def assistantText(ends: List<&2,V.Value>) -> Maybe<&2,String>:
  match ends:
    case Nil{}: None{}
    case +event <> rest:
      Bool.pick(Maybe<&2,String>,String.eq(messageRole(event),"assistant"),Maybe.bind(&2,V.Value,String,fieldOf(event,"message"),message => contentText(fieldOf(message,"content"))),assistantText(rest))

def modelOf(state: Types.RpcSessionState) -> Maybe<&2,Ai.Model<Ai.JsonValue>>:
  match state:
    case Types.RpcSessionState{model,_,_,_,_,_,_,_,_,_,_,_}: model
def levelOf(state: Types.RpcSessionState) -> Ai.ModelThinkingLevel:
  match state:
    case Types.RpcSessionState{_,level,_,_,_,_,_,_,_,_,_,_}: level
def streamingOf(state: Types.RpcSessionState) -> Bool:
  match state:
    case Types.RpcSessionState{_,_,streaming,_,_,_,_,_,_,_,_,_}: streaming
def countOf(state: Types.RpcSessionState) -> Nat:
  match state:
    case Types.RpcSessionState{_,_,_,_,_,_,_,_,_,_,count,_}: count
def nameOf(state: Types.RpcSessionState) -> Maybe<&2,String>:
  match state:
    case Types.RpcSessionState{_,_,_,_,_,_,_,_,name,_,_,_}: name
def sameLevel(left: Ai.ModelThinkingLevel,right: Ai.ModelThinkingLevel) -> Bool:
  String.eq(Levels.name(left),Levels.name(right))
def containsLevel(levels: List<&2,Ai.ModelThinkingLevel>,+level: Ai.ModelThinkingLevel) -> Bool:
  match levels:
    case Nil{}: False{}
    case head <> rest: sameLevel(head,level) || containsLevel(rest,level)
def sameText(left: Maybe<&2,String>,right: Maybe<&2,String>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a,b)
    case _ _: False{}
def sameTexts(left: List<&2,String>,right: List<&2,String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> as b <> bs: String.eq(a,b) && sameTexts(as,bs)
    case _ _: False{}
def entryIds(entries: List<&2,Session.Entry()>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: S.entryId(Unit,Tools.ToolDetails,V.Value,entry) <> entryIds(rest)
def lastId(entries: List<&2,Session.Entry()>) -> Maybe<&2,String>:
  Maybe.map(&2,String,String,id => id,List.last(&2,String,entryIds(entries)))
def providerOf(model: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> String:
  match model:
    case None{}: ""
    case Some{Ai.Model{_,_,_,provider,_,_,_,_,_,_,_,_,_,_,_,_}}: provider
def modelIdOf(model: Maybe<&2,Ai.Model<Ai.JsonValue>>) -> String:
  match model:
    case None{}: ""
    case Some{Ai.Model{id,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}}: id
def isCompaction(entry: Session.Entry()) -> Bool:
  match entry:
    case S.Compaction{_}: True{}
    case _: False{}
def anyCompaction(entries: List<&2,Session.Entry()>) -> Bool:
  match entries:
    case Nil{}: False{}
    case entry <> rest: isCompaction(entry) || anyCompaction(rest)

# The session file
# ----------------

def parsedLine(parsed: Result<&2,&2,Decode.ParseError,V.Value>,rest: List<&2,V.Value>) -> List<&2,V.Value>:
  match parsed:
    case Done{value}: value <> rest
    case Fail{_}: rest
def decodedLines(lines: List<&2,String>) -> List<&2,V.Value>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: parsedLine(Decode.parse(line),decodedLines(rest))
def jsonlFiles(entries: List<&2,FS.DirectoryEntry>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case FS.DirectoryEntry{+name,_} <> +rest: Bool.pick(List<&2,String>,String.ends_with(name,".jsonl"),name <> jsonlFiles(rest),jsonlFiles(rest))
def names(entries: List<&2,FS.DirectoryEntry>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case FS.DirectoryEntry{name,_} <> rest: name <> names(rest)
def fsText(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> Result<&2,&2,String,String>:
  match result:
    case Done{bytes}: Done{Utf8.decodeBytes(bytes)}
    case Fail{error}: Fail{FS.errorMessage(error)}
def fsEntries(result: Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>) -> Result<&2,&2,String,List<&2,FS.DirectoryEntry>>:
  match result:
    case Done{entries}: Done{entries}
    case Fail{error}: Fail{FS.errorMessage(error)}
def directory(path: String) -> Step(List<&2,FS.DirectoryEntry>):
  IO.bind(Result<&2,&2,FS.Error,List<&2,FS.DirectoryEntry>>,Result<&2,&2,String,List<&2,FS.DirectoryEntry>>,FS.readDirectory(path),result => IO.pure(Result<&2,&2,String,List<&2,FS.DirectoryEntry>>,fsEntries(result)))
def runTest(context: Context,+index: Nat,+name: String,body: Context -> Client.RpcClient -> Step(Unit)) -> IO(Unit):
  match context:
    case Context{cli,cwd,+root,+baseUrl,_}:
      do IO<Unit>:
        +directory : String = FS.child(root,"pi-rpc-test-" ++ Nat.show(index))
        made : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(directory)
        written : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(FS.child(directory,"models.json"),modelsJson(baseUrl))
        result : Result<&2,&2,String,Unit> <- prepared(Context{cli,cwd,root,baseUrl,directory},body,written)
        report(name,result)
def readText(path: String) -> Step(String):
  IO.bind(Result<&2,&2,FS.Error,List<&2,U32>>,Result<&2,&2,String,String>,FS.readFile(path),result => IO.pure(Result<&2,&2,String,String>,fsText(result)))
def firstName(values: List<&2,String>) -> String:
  match values:
    case Nil{}: ""
    case value <> _: value
# upstream: sessions/<first cwd directory>/<its only .jsonl file>, split
# into JSON lines.
def sessionFileEntries(+sessionDir: String,expectOne: Bool) -> Step(List<&2,V.Value>):
  do Step<List<&2,V.Value>>:
    +sessionsPath : String = FS.child(sessionDir,"sessions")
    cwdDirs : List<&2,FS.DirectoryEntry> <- directory(sessionsPath)
    +cwdSessionDir : String = FS.child(sessionsPath,firstName(names(cwdDirs)))
    files : List<&2,FS.DirectoryEntry> <- directory(cwdSessionDir)
    +sessionFiles : List<&2,String> = jsonlFiles(files)
    expect(Bool.not(expectOne) || Nat.is_eq(List.length(&2,String,sessionFiles),1n),"expected one session file")
    content : String <- readText(FS.child(cwdSessionDir,firstName(sessionFiles)))
    return decodedLines(String.split(String.trim(content),'\n'))
def entriesOfType(values: List<&2,V.Value>,+kind: String) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case +value <> +rest: Bool.pick(List<&2,V.Value>,String.eq(typeOf(value),kind),value <> entriesOfType(rest,kind),entriesOfType(rest,kind))
def roles(values: List<&2,V.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: messageRole(value) <> roles(rest)
def containsText(values: List<&2,String>,+text: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(value,text) || containsText(rest,text)
def bashMessages(values: List<&2,V.Value>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case +value <> +rest: Bool.pick(List<&2,V.Value>,String.eq(typeOf(value),"message") && String.eq(messageRole(value),"bashExecution"),value <> bashMessages(rest),bashMessages(rest))
def firstValue(values: List<&2,V.Value>) -> V.Value:
  match values:
    case Nil{}: V.Null{}
    case value <> _: value
def unique(+prefix: String) -> Step(String):
  do Step<String>:
    now : F64 <- lift(F64,Date.now())
    return prefix ++ Nat.show(Result.default(&2,&2,F.Error,Nat,F.convert(now),0n))

# Tests
# -----

def started(client: Client.RpcClient) -> Step(Unit): Client.start(client)
def awaited(client: Client.RpcClient,message: String) -> Step(List<&2,V.Value>):
  Client.promptAndWait(client,message,None{},60000)

def getState(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    +state : Types.RpcSessionState <- Client.getState(client)
    +provider : String = providerOf(modelOf(state))
    +modelId : String = modelIdOf(modelOf(state))
    expect(Maybe.is_some(&2,Ai.Model<Ai.JsonValue>,modelOf(state)),"model is undefined")
    expect(String.eq(provider,"openai"),"provider " ++ provider)
    expect(String.eq(modelId,"gpt-5-mini"),"model id " ++ modelId)
    expect(Bool.not(streamingOf(state)),"isStreaming")
    expect(Nat.is_eq(countOf(state),0n),"messageCount")

def saveMessages(+context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Reply with just the word 'hello'")
    expect(Nat.is_ge(List.length(&2,V.Value,messageEnds(events)),2n),"expected user and assistant message_end events")
    sleep(200)
    +entries : List<&2,V.Value> <- sessionFileEntries(sessionDirOf(context),True{})
    expect(String.eq(typeOf(firstValue(entries)),"session"),"first entry is not the session header")
    +messages : List<&2,V.Value> = entriesOfType(entries,"message")
    expect(Nat.is_ge(List.length(&2,V.Value,messages),2n),"expected two messages")
    +found : List<&2,String> = roles(messages)
    expect(containsText(found,"user") && containsText(found,"assistant"),"roles lack user or assistant")

def tokensBeforeOf(result: Compaction.CompactionResult) -> F64:
  match result:
    case Compaction.CompactionResult{_,_,tokensBefore,_,_,_}: tokensBefore
def manualCompaction(+context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Say hello")
    result : Compaction.CompactionResult <- Client.compact(client,None{})
    expect(F.isGreater(F.compare(tokensBeforeOf(result),F.fromU32(0))),"tokensBefore is not positive")
    sleep(200)
    +entries : List<&2,V.Value> <- sessionFileEntries(sessionDirOf(context),False{})
    +compactions : List<&2,V.Value> = entriesOfType(entries,"compaction")
    expect(Nat.is_eq(List.length(&2,V.Value,compactions),1n),"expected one compaction entry")
    expect(Maybe.is_some(&2,V.Value,fieldOf(firstValue(compactions),"summary")),"compaction entry lacks its summary")

def bashFields(result: Bash.BashResult) -> Bool:
  match result:
    case Bash.BashResult{output,exitCode,cancelled,_,_}: String.eq(String.trim(output),"hello") && Maybe.default(&2,Bool,Maybe.map(&2,U32,Bool,code => U32.is_eq(code,0),exitCode),False{}) && Bool.not(cancelled)
def executeBash(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    result : Bash.BashResult <- Client.bash(client,"echo hello")
    expect(bashFields(result),"unexpected bash result")

def bashToContext(+context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Say hi")
    +uniqueValue : String <- unique("test-")
    result : Bash.BashResult <- Client.bash(client,"echo " ++ uniqueValue)
    sleep(200)
    entries : List<&2,V.Value> <- sessionFileEntries(sessionDirOf(context),False{})
    +found : List<&2,V.Value> = bashMessages(entries)
    expect(Nat.is_eq(List.length(&2,V.Value,found),1n),"expected one bashExecution message")
    expect(String.contains(textOf(Maybe.bind(&2,V.Value,V.Value,fieldOf(firstValue(found),"message"),message => fieldOf(message,"output"))),uniqueValue),"bash output lacks the unique value")

def bashInLlmContext(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    +uniqueValue : String <- unique("unique-")
    result : Bash.BashResult <- Client.bash(client,"echo " ++ uniqueValue)
    events : List<&2,V.Value> <- awaited(client,"What was the exact output of the echo command I just ran? Reply with just the value, nothing else.")
    +text : Maybe<&2,String> = assistantText(messageEnds(events))
    expect(Maybe.is_some(&2,String,text),"no assistant message_end")
    expect(String.contains(Maybe.default(&2,String,text,""),uniqueValue),"assistant text lacks the unique value")

def setThinking(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    Client.setThinkingLevel(client,Ai.Thinking{Ai.High{}})
    +state : Types.RpcSessionState <- Client.getState(client)
    expect(sameLevel(levelOf(state),Ai.Thinking{Ai.High{}}),"thinking level is " ++ Levels.name(levelOf(state)))

def levelCycled(cycled: Maybe<&2,Client.ThinkingLevelCycle>) -> Maybe<&2,Ai.ModelThinkingLevel>:
  match cycled:
    case None{}: None{}
    case Some{Client.ThinkingLevelCycle{level}}: Some{level}
def cycleThinking(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    +initialState : Types.RpcSessionState <- Client.getState(client)
    +cycled : Maybe<&2,Client.ThinkingLevelCycle> <- Client.cycleThinkingLevel(client)
    expect(Maybe.is_some(&2,Client.ThinkingLevelCycle,cycled),"cycleThinkingLevel returned null")
    +level : Ai.ModelThinkingLevel = Maybe.default(&2,Ai.ModelThinkingLevel,levelCycled(cycled),levelOf(initialState))
    expect(Bool.not(sameLevel(level,levelOf(initialState))),"level did not change")
    newState : Types.RpcSessionState <- Client.getState(client)
    expect(sameLevel(levelOf(newState),level),"state level differs from the cycled level")

def cycledWithin(+levels: List<&2,Ai.ModelThinkingLevel>,+initial: Ai.ModelThinkingLevel,cycled: Maybe<&2,Ai.ModelThinkingLevel>) -> Bool:
  match cycled:
    case None{}: True{}
    case Some{+level}: containsLevel(levels,level) && (Nat.is_le(List.length(&2,Ai.ModelThinkingLevel,levels),1n) || Bool.not(sameLevel(level,initial)))
def availableLevels(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    +levels : List<&2,Ai.ModelThinkingLevel> <- Client.getAvailableThinkingLevels(client)
    expect(Nat.is_gt(List.length(&2,Ai.ModelThinkingLevel,levels),0n),"no thinking levels")
    +state : Types.RpcSessionState <- Client.getState(client)
    expect(containsLevel(levels,levelOf(state)),"current level is not available")
    cycled : Maybe<&2,Client.ThinkingLevelCycle> <- Client.cycleThinkingLevel(client)
    expect(cycledWithin(levels,levelOf(state),levelCycled(cycled)),"cycled level outside the available levels")

def modelsValid(models: List<&2,Client.ModelInfo>) -> Bool:
  match models:
    case Nil{}: True{}
    case Client.ModelInfo{_,_,contextWindow,_} <> rest: F.isGreater(F.compare(contextWindow,F.fromU32(0))) && modelsValid(rest)
def availableModels(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    +models : List<&2,Client.ModelInfo> <- Client.getAvailableModels(client)
    expect(Nat.is_gt(List.length(&2,Client.ModelInfo,models),0n),"no models")
    expect(modelsValid(models),"a model has no positive context window")

def statsCounts(stats: Stats.Stats) -> Bool:
  match stats:
    case Stats.Stats{file,_,Stats.Totals{users,assistants,_,_,_,_,_,_,_,_},_}: Maybe.is_some(&2,String,file) && Nat.is_ge(users,1n) && Nat.is_ge(assistants,1n)
def sessionStats(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Hello")
    stats : Stats.Stats <- Client.getSessionStats(client)
    expect(statsCounts(stats),"stats lack the session file or message counts")

def newSession(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Hello")
    before : Types.RpcSessionState <- Client.getState(client)
    expect(Nat.is_gt(countOf(before),0n),"no messages before the new session")
    replaced : Client.Cancellable <- Client.newSession(client,None{})
    after : Types.RpcSessionState <- Client.getState(client)
    expect(Nat.is_eq(countOf(after),0n),"messages remain after the new session")

def exportPath(result: Client.ExportResult) -> String:
  match result:
    case Client.ExportResult{path}: path
def exportHtml(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Hello")
    result : Client.ExportResult <- Client.exportHtml(client,None{})
    +path : String = exportPath(result)
    expect(String.ends_with(path,".html"),"export path " ++ path)
    exists : Bool <- lift(Bool,FS.accessible(path,0))
    expect(exists,"exported file is missing")

def lastAssistantText(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    initial : Maybe<&2,String> <- Client.getLastAssistantText(client)
    expect(Maybe.is_none(&2,String,initial),"initial text is defined")
    events : List<&2,V.Value> <- awaited(client,"Reply with just: test123")
    text : Maybe<&2,String> <- Client.getLastAssistantText(client)
    expect(String.contains(Maybe.default(&2,String,text,""),"test123"),"text lacks test123")

def entriesOf(value: Client.SessionEntries) -> List<&2,Session.Entry()>:
  match value:
    case Client.SessionEntries{entries,_}: entries
def leafOf(value: Client.SessionEntries) -> Maybe<&2,String>:
  match value:
    case Client.SessionEntries{_,leafId}: leafId
def entriesSince(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Reply with just 'ok'")
    +all : Client.SessionEntries <- Client.getEntries(client,None{})
    +ids : List<&2,String> = entryIds(entriesOf(all))
    expect(Nat.is_ge(List.length(&2,String,ids),2n),"expected at least two entries")
    expect(sameText(leafOf(all),lastId(entriesOf(all))),"leafId is not the last entry")
    +since : Client.SessionEntries <- Client.getEntries(client,Some{firstName(ids)})
    expect(sameTexts(entryIds(entriesOf(since)),List.drop(&2,String,ids,1n)),"since returned other entries")
    expect(sameText(leafOf(since),leafOf(all)),"since changed leafId")
    missing : Result<&2,&2,String,Client.SessionEntries> <- lift(Result<&2,&2,String,Client.SessionEntries>,Client.getEntries(client,Some{"nonexistent-id"}))
    rejects(Client.SessionEntries,"Entry not found",missing)
type Chain is Data:
  Chain{ids: List<&2,String>,remaining: Nat}
def prependChain(id: String,rest: Chain) -> Chain:
  match rest:
    case Chain{ids,remaining}: Chain{id <> ids,remaining}
# upstream: follow single children from the root, collecting entry ids.
def chain(nodes: List<&2,Types.TreeNode()>) -> Chain:
  match nodes:
    case Nil{}: Chain{Nil{},0n}
    case S.SessionTreeNode{entry,children,_,_} <> Nil{}: prependChain(S.entryId(Unit,Tools.ToolDetails,V.Value,entry),chain(children))
    case _ <> _ <> rest: Chain{Nil{},2n + List.length(&2,Types.TreeNode(),rest)}
def chainMatches(walked: Chain,expected: List<&2,String>) -> Bool:
  match walked:
    case Chain{ids,remaining}: Nat.is_eq(remaining,0n) && sameTexts(ids,expected)
def treeOf(value: Client.SessionTree) -> List<&2,Types.TreeNode()>:
  match value:
    case Client.SessionTree{tree,_}: tree
def treeLeaf(value: Client.SessionTree) -> Maybe<&2,String>:
  match value:
    case Client.SessionTree{_,leafId}: leafId
def sessionTree(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Reply with just 'ok'")
    +all : Client.SessionEntries <- Client.getEntries(client,None{})
    +tree : Client.SessionTree <- Client.getTree(client)
    expect(sameText(treeLeaf(tree),leafOf(all)),"tree leafId differs")
    expect(Nat.is_eq(List.length(&2,Types.TreeNode(),treeOf(tree)),1n),"expected a single root")
    walked : Chain = chain(treeOf(tree))
    expect(chainMatches(walked,entryIds(entriesOf(all))),"the chain differs from the entries or ends in siblings")

def retainEntries(context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    events : List<&2,V.Value> <- awaited(client,"Reply with just 'ok'")
    +before : Client.SessionEntries <- Client.getEntries(client,None{})
    result : Compaction.CompactionResult <- Client.compact(client,None{})
    +after : Client.SessionEntries <- Client.getEntries(client,None{})
    +beforeIds : List<&2,String> = entryIds(entriesOf(before))
    expect(sameTexts(List.take(&2,String,entryIds(entriesOf(after)),List.length(&2,String,beforeIds)),beforeIds),"pre-compaction entries changed")
    expect(anyCompaction(entriesOf(after)),"no compaction entry")

def sessionName(+context: Context,+client: Client.RpcClient) -> Step(Unit):
  do Step<Unit>:
    started(client)
    initial : Types.RpcSessionState <- Client.getState(client)
    expect(Maybe.is_none(&2,String,nameOf(initial)),"session name is initially defined")
    events : List<&2,V.Value> <- awaited(client,"Reply with just 'ok'")
    Client.setSessionName(client,"my-test-session")
    state : Types.RpcSessionState <- Client.getState(client)
    expect(sameText(nameOf(state),Some{"my-test-session"}),"session name not set")
    sleep(200)
    entries : List<&2,V.Value> <- sessionFileEntries(sessionDirOf(context),False{})
    +infos : List<&2,V.Value> = entriesOfType(entries,"session_info")
    expect(Nat.is_eq(List.length(&2,V.Value,infos),1n),"expected one session_info entry")
    expect(String.eq(textOf(fieldOf(firstValue(infos),"name")),"my-test-session"),"session_info name")

def run(args: List<String>) -> IO(Unit):
  match args:
    case cli <> cwd <> root <> baseUrl <> Nil{}:
      do IO<Unit>:
        +context : Context = Context{cli,cwd,root,baseUrl,""}
        runTest(context,1n,"should get state",ctx => client => getState(ctx,client))
        runTest(context,2n,"should save messages to session file",ctx => client => saveMessages(ctx,client))
        runTest(context,3n,"should handle manual compaction",ctx => client => manualCompaction(ctx,client))
        runTest(context,4n,"should execute bash command",ctx => client => executeBash(ctx,client))
        runTest(context,5n,"should add bash output to context",ctx => client => bashToContext(ctx,client))
        runTest(context,6n,"should include bash output in LLM context",ctx => client => bashInLlmContext(ctx,client))
        runTest(context,7n,"should set and get thinking level",ctx => client => setThinking(ctx,client))
        runTest(context,8n,"should cycle thinking level",ctx => client => cycleThinking(ctx,client))
        runTest(context,9n,"should get available thinking levels",ctx => client => availableLevels(ctx,client))
        runTest(context,10n,"should get available models",ctx => client => availableModels(ctx,client))
        runTest(context,11n,"should get session stats",ctx => client => sessionStats(ctx,client))
        runTest(context,12n,"should create new session",ctx => client => newSession(ctx,client))
        runTest(context,13n,"should export to HTML",ctx => client => exportHtml(ctx,client))
        runTest(context,14n,"should get last assistant text",ctx => client => lastAssistantText(ctx,client))
        runTest(context,15n,"should get session entries with since cursor",ctx => client => entriesSince(ctx,client))
        runTest(context,16n,"should get session tree",ctx => client => sessionTree(ctx,client))
        runTest(context,17n,"should retain pre-compaction entries in get_entries",ctx => client => retainEntries(ctx,client))
        runTest(context,18n,"should set and get session name",ctx => client => sessionName(ctx,client))
    case _: IO.die(Unit,1,"usage: rpc <cli> <cwd> <temporary root> <provider base URL>")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
