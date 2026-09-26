import Base
import ../src/utils/clipboard-image.bend as Clip
import ../src/utils/clipboard-command.bend as Cmd
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/ref.bend as Ref
import ../../runtime/src/filesystem.bend as FS

# pi-mono packages/coding-agent/test/clipboard-image.test.ts and
# clipboard-image-bmp-conversion.test.ts. Upstream mocks the clipboard command
# module and the native helper; here they are the injected Dependencies. A
# scenario scripts the commands and the native helper; each run records the
# commands it was asked for and counts native reads.

def report(+name: String,passed: Bool) -> IO(Unit):
  Bool.pick(IO(Unit),passed,IO.print("PASS " ++ name),IO.print("FAIL " ++ name))

def png() -> List<&2,U32>: [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82]
def bmp() -> List<&2,U32>:
  [66,77,58,0,0,0,0,0,0,0,54,0,0,0,40,0,0,0,1,0,0,0,1,0,0,0,1,0,24,0,0,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,255,0]
def ascii(text: String) -> List<&2,U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c,rest}: Char.to_u32(c) <> ascii(rest)

# The command script: what each command answers.
type Script is Data:
  Refuse{}
  Listing{command: String,present: Bool}
  WaylandBroken{}
  Wsl{tmpFile: Ref.Ref<String>}
  BmpWayland{}
type Var is Data: Var{key: String,value: String}
type Env is Data: Env{pairs: List<&2,Var>}
type Recorder is Data: Recorder{script: Script,calls: Ref.Ref<List<&2,String>>}
type Native is Data: Native{answer: Clip.NativeImage,reads: Ref.Ref<Nat>}

def lookup(pairs: List<&2,Var>,+name: String) -> Maybe<&2,String>:
  match pairs:
    case Nil{}: None{}
    case Var{key,value} <> rest: Bool.pick(Maybe<&2,String>,String.eq(key,name),Some{value},lookup(rest,name))
def envCall(env: Env,name: String) -> IO(Maybe<&2,String>):
  match env: case Env{pairs}: IO.pure(Maybe<&2,String>,lookup(pairs,name))
def has(args: List<&2,String>,+needle: String) -> Bool:
  match args:
    case Nil{}: False{}
    case arg <> rest: String.eq(arg,needle) || has(rest,needle)
def nth(args: List<&2,String>,index: Nat) -> String:
  match args index:
    case Nil{} _: ""
    case arg <> _ 0n: arg
    case _ <> rest 1n+n: nth(rest,n)
def closeAfter(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Bool):
  match pair:
    case (file,result):
      do IO<Bool>:
        closed : Result<&1,&1,U32 & String,Unit> <- File.close_checked(file)
        return Result.is_done(&1,&1,U32 & String,Unit,result)
def writeAll(opened: Result<&1,&1,U32 & String,File>,bytes: List<&2,U32>) -> IO(Bool):
  match opened:
    case Fail{_}: IO.pure(Bool,False{})
    case Done{file}:
      do IO<Bool>:
        pair : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        closeAfter(pair)
def listingAnswer(+present: Bool) -> List<&2,U32>: ascii(Bool.pick(String,present,"text/plain\nimage/png\n","text/plain\n"))
def answer(script: Script,+name: String,+args: List<&2,String>) -> IO(Maybe<&2,List<&2,U32>>):
  match script:
    case Refuse{}: IO.pure(Maybe<&2,List<&2,U32>>,None{})
    case Listing{+command,+present}:
      Bool.pick(IO(Maybe<&2,List<&2,U32>>),String.eq(name,command),
        IO.pure(Maybe<&2,List<&2,U32>>,Some{Bool.pick(List<&2,U32>,has(args,"--list-types") || has(args,"TARGETS"),listingAnswer(present),png())}),
        IO.pure(Maybe<&2,List<&2,U32>>,None{}))
    case WaylandBroken{}:
      Bool.pick(IO(Maybe<&2,List<&2,U32>>),String.eq(name,"wl-paste"),IO.pure(Maybe<&2,List<&2,U32>>,None{}),
        IO.pure(Maybe<&2,List<&2,U32>>,Some{Bool.pick(List<&2,U32>,has(args,"TARGETS"),ascii("image/png\n"),png())}))
    case Wsl{+tmpFile}:
      Bool.pick(Unit -> IO(Maybe<&2,List<&2,U32>>),String.eq(name,"wslpath"),
        _ => do IO<Maybe<&2,List<&2,U32>>>:
          Ref.write(String,tmpFile,nth(args,1n))
          return Some{ascii("C:\\Users\\O'Hare\\clip.png\n")},
        _ => Bool.pick(Unit -> IO(Maybe<&2,List<&2,U32>>),String.eq(name,"powershell.exe"),
          _ => do IO<Maybe<&2,List<&2,U32>>>:
            path : String <- Ref.read(String,tmpFile)
            quoted : Bool <- IO.pure(Bool,String.contains(nth(args,2n),"$path = 'C:\\Users\\O''Hare\\clip.png'"))
            opened : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
            wrote : Bool <- writeAll(opened,png())
            return Bool.pick(Maybe<&2,List<&2,U32>>,quoted && wrote,Some{ascii("ok\n")},None{}),
          _ => IO.pure(Maybe<&2,List<&2,U32>>,None{}))(Unit{}))(Unit{})
    case BmpWayland{}:
      Bool.pick(IO(Maybe<&2,List<&2,U32>>),String.eq(name,"wl-paste") && has(args,"--list-types"),IO.pure(Maybe<&2,List<&2,U32>>,Some{ascii("image/bmp\n")}),
        Bool.pick(IO(Maybe<&2,List<&2,U32>>),String.eq(name,"wl-paste") && has(args,"image/bmp"),IO.pure(Maybe<&2,List<&2,U32>>,Some{bmp()}),IO.pure(Maybe<&2,List<&2,U32>>,None{})))
def dataArgs(args: List<String>) -> List<&2,String>:
  match args:
    case Nil{}: Nil{}
    case arg <> rest: arg <> dataArgs(rest)
def runCall(recorder: Recorder,command: Clip.ClipboardCommand) -> IO(Maybe<&2,List<&2,U32>>):
  match recorder command:
    case Recorder{script,calls} Clip.ClipboardCommand{+name,args,_}:
      do IO<Maybe<&2,List<&2,U32>>>:
        Ref.modify(List<&2,String>,Unit,calls,list => (name <> list,Unit{}))
        answer(script,name,dataArgs(args))
def nativeCall(native: Native,_: Unit) -> IO(Clip.NativeImage):
  match native:
    case Native{answer,reads}:
      do IO<Clip.NativeImage>:
        Ref.modify(Nat,Unit,reads,n => (n + 1n,Unit{}))
        return answer

# One run: the result, the commands asked for (in order) and native reads.
type Outcome is Data: Outcome{result: Result<&2,&2,String,Maybe<&2,Clip.ClipboardImage>>,calls: List<&2,String>,reads: Nat}
def nativeOf(helper: Maybe<&2,Native>) -> IO(Maybe<&2,Clip.NativeClipboard>):
  match helper:
    case None{}: IO.pure(Maybe<&2,Clip.NativeClipboard>,None{})
    case Some{native}:
      do IO<Maybe<&2,Clip.NativeClipboard>>:
        getImage : Callback.Callback<Unit,Clip.NativeImage> <- Callback.create(~Native,~Unit,~Clip.NativeImage,~nativeCall,native)
        return Some{Clip.NativeClipboard{getImage}}
def readsOf(helper: Maybe<&2,Native>) -> IO(Nat):
  match helper:
    case None{}: IO.pure(Nat,0n)
    case Some{Native{_,reads}}: Ref.read(Nat,reads)
def runWith(+platform: String,pairs: List<&2,Var>,script: Script,+helper: Maybe<&2,Native>) -> IO(Outcome):
  do IO<Outcome>:
    +calls : Ref.Ref<List<&2,String>> <- Ref.new(List<&2,String>,Nil{})
    env : Callback.Callback<String,Maybe<&2,String>> <- Callback.create(~Env,~String,~Maybe<&2,String>,~envCall,Env{pairs})
    run : Callback.Callback<Clip.ClipboardCommand,Maybe<&2,List<&2,U32>>> <- Callback.create(~Recorder,~Clip.ClipboardCommand,~Maybe<&2,List<&2,U32>>,~runCall,Recorder{script,calls})
    native : Maybe<&2,Clip.NativeClipboard> <- nativeOf(helper)
    result : Result<&2,&2,String,Maybe<&2,Clip.ClipboardImage>> <- Clip.readClipboardImageWith(Clip.Dependencies{env,run,native},platform)
    asked : List<&2,String> <- Ref.read(List<&2,String>,calls)
    reads : Nat <- readsOf(helper)
    return Outcome{result,List.reverse(&2,String,asked),reads}
def helper(answer: Clip.NativeImage) -> IO(Maybe<&2,Native>):
  do IO<Maybe<&2,Native>>:
    reads : Ref.Ref<Nat> <- Ref.new(Nat,0n)
    return Some{Native{answer,reads}}

def sameBytes(a: List<&2,U32>,b: List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && sameBytes(xs,ys)
    case _ _: False{}
def isPng(outcome: Outcome) -> Bool:
  match outcome:
    case Outcome{Done{Some{Clip.ClipboardImage{bytes,mime}}},_,_}: sameBytes(bytes,png()) && String.eq(mime,"image/png")
    case _: False{}
def isNull(outcome: Outcome) -> Bool:
  match outcome:
    case Outcome{Done{None{}},_,_}: True{}
    case _: False{}
def failedWith(outcome: Outcome,+message: String) -> Bool:
  match outcome:
    case Outcome{Fail{m},_,_}: String.eq(m,message)
    case _: False{}
def pngHeader(outcome: Outcome) -> Bool:
  match outcome:
    case Outcome{Done{Some{Clip.ClipboardImage{137 <> 80 <> 78 <> 71 <> _,mime}}},_,_}: String.eq(mime,"image/png")
    case _: False{}
def callsOf(outcome: Outcome) -> List<&2,String>:
  match outcome: case Outcome{_,calls,_}: calls
def readsIn(outcome: Outcome) -> Nat:
  match outcome: case Outcome{_,_,reads}: reads
def sameNames(a: List<&2,String>,b: List<&2,String>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: String.eq(x,y) && sameNames(xs,ys)
    case _ _: False{}
def repeated(+name: String,n: Nat) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+m: name <> repeated(name,m)

# upstream: `${backend}: command image present=%s stops fallback`
def commandCase(+backend: String,+command: String,pairs: List<&2,Var>,+present: Bool) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(Clip.NativeBytes{png()})
    +outcome : Outcome <- runWith("linux",pairs,Listing{command,present},native)
    report("readClipboardImage > " ++ backend ++ ": command image present=" ++ Bool.pick(String,present,"true","false") ++ " stops fallback",
      Bool.pick(Bool,present,isPng(outcome),isNull(outcome)) && sameNames(callsOf(outcome),repeated(command,Bool.pick(Nat,present,2n,1n))) && Nat.is_eq(readsIn(outcome),0n))
# upstream: "native X11 result %j stops fallback"
def nativeX11(+label: String,answer: Clip.NativeImage,+expectPng: Bool) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(answer)
    +outcome : Outcome <- runWith("linux",[Var{"DISPLAY",":0"}],Refuse{},native)
    report("readClipboardImage > native X11 result " ++ label ++ " stops fallback",
      Bool.pick(Bool,expectPng,isPng(outcome),isNull(outcome)) && Nat.is_eq(readsIn(outcome),1n) && sameNames(callsOf(outcome),repeated("xclip",5n)))
# upstream: "Wayland: falls back to X11 after %s"
def waylandFallback(+failure: String,+missing: Bool) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- Bool.pick(IO(Maybe<&2,Native>),missing,IO.pure(Maybe<&2,Native>,None{}),helper(Clip.NativeUnavailable{}))
    +outcome : Outcome <- runWith("linux",[Var{"WAYLAND_DISPLAY","1"}],WaylandBroken{},native)
    report("readClipboardImage > Wayland: falls back to X11 after " ++ failure,isPng(outcome) && Nat.is_eq(readsIn(outcome),0n))
def wslCase(_: Unit) -> IO(Unit):
  do IO<Unit>:
    +tmpFile : Ref.Ref<String> <- Ref.new(String,"")
    native : Maybe<&2,Native> <- helper(Clip.NativeFailed{"Broken X11 bridge"})
    +outcome : Outcome <- runWith("linux",[Var{"WSL_DISTRO_NAME","Ubuntu"}],Wsl{tmpFile},native)
    report("readClipboardImage > WSL: tries PowerShell before a broken native X11 bridge",isPng(outcome) && Nat.is_eq(readsIn(outcome),0n))
# upstream: `${platform}: reads native image %j once`
def nativePlatform(+platform: String,+label: String,answer: Clip.NativeImage,+expectPng: Bool) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(answer)
    +outcome : Outcome <- runWith(platform,Nil{},Refuse{},native)
    report("readClipboardImage > " ++ platform ++ ": reads native image " ++ label ++ " once",
      Bool.pick(Bool,expectPng,isPng(outcome),isNull(outcome)) && Nat.is_eq(readsIn(outcome),1n) && List.is_empty(&2,String,callsOf(outcome)))
def noHelper(_: Unit) -> IO(Unit):
  do IO<Unit>:
    +outcome : Outcome <- runWith("win32",Nil{},Refuse{},None{})
    report("readClipboardImage > returns null without a native helper",isNull(outcome))
# upstream: "%s: propagates native transfer errors without fallback"
def nativeErrors(+platform: String) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(Clip.NativeFailed{"Native clipboard operation failed"})
    +outcome : Outcome <- runWith(platform,[Var{"WAYLAND_DISPLAY","1"},Var{"DISPLAY",":0"}],Refuse{},native)
    report("readClipboardImage > " ++ platform ++ ": propagates native transfer errors without fallback",
      failedWith(outcome,"Native clipboard operation failed") && sameNames(callsOf(outcome),Bool.pick(List<&2,String>,String.eq(platform,"linux"),"wl-paste" <> repeated("xclip",5n),Nil{})))
def termux(_: Unit) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(Clip.NativeBytes{png()})
    +outcome : Outcome <- runWith("linux",[Var{"TERMUX_VERSION","0.119"}],Refuse{},native)
    report("readClipboardImage > Termux does not read image clipboards",isNull(outcome) && List.is_empty(&2,String,callsOf(outcome)) && Nat.is_eq(readsIn(outcome),0n))
# clipboard-image-bmp-conversion.test.ts
def bmpCase(+platform: String) -> IO(Unit):
  do IO<Unit>:
    native : Maybe<&2,Native> <- helper(Clip.NativeBytes{bmp()})
    +outcome : Outcome <- runWith(platform,[Var{"WAYLAND_DISPLAY","wayland-0"}],BmpWayland{},native)
    report("readClipboardImage BMP conversion > " ++ platform ++ ": converts command/native BMP to PNG",pngHeader(outcome))

def main() -> IO(Unit):
  do IO<Unit>:
    commandCase("wayland","wl-paste",[Var{"WAYLAND_DISPLAY","1"},Var{"DISPLAY",":0"}],True{})
    commandCase("wayland","wl-paste",[Var{"WAYLAND_DISPLAY","1"},Var{"DISPLAY",":0"}],False{})
    commandCase("x11","xclip",[Var{"DISPLAY",":0"}],True{})
    commandCase("x11","xclip",[Var{"DISPLAY",":0"}],False{})
    nativeX11("png",Clip.NativeBytes{png()},True{})
    nativeX11("null",Clip.NativeNone{},False{})
    nativeX11("empty",Clip.NativeBytes{Nil{}},False{})
    waylandFallback("missing module",True{})
    waylandFallback("unavailable display",False{})
    wslCase(Unit{})
    nativePlatform("darwin","png",Clip.NativeBytes{png()},True{})
    nativePlatform("darwin","null",Clip.NativeNone{},False{})
    nativePlatform("darwin","empty",Clip.NativeBytes{Nil{}},False{})
    nativePlatform("darwin","undefined",Clip.NativeUnavailable{},False{})
    nativePlatform("win32","png",Clip.NativeBytes{png()},True{})
    nativePlatform("win32","null",Clip.NativeNone{},False{})
    nativePlatform("win32","empty",Clip.NativeBytes{Nil{}},False{})
    nativePlatform("win32","undefined",Clip.NativeUnavailable{},False{})
    noHelper(Unit{})
    nativeErrors("linux")
    nativeErrors("win32")
    termux(Unit{})
    bmpCase("linux")
    bmpCase("win32")
