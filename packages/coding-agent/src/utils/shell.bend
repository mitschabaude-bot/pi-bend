import Base
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/child-process.bend as Child

type CommandTransport is Data:
  Argv{}
  Stdin{}
type ShellConfig is Data:
  ShellConfig{shell: String, args: List<&2,String>, commandTransport: Maybe<&2,CommandTransport>}
type Variable is Data: Variable{name: String, value: String}
def Environment() -> Data: List<&2,Variable>
type Error is Data:
  CustomShellNotFound{path: String}
  InvalidEnvironment{entry: String}
  DuplicateVariable{name: String}

def bash(shell: String) -> ShellConfig: ShellConfig{shell,"-c" <> Nil{},None{}}

def fallback(path: Maybe<&2,String>) -> ShellConfig:
  match path:
    case Some{value}: bash(value)
    case None{}: bash("sh")

def defaultShell(defaultBash: String, paths: List<&2,String>, found: Bool) -> IO(Result<&2,&2,Error,ShellConfig>):
  match found:
    case True{}: IO.pure(Result<&2,&2,Error,ShellConfig>,Done{bash(defaultBash)})
    case False{}:
      do IO<Result<&2,&2,Error,ShellConfig>>:
        found : Maybe<&2,String> <- Child.findExecutableOnPath("bash",paths,None{})
        return Done{fallback(found)}

# This is the shared POSIX selection algorithm. Explicit paths and /bin/bash
# use upstream's existence policy; the eventual spawn reports execute errors.
def getShellConfigWith(customShellPath: Maybe<&2,String>, +defaultBash: String, paths: List<&2,String>) -> IO(Result<&2,&2,Error,ShellConfig>):
  match customShellPath:
    case Some{SCon{+first,+rest}}:
      +path = {SCon{first,rest} : String}
      do IO<Result<&2,&2,Error,ShellConfig>>:
        found : Bool <- FS.accessible(path,0)
        return Bool.pick(Result<&2,&2,Error,ShellConfig>,found,Done{bash(path)},Fail{CustomShellNotFound{path}})
    case _:
      do IO<Result<&2,&2,Error,ShellConfig>>:
        found : Bool <- FS.accessible(defaultBash,0)
        defaultShell(defaultBash,paths,found)

def pathEntries(result: Result<&1,&1,U32 & String,String>) -> List<&2,String>:
  match result:
    case Done{value}: Strings.split(value,':')
    case Fail{_}: Nil{}

def getShellConfig(customShellPath: Maybe<&2,String>) -> IO(Result<&2,&2,Error,ShellConfig>):
  do IO<Result<&2,&2,Error,ShellConfig>>:
    path : Result<&1,&1,U32 & String,String> <- IO.get_env("PATH")
    getShellConfigWith(customShellPath,"/bin/bash",pathEntries(path))

def pathKey(name: String) -> Bool:
  match name:
    case SCon{p,SCon{a,SCon{t,SCon{h,SNil{}}}}}:
      Char.is_eq(Char.to_lower(p),'p') && Char.is_eq(Char.to_lower(a),'a') && Char.is_eq(Char.to_lower(t),'t') && Char.is_eq(Char.to_lower(h),'h')
    case _: False{}

def contains(+value: String, entries: List<&2,String>) -> Bool:
  match entries:
    case Nil{}: False{}
    case "" <> rest: contains(value,rest)
    case entry <> +rest: Bool.pick(Unit -> Bool,Strings.equal(value,entry),_ => True{},_ => contains(value,rest))(Unit{})

def prependPath(+binDir: String, +current: String) -> String:
  Bool.pick(String,contains(binDir,Strings.split(current,':')),current,
    Bool.pick(String,Strings.equal(binDir,""),current,Bool.pick(String,Strings.equal(current,""),binDir,binDir ++ ":" ++ current)))

def pathVariable(environment: Environment()) -> Maybe<&2,Variable>:
  match environment:
    case Nil{}: None{}
    case Variable{+name,value} <> +rest:
      Bool.pick(Unit -> Maybe<&2,Variable>,pathKey(name),_ => Some{Variable{name,value}},_ => pathVariable(rest))(Unit{})

def updateEnvironment(+name: String, +value: String, entries: Environment(), +reversed: Environment()) -> Environment():
  match entries:
    case Nil{}: List.reverse(&2,Variable,Variable{name,value} <> reversed)
    case Variable{+key,+old} <> +rest:
      Bool.pick(Unit -> Environment(),Strings.equal(name,key),
        _ => List.append(&2,Variable,List.reverse(&2,Variable,Variable{key,value} <> reversed),rest),
        _ => updateEnvironment(name,value,rest,Variable{key,old} <> reversed))(Unit{})

def withPath(binDir: String, environment: Environment(), path: Maybe<&2,Variable>) -> Environment():
  match path:
    case None{}: updateEnvironment("PATH",binDir,environment,Nil{})
    case Some{Variable{name,value}}: updateEnvironment(name,prependPath(binDir,value),environment,Nil{})

# Named immutable variables replace ProcessEnv's object mutation. Preserve the
# first case-insensitive PATH key and all other values, including empty strings.
def getShellEnv(binDir: String, +environment: Environment()) -> Environment(): withPath(binDir,environment,pathVariable(environment))

def present(+name: String, entries: Environment()) -> Bool:
  match entries:
    case Nil{}: False{}
    case Variable{key,_} <> +rest: Bool.pick(Unit -> Bool,Strings.equal(name,key),_ => True{},_ => present(name,rest))(Unit{})

def validText(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{0},_}: False{}
    case SCon{_,rest}: validText(rest)

def variable(entry: String, reversed: String) -> Maybe<&2,Variable>:
  match entry reversed:
    case SCon{'=',value} SCon{char,rest}: Some{Variable{String.reverse(SCon{char,rest}),value}}
    case SCon{'=',_} SNil{}: None{}
    case SCon{char,rest} reversed: variable(rest,SCon{char,reversed})
    case SNil{} _: None{}

def environmentEntry(+entry: String, +reversed: Environment(), parsed: Maybe<&2,Variable>) -> Result<&2,&2,Error,Environment()>:
  match parsed:
    case None{}: Fail{InvalidEnvironment{entry}}
    case Some{Variable{+name,value}}:
      Bool.pick(Result<&2,&2,Error,Environment()>,present(name,reversed),Fail{DuplicateVariable{name}},Done{Variable{name,value} <> reversed})

def readEnvironment(entries: List<String>, result: Result<&2,&2,Error,Environment()>) -> Result<&2,&2,Error,Environment()>:
  match entries result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} Done{reversed}: Done{List.reverse(&2,Variable,reversed)}
    case +entry <> rest Done{reversed}:
      readEnvironment(rest,Bool.pick(Unit -> Result<&2,&2,Error,Environment()>,validText(entry),_ => environmentEntry(entry,reversed,variable(entry,"")),_ => Fail{InvalidEnvironment{entry}})(Unit{}))

def fromEntries(entries: List<String>) -> Result<&2,&2,Error,Environment()>: readEnvironment(entries,Done{Nil{}})
def toEntries(environment: Environment()) -> List<String>:
  match environment:
    case Nil{}: Nil{}
    case Variable{name,value} <> rest: (name ++ "=" ++ value) <> toEntries(rest)

# Match the actual source filter, not its broader comment: C0 controls other
# than tab/LF/CR and FFF9..FFFB are removed; other format characters survive.
def sanitized(text: String, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,rest}:
      +code = Char.to_u32(char)
      +keep = U32.is_eq(code,9) || U32.is_eq(code,10) || U32.is_eq(code,13) || (U32.is_gt(code,31) && Bool.not(U32.is_ge(code,65529) && U32.is_le(code,65531)))
      sanitized(rest,Bool.pick(String,keep,SCon{char,reversed},reversed))

def sanitizeBinaryOutput(text: String) -> String: sanitized(text,"")

# The process boundary supplies the host environment once. Policy thereafter
# uses immutable named values rather than implicit ambient reads.
def loadShellEnv(binDir: String) -> IO(Result<&2,&2,Error,Environment()>):
  do IO<Result<&2,&2,Error,Environment()>>:
    entries : List<String> <- IO.environment()
    return Result.map(&2,&2,Error,Environment(),Environment(),environment => getShellEnv(binDir,environment),fromEntries(entries))
