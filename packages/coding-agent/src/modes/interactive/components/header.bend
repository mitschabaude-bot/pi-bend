import Base
import ../../../../../runtime/src/callback.bend as Callback
import ../../../../../runtime/src/ref.bend as Ref
import ../../../../../runtime/src/posix-path.bend as Path
import ../../../../../runtime/src/string.bend as Strings
import ../../../../../tui/src/component.bend as Component
import ../../../../../tui/src/components/text.bend as Text
import ../../../core/system-prompt.bend as Prompt
import ../../../core/skills.bend as Skills
import ../../../config.bend as Config
import ../theme/theme.bend as Theme

# The built-in header belongs to the scrollable document, but survives a
# transcript replacement. Expansion and theme changes are read at render time.
# The loaded context files and skills; /reload replaces them.
type Loaded is Data: Loaded{contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>}
type Header is Data: Header{expanded: Ref.Ref<Bool>,theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,loaded: Ref.Ref<Loaded>,heading: Ref.Ref<Text.Text>,resources: Ref.Ref<Text.Text>}
type Owner is Type: Owner{expanded: Ref.Ref<Bool>,loaded: Ref.Ref<Loaded>,heading: Ref.Ref<Text.Text>,resources: Ref.Ref<Text.Text>,component: Component.Component,render: Callback.Callback<Nat,List<&2,String>>,invalidate: Callback.Callback<Unit,Unit>}
type Handle is Data: Handle{expanded: Ref.Ref<Bool>,loaded: Ref.Ref<Loaded>}

def colorResult(result: Result<&2,&2,Theme.Error,String>) -> IO(String):
  match result:
    case Done{painted}: IO.pure(String,painted)
    case Fail{_}: IO.die(String,1,"invalid header theme color")
def colored(theme: Theme.Theme,key: String,text: String) -> IO(String):
  colorResult(Theme.foreground(theme,key,text))
def logo(+theme: Theme.Theme) -> IO(String):
  do IO<String>:
    name : String <- colored(theme,"accent","pi")
    version : String <- colored(theme,"dim"," v" ++ Config.version())
    return "\u{1b}[1m" ++ name ++ "\u{1b}[22m" ++ version
def compact(+theme: Theme.Theme,brand: String) -> IO(String):
  do IO<String>:
    hints : String <- colored(theme,"muted","escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more")
    more : String <- colored(theme,"dim","Press ctrl+o to show full startup help and loaded resources.")
    onboarding : String <- colored(theme,"dim","Pi can explain its own features and look up its docs. Ask it how to use or extend Pi.")
    return brand ++ "\n" ++ hints ++ "\n" ++ more ++ "\n\n" ++ onboarding
def expanded(+theme: Theme.Theme,brand: String) -> IO(String):
  do IO<String>:
    hints : String <- colored(theme,"muted","escape to interrupt\nctrl+c to clear\nctrl+c twice to exit\nctrl+d to exit (empty)\nctrl+z to suspend\nctrl+k to delete to end\nshift+tab to cycle thinking level\nctrl+p/shift+ctrl+p to cycle models\nctrl+l to select model\nctrl+o to expand tools\nctrl+t to expand thinking\nctrl+g for external editor\n/ for commands\n! to run bash\n!! to run bash (no context)\nalt+enter to queue follow-up\nalt+up to edit all queued messages\nctrl+v to paste image (with text fallback)\ndrop files to attach")
    onboarding : String <- colored(theme,"dim","Pi can explain its own features and look up its docs. Ask it how to use or extend Pi.")
    return brand ++ "\n" ++ hints ++ "\n\n" ++ onboarding

def inside(base: String,path: String) -> Maybe<&2,String>:
  +relative = Path.relative(base,path)
  Bool.pick(Maybe<&2,String>,Strings.equal(relative,"..") || String.starts_with(relative,"../") || Path.isAbsolute(relative),None{},Some{relative})
def displayFound(found: Maybe<&2,String>,path: String) -> String:
  match found:
    case None{}: path
    case Some{""}: "~"
    case Some{relative}: "~/" ++ relative
def displayPath(+path: String,home: Maybe<&2,String>) -> String:
  match home:
    case None{}: path
    case Some{root}: displayFound(inside(root,path),path)
def compactFound(found: Maybe<&2,String>,path: String,home: Maybe<&2,String>) -> String:
  match found:
    case Some{relative}: relative
    case None{}: displayPath(path,home)
def contextPath(+path: String,cwd: String,+home: Maybe<&2,String>,expanded: Bool) -> String:
  Bool.pick(Unit -> String,expanded,_ => displayPath(path,home),_ => compactFound(inside(cwd,path),path,home))(Unit{})
def contextPaths(files: List<&2,Prompt.ContextFile>,+cwd: String,+home: Maybe<&2,String>,+expanded: Bool,reversed: List<&2,String>) -> List<&2,String>:
  match files:
    case Nil{}: List.reverse(&2,String,reversed)
    case Prompt.ContextFile{path,_} <> rest: contextPaths(rest,cwd,home,expanded,("  " ++ contextPath(path,cwd,home,expanded)) <> reversed)
def contextSection(+theme: Theme.Theme,files: List<&2,Prompt.ContextFile>,cwd: String,home: Maybe<&2,String>,+expanded: Bool) -> IO(String):
  match files:
    case Nil{}: IO.pure(String,"")
    case _:
      do IO<String>:
        title : String <- colored(theme,"mdHeading","[Context]")
        body : String <- colored(theme,"dim",String.join(contextPaths(files,cwd,home,expanded,Nil{}),Bool.pick(String,expanded,"\n",", ")))
        return title ++ "\n" ++ body

def skillScope(skill: Skills.Skill) -> Nat:
  match skill:
    case Skills.Skill{_,_,_,_,Skills.SourceInfo{_,_,Skills.Project{},_,_},_}: 0n
    case Skills.Skill{_,_,_,_,Skills.SourceInfo{_,_,Skills.User{},_,_},_}: 1n
    case _: 2n
def inScope(skills: List<&2,Skills.Skill>,+wanted: Nat,+reversed: List<&2,Skills.Skill>) -> List<&2,Skills.Skill>:
  match skills:
    case Nil{}: List.reverse(&2,Skills.Skill,reversed)
    case +skill <> rest: inScope(rest,wanted,Bool.pick(List<&2,Skills.Skill>,Nat.is_eq(skillScope(skill),wanted),skill <> reversed,reversed))
def skillBefore(first: Skills.Skill,second: Skills.Skill) -> Bool:
  match first second:
    case Skills.Skill{_,_,path,_,_,_} Skills.Skill{_,_,other,_,_,_}: String.is_le(path,other)
def skillPaths(skills: List<&2,Skills.Skill>,+home: Maybe<&2,String>,reversed: List<&2,String>) -> List<&2,String>:
  match skills:
    case Nil{}: List.reverse(&2,String,reversed)
    case Skills.Skill{_,_,path,_,_,_} <> rest: skillPaths(rest,home,("    " ++ displayPath(path,home)) <> reversed)
def skillGroupSelected(selected: List<&2,Skills.Skill>,+theme: Theme.Theme,label: String,home: Maybe<&2,String>) -> IO(String):
  match selected:
    case Nil{}: IO.pure(String,"")
    case _:
      do IO<String>:
        title : String <- colored(theme,"accent","  " ++ label)
        paths : String <- colored(theme,"dim",String.join(skillPaths(List.sort(~Skills.Skill,~skillBefore,selected),home,Nil{}),"\n"))
        return title ++ "\n" ++ paths
def skillGroup(theme: Theme.Theme,skills: List<&2,Skills.Skill>,wanted: Nat,label: String,home: Maybe<&2,String>) -> IO(String):
  skillGroupSelected(inScope(skills,wanted,Nil{}),theme,label,home)
def skillNames(skills: List<&2,Skills.Skill>,reversed: List<&2,String>) -> List<&2,String>:
  match skills:
    case Nil{}: List.reverse(&2,String,reversed)
    case Skills.Skill{name,_,_,_,_,_} <> rest: skillNames(rest,name <> reversed)
def joined(+first: String,+second: String) -> String:
  Bool.pick(String,Strings.equal(first,""),second,Bool.pick(String,Strings.equal(second,""),first,first ++ "\n" ++ second))
def expandedSkills(+theme: Theme.Theme,+skills: List<&2,Skills.Skill>,+home: Maybe<&2,String>) -> IO(String):
  do IO<String>:
    project : String <- skillGroup(theme,skills,0n,"project",home)
    user : String <- skillGroup(theme,skills,1n,"user",home)
    paths : String <- skillGroup(theme,skills,2n,"path",home)
    return joined(joined(project,user),paths)
def skillsSection(+theme: Theme.Theme,+skills: List<&2,Skills.Skill>,home: Maybe<&2,String>,expanded: Bool) -> IO(String):
  match skills:
    case Nil{}: IO.pure(String,"")
    case _:
      do IO<String>:
        title : String <- colored(theme,"mdHeading","[Skills]")
        body : String <- Bool.pick(Unit -> IO(String),expanded,_ => expandedSkills(theme,skills,home),_ => colored(theme,"dim","  " ++ String.join(List.sort(~String,~String.is_le,skillNames(skills,Nil{})),", ")))(Unit{})
        return title ++ "\n" ++ body
def resourceText(+theme: Theme.Theme,files: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>,cwd: String,+home: Maybe<&2,String>,+expanded: Bool) -> IO(String):
  do IO<String>:
    +context : String <- contextSection(theme,files,cwd,home,expanded)
    +skillsText : String <- skillsSection(theme,skills,home,expanded)
    return Bool.pick(String,Strings.equal(context,"") || Strings.equal(skillsText,""),context ++ skillsText,context ++ "\n\n" ++ skillsText)

def currentText(+old: Text.Text,+body: String) -> Text.Text:
  match old:
    case Text.Text{previous,_,_,_,_}: Bool.pick(Text.Text,Strings.equal(previous,body),old,Text.setText(old,body))
def stored(pair: Text.Text & List<&2,String>,cache: Ref.Ref<Text.Text>) -> IO(List<&2,String>):
  match pair:
    case (next,lines):
      do IO<List<&2,String>>:
        Ref.write(Text.Text,cache,next)
        return lines
def cached(+cache: Ref.Ref<Text.Text>,body: String,width: Nat) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    old : Text.Text <- Ref.read(Text.Text,cache)
    pair : Text.Text & List<&2,String> <- Text.render(currentText(old,body),width)
    stored(pair,cache)
def listedText(+theme: Theme.Theme,listed: Loaded,cwd: String,+home: Maybe<&2,String>,+expanded: Bool) -> IO(String):
  match listed:
    case Loaded{contexts,skills}: resourceText(theme,contexts,skills,cwd,home,expanded)
def draw(input: Header,width: Nat) -> IO(List<&2,String>):
  match input:
    case Header{state,theme,quiet,cwd,home,loaded,heading,resources}:
      match quiet:
        case True{}: IO.pure(List<&2,String>,Nil{})
        case False{}:
          do IO<List<&2,String>>:
            +size : Nat <- IO.pure(Nat,width)
            +isExpanded : Bool <- Ref.read(Bool,state)
            +current : Theme.Theme <- Ref.read(Theme.Theme,theme)
            listed : Loaded <- Ref.read(Loaded,loaded)
            +brand : String <- logo(current)
            body : String <- Bool.pick(Unit -> IO(String),isExpanded,_ => expanded(current,brand),_ => compact(current,brand))(Unit{})
            headerLines : List<&2,String> <- cached(heading,body,size)
            +details : String <- listedText(current,listed,cwd,home,isExpanded)
            resourceLines : List<&2,String> <- cached(resources,details,size)
            +present : Bool <- IO.pure(Bool,Bool.not(Strings.equal(details,"")))
            +before : List<&2,String> <- IO.pure(List<&2,String>,Bool.pick(List<&2,String>,present,"" <> "" <> Nil{},Nil{}))
            return "" <> List.append(&2,String,headerLines,List.append(&2,String,before,List.append(&2,String,resourceLines,[""])))
def ignore(_: Unit,_: Unit) -> IO(Unit): IO.pure(Unit,Unit{})
def create(theme: Ref.Ref<Theme.Theme>,quiet: Bool,cwd: String,home: Maybe<&2,String>,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>) -> IO(Owner):
  do IO<Owner>:
    +state : Ref.Ref<Bool> <- Ref.new(Bool,False{})
    +loaded : Ref.Ref<Loaded> <- Ref.new(Loaded,Loaded{contexts,skills})
    +heading : Ref.Ref<Text.Text> <- Ref.new(Text.Text,Text.new("",Some{1n},Some{0n},None{}))
    +resources : Ref.Ref<Text.Text> <- Ref.new(Text.Text,Text.new("",Some{0n},Some{0n},None{}))
    +render : Callback.Callback<Nat,List<&2,String>> <- Callback.create(~Header,~Nat,~List<&2,String>,~draw,Header{state,theme,quiet,cwd,home,loaded,heading,resources})
    +invalidate : Callback.Callback<Unit,Unit> <- Callback.create(~Unit,~Unit,~Unit,~ignore,Unit{})
    return Owner{state,loaded,heading,resources,Component.Component{Component.ComponentId{90n},render,None{},None{},invalidate,None{},False{}},render,invalidate}
def borrow(owner: Owner) -> Owner & Component.Component & Handle:
  match owner:
    case Owner{+state,+loaded,heading,resources,+component,render,invalidate}: (Owner{state,loaded,heading,resources,component,render,invalidate},component,Handle{state,loaded})
def toggle(handle: Handle) -> IO(Unit):
  match handle:
    case Handle{state,_}: Ref.modify(Bool,Unit,state,previous => (Bool.not(previous),Unit{}))
# upstream showLoadedResources after /reload: the listing shows the reloaded resources.
def setResources(handle: Handle,contexts: List<&2,Prompt.ContextFile>,skills: List<&2,Skills.Skill>) -> IO(Unit):
  match handle:
    case Handle{_,loaded}: Ref.write(Loaded,loaded,Loaded{contexts,skills})
def dispose(owner: Owner) -> IO(Unit):
  match owner:
    case Owner{state,loaded,heading,resources,_,render,invalidate}:
      do IO<Unit>:
        oldLoaded : Loaded <- Ref.dispose(Loaded,loaded)
        Callback.dispose(Nat,List<&2,String>,render)
        Callback.dispose(Unit,Unit,invalidate)
        previous : Bool <- Ref.dispose(Bool,state)
        oldHeading : Text.Text <- Ref.dispose(Text.Text,heading)
        oldResources : Text.Text <- Ref.dispose(Text.Text,resources)
        return Unit{}
