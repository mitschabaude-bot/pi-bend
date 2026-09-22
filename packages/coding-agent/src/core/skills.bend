import Base

# Resource data shared by native skills and their callers. Discovery, frontmatter
# parsing and loading are separate work; prompt formatting performs no IO.
type SourceScope is Data:
  User{}
  Project{}
  Temporary{}
type SourceOrigin is Data:
  Package{}
  TopLevel{}
type SourceInfo is Data:
  SourceInfo{path: String,source: String,scope: SourceScope,origin: SourceOrigin,baseDir: Maybe<&2,String>}
type Skill is Data:
  Skill{name: String,description: String,filePath: String,baseDir: String,sourceInfo: SourceInfo,disableModelInvocation: Bool}
type FileReadTool is Data:
  Read{}
  Bash{}

def escapeXml(text: String,reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'&',rest}: escapeXml(rest,String.reverse.go("&amp;",reversed))
    case SCon{'<',rest}: escapeXml(rest,String.reverse.go("&lt;",reversed))
    case SCon{'>',rest}: escapeXml(rest,String.reverse.go("&gt;",reversed))
    case SCon{'"',rest}: escapeXml(rest,String.reverse.go("&quot;",reversed))
    case SCon{'\'',rest}: escapeXml(rest,String.reverse.go("&apos;",reversed))
    case SCon{char,rest}: escapeXml(rest,SCon{char,reversed})

def skillEntries(skills: List<&2,Skill>,reversed: List<&2,String>) -> List<&2,String>:
  match skills:
    case Nil{}: List.reverse(&2,String,reversed)
    case Skill{_,_,_,_,_,True{}} <> rest: skillEntries(rest,reversed)
    case Skill{name,description,filePath,_,_,False{}} <> rest:
      skillEntries(rest,("  <skill>\n    <name>" ++ escapeXml(name,"") ++ "</name>\n    <description>" ++ escapeXml(description,"") ++ "</description>\n    <location>" ++ escapeXml(filePath,"") ++ "</location>\n  </skill>") <> reversed)

def readInstruction(tool: FileReadTool) -> String:
  match tool:
    case Read{}: "Use the read tool to load a skill's file when the task matches its description."
    case Bash{}: "Use bash to load a skill's file when the task matches its description."

def formatted(entries: List<&2,String>,tool: FileReadTool) -> String:
  match entries:
    case Nil{}: ""
    case first <> rest:
      "\n\nThe following skills provide specialized instructions for specific tasks.\n" ++ readInstruction(tool) ++ "\nWhen a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n\n<available_skills>\n" ++ String.join(first <> rest,"\n") ++ "\n</available_skills>"

# Callers choose the read tool explicitly; the upstream default is Read{}.
def formatSkillsForPrompt(skills: List<&2,Skill>,fileReadTool: FileReadTool) -> String:
  formatted(skillEntries(skills,Nil{}),fileReadTool)
