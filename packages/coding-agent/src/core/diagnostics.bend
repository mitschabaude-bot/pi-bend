import Base

type ResourceType is Data:
  Extension{}
  Skill{}
  Prompt{}
  Theme{}
type DiagnosticType is Data:
  Warning{}
  Error{}
  Collision{}
type ResourceCollision is Data:
  ResourceCollision{resourceType: ResourceType,name: String,winnerPath: String,loserPath: String,winnerSource: Maybe<&2,String>,loserSource: Maybe<&2,String>}
type ResourceDiagnostic is Data:
  ResourceDiagnostic{kind: DiagnosticType,message: String,path: Maybe<&2,String>,collision: Maybe<&2,ResourceCollision>}
def warning(message: String,path: String) -> ResourceDiagnostic:
  ResourceDiagnostic{Warning{},message,Some{path},None{}}
