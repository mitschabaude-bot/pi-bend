import Base
import ../../../runtime/src/file-lock.bend as Lock
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Json
import ../../../runtime/src/posix-path.bend as Path
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/utf8.bend as Utf8

# upstream core/trust-manager.ts: saved project trust decisions in
# <agentDir>/trust.json, keyed by canonical folder path. The nearest saved
# ancestor decision applies; `null` removes a key.
type ProjectTrustStoreEntry is Data: ProjectTrustStoreEntry{path: String,decision: Bool}
type ProjectTrustUpdate is Data: ProjectTrustUpdate{path: String,decision: Maybe<&2,Bool>}
type ProjectTrustOption is Data: ProjectTrustOption{label: String,trusted: Bool,updates: List<&2,ProjectTrustUpdate>,savedPath: Maybe<&2,String>}
type ProjectTrustStore is Data: ProjectTrustStore{trustPath: String}
type Error is Data: Error{message: String}

def CONFIG_DIR_NAME() -> String: ".pi"
def TRUST_REQUIRING_PROJECT_CONFIG_RESOURCES() -> List<&2,String>: ["settings.json","extensions","skills","prompts","themes","SYSTEM.md","APPEND_SYSTEM.md"]

def create(agentDir: String) -> ProjectTrustStore: ProjectTrustStore{Path.join(agentDir,"trust.json")}

# upstream canonicalizePath(resolvePath(cwd)): the real path when it exists.
# Callers pass absolute folders.
def canonicalOr(+path: String,result: Result<&2,&2,FS.Error,String>) -> String:
  match result:
    case Done{real}: real
    case Fail{_}: path
def normalizeCwd(cwd: String) -> IO(String):
  do IO<String>:
    +resolved : String <- IO.pure(String,Path.normalize(cwd))
    real : Result<&2,&2,FS.Error,String> <- FS.realpath(resolved)
    return canonicalOr(resolved,real)

def dirname(+path: String) -> String: Path.normalize(path ++ "/..")
def parentOf(+path: String) -> Maybe<&2,String>:
  +parent = dirname(path)
  Bool.pick(Maybe<&2,String>,String.eq(parent,path),None{},Some{parent})

def getProjectTrustParentPath(cwd: String) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    trustPath : String <- normalizeCwd(cwd)
    return parentOf(trustPath)

def parentOption(parent: Maybe<&2,String>,trustPath: String) -> List<&2,ProjectTrustOption>:
  match parent:
    case None{}: Nil{}
    case Some{+path}: [ProjectTrustOption{"Trust parent folder (" ++ path ++ ")",True{},[ProjectTrustUpdate{path,Some{True{}}},ProjectTrustUpdate{trustPath,None{}}],Some{path}}]
def sessionOnly(include: Bool,label: String,trusted: Bool) -> List<&2,ProjectTrustOption>:
  Bool.pick(List<&2,ProjectTrustOption>,include,[ProjectTrustOption{label,trusted,Nil{},None{}}],Nil{})
def trustOptions(+trustPath: String,+includeSessionOnly: Bool) -> List<&2,ProjectTrustOption>:
  ProjectTrustOption{"Trust",True{},[ProjectTrustUpdate{trustPath,Some{True{}}}],Some{trustPath}} <> List.append(&2,ProjectTrustOption,parentOption(parentOf(trustPath),trustPath),List.append(&2,ProjectTrustOption,sessionOnly(includeSessionOnly,"Trust (this session only)",True{}),ProjectTrustOption{"Do not trust",False{},[ProjectTrustUpdate{trustPath,Some{False{}}}],Some{trustPath}} <> sessionOnly(includeSessionOnly,"Do not trust (this session only)",False{})))
def getProjectTrustOptions(cwd: String,includeSessionOnly: Bool) -> IO(List<&2,ProjectTrustOption>):
  do IO<List<&2,ProjectTrustOption>>:
    trustPath : String <- normalizeCwd(cwd)
    return trustOptions(trustPath,includeSessionOnly)

# The trust file maps paths to true, false or null.
type Entry is Data: Entry{path: String,decision: Maybe<&2,Bool>}
def stripBom(text: String) -> String:
  match text:
    case SCon{'\u{feff}',rest}: rest
    case _: text
def invalidValue(+path: String,key: String) -> Result<&2,&2,Error,List<&2,Entry>>:
  Fail{Error{"Invalid trust store " ++ path ++ ": value for " ++ Json.quote(key) ++ " must be true, false, or null"}}
def withEntry(+key: String,decision: Maybe<&2,Bool>,rest: Result<&2,&2,Error,List<&2,Entry>>) -> Result<&2,&2,Error,List<&2,Entry>>:
  match rest:
    case Done{entries}: Done{Entry{key,decision} <> entries}
    case failed: failed
def entriesOf(+path: String,properties: List<&2,R.Property<V.Value>>) -> Result<&2,&2,Error,List<&2,Entry>>:
  match properties:
    case Nil{}: Done{Nil{}}
    case R.Property{+key,V.Boolean{value}} <> rest: withEntry(key,Some{value},entriesOf(path,rest))
    case R.Property{+key,V.Null{}} <> rest: withEntry(key,None{},entriesOf(path,rest))
    case R.Property{key,_} <> _: invalidValue(path,key)
def trustData(+path: String,parsed: Result<&2,&2,Json.ParseError,V.Value>) -> Result<&2,&2,Error,List<&2,Entry>>:
  match parsed:
    case Done{V.ObjectValue{properties}}: entriesOf(path,R.entries(V.Value,properties))
    case Done{_}: Fail{Error{"Invalid trust store " ++ path ++ ": expected an object"}}
    case Fail{_}: Fail{Error{"Failed to read trust store " ++ path ++ ": invalid JSON"}}
def trustRead(+path: String,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Result<&2,&2,Error,List<&2,Entry>>:
  match read:
    case Fail{FS.System{2,_}}: Done{Nil{}}
    case Fail{cause}: Fail{Error{"Failed to read trust store " ++ path ++ ": " ++ FS.errorMessage(cause)}}
    case Done{bytes}: trustData(path,Json.parse(stripBom(Utf8.decodeBuffer(bytes))))
def readTrustFile(+path: String) -> IO(Result<&2,&2,Error,List<&2,Entry>>):
  do IO<Result<&2,&2,Error,List<&2,Entry>>>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return trustRead(path,read)

# The folder and its ancestors, nearest first; `fuel` bounds the walk.
def ancestors(fuel: Nat,current: Maybe<&2,String>) -> List<&2,String>:
  match fuel current:
    case _ None{}: Nil{}
    case Zero{} _: Nil{}
    case Succ{left} Some{+path}: path <> ancestors(left,parentOf(path))
def decisionAt(entries: List<&2,Entry>,+path: String) -> Maybe<&2,Bool>:
  match entries:
    case Nil{}: None{}
    case Entry{key,decision} <> rest:
      +further = decisionAt(rest,path)
      Bool.pick(Maybe<&2,Bool>,String.eq(key,path),decision,further)
def nearestAt(found: Maybe<&2,Bool>,path: String,further: Maybe<&2,ProjectTrustStoreEntry>) -> Maybe<&2,ProjectTrustStoreEntry>:
  match found:
    case Some{decision}: Some{ProjectTrustStoreEntry{path,decision}}
    case None{}: further
def nearestIn(+entries: List<&2,Entry>,paths: List<&2,String>) -> Maybe<&2,ProjectTrustStoreEntry>:
  match paths:
    case Nil{}: None{}
    case +path <> rest: nearestAt(decisionAt(entries,path),path,nearestIn(entries,rest))
def findNearestTrustEntry(entries: List<&2,Entry>,+cwd: String) -> Maybe<&2,ProjectTrustStoreEntry>:
  nearestIn(entries,ancestors(String.length(cwd) + 1n,Some{cwd}))

# upstream withTrustFileLock: proper-lockfile on <trust.json>.lock, ten
# attempts twenty milliseconds apart.
def lockOptions() -> Lock.Options: Lock.Options{10000,5000,10n,20,False{}}
def lockFailed(-A: Data) -> Result<&2,&2,Error,A>: Fail{Error{"Failed to acquire trust store lock"}}

def entryAfterRead(read: Result<&2,&2,Error,List<&2,Entry>>,+cwd: String) -> Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>:
  match read:
    case Done{entries}: Done{findNearestTrustEntry(entries,cwd)}
    case Fail{error}: Fail{error}
def lockedEntry(locked: Result<&2,&1,Lock.Error,Lock.Owner>,+path: String,+cwd: String) -> IO(Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>):
  match locked:
    case Fail{_}: IO.pure(Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>,lockFailed(Maybe<&2,ProjectTrustStoreEntry>))
    case Done{owner}:
      do IO<Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>>:
        read : Result<&2,&2,Error,List<&2,Entry>> <- readTrustFile(path)
        done : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        return entryAfterRead(read,cwd)
def getEntry(store: ProjectTrustStore,cwd: String) -> IO(Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>):
  match store:
    case ProjectTrustStore{+path}:
      do IO<Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>>:
        +key : String <- normalizeCwd(cwd)
        dir : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(dirname(path))
        locked : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,lockOptions(),None{})
        lockedEntry(locked,path,key)
def decisionOf(entry: Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>>) -> Result<&2,&2,Error,Maybe<&2,Bool>>:
  match entry:
    case Done{Some{ProjectTrustStoreEntry{_,decision}}}: Done{Some{decision}}
    case Done{None{}}: Done{None{}}
    case Fail{error}: Fail{error}
def get(store: ProjectTrustStore,cwd: String) -> IO(Result<&2,&2,Error,Maybe<&2,Bool>>):
  do IO<Result<&2,&2,Error,Maybe<&2,Bool>>>:
    entry : Result<&2,&2,Error,Maybe<&2,ProjectTrustStoreEntry>> <- getEntry(store,cwd)
    return decisionOf(entry)

# Writes keep upstream's JSON.stringify(sortedKeys, null, 2) layout.
def withoutKey(entries: List<&2,Entry>,+key: String) -> List<&2,Entry>:
  match entries:
    case Nil{}: Nil{}
    case Entry{+path,decision} <> rest:
      +tail = withoutKey(rest,key)
      Bool.pick(List<&2,Entry>,String.eq(path,key),tail,Entry{path,decision} <> tail)
def applied(entries: List<&2,Entry>,+key: String,decision: Maybe<&2,Bool>) -> List<&2,Entry>:
  match decision:
    case None{}: withoutKey(entries,key)
    case Some{value}: Entry{key,Some{value}} <> withoutKey(entries,key)
def entryBefore(left: Entry,right: Entry) -> Bool:
  match left right:
    case Entry{a,_} Entry{b,_}: String.is_lt(a,b)
def insertSorted(+entry: Entry,entries: List<&2,Entry>) -> List<&2,Entry>:
  match entries:
    case Nil{}: [entry]
    case +first <> +rest: Bool.pick(Unit -> List<&2,Entry>,entryBefore(entry,first),_ => entry <> first <> rest,_ => first <> insertSorted(entry,rest))(Unit{})
def sorted(entries: List<&2,Entry>,result: List<&2,Entry>) -> List<&2,Entry>:
  match entries:
    case Nil{}: result
    case entry <> rest: sorted(rest,insertSorted(entry,result))
def valueText(decision: Maybe<&2,Bool>) -> String:
  match decision:
    case Some{True{}}: "true"
    case Some{False{}}: "false"
    case None{}: "null"
def lines(entries: List<&2,Entry>) -> List<&2,String>:
  match entries:
    case Nil{}: Nil{}
    case Entry{path,decision} <> rest: ("  " ++ Json.quote(path) ++ ": " ++ valueText(decision)) <> lines(rest)
def trustText(entries: List<&2,Entry>) -> String:
  match entries:
    case Nil{}: "{}\n"
    case entries: "{\n" ++ String.join(lines(entries),",\n") ++ "\n}\n"

type Keyed is Data: Keyed{key: String,decision: Maybe<&2,Bool>}
def keyedUpdates(updates: List<&2,ProjectTrustUpdate>) -> IO(List<&2,Keyed>):
  match updates:
    case Nil{}: IO.pure(List<&2,Keyed>,Nil{})
    case ProjectTrustUpdate{path,decision} <> rest:
      do IO<List<&2,Keyed>>:
        key : String <- normalizeCwd(path)
        more : List<&2,Keyed> <- keyedUpdates(rest)
        return Keyed{key,decision} <> more
def applyAll(updates: List<&2,Keyed>,entries: List<&2,Entry>) -> List<&2,Entry>:
  match updates:
    case Nil{}: entries
    case Keyed{key,decision} <> rest: applyAll(rest,applied(entries,key,decision))
def writeResult(result: Result<&2,&2,FS.Error,Unit>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Done{_}: Done{Unit{}}
    case Fail{cause}: Fail{Error{FS.errorMessage(cause)}}
def written(+path: String,read: Result<&2,&2,Error,List<&2,Entry>>,updates: List<&2,Keyed>) -> IO(Result<&2,&2,Error,Unit>):
  match read:
    case Fail{error}: IO.pure(Result<&2,&2,Error,Unit>,Fail{error})
    case Done{entries}:
      do IO<Result<&2,&2,Error,Unit>>:
        result : Result<&2,&2,FS.Error,Unit> <- FS.writeFile(path,trustText(sorted(applyAll(updates,entries),Nil{})))
        return writeResult(result)
def lockedWrite(locked: Result<&2,&1,Lock.Error,Lock.Owner>,+path: String,updates: List<&2,Keyed>) -> IO(Result<&2,&2,Error,Unit>):
  match locked:
    case Fail{_}: IO.pure(Result<&2,&2,Error,Unit>,lockFailed(Unit))
    case Done{owner}:
      do IO<Result<&2,&2,Error,Unit>>:
        read : Result<&2,&2,Error,List<&2,Entry>> <- readTrustFile(path)
        result : Result<&2,&2,Error,Unit> <- written(path,read,updates)
        done : Result<&2,&2,Lock.Error,Unit> <- Lock.release(owner)
        return result
def setMany(store: ProjectTrustStore,updates: List<&2,ProjectTrustUpdate>) -> IO(Result<&2,&2,Error,Unit>):
  match store:
    case ProjectTrustStore{+path}:
      do IO<Result<&2,&2,Error,Unit>>:
        keyed : List<&2,Keyed> <- keyedUpdates(updates)
        dir : Result<&2,&2,FS.Error,Unit> <- FS.mkdir(dirname(path))
        locked : Result<&2,&1,Lock.Error,Lock.Owner> <- Lock.acquire(path,lockOptions(),None{})
        lockedWrite(locked,path,keyed)
def set(store: ProjectTrustStore,cwd: String,decision: Maybe<&2,Bool>) -> IO(Result<&2,&2,Error,Unit>):
  setMany(store,[ProjectTrustUpdate{cwd,decision}])

# upstream hasTrustRequiringProjectResources: trust-requiring entries under
# <cwd>/.pi, or a .agents/skills folder in cwd or an ancestor other than the
# user's ~/.agents/skills.
def exists(path: String) -> IO(Bool): FS.accessible(path,0)
def anyExists(paths: List<&2,String>) -> IO(Bool):
  match paths:
    case Nil{}: IO.pure(Bool,False{})
    case path <> rest:
      do IO<Bool>:
        found : Bool <- exists(path)
        Bool.pick(Unit -> IO(Bool),found,_ => IO.pure(Bool,True{}),_ => anyExists(rest))(Unit{})
def configEntries(+configDir: String,names: List<&2,String>) -> List<&2,String>:
  match names:
    case Nil{}: Nil{}
    case name <> rest: Path.join(configDir,name) <> configEntries(configDir,rest)
def agentsSkills(+userSkills: String,folders: List<&2,String>) -> List<&2,String>:
  match folders:
    case Nil{}: Nil{}
    case folder <> rest:
      +skills = Path.join(folder,".agents/skills")
      +tail = agentsSkills(userSkills,rest)
      Bool.pick(List<&2,String>,String.eq(skills,userSkills),tail,skills <> tail)
def canonicalHome(home: Maybe<&2,String>) -> IO(String):
  match home:
    case Some{value}: normalizeCwd(value)
    case None{}: IO.pure(String,"")
def hasTrustRequiringProjectResources(cwd: String,home: Maybe<&2,String>) -> IO(Bool):
  do IO<Bool>:
    +folder : String <- normalizeCwd(cwd)
    homeDir : String <- canonicalHome(home)
    inConfig : Bool <- anyExists(configEntries(Path.join(folder,CONFIG_DIR_NAME()),TRUST_REQUIRING_PROJECT_CONFIG_RESOURCES()))
    Bool.pick(Unit -> IO(Bool),inConfig,_ => IO.pure(Bool,True{}),_ => anyExists(agentsSkills(Path.join(homeDir,".agents/skills"),ancestors(String.length(folder) + 1n,Some{folder}))))(Unit{})
