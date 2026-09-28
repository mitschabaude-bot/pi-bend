import Base
import ../../../runtime/src/base64.bend as Base64
import ../../../runtime/src/child-process.bend as Child
import ../../../runtime/src/callback.bend as Callback
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/text.bend as Text
import ../../../ai/src/utils/uuid.bend as Uuid
import ./clipboard-command.bend as ClipCmd
import ../core/tools/output-accumulator.bend as Temp

# Desktop writers retain selection ownership. Remote and headless terminals use
# OSC 52, which has no acknowledgement channel back from the terminal.
type Environment is Data:
  Environment{termux: Bool,wayland: Bool,x11: Bool,remote: Bool}
type Command is Type:
  Command{name: String,args: List<String>}

def present(result: Result<&1,&1,U32 & String,String>) -> Bool:
  match result:
    case Done{value}: Bool.not(String.is_empty(value))
    case Fail{_}: False{}
def flags(termux: Bool,wayland: Bool,x11: Bool,ssh: Bool,client: Bool,mosh: Bool) -> Environment:
  Environment{termux,wayland,x11,ssh || client || mosh}
def environment() -> IO(Environment):
  do IO<Environment>:
    termux : Result<&1,&1,U32 & String,String> <- IO.get_env("TERMUX_VERSION")
    wayland : Result<&1,&1,U32 & String,String> <- IO.get_env("WAYLAND_DISPLAY")
    x11 : Result<&1,&1,U32 & String,String> <- IO.get_env("DISPLAY")
    ssh : Result<&1,&1,U32 & String,String> <- IO.get_env("SSH_CONNECTION")
    client : Result<&1,&1,U32 & String,String> <- IO.get_env("SSH_CLIENT")
    mosh : Result<&1,&1,U32 & String,String> <- IO.get_env("MOSH_CONNECTION")
    return flags(present(termux),present(wayland),present(x11),present(ssh),present(client),present(mosh))
def termuxWriters(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"termux-clipboard-set",Nil{}} <> Nil{}
    case False{}: Nil{}
def waylandWriters(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"wl-copy",Nil{}} <> Nil{}
    case False{}: Nil{}
def x11Writers(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"xclip","-selection" <> "clipboard" <> Nil{}} <> Command{"xsel","--clipboard" <> "--input" <> Nil{}} <> Nil{}
    case False{}: Nil{}
def candidates(flags: Environment) -> List<&1,Command>:
  match flags:
    case Environment{termux,wayland,x11,_}:
      List.concat(&1,Command,termuxWriters(termux) <> waylandWriters(wayland) <> x11Writers(x11) <> Nil{})
def termuxReaders(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"termux-clipboard-get",Nil{}} <> Nil{}
    case False{}: Nil{}
def waylandReaders(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"wl-paste","--no-newline" <> "--type" <> "text" <> Nil{}} <> Nil{}
    case False{}: Nil{}
def x11Readers(enabled: Bool) -> List<&1,Command>:
  match enabled:
    case True{}: Command{"xclip","-selection" <> "clipboard" <> "-out" <> Nil{}} <> Command{"xsel","--clipboard" <> "--output" <> Nil{}} <> Nil{}
    case False{}: Nil{}
def readers(flags: Environment) -> List<&1,Command>:
  match flags:
    case Environment{termux,wayland,x11,_}:
      List.concat(&1,Command,termuxReaders(termux) <> waylandReaders(wayland) <> x11Readers(x11) <> Nil{})
def discard(_: Unit,_: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
def exited(result: Result<&2,&2,Child.ExecutionError,U32>) -> Bool:
  match result:
    case Done{0}: True{}
    case _: False{}
def runResolved(program: Maybe<&2,String>,args: List<String>,text: String,cwd: String,env: List<String>) -> IO(Bool):
  match program:
    case None{}: IO.pure(Bool,False{})
    case Some{path}:
      do IO<Bool>:
        +sink : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Unit,~List<&2,U32>,~Result<&2,&2,String,Unit>,~discard,Unit{})
        result : Result<&2,&2,Child.ExecutionError,U32> <- Child.executeValidated(Child.Merged{},True{},path,args,text,cwd,env,Nil{},sink,Done{Some{5000}})
        Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,sink)
        return exited(result)
def runFound(name: String,args: List<String>,text: String,cwd: String,found: String & List<String>) -> IO(Bool):
  match found:
    case (path,env):
      do IO<Bool>:
        program : Maybe<&2,String> <- Child.resolveCommand(name,path)
        runResolved(program,args,text,cwd,env)
def runSearched(command: Command,text: String,cwd: String,found: String & List<String>) -> IO(Bool):
  match command:
    case Command{name,args}: runFound(name,args,text,cwd,found)
def run(command: Command,text: String,cwd: String) -> IO(Bool):
  do IO<Bool>:
    env : List<String> <- IO.environment()
    runSearched(command,text,cwd,Child.withSearchPath(env,None{}))
def attempt(commands: List<&1,Command>,+text: String,+cwd: String) -> IO(Bool):
  match commands:
    case Nil{}: IO.pure(Bool,False{})
    case command <> rest:
      do IO<Bool>:
        copied : Bool <- run(command,text,cwd)
        Bool.pick(Unit -> IO(Bool),copied,_ => IO.pure(Bool,True{}),_ => attempt(rest,text,cwd))(Unit{})

type ReadAttempt is Data: Unavailable{} Read{value: Maybe<&2,String>}
type Capture is Data: Capture{reversed: List<&2,U32>,size: Nat}
def captured(+bytes: List<&2,U32>,state: Capture) -> Capture & Result<&2,&2,String,Unit>:
  match state:
    case Capture{+reversed,+size}:
      +next = size + List.length(&2,U32,bytes)
      Bool.pick(Unit -> Capture & Result<&2,&2,String,Unit>,Nat.is_le(next,1048576n),
        _ => (Capture{List.append(&2,U32,List.reverse(&2,U32,bytes),reversed),next},Done{Unit{}}),
        _ => (Capture{reversed,size},Fail{"Clipboard output exceeds 1 MiB"}))(Unit{})
def capture(target: Ref.Ref<Capture>,bytes: List<&2,U32>) -> IO(Result<&2,&2,String,Unit>):
  Ref.modify(Capture,Result<&2,&2,String,Unit>,target,state => captured(bytes,state))
def readResult(result: Result<&2,&2,Child.ExecutionError,U32>,state: Capture) -> ReadAttempt:
  match result state:
    case Done{0} Capture{reversed,_}:
      +value = Utf8.decodeBuffer(List.reverse(&2,U32,reversed))
      Read{Bool.pick(Maybe<&2,String>,String.is_empty(value),None{},Some{value})}
    case _ _: Unavailable{}
def readResolved(program: Maybe<&2,String>,args: List<String>,cwd: String,env: List<String>) -> IO(ReadAttempt):
  match program:
    case None{}: IO.pure(ReadAttempt,Unavailable{})
    case Some{path}:
      do IO<ReadAttempt>:
        +state : Ref.Ref<Capture> <- Ref.new(Capture,Capture{Nil{},0n})
        +sink : Callback.Callback<List<&2,U32>,Result<&2,&2,String,Unit>> <- Callback.create(~Ref.Ref<Capture>,~List<&2,U32>,~Result<&2,&2,String,Unit>,~capture,state)
        result : Result<&2,&2,Child.ExecutionError,U32> <- Child.executeValidated(Child.Stdout{},False{},path,args,"",cwd,env,Nil{},sink,Done{Some{5000}})
        Callback.dispose(List<&2,U32>,Result<&2,&2,String,Unit>,sink)
        collected : Capture <- Ref.dispose(Capture,state)
        return readResult(result,collected)
def readFound(name: String,args: List<String>,cwd: String,found: String & List<String>) -> IO(ReadAttempt):
  match found:
    case (path,env):
      do IO<ReadAttempt>:
        program : Maybe<&2,String> <- Child.resolveCommand(name,path)
        readResolved(program,args,cwd,env)
def readCommand(command: Command,cwd: String) -> IO(ReadAttempt):
  match command:
    case Command{name,args}:
      do IO<ReadAttempt>:
        env : List<String> <- IO.environment()
        readFound(name,args,cwd,Child.withSearchPath(env,None{}))
def available(value: ReadAttempt) -> Bool:
  match value:
    case Read{_}: True{}
    case Unavailable{}: False{}
def readAttempt(commands: List<&1,Command>,+cwd: String) -> IO(ReadAttempt):
  match commands:
    case Nil{}: IO.pure(ReadAttempt,Unavailable{})
    case command <> rest:
      do IO<ReadAttempt>:
        +result : ReadAttempt <- readCommand(command,cwd)
        Bool.pick(Unit -> IO(ReadAttempt),available(result),_ => IO.pure(ReadAttempt,result),_ => readAttempt(rest,cwd))(Unit{})
def readValue(value: ReadAttempt) -> Maybe<&2,String>:
  match value:
    case Read{value}: value
    case Unavailable{}: None{}
def read(cwd: String) -> IO(Maybe<&2,String>):
  do IO<Maybe<&2,String>>:
    flags : Environment <- environment()
    result : ReadAttempt <- readAttempt(readers(flags),cwd)
    return readValue(result)

# WSL without a Linux display can still reach the Windows clipboard. A file
# carries UTF-8 text across interop; PowerShell's stdin uses the console code
# page and would corrupt non-ASCII input.
def wslRelease(result: Result<&2,&2,FS.Error,List<&2,U32>>) -> Bool:
  match result:
    case Done{bytes}:
      +version = String.to_lower(Utf8.decodeBuffer(bytes))
      String.contains(version,"microsoft") || String.contains(version,"wsl")
    case Fail{_}: False{}
def isWsl() -> IO(Bool):
  do IO<Bool>:
    distro : Result<&1,&1,U32 & String,String> <- IO.get_env("WSL_DISTRO_NAME")
    interop : Result<&1,&1,U32 & String,String> <- IO.get_env("WSLENV")
    Bool.pick(Unit -> IO(Bool),present(distro) || present(interop),_ => IO.pure(Bool,True{}),
      _ => do IO<Bool>:
        release : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile("/proc/version")
        return wslRelease(release))(Unit{})
def windowsPath(output: Maybe<&2,List<&2,U32>>) -> Maybe<&2,String>:
  match output:
    case None{}: None{}
    case Some{bytes}:
      +path = Text.trim(Utf8.decodeBuffer(bytes))
      Bool.pick(Maybe<&2,String>,String.is_empty(path),None{},Some{path})
def powerShellAt(path: Maybe<&2,String>,cwd: String) -> IO(Bool):
  match path:
    case None{}: IO.pure(Bool,False{})
    case Some{value}:
      do IO<Bool>:
        +script : String <- IO.pure(String,"Set-Clipboard -Value ([System.IO.File]::ReadAllText('" ++ Strings.replaceAll(value,"'","''") ++ "', [System.Text.Encoding]::UTF8))")
        output : Maybe<&2,List<&2,U32>> <- ClipCmd.runClipboardCommand("powershell.exe",["-NoProfile","-Command",script],ClipCmd.withTimeout(5000),cwd)
        return Maybe.is_some(&2,List<&2,U32>,output)
def writtenWindows(path: String,+cwd: String,result: Result<&2,&2,FS.Error,Unit>) -> IO(Bool):
  match result:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{_}:
      do IO<Bool>:
        output : Maybe<&2,List<&2,U32>> <- ClipCmd.runClipboardCommand("wslpath",["-w",path],ClipCmd.withTimeout(1000),cwd)
        powerShellAt(windowsPath(output),cwd)
def windowsNamed(text: String,cwd: String,name: Result<&2,&2,Uuid.Error,String>) -> IO(Bool):
  match name:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{id}:
      do IO<Bool>:
        directory : String <- Temp.tempDirectory(["TMPDIR","TMP","TEMP"],None{})
        +path : String <- IO.pure(String,FS.child(directory,"pi-wsl-clip-" ++ id ++ ".txt"))
        written : Result<&2,&2,FS.Error,Unit> <- FS.writeFileMode(path,text,384)
        copied : Bool <- writtenWindows(path,cwd,written)
        removed : Result<&2,&2,FS.Error,Unit> <- FS.remove(path,False{},True{})
        return copied
def copyViaWindowsClipboard(text: String,cwd: String) -> IO(Bool):
  do IO<Bool>:
    name : Result<&2,&2,Uuid.Error,String> <- Uuid.randomUUID()
    windowsNamed(text,cwd,name)

def encoded(value: Result<&2,&2,Base64.Error,String>) -> Result<&2,&2,String,String>:
  match value:
    case Done{text}: Done{text}
    case Fail{_}: Fail{"Clipboard unavailable"}
def osc52Encoded(value: Result<&2,&2,String,String>) -> Result<&2,&2,String,String>:
  match value:
    case Fail{message}: Fail{message}
    case Done{+value}:
      Bool.pick(Result<&2,&2,String,String>,Nat.is_le(String.length(value),100000n),Done{"\u{1b}]52;c;" ++ value ++ "\u{7}"},Fail{"Clipboard unavailable: text exceeds the OSC 52 size limit"})
def osc52(text: String) -> Result<&2,&2,String,String>:
  osc52Encoded(encoded(Base64.encode(Utf8.encode(text))))
def emit(value: Result<&2,&2,String,String>) -> IO(Result<&2,&2,String,Unit>):
  match value:
    case Fail{message}: IO.pure(Result<&2,&2,String,Unit>,Fail{message})
    case Done{sequence}:
      do IO<Result<&2,&2,String,Unit>>:
        IO.write(sequence)
        return Done{Unit{}}
def emitIfPossible(value: Result<&2,&2,String,String>) -> IO(Result<&2,&2,String,Unit>):
  match value:
    case Fail{_}: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case Done{sequence}:
      do IO<Result<&2,&2,String,Unit>>:
        IO.write(sequence)
        return Done{Unit{}}
def unavailable(flags: Environment) -> String:
  match flags:
    case Environment{True{},_,_,_}: "Clipboard unavailable: install the Termux:API app and `termux-api` package"
    case Environment{_,True{},_,_}: "Clipboard unavailable: install `wl-clipboard` (`wl-copy`) or check Wayland access"
    case Environment{_,_,True{},_}: "Clipboard unavailable: install `xclip` or `xsel`, or check X11 access"
    case _: "Clipboard unavailable"
def terminalFallback(text: String,flags: Environment) -> IO(Result<&2,&2,String,Unit>):
  match flags:
    case Environment{False{},False{},False{},_}: emit(osc52(text))
    case Environment{_,_,_,True{}}: emit(osc52(text))
    case _: IO.pure(Result<&2,&2,String,Unit>,Fail{unavailable(flags)})
def emitted(value: Result<&2,&2,String,String>) -> IO(Bool):
  match value:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{sequence}:
      do IO<Bool>:
        IO.write(sequence)
        return True{}
def afterWindows(copied: Bool,text: String,flags: Environment) -> IO(Result<&2,&2,String,Unit>):
  match copied flags:
    case True{} Environment{_,_,_,True{}}: emitIfPossible(osc52(text))
    case True{} _: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case False{} _: terminalFallback(text,flags)
def wslFallback(+text: String,cwd: String,flags: Environment) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    terminal : Result<&1,&1,U32 & String,String> <- IO.get_env("WT_SESSION")
    sent : Bool <- Bool.pick(Unit -> IO(Bool),present(terminal),_ => emitted(osc52(text)),_ => IO.pure(Bool,False{}))(Unit{})
    Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),sent,_ => IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}}),
      _ => do IO<Result<&2,&2,String,Unit>>:
        copied : Bool <- copyViaWindowsClipboard(text,cwd)
        afterWindows(copied,text,flags))(Unit{})
def afterFailedCommands(+text: String,cwd: String,+flags: Environment) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    wsl : Bool <- isWsl()
    Bool.pick(Unit -> IO(Result<&2,&2,String,Unit>),wsl,_ => wslFallback(text,cwd,flags),_ => terminalFallback(text,flags))(Unit{})
def afterCommands(copied: Bool,text: String,cwd: String,flags: Environment) -> IO(Result<&2,&2,String,Unit>):
  match copied flags:
    case True{} Environment{_,_,_,True{}}: emitIfPossible(osc52(text))
    case True{} _: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case False{} flags: afterFailedCommands(text,cwd,flags)
def copy(+text: String,+cwd: String) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    +flags : Environment <- environment()
    copied : Bool <- attempt(candidates(flags),text,cwd)
    afterCommands(copied,text,cwd,flags)
