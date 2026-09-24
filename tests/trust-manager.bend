import Base
import ../packages/coding-agent/src/core/trust-manager.bend as T
import ../packages/runtime/src/filesystem.bend as FS
import ../packages/runtime/src/utf8.bend as Utf8

# upstream trust-manager behaviour: nearest saved ancestor, null removes a key,
# sorted two-space JSON, trust-requiring project resources.
def check(ok: Bool,+name: String) -> IO(Unit):
  Bool.pick(Unit -> IO(Unit),ok,_ => IO.print("ok " ++ name),_ => IO.die(Unit,1,"FAIL " ++ name))(Unit{})
def decision(value: Result<&2,&2,T.Error,Maybe<&2,Bool>>) -> String:
  match value:
    case Done{Some{True{}}}: "true"
    case Done{Some{False{}}}: "false"
    case Done{None{}}: "none"
    case Fail{T.Error{message}}: "error: " ++ message
def text(read: Result<&2,&2,FS.Error,List<&2,U32>>) -> String:
  match read:
    case Done{bytes}: Utf8.decodeBuffer(bytes)
    case Fail{_}: "<missing>"
def labels(options: List<&2,T.ProjectTrustOption>) -> String:
  match options:
    case Nil{}: ""
    case T.ProjectTrustOption{label,_,_,_} <> rest: label ++ "|" ++ labels(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    +root : String <- IO.pure(String,"/tmp/pi-bend-trust-test")
    cleared : Result<&2,&2,FS.Error,Unit> <- FS.remove(root,True{},True{})
    made : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(root ++ "/work/project/sub")
    +store : T.ProjectTrustStore <- IO.pure(T.ProjectTrustStore,T.create(root ++ "/agent"))
    none : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(store,root ++ "/work/project")
    check(String.eq(decision(none),"none"),"no trust file: no decision")
    first : Result<&2,&2,T.Error,Unit> <- T.setMany(store,[T.ProjectTrustUpdate{root ++ "/work",Some{True{}}},T.ProjectTrustUpdate{root ++ "/work/project",Some{False{}}}])
    nested : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(store,root ++ "/work/project/sub")
    check(String.eq(decision(nested),"false"),"nearest saved ancestor decides")
    sibling : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(store,root ++ "/work/other")
    check(String.eq(decision(sibling),"true"),"parent decision applies to other children")
    file : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(root ++ "/agent/trust.json")
    check(String.eq(text(file),"{\n  \"" ++ root ++ "/work\": true,\n  \"" ++ root ++ "/work/project\": false\n}\n"),"sorted two-space JSON")
    second : Result<&2,&2,T.Error,Unit> <- T.set(store,root ++ "/work/project",None{})
    removed : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(store,root ++ "/work/project")
    check(String.eq(decision(removed),"true"),"null removes the key")
    options : List<&2,T.ProjectTrustOption> <- T.getProjectTrustOptions(root ++ "/work/project",True{})
    check(String.eq(labels(options),"Trust|Trust parent folder (" ++ root ++ "/work)|Trust (this session only)|Do not trust|Do not trust (this session only)|"),"prompt options")
    plain : Bool <- T.hasTrustRequiringProjectResources(root ++ "/work/project",None{})
    check(Bool.not(plain),"no project resources")
    prompts : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(root ++ "/work/project/.pi/prompts")
    configured : Bool <- T.hasTrustRequiringProjectResources(root ++ "/work/project",None{})
    check(configured,".pi/prompts requires trust")
    skills : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(root ++ "/work/.agents/skills")
    ancestor : Bool <- T.hasTrustRequiringProjectResources(root ++ "/work/project/sub",None{})
    check(ancestor,"ancestor .agents/skills requires trust")
    home : Bool <- T.hasTrustRequiringProjectResources(root ++ "/work/project/sub",Some{root ++ "/work"})
    check(Bool.not(home),"the user's ~/.agents/skills does not")
    # upstream trust-manager.test.ts: "stores decisions and inherits from parent directories"
    +temp : String <- IO.pure(String,root ++ "/upstream")
    +upstream : T.ProjectTrustStore <- IO.pure(T.ProjectTrustStore,T.create(temp ++ "/agent"))
    madeChild : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(temp ++ "/trusted-parent/project")
    u1 : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(upstream,temp ++ "/trusted-parent/project")
    s1 : Result<&2,&2,T.Error,Unit> <- T.set(upstream,temp ++ "/trusted-parent",Some{True{}})
    u2 : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(upstream,temp ++ "/trusted-parent/project")
    s2 : Result<&2,&2,T.Error,Unit> <- T.set(upstream,temp ++ "/trusted-parent/project",Some{False{}})
    u3 : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(upstream,temp ++ "/trusted-parent/project")
    s3 : Result<&2,&2,T.Error,Unit> <- T.set(upstream,temp ++ "/trusted-parent/project",None{})
    u4 : Result<&2,&2,T.Error,Maybe<&2,Bool>> <- T.get(upstream,temp ++ "/trusted-parent/project")
    check(String.eq(decision(u1) ++ decision(u2) ++ decision(u3) ++ decision(u4),"nonetruefalsetrue"),"stores decisions and inherits from parent directories")
    # upstream: "detects trust-requiring project resources" (HOME = the temp dir)
    +cwd : String <- IO.pure(String,temp ++ "/project")
    m1 : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(temp ++ "/.pi/agent")
    m2 : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(temp ++ "/.agents/skills")
    m3 : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(cwd)
    h1 : Bool <- T.hasTrustRequiringProjectResources(temp,Some{temp})
    h2 : Bool <- T.hasTrustRequiringProjectResources(cwd,Some{temp})
    w1 : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(temp ++ "/.pi/settings.json","{}")
    h3 : Bool <- T.hasTrustRequiringProjectResources(temp,Some{temp})
    r1 : Result<&2,&2,FS.Error,Unit> <- FS.remove(temp ++ "/.pi/settings.json",False{},True{})
    m4 : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(cwd ++ "/.pi")
    w2 : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(cwd ++ "/.pi/settings.json","{}")
    h4 : Bool <- T.hasTrustRequiringProjectResources(cwd,Some{temp})
    r2 : Result<&2,&2,FS.Error,Unit> <- FS.remove(cwd ++ "/.pi",True{},True{})
    m5 : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(cwd ++ "/.agents/skills")
    h5 : Bool <- T.hasTrustRequiringProjectResources(cwd,Some{temp})
    check(Bool.not(h1) && Bool.not(h2) && h3 && h4 && h5,"detects trust-requiring project resources")
