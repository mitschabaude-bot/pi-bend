import Base
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/message-json.bend as Json
import ../../../ai/src/utils/model-api.bend as Api
import ../../../ai/src/utils/model-json.bend as ModelJson
import ../../../ai/src/utils/thinking-levels.bend as Levels
import ../../../agent/src/types.bend as AgentTypes
import ../core/agent-session.bend as Session
import ../core/bash-executor.bend as Bash
import ../core/model-config.bend as Config
import ../core/provider-composer.bend as Composer
import ../core/session-json.bend as SessionJson
import ../core/session-manager.bend as S
import ../core/skills.bend as Skills
import ../core/tools/index.bend as Tools

# pi v0.87.1 modes/rpc/rpc-types.ts: the typed RPC protocol and its JSON wire
# form. Commands and responses are LF-delimited JSON records (./jsonl.bend).
# Upstream's per-command RpcResponse union carries each command's data type;
# here the response envelope keeps `data` as its JSON value, and each RpcClient
# method decodes it with the typed decoder of its command.

def Decoded(-A: Data) -> Data: Result<&2,&2,Decode.Error,A>

# Commands (stdin)
# ----------------
# upstream RpcCommand without its correlation id, which the sender adds.
type RpcCommand is Data:
  RpcPrompt{message: String,images: Maybe<&2,List<&2,Ai.ImageContent>>,streamingBehavior: Maybe<&2,Session.StreamingBehavior>}
  RpcSteer{message: String,images: Maybe<&2,List<&2,Ai.ImageContent>>}
  RpcFollowUp{message: String,images: Maybe<&2,List<&2,Ai.ImageContent>>}
  RpcAbort{}
  RpcClearQueue{}
  RpcNewSession{parentSession: Maybe<&2,String>}
  RpcGetState{}
  RpcSetModel{provider: String,modelId: String}
  RpcCycleModel{}
  RpcGetAvailableModels{}
  RpcSetThinkingLevel{level: Ai.ModelThinkingLevel}
  RpcCycleThinkingLevel{}
  RpcGetAvailableThinkingLevels{}
  RpcSetSteeringMode{mode: AgentTypes.QueueMode}
  RpcSetFollowUpMode{mode: AgentTypes.QueueMode}
  RpcCompact{customInstructions: Maybe<&2,String>}
  RpcSetAutoCompaction{enabled: Bool}
  RpcSetAutoRetry{enabled: Bool}
  RpcAbortRetry{}
  RpcBash{command: String,excludeFromContext: Maybe<&2,Bool>}
  RpcAbortBash{}
  RpcGetSessionStats{}
  RpcExportHtml{outputPath: Maybe<&2,String>}
  RpcSwitchSession{sessionPath: String}
  RpcFork{entryId: String}
  RpcClone{}
  RpcGetForkMessages{}
  RpcGetEntries{since: Maybe<&2,String>}
  RpcGetTree{}
  RpcGetLastAssistantText{}
  RpcSetSessionName{name: String}
  RpcGetMessages{}
  RpcGetCommands{}

# upstream RpcCommandType
def commandType(command: RpcCommand) -> String:
  match command:
    case RpcPrompt{_,_,_}: "prompt"
    case RpcSteer{_,_}: "steer"
    case RpcFollowUp{_,_}: "follow_up"
    case RpcAbort{}: "abort"
    case RpcClearQueue{}: "clear_queue"
    case RpcNewSession{_}: "new_session"
    case RpcGetState{}: "get_state"
    case RpcSetModel{_,_}: "set_model"
    case RpcCycleModel{}: "cycle_model"
    case RpcGetAvailableModels{}: "get_available_models"
    case RpcSetThinkingLevel{_}: "set_thinking_level"
    case RpcCycleThinkingLevel{}: "cycle_thinking_level"
    case RpcGetAvailableThinkingLevels{}: "get_available_thinking_levels"
    case RpcSetSteeringMode{_}: "set_steering_mode"
    case RpcSetFollowUpMode{_}: "set_follow_up_mode"
    case RpcCompact{_}: "compact"
    case RpcSetAutoCompaction{_}: "set_auto_compaction"
    case RpcSetAutoRetry{_}: "set_auto_retry"
    case RpcAbortRetry{}: "abort_retry"
    case RpcBash{_,_}: "bash"
    case RpcAbortBash{}: "abort_bash"
    case RpcGetSessionStats{}: "get_session_stats"
    case RpcExportHtml{_}: "export_html"
    case RpcSwitchSession{_}: "switch_session"
    case RpcFork{_}: "fork"
    case RpcClone{}: "clone"
    case RpcGetForkMessages{}: "get_fork_messages"
    case RpcGetEntries{_}: "get_entries"
    case RpcGetTree{}: "get_tree"
    case RpcGetLastAssistantText{}: "get_last_assistant_text"
    case RpcSetSessionName{_}: "set_session_name"
    case RpcGetMessages{}: "get_messages"
    case RpcGetCommands{}: "get_commands"

def queueModeName(value: AgentTypes.QueueMode) -> String:
  match value:
    case AgentTypes.All{}: "all"
    case AgentTypes.OneAtATime{}: "one-at-a-time"
def behaviorName(value: Session.StreamingBehavior) -> String:
  match value:
    case Session.Steer{}: "steer"
    case Session.FollowUp{}: "followUp"
def imageValues(images: List<&2,Ai.ImageContent>) -> List<&2,V.Value>:
  match images:
    case Nil{}: Nil{}
    case image <> rest: Json.imageContent(image) <> imageValues(rest)
def optionalImages(images: Maybe<&2,List<&2,Ai.ImageContent>>,rest: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<V.Value>>:
  Json.optional("images",Maybe.map(&2,List<&2,Ai.ImageContent>,V.Value,values => V.ArrayValue{imageValues(values)},images),rest)
def commandFields(command: RpcCommand,rest: List<&2,R.Property<V.Value>>) -> List<&2,R.Property<V.Value>>:
  match command:
    case RpcPrompt{message,images,behavior}: Json.field("message",V.Text{message},optionalImages(images,Json.optionalText("streamingBehavior",Maybe.map(&2,Session.StreamingBehavior,String,behaviorName,behavior),rest)))
    case RpcSteer{message,images}: Json.field("message",V.Text{message},optionalImages(images,rest))
    case RpcFollowUp{message,images}: Json.field("message",V.Text{message},optionalImages(images,rest))
    case RpcNewSession{parentSession}: Json.optionalText("parentSession",parentSession,rest)
    case RpcSetModel{provider,modelId}: Json.field("provider",V.Text{provider},Json.field("modelId",V.Text{modelId},rest))
    case RpcSetThinkingLevel{level}: Json.field("level",V.Text{Levels.name(level)},rest)
    case RpcSetSteeringMode{mode}: Json.field("mode",V.Text{queueModeName(mode)},rest)
    case RpcSetFollowUpMode{mode}: Json.field("mode",V.Text{queueModeName(mode)},rest)
    case RpcCompact{instructions}: Json.optionalText("customInstructions",instructions,rest)
    case RpcSetAutoCompaction{enabled}: Json.field("enabled",V.Boolean{enabled},rest)
    case RpcSetAutoRetry{enabled}: Json.field("enabled",V.Boolean{enabled},rest)
    case RpcBash{command,exclude}: Json.field("command",V.Text{command},Json.optionalBoolean("excludeFromContext",exclude,rest))
    case RpcExportHtml{path}: Json.optionalText("outputPath",path,rest)
    case RpcSwitchSession{path}: Json.field("sessionPath",V.Text{path},rest)
    case RpcFork{entryId}: Json.field("entryId",V.Text{entryId},rest)
    case RpcGetEntries{since}: Json.optionalText("since",since,rest)
    case RpcSetSessionName{name}: Json.field("name",V.Text{name},rest)
    case _: rest

# upstream `{ ...command, id }`: the command's members, then the request id.
def commandValue(+command: RpcCommand,id: Maybe<&2,String>) -> V.Value:
  Json.object(Json.field("type",V.Text{commandType(command)},commandFields(command,Json.optionalText("id",id,Nil{}))))

# Responses (stdout)
# ------------------
type RpcOutcome is Data:
  RpcSuccess{data: Maybe<&2,V.Value>}
  RpcFailure{error: String}
type RpcResponse is Data:
  RpcResponse{id: Maybe<&2,String>,command: String,outcome: RpcOutcome}

def responseValue(response: RpcResponse) -> V.Value:
  match response:
    case RpcResponse{id,command,RpcSuccess{data}}: Json.object(Json.optionalText("id",id,Json.field("type",V.Text{"response"},Json.field("command",V.Text{command},Json.field("success",V.Boolean{True{}},Json.optional("data",data,Nil{}))))))
    case RpcResponse{id,command,RpcFailure{error}}: Json.object(Json.optionalText("id",id,Json.field("type",V.Text{"response"},Json.field("command",V.Text{command},Json.field("success",V.Boolean{False{}},Json.field("error",V.Text{error},Nil{}))))))

def decodeBoolean(value: V.Value) -> Decoded(Bool):
  match value:
    case V.Boolean{flag}: Done{flag}
    case _: Fail{Decode.WrongType{Nil{},"boolean"}}
def outcomeOf(success: Bool,+fields: R.Record<V.Value>) -> Decoded(RpcOutcome):
  match success:
    case True{}: Done{RpcSuccess{R.get(V.Value,fields,"data")}}
    case False{}: Result.map(&2,&2,Decode.Error,String,RpcOutcome,error => RpcFailure{error},Decode.required(String,fields,"error",Decode.string))
def responseFields(+fields: R.Record<V.Value>) -> Decoded(RpcResponse):
  do Result<&2,&2,Decode.Error,RpcResponse>:
    id : Maybe<&2,String> <- Decode.optional(String,fields,"id",Decode.string)
    command : String <- Decode.required(String,fields,"command",Decode.string)
    success : Bool <- Decode.required(Bool,fields,"success",decodeBoolean)
    outcome : RpcOutcome <- outcomeOf(success,fields)
    return RpcResponse{id,command,outcome}
def decodeResponse(value: V.Value) -> Decoded(RpcResponse):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,RpcResponse,Decode.object(value),fields => responseFields(fields))

# Session state
# -------------
type RpcSessionState is Data:
  RpcSessionState{model: Maybe<&2,Ai.Model<Ai.JsonValue>>,thinkingLevel: Ai.ModelThinkingLevel,isStreaming: Bool,isCompacting: Bool,steeringMode: AgentTypes.QueueMode,followUpMode: AgentTypes.QueueMode,sessionFile: Maybe<&2,String>,sessionId: String,sessionName: Maybe<&2,String>,autoCompactionEnabled: Bool,messageCount: Nat,pendingMessageCount: Nat}

def sessionStateValue(state: RpcSessionState) -> V.Value:
  match state:
    case RpcSessionState{model,level,streaming,compacting,steering,followUp,file,id,name,auto,messages,pending}:
      Json.object(Json.optional("model",Maybe.map(&2,Ai.Model<Ai.JsonValue>,V.Value,ModelJson.model,model),Json.field("thinkingLevel",V.Text{Levels.name(level)},Json.field("isStreaming",V.Boolean{streaming},Json.field("isCompacting",V.Boolean{compacting},Json.field("steeringMode",V.Text{queueModeName(steering)},Json.field("followUpMode",V.Text{queueModeName(followUp)},Json.optionalText("sessionFile",file,Json.field("sessionId",V.Text{id},Json.optionalText("sessionName",name,Json.field("autoCompactionEnabled",V.Boolean{auto},Json.field("messageCount",Json.natural(messages),Json.field("pendingMessageCount",Json.natural(pending),Nil{})))))))))))))

def known(-A: Data,expected: String,value: Maybe<&2,A>) -> Decoded(A):
  match value:
    case Some{found}: Done{found}
    case None{}: Fail{Decode.InvalidValue{Nil{},expected}}
def decodeThinkingLevel(value: V.Value) -> Decoded(Ai.ModelThinkingLevel):
  Result.bind(&2,&2,Decode.Error,String,Ai.ModelThinkingLevel,Decode.string(value),name => known(Ai.ModelThinkingLevel,"thinking level",Levels.fromName(name)))
def queueMode(value: String) -> Maybe<&2,AgentTypes.QueueMode>:
  match value:
    case "all": Some{AgentTypes.All{}}
    case "one-at-a-time": Some{AgentTypes.OneAtATime{}}
    case _: None{}
def decodeQueueMode(value: V.Value) -> Decoded(AgentTypes.QueueMode):
  Result.bind(&2,&2,Decode.Error,String,AgentTypes.QueueMode,Decode.string(value),name => known(AgentTypes.QueueMode,"'all' or 'one-at-a-time'",queueMode(name)))
def decodeNatural(value: V.Value) -> Decoded(Nat): SessionJson.decodeNatural(value)

# A model as ModelJson.model renders it. Optional members are read with the
# models.json readers and compat with the typed compat of the model's api.
def modelFields(+fields: R.Record<V.Value>) -> Decoded(Ai.Model<Ai.JsonValue>):
  do Result<&2,&2,Decode.Error,Ai.Model<Ai.JsonValue>>:
    id : String <- Decode.required(String,fields,"id",Decode.string)
    name : String <- Decode.required(String,fields,"name",Decode.string)
    +api : Ai.ModelApi <- Result.map(&2,&2,Decode.Error,String,Ai.ModelApi,name => Api.fromString(name),Decode.required(String,fields,"api",Decode.string))
    provider : String <- Decode.required(String,fields,"provider",Decode.string)
    baseUrl : String <- Decode.required(String,fields,"baseUrl",Decode.string)
    reasoning : Bool <- Decode.required(Bool,fields,"reasoning",decodeBoolean)
    input : List<&2,Ai.ModelInput> <- Decode.located(List<&2,Ai.ModelInput>,known(List<&2,Ai.ModelInput>,"model inputs",Config.inputsOf(R.get(V.Value,fields,"input"))),Decode.Field{"input"})
    cost : Ai.ModelCost <- Decode.located(Ai.ModelCost,known(Ai.ModelCost,"model cost",Config.costOf(R.get(V.Value,fields,"cost"))),Decode.Field{"cost"})
    contextWindow : F64 <- Decode.required(F64,fields,"contextWindow",Decode.number)
    maxTokens : F64 <- Decode.required(F64,fields,"maxTokens",Decode.number)
    return Ai.Model{id,name,api,provider,baseUrl,reasoning,Config.thinkingLevelMapOf(R.get(V.Value,fields,"thinkingLevelMap")),input,Config.inputLimitsOf(R.get(V.Value,fields,"inputLimits")),cost,Config.promptCacheOf(R.get(V.Value,fields,"promptCache")),contextWindow,maxTokens,Config.samplingOf(R.get(V.Value,fields,"samplingParams")),Config.headersOf(R.get(V.Value,fields,"headers")),Composer.compatFor(api,R.get(V.Value,fields,"compat"))}
def decodeModel(value: V.Value) -> Decoded(Ai.Model<Ai.JsonValue>):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,Ai.Model<Ai.JsonValue>,Decode.object(value),fields => modelFields(fields))

def sessionStateFields(+fields: R.Record<V.Value>) -> Decoded(RpcSessionState):
  do Result<&2,&2,Decode.Error,RpcSessionState>:
    model : Maybe<&2,Ai.Model<Ai.JsonValue>> <- Decode.optional(Ai.Model<Ai.JsonValue>,fields,"model",decodeModel)
    level : Ai.ModelThinkingLevel <- Decode.required(Ai.ModelThinkingLevel,fields,"thinkingLevel",decodeThinkingLevel)
    streaming : Bool <- Decode.required(Bool,fields,"isStreaming",decodeBoolean)
    compacting : Bool <- Decode.required(Bool,fields,"isCompacting",decodeBoolean)
    steering : AgentTypes.QueueMode <- Decode.required(AgentTypes.QueueMode,fields,"steeringMode",decodeQueueMode)
    followUp : AgentTypes.QueueMode <- Decode.required(AgentTypes.QueueMode,fields,"followUpMode",decodeQueueMode)
    file : Maybe<&2,String> <- Decode.optional(String,fields,"sessionFile",Decode.string)
    id : String <- Decode.required(String,fields,"sessionId",Decode.string)
    name : Maybe<&2,String> <- Decode.optional(String,fields,"sessionName",Decode.string)
    auto : Bool <- Decode.required(Bool,fields,"autoCompactionEnabled",decodeBoolean)
    messages : Nat <- Decode.required(Nat,fields,"messageCount",decodeNatural)
    pending : Nat <- Decode.required(Nat,fields,"pendingMessageCount",decodeNatural)
    return RpcSessionState{model,level,streaming,compacting,steering,followUp,file,id,name,auto,messages,pending}
def decodeSessionState(value: V.Value) -> Decoded(RpcSessionState):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,RpcSessionState,Decode.object(value),fields => sessionStateFields(fields))

# Slash commands (get_commands)
# -----------------------------
type RpcSlashCommandSource is Data:
  ExtensionCommand{}
  PromptCommand{}
  SkillCommand{}
type RpcSlashCommand is Data:
  RpcSlashCommand{name: String,description: Maybe<&2,String>,source: RpcSlashCommandSource,sourceInfo: Skills.SourceInfo}

def sourceName(source: RpcSlashCommandSource) -> String:
  match source:
    case ExtensionCommand{}: "extension"
    case PromptCommand{}: "prompt"
    case SkillCommand{}: "skill"
def scopeName(scope: Skills.SourceScope) -> String:
  match scope:
    case Skills.User{}: "user"
    case Skills.Project{}: "project"
    case Skills.Temporary{}: "temporary"
def originName(origin: Skills.SourceOrigin) -> String:
  match origin:
    case Skills.Package{}: "package"
    case Skills.TopLevel{}: "top-level"
def sourceInfoValue(info: Skills.SourceInfo) -> V.Value:
  match info:
    case Skills.SourceInfo{path,source,scope,origin,baseDir}:
      Json.object(Json.field("path",V.Text{path},Json.field("source",V.Text{source},Json.field("scope",V.Text{scopeName(scope)},Json.field("origin",V.Text{originName(origin)},Json.optionalText("baseDir",baseDir,Nil{}))))))
def slashCommandValue(command: RpcSlashCommand) -> V.Value:
  match command:
    case RpcSlashCommand{name,description,source,info}:
      Json.object(Json.field("name",V.Text{name},Json.optionalText("description",description,Json.field("source",V.Text{sourceName(source)},Json.field("sourceInfo",sourceInfoValue(info),Nil{})))))

def sourceOf(name: String) -> Maybe<&2,RpcSlashCommandSource>:
  match name:
    case "extension": Some{ExtensionCommand{}}
    case "prompt": Some{PromptCommand{}}
    case "skill": Some{SkillCommand{}}
    case _: None{}
def scopeOf(name: String) -> Maybe<&2,Skills.SourceScope>:
  match name:
    case "user": Some{Skills.User{}}
    case "project": Some{Skills.Project{}}
    case "temporary": Some{Skills.Temporary{}}
    case _: None{}
def originOf(name: String) -> Maybe<&2,Skills.SourceOrigin>:
  match name:
    case "package": Some{Skills.Package{}}
    case "top-level": Some{Skills.TopLevel{}}
    case _: None{}
def decodeNamed(-A: Data,expected: String,read: String -> Maybe<&2,A>,value: V.Value) -> Decoded(A):
  Result.bind(&2,&2,Decode.Error,String,A,Decode.string(value),name => known(A,expected,read(name)))
def sourceInfoFields(+fields: R.Record<V.Value>) -> Decoded(Skills.SourceInfo):
  do Result<&2,&2,Decode.Error,Skills.SourceInfo>:
    path : String <- Decode.required(String,fields,"path",Decode.string)
    source : String <- Decode.required(String,fields,"source",Decode.string)
    scope : Skills.SourceScope <- Decode.required(Skills.SourceScope,fields,"scope",value => decodeNamed(Skills.SourceScope,"source scope",scopeOf,value))
    origin : Skills.SourceOrigin <- Decode.required(Skills.SourceOrigin,fields,"origin",value => decodeNamed(Skills.SourceOrigin,"source origin",originOf,value))
    baseDir : Maybe<&2,String> <- Decode.optional(String,fields,"baseDir",Decode.string)
    return Skills.SourceInfo{path,source,scope,origin,baseDir}
def decodeSourceInfo(value: V.Value) -> Decoded(Skills.SourceInfo):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,Skills.SourceInfo,Decode.object(value),fields => sourceInfoFields(fields))
def slashCommandFields(+fields: R.Record<V.Value>) -> Decoded(RpcSlashCommand):
  do Result<&2,&2,Decode.Error,RpcSlashCommand>:
    name : String <- Decode.required(String,fields,"name",Decode.string)
    description : Maybe<&2,String> <- Decode.optional(String,fields,"description",Decode.string)
    source : RpcSlashCommandSource <- Decode.required(RpcSlashCommandSource,fields,"source",value => decodeNamed(RpcSlashCommandSource,"command source",sourceOf,value))
    info : Skills.SourceInfo <- Decode.required(Skills.SourceInfo,fields,"sourceInfo",decodeSourceInfo)
    return RpcSlashCommand{name,description,source,info}
def decodeSlashCommand(value: V.Value) -> Decoded(RpcSlashCommand):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,RpcSlashCommand,Decode.object(value),fields => slashCommandFields(fields))

# Other response data
# -------------------
# BashResult (bash): `output` on the wire.
def bashResultValue(result: Bash.BashResult) -> V.Value:
  match result:
    case Bash.BashResult{output,exitCode,cancelled,truncated,fullOutputPath}:
      Json.object(Json.field("output",V.Text{output},Json.optional("exitCode",Maybe.map(&2,U32,V.Value,code => Json.natural(U32.to_nat(code)),exitCode),Json.field("cancelled",V.Boolean{cancelled},Json.field("truncated",V.Boolean{truncated},Json.optionalText("fullOutputPath",fullOutputPath,Nil{}))))))
def bashResultFields(+fields: R.Record<V.Value>) -> Decoded(Bash.BashResult):
  do Result<&2,&2,Decode.Error,Bash.BashResult>:
    output : String <- Decode.required(String,fields,"output",Decode.string)
    exitCode : Maybe<&2,U32> <- Decode.optional(U32,fields,"exitCode",SessionJson.exitCodeOf)
    cancelled : Bool <- Decode.required(Bool,fields,"cancelled",decodeBoolean)
    truncated : Bool <- Decode.required(Bool,fields,"truncated",decodeBoolean)
    fullOutputPath : Maybe<&2,String> <- Decode.optional(String,fields,"fullOutputPath",Decode.string)
    return Bash.BashResult{output,exitCode,cancelled,truncated,fullOutputPath}
def decodeBashResult(value: V.Value) -> Decoded(Bash.BashResult):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,Bash.BashResult,Decode.object(value),fields => bashResultFields(fields))

# clear_queue: the removed queued texts (upstream session.clearQueue()).
def texts(values: List<&2,String>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: V.Text{value} <> texts(rest)
def clearedQueueValue(value: Session.QueuedMessages) -> V.Value:
  match value:
    case Session.QueuedMessages{steering,followUp}: Json.object(Json.field("steering",V.ArrayValue{texts(steering)},Json.field("followUp",V.ArrayValue{texts(followUp)},Nil{})))
def clearedQueueFields(+fields: R.Record<V.Value>) -> Decoded(Session.QueuedMessages):
  do Result<&2,&2,Decode.Error,Session.QueuedMessages>:
    steering : List<&2,String> <- Decode.required(List<&2,String>,fields,"steering",value => Decode.list(~String,~Decode.string,value))
    followUp : List<&2,String> <- Decode.required(List<&2,String>,fields,"followUp",value => Decode.list(~String,~Decode.string,value))
    return Session.QueuedMessages{steering,followUp}
def decodeClearedQueue(value: V.Value) -> Decoded(Session.QueuedMessages):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,Session.QueuedMessages,Decode.object(value),fields => clearedQueueFields(fields))

# Session entries and the entry tree, with the session's detail types.
def entryValue(entry: Session.Entry()) -> V.Value:
  SessionJson.entry(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,entry)
def entryFields(+fields: R.Record<V.Value>) -> Decoded(Session.Entry()):
  do Result<&2,&2,Decode.Error,Session.Entry()>:
    kind : String <- Decode.required(String,fields,"type",Decode.string)
    SessionJson.entryOf(~Unit,~Tools.ToolDetails,~V.Value,~Session.readUnit,~Session.readDetails,~Session.readRaw,kind,fields)
def decodeEntry(value: V.Value) -> Decoded(Session.Entry()):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,Session.Entry(),Decode.object(value),fields => entryFields(fields))

def TreeNode() -> Data: S.SessionTreeNode<Unit,Tools.ToolDetails,V.Value>
# The nested tree is rendered with an explicit work stack, so deep chains do
# not recurse through the JSON builder.
type TreeTask is Data:
  RenderNode{value: TreeNode()}
  RenderNodes{values: List<&2,TreeNode()>,built: List<&2,V.Value>}
  AppendNode{remaining: List<&2,TreeNode()>,built: List<&2,V.Value>}
  CompleteNode{entry: V.Value,label: Maybe<&2,String>,labelTimestamp: Maybe<&2,String>}
@unsafe def renderTree(tasks: List<&2,TreeTask>,completed: V.Value) -> V.Value:
  match tasks:
    case Nil{}: completed
    case RenderNode{S.SessionTreeNode{entry,children,label,labelTimestamp}} <> rest:
      renderTree(RenderNodes{children,Nil{}} <> CompleteNode{entryValue(entry),label,labelTimestamp} <> rest,completed)
    case RenderNodes{Nil{},built} <> rest:
      renderTree(rest,V.ArrayValue{List.reverse(&2,V.Value,built)})
    case RenderNodes{head <> tail,built} <> rest:
      renderTree(RenderNode{head} <> AppendNode{tail,built} <> rest,completed)
    case AppendNode{remaining,built} <> rest:
      renderTree(RenderNodes{remaining,completed <> built} <> rest,V.Null{})
    case CompleteNode{entry,label,labelTimestamp} <> rest:
      renderTree(rest,Json.object(Json.field("entry",entry,Json.field("children",completed,Json.optionalText("label",label,Json.optionalText("labelTimestamp",labelTimestamp,Nil{}))))))
def treeValue(tree: List<&2,TreeNode()>) -> V.Value:
  renderTree(RenderNodes{tree,Nil{}} <> Nil{},V.Null{})

# One node's children are decoded before the node, then its siblings.
def treeNodeFields(+fields: R.Record<V.Value>,children: List<&2,TreeNode()>) -> Decoded(TreeNode()):
  do Result<&2,&2,Decode.Error,TreeNode()>:
    entry : Session.Entry() <- Decode.required(Session.Entry(),fields,"entry",decodeEntry)
    label : Maybe<&2,String> <- Decode.optional(String,fields,"label",Decode.string)
    labelTimestamp : Maybe<&2,String> <- Decode.optional(String,fields,"labelTimestamp",Decode.string)
    return S.SessionTreeNode{entry,children,label,labelTimestamp}
@unsafe def decodeNodes(values: List<&2,V.Value>,+index: Nat) -> Decoded(List<&2,TreeNode()>):
  match values:
    case Nil{}: Done{Nil{}}
    case value <> rest:
      do Result<&2,&2,Decode.Error,List<&2,TreeNode()>>:
        +fields : R.Record<V.Value> <- Decode.located(R.Record<V.Value>,Decode.object(value),Decode.Index{index})
        nested : List<&2,V.Value> <- Decode.located(List<&2,V.Value>,Decode.required(List<&2,V.Value>,fields,"children",Decode.array),Decode.Index{index})
        children : List<&2,TreeNode()> <- Decode.located(List<&2,TreeNode()>,Decode.located(List<&2,TreeNode()>,decodeNodes(nested,0n),Decode.Field{"children"}),Decode.Index{index})
        node : TreeNode() <- Decode.located(TreeNode(),treeNodeFields(fields,children),Decode.Index{index})
        others : List<&2,TreeNode()> <- decodeNodes(rest,index + 1n)
        return node <> others
def decodeTree(value: V.Value) -> Decoded(List<&2,TreeNode()>):
  Result.bind(&2,&2,Decode.Error,List<&2,V.Value>,List<&2,TreeNode()>,Decode.array(value),values => decodeNodes(values,0n))

# Extension UI (stdout requests, stdin responses)
# -----------------------------------------------
# upstream RpcExtensionUIRequest: dialogs wait for a response with their id;
# the other methods are fire and forget.
type RpcExtensionUIRequest is Data:
  UISelect{id: String,title: String,options: List<&2,String>,timeout: Maybe<&2,F64>}
  UIConfirm{id: String,title: String,message: String,timeout: Maybe<&2,F64>}
  UIInput{id: String,title: String,placeholder: Maybe<&2,String>,timeout: Maybe<&2,F64>}
  UIEditor{id: String,title: String,prefill: Maybe<&2,String>}
  UINotify{id: String,message: String,notifyType: Maybe<&2,String>}
  UISetStatus{id: String,statusKey: String,statusText: Maybe<&2,String>}
  UISetWidget{id: String,widgetKey: String,widgetLines: Maybe<&2,List<&2,String>>,widgetPlacement: Maybe<&2,String>}
  UISetTitle{id: String,title: String}
  UISetEditorText{id: String,text: String}

def uiRequest(id: String,method: String,rest: List<&2,R.Property<V.Value>>) -> V.Value:
  Json.object(Json.field("type",V.Text{"extension_ui_request"},Json.field("id",V.Text{id},Json.field("method",V.Text{method},rest))))
def uiRequestValue(request: RpcExtensionUIRequest) -> V.Value:
  match request:
    case UISelect{id,title,options,timeout}: uiRequest(id,"select",Json.field("title",V.Text{title},Json.field("options",V.ArrayValue{texts(options)},Json.optionalNumber("timeout",timeout,Nil{}))))
    case UIConfirm{id,title,message,timeout}: uiRequest(id,"confirm",Json.field("title",V.Text{title},Json.field("message",V.Text{message},Json.optionalNumber("timeout",timeout,Nil{}))))
    case UIInput{id,title,placeholder,timeout}: uiRequest(id,"input",Json.field("title",V.Text{title},Json.optionalText("placeholder",placeholder,Json.optionalNumber("timeout",timeout,Nil{}))))
    case UIEditor{id,title,prefill}: uiRequest(id,"editor",Json.field("title",V.Text{title},Json.optionalText("prefill",prefill,Nil{})))
    case UINotify{id,message,kind}: uiRequest(id,"notify",Json.field("message",V.Text{message},Json.optionalText("notifyType",kind,Nil{})))
    case UISetStatus{id,key,text}: uiRequest(id,"setStatus",Json.field("statusKey",V.Text{key},Json.optionalText("statusText",text,Nil{})))
    case UISetWidget{id,key,lines,placement}: uiRequest(id,"setWidget",Json.field("widgetKey",V.Text{key},Json.optional("widgetLines",Maybe.map(&2,List<&2,String>,V.Value,values => V.ArrayValue{texts(values)},lines),Json.optionalText("widgetPlacement",placement,Nil{}))))
    case UISetTitle{id,title}: uiRequest(id,"setTitle",Json.field("title",V.Text{title},Nil{}))
    case UISetEditorText{id,text}: uiRequest(id,"set_editor_text",Json.field("text",V.Text{text},Nil{}))

# upstream RpcExtensionUIResponse
type RpcExtensionUIResponse is Data:
  UIValue{id: String,value: String}
  UIConfirmed{id: String,confirmed: Bool}
  UICancelled{id: String}

def uiResponseId(response: RpcExtensionUIResponse) -> String:
  match response:
    case UIValue{id,_}: id
    case UIConfirmed{id,_}: id
    case UICancelled{id}: id
# A response carries `cancelled: true`, a `value` or `confirmed`, tried in
# that order as upstream's dialogs test them.
def uiResponseOf(id: String,cancelled: Maybe<&2,Bool>,value: Maybe<&2,String>,confirmed: Maybe<&2,Bool>) -> Decoded(RpcExtensionUIResponse):
  match cancelled value confirmed:
    case Some{True{}} _ _: Done{UICancelled{id}}
    case _ Some{text} _: Done{UIValue{id,text}}
    case _ None{} Some{flag}: Done{UIConfirmed{id,flag}}
    case _ None{} None{}: Fail{Decode.InvalidValue{Nil{},"extension UI response"}}
def uiResponseFields(+fields: R.Record<V.Value>) -> Decoded(RpcExtensionUIResponse):
  do Result<&2,&2,Decode.Error,RpcExtensionUIResponse>:
    id : String <- Decode.required(String,fields,"id",Decode.string)
    cancelled : Maybe<&2,Bool> <- Decode.optional(Bool,fields,"cancelled",decodeBoolean)
    value : Maybe<&2,String> <- Decode.optional(String,fields,"value",Decode.string)
    confirmed : Maybe<&2,Bool> <- Decode.optional(Bool,fields,"confirmed",decodeBoolean)
    uiResponseOf(id,cancelled,value,confirmed)
def decodeUIResponse(value: V.Value) -> Decoded(RpcExtensionUIResponse):
  Result.bind(&2,&2,Decode.Error,R.Record<V.Value>,RpcExtensionUIResponse,Decode.object(value),fields => uiResponseFields(fields))
