import Base
import ../../../../ai/src/utils/message-json.bend as Json
import ../../../../ai/src/utils/uuid.bend as Uuid
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/record.bend as R
import ../../core/agent-session.bend as Session
import ../../core/session-export.bend as Export
import ../../core/session-json.bend as SessionJson
import ../../core/session-persistence.bend as Persistence
import ../../core/extensions/types.bend as Extensions
import ../../core/tools/index.bend as Tools

# Export-only presentation data for the pi session viewer. The original
# conversation entries and the live session are not modified.
def tool(value: Extensions.ToolInfo) -> V.Value:
  match value:
    case Extensions.ToolInfo{name,description,parameters}:
      Json.object([R.Property{"name",Json.text(name)},R.Property{"description",Json.text(description)},R.Property{"parameters",parameters}])

def tools(values: List<&2,Extensions.ToolInfo>) -> List<&2,V.Value>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: tool(value) <> tools(rest)

def createShareTrailingEntries(parent: Maybe<&2,String>,timestamp: String,id: String,systemPrompt: String,activeTools: List<&2,Extensions.ToolInfo>) -> List<&2,V.Value>:
  +data = Json.object([R.Property{"systemPrompt",Json.text(systemPrompt)},R.Property{"tools",V.ArrayValue{tools(activeTools)}}])
  [Json.object([R.Property{"type",Json.text("custom")},R.Property{"customType",Json.text("pi.share")},R.Property{"id",Json.text(String.take(id,8n))},R.Property{"parentId",SessionJson.nullableText(parent)},R.Property{"timestamp",Json.text(timestamp)},R.Property{"data",data}])]

def exported(+session: Session.AgentSession,cwd: String,path: String,timestamp: String,id: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    state : Session.AgentState() <- Session.state(session)
    prompt : String <- Session.systemPrompt(session)
    stored : Session.Session() <- Session.sessionOf(session)
    Export.exportSessionToJsonl(~Unit,~Tools.ToolDetails,~V.Value,~Session.unitValue,~Tools.detailsValue,~Session.rawValue,Session.stateOf(stored),cwd,path,timestamp,parent => time => createShareTrailingEntries(parent,time,id,prompt,Session.toolInfos(Session.stateTools(state))))

def withId(session: Session.AgentSession,cwd: String,path: String,time: Persistence.Outcome(String),id: Result<&2,&2,Uuid.Error,String>) -> IO(Result<&2,&2,String,String>):
  match time id:
    case Fail{error} _: IO.pure(Result<&2,&2,String,String>,Fail{Persistence.message(error)})
    case _ Fail{error}: IO.pure(Result<&2,&2,String,String>,Fail{Uuid.errorMessage(error)})
    case Done{timestamp} Done{value}: exported(session,cwd,path,timestamp,value)

def exportSessionForShare(session: Session.AgentSession,cwd: String,path: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    timestamp : Persistence.Outcome(String) <- Persistence.isoNow()
    id : Result<&2,&2,Uuid.Error,String> <- Uuid.randomUUID()
    withId(session,cwd,path,timestamp,id)
